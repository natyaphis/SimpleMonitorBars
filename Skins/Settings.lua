
-- Main settings window and tab routing.
local addonName, ns = ...

local L = ns.L
local AceGUI
local MB = ns.MonitorBars

local FOOTER_BUTTON_HEIGHT = 24
local FOOTER_BUTTON_GAP = 8
local FOOTER_SIDE_INSET = 14
local TOP_TAB_WIDTH_SCALE = 1.2
local TOP_TAB_OVERLAP = -14

local function GetAddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, "Version")
    end
    return GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")
end

local function GetTabList()
    return {
        { value = "general", text = L.tabOverview or L.general },
        { value = "monitorBars", text = L.tabMonitorSettings or L.monitorBars },
        { value = "profiles", text = L.tabProfiles or L.profiles },
    }
end

local function OnTabSelected(container, _, group)
    -- Reuse the same scroll container so tab switches don't flash from full teardown/rebuild.
    local scroll = container._smbScroll
    if scroll and (not scroll.frame or scroll.parent ~= container or (AceGUI and AceGUI.IsReleasing and AceGUI:IsReleasing(scroll))) then
        container._smbScroll = nil
        scroll = nil
    end
    if not scroll then
        scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll:SetFullWidth(true)
        scroll:SetFullHeight(true)
        container:AddChild(scroll)
        container._smbScroll = scroll
    else
        scroll:ReleaseChildren()
    end

    if group == "general" then
        ns.BuildGeneralTab(scroll)
    elseif group == "monitorBars" then
        ns.BuildMonitorBarsTab(scroll)
    elseif group == "profiles" then
        ns.BuildProfilesTab(scroll)
    end

    C_Timer.After(0, function()
        if scroll and scroll.DoLayout then
            scroll:DoLayout()
        end
        if container and container.type == "TabGroup" then
            ns._adjustSettingsTabs(container)
        end
    end)
end

