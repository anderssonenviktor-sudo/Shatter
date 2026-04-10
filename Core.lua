-- Shatter – Core
local addonName, ns = ...

-- Constants
ns.ADDON_NAME = "Shatter"
ns.ADDON_COLOR = "|cFFFFE000"
ns.VERSION = "1.0.0"
ns.DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
ns.DEBUFF_SPELL_ID = 1221389
ns.CDM_SPELL_ID = 1246769

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
    BarTexture = "Blizzard",
    BarColor = { 0.2, 0.4, 1, 1 },
    BackgroundColor = { 0.1, 0.1, 0.1, 0.8 },
    ColorThresholds = {},
    ShowBorder = true,
    BorderColor = { 0, 0, 0, 0 },
    CustomTickValues = "",
    TickWidth = 1,
    TickColor = { 0, 0, 0, 0 },
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
    HighPerformance = false,
}


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

function ns:ApplyDefaults(profile)
    for k, v in pairs(DEFAULTS) do
        if profile[k] == nil then
            if type(v) == "table" then
                profile[k] = self:DeepCopy(v)
            else
                profile[k] = v
            end
        end
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

    elseif event == "PLAYER_LOGIN" then
        SLASH_SHATTER1 = "/shatter"
        SlashCmdList["SHATTER"] = function()
            ns:OpenConfig()
        end

        local specID = PlayerUtil.GetCurrentSpecID()
        if specID == 64 and ns.db and ns.db.Enabled then
            ns:Enable()
        end
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
    if self.enabled then
        self:Disable()
    end
    local specID = PlayerUtil.GetCurrentSpecID()
    if specID == 64 and self.db.Enabled then
        self:Enable()
    end
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
