
local _, ns = ...

local L = ns.L
local UI = ns.UI
local PROFILE_LIST_LAYOUT = "SMBProfileList3"
local profileListLayoutRegistered = false

local function GetProfileList(db, excludeCurrent)
    local profiles = {}
    local order = {}
    local tmpProfiles = {}
    local current = db:GetCurrentProfile()
    for _, name in pairs(db:GetProfiles(tmpProfiles)) do
        if not (excludeCurrent and name == current) then
            profiles[name] = name
            order[#order + 1] = name
        end
    end
    table.sort(order)
    return profiles, order
end

local function RegisterProfileLayouts(AceGUI)
    if profileListLayoutRegistered or not AceGUI then
        return
    end

    AceGUI:RegisterLayout(PROFILE_LIST_LAYOUT, function(content, children)
        local height = 0
        local width = content.width or content:GetWidth() or 0

        for i = 1, #children do
            local child = children[i]
            local frame = child.frame

            frame:ClearAllPoints()
            frame:Show()
            if i == 1 then
                frame:SetPoint("TOPLEFT", content)
            else
                frame:SetPoint("TOPLEFT", children[i - 1].frame, "BOTTOMLEFT", 0, -3)
            end

            if child.width == "fill" then
                child:SetWidth(width)
                frame:SetPoint("RIGHT", content)

                if child.DoLayout then
                    child:DoLayout()
                end
            elseif child.width == "relative" then
                child:SetWidth(width * child.relWidth)

                if child.DoLayout then
                    child:DoLayout()
                end
            end

            height = height + (frame.height or frame:GetHeight() or 0)
            if i > 1 then
                height = height + 3
            end
        end

        content.obj:LayoutFinished(nil, height)
    end)

    profileListLayoutRegistered = true
end

function ns.BuildProfileTab(scroll)
    local AceGUI = LibStub("AceGUI-3.0")
    RegisterProfileLayouts(AceGUI)
    local db = ns.acedb

    local content = AceGUI:Create("SimpleGroup")
    content:SetFullWidth(true)
    content:SetLayout(PROFILE_LIST_LAYOUT)
    scroll:AddChild(content)

    local function RefreshTab()
        local tabs = ns._settingsFrame and ns._settingsFrame.children and ns._settingsFrame.children[1]
        if tabs and tabs.SelectTab then tabs:SelectTab("profiles") end
    end

    local currentLabel = AceGUI:Create("Label")
    currentLabel:SetText("|cffffd200" .. db:GetCurrentProfile() .. "|r")
    currentLabel:SetFullWidth(true)
    currentLabel:SetFontObject(GameFontNormal)
    currentLabel:SetJustifyH("CENTER")
    content:AddChild(currentLabel)

    local profileItems, profileOrder = GetProfileList(db)
    local chooseDD = AceGUI:Create("Dropdown")
    chooseDD:SetLabel(L.profileChooseDesc)
    chooseDD:SetList(profileItems, profileOrder)
    chooseDD:SetValue(db:GetCurrentProfile())
    chooseDD:SetFullWidth(true)
    chooseDD:SetCallback("OnValueChanged", function(_, _, val)
        db:SetProfile(val)
        print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.profileLoaded, val))
        RefreshTab()
    end)
    content:AddChild(chooseDD)

    UI.AddHeading(content, L.profileNew)

    local newDesc = AceGUI:Create("Label")
    newDesc:SetText("|cffffd200" .. L.profileNewDesc .. "|r")
    newDesc:SetFullWidth(true)
    newDesc:SetFontObject(GameFontNormal)
    content:AddChild(newDesc)

    local newBox = AceGUI:Create("EditBox")
    newBox:SetLabel("")
    newBox:SetFullWidth(true)
    newBox:SetCallback("OnEnterPressed", function(_, _, val)
        val = val and val:match("^%s*(.-)%s*$")
        if not val or val == "" then return end
        db:SetProfile(val)
        print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.profileCreated, val))
        RefreshTab()
    end)
    content:AddChild(newBox)

    local copyItems, copyOrder = GetProfileList(db, true)
    if next(copyItems) then
        local copyLabel = AceGUI:Create("Label")
        copyLabel:SetText("|cffffd200" .. L.profileCopyFrom .. "|r")
        copyLabel:SetFullWidth(true)
        copyLabel:SetFontObject(GameFontNormal)
        content:AddChild(copyLabel)

        local copyDD = AceGUI:Create("Dropdown")
        copyDD:SetLabel("")
        copyDD:SetList(copyItems, copyOrder)
        copyDD:SetFullWidth(true)
        copyDD:SetCallback("OnValueChanged", function(_, _, val)
            db:CopyProfile(val)
            print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.profileCopied, val))
            RefreshTab()
        end)
        content:AddChild(copyDD)
    end

    local delItems, delOrder = GetProfileList(db, true)
    if next(delItems) then
        local deleteLabel = AceGUI:Create("Label")
        deleteLabel:SetText("|cffffd200" .. L.profileDelete .. "|r")
        deleteLabel:SetFullWidth(true)
        deleteLabel:SetFontObject(GameFontNormal)
        content:AddChild(deleteLabel)

        local deleteGroup = AceGUI:Create("SimpleGroup")
        deleteGroup:SetFullWidth(true)
        deleteGroup:SetLayout("Flow")
        content:AddChild(deleteGroup)

        local delDD = AceGUI:Create("Dropdown")
        delDD:SetLabel("")
        delDD:SetList(delItems, delOrder)
        delDD:SetRelativeWidth(0.5)
        deleteGroup:AddChild(delDD)

        local delBtn = AceGUI:Create("Button")
        delBtn:SetText("|cffff4444" .. L.profileDelete .. "|r")
        delBtn:SetRelativeWidth(0.5)
        delBtn:SetHeight(24)
        delBtn.alignoffset = 10
        delBtn:SetCallback("OnClick", function()
            local selected = delDD:GetValue()
            if not selected then return end
            if selected == db:GetCurrentProfile() then
                print("|cff00ccff[SimpleMonitorBars]|r " .. L.profileCantDeleteCurrent)
                return
            end
            db:DeleteProfile(selected)
            print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.profileDeleted, selected))
            RefreshTab()
        end)
        deleteGroup:AddChild(delBtn)
    end

    UI.AddHeading(content, L.importExport)

    local exportBox = AceGUI:Create("MultiLineEditBox")
    exportBox:SetLabel(L.exportHint)
    exportBox:SetFullWidth(true)
    exportBox:SetNumLines(3)
    exportBox:SetText("")
    exportBox:DisableButton(true)
    content:AddChild(exportBox)

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText(L.exportBtn)
    exportBtn:SetFullWidth(true)
    exportBtn:SetCallback("OnClick", function()
        local str = ns:ExportConfig()
        exportBox:SetText(str)
        exportBox:SetFocus()
        exportBox:HighlightText()
    end)
    content:AddChild(exportBtn)

    local importBox = AceGUI:Create("MultiLineEditBox")
    importBox:SetLabel(L.importHint)
    importBox:SetFullWidth(true)
    importBox:SetNumLines(3)
    importBox:SetText("")
    importBox:DisableButton(true)
    content:AddChild(importBox)

    local importGroup = AceGUI:Create("SimpleGroup")
    importGroup:SetFullWidth(true)
    importGroup:SetLayout("Flow")
    content:AddChild(importGroup)

    local importNameLabel = AceGUI:Create("Label")
    importNameLabel:SetText("|cffffd200" .. L.importName .. "|r")
    importNameLabel:SetFullWidth(true)
    importNameLabel:SetFontObject(GameFontNormal)
    importGroup:AddChild(importNameLabel)

    local importNameBox = AceGUI:Create("EditBox")
    importNameBox:SetLabel("")
    importNameBox:SetRelativeWidth(0.5)
    importNameBox:SetHeight(24)
    importNameBox:SetCallback("OnEnterPressed", function() end)
    importGroup:AddChild(importNameBox)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText(L.importBtn)
    importBtn:SetRelativeWidth(0.5)
    importBtn:SetHeight(22)
    importBtn:SetCallback("OnClick", function()
        local name = importNameBox:GetText()
        if not name or name:match("^%s*$") then
            print("|cff00ccff[SimpleMonitorBars]|r " .. L.profileNoName)
            return
        end
        name = name:match("^%s*(.-)%s*$")
        local str = importBox:GetText()
        if not str or str == "" then return end
        local ok, errMsg = ns:ImportConfig(str, name)
        if ok then
            print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.importSuccess, name))
            RefreshTab()
        else
            print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.importFail, errMsg or L.unknown))
        end
    end)
    importGroup:AddChild(importBtn)

    local resetBtn = AceGUI:Create("Button")
    resetBtn:SetText(L.profileReset)
    resetBtn:SetFullWidth(true)
    local pendingReset = false
    resetBtn:SetCallback("OnClick", function()
        if not pendingReset then
            pendingReset = true
            resetBtn:SetText("|cffff4444" .. L.profileResetConfirm .. "|r")
            C_Timer.After(5, function()
                if pendingReset then
                    pendingReset = false
                    resetBtn:SetText(L.profileReset)
                end
            end)
        else
            pendingReset = false
            db:ResetProfile()
            print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.profileResetDone, db:GetCurrentProfile()))
            RefreshTab()
        end
    end)
    content:AddChild(resetBtn)
end
