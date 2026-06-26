-- Shatter – Config
local addonName, ns = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-------- Theme --------

local THEME = {
    cardBg      = { 0.06, 0.06, 0.07, 0.6 },
    cardBorder  = { 0.20, 0.20, 0.22, 1 },
    headerText  = { 0.92, 0.92, 0.94 },
    rowH        = 30,
    pad         = 14,
    colGap      = 22,
    rowGap      = 12,
    label       = { 0.82, 0.83, 0.86 },
    sublabel    = { 0.52, 0.53, 0.58 },
    btnBg       = { 0.12, 0.12, 0.14, 1 },
    btnBgHover  = { 0.16, 0.17, 0.20, 1 },
    btnBgDown   = { 0.09, 0.09, 0.11, 1 },
    btnBorder   = { 0.28, 0.28, 0.31, 1 },
    btnBorderHi = { 0.35, 0.55, 0.85, 1 },
    btnText     = { 0.86, 0.87, 0.90 },
    btnTextHi   = { 1, 1, 1 },
    btnTextDis  = { 0.45, 0.45, 0.48 },
}

local function Tex(parent, layer)
    return parent:CreateTexture(nil, layer or "BACKGROUND")
end

local function CreateCard(parent, titleText)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    card:SetBackdropColor(THEME.cardBg[1], THEME.cardBg[2], THEME.cardBg[3], THEME.cardBg[4])
    card:SetBackdropBorderColor(THEME.cardBorder[1], THEME.cardBorder[2], THEME.cardBorder[3], THEME.cardBorder[4])

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(titleText)
    title:SetTextColor(THEME.headerText[1], THEME.headerText[2], THEME.headerText[3])
    card.title = title

    local sep = Tex(card, "ARTWORK")
    sep:SetColorTexture(THEME.cardBorder[1], THEME.cardBorder[2], THEME.cardBorder[3], 1)
    sep:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sep:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    sep:SetHeight(1)

    card.content = CreateFrame("Frame", nil, card)
    card.content:SetPoint("TOPLEFT", 14, -44)
    card.content:SetPoint("RIGHT", -14, 0)
    card.content:SetHeight(1)

    return card
end

-------- Widget factories --------

local function CreateLabel(parent, text, sub)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(text)
    fs:SetTextColor(sub and THEME.sublabel[1] or THEME.label[1],
                    sub and THEME.sublabel[2] or THEME.label[2],
                    sub and THEME.sublabel[3] or THEME.label[3])
    return fs
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 100, height or 24)
    button:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    button:SetFontString(label)

    local function Paint()
        if not button:IsEnabled() then
            button:SetBackdropColor(unpack(THEME.btnBg))
            button:SetBackdropBorderColor(unpack(THEME.btnBorder))
            label:SetTextColor(unpack(THEME.btnTextDis))
            return
        end
        if button.__down then
            button:SetBackdropColor(unpack(THEME.btnBgDown))
        elseif button.__over then
            button:SetBackdropColor(unpack(THEME.btnBgHover))
        else
            button:SetBackdropColor(unpack(THEME.btnBg))
        end
        button:SetBackdropBorderColor(unpack(button.__over and THEME.btnBorderHi or THEME.btnBorder))
        label:SetTextColor(unpack(button.__over and THEME.btnTextHi or THEME.btnText))
    end

    button:HookScript("OnEnter", function(self) self.__over = true; Paint() end)
    button:HookScript("OnLeave", function(self) self.__over = false; Paint() end)
    button:HookScript("OnMouseDown", function(self) self.__down = true; Paint() end)
    button:HookScript("OnMouseUp", function(self) self.__down = false; Paint() end)
    button:HookScript("OnEnable", Paint)
    button:HookScript("OnDisable", Paint)
    button:HookScript("OnShow", Paint)
    Paint()

    return button
end

