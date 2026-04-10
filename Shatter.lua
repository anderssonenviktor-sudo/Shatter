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

local function SafeGetApplications(auraData)
    local ok, stacks = pcall(function() return auraData.applications or 0 end)
    return ok and stacks or nil
end

local function IsOurAura(auraData)
    local ok, isOurs = pcall(function()
        return auraData.sourceUnit == "player"
            or auraData.sourceUnit == "pet"
            or auraData.isFromPlayerOrPlayerPet
    end)
    return not ok or isOurs
end

local function SetAllBarsValue(granularBars, thresholdLayers, value, usePcall)
    if usePcall then
        for _, bar in ipairs(granularBars) do pcall(function() bar:SetValue(value) end) end
        if thresholdLayers then
            for _, layer in ipairs(thresholdLayers) do
                for _, bar in ipairs(layer) do pcall(function() bar:SetValue(value) end) end
            end
        end
    else
        for _, bar in ipairs(granularBars) do bar:SetValue(value) end
        if thresholdLayers then
            for _, layer in ipairs(thresholdLayers) do
                for _, bar in ipairs(layer) do bar:SetValue(value) end
            end
        end
    end
end


-- Tracking State

ns.frame = nil
ns.innerContainer = nil
ns.granularBars = {}
ns.stackText = nil
ns.ticksContainer = nil
ns.ticks = {}
ns.trackedInstanceID = nil
ns.currentStacks = 0
ns.cachedCDMFrame = nil
ns.tickerHandle = nil
ns.previewActive = false
ns.previewTimer = nil
ns.enabled = false
ns.onUpdateActive = false


-- Event Dispatch

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

local function RegisterEvent(event)
    eventFrame:RegisterEvent(event)
end

local function UnregisterAllEvents()
    eventFrame:UnregisterAllEvents()
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = eventHandlers[event]
    if handler then handler(...) end
end)


-- Aura Detection


local function HasAuraInstanceID(id)
    if not id then return false end
    local ok, result = pcall(function() return id ~= 0 end)
    if not ok then return true end
    return result
end

local TRACKED_SPELL_NAME
local function GetTrackedSpellName()
    if TRACKED_SPELL_NAME then return TRACKED_SPELL_NAME end
    local info = C_Spell.GetSpellInfo(ns.DEBUFF_SPELL_ID)
    TRACKED_SPELL_NAME = info and info.name
    return TRACKED_SPELL_NAME
end

local function IsTrackedAura(auraData)
    if not auraData then return false end
    local ok, match = pcall(function() return auraData.spellId == ns.DEBUFF_SPELL_ID end)
    if ok and match then return true end
    local name = GetTrackedSpellName()
    if name then
        local okName, nameMatch = pcall(function() return auraData.name == name end)
        if okName and nameMatch then return true end
    end
    return false
end

local function TryReadFromCDMFrame(cdmFrame)
    if not cdmFrame then return false end
    local auraInstanceID = cdmFrame.auraInstanceID
    if not HasAuraInstanceID(auraInstanceID) then return false end
    local unit = cdmFrame.auraDataUnit or "target"
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok and auraData then
        ns.trackedInstanceID = auraInstanceID
        local stacks = SafeGetApplications(auraData)
        if stacks then ns.currentStacks = stacks end
        return true
    end
    return false
end


-- CDM Frame Matching


function ns:CDMFrameMatches(frame, cdmCooldownID)
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
        local ok, match = pcall(function() return spellID == ns.CDM_SPELL_ID end)
        if ok and match then return true end
    end
    return false
end

function ns:FindCDMFrame()
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

function ns:ClearTrackedState()
    self.trackedInstanceID = nil
    self.currentStacks = 0
    
end

function ns:FullScanForTrackedAura()
    self:ClearTrackedState()
    local db = self.db or {}
    local unit = db.TrackUnit or "target"
    if not UnitExists(unit) then return end

    if TryReadFromCDMFrame(self.cachedCDMFrame) then return end

    self.cachedCDMFrame = self:FindCDMFrame()
    if TryReadFromCDMFrame(self.cachedCDMFrame) then return end

    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not auraData then break end
        if IsTrackedAura(auraData) and HasAuraInstanceID(auraData.auraInstanceID) then
            if IsOurAura(auraData) then
                self.trackedInstanceID = auraData.auraInstanceID
                local stacks = SafeGetApplications(auraData)
                if stacks then self.currentStacks = stacks end
                return
            end
        end
    end
end


