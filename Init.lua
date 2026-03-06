
-- Addon bootstrap: initializes DB, settings UI, and runtime event handlers.
local _, ns = ...

local MB = ns.MonitorBars
local L = ns.L

local function IsMonitorBarsEnabled()
    return ns.db and ns.db.monitorBars and MB
end

local function RebuildMonitorBars()
    if not IsMonitorBarsEnabled() then return end
    MB:ScanCDMViewers()
    MB:RebuildAllBars()
end

local function RegisterProfileCallbacks()
    -- Rebuild bars whenever AceDB profile content changes.
    local function OnProfileChanged()
        ns:OnProfileChanged()
        RebuildMonitorBars()
    end

    ns.acedb.RegisterCallback(ns, "OnProfileChanged", OnProfileChanged)
    ns.acedb.RegisterCallback(ns, "OnProfileCopied", OnProfileChanged)
    ns.acedb.RegisterCallback(ns, "OnProfileReset", OnProfileChanged)
end

local function RegisterEventHandlers()
    -- Route game events through a lookup table to keep registration centralized.
    local eventFrame = CreateFrame("Frame")
    local handlers = {}

    handlers["PLAYER_ENTERING_WORLD"] = function()
        C_Timer.After(0.5, RebuildMonitorBars)
    end

    handlers["PLAYER_SPECIALIZATION_CHANGED"] = function()
        C_Timer.After(0.5, RebuildMonitorBars)
    end

    handlers["UNIT_AURA"] = function(unit)
        if IsMonitorBarsEnabled() then
            MB:OnAuraUpdate(unit)
        end
    end

    handlers["SPELL_UPDATE_CHARGES"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnChargeUpdate()
        end
    end

    handlers["PLAYER_TARGET_CHANGED"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnTargetChanged()
        end
    end

    handlers["PLAYER_REGEN_ENABLED"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnCombatLeave()
        end
    end

    handlers["PLAYER_REGEN_DISABLED"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnCombatEnter()
        end
    end

    handlers["SPELL_UPDATE_COOLDOWN"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnCooldownUpdate()
        end
    end

    handlers["UPDATE_BONUS_ACTIONBAR"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnSkyridingChanged()
        end
    end

    handlers["ACTIONBAR_UPDATE_STATE"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnSkyridingChanged()
        end
    end

    handlers["PLAYER_CAN_GLIDE_CHANGED"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnSkyridingChanged()
        end
    end

    handlers["PLAYER_IS_GLIDING_CHANGED"] = function()
        if IsMonitorBarsEnabled() then
            MB:OnSkyridingChanged()
        end
    end

    for event in pairs(handlers) do
        eventFrame:RegisterEvent(event)
    end

    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local handler = handlers[event]
        if handler then
            handler(...)
        end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, _, addonName)
    if addonName ~= "SimpleMonitorBars" then return end

    ns:InitDB()

    RegisterProfileCallbacks()
    RegisterEventHandlers()

    if ns.InitSettings then
        ns:InitSettings()
    end

    RebuildMonitorBars()

    print("|cff00ccff[SimpleMonitorBars]|r " .. format(L.loaded, L.slashHelp))
    initFrame:UnregisterAllEvents()
end)