-- Slider with click-to-edit inline value. Click the number to type a value.
-- Returns container (height rowH+16).
local function CreateSlider(parent, labelText, value, minV, maxV, step, onChange, fmt)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(THEME.rowH + 16)

    local label = CreateLabel(container, labelText)
    label:SetPoint("TOPLEFT", 0, 0)

    local fmtVal = fmt or function(v) return tostring(v) end

    -- Snap a raw value to the step grid and clamp to range.
    local function Snap(v)
        v = math.floor(v / step + 0.5) * step
        if v < minV then v = minV elseif v > maxV then v = maxV end
        return v
    end

    -- Displayed value text (also the click target).
    local valFS = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valFS:SetPoint("TOPRIGHT", 0, 0)
    valFS:SetTextColor(THEME.headerText[1], THEME.headerText[2], THEME.headerText[3])
    valFS:SetText(fmtVal(value))

    -- Edit box, shown over the value text on click. Hidden by default.
    local edit = CreateFrame("EditBox", nil, container)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetJustifyH("RIGHT")
    edit:SetSize(60, 16)
    edit:SetPoint("TOPRIGHT", 0, 0)
    edit:Hide()

    -- Click-to-edit hotspot covering the value text.
    local hit = CreateFrame("Button", nil, container)
    hit:SetPoint("TOPRIGHT", 0, 0)
    hit:SetSize(60, 16)

    local slider = CreateFrame("Slider", nil, container, "MinimalSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetPoint("TOPRIGHT", 0, -18)
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(Snap(value or minV))

    local applying = false
    slider:SetScript("OnValueChanged", function(_, v)
        v = Snap(v)
        valFS:SetText(fmtVal(v))
        if not applying and onChange then onChange(v) end
    end)

    local function CommitEdit()
        local n = tonumber(edit:GetText())
        edit:Hide()
        valFS:Show()
        hit:Show()
        if n then
            slider:SetValue(Snap(n))   -- drives OnValueChanged -> onChange
        end
    end

    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self)
        self:Hide(); valFS:Show(); hit:Show(); self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", CommitEdit)

    hit:SetScript("OnClick", function()
        local _, v = pcall(function() return slider:GetValue() end)
        edit:SetText(fmtVal(Snap(v or minV)))
        valFS:Hide()
        hit:Hide()
        edit:Show()
        edit:SetFocus()
        edit:HighlightText()
    end)

    container.slider = slider
    container.SetValueSilent = function(_, v)
        applying = true
        slider:SetValue(Snap(v))
        valFS:SetText(fmtVal(Snap(v)))
        applying = false
    end
    return container
end

local function CreateEditBox(parent, labelText, value, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(THEME.rowH + 16)

    local label = CreateLabel(container, labelText)
    label:SetPoint("TOPLEFT", 0, 0)

    local box = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    box:SetHeight(22)
    box:SetPoint("TOPLEFT", 4, -18)
    box:SetPoint("TOPRIGHT", 0, -18)
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

local function CreateColorSwatch(parent, labelText, color, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(THEME.rowH)

    local label = CreateLabel(container, labelText)
    label:SetPoint("LEFT", 0, 0)

    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(24, 24)
    swatch:SetPoint("RIGHT", 0, 0)
    swatch:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)

    -- Checkerboard backdrop so transparency in the color is visible.
    local checker = swatch:CreateTexture(nil, "BACKGROUND")
    checker:SetAllPoints(swatch)
    checker:SetColorTexture(0.2, 0.2, 0.2, 1)

    -- Fill texture showing the actual color (drawn above the checker).
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(swatch)

    local c = color or { 1, 1, 1, 1 }
    fill:SetColorTexture(ns.UnpackColor(c))

    swatch:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.7, 0.7, 0.72, 1) end)
    swatch:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)

    swatch:SetScript("OnClick", function()
        local info = {}
        info.r, info.g, info.b = c[1], c[2], c[3]
        info.opacity = c[4] or 1
        info.hasOpacity = true
        info.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            c[1], c[2], c[3], c[4] = r, g, b, a
            fill:SetColorTexture(r, g, b, a)
            if onChange then onChange(c) end
        end
        info.cancelFunc = function(prev)
            c[1], c[2], c[3], c[4] = prev.r, prev.g, prev.b, prev.opacity or 1
            fill:SetColorTexture(c[1], c[2], c[3], c[4])
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
    container:SetHeight(THEME.rowH + 16)

    local label = CreateLabel(container, labelText)
    label:SetPoint("TOPLEFT", 0, 0)

    local button = CreateButton(container, "", 100, 24)
    button:SetPoint("TOPLEFT", 0, -18)
    button:SetPoint("TOPRIGHT", 0, -18)

    local fs = button:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -20, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)

    local function DisplayFor(key)
        if type(options) == "table" then
            for k, v in pairs(options) do
                if k == key then return v end
            end
        end
        return key or ""
    end
    button:SetText(DisplayFor(current))

    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetRotation(math.pi)

    local function Generator(_, rootDescription)
        rootDescription:SetScrollMode(320)
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
    end

    button:SetScript("OnClick", function(self)
        -- Re-anchor the menu below the button (CreateContextMenu opens at cursor).
        local menu = MenuUtil.CreateContextMenu(self, Generator)
        if menu then
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        end
    end)

    container.button = button
    return container
