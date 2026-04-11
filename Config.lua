-- Shatter – Config
local addonName, ns = ...

local LSM = LibStub("LibSharedMedia-3.0", true)


-- UI Factories

local function CreateSectionHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    return fs
end

local function CreateLabel(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(text)
    return fs
end

local function CreateEditBox(parent, labelText, value, onChange, width)
    local w = width or 260
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(w, 44)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)

    local box = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    box:SetSize(w, 22)
    box:SetPoint("TOPLEFT", 0, -16)
    box:SetAutoFocus(false)
    box:SetText(value or "")
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onChange then onChange(self:GetText()) end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    container.box = box
    return container
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, height or 26)
    button:SetText(text)
    return button
end

local function CreateColorSwatch(parent, labelText, color, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 22)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(100)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(22, 22)
    swatch:SetPoint("LEFT", container, "LEFT", 104, 0)
    swatch:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(1, 1, 1, 1)

    local c = color or { 1, 1, 1, 1 }
    swatch:SetBackdropColor(ns.UnpackColor(c))

    swatch:SetScript("OnClick", function()
        local info = {}
        info.r, info.g, info.b = c[1], c[2], c[3]
        info.opacity = c[4] or 1
        info.hasOpacity = true
        info.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            c[1], c[2], c[3], c[4] = r, g, b, a
            swatch:SetBackdropColor(r, g, b, a)
            if onChange then onChange(c) end
        end
        info.cancelFunc = function(prev)
            c[1], c[2], c[3], c[4] = prev.r, prev.g, prev.b, prev.opacity or 1
            swatch:SetBackdropColor(c[1], c[2], c[3], c[4])
            if onChange then onChange(c) end
        end
        info.opacityFunc = info.swatchFunc
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    container.swatch = swatch
    return container
end

local function CreateDropdown(parent, labelText, options, current, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(260, 44)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)

    local button = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    button:SetSize(260, 24)
    button:SetPoint("TOPLEFT", 0, -16)

    local displayText = current or ""
    if type(options) == "table" then
        for k, v in pairs(options) do
            if k == current then displayText = v; break end
        end
    end
    button:SetText(displayText)

    button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:SetScrollMode(300)
            local sorted = {}
            for k, v in pairs(options) do
                sorted[#sorted + 1] = { key = k, display = v }
            end
            table.sort(sorted, function(a, b) return a.display < b.display end)
            for _, entry in ipairs(sorted) do
                rootDescription:CreateButton(entry.display, function()
                    button:SetText(entry.display)
                    if onChange then onChange(entry.key) end
                end)
            end
        end)
    end)

    container.button = button
    return container
end

local function CreateCheckbox(parent, labelText, checked, onChange)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetChecked(checked)
    checkbox.Text:SetText(labelText)
    checkbox.Text:SetFontObject("GameFontHighlight")
    checkbox:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)
    return checkbox
end


-- Import / Export Popup

local settingsCategoryID = nil
local configContentFrame = nil

local function CreateImportExportPopup()
    local popup = CreateFrame("Frame", "ShatterImportExportPopup", UIParent, "BackdropTemplate")
    popup:SetSize(500, 350)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:EnableMouse(true)
    popup:Hide()

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    popup.title = title

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(440)
    editBox:SetHeight(260)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    scrollFrame:SetScrollChild(editBox)
    popup.editBox = editBox

    local clickCatcher = CreateFrame("Button", nil, scrollFrame)
    clickCatcher:SetAllPoints(scrollFrame)
    clickCatcher:SetScript("OnClick", function() editBox:SetFocus() end)
    clickCatcher:SetFrameLevel(scrollFrame:GetFrameLevel())

    local closeButton = CreateButton(popup, "Close", 80, 26)
    closeButton:SetPoint("BOTTOMRIGHT", -12, 12)
    closeButton:SetScript("OnClick", function() popup:Hide() end)

    popup.statusText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    popup.statusText:SetPoint("BOTTOMLEFT", 12, 18)

    popup.actionBtn = CreateButton(popup, "Import", 80, 26)
    popup.actionBtn:SetPoint("RIGHT", closeButton, "LEFT", -8, 0)
    popup.actionBtn:Hide()

    return popup
