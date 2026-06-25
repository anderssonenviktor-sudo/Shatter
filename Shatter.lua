-- Shatter
local addonName, ns = ...


-- Upvalues

local CreateFrame = CreateFrame
local UIParent = UIParent
local pairs = pairs
local ipairs = ipairs
local table = table
local tostring = tostring
local _G = _G
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local math_floor = math.floor
local math_max = math.max


-- Constants

local CDM_VIEWER_NAMES = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
    "CooldownIconCooldownViewer",
    "CooldownBarCooldownViewer",
}


-- Local Helpers

local function PixelSnap(n, effectiveScale)
    local _, h = GetPhysicalScreenSize()
    local s = effectiveScale or UIParent:GetScale()
    if h and h > 0 and s and s > 0 then
        local pmult = (768 / h) / s
        return math_floor(n / pmult + 0.5) * pmult
    end
    return math_floor(n + 0.5)
end

local function SnapFrameToPixels(frame)
    if not frame then return end
    local scale = frame:GetEffectiveScale()
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    if left and bottom then
        local snappedLeft = math_floor(left * scale + 0.5) / scale
        local snappedBottom = math_floor(bottom * scale + 0.5) / scale
        local offsetX = snappedLeft - left
        local offsetY = snappedBottom - bottom
        if offsetX ~= 0 or offsetY ~= 0 then
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
            if point then
                frame:ClearAllPoints()
                frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + offsetX, (y or 0) + offsetY)
            end
        end
    end
end

-- `value` is the plain `applications` stack count. Call SetValue UNPROTECTED
-- (a number). Each segment has a 0.5-wide range so it renders binary: full
-- when value >= i, empty otherwise.
local function SetAllBarsValue(granularBars, thresholdLayers, value)
    for _, bar in ipairs(granularBars) do bar:SetValue(value) end
    if thresholdLayers then
        for _, layer in ipairs(thresholdLayers) do
            for _, bar in ipairs(layer) do bar:SetValue(value) end
        end
    end
end


-- Aura Detection


-- 12.0: an auraInstanceID may be a Secret Value. Comparing it (id ~= 0)
-- taints. Presence is a plain nil-check only, matching ArcUI's IsAuraActive.
local function HasAuraInstanceID(id)
    return id ~= nil
end

-- Stack count, read EXACTLY as ArcUI does (ArcUI_Core.lua durationStacksRef):
--   auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)
--   return auraData.applications
-- For this aura `applications` is a plain readable number (cf. ArcUI_Resources
-- "NON-SECRET: applications ... safe to compare"). It feeds SetValue directly.
-- NOTE: GetAuraApplicationDisplayCount returns a secret *string* for display
-- only and cannot drive a StatusBar (SetValue rejects it) — do not use it here.
local function ReadDisplayCount(cdmFrame, fallbackUnit)
    if not cdmFrame then return nil end
    local auraInstanceID = cdmFrame.auraInstanceID
    if not HasAuraInstanceID(auraInstanceID) then return nil end
    -- The CDM frame knows its own unit; fall back to the bar's TrackUnit
    -- (e.g. "player" for self-buffs like Salvo) rather than always "target".
    local unit = cdmFrame.auraDataUnit or fallbackUnit or "target"
    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if auraData then
        return auraInstanceID, auraData.applications or 0
    end
    return nil
end


-- =====================================================================
-- Bar prototype
-- =====================================================================
-- Each tracked aura (Shatter / SalvoBar) is one Bar instance. All bar state
-- and rendering lives on the instance; spec/spell-specific data lives in
-- self.cfg. A single shared eventFrame fans runtime events out to every
-- enabled bar (see Event Dispatch below).

local Bar = {}
Bar.__index = Bar

function Bar.New(cfg)
    local self = setmetatable({}, Bar)
    self.cfg = cfg
    self.db = nil
    self.frame = nil
    self.innerContainer = nil
    self.granularBars = {}
    self.thresholdLayers = {}
    self.stackText = nil
    self.ticksContainer = nil
    self.ticks = {}
    self.trackedInstanceID = nil
    self.currentStacks = 0
    self.cachedCDMFrame = nil
    self.previewActive = false
    self.previewTimer = nil
    self.enabled = false
    self.hookedCDMFrames = {}
    self.borderTextures = nil
    self.effectiveMaxStacks = cfg.baseStacks or 20
    return self
