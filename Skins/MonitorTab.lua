
-- Monitor-bar configuration UI and catalog-driven bar creation flow.
local _, ns = ...

local L   = ns.L
local MB  = ns.MonitorBars
local AceGUI
local LSM

local MASK_AND_BORDER_STYLE_ITEMS = {
    ["0"] = L.mbStyle0,
    ["1"] = L.mbStyle1,
    ["2"] = L.mbStyle2,
    ["3"] = L.mbStyle3,
    ["4"] = L.mbStyle4,
    ["5"] = L.mbStyle5,
}

local BORDER_STYLE_ITEMS = {
    ["none"] = L.mbBorderNone,
    ["whole"] = L.mbBorderWhole,
    ["segment"] = L.mbBorderSegment,
}

local OUTLINE_ITEMS = {
    ["NONE"]         = L.outNone,
    ["OUTLINE"]      = L.outOutline,
    ["THICKOUTLINE"] = L.outThick,
}

local STRATA_ITEMS = {
    ["BACKGROUND"] = L.mbStrataBackground,
    ["LOW"]        = L.mbStrataLow,
    ["MEDIUM"]     = L.mbStrataMedium,
    ["HIGH"]       = L.mbStrataHigh,
}
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }

local TEXT_ANCHOR_ITEMS = {
    ["LEFT"]        = L.posLeft,
    ["CENTER"]      = L.posCenter,
    ["RIGHT"]       = L.posRight,
}
local TEXT_ANCHOR_ORDER = { "LEFT", "CENTER", "RIGHT" }

local BAR_TYPE_ITEMS = {
    ["stack"]    = L.mbTypeStack,
    ["charge"]   = L.mbTypeCharge,
    ["duration"] = L.mbTypeDuration,
}

local UNIT_ITEMS = {
    ["player"] = L.mbUnitPlayer,
    ["target"] = L.mbUnitTarget,
}

local CLASS_TAG_ORDER = {
    "ALL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
}

local selectedBarID = nil
local PLAYER_CLASS_TAG = select(2, UnitClass("player"))
local ICICLES_SPELL_ID = 205473
local HALF_CONTROL_RELATIVE_WIDTH = 0.5
local LABELED_ROW_HEIGHT = 44
local COMPACT_ROW_HEIGHT = 24
local CONTROL_ROW_SPACING = 3
local SECTION_SPACER_HEIGHT = 6
local MONITOR_BARS_FLOW_LAYOUT = "SMBFlow3"
local MONITOR_BARS_SPEC_LAYOUT = "SMBSpecSpread"
local TEXTURE_DROPDOWN_VISIBLE_ITEMS = 20
local TEXTURE_DROPDOWN_ITEM_TYPE = "SMB-Dropdown-Item-Texture"
local monitorBarsFlowRegistered = false
local monitorBarsSpecLayoutRegistered = false
local textureDropdownItemRegistered = false

local function RoundToOneDecimal(num)
    if type(num) ~= "number" then return num end
    return math.floor(num * 10 + 0.5) / 10
end

local function GetSelectedBarConfig()
    local bars = ns.db and ns.db.monitorBars and ns.db.monitorBars.bars
    if type(bars) ~= "table" then
        return nil
    end

    for _, barCfg in ipairs(bars) do
        if type(barCfg) == "table" and barCfg.id == selectedBarID then
            return barCfg
        end
    end
    return nil
end

local function GetSelectedBarDisplayName()
    local barCfg = GetSelectedBarConfig()
    if not barCfg then
        return nil
    end

    local spellName = barCfg.spellName
    if (not spellName or spellName == "") and type(barCfg.spellID) == "number" and barCfg.spellID > 0 then
        spellName = C_Spell.GetSpellName(barCfg.spellID)
    end

    if spellName and spellName ~= "" then
        return spellName
    end
    return L.mbNoSpell or "未选择技能"
end

function ns.GetSelectedMonitorBarNoticeText()
    local spellName = GetSelectedBarDisplayName()
    if not spellName then
        return ""
    end
    return string.format(L.mbEditingBarNoticeFormat or "当前选中[%s]正在编辑", spellName)
end

local function RefreshSelectedBarNotice()
    if type(ns._refreshSelectedBarNotice) == "function" then
        ns._refreshSelectedBarNotice()
    end
end

local function IsClassMatchedForCurrentPlayer(classTag)
    if classTag == nil or classTag == "" or classTag == "ALL" then
        return true
    end
    return classTag == PLAYER_CLASS_TAG
end

local function GetFontItems()
    local items, order = {}, {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List("font")) do
            items[name] = name
            order[#order + 1] = name
        end
    end
    return items, order
end

local function GetTextureItems()
    local items, order = {}, {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List("statusbar")) do
            items[name] = name
            order[#order + 1] = name
        end
    end
    return items, order
end

local function EnhanceTextureDropdown(dropdown)
    if not dropdown or not dropdown.pullout or not dropdown.pullout.IterateItems then
        return
    end

    dropdown.pullout:SetMaxHeight((TEXTURE_DROPDOWN_VISIBLE_ITEMS * 17) + 34)
end

local function RegisterTextureDropdownItem()
    if textureDropdownItemRegistered or not AceGUI then
        return
    end

    local itemBaseLib = LibStub("AceGUI-3.0-DropDown-ItemBase", true)
    if not itemBaseLib or not itemBaseLib.GetItemBase then
        return
    end

    local ItemBase = itemBaseLib:GetItemBase()
    local widgetType = TEXTURE_DROPDOWN_ITEM_TYPE
    local widgetVersion = 1

    local function UpdateToggle(self)
        if self.value then
            self.check:Show()
        else
            self.check:Hide()
        end
    end

    local function RefreshTexturePreview(self)
        if not self._smbTexturePreview then
            return
        end
        local texPath = LSM and LSM.Fetch and LSM:Fetch("statusbar", self.userdata and self.userdata.value)
        self._smbTexturePreview:SetTexture(texPath or "Interface\\Buttons\\WHITE8X8")
        self._smbTexturePreview:Show()
    end

    local function OnRelease(self)
        ItemBase.OnRelease(self)
        self:SetValue(nil)
        self._smbTexturePreview:Hide()
        self._smbTexturePreview:SetTexture(nil)
        self.text:SetShadowColor(0, 0, 0, 0)
        self.text:SetShadowOffset(0, 0)
    end

    local function Frame_OnClick(this)
        local self = this.obj
        if self.disabled then return end
        self.value = not self.value
        if self.value then
            PlaySound(856)
        else
            PlaySound(857)
        end
        UpdateToggle(self)
        self:Fire("OnValueChanged", self.value)
    end

    local function SetValue(self, value)
        self.value = value
        UpdateToggle(self)
    end

    local function SetText(self, text)
        ItemBase.SetText(self, text)
        RefreshTexturePreview(self)
    end

    local function Constructor()
        local self = ItemBase.Create(widgetType)

        self.frame:SetScript("OnClick", Frame_OnClick)

        self._smbTexturePreview = self.frame:CreateTexture(nil, "BACKGROUND")
        self._smbTexturePreview:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -1)
        self._smbTexturePreview:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 1)
        self._smbTexturePreview:SetAlpha(0.9)
        self._smbTexturePreview:Hide()

        self.text:SetShadowColor(0, 0, 0, 1)
        self.text:SetShadowOffset(1, -1)

        self.SetText = SetText
        self.SetValue = SetValue
        self.GetValue = function(widget) return widget.value end
        self.OnRelease = OnRelease

        AceGUI:RegisterAsWidget(self)
        return self
    end

    AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion + ItemBase.version)
    textureDropdownItemRegistered = true
end

local function NewBarDefaults(id, barType, spellID, spellName, unit)
    local playerClass = select(2, UnitClass("player"))
    return {
        id         = id,
        enabled    = true,
        class      = playerClass,
        barType    = barType or "stack",
        spellID    = spellID or 0,
        spellName  = spellName or "",
        unit       = unit or "player",
        maxStacks  = 5,
        maxCharges = 0,
        isChargeSpell = (barType == "charge"),
        maxDuration = 60,
        width      = 300,
        height     = 15,
        barShape   = "Bar",
        verticalBar = false,
        reverseGrowth = false,
        posX       = 0,
        posY       = 0,
        barColor    = { 0.4, 0.75, 1.0, 1 },
        bgColor     = { 0.1, 0.1, 0.1, 0.6 },
        borderColor = { 0, 0, 0, 1 },
        maskAndBorderStyle = "1",
        showIcon   = false,
        showText   = false,
        textAlign  = "CENTER",
        textOffsetX = 0,
        textOffsetY = 0,
        fontName   = "",
        fontSize   = 14,
        outline    = "OUTLINE",
        showCountText = false,
        countTextAnchor = "LEFT",
        countTextOffsetX = 0,
        countTextOffsetY = 0,
        countFontName = "",
        countFontSize = 14,
        countOutline = "OUTLINE",
        barTexture = "Solid",
        colorThreshold  = 0,
        thresholdColor  = { 1.0, 1.0, 1.0, 1 },
        colorThreshold2 = 0,
        thresholdColor2 = { 1.0, 1.0, 0.0, 1 },
        borderStyle     = "whole",
        segmentGap      = 1,
        hideFromCDM     = false,
        showCondition   = (barType == "duration") and "active_only" or "always",
        frameStrata     = "MEDIUM",
        textAnchor      = "CENTER",
        smoothAnimation = true,
        showSpellName  = false,
        nameAnchor     = "RIGHT",
        nameOutline    = "OUTLINE",
        nameFontName   = "",
        nameFontSize   = 14,
        specs           = { GetSpecialization() or 1 },
    }
