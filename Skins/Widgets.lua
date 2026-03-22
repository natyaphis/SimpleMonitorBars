
local _, ns = ...

ns.UI = {}





local function GetAceGUI()
    return LibStub("AceGUI-3.0")
end

function ns.UI.AddHeading(parent, text)
    local AceGUI = GetAceGUI()
    local topSpacer = AceGUI:Create("Label")
    topSpacer:SetText(" ")
    topSpacer:SetFullWidth(true)
    topSpacer:SetFontObject(GameFontHighlightSmall)
    parent:AddChild(topSpacer)

    local w = AceGUI:Create("Heading")
    w:SetText(text)
    w:SetFullWidth(true)
    parent:AddChild(w)

    local bottomSpacer = AceGUI:Create("Label")
    bottomSpacer:SetText(" ")
    bottomSpacer:SetFullWidth(true)
    bottomSpacer:SetFontObject(GameFontHighlightSmall)
    parent:AddChild(bottomSpacer)
end









function ns.UI.OpenSpellCatalogFrame(title, sections, onManualAdd)
    local AceGUI = GetAceGUI()
    local FRAME_WIDTH = 300
    local SIDE_INSET = 14
    local HEADER_BOTTOM_INSET = 42
    local FOOTER_TOP_INSET = 44

    local frame = AceGUI:Create("Frame")
    frame:SetTitle(title)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(510)
    frame:SetLayout("Fill")
    frame:EnableResize(false)

    frame.titlebg:ClearAllPoints()
    frame.titlebg:SetPoint("TOP", frame.frame, "TOP", 0, 4)

    local settingsFrame = ns._settingsFrame and ns._settingsFrame.frame
    if settingsFrame then
        frame.frame:ClearAllPoints()
        frame.frame:SetPoint("TOPRIGHT", settingsFrame, "TOPLEFT", -3, 0)
    end

    local divider = frame.frame:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetPoint("TOPLEFT", frame.frame, "TOPLEFT", SIDE_INSET, -HEADER_BOTTOM_INSET)
    divider:SetPoint("TOPRIGHT", frame.frame, "TOPRIGHT", -SIDE_INSET, -HEADER_BOTTOM_INSET)
    divider:SetHeight(1)

    local bottomDivider = frame.frame:CreateTexture(nil, "BORDER")
    bottomDivider:SetColorTexture(1, 1, 1, 0.12)
    bottomDivider:SetPoint("BOTTOMLEFT", frame.frame, "BOTTOMLEFT", SIDE_INSET, FOOTER_TOP_INSET)
    bottomDivider:SetPoint("BOTTOMRIGHT", frame.frame, "BOTTOMRIGHT", -SIDE_INSET, FOOTER_TOP_INSET)
    bottomDivider:SetHeight(1)

    frame.content:ClearAllPoints()
    frame.content:SetPoint("TOPLEFT", frame.frame, "TOPLEFT", SIDE_INSET, -(HEADER_BOTTOM_INSET + 10))
    frame.content:SetPoint("BOTTOMRIGHT", frame.frame, "BOTTOMRIGHT", -SIDE_INSET, FOOTER_TOP_INSET + 12)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    frame:AddChild(scroll)


    if onManualAdd then
        local manualBox = AceGUI:Create("EditBox")
        manualBox:SetLabel(ns.L and ns.L.spellID or "Spell ID")
        manualBox:SetFullWidth(true)
        manualBox:SetCallback("OnEnterPressed", function(_, _, val)
            local spellID = tonumber(val)
            if not spellID or spellID <= 0 then return end
            local spellName = C_Spell.GetSpellName(spellID) or ""
            onManualAdd(spellID, spellName)
            frame:Release()
        end)
        scroll:AddChild(manualBox)
    end


    local hasAny = false
    for _, section in ipairs(sections) do
        if section.entries and #section.entries > 0 then
            hasAny = true
            if section.heading and section.heading ~= "" then
                local heading = AceGUI:Create("Heading")
                heading:SetText(section.heading)
                heading:SetFullWidth(true)
                scroll:AddChild(heading)
            end
            for _, entry in ipairs(section.entries) do
                local btn = AceGUI:Create("InteractiveLabel")
                local tex = entry.icon and ("|T" .. entry.icon .. ":16:16:0:0|t ") or ""
                local spellIDSuffix = ""
                if entry.spellID and entry.spellID > 0 then
                    spellIDSuffix = "  |cff888888(" .. entry.spellID .. ")|r"
                end
                local monitoredSuffix = ""
                if entry.monitored then
                    monitoredSuffix = " |cff00ccff- " .. ((ns.L and ns.L.mbAlreadyMonitored) or "Monitored") .. "|r"
                end
                btn:SetText(tex .. "|cffffffff" .. entry.name .. "|r" .. spellIDSuffix .. monitoredSuffix)
                btn:SetFullWidth(true)
                btn:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                btn:SetCallback("OnClick", function()
                    section.onSelect(entry)
                    frame:Release()
                end)
                scroll:AddChild(btn)
            end
        end
    end

    if not hasAny and not onManualAdd then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("|cffaaaaaa" .. ((ns.L and ns.L.bgCatalogEmpty) or "") .. "|r")
        emptyLabel:SetFullWidth(true)
        scroll:AddChild(emptyLabel)
    end

    return frame
end