end

-- Effective max stacks. For talent-driven bars (cfg.autoMaxStacks) this follows
-- the Sunfury talent; otherwise it is the configured db.MaxStacks.
function Bar:GetMaxStacks()
    if self.cfg.autoMaxStacks then
        return self.effectiveMaxStacks or self.cfg.baseStacks or 20
    end
    local db = self.db or {}
    return db.MaxStacks or 20
end

-- Recompute effectiveMaxStacks from the Sunfury talent. Returns true if it
-- changed. Talent detection via C_Traits over the active config; guarded so a
-- missing/uniterable config never errors.
function Bar:RefreshMaxStacks()
    if not self.cfg.autoMaxStacks then return false end
    local base = self.cfg.baseStacks or 20
    local talented = self.cfg.talentStacks or base
    local newMax = base

    local talentID = self.cfg.talentID
    if talentID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID and C_Traits then
            -- Scan the spec tree for an active node whose entry grants talentID.
            local found = false
            local cfgInfo = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
            if cfgInfo and cfgInfo.treeIDs then
                for _, treeID in ipairs(cfgInfo.treeIDs) do
                    local nodes = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
                    if nodes then
                        for _, nodeID in ipairs(nodes) do
                            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                            if nodeInfo and nodeInfo.activeRank and nodeInfo.activeRank > 0
                               and nodeInfo.entryIDs then
                                for _, entryID in ipairs(nodeInfo.entryIDs) do
                                    -- talentID may be supplied as the entry's
                                    -- definitionID OR the granted spellID; match
                                    -- either, since the Midnight trait API is
                                    -- still iterating on which is canonical.
                                    local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                                    if entryInfo and entryInfo.definitionID then
                                        if entryInfo.definitionID == talentID then
                                            found = true
                                            break
                                        end
                                        local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                                        if defInfo and defInfo.spellID == talentID then
                                            found = true
                                            break
                                        end
                                    end
                                end
                            end
                            if found then break end
                        end
                    end
                    if found then break end
                end
            end
            if found then newMax = talented end
        end
    end

    if newMax ~= self.effectiveMaxStacks then
        self.effectiveMaxStacks = newMax
        return true
    end
    return false
end


-- CDM Frame Matching

function Bar:CDMFrameMatches(frame, cdmCooldownID)
    local cdID = frame.cooldownID
    if not cdID and frame.cooldownInfo then
        cdID = frame.cooldownInfo.cooldownID
    end
    if cdID and cdmCooldownID then
        local ok, match = pcall(function() return cdID == cdmCooldownID end)
        if ok and match then return true end
    end
    local spellID = frame.spellID or (frame.cooldownInfo and frame.cooldownInfo.spellID)
    if spellID then
        local ok, match = pcall(function() return spellID == self.cfg.spellID end)
        if ok and match then return true end
    end
    return false
end