-- Cooldown Discovery

function ns:DiscoverCooldownID()
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


-- Ticker / Polling

function ns:StartTicker()
    local db = self.db or {}
    if db.HighPerformance then
        self:StartOnUpdate()
        return
    end
    if self.tickerHandle then return end
    self.tickerHandle = C_Timer.NewTicker(0.1, function() self:PollAura() end)
end

function ns:StopTicker()
    if self.tickerHandle then
        self.tickerHandle:Cancel()
        self.tickerHandle = nil
    end
    self:StopOnUpdate()
end

function ns:StartOnUpdate()
    if self.onUpdateActive then return end
    self.onUpdateActive = true
    eventFrame:SetScript("OnUpdate", function() ns:PollAura() end)
end

function ns:StopOnUpdate()
    if not self.onUpdateActive then return end
    self.onUpdateActive = false
    eventFrame:SetScript("OnUpdate", nil)
end

function ns:PollAura()
    if self.previewActive then return end
    local db = self.db or {}
    local unit = db.TrackUnit or "target"

    if not UnitExists(unit) then
        self:StopTicker()
        self:ClearTrackedState()
        self:UpdateBar()
        return
    end

    if not HasAuraInstanceID(self.trackedInstanceID) then
        self:StopTicker()
        self:ClearTrackedState()
        self:UpdateBar()
        return
    end

    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, self.trackedInstanceID)
    if ok and auraData then
        local newStacks = SafeGetApplications(auraData)
        if not newStacks then newStacks = self.currentStacks end
        local okChanged, changed = pcall(function() return newStacks ~= self.currentStacks end)
        if (okChanged and changed) or not okChanged then
            self.currentStacks = newStacks
            self:UpdateBar()
        end
    else
        self.cachedCDMFrame = self:FindCDMFrame()
        if TryReadFromCDMFrame(self.cachedCDMFrame) then
            self:UpdateBar()
        else
            self:ClearTrackedState()
            self:FullScanForTrackedAura()
            self:UpdateBar()
        end
    end
end


-- Bar Update

function ns:UpdateBar()
    if self.previewActive then return end
    if not self.frame then return end
    local db = self.db or {}
    local unit = db.TrackUnit or "target"

    local isTracking = HasAuraInstanceID(self.trackedInstanceID)

    if not isTracking then
        self.currentStacks = 0
        SetAllBarsValue(self.granularBars, self.thresholdLayers, 0, false)
        if db.ShowStackCount then self.stackText:SetText("0") end
        if db.HideWhenInactive then
            self.frame:Hide()
        else
            self.frame:Show()
        end
        if UnitExists(unit) and not self.tickerHandle then
            self:StartTicker()
        elseif not UnitExists(unit) then
            self:StopTicker()
        end
        return
    end

    SetAllBarsValue(self.granularBars, self.thresholdLayers, self.currentStacks, true)
    if db.ShowStackCount then
        local ok = pcall(function() self.stackText:SetText(self.currentStacks) end)
        if not ok then self.stackText:SetText("?") end
    end

    self.frame:Show()
    if not self.tickerHandle then self:StartTicker() end
end


-- Frame Creation

function ns:GetBarTexturePath()
    local db = self.db or {}
    local name = db.BarTexture or "Blizzard"
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("statusbar", name, true)
        if path then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

function ns:CreateFrame()
    if self.frame then return end

    local db = self.db or {}
    local width = db.BarWidth or 200
    local height = db.BarHeight or 20

    local anchorParent = UIParent
    if db.AnchorToECV and _G["EssentialCooldownViewer"] then
        anchorParent = _G["EssentialCooldownViewer"]
    end

    self.frame = CreateFrame("Frame", "ShatterFrame", UIParent)
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
    local tickLevel = 12 + (db.MaxStacks or 10) * (maxThresholds + 2) + 2
    self.ticksContainer:SetFrameLevel(tickLevel)

    local fontPath = ns:GetFont(db.FontFace)
    local outlineFlag = (db.TextOutline == "NONE") and "" or (db.TextOutline or "OUTLINE")
    self.textFrame = CreateFrame("Frame", nil, self.frame)
    self.textFrame:SetAllPoints(self.frame)
    self.textFrame:SetFrameLevel(self.ticksContainer:GetFrameLevel() + 2)
    self.stackText = self.textFrame:CreateFontString(nil, "OVERLAY")
    self.stackText:SetFont(fontPath, db.FontSize or 20, outlineFlag)
    local textColor = db.TextColor or { 1, 1, 1, 1 }
    self.stackText:SetTextColor(ns.UnpackColor(textColor))
    self.stackText:SetText("")
    self:ApplyTextPosition()
    self:ApplyTextShadow()

    self:RebuildGranularBars()

    local hideOnCreate = db.HideWhenInactive
    if hideOnCreate then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end


