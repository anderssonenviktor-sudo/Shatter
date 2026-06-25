-- Shatter – Core
local addonName, ns = ...

-- Constants
ns.ADDON_NAME = "Shatter"
ns.ADDON_COLOR = "|cFFFFE000"
ns.VERSION = "1.0.0"
ns.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
-- Per-bar settings template. Each registered bar gets its own copy under
-- profile.bars[barKey]. Per-bar overrides come from ns.barsByKey[key].cfg.dbDefaults.
local DEFAULTS = {
    Enabled = true,
    CooldownID = 0,
    TrackUnit = "target",
    MaxStacks = 20,
    BarWidth = 200,
    BarHeight = 20,
    BarScale = 1.0,
    PosX = 0,
    PosY = 0,
    BarTexture = "Solid",
    BarColor = { 0.2, 0.4, 1, 1 },
    BackgroundColor = { 0.1, 0.1, 0.1, 0.8 },
    ColorThresholds = {},
    ShowBorder = true,
    BorderColor = { 0, 0, 0, 1 },
    CustomTickValues = "",
    TickWidth = 1,
    TickColor = { 0, 0, 0, 1 },
    ShowStackCount = true,
    FontFace = "Friz Quadrata TT",
    FontSize = 20,
    TextColor = { 1, 1, 1, 1 },
    TextOutline = "OUTLINE",
    TextShadow = false,
    TextPosition = "CENTER",
    TextXOffset = 0,
    TextYOffset = 0,
    HideWhenInactive = false,
    AnchorToECV = false,
}

-- Keys that used to live on the flat profile and are no longer valid.
local LEGACY_DEFAULT_KEYS = {
    HighPerformance = true,
}

-- Settings keys belonging to a bar (everything in DEFAULTS). Used to migrate
-- the pre-SalvoBar flat profile into profile.bars.shatter.
local BAR_SETTING_KEYS = {}
for k in pairs(DEFAULTS) do BAR_SETTING_KEYS[k] = true end


-- Utilities

function ns:Print(msg)
    print(ns.ADDON_COLOR .. "Shatter|r " .. tostring(msg))
end

function ns:DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = self:DeepCopy(v)
    end
    return copy
end

-- Fill one bar's settings table from DEFAULTS, then apply the bar's per-bar
-- default overrides (cfg.dbDefaults), preserving any value the user already set.
function ns:ApplyBarDefaults(barSettings, cfg)
    for k in pairs(LEGACY_DEFAULT_KEYS) do
        barSettings[k] = nil
    end
    for k, v in pairs(DEFAULTS) do
        if barSettings[k] == nil then
            if type(v) == "table" then
                barSettings[k] = self:DeepCopy(v)
            else
                barSettings[k] = v
            end
        end
    end
    if cfg and cfg.dbDefaults then
        for k, v in pairs(cfg.dbDefaults) do
            if barSettings[k] == nil then
                if type(v) == "table" then
                    barSettings[k] = self:DeepCopy(v)
                else
                    barSettings[k] = v
                end
            end
        end
    end

    -- TrackUnit has no UI; the bar's configured unit is authoritative. Force it
    -- so a profile saved before SalvoBar's "player" default gets corrected
    -- (otherwise a stale "target" would silently break self-buff tracking).
    if cfg and cfg.dbDefaults and cfg.dbDefaults.TrackUnit then
        barSettings.TrackUnit = cfg.dbDefaults.TrackUnit
    end
end

-- Visual settings copied by "Copy from Shatter". Deliberately excludes
-- bar identity (Enabled/CooldownID/TrackUnit/MaxStacks), tick marks
-- (CustomTickValues/TickWidth/TickColor) and ColorThresholds.
local COPYABLE_VISUAL_KEYS = {
    "BarWidth", "BarHeight", "BarScale", "PosX", "PosY", "AnchorToECV",
    "HideWhenInactive",
    "BarTexture", "BarColor", "BackgroundColor", "ShowBorder", "BorderColor",
    "FontFace", "FontSize", "TextOutline", "TextColor", "TextShadow",
    "ShowStackCount", "TextPosition", "TextXOffset", "TextYOffset",
}

-- Copy the visual settings (see COPYABLE_VISUAL_KEYS) from one bar's settings
-- into another's. Tables are deep-copied so the bars stay independent.
function ns:CopyVisualSettings(fromKey, toKey)
    local profile = self.db
    if not profile or not profile.bars then return false end
    local src = profile.bars[fromKey]
    local dst = profile.bars[toKey]
    if not src or not dst then return false end
    for _, k in ipairs(COPYABLE_VISUAL_KEYS) do
        local v = src[k]
        if type(v) == "table" then
            dst[k] = self:DeepCopy(v)
        else
            dst[k] = v
        end
    end
    return true
