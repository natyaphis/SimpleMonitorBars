
-- Migration helpers that normalize profile data into current defaults.
local _, ns = ...

local DeepCopy = ns.DeepCopy

local function MigrateMonitorBars(profileData)
    if type(profileData.monitorBars) ~= "table" then
        profileData.monitorBars = DeepCopy(ns.defaults.monitorBars)
    end

    local bars = profileData.monitorBars.bars
    if type(bars) ~= "table" then
        bars = {}
        profileData.monitorBars.bars = bars
    end

    -- Fill missing keys for each bar while preserving user values.
    local barDefaults = {
        enabled = true,
        class = "ALL",
        barType = "stack",
        spellID = 0,
        spellName = "",
        unit = "player",
        maxStacks = 5,
        maxCharges = 2,
        maxDuration = 60,
        width = 200,
        height = 20,
        posX = 0,
        posY = 0,
        barColor = { 0.4, 0.75, 1.0, 1 },
        bgColor = { 0.1, 0.1, 0.1, 0.6 },
        borderColor = { 0, 0, 0, 1 },
        showIcon = true,
        showText = true,
        textAlign = "RIGHT",
        textOffsetX = -4,
        textOffsetY = 0,
        fontName = "",
        fontSize = 12,
        outline = "OUTLINE",
        barTexture = "Solid",
        colorThreshold = 0,
        thresholdColor = { 1.0, 1.0, 1.0, 1 },
        colorThreshold2 = 0,
        thresholdColor2 = { 1.0, 1.0, 0.0, 1 },
        maskAndBorderStyle = "1",
        borderStyle = "whole",
        segmentGap = 1,
        hideFromCDM = false,
        showCondition = "always",
        frameStrata = "MEDIUM",
        textAnchor = "RIGHT",
        smoothAnimation = true,
        ringThickness = 10,
        specs = {},
    }

    local maxID = 0
    for _, bar in ipairs(bars) do
        if type(bar) == "table" then
            for k, v in pairs(barDefaults) do
                if bar[k] == nil then
                    bar[k] = DeepCopy(v)
                end
            end
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