local function AdjustSettingsTabs(tabGroup)
    if not tabGroup or not tabGroup.tabs or not tabGroup.tablist then
        return
    end

    local count = #tabGroup.tablist
    if count == 0 then
        return
    end

    local availableWidth = tabGroup.frame.width or tabGroup.frame:GetWidth() or 0
    if availableWidth <= 0 then
        C_Timer.After(0, function()
            AdjustSettingsTabs(tabGroup)
        end)
        return
    end

    local tabs = {}
    local totalWidth = 0
    local hastitle = (tabGroup.titletext:GetText() and tabGroup.titletext:GetText() ~= "")
    local yOffset = -((hastitle and 14 or 7))

    for i = 1, count do
        local tab = tabGroup.tabs[i]
        if tab and tab:IsShown() then
            local baseWidth = tab._smbBaseWidth or (tab:GetWidth() or 0)
            tab._smbBaseWidth = baseWidth
            local scaledWidth = math.floor(baseWidth * TOP_TAB_WIDTH_SCALE + 0.5)
            tab:SetWidth(scaledWidth)
            tabs[#tabs + 1] = tab
            totalWidth = totalWidth + scaledWidth
        end
    end

    if #tabs == 0 then
        return
    end

    local contentWidth = totalWidth + (TOP_TAB_OVERLAP * (#tabs - 1))
    local startX = math.max(0, (availableWidth - contentWidth) / 2)

    for i, tab in ipairs(tabs) do
        tab:ClearAllPoints()
        if i == 1 then
            tab:SetPoint("TOPLEFT", tabGroup.frame, "TOPLEFT", startX, yOffset)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", TOP_TAB_OVERLAP, 0)
        end
    end
end

ns._adjustSettingsTabs = AdjustSettingsTabs

local function HideDefaultFooterControls(frame)
    frame.statustext:GetParent():Hide()

    for _, child in ipairs({ frame.frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and child.GetText and child:GetText() == CLOSE then
            child:Hide()
            child:SetScript("OnClick", nil)
        end
    end
end

local function CreateFooterButton(parent, text, anchorPoint, relativeTo, relativePoint, xOffset, width, onClick)
    local btn = AceGUI:Create("Button")
    btn:SetText(text)
    btn:SetWidth(width)
    btn:SetHeight(FOOTER_BUTTON_HEIGHT)
    btn.frame:SetParent(parent)
    btn.frame:ClearAllPoints()
    btn.frame:SetPoint(anchorPoint, relativeTo, relativePoint, xOffset, 15)
    btn.frame:Show()
    btn:SetCallback("OnClick", onClick)
    return btn
end

local function ToggleSettings()
    if ns._settingsFrame then
        ns._settingsFrame:Release()
        ns._settingsFrame = nil
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("SimpleMonitorBars by NatYaphis")
    frame:SetWidth(450)
    frame:SetHeight(512)
    frame:SetLayout("Fill")
    frame:EnableResize(false)

    local f = frame.frame
    frame.titlebg:ClearAllPoints()
    frame.titlebg:SetPoint("TOP", f, "TOP", 0, 4)

    local versionText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    versionText:SetPoint("TOP", frame.titletext, "BOTTOM", 0, -2)
    versionText:SetTextColor(1, 1, 1, 0.95)
    versionText:SetText("Version " .. (GetAddonVersion() or "Unknown"))

    local dragBar = CreateFrame("Frame", nil, f)
    dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    dragBar:SetHeight(44)
    dragBar:EnableMouse(true)
    dragBar:SetScript("OnMouseDown", function() f:StartMoving() end)
    dragBar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    dragBar:SetFrameLevel(f:GetFrameLevel() + 5)

    frame.content:ClearAllPoints()
    frame.content:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -50)
    frame.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 56)

    HideDefaultFooterControls(frame)

    local tabs = AceGUI:Create("TabGroup")
    tabs._smbScroll = nil
    tabs:SetTabs(GetTabList())
    tabs:SetLayout("Fill")
    tabs:SetCallback("OnGroupSelected", OnTabSelected)
    frame:AddChild(tabs)

    C_Timer.After(0, function()
        AdjustSettingsTabs(tabs)
    end)

    local footerWidth = f:GetWidth() - (FOOTER_SIDE_INSET * 2) - (FOOTER_BUTTON_GAP * 2)
    local buttonWidth = math.floor(footerWidth / 3)

    local btnEM = CreateFooterButton(f, L.openEditMode, "BOTTOMLEFT", f, "BOTTOMLEFT", FOOTER_SIDE_INSET, buttonWidth, function()
        if InCombatLockdown() then
            print(L.editModeCombatLocked)
            return
        end
        local emFrame = _G.EditModeManagerFrame
        if not emFrame then
            local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
            if loader then loader("Blizzard_EditMode") end
            emFrame = _G.EditModeManagerFrame
        end
        if emFrame then
            if emFrame.CanEnterEditMode and not emFrame:CanEnterEditMode() then return end
            if emFrame:IsShown() then HideUIPanel(emFrame) else ShowUIPanel(emFrame) end
        end
    end)
    btnEM.frame:SetFrameLevel(f:GetFrameLevel() + 3)

    local btnLock

    local function RefreshLockButtonText()
        local isLocked = ns.db and ns.db.monitorBars and ns.db.monitorBars.locked
        btnLock:SetText(isLocked and (L.mbAlreadyLocked or L.mbLocked) or L.mbLocked)
        if isLocked then
            btnLock.frame:LockHighlight()
        else
            btnLock.frame:UnlockHighlight()
        end
    end

    btnLock = CreateFooterButton(f, L.mbLocked, "BOTTOM", f, "BOTTOM", 0, buttonWidth, function()
        local locked = not (ns.db and ns.db.monitorBars and ns.db.monitorBars.locked)
        MB:SetLocked(locked)
        RefreshLockButtonText()
    end)
    btnLock.frame:SetFrameLevel(f:GetFrameLevel() + 3)
    RefreshLockButtonText()

    local btnClose = CreateFooterButton(f, CLOSE, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -FOOTER_SIDE_INSET, buttonWidth, function()
        frame:Hide()
    end)
    btnClose.frame:SetFrameLevel(f:GetFrameLevel() + 3)

    frame:SetCallback("OnClose", function(widget)
        dragBar:Hide()
        btnEM:Release()
        btnLock:Release()
        btnClose:Release()
        widget:Release()
        ns._settingsFrame = nil
    end)

    tabs:SelectTab("general")
    ns._settingsFrame = frame
end

ns.ToggleSettings = ToggleSettings

function ns:InitSettings()
    -- Register slash commands and the Blizzard Settings category entry.
    AceGUI = LibStub("AceGUI-3.0")

    SLASH_SIMPLEMONITORBARS1 = "/simplemonitorbars"
    SLASH_SIMPLEMONITORBARS2 = "/smb"
    SlashCmdList["SIMPLEMONITORBARS"] = ToggleSettings

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local panel = CreateFrame("Frame")
        panel:SetSize(600, 300)

        local logo = panel:CreateTexture(nil, "ARTWORK")
        logo:SetSize(64, 64)
        logo:SetPoint("TOPLEFT", 20, -20)
        logo:SetTexture("Interface\\AddOns\\SimpleMonitorBars\\Media\\Icon")

        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -4)
        title:SetText("|cff00ccffSimpleMonitorBars|r")

        local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        desc:SetWidth(460)
        desc:SetJustifyH("LEFT")
        desc:SetText(L.aboutDesc)

        local cmdTip = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cmdTip:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
        cmdTip:SetText("|cff888888" .. L.slashHelp .. "|r")

        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(160, 28)
        btn:SetPoint("TOPLEFT", cmdTip, "BOTTOMLEFT", 0, -10)
        btn:SetText(L.openSettings)
        btn:SetScript("OnClick", function()
            ToggleSettings()
            if SettingsPanel and SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
        end)

        local category = Settings.RegisterCanvasLayoutCategory(panel, "SimpleMonitorBars", "SimpleMonitorBars")
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    end
end