-- Granular Bars

function ns:CleanupBars()
    ns.CleanupFrameList(self.granularBars)
    self.granularBars = {}

    if self.thresholdLayers then
        for _, layer in ipairs(self.thresholdLayers) do
            ns.CleanupFrameList(layer)
        end
    end
    self.thresholdLayers = {}
end

function ns:CreateBarLayers()
    local db = self.db or {}
    local maxStacks = db.MaxStacks or 10
    local texPath = self:GetBarTexturePath()
    local barColor = db.BarColor or { 0.2, 0.4, 1, 1 }
    local baseLevel = self.innerContainer:GetFrameLevel() + 1
    local thresholds = db.ColorThresholds or {}

    table.sort(thresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)

    for i = 1, maxStacks do
        local bar = CreateFrame("StatusBar", nil, self.innerContainer)
        bar:SetStatusBarTexture(texPath)
        bar:SetFrameLevel(baseLevel + i)
        bar:SetMinMaxValues(i - 1, i)
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

            if i <= thresholdStacks then
                bar:SetMinMaxValues(thresholdStacks, thresholdStacks + 1)
            else
                bar:SetMinMaxValues(i - 1, i)
            end

            bar:Show()
            layer[i] = bar
        end

        self.thresholdLayers[thresholdIdx] = layer
    end
end

function ns:DeferBarPositioning()
    local db = self.db or {}
    local maxStacks = db.MaxStacks or 10

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

function ns:RebuildGranularBars()
    if not self.innerContainer then return end
    self:CleanupBars()
    self:CreateBarLayers()
    self:DeferBarPositioning()
end


-- Visual Settings

function ns:ApplyBorder()
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

function ns:ApplyTextPosition()
    if not self.stackText then return end
    local db = self.db or {}
    local pos = db.TextPosition or "CENTER"
    local anchor = self.textFrame or self.frame
    self.stackText:ClearAllPoints()
    self.stackText:SetPoint(pos, anchor, pos, db.TextXOffset or 0, db.TextYOffset or 0)
end

function ns:ApplyTextShadow()
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

function ns:SetupTicks()
    for _, tick in ipairs(self.ticks) do
        tick:SetParent(nil)
    end
    self.ticks = {}

    local db = self.db or {}
    local raw = db.CustomTickValues or ""
    if raw:match("^%s*$") then return end

    local maxStacks = db.MaxStacks or 10
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

function ns:ApplyVisualSettings()
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
    self.stackText:SetFont(fontPath, db.FontSize or 20, outlineFlag)
    local textColor = db.TextColor or { 1, 1, 1, 1 }
    self.stackText:SetTextColor(ns.UnpackColor(textColor))
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

function ns:Enable()
    if self.enabled then return end
    local db = self.db or {}
    if not db.Enabled then return end

    self.enabled = true

    self.cachedCDMFrame = self:FindCDMFrame()
    self:CreateFrame()
    self:ApplyVisualSettings()

    eventHandlers["UNIT_AURA"] = function(...) ns:UNIT_AURA(...) end
    eventHandlers["PLAYER_TARGET_CHANGED"] = function(...) ns:PLAYER_TARGET_CHANGED(...) end
    eventHandlers["PLAYER_ENTERING_WORLD"] = function(...) ns:PLAYER_ENTERING_WORLD(...) end
    eventHandlers["PLAYER_SPECIALIZATION_CHANGED"] = function(...) ns:PLAYER_SPECIALIZATION_CHANGED(...) end

    RegisterEvent("UNIT_AURA")
    RegisterEvent("PLAYER_TARGET_CHANGED")
    RegisterEvent("PLAYER_ENTERING_WORLD")
    RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    self:FullScanForTrackedAura()
    self:UpdateBar()
end

function ns:Disable()
    self.enabled = false
    self:StopTicker()
    self:ClearTrackedState()
    UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
end


-- Event Handlers