end

local function ResetBarToDefaults(barCfg)
    if not barCfg then
        return
    end

    local resetBar = NewBarDefaults(barCfg.id, barCfg.barType, barCfg.spellID, barCfg.spellName, barCfg.unit)
    resetBar.class = barCfg.class
    resetBar.specs = ns.DeepCopy(barCfg.specs or resetBar.specs)
    resetBar.enabled = barCfg.enabled

    for k in pairs(barCfg) do
        barCfg[k] = nil
    end
    for k, v in pairs(resetBar) do
        barCfg[k] = ns.DeepCopy(v)
    end
end

local function GetClassItems()
    local items, order = {}, {}
    items.ALL = L.classAll
    order[#order + 1] = "ALL"
    for i = 2, #CLASS_TAG_ORDER do
        local classTag = CLASS_TAG_ORDER[i]
        local className = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classTag]) or classTag
        items[classTag] = className
        order[#order + 1] = classTag
    end
    return items, order
end

local function GetBarDropdownList(cfg)
    local items, order, idToIndex = {}, {}, {}
    for i, bar in ipairs(cfg.bars) do
        if IsClassMatchedForCurrentPlayer(bar.class) then
            local name = bar.spellName and bar.spellName ~= "" and bar.spellName or L.mbNoSpell
            local typeTag
            if bar.barType == "charge" then
                typeTag = L.mbTypeCharge
            elseif bar.barType == "duration" then
                typeTag = L.mbTypeDuration or "Duration"
            else
                typeTag = L.mbTypeStack
            end
            local barID = bar.id or i
            items[barID] = string.format("%s  [%s]", name, typeTag)
            order[#order + 1] = barID
            idToIndex[barID] = i
        end
    end
    return items, order, idToIndex
end

local function IsBarVisibleForCurrentSpec(barCfg)
    if not barCfg or barCfg.enabled == false then
        return false
    end

    local specs = barCfg and barCfg.specs
    if type(specs) ~= "table" or #specs == 0 then
        return true
    end

    local currentSpec = GetSpecialization() or 1
    for _, specIndex in ipairs(specs) do
        if specIndex == currentSpec then
            return true
        end
    end
    return false
end

local function GetDefaultBarIDForCurrentSpec(cfg, barOrder, idToIndex)
    for _, barID in ipairs(barOrder or {}) do
        local index = idToIndex and idToIndex[barID]
        local barCfg = index and cfg and cfg.bars and cfg.bars[index]
        if barCfg and IsBarVisibleForCurrentSpec(barCfg) then
            return barID
        end
    end
    return nil
end

local function AddMonitorHeading(parent, text)
    local topSpacer = AceGUI:Create("Label")
    topSpacer:SetText("")
    topSpacer:SetFullWidth(true)
    topSpacer:SetHeight(SECTION_SPACER_HEIGHT)
    parent:AddChild(topSpacer)

    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    parent:AddChild(heading)

    local bottomSpacer = AceGUI:Create("Label")
    bottomSpacer:SetText("")
    bottomSpacer:SetFullWidth(true)
    bottomSpacer:SetHeight(SECTION_SPACER_HEIGHT)
    parent:AddChild(bottomSpacer)
end

local function NormalizeDropdownToFrame(widget)
    if not widget or not widget.frame or not widget.dropdown then
        return
    end

    widget.dropdown:ClearAllPoints()
    widget.dropdown:SetPoint("TOPLEFT", widget.frame, "TOPLEFT", -14.5, 0)
    widget.dropdown:SetPoint("BOTTOMRIGHT", widget.frame, "BOTTOMRIGHT", 20.5, 0)
end

local function RegisterMonitorBarsFlowLayout()
    if monitorBarsFlowRegistered or not AceGUI then
        return
    end

    AceGUI:RegisterLayout(MONITOR_BARS_FLOW_LAYOUT, function(content, children)
        local height = 0
        local usedwidth = 0
        local rowheight = 0
        local rowoffset = 0
        local width = content.width or content:GetWidth() or 0

        local rowstart
        local rowstartoffset
        local isfullheight
        local frameoffset
        local lastframeoffset
        local oversize

        for i = 1, #children do
            local child = children[i]
            local frame = child.frame
            local frameheight = frame.height or frame:GetHeight() or 0
            local framewidth = frame.width or frame:GetWidth() or 0
            lastframeoffset = frameoffset
            frameoffset = child.alignoffset or (frameheight / 2)
            oversize = nil

            if child.width == "relative" then
                framewidth = width * child.relWidth
            end

            frame:Show()
            frame:ClearAllPoints()
            if i == 1 then
                frame:SetPoint("TOPLEFT", content)
                rowheight = frameheight
                rowoffset = frameoffset
                rowstart = frame
                rowstartoffset = frameoffset
                usedwidth = framewidth
                if usedwidth > width then
                    oversize = true
                end
            else
                if usedwidth == 0 or (framewidth + usedwidth > width) or child.width == "fill" then
                    if isfullheight then
                        break
                    end
                    rowstart:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(height + (rowoffset - rowstartoffset) + CONTROL_ROW_SPACING))
                    height = height + rowheight + CONTROL_ROW_SPACING
                    rowstart = frame
                    rowstartoffset = frameoffset
                    rowheight = frameheight
                    rowoffset = frameoffset
                    usedwidth = framewidth
                    if usedwidth > width then
                        oversize = true
                    end
                else
                    rowoffset = math.max(rowoffset, frameoffset)
                    rowheight = math.max(rowheight, rowoffset + (frameheight / 2))

                    frame:SetPoint("TOPLEFT", children[i - 1].frame, "TOPRIGHT", 0, frameoffset - lastframeoffset)
                    usedwidth = framewidth + usedwidth
                end
            end

            if child.width == "fill" then
                child:SetWidth(width)
                frame:SetPoint("RIGHT", content)

                usedwidth = 0
                rowstart = frame

                if child.DoLayout then
                    child:DoLayout()
                end
                rowheight = frame.height or frame:GetHeight() or 0
                rowoffset = child.alignoffset or (rowheight / 2)
                rowstartoffset = rowoffset
            elseif child.width == "relative" then
                child:SetWidth(width * child.relWidth)

                if child.DoLayout then
                    child:DoLayout()
                end
            elseif oversize and width > 1 then
                frame:SetPoint("RIGHT", content)
            end

            if child.height == "fill" then
                frame:SetPoint("BOTTOM", content)
                isfullheight = true
            end
        end

        if isfullheight then
            rowstart:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -height)
        elseif rowstart then
            rowstart:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(height + (rowoffset - rowstartoffset) + CONTROL_ROW_SPACING))
        end

        height = height + rowheight + CONTROL_ROW_SPACING
        content.obj:LayoutFinished(nil, height)
    end)

    monitorBarsFlowRegistered = true
end

local function RegisterMonitorBarsSpecLayout()
    if monitorBarsSpecLayoutRegistered or not AceGUI then
        return
    end

    AceGUI:RegisterLayout(MONITOR_BARS_SPEC_LAYOUT, function(content, children)
        local width = content.width or content:GetWidth() or 0
        local count = #children
        if count == 0 then
            content.obj:LayoutFinished(nil, 0)
            return
        end

        local maxHeight = 0
        local centers = {}
        local firstWidth, lastWidth

        for i = 1, count do
            local child = children[i]
            local frame = child.frame
            local frameWidth = frame.width or frame:GetWidth() or 0
            local frameHeight = frame.height or frame:GetHeight() or 0

            frame:Show()
            frame:ClearAllPoints()

            if i == 1 then
                firstWidth = frameWidth
            end
            if i == count then
                lastWidth = frameWidth
            end

            maxHeight = math.max(maxHeight, frameHeight)
        end

        if count == 1 then
            centers[1] = (firstWidth or 0) / 2
        else
            local firstCenter = (firstWidth or 0) / 2
            local lastCenter = width - ((lastWidth or 0) / 2)
            for i = 1, count do
                centers[i] = firstCenter + ((i - 1) * (lastCenter - firstCenter) / (count - 1))
            end
        end

        for i = 1, count do
            local child = children[i]
            local frame = child.frame
            local frameWidth = frame.width or frame:GetWidth() or 0
            local x = centers[i] - (frameWidth / 2)
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", x, 0)
        end

        content.obj:LayoutFinished(nil, maxHeight)
    end)

    monitorBarsSpecLayoutRegistered = true
