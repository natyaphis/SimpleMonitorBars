
-- Migration helpers that normalize profile data into current defaults.
local _, ns = ...

local DeepCopy = ns.DeepCopy
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
        isChargeSpell = nil,
        maxDuration = 60,
        width = 200,
        height = 20,
        barShape = "Bar",
        posX = 0,
        posY = 0,
        barColor = { 0.4, 0.75, 1.0, 1 },
        bgColor = { 0.1, 0.1, 0.1, 0.6 },
        borderColor = { 0, 0, 0, 1 },
        showIcon = false,
        showText = false,
        textAlign = "CENTER",
        textOffsetX = 0,
        textOffsetY = 0,
        fontName = "",
        fontSize = 14,
        outline = "OUTLINE",
        showCountText = false,
        countTextAnchor = "LEFT",
        countTextOffsetX = 0,
        countTextOffsetY = 0,
        countFontName = "",
        countFontSize = 14,
        countOutline = "OUTLINE",
        barTexture = "Solid",
        colorThreshold = 0,
        thresholdColor = { 1.0, 1.0, 1.0, 1 },
        colorThreshold2 = 0,
        thresholdColor2 = { 1.0, 1.0, 0.0, 1 },
        maskAndBorderStyle = "1",
        borderStyle = "whole",
        segmentGap = 1,
        showCondition = "always",
        hideInNativeCooldownViewer = false,
        frameStrata = "MEDIUM",
        textAnchor = "CENTER",
        smoothAnimation = true,
        nameAnchor = "RIGHT",
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
            bar.nameAnchor = NormalizeSimpleTextAnchor(bar.nameAnchor, "RIGHT")
            bar.countTextAnchor = NormalizeSimpleTextAnchor(bar.countTextAnchor, "LEFT")
            bar.textAnchor = NormalizeSimpleTextAnchor(bar.textAnchor or bar.textAlign, "CENTER")
            bar.textAlign = bar.textAnchor
            bar.barShape = "Bar"
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
