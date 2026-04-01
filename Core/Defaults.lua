
local _, ns = ...

ns.defaults = {
    monitorBars = {
        locked = false,
        nextID = 1,
        bars = {},
    },
}

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do
        t[k] = DeepCopy(v)
    end
    return t
end

ns.DeepCopy = DeepCopy

function ns.GetMonitorBarDefaults(options)
    options = options or {}

    local barType = options.barType or "stack"
    local playerClass = select(2, UnitClass("player")) or "ALL"

    return {
        id = options.id,
        enabled = true,
        class = options.class or playerClass,
        barType = barType,
        spellID = options.spellID or 0,
        spellName = options.spellName or "",
        unit = options.unit or "player",
        maxStacks = 5,
        maxCharges = options.maxCharges,
        isChargeSpell = options.isChargeSpell,
        maxDuration = 60,
        width = options.width or 300,
        height = options.height or 8,
        verticalBar = false,
        reverseGrowth = false,
        posX = 0,
        posY = 0,
        barColor = { 0.4, 0.75, 1.0, 1 },
        bgColor = { 0.1, 0.1, 0.1, 0.6 },
        borderColor = { 0, 0, 0, 1 },
        maskAndBorderStyle = "1",
        showIcon = false,
        iconOnRight = false,
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
        borderStyle = "whole",
        segmentGap = 1,
        showCondition = options.showCondition or "always",
        hideInNativeCooldownViewer = false,
        frameStrata = "MEDIUM",
        textAnchor = "CENTER",
        smoothAnimation = true,
        showSpellName = false,
        nameAnchor = "RIGHT",
        nameOutline = "OUTLINE",
        nameFontName = "",
        nameFontSize = 14,
        specs = DeepCopy(options.specs or {}),
    }
end
