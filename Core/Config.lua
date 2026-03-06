
-- Database bootstrap and schema migration.
local _, ns = ...

local AceDB3 = LibStub("AceDB-3.0")
local LibDualSpec = LibStub("LibDualSpec-1.0", true)
local DeepCopy = ns.DeepCopy
local MigrateOldData = ns.MigrateOldData

local LEGACY_SHARED_PROFILE_NAME = "Default"

function ns:InitDB()
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    ns._charKey = charKey

    local oldCharConfig = nil
    if SimpleMonitorBarsDB_Char and SimpleMonitorBarsDB_Char.config then
        oldCharConfig = DeepCopy(SimpleMonitorBarsDB_Char.config)
    end

    local oldProfiles = nil
    if SimpleMonitorBarsDB_Profiles and next(SimpleMonitorBarsDB_Profiles) then
        oldProfiles = DeepCopy(SimpleMonitorBarsDB_Profiles)
    end

    local oldAccountConfig = nil
    if SimpleMonitorBarsDB and SimpleMonitorBarsDB.essential and not SimpleMonitorBarsDB.profiles then
        oldAccountConfig = DeepCopy(SimpleMonitorBarsDB)
        wipe(SimpleMonitorBarsDB)
    end

    local db = AceDB3:New("SimpleMonitorBarsDB", {
        profile = ns.defaults,
        char    = { useSharedProfile = false },
    }, charKey)

    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(db, "SimpleMonitorBars")
    end

    ns.acedb = db

    local migrated = false
    if oldCharConfig then
        MigrateOldData(oldCharConfig)
        for k, v in pairs(oldCharConfig) do
            if type(v) == "table" then
                db.profile[k] = DeepCopy(v)
            else
                db.profile[k] = v
            end
        end
        migrated = true
    elseif oldAccountConfig then
        MigrateOldData(oldAccountConfig)
        for k, v in pairs(oldAccountConfig) do
            if type(v) == "table" then
                db.profile[k] = DeepCopy(v)
            else
                db.profile[k] = v
            end
        end
        migrated = true
    end

    if oldProfiles then
        for name, cfg in pairs(oldProfiles) do
            MigrateOldData(cfg)
            db.sv.profiles[name] = cfg
        end
    end

    -- Clear transitional globals after migration succeeds.
    if migrated or oldProfiles then
        SimpleMonitorBarsDB_Char = nil
        SimpleMonitorBarsDB_Profiles = nil
    end

    -- Preserve the effective settings for characters that previously used
    -- the removed shared-profile toggle, then return them to character profiles.
    if db.char.useSharedProfile then
        local sharedProfile = db.sv.profiles and db.sv.profiles[LEGACY_SHARED_PROFILE_NAME]
        if sharedProfile then
            db.sv.profiles[charKey] = DeepCopy(sharedProfile)
        end
        db.char.useSharedProfile = false
    end

    db:SetProfile(charKey)

    ns.db = db.profile
end

function ns:OnProfileChanged()
    ns.db = ns.acedb.profile
end