function Bar:FindCDMFrame()
    local db = self.db or {}
    local cdmCooldownID = db.CooldownID and db.CooldownID ~= 0 and db.CooldownID

    for _, viewerName in ipairs(CDM_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            if viewer.itemFramePool then
                for frame in viewer.itemFramePool:EnumerateActive() do
                    if self:CDMFrameMatches(frame, cdmCooldownID) then
                        return frame
                    end
                end
            end
            for _, frame in ipairs({viewer:GetChildren()}) do
                if self:CDMFrameMatches(frame, cdmCooldownID) then
                    return frame
                end
            end
        end
    end
    return nil
end

function Bar:ClearTrackedState()
    self.trackedInstanceID = nil
    self.currentStacks = 0
end

function Bar:TryReadFromCDMFrame(cdmFrame)
    local auraInstanceID, count = ReadDisplayCount(cdmFrame, self.db and self.db.TrackUnit)
    if not auraInstanceID then return false end
    self.trackedInstanceID = auraInstanceID
    self.currentStacks = count   -- plain applications count; drives SetValue
    return true
end

function Bar:SweepActiveCDMFrames()
    self:ClearTrackedState()
    self.cachedCDMFrame = self:FindCDMFrame()
    if self:TryReadFromCDMFrame(self.cachedCDMFrame) then return true end
    return false
end


-- CDM Frame Hooks

-- Single CDM-driven update path. Reads the secret-safe display count off the
-- frame and pushes it to the bars. Every hook routes through here.
function Bar:OnCDMFrameUpdate(frame)
    if not self.enabled or self.previewActive then return end
    if not self:CDMFrameMatches(frame, (self.db and self.db.CooldownID ~= 0) and self.db.CooldownID or nil) then return end

    self.cachedCDMFrame = frame
    if not HasAuraInstanceID(frame.auraInstanceID) then
        self:ClearTrackedState()
        self:UpdateBar()
        return
    end

    local auraInstanceID, count = ReadDisplayCount(frame, self.db and self.db.TrackUnit)
    if auraInstanceID then
        self.trackedInstanceID = auraInstanceID
        self.currentStacks = count   -- plain applications count
    else
        self:ClearTrackedState()
    end
    self:UpdateBar()
end

function Bar:OnCDMFrameHidden(frame)
    if not self.enabled or self.previewActive then return end
    if not self:CDMFrameMatches(frame, (self.db and self.db.CooldownID ~= 0) and self.db.CooldownID or nil) then return end
    self:ClearTrackedState()
    self:UpdateBar()
end

function Bar:HookCDMFrame(frame)
    if not frame or self.hookedCDMFrames[frame] then return end
    self.hookedCDMFrames[frame] = true

    -- 12.0 (ArcUI_AuraFrames.lua): drive updates entirely off the CDM frame.
    --   OnAuraInstanceInfoSet/Cleared → aura gained / lost
    --   OnUnitAuraUpdatedEvent        → stacks change on the SAME instance
    --                                    (the case missed by gain/loss alone)
    --   OnNewTarget                   → target swap (target-unit debuffs)
    if frame.OnAuraInstanceInfoSet then
        hooksecurefunc(frame, "OnAuraInstanceInfoSet", function(f) self:OnCDMFrameUpdate(f) end)
    end
    if frame.OnAuraInstanceInfoCleared then
        hooksecurefunc(frame, "OnAuraInstanceInfoCleared", function(f) self:OnCDMFrameUpdate(f) end)
    end
    if frame.OnUnitAuraUpdatedEvent then
        hooksecurefunc(frame, "OnUnitAuraUpdatedEvent", function(f) self:OnCDMFrameUpdate(f) end)
    end
    if frame.OnNewTarget then
        hooksecurefunc(frame, "OnNewTarget", function(f) self:OnCDMFrameUpdate(f) end)
    end
    frame:HookScript("OnShow", function(f) self:OnCDMFrameUpdate(f) end)
    frame:HookScript("OnHide", function(f) self:OnCDMFrameHidden(f) end)
end

function Bar:HookAllCDMFrames()
    for _, viewerName in ipairs(CDM_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            -- The viewer-level RefreshLayout rehook must re-hook for every
            -- enabled bar, so route it through the shared dispatcher.
            if not viewer.__shatterViewerHooked then
                viewer.__shatterViewerHooked = true
                if viewer.RefreshLayout then
                    hooksecurefunc(viewer, "RefreshLayout", function() ns:HookAllBars() end)
                end
            end
            if viewer.itemFramePool then
                for frame in viewer.itemFramePool:EnumerateActive() do
                    self:HookCDMFrame(frame)
                end
            end
            for _, frame in ipairs({viewer:GetChildren()}) do
                self:HookCDMFrame(frame)
            end
        end
    end
end


-- Cooldown Discovery

function Bar:DiscoverCooldownID()
    local db = self.db or {}
    local frame = self:FindCDMFrame()
    if not frame then
        return nil, "No CDM frame found — is the spell tracked in Cooldown Manager?"
    end
    local cdID = frame.cooldownID
    if not cdID and frame.cooldownInfo then
        cdID = frame.cooldownInfo.cooldownID
    end
    if cdID then
        db.CooldownID = cdID
        return cdID
    end
    return nil, "CDM frame found but no cooldownID"
end


-- Bar Update

function Bar:UpdateBar()
    if self.previewActive then return end
    if not self.frame then return end
    local db = self.db or {}

    local isTracking = HasAuraInstanceID(self.trackedInstanceID)

    if not isTracking then
        self.currentStacks = 0
        SetAllBarsValue(self.granularBars, self.thresholdLayers, 0)
        if db.ShowStackCount then self.stackText:SetText("0") end
        if db.HideWhenInactive and not UnitAffectingCombat("player") then
            self.frame:Hide()
        else
            self.frame:Show()
        end
        return
    end

    SetAllBarsValue(self.granularBars, self.thresholdLayers, self.currentStacks)
    if db.ShowStackCount then
        -- Unprotected, like ArcUI (_arcSingleStackText:SetText(count)).
        self.stackText:SetText(self.currentStacks)
    end

    self.frame:Show()
end


-- Frame Creation

function Bar:GetBarTexturePath()
    local db = self.db or {}
    local name = db.BarTexture or "Blizzard"
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("statusbar", name, true)
        if path then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

function Bar:CreateFrame()
    if self.frame then return end

    local db = self.db or {}
    local width = db.BarWidth or 200
    local height = db.BarHeight or 20

    local anchorParent = UIParent
    if db.AnchorToECV and _G["EssentialCooldownViewer"] then
        anchorParent = _G["EssentialCooldownViewer"]
    end

    self.frame = CreateFrame("Frame", self.cfg.frameName, UIParent)
    self.frame:SetSize(PixelSnap(width), PixelSnap(height))
    self.frame:SetFrameStrata("MEDIUM")
    self.frame:SetFrameLevel(10)
    self.frame:SetPoint("CENTER", anchorParent, "CENTER", db.PosX or 0, db.PosY or 0)
    C_Timer.After(0, function()
        SnapFrameToPixels(self.frame)
    end)

    self:ApplyBorder()

    local borderInset = PixelSnap(1, self.frame:GetEffectiveScale())
    self.innerContainer = CreateFrame("Frame", nil, self.frame)
    self.innerContainer:SetPoint("TOPLEFT", borderInset, -borderInset)
    self.innerContainer:SetPoint("BOTTOMRIGHT", -borderInset, borderInset)
    self.innerContainer:SetClipsChildren(true)

    self.innerContainer.bg = self.innerContainer:CreateTexture(nil, "BACKGROUND")
    self.innerContainer.bg:SetAllPoints()
    local bgColor = db.BackgroundColor or { 0.1, 0.1, 0.1, 0.8 }
    self.innerContainer.bg:SetColorTexture(ns.UnpackColor(bgColor, 0.8))
    self.innerContainer.bg:SetSnapToPixelGrid(false)
    self.innerContainer.bg:SetTexelSnappingBias(0)

    self.ticksContainer = CreateFrame("Frame", nil, self.innerContainer)
    self.ticksContainer:SetAllPoints(self.innerContainer)
    local maxThresholds = 10
    local tickLevel = 12 + self:GetMaxStacks() * (maxThresholds + 2) + 2
    self.ticksContainer:SetFrameLevel(tickLevel)

    local fontPath = ns:GetFont(db.FontFace)
    local outlineFlag = (db.TextOutline == "NONE") and "" or (db.TextOutline or "OUTLINE")
    self.textFrame = CreateFrame("Frame", nil, self.frame)
    self.textFrame:SetAllPoints(self.frame)
    self.textFrame:SetFrameLevel(self.ticksContainer:GetFrameLevel() + 2)
    self.stackText = self.textFrame:CreateFontString(nil, "OVERLAY")
    local fontSize = db.FontSize or 20
    if fontSize > 0 then
        self.stackText:SetFont(fontPath, fontSize, outlineFlag)
        local textColor = db.TextColor or { 1, 1, 1, 1 }
        self.stackText:SetTextColor(ns.UnpackColor(textColor))
        self.stackText:Show()
    else
        self.stackText:SetFont(fontPath, 1, outlineFlag)
        self.stackText:Hide()
    end
    self.stackText:SetText("")
    self:ApplyTextPosition()
    self:ApplyTextShadow()

    self:RebuildGranularBars()

    local hideOnCreate = db.HideWhenInactive and not UnitAffectingCombat("player")
    if hideOnCreate then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

-- Granular Bars

function Bar:CleanupBars()
    ns.CleanupFrameList(self.granularBars)
    self.granularBars = {}

    if self.thresholdLayers then
        for _, layer in ipairs(self.thresholdLayers) do
            ns.CleanupFrameList(layer)
        end
    end
    self.thresholdLayers = {}
end

function Bar:CreateBarLayers()
    local db = self.db or {}
    local maxStacks = self:GetMaxStacks()
    local texPath = self:GetBarTexturePath()
    local barColor = db.BarColor or { 0.2, 0.4, 1, 1 }
    local baseLevel = self.innerContainer:GetFrameLevel() + 1
    local thresholds = db.ColorThresholds or {}

    table.sort(thresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)

    for i = 1, maxStacks do
        local bar = CreateFrame("StatusBar", nil, self.innerContainer)
        bar:SetStatusBarTexture(texPath)
        bar:SetFrameLevel(baseLevel + i)
        -- 0.5-wide range (ArcUI CreateChargeSlot pattern) makes each segment a
        -- binary fill: SetValue(secretStacks) renders full when stacks >= i,
        -- empty otherwise. A 1.0-wide (i-1, i) range asks the engine to PARTIAL
        -- fill from a Secret Value, which silently fails -> bar never fills.
        bar:SetMinMaxValues(i - 0.5, i)
        bar:SetValue(0)
        bar:SetStatusBarColor(ns.UnpackColor(barColor))
        local barTex = bar:GetStatusBarTexture()
        if barTex then
            barTex:SetSnapToPixelGrid(false)
            barTex:SetTexelSnappingBias(0)
        end
        bar:Show()
        self.granularBars[i] = bar
    end

    for thresholdIdx, threshold in ipairs(thresholds) do
        local thresholdStacks = threshold.stacks or 0
        local thresholdColor = threshold.color or barColor
        local layer = {}
        local layerLevel = baseLevel + maxStacks + (thresholdIdx * maxStacks)

        for i = 1, maxStacks do
            local bar = CreateFrame("StatusBar", nil, self.innerContainer)
            bar:SetStatusBarTexture(texPath)
            bar:SetFrameLevel(layerLevel + i)
            bar:SetValue(0)
            bar:SetStatusBarColor(ns.UnpackColor(thresholdColor))
            local barTex = bar:GetStatusBarTexture()
            if barTex then
                barTex:SetSnapToPixelGrid(false)
                barTex:SetTexelSnappingBias(0)
            end

            -- Binary 0.5-wide segments (see CreateBarLayers note above). A
            -- threshold layer's segment i only renders once the count has
            -- reached this threshold, so gate it at max(i, thresholdStacks).
            local fillAt = (i <= thresholdStacks) and thresholdStacks or i
            bar:SetMinMaxValues(fillAt - 0.5, fillAt)

            bar:Show()
            layer[i] = bar
        end

        self.thresholdLayers[thresholdIdx] = layer
    end
end

function Bar:DeferBarPositioning()
    local maxStacks = self:GetMaxStacks()

    C_Timer.After(0, function()
        if not self.innerContainer then return end
        local totalWidth = self.innerContainer:GetWidth()
        if totalWidth == 0 then return end

        local barScale = self.innerContainer:GetEffectiveScale()

        local prevRight = 0
        for i = 1, #self.granularBars do
            local bar = self.granularBars[i]
            local snappedRight = PixelSnap((i / maxStacks) * totalWidth, barScale)
            local w = math_max(2, snappedRight - prevRight)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", self.innerContainer, "TOPLEFT", prevRight, 0)
            bar:SetPoint("BOTTOM", self.innerContainer, "BOTTOM", 0, 0)
            bar:SetWidth(w)
            prevRight = snappedRight
        end

        for _, layer in ipairs(self.thresholdLayers) do
            prevRight = 0
            for i = 1, #layer do
                local bar = layer[i]
                local snappedRight = PixelSnap((i / maxStacks) * totalWidth, barScale)
                local w = math_max(2, snappedRight - prevRight)
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", self.innerContainer, "TOPLEFT", prevRight, 0)
                bar:SetPoint("BOTTOM", self.innerContainer, "BOTTOM", 0, 0)
                bar:SetWidth(w)
                prevRight = snappedRight
            end
        end
    end)
end

function Bar:RebuildGranularBars()
    if not self.innerContainer then return end
    self:CleanupBars()
    self:CreateBarLayers()
    self:DeferBarPositioning()
end


-- Visual Settings

function Bar:ApplyBorder()
    if not self.frame then return end
    local db = self.db or {}
    local borderColor = db.BorderColor or { 1, 1, 1, 1 }
    local show = db.ShowBorder

    if not self.borderTextures then
        local onePx = PixelSnap(1, self.frame:GetEffectiveScale())

        local function CreateBorderTex(frame)
            local tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(ns.UnpackColor(borderColor))
            tex:SetTexelSnappingBias(0)
            tex:SetSnapToPixelGrid(false)
            return tex
        end

        local top = CreateBorderTex(self.frame)
        top:SetHeight(onePx)
        top:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)

        local bottom = CreateBorderTex(self.frame)
        bottom:SetHeight(onePx)
        bottom:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)

        local left = CreateBorderTex(self.frame)
        left:SetWidth(onePx)
        left:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)

        local right = CreateBorderTex(self.frame)
        right:SetWidth(onePx)
        right:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)

        self.borderTextures = { top = top, bottom = bottom, left = left, right = right }
    end

    for _, tex in pairs(self.borderTextures) do
        tex:SetColorTexture(ns.UnpackColor(borderColor))
        if show then tex:Show() else tex:Hide() end
    end
