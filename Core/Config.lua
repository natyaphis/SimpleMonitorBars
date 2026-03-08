
-- Database bootstrap and schema migration.
local _, ns = ...

local AceDB3 = LibStub("AceDB-3.0")
local MigrateOldData = ns.MigrateOldData

function ns:InitDB()
    local charKey = UnitName("player") .. " - " .. GetRealmName()

    local db = AceDB3:New("SimpleMonitorBarsDB", {
        profile = ns.defaults,
    }, charKey)

    ns.acedb = db

    db:SetProfile(charKey)
    MigrateOldData(db.profile)

    ns.db = db.profile
end

function ns:OnProfileChanged()
    ns.db = ns.acedb.profile
end