end

local function CreateCheckbox(parent, labelText, checked, onChange, tooltip)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(THEME.rowH)

    local checkbox = CreateFrame("CheckButton", nil, container, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("LEFT", -2, 0)
    checkbox:SetChecked(checked)
    checkbox.Text:SetText(labelText)
    checkbox.Text:SetFontObject("GameFontHighlightSmall")
    checkbox.Text:SetTextColor(unpack(THEME.label))
    checkbox:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)
    if tooltip then
        checkbox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltip[1], 1, 1, 1)
            if tooltip[2] then GameTooltip:AddLine(tooltip[2], 1, 0.82, 0, true) end
            GameTooltip:Show()
        end)
        checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    container.checkbox = checkbox
    return container
end

-------- Layout helper --------

local function GridLayout(content, items, columns, totalW)
    columns = columns or 2
    local gap = THEME.colGap
    if not totalW or totalW < 1 then totalW = content:GetWidth() end
    if not totalW or totalW < 1 then totalW = 480 end
    local colW = (totalW - gap * (columns - 1)) / columns

    local y = 0
    local colInRow = 0
    local rowMaxH = 0

    local function endRow()
        if colInRow > 0 then
            y = y - rowMaxH - THEME.rowGap
        end
        colInRow = 0
        rowMaxH = 0
    end

    for _, item in ipairs(items) do
        local span = item.span or 1
        if span > columns then span = columns end

        if colInRow > 0 and (colInRow + span) > columns then
            endRow()
        end

        local w = item.frame
        local widthForSpan = colW * span + gap * (span - 1)
        local x = colInRow * (colW + gap)

        w:SetParent(content)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        w:SetWidth(widthForSpan)

        local h = w:GetHeight()
        if h > rowMaxH then rowMaxH = h end
        colInRow = colInRow + span

        if colInRow >= columns then
            endRow()
        end
    end
    endRow()

    content:SetHeight(math.abs(y) + 2)
    return math.abs(y)
end

-------- Import / Export popup --------

local settingsCategoryID = nil
-- One panel record per bar: { bar = <Bar>, content = <Frame>, includeProfiles = bool }.
local barPanels = {}

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

-------- Cards --------

local function BuildLayoutCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Bar Size & Position")
    local c = card.content
    local items = {}

    items[#items+1] = { frame = CreateSlider(c, "Width", db.BarWidth or 200, 10, 1000, 1, function(v)
        db.BarWidth = v; bar:Refresh() end) }
    items[#items+1] = { frame = CreateSlider(c, "Height", db.BarHeight or 20, 4, 200, 1, function(v)
        db.BarHeight = v; bar:Refresh() end) }
    items[#items+1] = { frame = CreateSlider(c, "Scale", db.BarScale or 1.0, 0.1, 5, 0.05, function(v)
        db.BarScale = v; bar:Refresh() end, function(v) return string.format("%.2f", v) end) }
    -- Talent-driven bars (SalvoBar) compute max stacks automatically, so no slider.
    if not bar.cfg.autoMaxStacks then
        items[#items+1] = { frame = CreateSlider(c, "Max Stacks", db.MaxStacks or 20, 1, 20, 1, function(v)
            db.MaxStacks = v; bar:ApplySettings() end) }
    end
    items[#items+1] = { frame = CreateSlider(c, "X Offset", db.PosX or 0, -800, 800, 1, function(v)
        db.PosX = v; bar:Refresh() end) }
    items[#items+1] = { frame = CreateSlider(c, "Y Offset", db.PosY or 0, -800, 800, 1, function(v)
        db.PosY = v; bar:Refresh() end) }

    items[#items+1] = { frame = CreateCheckbox(c, "Anchor to Essentials", db.AnchorToECV, function(v)
        db.AnchorToECV = v; bar:Refresh() end,
        { "Anchor to Essentials" }), span = 1 }
    items[#items+1] = { frame = CreateCheckbox(c, "Hide When Inactive", db.HideWhenInactive, function(v)
        db.HideWhenInactive = v; bar:Refresh() end,
        { "Hide When Inactive", "Hide the bar out of combat when the aura is not on the tracked target. Always shown while in combat." }), span = 1 }

    card.Relayout = function(w) GridLayout(c, items, 2, w) end
    card.Relayout()
    return card