function ns:UNIT_AURA(unit, updateInfo)
    if self.previewActive then return end
    local db = self.db or {}
    if unit ~= (db.TrackUnit or "target") then return end

    if not UnitExists(unit) then
        self:ClearTrackedState()
        self:UpdateBar()
        return
    end

    if not updateInfo or updateInfo.isFullUpdate then
        self:FullScanForTrackedAura()
        self:UpdateBar()
        return
    end

    if updateInfo.removedAuraInstanceIDs and HasAuraInstanceID(self.trackedInstanceID) then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            local ok, match = pcall(function() return id == self.trackedInstanceID end)
            if ok and match then
                self:ClearTrackedState()
                break
            end
        end
    end

    if updateInfo.addedAuras then
        for _, auraData in ipairs(updateInfo.addedAuras) do
            if IsTrackedAura(auraData) and HasAuraInstanceID(auraData.auraInstanceID) then
                if IsOurAura(auraData) then
                    self.trackedInstanceID = auraData.auraInstanceID
                    local stacks = SafeGetApplications(auraData)
                    if stacks then self.currentStacks = stacks end
                end
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs and HasAuraInstanceID(self.trackedInstanceID) then
        for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
            local ok, match = pcall(function() return id == self.trackedInstanceID end)
            if ok and match then
                local okAura, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
                if okAura and auraData then
                    local stacks = SafeGetApplications(auraData)
                    if stacks then self.currentStacks = stacks end
                else
                    self:ClearTrackedState()
                    self:FullScanForTrackedAura()
                end
                break
            end
        end
    end

    if not HasAuraInstanceID(self.trackedInstanceID) then
        self:FullScanForTrackedAura()
    end

    self:UpdateBar()
end

function ns:PLAYER_TARGET_CHANGED()
    if self.previewActive then return end
    self:ClearTrackedState()
    self.cachedCDMFrame = nil
    self:FullScanForTrackedAura()
    self:UpdateBar()
    for _, delay in ipairs({ 0, 0.05, 0.15, 0.3 }) do
        C_Timer.After(delay, function()
            if self.previewActive or not self.enabled then return end
            if not HasAuraInstanceID(self.trackedInstanceID) then
                self:FullScanForTrackedAura()
                self:UpdateBar()
            end
        end)
    end
end

function ns:PLAYER_ENTERING_WORLD()
    self:ClearTrackedState()
    self.cachedCDMFrame = nil
    C_Timer.After(0.5, function()
        if self.enabled and not self.previewActive then
            self:FullScanForTrackedAura()
            self:UpdateBar()
        end
    end)
end

function ns:PLAYER_SPECIALIZATION_CHANGED()
    local specID = PlayerUtil.GetCurrentSpecID()
    if specID == 64 then
        if not self.enabled and self.db and self.db.Enabled then
            self:Enable()
        end
        if not self.previewActive then
            self.cachedCDMFrame = self:FindCDMFrame()
            self:FullScanForTrackedAura()
            self:UpdateBar()
        end
    else
        if self.enabled then
            self:Disable()
        end
    end
end

function ns:ApplySettings()
    local db = self.db or {}
    if db.Enabled then
        if not self.enabled then
            self:Enable()
        else
            -- Restart ticker to pick up HighPerformance changes
            self:StopTicker()
            if HasAuraInstanceID(self.trackedInstanceID) or UnitExists(db.TrackUnit or "target") then
                self:StartTicker()
            end
            self.cachedCDMFrame = self:FindCDMFrame()
            self:CreateFrame()
            self:ApplyVisualSettings()
        end
    else
        if self.enabled then
            self:Disable()
        end
    end
end

function ns:Refresh()
    if self.frame then
        self:ApplyVisualSettings()
    end
end


-- Preview

function ns:ShowPreview()
    self:CreateFrame()
    self:ApplyVisualSettings()

    self.previewActive = true

    local db = self.db or {}
    local maxStacks = db.MaxStacks or 10
    local animVal = 0

    SetAllBarsValue(self.granularBars, self.thresholdLayers, 0, false)
    self.frame:Show()

    if self.previewTimer then self.previewTimer:Cancel() end
    self.previewTimer = C_Timer.NewTicker(0.3, function()
        if not self.previewActive then return end
        animVal = animVal + 1
        if animVal > maxStacks then animVal = 0 end
        SetAllBarsValue(self.granularBars, self.thresholdLayers, animVal, false)
        if db.ShowStackCount then
            self.stackText:SetText(tostring(animVal))
        end
    end)
end

function ns:HidePreview()
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

function ns:TogglePreview()
    if self.previewActive then
        self:HidePreview()
    else
        self:ShowPreview()
    end
end