end

-- One-time migration: a pre-SalvoBar profile stored bar settings flat on the
-- profile. Move them into profile.bars.shatter, then drop the flat keys.
local function MigrateFlatProfile(profile)
    if profile.bars then return end
    local shatter = {}
    for k in pairs(BAR_SETTING_KEYS) do
        if profile[k] ~= nil then
            shatter[k] = profile[k]
            profile[k] = nil
        end
    end
    profile.bars = { shatter = shatter }
end

-- Ensure profile.bars exists and every registered bar has a defaulted settings
-- table. Re-points ns.bars instances at their settings.
function ns:ApplyDefaults(profile)
    for k in pairs(LEGACY_DEFAULT_KEYS) do
        profile[k] = nil
    end
    MigrateFlatProfile(profile)
    profile.bars = profile.bars or {}

    for _, bar in ipairs(self.bars or {}) do
        local key = bar.cfg.key
        profile.bars[key] = profile.bars[key] or {}
        self:ApplyBarDefaults(profile.bars[key], bar.cfg)
    end
end

function ns:GetFont(name)
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM and name then
        local path = LSM:Fetch("font", name, true)
        if path then return path end
    end
    return ns.DEFAULT_FONT
end

function ns.UnpackColor(color, fallbackAlpha)
    return color[1], color[2], color[3], color[4] or (fallbackAlpha or 1)
end

function ns.CleanupFrameList(list)
    for _, frame in ipairs(list) do
        frame:Hide()
        frame:SetParent(nil)
    end
end


-- Initialization

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if not ShatterDB or not ShatterDB.profiles then
            local old = ShatterDB or {}
            old.profiles = nil
            old.activeProfile = nil
            ShatterDB = {
                profiles = { ["Default"] = old },
                activeProfile = "Default",
            }
        end

        local profileName = ShatterDB.activeProfile or "Default"
        if not ShatterDB.profiles[profileName] then
            profileName = "Default"
            ShatterDB.activeProfile = profileName
            if not ShatterDB.profiles[profileName] then
                ShatterDB.profiles[profileName] = {}
            end
        end

        local profile = ShatterDB.profiles[profileName]
        ns:ApplyDefaults(profile)
        ns.db = profile
        ns:RebindBarDBs()

    elseif event == "PLAYER_LOGIN" then
        SLASH_SHATTER1 = "/shatter"
        SlashCmdList["SHATTER"] = function()
            ns:OpenConfig()
        end

        -- Enable whichever bar matches the current spec.
        ns:UpdateBarsForSpec()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and ns.PLAYER_SPECIALIZATION_CHANGED then
        ns:PLAYER_SPECIALIZATION_CHANGED()
    end
end)


-- Profile Management

function ns:GetProfileNames()
    local names = {}
    for name in pairs(ShatterDB.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function ns:SwitchProfile(name)
    if not ShatterDB.profiles[name] then return end
    ShatterDB.activeProfile = name
    local profile = ShatterDB.profiles[name]
    self:ApplyDefaults(profile)
    self.db = profile

    -- Disable every bar, re-point each at the new profile, then re-enable per spec.
    for _, bar in ipairs(self.bars) do
        if bar.enabled then bar:Disable() end
    end
    self:RebindBarDBs()
    self:UpdateBarsForSpec()

    if self.RebuildConfigPanel then
        self:RebuildConfigPanel()
    end
end

function ns:CreateProfile(name, copyFrom)
    if ShatterDB.profiles[name] then return false end
    if copyFrom and ShatterDB.profiles[copyFrom] then
        ShatterDB.profiles[name] = self:DeepCopy(ShatterDB.profiles[copyFrom])
    else
        local profile = {}
        self:ApplyDefaults(profile)
        ShatterDB.profiles[name] = profile
    end
    return true
end

function ns:RenameProfile(oldName, newName)
    if not ShatterDB.profiles[oldName] then return false end
    if ShatterDB.profiles[newName] then return false end
    ShatterDB.profiles[newName] = ShatterDB.profiles[oldName]
    ShatterDB.profiles[oldName] = nil
    if ShatterDB.activeProfile == oldName then
        ShatterDB.activeProfile = newName
    end
    return true
end
