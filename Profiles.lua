-- Shatter – Profiles
local addonName, ns = ...


-- Libraries

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local EXPORT_PREFIX = "SHATTER"
local EXPORT_VERSION = 1


-- Export / Import

function ns:ExportProfile(profileName)
    profileName = profileName or ShatterDB.activeProfile
    local profile = ShatterDB.profiles[profileName]
    if not profile then return nil, "Profile not found" end

    local exportData = {
        prefix  = EXPORT_PREFIX,
        version = EXPORT_VERSION,
        profile = self:DeepCopy(profile),
    }

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized then return nil, "Serialization failed" end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then return nil, "Compression failed" end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then return nil, "Encoding failed" end

    return encoded
end

function ns:ImportProfile(encodedString, profileName)
    if not encodedString or encodedString == "" then
        return false, "Empty import string"
    end

    local decoded = LibDeflate:DecodeForPrint(encodedString)
    if not decoded then return false, "Invalid string (decode failed)" end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, "Decompression failed" end

    local success, data = AceSerializer:Deserialize(decompressed)
    if not success then return false, "Deserialization failed" end

    if type(data) ~= "table" or data.prefix ~= EXPORT_PREFIX then
        return false, "Not a Shatter profile string"
    end

    if type(data.profile) ~= "table" then
        return false, "Profile data missing"
    end

    local profile = data.profile
    self:ApplyDefaults(profile)

    ShatterDB.profiles[profileName] = profile
    return true
end