end

function Bar:ApplyTextPosition()
    if not self.stackText then return end
    local db = self.db or {}
    local pos = db.TextPosition or "CENTER"
    local anchor = self.textFrame or self.frame
    self.stackText:ClearAllPoints()
    self.stackText:SetPoint(pos, anchor, pos, db.TextXOffset or 0, db.TextYOffset or 0)
end

function Bar:ApplyTextShadow()
    if not self.stackText then return end
    local db = self.db or {}
    if db.TextShadow then
        self.stackText:SetShadowOffset(1, -1)
        self.stackText:SetShadowColor(0, 0, 0, 1)
    else
        self.stackText:SetShadowOffset(0, 0)
    end
end


-- Tick Marks

function Bar:SetupTicks()
    for _, tick in ipairs(self.ticks) do
        tick:SetParent(nil)
    end
    self.ticks = {}

    local db = self.db or {}
    local raw = db.CustomTickValues or ""
    if raw:match("^%s*$") then return end

    local maxStacks = self:GetMaxStacks()
    if maxStacks < 2 then return end

    local tickWidth = db.TickWidth or 1
    if tickWidth <= 0 then return end

    local innerWidth = self.innerContainer:GetWidth()
    local innerHeight = self.innerContainer:GetHeight()
    if innerWidth == 0 then return end

    local tickColor = db.TickColor or { 0, 0, 0, 1 }
    local positions = {}

    for part in raw:gmatch("[^,]+") do
        local n = tonumber(part:match("^%s*(.-)%s*$"))
        if n and n >= 1 and n < maxStacks then
            positions[#positions + 1] = n
        end
    end

    for _, stackVal in ipairs(positions) do
        local xPos = (stackVal / maxStacks) * innerWidth
        local tick = self.ticksContainer:CreateTexture(nil, "OVERLAY")
        tick:SetColorTexture(ns.UnpackColor(tickColor))
        tick:SetSize(tickWidth, innerHeight)
        tick:SetPoint("CENTER", self.ticksContainer, "LEFT", xPos, 0)
        tick:SetTexelSnappingBias(0)
        tick:SetSnapToPixelGrid(false)
        table.insert(self.ticks, tick)
    end
end

function Bar:ApplyVisualSettings()
    if not self.frame then return end
    local db = self.db or {}

    local width = db.BarWidth or 200
    local height = db.BarHeight or 20

    self.frame:SetSize(PixelSnap(width), PixelSnap(height))
    self.frame:SetScale(db.BarScale or 1.0)
    local anchorParent = UIParent
    if db.AnchorToECV and _G["EssentialCooldownViewer"] then
        anchorParent = _G["EssentialCooldownViewer"]
    end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", anchorParent, "CENTER", db.PosX or 0, db.PosY or 0)
    C_Timer.After(0, function()
        SnapFrameToPixels(self.frame)
    end)
    self:ApplyBorder()

    local borderInset = PixelSnap(1, self.frame:GetEffectiveScale())
    self.innerContainer:ClearAllPoints()
    self.innerContainer:SetPoint("TOPLEFT", borderInset, -borderInset)
    self.innerContainer:SetPoint("BOTTOMRIGHT", -borderInset, borderInset)

    local bgColor = db.BackgroundColor or { 0.1, 0.1, 0.1, 0.8 }
    self.innerContainer.bg:SetColorTexture(ns.UnpackColor(bgColor, 0.8))

    local fontPath = ns:GetFont(db.FontFace)
    local outlineFlag = (db.TextOutline == "NONE") and "" or (db.TextOutline or "OUTLINE")
    local fontSize = db.FontSize or 20
    if fontSize > 0 then
        self.stackText:SetFont(fontPath, fontSize, outlineFlag)
        local textColor = db.TextColor or { 1, 1, 1, 1 }
        self.stackText:SetTextColor(ns.UnpackColor(textColor))
        self.stackText:Show()
    else
        self.stackText:SetFont(fontPath, 1, outlineFlag)
        self.stackText:Hide()
    end
    self:ApplyTextPosition()
    self:ApplyTextShadow()

    C_Timer.After(0, function()
        if not self.frame then return end
        self:RebuildGranularBars()
        self:SetupTicks()
        self:UpdateBar()
    end)
end


-- Enable / Disable

function Bar:Enable()
    if self.enabled then return end
    local db = self.db or {}
    if not db.Enabled then return end

    self.enabled = true

    self:RefreshMaxStacks()
    self:CreateFrame()
    self:ApplyVisualSettings()

    self:HookAllCDMFrames()
    self:SweepActiveCDMFrames()

    ns:EnsureEventsRegistered()

    self:UpdateBar()
end

function Bar:Disable()
    self.enabled = false
    self:ClearTrackedState()
    if self.frame then self.frame:Hide() end
    ns:UpdateEventRegistration()
end


-- Per-bar runtime event responses (called by the shared dispatcher)

function Bar:OnTargetChanged()
    if self.previewActive then return end
    self:HookAllCDMFrames()
    self:SweepActiveCDMFrames()
    self:UpdateBar()
end

function Bar:OnEnteringWorld()
    self:ClearTrackedState()
    self.cachedCDMFrame = nil
    C_Timer.After(0.5, function()
        if self.enabled and not self.previewActive then
            self:HookAllCDMFrames()
            self:SweepActiveCDMFrames()
            self:UpdateBar()
        end
    end)
end

function Bar:OnSpecOrTalentChanged()
    local specID = PlayerUtil.GetCurrentSpecID()
    if specID == self.cfg.specID then
        if not self.enabled and self.db and self.db.Enabled then
            self:Enable()
        end
        if self.enabled and not self.previewActive then
            if self:RefreshMaxStacks() then
                self:RebuildGranularBars()
                self:SetupTicks()
            end
            self:HookAllCDMFrames()
            self:SweepActiveCDMFrames()
            self:UpdateBar()
        end
    else
        if self.enabled then
            self:Disable()
        end
    end
end

function Bar:ApplySettings()
    local db = self.db or {}
    if db.Enabled then
        if not self.enabled then
            self:Enable()
        else
            self:HookAllCDMFrames()
            self:SweepActiveCDMFrames()
            self:CreateFrame()
            self:ApplyVisualSettings()
        end
    else
        if self.enabled then
            self:Disable()
        end
    end
end

function Bar:Refresh()
    if self.frame then
        self:ApplyVisualSettings()
    end
end


-- Preview

function Bar:ShowPreview()
    self:CreateFrame()
    self:ApplyVisualSettings()

    self.previewActive = true

    local db = self.db or {}
    local maxStacks = self:GetMaxStacks()
    local animVal = 0

    SetAllBarsValue(self.granularBars, self.thresholdLayers, 0)
    self.frame:Show()

    if self.previewTimer then self.previewTimer:Cancel() end
    self.previewTimer = C_Timer.NewTicker(0.3, function()
        if not self.previewActive then return end
        animVal = animVal + 1
        if animVal > maxStacks then animVal = 0 end
        SetAllBarsValue(self.granularBars, self.thresholdLayers, animVal)
        if db.ShowStackCount then
            self.stackText:SetText(tostring(animVal))
        end
    end)
end

function Bar:HidePreview()
    self.previewActive = false
    if self.previewTimer then
        self.previewTimer:Cancel()
        self.previewTimer = nil
    end
    if self.frame then
        if self.enabled then
            self:UpdateBar()
        else
            self.frame:Hide()
        end
    end
end

function Bar:TogglePreview()
    if self.previewActive then
        self:HidePreview()
    else
        self:ShowPreview()
    end
end


-- =====================================================================
-- Bar registry + shared event dispatch
-- =====================================================================

ns.bars = ns.bars or {}
ns.barsByKey = ns.barsByKey or {}

function ns:RegisterBar(cfg)
    local bar = Bar.New(cfg)
    self.bars[#self.bars + 1] = bar
    self.barsByKey[cfg.key] = bar
    -- If the profile is already loaded, wire up the bar's db immediately.
    if self.db and self.db.bars then
        bar.db = self.db.bars[cfg.key]
    end
    return bar
end

-- Re-point every bar's db at the active profile (called on load / switch).
function ns:RebindBarDBs()
    if not self.db or not self.db.bars then return end
    for _, bar in ipairs(self.bars) do
        bar.db = self.db.bars[bar.cfg.key]
    end
end

-- Rehook CDM frames for every enabled bar (RefreshLayout fan-out).
function ns:HookAllBars()
    for _, bar in ipairs(self.bars) do
        if bar.enabled and not bar.previewActive then
            bar:HookAllCDMFrames()
        end
    end
end

-- Enable/disable each bar according to the player's current spec.
function ns:UpdateBarsForSpec()
    for _, bar in ipairs(self.bars) do
        bar:OnSpecOrTalentChanged()
    end
end

-- Shared event frame. Runtime events fan out to every enabled bar; the trait
-- event only matters to talent-driven bars.
local eventFrame = CreateFrame("Frame")
local registered = false

local function ForEachEnabled(method, ...)
    for _, bar in ipairs(ns.bars) do
        if bar.enabled then
            bar[method](bar, ...)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        ForEachEnabled("OnTargetChanged")
    elseif event == "PLAYER_ENTERING_WORLD" then
        ForEachEnabled("OnEnteringWorld")
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        ForEachEnabled("UpdateBar")
    elseif event == "TRAIT_CONFIG_UPDATED" then
        for _, bar in ipairs(ns.bars) do
            if bar.enabled and bar.cfg.autoMaxStacks and not bar.previewActive then
                if bar:RefreshMaxStacks() then
                    bar:RebuildGranularBars()
                    bar:SetupTicks()
                    bar:UpdateBar()
                end
            end
        end
    end
end)

-- Register the shared events once, as soon as any bar is enabled.
function ns:EnsureEventsRegistered()
    if registered then return end
    registered = true
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end

-- If no bar is enabled anymore, drop the shared registration.
function ns:UpdateEventRegistration()
    if not registered then return end
    for _, bar in ipairs(self.bars) do
        if bar.enabled then return end
    end
    registered = false
    eventFrame:UnregisterAllEvents()
end

-- Called by Core on PLAYER_SPECIALIZATION_CHANGED.
function ns:PLAYER_SPECIALIZATION_CHANGED()
    self:UpdateBarsForSpec()
end


-- =====================================================================
-- Bar registration
-- =====================================================================

ns:RegisterBar({
    key       = "shatter",
    title     = "Shatter",
    subtitle  = "Freezing stack tracker for Frost Mage",
    specID    = 64,
    spellID   = 1246769,
    frameName = "ShatterFrame",
})

ns:RegisterBar({
    key          = "salvo",
    title        = "SalvoBar",
    subtitle     = "Salvo stack tracker for Arcane Mage",
    specID       = 62,
    spellID      = 384452,
    frameName    = "SalvoBarFrame",
    talentID     = 1260616,   -- Sunfury (raises stack max)
    baseStacks   = 20,
    talentStacks = 25,
    autoMaxStacks = true,
    dbDefaults   = {
        BarColor  = { 0.6, 0.3, 0.95, 1 },   -- arcane purple
        TrackUnit = "player",                -- Salvo is a self-buff
    },
})