end

-- Tracking card has the dynamic CooldownID lock UI; build its own layout.
local function BuildTrackingCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Tracking")
    local c = card.content

    local cdLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdLabel:SetPoint("TOPLEFT", 0, 0)

    local function RefreshCDLabel()
        local cdID = db.CooldownID or 0
        if cdID ~= 0 then
            cdLabel:SetTextColor(0.1, 1, 0.1)
            cdLabel:SetText("Found: CooldownID " .. cdID)
        else
            cdLabel:SetTextColor(1, 0.3, 0.3)
            cdLabel:SetText("Not found - press Lock while debuff is active")
        end
    end
    RefreshCDLabel()

    local lockBtn = CreateButton(c, "Lock", 100, 24)
    lockBtn:SetPoint("LEFT", cdLabel, "RIGHT", 10, 0)
    lockBtn:SetScript("OnClick", function()
        local _, err = bar:DiscoverCooldownID()
        local newID = db.CooldownID or 0
        RefreshCDLabel()
        if newID ~= 0 then
            ns:Print("Lock successful — CooldownID " .. newID)
        else
            cdLabel:SetText("Not found - see chat for details")
            ns:Print("Lock failed — " .. (err or "no cooldownID returned"))
        end
    end)
    local auraName = bar.cfg.title
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Lock Hook", 1, 1, 1)
        GameTooltip:AddLine("- Press this when you have " .. auraName .. " applied to the target to lock the hook", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Make sure you have " .. auraName .. " tracked in blizzards CDM settings", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Relog if the hook cant find it", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card.Relayout = function(w)
        c:SetHeight(THEME.rowH)
    end
    card.Relayout()
    return card
end

local function BuildColorsCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Colors & Border")
    local c = card.content
    local items = {}

    items[#items+1] = { frame = CreateColorSwatch(c, "Bar Color", db.BarColor, function(col)
        db.BarColor = col; bar:Refresh() end) }
    items[#items+1] = { frame = CreateColorSwatch(c, "Background", db.BackgroundColor, function(col)
        db.BackgroundColor = col; bar:Refresh() end) }
    items[#items+1] = { frame = CreateColorSwatch(c, "Border Color", db.BorderColor, function(col)
        db.BorderColor = col; bar:Refresh() end) }
    items[#items+1] = { frame = CreateCheckbox(c, "Show Border", db.ShowBorder, function(v)
        db.ShowBorder = v; bar:Refresh() end) }

    card.Relayout = function(w) GridLayout(c, items, 2, w) end
    card.Relayout()
    return card
end

local function BuildTextureCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Texture & Font")
    local c = card.content
    local items = {}

    local textures = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do textures[name] = name end
    else
        textures["Blizzard"] = "Blizzard"
    end
    items[#items+1] = { frame = CreateDropdown(c, "Bar Texture", textures, db.BarTexture or "Blizzard", function(v)
        db.BarTexture = v; bar:Refresh() end) }

    local fonts = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fonts[name] = name end
    else
        fonts["Friz Quadrata TT"] = "Friz Quadrata TT"
    end
    items[#items+1] = { frame = CreateDropdown(c, "Font Face", fonts, db.FontFace or "Friz Quadrata TT", function(v)
        db.FontFace = v; bar:Refresh() end) }

    local outlines = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" }
    items[#items+1] = { frame = CreateDropdown(c, "Outline", outlines, db.TextOutline or "OUTLINE", function(v)
        db.TextOutline = v; bar:Refresh() end) }
    items[#items+1] = { frame = CreateSlider(c, "Font Size", db.FontSize or 20, 0, 60, 1, function(v)
        db.FontSize = v; bar:Refresh() end) }

    card.Relayout = function(w) GridLayout(c, items, 2, w) end
    card.Relayout()
    return card
