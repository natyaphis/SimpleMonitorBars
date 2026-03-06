
local _, ns = ...

ns.UI = {}





local function GetAceGUI()
    return LibStub("AceGUI-3.0")
end

function ns.UI.AddHeading(parent, text)
    local AceGUI = GetAceGUI()
    local w = AceGUI:Create("Heading")
    w:SetText(text)
    w:SetFullWidth(true)
    parent:AddChild(w)
end









function ns.UI.OpenSpellCatalogFrame(title, sections, onManualAdd)
    local AceGUI = GetAceGUI()

    local frame = AceGUI:Create("Frame")
    frame:SetTitle(title)
    frame:SetWidth(420)
    frame:SetHeight(500)
    frame:SetLayout("Fill")
    frame:EnableResize(false)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    frame:AddChild(scroll)


    if onManualAdd then
        local manualGroup = AceGUI:Create("InlineGroup")
        manualGroup:SetTitle(ns.L and ns.L.bgManualAdd or "Manual Spell ID")
        manualGroup:SetFullWidth(true)
        manualGroup:SetLayout("Flow")
        scroll:AddChild(manualGroup)

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
        manualGroup:AddChild(manualBox)
    end


    local hasAny = false
    for _, section in ipairs(sections) do
        if section.entries and #section.entries > 0 then
            hasAny = true
            local heading = AceGUI:Create("Heading")
            heading:SetText(section.heading .. " (" .. #section.entries .. ")")
            heading:SetFullWidth(true)
            scroll:AddChild(heading)

            for _, entry in ipairs(section.entries) do
                local btn = AceGUI:Create("InteractiveLabel")
                local tex = entry.icon and ("|T" .. entry.icon .. ":16:16:0:0|t ") or ""
                btn:SetText(tex .. "|cffffffff" .. entry.name .. "|r  |cff888888(" .. entry.spellID .. ")|r")
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