end

local function AddDeleteButton(parent, barCfg, rebuildAll, widthSource)
    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetHeight(35)
    local function SetDeleteButtonText(text)
        deleteBtn:SetText("|cffff4444" .. text .. "|r")
    end

    SetDeleteButtonText(L.mbDeleteBar)
    deleteBtn:SetFullWidth(true)

    local pendingDelete = false
    deleteBtn:SetCallback("OnClick", function()
        if not pendingDelete then
            pendingDelete = true
            SetDeleteButtonText(L.mbDeleteConfirm)
            C_Timer.After(5, function()
                if pendingDelete then
                    pendingDelete = false
                    SetDeleteButtonText(L.mbDeleteBar)
                end
            end)
            return
        end

        pendingDelete = false
        MB:DestroyBar(barCfg.id)
        local bars = ns.db.monitorBars.bars
        for i, b in ipairs(bars) do
            if b.id == barCfg.id then
                table.remove(bars, i)
                break
            end
        end
        selectedBarID = nil
        RefreshSelectedBarNotice()
        rebuildAll()
    end)
    parent:AddChild(deleteBtn)
end

local function BuildBarConfig(container, barCfg, rebuildAll)
    barCfg.width = tonumber(barCfg.width) or 300
    barCfg.height = tonumber(barCfg.height) or 15
    barCfg.verticalBar = (barCfg.verticalBar == true)
    barCfg.reverseGrowth = (barCfg.reverseGrowth == true)
    barCfg.posX = tonumber(barCfg.posX) or 0
    barCfg.posY = tonumber(barCfg.posY) or 0


    if barCfg.maskAndBorderStyle == "1px" then
        barCfg.maskAndBorderStyle = "1"
    elseif barCfg.maskAndBorderStyle == "Thin" then
        barCfg.maskAndBorderStyle = "2"
    elseif barCfg.maskAndBorderStyle == "Medium" then
        barCfg.maskAndBorderStyle = "3"
    elseif barCfg.maskAndBorderStyle == "Thick" then
        barCfg.maskAndBorderStyle = "5"
    elseif barCfg.maskAndBorderStyle == "None" then
        barCfg.maskAndBorderStyle = "0"
    elseif not barCfg.maskAndBorderStyle then
        if barCfg.borderSize and barCfg.borderSize > 1 then
            barCfg.maskAndBorderStyle = "2"
        elseif barCfg.borderSize and barCfg.borderSize == 0 then
            barCfg.maskAndBorderStyle = "0"
        else
            barCfg.maskAndBorderStyle = "1"
        end
    end

    local function Refresh()
        local f = MB:GetActiveFrame(barCfg.id)
        if f then MB:ApplyStyle(f) end
    end

    local function RefreshPosition()
        local f = MB:GetActiveFrame(barCfg.id)
        if not f then
            return
        end

        local frameScale = f:GetEffectiveScale()
        local posX = MB.getNearestPixel(barCfg.posX or 0, frameScale)
        local posY = MB.getNearestPixel(barCfg.posY or 0, frameScale)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    end

    local function AddSpacer(parent)
        -- Keep section transitions readable on narrow window layouts.
        local spacer = AceGUI:Create("Label")
        spacer:SetText("")
        spacer:SetFullWidth(true)
        spacer:SetHeight(SECTION_SPACER_HEIGHT)
        parent:AddChild(spacer)
    end

    local function AddTwoColumnRow(parent)
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
        parent:AddChild(row)
        return row
    end

    AddMonitorHeading(container, L.mbGeneralSection or "总体设置")

    local topActionRow = AddTwoColumnRow(container)
    topActionRow.noAutoHeight = true
    topActionRow:SetHeight(COMPACT_ROW_HEIGHT)

    local enableCB = AceGUI:Create("CheckBox")
    enableCB:SetLabel(L.enable)
    enableCB:SetValue(barCfg.enabled)
    enableCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    enableCB:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.enabled = val
        MB:RebuildAllBars()
    end)
    topActionRow:AddChild(enableCB)

    local resetBtn = AceGUI:Create("Button")
    local pendingReset = false
    local function SetResetButtonText()
        if pendingReset then
            resetBtn:SetText("|cffff4444" .. (L.mbResetBarConfirm or "确认恢复？") .. "|r")
        else
            resetBtn:SetText("|cffffd200" .. (L.mbResetBar or "恢复默认设置") .. "|r")
        end
    end
    resetBtn:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    resetBtn:SetCallback("OnClick", function()
        if not pendingReset then
            pendingReset = true
            SetResetButtonText()
            C_Timer.After(3, function()
                if pendingReset and resetBtn and resetBtn.frame then
                    pendingReset = false
                    SetResetButtonText()
                end
            end)
            return
        end

        pendingReset = false
        ResetBarToDefaults(barCfg)
        MB:RebuildAllBars()
        rebuildAll()
    end)
    SetResetButtonText()
    topActionRow:AddChild(resetBtn)

    AddMonitorHeading(container, "触发设置")

    local spellRow = AddTwoColumnRow(container)
    spellRow.noAutoHeight = true
    spellRow:SetHeight(LABELED_ROW_HEIGHT)

    local spellBox = AceGUI:Create("EditBox")
    spellBox:SetLabel(L.mbSpellID)
    spellBox:SetText(barCfg.spellID > 0 and tostring(barCfg.spellID) or "")
    spellBox:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    spellBox.frame:SetHeight(LABELED_ROW_HEIGHT)
    spellBox.alignoffset = 30
    spellBox:SetCallback("OnEnterPressed", function(_, _, val)
        local id = tonumber(val)
        if id and id > 0 then
            barCfg.spellID = id
            barCfg.spellName = C_Spell.GetSpellName(id) or ""
            MB:RebuildAllBars()
            rebuildAll()
        end
    end)
    spellRow:AddChild(spellBox)

    local spellName = L.mbNoSpell
    if barCfg.spellID > 0 then
        spellName = barCfg.spellName
        if not spellName or spellName == "" then
            spellName = C_Spell.GetSpellName(barCfg.spellID) or "?"
            barCfg.spellName = spellName
        end
    end

    local nameLabel = AceGUI:Create("Label")
    nameLabel:SetText("|cff00ccff" .. L.mbSpellName .. ": " .. spellName .. "|r")
    nameLabel:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    nameLabel:SetFontObject(GameFontHighlightSmall)
    nameLabel.frame:SetHeight(LABELED_ROW_HEIGHT)
    nameLabel.label:ClearAllPoints()
    nameLabel.label:SetPoint("TOPLEFT", nameLabel.frame, "TOPLEFT", 0, -18)
    nameLabel.label:SetPoint("TOPRIGHT", nameLabel.frame, "TOPRIGHT", 0, -18)
    nameLabel.label:SetJustifyH("LEFT")
    nameLabel.label:SetJustifyV("TOP")
    spellRow:AddChild(nameLabel)

    local typeClassRow = AddTwoColumnRow(container)
    typeClassRow.noAutoHeight = true
    typeClassRow:SetHeight(LABELED_ROW_HEIGHT)

    local typeDD = AceGUI:Create("Dropdown")
    typeDD:SetLabel(L.mbBarType)
    typeDD:SetList(BAR_TYPE_ITEMS, { "stack", "charge", "duration" })
    typeDD:SetValue(barCfg.barType)
    typeDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    typeDD:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.barType = val
        barCfg.barShape = "Bar"
        MB:RebuildAllBars()
        rebuildAll()
    end)
    typeClassRow:AddChild(typeDD)

    local classItems, classOrder = GetClassItems()
    local classDD = AceGUI:Create("Dropdown")
    classDD:SetLabel(L.mbLoadClass)
    classDD:SetList(classItems, classOrder)
    classDD:SetValue(barCfg.class or "ALL")
    classDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    classDD:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.class = val
        MB:RebuildAllBars()
    end)
    typeClassRow:AddChild(classDD)

    local SHOW_COND_ITEMS = {
        ["always"]          = L.mbCondAlways,
        ["combat"]          = L.mbCondCombat,
        ["target"]          = L.mbCondTarget,
        ["dragonriding"]    = L.mbCondDragonriding,
        ["not_dragonriding"] = L.mbCondNotDragonriding,
        ["active_only"]     = L.mbCondActiveOnly,
    }
    local condDD = AceGUI:Create("Dropdown")
    condDD:SetLabel(L.mbShowCondition)
    condDD:SetList(SHOW_COND_ITEMS, { "always", "combat", "target", "active_only", "dragonriding", "not_dragonriding" })
    condDD:SetValue(barCfg.showCondition or "always")
    condDD:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.showCondition = val
        MB:RebuildAllBars()
    end)

    if barCfg.barType == "stack" or barCfg.barType == "duration" then
        local unitCondRow = AddTwoColumnRow(container)
        unitCondRow.noAutoHeight = true
        unitCondRow:SetHeight(LABELED_ROW_HEIGHT)

        local unitDD = AceGUI:Create("Dropdown")
        unitDD:SetLabel(L.mbUnit)
        unitDD:SetList(UNIT_ITEMS, { "player", "target" })
        unitDD:SetValue(barCfg.unit or "player")
        unitDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        unitDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.unit = val
            Refresh()
        end)
        unitCondRow:AddChild(unitDD)

        condDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        unitCondRow:AddChild(condDD)
    else
        condDD:SetFullWidth(true)
        container:AddChild(condDD)
    end

    local hideTrackerCB = AceGUI:Create("CheckBox")
    hideTrackerCB:SetLabel(L.mbHideFromTracker)
    hideTrackerCB:SetValue(barCfg.hideFromCDM or false)
    hideTrackerCB:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.hideFromCDM = val
        MB:RebuildAllBars()
    end)
    if barCfg.barType == "stack" then
        local trackerRow = AddTwoColumnRow(container)
        trackerRow.noAutoHeight = true
        trackerRow:SetHeight(COMPACT_ROW_HEIGHT)

        hideTrackerCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        trackerRow:AddChild(hideTrackerCB)

        local smoothCB = AceGUI:Create("CheckBox")
        smoothCB:SetLabel(L.mbSmoothAnimation)
        smoothCB:SetValue(barCfg.smoothAnimation ~= false)
        smoothCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        smoothCB:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.smoothAnimation = val
            MB:RebuildAllBars()
        end)
        smoothCB:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText(L.mbSmoothAnimationTip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        smoothCB:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
        trackerRow:AddChild(smoothCB)
    else
        hideTrackerCB:SetFullWidth(true)
        container:AddChild(hideTrackerCB)
    end
    if barCfg.barType == "stack" then
    elseif barCfg.barType == "charge" then
        local chargeSlider = AceGUI:Create("Slider")
        chargeSlider:SetLabel(L.mbMaxCharges)
        chargeSlider:SetSliderValues(0, 10, 1)
        chargeSlider:SetValue(barCfg.maxCharges or 0)
        chargeSlider:SetFullWidth(true)
        chargeSlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.maxCharges = math.floor(val)
            MB:RebuildAllBars()
        end)
        container:AddChild(chargeSlider)
    end

    AddMonitorHeading(container, L.mbSpecs)

    local specGroup = AceGUI:Create("SimpleGroup")
    specGroup:SetFullWidth(true)
    specGroup:SetLayout(MONITOR_BARS_SPEC_LAYOUT)
    container:AddChild(specGroup)

    local specs = barCfg.specs or {}
    local numSpecs = GetNumSpecializations() or 4

    for i = 1, numSpecs do
        local _, specName = GetSpecializationInfo(i)
        if specName then
            local specCB = AceGUI:Create("CheckBox")
            specCB:SetLabel(specName)
            specCB:SetWidth(math.ceil(specCB.text:GetStringWidth() + 30))
            local found = false
            for _, s in ipairs(specs) do
                if s == i then found = true; break end
            end
            specCB:SetValue(#specs == 0 or found)
            specCB:SetCallback("OnValueChanged", function(_, _, val)
                local newSpecs = {}
                for j = 1, numSpecs do
                    local checked = (j == i) and val
                    if j ~= i then
                        for _, s in ipairs(barCfg.specs or {}) do
                            if s == j then checked = true; break end
                        end
                    end
                    if checked then newSpecs[#newSpecs + 1] = j end
                end
                barCfg.specs = newSpecs
                MB:RebuildAllBars()
            end)
            specGroup:AddChild(specCB)
        end
    end
    AddMonitorHeading(container, L.generalSettings)

    local styleGroup = AceGUI:Create("SimpleGroup")
    styleGroup:SetFullWidth(true)
    styleGroup:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
    container:AddChild(styleGroup)

    local directionRow = AddTwoColumnRow(styleGroup)

    local verticalCB = AceGUI:Create("CheckBox")
    verticalCB:SetLabel(L.mbVerticalBar or "Vertical Monitor")
    verticalCB:SetValue(barCfg.verticalBar == true)
    verticalCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    verticalCB:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.verticalBar = (val == true)
        MB:RebuildAllBars()
    end)
    directionRow:AddChild(verticalCB)

    local reverseCB = AceGUI:Create("CheckBox")
    reverseCB:SetLabel(L.mbReverseGrowth or "Reverse Growth")
    reverseCB:SetValue(barCfg.reverseGrowth == true)
    reverseCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    reverseCB:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.reverseGrowth = (val == true)
        MB:RebuildAllBars()
    end)
    directionRow:AddChild(reverseCB)

    local strataDD = AceGUI:Create("Dropdown")
    strataDD:SetLabel(L.mbFrameStrata)
    strataDD:SetList(STRATA_ITEMS, STRATA_ORDER)
    strataDD:SetValue(barCfg.frameStrata or "MEDIUM")
    strataDD:SetFullWidth(true)
    strataDD:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.frameStrata = val
        MB:RebuildAllBars()
    end)
    styleGroup:AddChild(strataDD)

    if barCfg.barType == "stack" then
        local maxSlider = AceGUI:Create("Slider")
        maxSlider:SetLabel(L.mbMaxStacks)
        maxSlider:SetSliderValues(1, 30, 1)
        maxSlider:SetValue(barCfg.maxStacks or 5)
        maxSlider:SetFullWidth(true)
        maxSlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.maxStacks = math.floor(val)
            MB:RebuildAllBars()
        end)
        styleGroup:AddChild(maxSlider)
    end

    local wSlider = AceGUI:Create("Slider")
    wSlider:SetLabel(L.mbBarWidth)
    wSlider:SetSliderValues(5, 500, 1)
    wSlider:SetValue(barCfg.width)
    wSlider:SetFullWidth(true)
    wSlider:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.width = RoundToOneDecimal(val)
        MB:RebuildAllBars()
    end)
    styleGroup:AddChild(wSlider)

    local hSlider = AceGUI:Create("Slider")
    hSlider:SetLabel(L.mbBarHeight)
    hSlider:SetSliderValues(5, 500, 0.1)
    hSlider:SetValue(barCfg.height)
    hSlider:SetFullWidth(true)
    hSlider:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.height = RoundToOneDecimal(val)
        MB:RebuildAllBars()
    end)
    styleGroup:AddChild(hSlider)

    local syncingPositionSliders = false

    local posXSlider = AceGUI:Create("Slider")
    posXSlider:SetLabel(L.mbBarOffsetX)
    posXSlider:SetSliderValues(-1000, 1000, 0.1)
    posXSlider:SetValue(RoundToOneDecimal(barCfg.posX or 0))
    posXSlider:SetFullWidth(true)
    posXSlider:SetCallback("OnValueChanged", function(_, _, val)
        if syncingPositionSliders then
            return
        end
        barCfg.posX = RoundToOneDecimal(val)
        RefreshPosition()
    end)
    styleGroup:AddChild(posXSlider)

    local posYSlider = AceGUI:Create("Slider")
    posYSlider:SetLabel(L.mbBarOffsetY)
    posYSlider:SetSliderValues(-600, 600, 0.1)
    posYSlider:SetValue(RoundToOneDecimal(barCfg.posY or 0))
    posYSlider:SetFullWidth(true)
    posYSlider:SetCallback("OnValueChanged", function(_, _, val)
        if syncingPositionSliders then
            return
        end
        barCfg.posY = RoundToOneDecimal(val)
        RefreshPosition()
    end)
    styleGroup:AddChild(posYSlider)

    barCfg._smbSyncPositionSliders = function(posX, posY)
        syncingPositionSliders = true
        posXSlider:SetValue(RoundToOneDecimal(posX or 0))
        posYSlider:SetValue(RoundToOneDecimal(posY or 0))
        syncingPositionSliders = false
    end

    AddMonitorHeading(styleGroup, "材质染色")

    local hasTextureDropdown = false
    local texItems, texOrder = GetTextureItems()
    if next(texItems) then
        hasTextureDropdown = true
        local texDD = AceGUI:Create("Dropdown")
        texDD:SetLabel(L.mbBarTexture)
        texDD:SetList(texItems, texOrder, TEXTURE_DROPDOWN_ITEM_TYPE)
        EnhanceTextureDropdown(texDD)
        texDD:SetValue(barCfg.barTexture or "Solid")
        texDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        texDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.barTexture = val
            MB:RebuildAllBars()
        end)
        styleGroup:AddChild(texDD)
    end

    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel(L.mbBarColor)
    barColorPicker:SetHasAlpha(true)
    if hasTextureDropdown then
        barColorPicker:SetRelativeWidth(0.48)
    else
        barColorPicker:SetFullWidth(true)
    end
    local bc = barCfg.barColor or { 0.4, 0.75, 1.0, 1 }
    barColorPicker:SetColor(bc[1], bc[2], bc[3], bc[4])
    local function OnBarColor(_, _, r, g, b, a)
        barCfg.barColor = { r, g, b, a }
        MB:RebuildAllBars()
    end
    barColorPicker:SetCallback("OnValueChanged", OnBarColor)
    barColorPicker:SetCallback("OnValueConfirmed", OnBarColor)
    styleGroup:AddChild(barColorPicker)

    if barCfg.barType ~= "duration" then
        local thresholdColorRow = AceGUI:Create("SimpleGroup")
        thresholdColorRow:SetFullWidth(true)
        thresholdColorRow:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
        styleGroup:AddChild(thresholdColorRow)

        local thresholdColorPicker = AceGUI:Create("ColorPicker")
        thresholdColorPicker:SetLabel(L.mbThresholdColor)
        thresholdColorPicker:SetHasAlpha(true)
        thresholdColorPicker:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        local tc = barCfg.thresholdColor or { 1.0, 1.0, 1.0, 1 }
        thresholdColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
        local function OnThresholdColor(_, _, r, g, b, a)
            barCfg.thresholdColor = { r, g, b, a }
            MB:RebuildAllBars()
        end
        thresholdColorPicker:SetCallback("OnValueChanged", OnThresholdColor)
        thresholdColorPicker:SetCallback("OnValueConfirmed", OnThresholdColor)
        thresholdColorRow:AddChild(thresholdColorPicker)

        local thresholdSlider2, thresholdColorPicker2

        thresholdColorPicker2 = AceGUI:Create("ColorPicker")
        thresholdColorPicker2:SetLabel(L.mbThresholdColor2)
        thresholdColorPicker2:SetHasAlpha(true)
        thresholdColorPicker2:SetRelativeWidth(0.48)
        local tc2 = barCfg.thresholdColor2 or { 1.0, 1.0, 0.0, 1 }
        thresholdColorPicker2:SetColor(tc2[1], tc2[2], tc2[3], tc2[4])
        thresholdColorPicker2:SetDisabled((barCfg.colorThreshold or 0) == 0)
        local function OnThresholdColor2(_, _, r, g, b, a)
            barCfg.thresholdColor2 = { r, g, b, a }
            MB:RebuildAllBars()
        end
        thresholdColorPicker2:SetCallback("OnValueChanged", OnThresholdColor2)
        thresholdColorPicker2:SetCallback("OnValueConfirmed", OnThresholdColor2)
        thresholdColorRow:AddChild(thresholdColorPicker2)

        local maxVal
        if barCfg.barType == "charge" then
            maxVal = (barCfg.maxCharges > 0 and barCfg.maxCharges or 10)
        elseif barCfg.barType == "duration" then
            maxVal = (barCfg.maxDuration or 60)
        else
            maxVal = (barCfg.maxStacks or 30)
        end
        local thresholdSlider = AceGUI:Create("Slider")
        thresholdSlider:SetLabel(L.mbColorThreshold)
        thresholdSlider:SetSliderValues(0, maxVal, barCfg.barType == "duration" and 0.1 or 1)
        thresholdSlider:SetValue(barCfg.colorThreshold or 0)
        thresholdSlider:SetFullWidth(true)
        thresholdSlider:SetCallback("OnValueChanged", function(_, _, val)
            local newVal = barCfg.barType == "duration" and (math.floor(val * 10 + 0.5) / 10) or math.floor(val)
            barCfg.colorThreshold = newVal
            MB:RebuildAllBars()

            if thresholdSlider2 then
                thresholdSlider2:SetDisabled(newVal == 0)
            end
            if thresholdColorPicker2 then
                thresholdColorPicker2:SetDisabled(newVal == 0)
            end
        end)
        styleGroup:AddChild(thresholdSlider)

        thresholdSlider2 = AceGUI:Create("Slider")
        thresholdSlider2:SetLabel(L.mbColorThreshold2)
        thresholdSlider2:SetSliderValues(0, maxVal, barCfg.barType == "duration" and 0.1 or 1)
        thresholdSlider2:SetValue(barCfg.colorThreshold2 or 0)
        thresholdSlider2:SetFullWidth(true)
        thresholdSlider2:SetDisabled((barCfg.colorThreshold or 0) == 0)
        thresholdSlider2:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.colorThreshold2 = barCfg.barType == "duration" and (math.floor(val * 10 + 0.5) / 10) or math.floor(val)
            MB:RebuildAllBars()
        end)
        styleGroup:AddChild(thresholdSlider2)
    end

    local colorRow = AceGUI:Create("SimpleGroup")
    colorRow:SetFullWidth(true)
    colorRow:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
    styleGroup:AddChild(colorRow)

    local bgColorPicker = AceGUI:Create("ColorPicker")
    bgColorPicker:SetLabel(L.mbBgColor)
    bgColorPicker:SetHasAlpha(true)
    bgColorPicker:SetRelativeWidth(0.48)
    local bgc = barCfg.bgColor or { 0.1, 0.1, 0.1, 0.6 }
    bgColorPicker:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
    local function OnBgColor(_, _, r, g, b, a)
        barCfg.bgColor = { r, g, b, a }
        MB:RebuildAllBars()
    end
    bgColorPicker:SetCallback("OnValueChanged", OnBgColor)
    bgColorPicker:SetCallback("OnValueConfirmed", OnBgColor)
    colorRow:AddChild(bgColorPicker)

    local borderColorPicker = AceGUI:Create("ColorPicker")
    borderColorPicker:SetLabel(L.mbBorderColor)
    borderColorPicker:SetHasAlpha(true)
    borderColorPicker:SetRelativeWidth(0.48)
    local bdc = barCfg.borderColor or { 0, 0, 0, 1 }
    borderColorPicker:SetColor(bdc[1], bdc[2], bdc[3], bdc[4])
    local function OnBorderColor(_, _, r, g, b, a)
        barCfg.borderColor = { r, g, b, a }
        MB:RebuildAllBars()
    end
    borderColorPicker:SetCallback("OnValueChanged", OnBorderColor)
    borderColorPicker:SetCallback("OnValueConfirmed", OnBorderColor)
    colorRow:AddChild(borderColorPicker)


    if barCfg.barType ~= "duration" then
        local borderRow = AceGUI:Create("SimpleGroup")
        borderRow:SetFullWidth(true)
        borderRow:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
        styleGroup:AddChild(borderRow)
        local mbsDD

        local borderStyleDD = AceGUI:Create("Dropdown")
        borderStyleDD:SetLabel(L.mbBorderStyle)
        borderStyleDD:SetList(BORDER_STYLE_ITEMS, { "none", "whole", "segment" })
        borderStyleDD:SetValue(barCfg.borderStyle or "whole")
        borderStyleDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        borderStyleDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.borderStyle = val
            mbsDD:SetDisabled(val == "none")
            MB:RebuildAllBars()
        end)
        borderRow:AddChild(borderStyleDD)

        mbsDD = AceGUI:Create("Dropdown")
        mbsDD:SetLabel(L.mbMaskAndBorderStyle or "Border Width")
        mbsDD:SetList(MASK_AND_BORDER_STYLE_ITEMS, { "0", "1", "2", "3", "4", "5" })
        mbsDD:SetValue(barCfg.maskAndBorderStyle or "1")
        mbsDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        mbsDD:SetDisabled((barCfg.borderStyle or "whole") == "none")
        mbsDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.maskAndBorderStyle = val
            MB:RebuildAllBars()
        end)
        borderRow:AddChild(mbsDD)
    end


    if barCfg.barType ~= "duration" then
        local gapSlider = AceGUI:Create("Slider")
        gapSlider:SetLabel(L.mbSegmentGap)
        gapSlider:SetSliderValues(0, 10, 1)
        gapSlider:SetValue(barCfg.segmentGap ~= nil and barCfg.segmentGap or 1)
        gapSlider:SetFullWidth(true)
        gapSlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.segmentGap = math.floor(val)
            MB:RebuildAllBars()
        end)
        styleGroup:AddChild(gapSlider)
    end

    AddMonitorHeading(styleGroup, "技能文字")

    local skillToggleRow = AddTwoColumnRow(styleGroup)
    skillToggleRow.noAutoHeight = true
    skillToggleRow:SetHeight(COMPACT_ROW_HEIGHT)

    local nameCB = AceGUI:Create("CheckBox")
    nameCB:SetLabel(L.mbShowSpellName or "Show Spell Name")
    nameCB:SetValue(barCfg.showSpellName or false)
    nameCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    skillToggleRow:AddChild(nameCB)

    local iconCB = AceGUI:Create("CheckBox")
    iconCB:SetLabel(L.mbShowIcon)
    iconCB:SetValue(barCfg.showIcon ~= false)
    iconCB:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    iconCB:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.showIcon = val
        Refresh()
    end)
    skillToggleRow:AddChild(iconCB)

    local nameRow = AddTwoColumnRow(styleGroup)

    local nameOutlineDD = AceGUI:Create("Dropdown")
    nameOutlineDD:SetLabel(L.mbNameOutline or "Name Outline")
    nameOutlineDD:SetList(OUTLINE_ITEMS, { "NONE", "OUTLINE", "THICKOUTLINE" })
    nameOutlineDD:SetValue(barCfg.nameOutline or barCfg.outline or "OUTLINE")
    nameOutlineDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    nameRow:AddChild(nameOutlineDD)

    local nAnchorDD = AceGUI:Create("Dropdown")
    nAnchorDD:SetLabel(L.mbNameAnchor or "Name Anchor")
    nAnchorDD:SetList(TEXT_ANCHOR_ITEMS, TEXT_ANCHOR_ORDER)
    nAnchorDD:SetValue(barCfg.nameAnchor or "RIGHT")
    nAnchorDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
    nameRow:AddChild(nAnchorDD)

    local nTxSlider = AceGUI:Create("Slider")
    nTxSlider:SetLabel(L.mbNameOffsetX or "Name Offset X")
    nTxSlider:SetSliderValues(-100, 100, 1)
    nTxSlider:SetValue(barCfg.nameOffsetX or 0)
    nTxSlider:SetFullWidth(true)
    styleGroup:AddChild(nTxSlider)

    local nTySlider = AceGUI:Create("Slider")
    nTySlider:SetLabel(L.mbNameOffsetY or "Name Offset Y")
    nTySlider:SetSliderValues(-100, 100, 1)
    nTySlider:SetValue(barCfg.nameOffsetY or 0)
    nTySlider:SetFullWidth(true)
    styleGroup:AddChild(nTySlider)

    local nameFontDD
    local nFontSizeSlider = AceGUI:Create("Slider")
    local fontItems, fontOrder = GetFontItems()
    if next(fontItems) then
        local nameFontRow = AddTwoColumnRow(styleGroup)

        nameFontDD = AceGUI:Create("Dropdown")
        nameFontDD:SetLabel(L.mbNameFontFamily or L.fontFamily)
        nameFontDD:SetList(fontItems, fontOrder)
        nameFontDD:SetValue(barCfg.nameFontName ~= "" and barCfg.nameFontName or nil)
        nameFontDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        nameFontRow:AddChild(nameFontDD)

        nFontSizeSlider:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        nameFontRow:AddChild(nFontSizeSlider)
    else
        nFontSizeSlider:SetFullWidth(true)
        styleGroup:AddChild(nFontSizeSlider)
    end

    nFontSizeSlider:SetLabel(L.mbNameFontSize or "Name Font Size")
    nFontSizeSlider:SetSliderValues(6, 24, 1)
    nFontSizeSlider:SetValue(barCfg.nameFontSize or 14)

    local function SetSkillNameControlsDisabled(disabled)
        nameOutlineDD:SetDisabled(disabled)
        nAnchorDD:SetDisabled(disabled)
        nTxSlider:SetDisabled(disabled)
        nTySlider:SetDisabled(disabled)
        nFontSizeSlider:SetDisabled(disabled)
        if nameFontDD then
            nameFontDD:SetDisabled(disabled)
        end
    end

    nameCB:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.showSpellName = val
        SetSkillNameControlsDisabled(not val)
        Refresh()
    end)

    nameOutlineDD:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.nameOutline = val
        Refresh()
    end)

    nAnchorDD:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.nameAnchor = val
        Refresh()
    end)

    nTxSlider:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.nameOffsetX = math.floor(val)
        Refresh()
    end)

    nTySlider:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.nameOffsetY = math.floor(val)
        Refresh()
    end)

    if nameFontDD then
        nameFontDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.nameFontName = val
            Refresh()
        end)
    end

    nFontSizeSlider:SetCallback("OnValueChanged", function(_, _, val)
        barCfg.nameFontSize = math.floor(val)
        Refresh()
    end)

    SetSkillNameControlsDisabled(not (barCfg.showSpellName or false))

    local fontItems, fontOrder = GetFontItems()

    if barCfg.barType == "stack" or barCfg.barType == "charge" or barCfg.barType == "duration" then
        AddMonitorHeading(styleGroup, L.mbCountTextHeading or "层数文字")

        local countTextCB = AceGUI:Create("CheckBox")
        local SetCountTextControlsDisabled
        countTextCB:SetLabel(L.mbShowCountText or "显示层数文字")
        countTextCB:SetValue(barCfg.showCountText == true)
        countTextCB:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.showCountText = val
            SetCountTextControlsDisabled(not val)
            Refresh()
        end)
        countTextCB:SetFullWidth(true)
        styleGroup:AddChild(countTextCB)

        local countTextRow = AceGUI:Create("SimpleGroup")
        countTextRow:SetFullWidth(true)
        countTextRow:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
        styleGroup:AddChild(countTextRow)

        local countOutlineDD = AceGUI:Create("Dropdown")
        countOutlineDD:SetLabel(L.mbCountTextOutline or "层数文字描边")
        countOutlineDD:SetList(OUTLINE_ITEMS, { "NONE", "OUTLINE", "THICKOUTLINE" })
        countOutlineDD:SetValue(barCfg.countOutline or "OUTLINE")
        countOutlineDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        countOutlineDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.countOutline = val
            Refresh()
        end)
        countTextRow:AddChild(countOutlineDD)

        local countAnchorDD = AceGUI:Create("Dropdown")
        countAnchorDD:SetLabel(L.mbCountTextAnchor or "层数文字锚点")
        countAnchorDD:SetList(TEXT_ANCHOR_ITEMS, TEXT_ANCHOR_ORDER)
        countAnchorDD:SetValue(barCfg.countTextAnchor or "LEFT")
        countAnchorDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        countAnchorDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.countTextAnchor = val
            Refresh()
        end)
        countTextRow:AddChild(countAnchorDD)

        local countXSlider = AceGUI:Create("Slider")
        countXSlider:SetLabel(L.mbCountTextOffsetX or "层数文字X偏移")
        countXSlider:SetSliderValues(-100, 100, 1)
        countXSlider:SetValue(barCfg.countTextOffsetX or 0)
        countXSlider:SetFullWidth(true)
        countXSlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.countTextOffsetX = math.floor(val)
            Refresh()
        end)
        styleGroup:AddChild(countXSlider)

        local countYSlider = AceGUI:Create("Slider")
        countYSlider:SetLabel(L.mbCountTextOffsetY or "层数文字Y偏移")
        countYSlider:SetSliderValues(-100, 100, 1)
        countYSlider:SetValue(barCfg.countTextOffsetY or 0)
        countYSlider:SetFullWidth(true)
        countYSlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.countTextOffsetY = math.floor(val)
            Refresh()
        end)
        styleGroup:AddChild(countYSlider)

        local countFontDD
        local countFontSizeSlider
        if next(fontItems) then
            local countFontRow = AddTwoColumnRow(styleGroup)

            countFontDD = AceGUI:Create("Dropdown")
            countFontDD:SetLabel(L.mbCountTextFontFamily or "层数文字字体")
            countFontDD:SetList(fontItems, fontOrder)
            countFontDD:SetValue(barCfg.countFontName ~= "" and barCfg.countFontName or nil)
            countFontDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
            countFontDD:SetCallback("OnValueChanged", function(_, _, val)
                barCfg.countFontName = val
                Refresh()
            end)
            countFontRow:AddChild(countFontDD)

            countFontSizeSlider = AceGUI:Create("Slider")
            countFontSizeSlider:SetLabel(L.mbCountTextFontSize or "层数文字字号")
            countFontSizeSlider:SetSliderValues(6, 24, 1)
            countFontSizeSlider:SetValue(barCfg.countFontSize or 14)
            countFontSizeSlider:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
            countFontSizeSlider:SetCallback("OnValueChanged", function(_, _, val)
                barCfg.countFontSize = math.floor(val)
                Refresh()
            end)
            countFontRow:AddChild(countFontSizeSlider)
        else
            countFontSizeSlider = AceGUI:Create("Slider")
            countFontSizeSlider:SetLabel(L.mbCountTextFontSize or "层数文字字号")
            countFontSizeSlider:SetSliderValues(6, 24, 1)
            countFontSizeSlider:SetValue(barCfg.countFontSize or 14)
            countFontSizeSlider:SetFullWidth(true)
            countFontSizeSlider:SetCallback("OnValueChanged", function(_, _, val)
                barCfg.countFontSize = math.floor(val)
                Refresh()
            end)
            styleGroup:AddChild(countFontSizeSlider)
        end

        SetCountTextControlsDisabled = function(disabled)
            countOutlineDD:SetDisabled(disabled)
            countAnchorDD:SetDisabled(disabled)
            countXSlider:SetDisabled(disabled)
            countYSlider:SetDisabled(disabled)
            if countFontDD then
                countFontDD:SetDisabled(disabled)
            end
            if countFontSizeSlider then
                countFontSizeSlider:SetDisabled(disabled)
            end
        end

        SetCountTextControlsDisabled(barCfg.showCountText ~= true)
    end

    if barCfg.barType == "charge" or barCfg.barType == "duration" then
        AddMonitorHeading(styleGroup, L.mbTimeTextHeading or "时间文字")

        local textCB = AceGUI:Create("CheckBox")
        local SetTextControlsDisabled
        local showTextLabel
        if barCfg.barType == "charge" then
            showTextLabel = L.mbShowTextCharge
        else
            showTextLabel = L.mbShowTextDuration or "Show Duration Text"
        end
        textCB:SetLabel(showTextLabel)
        textCB:SetValue(barCfg.showText ~= false)
        textCB:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.showText = val
            SetTextControlsDisabled(not val)
            Refresh()
        end)
        textCB:SetFullWidth(true)
        styleGroup:AddChild(textCB)

        local textRow = AceGUI:Create("SimpleGroup")
        textRow:SetFullWidth(true)
        textRow:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
        styleGroup:AddChild(textRow)

        local outlineDD = AceGUI:Create("Dropdown")
        outlineDD:SetLabel(L.mbTimeTextOutline or L.outline)
        outlineDD:SetList(OUTLINE_ITEMS, { "NONE", "OUTLINE", "THICKOUTLINE" })
        outlineDD:SetValue(barCfg.outline or "OUTLINE")
        outlineDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        outlineDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.outline = val
            Refresh()
        end)
        textRow:AddChild(outlineDD)

        local anchorDD = AceGUI:Create("Dropdown")
        anchorDD:SetLabel(L.mbTimeTextAnchor or L.mbTextAnchor)
        anchorDD:SetList(TEXT_ANCHOR_ITEMS, TEXT_ANCHOR_ORDER)
        anchorDD:SetValue(barCfg.textAnchor or barCfg.textAlign or "CENTER")
        anchorDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
        anchorDD:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.textAnchor = val
            Refresh()
        end)
        textRow:AddChild(anchorDD)

        local txSlider = AceGUI:Create("Slider")
        txSlider:SetLabel(L.mbTimeTextOffsetX or L.mbTextOffsetX)
        txSlider:SetSliderValues(-100, 100, 1)
        txSlider:SetValue(barCfg.textOffsetX or -5)
        txSlider:SetFullWidth(true)
        txSlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.textOffsetX = math.floor(val)
            Refresh()
        end)
        styleGroup:AddChild(txSlider)

        local tySlider = AceGUI:Create("Slider")
        tySlider:SetLabel(L.mbTimeTextOffsetY or L.mbTextOffsetY)
        tySlider:SetSliderValues(-100, 100, 1)
        tySlider:SetValue(barCfg.textOffsetY or 0)
        tySlider:SetFullWidth(true)
        tySlider:SetCallback("OnValueChanged", function(_, _, val)
            barCfg.textOffsetY = math.floor(val)
            Refresh()
        end)
        styleGroup:AddChild(tySlider)

        local fontDD
        local fontSizeSlider
        if next(fontItems) then
            local fontRow = AddTwoColumnRow(styleGroup)

            fontDD = AceGUI:Create("Dropdown")
            fontDD:SetLabel(L.mbTimeTextFontFamily or L.fontFamily)
            fontDD:SetList(fontItems, fontOrder)
            fontDD:SetValue(barCfg.fontName ~= "" and barCfg.fontName or nil)
            fontDD:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
            fontDD:SetCallback("OnValueChanged", function(_, _, val)
                barCfg.fontName = val
                Refresh()
            end)
            fontRow:AddChild(fontDD)

            fontSizeSlider = AceGUI:Create("Slider")
            fontSizeSlider:SetLabel(L.mbTimeTextFontSize or L.fontSize)
            fontSizeSlider:SetSliderValues(6, 24, 1)
            fontSizeSlider:SetValue(barCfg.fontSize or 14)
            fontSizeSlider:SetRelativeWidth(HALF_CONTROL_RELATIVE_WIDTH)
            fontSizeSlider:SetCallback("OnValueChanged", function(_, _, val)
                barCfg.fontSize = math.floor(val)
                Refresh()
            end)
            fontRow:AddChild(fontSizeSlider)
        else
            fontSizeSlider = AceGUI:Create("Slider")
            fontSizeSlider:SetLabel(L.mbTimeTextFontSize or L.fontSize)
            fontSizeSlider:SetSliderValues(6, 24, 1)
            fontSizeSlider:SetValue(barCfg.fontSize or 14)
            fontSizeSlider:SetFullWidth(true)
            fontSizeSlider:SetCallback("OnValueChanged", function(_, _, val)
                barCfg.fontSize = math.floor(val)
                Refresh()
            end)
            styleGroup:AddChild(fontSizeSlider)
        end

        SetTextControlsDisabled = function(disabled)
            outlineDD:SetDisabled(disabled)
            anchorDD:SetDisabled(disabled)
            txSlider:SetDisabled(disabled)
            tySlider:SetDisabled(disabled)
            if fontDD then
                fontDD:SetDisabled(disabled)
            end
            if fontSizeSlider then
                fontSizeSlider:SetDisabled(disabled)
            end
        end

        SetTextControlsDisabled(barCfg.showText == false)
    end