end

local importExportPopup = nil

local function GetPopup()
    if not importExportPopup then
        importExportPopup = CreateImportExportPopup()
    end
    return importExportPopup
end

local function ShowExportPopup(profileName)
    local popup = GetPopup()
    popup.title:SetText("Export: " .. profileName)
    popup.statusText:SetText("Ctrl+A to select, then Ctrl+C to copy")
    popup.actionBtn:Hide()

    local encoded, err = ns:ExportProfile(profileName)
    if not encoded then
        popup.editBox:SetText("Export failed: " .. (err or "unknown error"))
    else
        popup.editBox:SetText(encoded)
    end
    popup.editBox:SetScript("OnTextChanged", nil)
    popup:Show()
    popup.editBox:HighlightText()
    popup.editBox:SetFocus()
end

local function ShowImportPopup()
    local popup = GetPopup()
    popup.title:SetText("Import Profile")
    popup.statusText:SetText("Paste a profile string and click Import")
    popup.editBox:SetText("")
    popup.editBox:SetFocus()

    popup.actionBtn:SetText("Import")
    popup.actionBtn:Show()
    popup.actionBtn:SetScript("OnClick", function()
        local text = popup.editBox:GetText():match("^%s*(.-)%s*$")
        if text == "" then
            popup.statusText:SetText("|cFFFF3333Empty string|r")
            return
        end

        StaticPopupDialogs["SHATTER_IMPORT_NAME"] = {
            text = "Name for the imported profile:",
            button1 = "Import",
            button2 = "Cancel",
            hasEditBox = true,
            OnShow = function(self)
                self.EditBox:SetText("Imported")
                self.EditBox:HighlightText()
            end,
            OnAccept = function(self)
                local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
                if name == "" then name = "Imported" end

                local baseName = name
                local idx = 1
                while ShatterDB.profiles[name] do
                    idx = idx + 1
                    name = baseName .. " " .. idx
                end

                local success, err = ns:ImportProfile(text, name)
                if success then
                    popup.statusText:SetText("|cFF00FF00Imported as '" .. name .. "'|r")
                    ns:SwitchProfile(name)
                    C_Timer.After(0.5, function() popup:Hide() end)
                else
                    popup.statusText:SetText("|cFFFF3333" .. (err or "Import failed") .. "|r")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("SHATTER_IMPORT_NAME")
    end)

    popup.editBox:SetScript("OnTextChanged", nil)
    popup:Show()
end


-- Config Section Builders

local function BuildBarSizeSection(parent, db, yOff)
    local sizeHeader = CreateSectionHeader(parent, "Bar Size")
    sizeHeader:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 30

    local widthBox = CreateEditBox(parent, "Width", tostring(db.BarWidth or 200), function(v)
        local n = tonumber(v)
        if n and n >= 10 and n <= 1000 then
            db.BarWidth = math.floor(n)
            ns:Refresh()
        end
    end, 56)
    widthBox:SetPoint("TOPLEFT", 20, yOff)

    local heightBox = CreateEditBox(parent, "Height", tostring(db.BarHeight or 20), function(v)
        local n = tonumber(v)
        if n and n >= 4 and n <= 200 then
            db.BarHeight = math.floor(n)
            ns:Refresh()
        end
    end, 56)
    heightBox:SetPoint("TOPLEFT", 96, yOff)

    local posXBox = CreateEditBox(parent, "X", tostring(db.PosX or 0), function(v)
        local n = tonumber(v)
        if n then
            db.PosX = math.floor(n)
            ns:Refresh()
        end
    end, 56)
    posXBox:SetPoint("TOPLEFT", 172, yOff)

    local posYBox = CreateEditBox(parent, "Y", tostring(db.PosY or 0), function(v)
        local n = tonumber(v)
        if n then
            db.PosY = math.floor(n)
            ns:Refresh()
        end
    end, 56)
    posYBox:SetPoint("TOPLEFT", 248, yOff)

    local scaleBox = CreateEditBox(parent, "Scale", tostring(db.BarScale or 1.0), function(v)
        local n = tonumber(v)
        if n and n >= 0.1 and n <= 5 then
            db.BarScale = n
            ns:Refresh()
        end
    end, 56)
    scaleBox:SetPoint("TOPLEFT", 324, yOff)

    local anchorECV = CreateCheckbox(parent, "Anchor", db.AnchorToECV, function(v)
        db.AnchorToECV = v; ns:Refresh()
    end)
    anchorECV:SetPoint("LEFT", scaleBox, "RIGHT", 10, -8)
    anchorECV:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Anchor to Essentials", 1, 1, 1)
        GameTooltip:Show()
    end)
    anchorECV:SetScript("OnLeave", function() GameTooltip:Hide() end)
    yOff = yOff - 50

    return yOff