end

local function BuildStackTextCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Stack Text")
    local c = card.content
    local items = {}

    items[#items+1] = { frame = CreateCheckbox(c, "Show Stack Count", db.ShowStackCount, function(v)
        db.ShowStackCount = v; bar:Refresh() end), span = 1 }
    items[#items+1] = { frame = CreateCheckbox(c, "Text Shadow", db.TextShadow, function(v)
        db.TextShadow = v; bar:Refresh() end), span = 1 }
    items[#items+1] = { frame = CreateColorSwatch(c, "Stack Text", db.TextColor, function(col)
        db.TextColor = col; bar:Refresh() end) }
    items[#items+1] = { frame = CreateSlider(c, "Text X Offset", db.TextXOffset or 0, -200, 200, 1, function(v)
        db.TextXOffset = v; bar:Refresh() end) }
    items[#items+1] = { frame = CreateSlider(c, "Text Y Offset", db.TextYOffset or 0, -200, 200, 1, function(v)
        db.TextYOffset = v; bar:Refresh() end) }

    card.Relayout = function(w) GridLayout(c, items, 2, w) end
    card.Relayout()
    return card
end

local function BuildTicksCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Tick Marks")
    local c = card.content
    local items = {}

    local desc = CreateLabel(c, "Vertical lines at the given stack values.", true)
    local descWrap = CreateFrame("Frame", nil, c)
    descWrap:SetHeight(16)
    desc:SetParent(descWrap)
    desc:SetPoint("LEFT", 0, 0)
    items[#items+1] = { frame = descWrap, span = 2 }

    items[#items+1] = { frame = CreateEditBox(c, "Tick Values (e.g. 5, 10, 15)", db.CustomTickValues or "", function(v)
        db.CustomTickValues = v; bar:Refresh() end), span = 2 }
    items[#items+1] = { frame = CreateSlider(c, "Tick Thickness", db.TickWidth or 1, 1, 20, 1, function(v)
        db.TickWidth = v; bar:Refresh() end) }
    items[#items+1] = { frame = CreateColorSwatch(c, "Tick Color", db.TickColor, function(col)
        db.TickColor = col; bar:Refresh() end) }

    card.Relayout = function(w) GridLayout(c, items, 2, w) end
    card.Relayout()
    return card
end