end

local catalogFrame = nil

local function CloseCatalogFrame()
    if catalogFrame then
        catalogFrame:Release()
        catalogFrame = nil
    end
    ns._catalogFrame = nil
end

ns._closeCatalogFrame = CloseCatalogFrame
ns._refreshCatalogToggle = nil

local function BuildSpecSpellMap()
    local specSpellMap = {}
    local numSpecs = GetNumSpecializations() or 0

    for specIndex = 1, numSpecs do
        local spells = {}
        local entries = { GetSpecializationSpells(specIndex) }
        for i = 1, #entries, 2 do
            local spellID = entries[i]
            if type(spellID) == "number" and spellID > 0 then
                spells[spellID] = true

                if C_Spell and C_Spell.GetBaseSpell then
                    local baseSpellID = C_Spell.GetBaseSpell(spellID)
                    if type(baseSpellID) == "number" and baseSpellID > 0 then
                        spells[baseSpellID] = true
                    end
                end
            end
        end
        specSpellMap[specIndex] = spells
    end

    return specSpellMap
end

local function GetMatchingSpecsForSpell(specSpellMap, spellID)
    local matchedSpecs = {}
    if not spellID or spellID <= 0 then
        return matchedSpecs
    end

    for specIndex, spells in pairs(specSpellMap) do
        if spells and spells[spellID] then
            matchedSpecs[#matchedSpecs + 1] = specIndex
        end
    end

    return matchedSpecs
end

local function ShowCatalog(rebuildTab)
    if InCombatLockdown() then
        print("|cff00ccff[SimpleMonitorBars]|r " .. L.mbScanCombatWarn)
        return
    end

    MB:ScanCDMViewers()
    local cooldowns, auras = MB:GetSpellCatalog()
    local iciclesName = C_Spell.GetSpellName(ICICLES_SPELL_ID) or "小冰刺"
    local iciclesIcon = C_Spell.GetSpellTexture(ICICLES_SPELL_ID)

    local function ContainsSpell(entries, spellID)
        for _, entry in ipairs(entries or {}) do
            if entry.spellID == spellID then
                return true
            end
        end
        return false
    end

    local currentSpec = GetSpecialization() or 1
    local numSpecs = GetNumSpecializations() or 0
    local specSpellMap = BuildSpecSpellMap()
    local specialEntries = {}
    if PLAYER_CLASS_TAG == "MAGE"
        and currentSpec == 1
        and not ContainsSpell(cooldowns, ICICLES_SPELL_ID)
        and not ContainsSpell(auras, ICICLES_SPELL_ID) then
        specialEntries[#specialEntries + 1] = {
            spellID = ICICLES_SPELL_ID,
            name = iciclesName,
            icon = iciclesIcon,
            unit = "player",
            barType = "stack",
        }
    end

    CloseCatalogFrame()

    local cfg = ns.db.monitorBars
    local TEMPLATE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

    local function AddBar(spellID, spellName, barType, unit)
        local id = cfg.nextID or (#cfg.bars + 1)
        cfg.nextID = id + 1
        local bar = NewBarDefaults(id, barType, spellID, spellName, unit)
        if barType == "charge" then
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            bar.isChargeSpell = (chargeInfo ~= nil)
            if chargeInfo and chargeInfo.maxCharges then
                if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
                    bar.maxCharges = chargeInfo.maxCharges
                end
            end
        end
        table.insert(cfg.bars, bar)
        selectedBarID = id
        MB:RebuildAllBars()
        if rebuildTab then rebuildTab() end
        print("|cff00ccff[SimpleMonitorBars]|r " .. string.format(L.mbAdded, spellName ~= "" and spellName or tostring(spellID)))
    end

    local function AddTemplateBar(barType, templateName)
        local id = cfg.nextID or (#cfg.bars + 1)
        cfg.nextID = id + 1

        local bar = NewBarDefaults(id, barType, 0, "", "player")
        bar.showCondition = "always"
        table.insert(cfg.bars, bar)

        selectedBarID = id
        MB:RebuildAllBars()
        if rebuildTab then rebuildTab() end
        print("|cff00ccff[SimpleMonitorBars]|r " .. string.format(L.mbAdded, templateName))
    end

    local skillEntries = {}
    local auraEntries = {}
    local templateEntries = {
        {
            spellID = 0,
            name = L.mbTemplateStack or "层数条模版",
            icon = TEMPLATE_ICON,
            unit = "player",
            barType = "stack",
            monitored = false,
        },
        {
            spellID = 0,
            name = L.mbTemplateCharge or "充能条模版",
            icon = TEMPLATE_ICON,
            unit = "player",
            barType = "charge",
            monitored = false,
        },
        {
            spellID = 0,
            name = L.mbTemplateDuration or "时间条模版",
            icon = TEMPLATE_ICON,
            unit = "player",
            barType = "duration",
            monitored = false,
        },
    }
    local monitoredSpellIDs = {}
    for _, bar in ipairs(cfg.bars or {}) do
        if bar and bar.spellID and bar.spellID > 0 then
            monitoredSpellIDs[bar.spellID] = true
        end
    end

    local function AddCatalogEntry(target, entry, barType)
        target[#target + 1] = {
            spellID = entry.spellID,
            name = entry.name,
            icon = entry.icon,
            unit = entry.unit,
            barType = barType,
            monitored = monitoredSpellIDs[entry.spellID] == true,
        }
    end

    local function ClassifyCatalogEntry(target, entry, barType)
        local matchedSpecs = GetMatchingSpecsForSpell(specSpellMap, entry.spellID)
        local isCurrentSpecOnly = (#matchedSpecs > 0 and #matchedSpecs < numSpecs)

        if isCurrentSpecOnly then
            for _, specIndex in ipairs(matchedSpecs) do
                if specIndex == currentSpec then
                    AddCatalogEntry(target, entry, barType)
                    return
                end
            end
        end

        AddCatalogEntry(target, entry, barType)
    end

    for _, entry in ipairs(cooldowns) do
        ClassifyCatalogEntry(skillEntries, entry, "charge")
    end
    for _, entry in ipairs(auras) do
        ClassifyCatalogEntry(auraEntries, entry, "stack")
    end
    for _, entry in ipairs(specialEntries) do
        ClassifyCatalogEntry(auraEntries, entry, entry.barType or "stack")
    end

    local function SortEntries(entries)
        table.sort(entries, function(a, b)
            return (a.name or "") < (b.name or "")
        end)
    end

    SortEntries(skillEntries)
    SortEntries(auraEntries)

    catalogFrame = ns.UI.OpenSpellCatalogFrame(
        L.mbScanCatalog,
        {
            {
                heading  = L.mbTemplateSection or "模版",
                entries  = templateEntries,
                onSelect = function(entry)
                    AddTemplateBar(entry.barType or "stack", entry.name or "")
                end,
            },
            {
                heading  = L.mbSkillSection or "技能",
                entries  = skillEntries,
                onSelect = function(entry)
                    AddBar(entry.spellID, entry.name, entry.barType or "charge", entry.unit or "player")
                end,
            },
            {
                heading  = L.mbAuraSection or "光环",
                entries  = auraEntries,
                onSelect = function(entry)
                    AddBar(entry.spellID, entry.name, entry.barType or "charge", entry.unit or "player")
                end,
            },
        },
        function(spellID, spellName)
            AddBar(spellID, spellName, "charge", "player")
        end
    )
    ns._catalogFrame = catalogFrame
    catalogFrame:SetCallback("OnClose", function(w)
        ns._catalogFrame = nil
        catalogFrame = nil
        if ns._refreshCatalogToggle then
            ns._refreshCatalogToggle()
        end
        w:Release()
    end)
end

function ns.BuildMonitorTab(scroll)
    -- Top-level tab builder; rebuilding this function refreshes dependent controls.
    AceGUI = AceGUI or LibStub("AceGUI-3.0")
    LSM = LSM or LibStub("LibSharedMedia-3.0", true)
    RegisterTextureDropdownItem()
    RegisterMonitorBarsFlowLayout()
    RegisterMonitorBarsSpecLayout()

    local cfg = ns.db.monitorBars
    if not cfg then return end

    local function RebuildContent()
        scroll:ReleaseChildren()
        ns.BuildMonitorTab(scroll)
        if scroll and scroll.DoLayout then
            scroll:DoLayout()
        end
    end

    local addBtn = AceGUI:Create("Button")
    local function RefreshCatalogButtonText()
        addBtn:SetText((ns._catalogFrame and (L.mbCloseCatalog or "关闭读取技能目录")) or L.mbAddBar)
    end
    RefreshCatalogButtonText()
    ns._refreshCatalogToggle = RefreshCatalogButtonText
    addBtn:SetHeight(48)
    addBtn:SetFullWidth(true)
    addBtn:SetCallback("OnClick", function()
        if ns._catalogFrame then
            CloseCatalogFrame()
        else
            ShowCatalog(RebuildContent)
        end
        RefreshCatalogButtonText()
    end)
    scroll:AddChild(addBtn)

    local addHintTopSpacer = AceGUI:Create("Label")
    addHintTopSpacer:SetText("")
    addHintTopSpacer:SetFullWidth(true)
    addHintTopSpacer:SetHeight(SECTION_SPACER_HEIGHT)
    scroll:AddChild(addHintTopSpacer)

    local catalogHintLabel = AceGUI:Create("Label")
    catalogHintLabel:SetText(L.mbCatalogHint or "此列表没有的技能或光环可以尝试用模版输入ID手动添加")
    catalogHintLabel:SetFullWidth(true)
    if catalogHintLabel.label then
        catalogHintLabel.label:SetJustifyH("CENTER")
        catalogHintLabel.label:SetTextColor(1, 1, 1, 1)
    end
    scroll:AddChild(catalogHintLabel)

    local catalogHintBottomSpacer = AceGUI:Create("Label")
    catalogHintBottomSpacer:SetText("")
    catalogHintBottomSpacer:SetFullWidth(true)
    catalogHintBottomSpacer:SetHeight(SECTION_SPACER_HEIGHT)
    scroll:AddChild(catalogHintBottomSpacer)

    local barItems, barOrder, idToIndex = GetBarDropdownList(cfg)
    if #barOrder == 0 then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("\n|cffaaaaaa" .. L.mbNoBar .. "|r")
        emptyLabel:SetFullWidth(true)
        scroll:AddChild(emptyLabel)
        return
    end

    AddMonitorHeading(scroll, L.monitorBars)

    local selectedVisible = selectedBarID and idToIndex[selectedBarID] ~= nil
    local currentSpecDefaultBarID = GetDefaultBarIDForCurrentSpec(cfg, barOrder, idToIndex)
    if selectedVisible then
        -- Keep the user's current selection, including a bar that was just added.
    elseif currentSpecDefaultBarID then
        selectedBarID = currentSpecDefaultBarID
    else
        local noSpecLabel = AceGUI:Create("Label")
        noSpecLabel:SetText("|cffff4444" .. (L.mbNoCurrentSpecBarNotice or "注意：当前专精没有设置监控") .. "|r")
        noSpecLabel:SetFullWidth(true)
        if noSpecLabel.label then
            noSpecLabel.label:SetJustifyH("CENTER")
        end
        scroll:AddChild(noSpecLabel)

        local noSpecSpacer = AceGUI:Create("Label")
        noSpecSpacer:SetText("")
        noSpecSpacer:SetFullWidth(true)
        noSpecSpacer:SetHeight(SECTION_SPACER_HEIGHT)
        scroll:AddChild(noSpecSpacer)

        if not selectedVisible then
            selectedBarID = barOrder[1]
        end
    end
    RefreshSelectedBarNotice()

    local barDD
    local detailHost = AceGUI:Create("SimpleGroup")
    detailHost:SetFullWidth(true)
    detailHost:SetLayout("List")

    local function BuildDetailSection()
        detailHost:ReleaseChildren()

        local selectedIndex = selectedBarID and idToIndex[selectedBarID]
        local barCfg = selectedIndex and cfg.bars[selectedIndex] or nil
        if not barCfg then
            if detailHost.DoLayout then
                detailHost:DoLayout()
            end
            return
        end

        AddDeleteButton(detailHost, barCfg, RebuildContent, barDD)

        local configGroup = AceGUI:Create("SimpleGroup")
        configGroup:SetFullWidth(true)
        configGroup:SetLayout(MONITOR_BARS_FLOW_LAYOUT)
        detailHost:AddChild(configGroup)

        BuildBarConfig(configGroup, barCfg, RebuildContent)

        if detailHost and detailHost.DoLayout then
            detailHost:DoLayout()
        end
        if scroll and scroll.DoLayout then
            scroll:DoLayout()
        end
    end

    barDD = AceGUI:Create("Dropdown")
    barDD:SetLabel("")
    barDD:SetList(barItems, barOrder)
    barDD:SetValue(selectedBarID)
    barDD:SetFullWidth(true)
    barDD:SetCallback("OnValueChanged", function(_, _, val)
        selectedBarID = val
        RefreshSelectedBarNotice()
        BuildDetailSection()
    end)
    NormalizeDropdownToFrame(barDD)
    scroll:AddChild(barDD)
    scroll:AddChild(detailHost)
    BuildDetailSection()

    if scroll and scroll.DoLayout then
        scroll:DoLayout()
    end
end