end

local function BuildTrackingSection(parent, db, yOff)
    local trackHeader = CreateSectionHeader(parent, "Tracking")
    trackHeader:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 30

    local maxStacksBox = CreateEditBox(parent, "Max Stacks", tostring(db.MaxStacks or 10), function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 20 then
            db.MaxStacks = math.floor(n)
            ns:ApplySettings()
        end
    end, 80)
    maxStacksBox:SetPoint("TOPLEFT", 20, yOff)

    yOff = yOff - 50

    local cdLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdLabel:SetPoint("TOPLEFT", 20, yOff)
    local cdID = db.CooldownID or 0
    if cdID ~= 0 then
        cdLabel:SetTextColor(0.1, 1, 0.1)
        cdLabel:SetText("Found: CooldownID " .. cdID)
    else
        cdLabel:SetTextColor(1, 0.3, 0.3)
        cdLabel:SetText("Not found - press Lock while debuff is active")
    end

    local lockBtn = CreateButton(parent, "Lock", 100, 26)
    lockBtn:SetPoint("LEFT", cdLabel, "RIGHT", 10, 0)
    lockBtn:SetScript("OnClick", function()
        local _, err = ns:DiscoverCooldownID()
        local newID = db.CooldownID or 0
        if newID ~= 0 then
            cdLabel:SetTextColor(0.1, 1, 0.1)
            cdLabel:SetText("Found: CooldownID " .. newID)
            ns:Print("Lock successful — CooldownID " .. newID)
        else
            cdLabel:SetTextColor(1, 0.3, 0.3)
            cdLabel:SetText("Not found - see chat for details")
            ns:Print("Lock failed — " .. (err or "no cooldownID returned"))
        end
    end)
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Lock Hook", 1, 1, 1)
        GameTooltip:AddLine("- Press this when you have Shatter applied to the target to lock the hook", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Make sure you have Shatter tracked in blizzards CDM settings", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Relog if the hook cant find it", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    yOff = yOff - 35

    local highPerf = CreateCheckbox(parent, "High Performance", db.HighPerformance, function(v)
        db.HighPerformance = v
        ns:ApplySettings()
    end)
    highPerf:SetPoint("TOPLEFT", 20, yOff)
    highPerf:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("High Performance Mode", 1, 1, 1)
        GameTooltip:AddLine("Updates the bar every frame using CDM aura refresh events instead of polling every 0.05s. More responsive but uses more CPU.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    highPerf:SetScript("OnLeave", function() GameTooltip:Hide() end)
    yOff = yOff - 30

    return yOff
end

local function BuildColorsSection(parent, db, yOff)
    local colorHeader = CreateSectionHeader(parent, "Colors")
    colorHeader:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 28

    local barColor = CreateColorSwatch(parent, "Bar Color", db.BarColor, function(c)
        db.BarColor = c; ns:Refresh()
    end)
    barColor:SetPoint("TOPLEFT", 20, yOff)

    local bgColor = CreateColorSwatch(parent, "Background", db.BackgroundColor, function(c)
        db.BackgroundColor = c; ns:Refresh()
    end)
    bgColor:SetPoint("TOPLEFT", 260, yOff)
    yOff = yOff - 28

    local borderColor = CreateColorSwatch(parent, "Border Color", db.BorderColor, function(c)
        db.BorderColor = c; ns:Refresh()
    end)
    borderColor:SetPoint("TOPLEFT", 20, yOff)

    local tickColor = CreateColorSwatch(parent, "Tick Color", db.TickColor, function(c)
        db.TickColor = c; ns:Refresh()
    end)
    tickColor:SetPoint("TOPLEFT", 260, yOff)
    yOff = yOff - 28

    local textColor = CreateColorSwatch(parent, "Stack Text", db.TextColor, function(c)
        db.TextColor = c; ns:Refresh()
    end)
    textColor:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 35

    return yOff
end

local function BuildGCDBarSection(parent, db, yOff)
    local header = CreateSectionHeader(parent, "Track Ice lance projectile")
    header:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 28

    local enable = CreateCheckbox(parent, "Projectile Bar", db.GCDBarEnabled, function(v)
        db.GCDBarEnabled = v
        ns:Refresh()
    end)
    enable:SetPoint("TOPLEFT", 20, yOff)
    enable:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Range Bar", 1, 1, 1)
        GameTooltip:AddLine("On Ice Lance cast, runs a status bar whose duration scales with target range: 40y = 1.5s, 0y = 0.2s (linear).", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    enable:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local heightBox = CreateEditBox(parent, "Height", tostring(db.GCDBarHeight or 6), function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 50 then
            db.GCDBarHeight = math.floor(n)
            ns:Refresh()
        end
    end, 56)
    heightBox:SetPoint("TOPLEFT", 180, yOff)

    local gapBox = CreateEditBox(parent, "Gap", tostring(db.GCDBarGap or 2), function(v)
        local n = tonumber(v)
        if n and n >= -50 and n <= 50 then
            db.GCDBarGap = math.floor(n)
            ns:Refresh()
        end
    end, 56)
    gapBox:SetPoint("TOPLEFT", 260, yOff)
    gapBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Gap", 1, 1, 1)
        GameTooltip:AddLine("Positive = above the Shatter bar, negative = below.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    gapBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local reverseFill = CreateCheckbox(parent, "Reverse Fill", db.GCDBarReverseFill, function(v)
        db.GCDBarReverseFill = v
        ns:Refresh()
    end)
    reverseFill:SetPoint("TOPLEFT", 340, yOff - 14)
    yOff = yOff - 32

    local gcdColor = CreateColorSwatch(parent, "Projectile Bar Color", db.GCDBarColor, function(c)
        db.GCDBarColor = c
        ns:Refresh()
    end)
    gcdColor:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 35

    return yOff
end

local function BuildThresholdsAndTicksSection(parent, db, yOff)
    local thresholdHeader = CreateSectionHeader(parent, "Color Thresholds")
    thresholdHeader:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 20

    local threshDesc = CreateLabel(parent, "Bar recolors when stacks cross each threshold")
    threshDesc:SetPoint("TOPLEFT", 20, yOff)
    yOff = yOff - 20

    local threshContainer = CreateFrame("Frame", nil, parent)
    threshContainer:SetPoint("TOPLEFT", 20, yOff)
    threshContainer:SetSize(480, 1)

    local function RebuildThresholds()
        for _, child in pairs({ threshContainer:GetChildren() }) do
            child:Hide(); child:SetParent(nil)
        end

        local thresholds = db.ColorThresholds or {}
        local rowY = 0

        for i, t in ipairs(thresholds) do
            local idx = i
            local row = CreateFrame("Frame", nil, threshContainer)
            row:SetSize(460, 30)
            row:SetPoint("TOPLEFT", 0, rowY)

            local stackLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            stackLabel:SetPoint("TOPLEFT", 0, 0)
            stackLabel:SetText("Stacks >")

            local stackBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            stackBox:SetSize(50, 22)
            stackBox:SetPoint("LEFT", stackLabel, "RIGHT", 8, 0)
            stackBox:SetAutoFocus(false)
            stackBox:SetNumeric(true)
            stackBox:SetText(tostring(t.stacks or 1))
            stackBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                local n = tonumber(self:GetText())
                if n and n >= 1 then
                    db.ColorThresholds[idx].stacks = math.floor(n)
                    table.sort(db.ColorThresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)
                    ns:Refresh()
                end
            end)
            stackBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

            local colorSwatch = CreateColorSwatch(row, "#" .. i, t.color or { 1, 1, 1, 1 }, function(c)
                db.ColorThresholds[idx].color = c
                ns:Refresh()
            end)
            colorSwatch:SetSize(60, 22)
            colorSwatch:SetPoint("LEFT", stackBox, "RIGHT", 8, 0)

            local removeBtn = CreateButton(row, "X", 26, 26)
            removeBtn:SetPoint("LEFT", colorSwatch, "LEFT", 62, 0)
            removeBtn:SetScript("OnClick", function()
                table.remove(db.ColorThresholds, idx)
                RebuildThresholds()
                ns:Refresh()
            end)

            rowY = rowY - 30
        end

        threshContainer:SetHeight(math.max(1, math.abs(rowY)))
    end

    RebuildThresholds()

    local tickHeader = CreateSectionHeader(parent, "Ticks")
    tickHeader:SetPoint("TOPLEFT", 300, yOff)

    local customTickBox = CreateEditBox(parent, "Tick Values (e.g. 5, 10, 15)", db.CustomTickValues or "", function(v)
        db.CustomTickValues = v; ns:Refresh()
    end)
    customTickBox:SetPoint("TOPLEFT", tickHeader, "BOTTOMLEFT", 0, -8)

    local tickWidthBox = CreateEditBox(parent, "Tick Thickness", tostring(db.TickWidth or 1), function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 20 then
            db.TickWidth = math.floor(n)
            ns:Refresh()
        end
    end, 80)
    tickWidthBox:SetPoint("TOPLEFT", customTickBox, "BOTTOMLEFT", 0, -8)

    local addBtn = CreateButton(parent, "+ Add Threshold", 160, 26)
    addBtn:SetPoint("TOPLEFT", threshContainer, "BOTTOMLEFT", 0, -8)
    addBtn:SetScript("OnClick", function()
        db.ColorThresholds = db.ColorThresholds or {}
        local newStacks = (#db.ColorThresholds > 0)
            and ((db.ColorThresholds[#db.ColorThresholds].stacks or 0) + 1)
            or 1
        table.insert(db.ColorThresholds, { stacks = newStacks, color = { 1, 0.5, 0, 1 } })
        table.sort(db.ColorThresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)
        RebuildThresholds()
        ns:Refresh()
    end)

    return yOff, addBtn
end

local function BuildTexturesAndFontsSection(parent, db, addBtn)
    local textureHeader = CreateSectionHeader(parent, "Textures & Fonts")
    textureHeader:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -20)

    local textures = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do textures[name] = name end
    else
        textures["Blizzard"] = "Blizzard"
    end
    local textureDropdown = CreateDropdown(parent, "Bar Texture", textures, db.BarTexture or "Blizzard", function(v)
        db.BarTexture = v; ns:Refresh()
    end)
    textureDropdown:SetPoint("TOPLEFT", textureHeader, "BOTTOMLEFT", 0, -8)

    local fonts = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fonts[name] = name end
    else
        fonts["Friz Quadrata TT"] = "Friz Quadrata TT"
    end
    local fontDropdown = CreateDropdown(parent, "Font Face", fonts, db.FontFace or "Friz Quadrata TT", function(v)
        db.FontFace = v; ns:Refresh()
    end)
    fontDropdown:SetPoint("TOPLEFT", textureDropdown, "TOPRIGHT", 20, 0)

    return textureDropdown
end

local function BuildTextSection(parent, db, textureDropdown)
    local textHeader = CreateSectionHeader(parent, "Text settings")
    textHeader:SetPoint("TOPLEFT", textureDropdown, "BOTTOMLEFT", 0, -20)

    local fontSizeBox = CreateEditBox(parent, "Font Size", tostring(db.FontSize or 20), function(v)
        local n = tonumber(v)
        if n and n >= 6 and n <= 72 then
            db.FontSize = math.floor(n)
            ns:Refresh()
        end
    end, 80)
    fontSizeBox:SetPoint("TOPLEFT", textHeader, "BOTTOMLEFT", 0, -8)

    local textXBox = CreateEditBox(parent, "Text X Offset", tostring(db.TextXOffset or 0), function(v)
        local n = tonumber(v)
        if n then
            db.TextXOffset = n
            ns:Refresh()
        end
    end, 80)
    textXBox:SetPoint("TOPLEFT", fontSizeBox, "TOPRIGHT", 20, 0)

    local textYBox = CreateEditBox(parent, "Text Y Offset", tostring(db.TextYOffset or 0), function(v)
        local n = tonumber(v)
        if n then
            db.TextYOffset = n
            ns:Refresh()
        end
    end, 80)
    textYBox:SetPoint("TOPLEFT", textXBox, "TOPRIGHT", 20, 0)

    local textShadow = CreateCheckbox(parent, "Text Shadow", db.TextShadow, function(v)
        db.TextShadow = v; ns:Refresh()
    end)
    textShadow:SetPoint("TOPLEFT", fontSizeBox, "BOTTOMLEFT", -2, -4)

    local previewBtn = CreateButton(parent, "Toggle Preview", 140, 30)
    previewBtn:SetPoint("TOPLEFT", textShadow, "BOTTOMLEFT", 2, -12)
    previewBtn:SetScript("OnClick", function()
        ns:TogglePreview()
    end)

    return previewBtn
end

local function BuildProfilesSection(parent, previewBtn)
    local profileHeader = CreateSectionHeader(parent, "Profiles")
    profileHeader:SetPoint("TOPLEFT", previewBtn, "BOTTOMLEFT", 0, -20)

    local profileNames = ns:GetProfileNames()
    local profileOptions = {}
    for _, name in ipairs(profileNames) do
        profileOptions[name] = name
    end

    local profileDropdown = CreateDropdown(parent, "Active Profile", profileOptions, ShatterDB.activeProfile, function(name)
        ns:SwitchProfile(name)
    end)
    profileDropdown:SetPoint("TOPLEFT", profileHeader, "BOTTOMLEFT", 0, -8)

    local newBtn = CreateButton(parent, "New", 70, 26)
    newBtn:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 0, -8)
    newBtn:SetScript("OnClick", function()
        StaticPopupDialogs["SHATTER_NEW_PROFILE"] = {
            text = "Enter new profile name:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
                if name ~= "" then
                    if ns:CreateProfile(name) then
                        ns:SwitchProfile(name)
                    else
                        ns:Print("Profile '" .. name .. "' already exists.")
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("SHATTER_NEW_PROFILE")
    end)

    local deleteBtn = CreateButton(parent, "Delete", 70, 26)
    deleteBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
    deleteBtn:SetScript("OnClick", function()
        local current = ShatterDB.activeProfile
        local count = 0
        for _ in pairs(ShatterDB.profiles) do count = count + 1 end
        if count <= 1 then
            ns:Print("Cannot delete the only profile.")
            return
        end
        StaticPopupDialogs["SHATTER_DELETE_PROFILE"] = {
            text = "Delete profile '" .. current .. "'?\nThis will switch to another profile.",
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function()
                local switchTo
                for name in pairs(ShatterDB.profiles) do
                    if name ~= current then switchTo = name; break end
                end
                ns:SwitchProfile(switchTo)
                ShatterDB.profiles[current] = nil
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("SHATTER_DELETE_PROFILE")
    end)

    local renameBtn = CreateButton(parent, "Rename", 80, 26)
    renameBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 8, 0)
    renameBtn:SetScript("OnClick", function()
        StaticPopupDialogs["SHATTER_RENAME_PROFILE"] = {
            text = "Rename '" .. ShatterDB.activeProfile .. "' to:",
            button1 = "Rename",
            button2 = "Cancel",
            hasEditBox = true,
            OnShow = function(self)
                self.EditBox:SetText(ShatterDB.activeProfile)
            end,
            OnAccept = function(self)
                local newName = self.EditBox:GetText():match("^%s*(.-)%s*$")
                if newName ~= "" then
                    if ns:RenameProfile(ShatterDB.activeProfile, newName) then
                        ns:RebuildConfigPanel()
                    else
                        ns:Print("Profile '" .. newName .. "' already exists.")
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("SHATTER_RENAME_PROFILE")
    end)

    local exportBtn = CreateButton(parent, "Export", 70, 26)
    exportBtn:SetPoint("LEFT", renameBtn, "RIGHT", 8, 0)
    exportBtn:SetScript("OnClick", function()
        ShowExportPopup(ShatterDB.activeProfile)
    end)

    local importBtn = CreateButton(parent, "Import", 70, 26)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetScript("OnClick", function()
        ShowImportPopup()
    end)
end


-- Main Config Builder

local function BuildConfigContent(parent)
    local db = ns.db
    local yOff = -10

    yOff = BuildBarSizeSection(parent, db, yOff)
    yOff = BuildTrackingSection(parent, db, yOff)
    yOff = BuildColorsSection(parent, db, yOff)
    yOff = BuildGCDBarSection(parent, db, yOff)
    local addBtn
    yOff, addBtn = BuildThresholdsAndTicksSection(parent, db, yOff)

    -- These sections anchor to the previous section's last element rather than yOff
    local textureDropdown = BuildTexturesAndFontsSection(parent, db, addBtn)
    local previewBtn = BuildTextSection(parent, db, textureDropdown)
    BuildProfilesSection(parent, previewBtn)
end


-- Settings Panel Init

local configScrollFrame = nil

local function InitSettingsPanel()
    local panel = CreateFrame("Frame", "ShatterSettingsPanel")
    panel:Hide()

    configScrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    configScrollFrame:SetPoint("TOPLEFT", 10, -10)
    configScrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    configContentFrame = CreateFrame("Frame", nil, configScrollFrame)
    configContentFrame:SetSize(540, 1200)
    configScrollFrame:SetScrollChild(configContentFrame)

    BuildConfigContent(configContentFrame)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Shatter")
    settingsCategoryID = category.ID
    Settings.RegisterAddOnCategory(category)
end

function ns:OpenConfig()
    if settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    end
end

function ns:RebuildConfigPanel()
    if not configContentFrame then return end
    ns.CleanupFrameList({ configContentFrame:GetChildren() })
    for _, region in pairs({ configContentFrame:GetRegions() }) do
        region:Hide()
        region:SetParent(nil)
    end
    BuildConfigContent(configContentFrame)
end

local configInitFrame = CreateFrame("Frame")
configInitFrame:RegisterEvent("PLAYER_LOGIN")
configInitFrame:SetScript("OnEvent", function(self)
    InitSettingsPanel()
    self:UnregisterAllEvents()
end)