-- Thresholds card has dynamic rows; build its own internal layout.
local function BuildThresholdsCard(parent, bar)
    local db = bar.db
    local card = CreateCard(parent, "Color Thresholds")
    local c = card.content

    local desc = CreateLabel(c, "Bar recolors when stacks cross each threshold.", true)
    desc:SetPoint("TOPLEFT", 0, 0)
    desc:SetWidth(c:GetWidth() > 1 and c:GetWidth() or 480)
    desc:SetJustifyH("LEFT")

    local rowsHolder = CreateFrame("Frame", nil, c)
    rowsHolder:SetPoint("TOPLEFT", 0, -24)
    rowsHolder:SetPoint("RIGHT", 0, 0)
    rowsHolder:SetHeight(1)

    local addBtn

    local function RebuildRows()
        for _, child in pairs({ rowsHolder:GetChildren() }) do
            child:Hide(); child:SetParent(nil)
        end

        local thresholds = db.ColorThresholds or {}
        table.sort(thresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)

        local maxStacks = bar:GetMaxStacks()

        local rowY = 0
        for i, t in ipairs(thresholds) do
            local idx = i
            local row = CreateFrame("Frame", nil, rowsHolder)
            row:SetHeight(28)
            row:SetPoint("TOPLEFT", 0, rowY)
            row:SetPoint("RIGHT", 0, 0)

            local stackLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            stackLabel:SetPoint("LEFT", 0, 0)
            stackLabel:SetText("Stacks =>")
            stackLabel:SetTextColor(unpack(THEME.label))

            local valFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valFS:SetPoint("LEFT", stackLabel, "RIGHT", 6, 0)
            valFS:SetWidth(26)
            valFS:SetJustifyH("LEFT")
            valFS:SetTextColor(THEME.headerText[1], THEME.headerText[2], THEME.headerText[3])
            valFS:SetText(tostring(t.stacks or 1))

            local slider = CreateFrame("Slider", nil, row, "MinimalSliderTemplate")
            slider:SetPoint("LEFT", valFS, "RIGHT", 6, 0)
            slider:SetWidth(150)
            slider:SetHeight(16)
            slider:SetOrientation("HORIZONTAL")
            slider:SetMinMaxValues(1, maxStacks)
            slider:SetValueStep(1)
            slider:SetObeyStepOnDrag(true)
            slider:SetValue(math.min(maxStacks, math.max(1, t.stacks or 1)))
            slider:SetScript("OnValueChanged", function(_, v)
                v = math.floor(v + 0.5)
                valFS:SetText(tostring(v))
                if db.ColorThresholds[idx] then
                    db.ColorThresholds[idx].stacks = v
                    bar:Refresh()
                end
            end)
            -- Re-sort + rebuild once the drag finishes, so rows reorder cleanly.
            slider:SetScript("OnMouseUp", function()
                table.sort(db.ColorThresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)
                RebuildRows()
            end)

            -- Click the value to type it manually.
            local stackEdit = CreateFrame("EditBox", nil, row)
            stackEdit:SetAutoFocus(false)
            stackEdit:SetNumeric(true)
            stackEdit:SetFontObject("GameFontHighlightSmall")
            stackEdit:SetJustifyH("LEFT")
            stackEdit:SetPoint("LEFT", stackLabel, "RIGHT", 6, 0)
            stackEdit:SetSize(26, 16)
            stackEdit:Hide()

            local stackHit = CreateFrame("Button", nil, row)
            stackHit:SetPoint("LEFT", stackLabel, "RIGHT", 6, 0)
            stackHit:SetSize(26, 16)

            local function CommitStackEdit()
                local n = tonumber(stackEdit:GetText())
                stackEdit:Hide(); valFS:Show(); stackHit:Show()
                if n then
                    if n < 1 then n = 1 elseif n > maxStacks then n = maxStacks end
                    slider:SetValue(n)   -- drives OnValueChanged -> saves + Refresh
                    table.sort(db.ColorThresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)
                    RebuildRows()
                end
            end
            stackEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            stackEdit:SetScript("OnEscapePressed", function(self)
                self:Hide(); valFS:Show(); stackHit:Show(); self:ClearFocus()
            end)
            stackEdit:SetScript("OnEditFocusLost", CommitStackEdit)
            stackHit:SetScript("OnClick", function()
                stackEdit:SetText(tostring(db.ColorThresholds[idx] and db.ColorThresholds[idx].stacks or 1))
                valFS:Hide(); stackHit:Hide(); stackEdit:Show()
                stackEdit:SetFocus(); stackEdit:HighlightText()
            end)

            local colorSwatch = CreateColorSwatch(row, "", t.color or { 1, 1, 1, 1 }, function(col)
                db.ColorThresholds[idx].color = col
                bar:Refresh()
            end)
            colorSwatch:SetSize(60, 24)
            colorSwatch:ClearAllPoints()
            colorSwatch:SetPoint("LEFT", slider, "RIGHT", 14, 0)
            colorSwatch.swatch:ClearAllPoints()
            colorSwatch.swatch:SetPoint("LEFT", 0, 0)

            local removeBtn = CreateButton(row, "Remove", 70, 24)
            removeBtn:SetPoint("LEFT", colorSwatch, "LEFT", 36, 0)
            removeBtn:SetScript("OnClick", function()
                table.remove(db.ColorThresholds, idx)
                RebuildRows()
                bar:Refresh()
            end)

            rowY = rowY - 32
        end

        rowsHolder:SetHeight(math.max(1, math.abs(rowY)))

        if addBtn then
            addBtn:ClearAllPoints()
            addBtn:SetPoint("TOPLEFT", rowsHolder, "BOTTOMLEFT", 0, -10)
        end

        c:SetHeight(24 + math.abs(rowY) + 44)
        if card.OnHeightChanged then card.OnHeightChanged() end
    end

    addBtn = CreateButton(c, "+ Add Threshold", 150, 26)
    addBtn:SetScript("OnClick", function()
        db.ColorThresholds = db.ColorThresholds or {}
        local maxStacks = bar:GetMaxStacks()
        local newStacks = (#db.ColorThresholds > 0)
            and math.min(maxStacks, (db.ColorThresholds[#db.ColorThresholds].stacks or 0) + 1)
            or 1
        table.insert(db.ColorThresholds, { stacks = newStacks, color = { 1, 0.5, 0, 1 } })
        table.sort(db.ColorThresholds, function(a, b) return (a.stacks or 0) < (b.stacks or 0) end)
        RebuildRows()
        bar:Refresh()
    end)

    card.RebuildRows = RebuildRows
    card.Relayout = function(w)
        if not w or w < 1 then w = c:GetWidth() end
        if not w or w < 1 then w = 480 end
        desc:SetWidth(w)
        RebuildRows()
    end
    card.Relayout()
    return card
end

local function BuildProfilesCard(parent, db)
    local card = CreateCard(parent, "Profiles")
    local c = card.content

    local profileNames = ns:GetProfileNames()
    local profileOptions = {}
    for _, name in ipairs(profileNames) do
        profileOptions[name] = name
    end

    local dd = CreateDropdown(c, "Active Profile", profileOptions, ShatterDB.activeProfile, function(name)
        ns:SwitchProfile(name)
    end)
    dd:SetParent(c)
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", 0, 0)
    dd:SetPoint("RIGHT", 0, 0)

    local function MakeBtn(text, width)
        return CreateButton(c, text, width, 26)
    end

    local newBtn = MakeBtn("New", 70)
    newBtn:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -8)
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

    local deleteBtn = MakeBtn("Delete", 70)
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

    local renameBtn = MakeBtn("Rename", 80)
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

    local exportBtn = MakeBtn("Export", 70)
    exportBtn:SetPoint("LEFT", renameBtn, "RIGHT", 8, 0)
    exportBtn:SetScript("OnClick", function()
        ShowExportPopup(ShatterDB.activeProfile)
    end)

    local importBtn = MakeBtn("Import", 70)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetScript("OnClick", function()
        ShowImportPopup()
    end)

    card.Relayout = function(w)
        c:SetHeight(THEME.rowH + 16 + 8 + 26)
    end
    card.Relayout()
    return card
end

-------- Content assembly --------

local CARD_SIDE_MARGIN   = 16
local CARD_CONTENT_INSET = 14
local CARD_HEADER_H      = 44
local CARD_BOTTOM_PAD    = 14
local CARD_GAP           = 14

local function StackCards(parent, cardList, headerOffset)
    local y = headerOffset
    for _, card in ipairs(cardList) do
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", CARD_SIDE_MARGIN, y)
        card:SetPoint("RIGHT", parent, "RIGHT", -CARD_SIDE_MARGIN, 0)
        local ch = card.content:GetHeight() or 1
        local total = ch + CARD_HEADER_H + CARD_BOTTOM_PAD
        card:SetHeight(total)
        y = y - total - CARD_GAP
    end
    return math.abs(y)
end

-- Build one bar's settings page into `parent`. The Shatter (main) page also
-- carries the shared Profiles card (includeProfiles); SalvoBar does not.
local function BuildConfigContent(parent, bar, includeProfiles)
    local db = bar and bar.db
    if not db then return end

    -- ---- Header ----
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 16, -10)
    header:SetPoint("RIGHT", -16, 0)
    header:SetHeight(84)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(bar.cfg.title)
    title:SetTextColor(unpack(THEME.headerText))

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
    subtitle:SetText(bar.cfg.subtitle or "")
    subtitle:SetTextColor(unpack(THEME.sublabel))

    -- Enable/disable toggle for this bar. db.Enabled is the source of truth;
    -- ApplySettings reads it and calls Enable()/Disable() as needed.
    local enableCheck = CreateFrame("CheckButton", nil, header, "InterfaceOptionsCheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -3, -4)
    enableCheck:SetChecked(db.Enabled ~= false)
    enableCheck.Text:SetText("Enable")
    enableCheck.Text:SetFontObject("GameFontHighlightSmall")
    enableCheck.Text:SetTextColor(unpack(THEME.label))
    enableCheck:SetScript("OnClick", function(self)
        local on = self:GetChecked()
        db.Enabled = on
        if not on and bar.previewActive then
            bar:HidePreview()
        end
        bar:ApplySettings()
    end)

    local previewBtn = CreateButton(header, "Toggle Preview", 130, 26)
    previewBtn:SetPoint("TOPRIGHT", 0, -2)
    previewBtn:SetScript("OnClick", function() bar:TogglePreview() end)

    -- Secondary bars get a "Copy from Shatter" button that pulls the main bar's
    -- visual settings (not ticks / thresholds).
    if bar.cfg.key ~= "shatter" then
        local copyBtn = CreateButton(header, "Copy from Shatter", 150, 26)
        copyBtn:SetPoint("TOPRIGHT", previewBtn, "TOPLEFT", -8, 0)
        copyBtn:SetScript("OnClick", function()
            if ns:CopyVisualSettings("shatter", bar.cfg.key) then
                bar:ApplySettings()
                ns:Print("Copied visual settings from Shatter.")
                ns:RebuildConfigPanel()
            end
        end)
    end

    local rule = Tex(header, "ARTWORK")
    rule:SetColorTexture(THEME.cardBorder[1], THEME.cardBorder[2], THEME.cardBorder[3], 1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)

    -- ---- Cards ----
    local cards = {
        BuildLayoutCard(parent, bar),
        BuildTrackingCard(parent, bar),
        BuildColorsCard(parent, bar),
        BuildTextureCard(parent, bar),
        BuildStackTextCard(parent, bar),
        BuildTicksCard(parent, bar),
        BuildThresholdsCard(parent, bar),
    }
    if includeProfiles then
        cards[#cards + 1] = BuildProfilesCard(parent, db)
    end

    local restacking = false
    local function Restack()
        if restacking then return end
        restacking = true

        local parentW = parent:GetWidth()
        if not parentW or parentW < 1 then parentW = 480 end
        local cardW = parentW - CARD_SIDE_MARGIN * 2
        local contentW = cardW - CARD_CONTENT_INSET * 2

        for _, card in ipairs(cards) do
            card:SetWidth(cardW)
            if card.Relayout then card.Relayout(contentW) end
        end
        local totalH = StackCards(parent, cards, -104)
        parent:SetHeight(totalH + 40)
        restacking = false
    end

    -- Thresholds card grows/shrinks; restack when it does.
    for _, card in ipairs(cards) do
        if card.RebuildRows then card.OnHeightChanged = Restack end
    end

    Restack()
    C_Timer.After(0, Restack)

    parent.Restack = Restack
end

-------- Settings panel init --------

-- Create a scrolling canvas panel for one bar and remember it for rebuilds.
local function CreateBarPanel(panelName, bar, includeProfiles)
    local panel = CreateFrame("Frame", panelName)
    panel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1200)
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnSizeChanged", function(_, w)
        if w and w > 1 then
            content:SetWidth(w)
            if content.Restack then content.Restack() end
        end
    end)

    barPanels[#barPanels + 1] = {
        bar = bar, content = content, includeProfiles = includeProfiles,
    }

    BuildConfigContent(content, bar, includeProfiles)
    return panel
end

local function InitSettingsPanel()
    local shatterBar = ns.barsByKey["shatter"]
    local salvoBar   = ns.barsByKey["salvo"]

    -- Main "Shatter" category (carries the Profiles card).
    local shatterPanel = CreateBarPanel("ShatterSettingsPanel", shatterBar, true)
    local category = Settings.RegisterCanvasLayoutCategory(shatterPanel, "Shatter")
    settingsCategoryID = category.ID
    Settings.RegisterAddOnCategory(category)

    -- "SalvoBar" as a subcategory of Shatter.
    if salvoBar then
        local salvoPanel = CreateBarPanel("SalvoBarSettingsPanel", salvoBar, false)
        Settings.RegisterCanvasLayoutSubcategory(category, salvoPanel, "SalvoBar")
    end
end

function ns:OpenConfig()
    if settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    end
end

-- Rebuild every bar's page (e.g. after a profile switch re-points the dbs).
function ns:RebuildConfigPanel()
    for _, rec in ipairs(barPanels) do
        local content = rec.content
        ns.CleanupFrameList({ content:GetChildren() })
        for _, region in pairs({ content:GetRegions() }) do
            region:Hide()
            region:SetParent(nil)
        end
        BuildConfigContent(content, rec.bar, rec.includeProfiles)
    end
end

local configInitFrame = CreateFrame("Frame")
configInitFrame:RegisterEvent("PLAYER_LOGIN")
configInitFrame:SetScript("OnEvent", function(self)
    InitSettingsPanel()
    self:UnregisterAllEvents()
end)
