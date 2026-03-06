
local _, ns = ...

local L = ns.L

function ns.BuildGeneralTab(scroll)
    local AceGUI = LibStub("AceGUI-3.0")
    local bars = (ns.db and ns.db.monitorBars and ns.db.monitorBars.bars) or {}
    local playerClassTag = select(2, UnitClass("player"))
    local currentSpec = GetSpecialization() or 1

    local content = AceGUI:Create("SimpleGroup")
    content:SetFullWidth(true)
    content:SetLayout("Flow")
    scroll:AddChild(content)

    local title = AceGUI:Create("Heading")
    title:SetText(L.overviewSpecBars)
    title:SetFullWidth(true)
    content:AddChild(title)

    local desc = AceGUI:Create("Label")
    desc:SetText("|cffaaaaaa" .. L.overviewSpecBarsDesc .. "|r")
    desc:SetFullWidth(true)
    desc:SetFontObject(GameFontHighlightSmall)
    content:AddChild(desc)

    if #bars == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetText("\n|cffaaaaaa" .. L.overviewNoBars .. "|r")
        empty:SetFullWidth(true)
        content:AddChild(empty)
        return
    end

    local function IsClassMatched(barClass)
        return (barClass == nil or barClass == "" or barClass == "ALL" or barClass == playerClassTag)
    end

    local function IsBarEnabledForSpec(barCfg, specIndex)
        if not barCfg.enabled or (barCfg.spellID or 0) <= 0 then
            return false
        end
        if not IsClassMatched(barCfg.class) then
            return false
        end
        local specs = barCfg.specs
        if not specs or #specs == 0 then
            return true
        end
        for _, s in ipairs(specs) do
            if s == specIndex then
                return true
            end
        end
        return false
    end

    local numSpecs = GetNumSpecializations() or 0
    if numSpecs <= 0 then
        numSpecs = 1
    end

    for specIndex = 1, numSpecs do
        local _, specName = GetSpecializationInfo(specIndex)
        specName = specName or string.format(L.overviewUnknownSpec, specIndex)

        local group = AceGUI:Create("InlineGroup")
        local specTitle = specName
        if specIndex == currentSpec then
            specTitle = specTitle .. "  |cff00ccff(" .. L.overviewCurrentSpec .. ")|r"
        end
        group:SetTitle(specTitle)
        group:SetFullWidth(true)
        group:SetLayout("Flow")
        content:AddChild(group)

        local added = 0
        for _, bar in ipairs(bars) do
            if IsBarEnabledForSpec(bar, specIndex) then
                local spellName = bar.spellName
                if not spellName or spellName == "" then
                    spellName = C_Spell.GetSpellName(bar.spellID) or ("SpellID " .. tostring(bar.spellID))
                end

                local typeText = L.mbTypeStack
                if bar.barType == "charge" then
                    typeText = L.mbTypeCharge
                elseif bar.barType == "duration" then
                    typeText = L.mbTypeDuration
                end

                local line = AceGUI:Create("Label")
                line:SetText(string.format("- %s  |cff888888[%s]|r", spellName, typeText))
                line:SetFullWidth(true)
                group:AddChild(line)
                added = added + 1
            end
        end

        if added == 0 then
            local empty = AceGUI:Create("Label")
            empty:SetText("|cff888888" .. L.overviewNoBarsForSpec .. "|r")
            empty:SetFullWidth(true)
            group:AddChild(empty)
        end
    end

end
