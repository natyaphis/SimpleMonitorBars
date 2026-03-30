
-- Migration helpers that normalize profile data into current defaults.
local _, ns = ...

local DeepCopy = ns.DeepCopy
local GetMonitorBarDefaults = ns.GetMonitorBarDefaults
local SIMPLE_TEXT_ANCHORS = {
    LEFT = true,
    CENTER = true,
    RIGHT = true,
}

local function NormalizeSimpleTextAnchor(value, fallback)
    if SIMPLE_TEXT_ANCHORS[value] then
        return value
    end
    return fallback
end

local function MigrateMonitorBars(profileData)
    if type(profileData.monitorBars) ~= "table" then
        profileData.monitorBars = DeepCopy(ns.defaults.monitorBars)
    end

    local bars = profileData.monitorBars.bars
    if type(bars) ~= "table" then
        bars = {}
        profileData.monitorBars.bars = bars
    end

    local maxID = 0
    for _, bar in ipairs(bars) do
        if type(bar) == "table" then
            local barDefaults = GetMonitorBarDefaults({
                class = "ALL",
                maxCharges = 2,
                width = 200,
                height = 20,
                showCondition = "always",
                specs = {},
            })
            for k, v in pairs(barDefaults) do
                if bar[k] == nil then
                    bar[k] = DeepCopy(v)
                end
            end
            bar.nameAnchor = NormalizeSimpleTextAnchor(bar.nameAnchor, "RIGHT")
            bar.countTextAnchor = NormalizeSimpleTextAnchor(bar.countTextAnchor, "LEFT")
            bar.textAnchor = NormalizeSimpleTextAnchor(bar.textAnchor or bar.textAlign, "CENTER")
            bar.textAlign = bar.textAnchor
            bar.barShape = nil
            bar.ringThickness = nil
            if type(bar.id) ~= "number" then
                maxID = maxID + 1
                bar.id = maxID
            else
                if bar.id > maxID then
                    maxID = bar.id
                end
            end
        end
    end

    if type(profileData.monitorBars.nextID) ~= "number" then
        profileData.monitorBars.nextID = maxID + 1
    end
end

function ns.MigrateOldData(profileData)
    -- Run every migration stage in a fixed order.
    if type(profileData) ~= "table" then return end
    MigrateMonitorBars(profileData)
end
