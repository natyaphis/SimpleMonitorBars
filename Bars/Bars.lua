
-- Runtime rendering pipeline for monitor bars.
local _, ns = ...

local MB = ns.MonitorBars
local LSM = LibStub("LibSharedMedia-3.0", true)
local BAR_TEXTURE  = ns._mbConst.BAR_TEXTURE
local SEGMENT_GAP  = ns._mbConst.SEGMENT_GAP
local UPDATE_INTERVAL = ns._mbConst.UPDATE_INTERVAL
local COVER_TEXTURE = "Interface\\AddOns\\SimpleMonitorBars\\Media\\cover.png"

local ResolveFontPath    = MB.ResolveFontPath
local ConfigureStatusBar = MB.ConfigureStatusBar
local HasAuraInstanceID  = MB.HasAuraInstanceID
local FindCDMFrame       = MB.FindCDMFrame
local FindCooldownIDBySpellID = MB.FindCooldownIDBySpellID
local spellToCooldownID  = MB._spellToCooldownID
local PLAYER_CLASS_TAG   = select(2, UnitClass("player"))

local activeFrames = {}
local elapsed = 0
local inCombat = false
local frameTick = 0


-- Forward declarations used across setup and update stages.
local ShouldBarBeVisible
local AnchorToJustifyH
local ANCHOR_POINT
local ANCHOR_REL


-- Segment fill velocity used by stack smoothing animation.
local STACK_FILL_SPEED = 12
local ICICLES_SPELL_ID = 205473

local function ResolveBarTexturePath(textureName)
    if LSM and LSM.Fetch and textureName then
        return LSM:Fetch("statusbar", textureName) or BAR_TEXTURE
    end
    return BAR_TEXTURE
end

local function IsVerticalBar(cfg)
    return cfg and cfg.verticalBar == true
end

local function IsReverseGrowth(cfg)
    return cfg and cfg.reverseGrowth == true
end

local function ConfigureLinearStatusBar(bar, cfg)
    if not bar then
        return
    end

    local isVertical = IsVerticalBar(cfg)
    if bar.SetOrientation then
        bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    end
    if bar.SetRotatesTexture then
        bar:SetRotatesTexture(isVertical)
    end
    if bar.SetReverseFill and cfg.barType ~= "duration" then
        bar:SetReverseFill(IsReverseGrowth(cfg))
    end
    if bar.GetStatusBarTexture then
        ConfigureStatusBar(bar)
    end
end

local function GetDurationTimerDirection(cfg)
    if IsReverseGrowth(cfg) then
        return Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
    end
    return Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
end

local function ApplyDurationTimer(seg, durObj, cfg)
    if not (seg and durObj and seg.SetTimerDuration) then
        return false
    end
    local interpolation = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or 0
    local direction = GetDurationTimerDirection(cfg)
    seg:SetMinMaxValues(0, 1)
    seg:SetTimerDuration(durObj, interpolation, direction)
    if seg.SetToTargetValue then
        seg:SetToTargetValue()
    end
    return true
end

function MB.rounded(num, idp)
    if not num then return num end
    local mult = 10^(idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

function MB.getPixelPerfectScale(customUIScale)
    local screenHeight = select(2, GetPhysicalScreenSize())
    local scale = customUIScale or UIParent:GetEffectiveScale()
    if scale == 0 or screenHeight == 0 then return 1 end
    return 768 / screenHeight / scale
end

function MB.getNearestPixel(value, customUIScale)
    if value == 0 then return 0 end
    local ppScale = MB.getPixelPerfectScale(customUIScale)
    return MB.rounded(value / ppScale) * ppScale
end

MB.MASK_AND_BORDER_STYLES = {
    ["0"] = {
        type = "fixed",
        thickness = 0,
    },
    ["1"] = {
        type = "fixed",
        thickness = 1,
    },
    ["2"] = {
        type = "fixed",
        thickness = 2,
    },
    ["3"] = {
        type = "fixed",
        thickness = 3,
    },
    ["4"] = {
        type = "fixed",
        thickness = 4,
    },
    ["5"] = {
        type = "fixed",
        thickness = 5,
    },
}





local function IsSkyriding()
    if GetBonusBarIndex() == 11 and GetBonusBarOffset() == 5 then
        return true
    end
    local _, canGlide = C_PlayerInfo.GetGlidingInfo()
    return canGlide == true
end

local function NormalizeMaskAndBorderStyle(styleName)
    if styleName == "1px" then
        return "1"
    elseif styleName == "Thin" then
        return "2"
    elseif styleName == "Medium" then
        return "3"
    elseif styleName == "Thick" then
        return "5"
    elseif styleName == "None" then
        return "0"
    end
    return styleName or "1"
end

local function ResolveCenterOffset(centerX, centerY, parentFrame, frameScale)
    local parentScale = parentFrame:GetEffectiveScale()
    local parentCenterX, parentCenterY = parentFrame:GetCenter()

    local worldX = centerX * frameScale
    local worldY = centerY * frameScale
    local parentWorldX = parentCenterX * parentScale
    local parentWorldY = parentCenterY * parentScale

    local offsetX = (worldX - parentWorldX) / frameScale
    local offsetY = (worldY - parentWorldY) / frameScale
    return MB.getNearestPixel(offsetX, frameScale), MB.getNearestPixel(offsetY, frameScale)
end

local function SetFrameCenterOffset(frame, parentFrame, offsetX, offsetY)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parentFrame, "CENTER", offsetX, offsetY)
end

local function ConfigurePrimaryText(frame, cfg)
    local fontPath = ResolveFontPath(cfg.fontName)
    local anchor = cfg.textAnchor or cfg.textAlign or "CENTER"
    local txOff = cfg.textOffsetX or 0
    local tyOff = cfg.textOffsetY or 0

    frame._text:SetFont(fontPath, cfg.fontSize or 12, cfg.outline or "OUTLINE")
    frame._text:ClearAllPoints()
    frame._text:SetPoint(ANCHOR_POINT[anchor] or anchor, frame._textHolder, ANCHOR_REL[anchor] or anchor, txOff, tyOff)
    frame._text:SetTextColor(1, 1, 1, 1)
    frame._text:SetJustifyH(AnchorToJustifyH(anchor))
end

local function ConfigureCountText(frame, cfg)
    local fontPath = ResolveFontPath(cfg.countFontName or cfg.fontName)
    local anchor = cfg.countTextAnchor or "LEFT"
    local txOff = cfg.countTextOffsetX or 0
    local tyOff = cfg.countTextOffsetY or 0

    frame._countText:SetFont(fontPath, cfg.countFontSize or cfg.fontSize or 14, cfg.countOutline or cfg.outline or "OUTLINE")
    frame._countText:ClearAllPoints()
    frame._countText:SetPoint(ANCHOR_POINT[anchor] or anchor, frame._textHolder, ANCHOR_REL[anchor] or anchor, txOff, tyOff)
    frame._countText:SetTextColor(1, 1, 1, 1)
    frame._countText:SetJustifyH(AnchorToJustifyH(anchor))
end

local function SetCountText(barFrame, text)
    local cfg = barFrame and barFrame._cfg
    if not cfg or cfg.showCountText ~= true or not barFrame._countText then
        return
    end
    barFrame._countText:SetText(text or "")
end

local function ClearCountText(barFrame)
    if barFrame and barFrame._countText then
        barFrame._countText:SetText("")
    end
end

local function ExtractAuraCount(auraData)
    if type(auraData) ~= "table" then return nil end
    local count = auraData.applications or auraData.stacks or auraData.charges or auraData.count
    if type(count) == "number" and count > 0 then
        return count
    end
    return nil
end

local function AttachDragHandlers(frame, barCfg)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.db.monitorBars.locked then return end

        self:SetToplevel(true)
        local frameScale = self:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = cursorX / frameScale, cursorY / frameScale

        local centerX, centerY = self:GetCenter()
        local dragOffsetX = centerX - cursorX
        local dragOffsetY = centerY - cursorY

        self:SetScript("OnUpdate", function(movingFrame)
            local nextCursorX, nextCursorY = GetCursorPosition()
            nextCursorX, nextCursorY = nextCursorX / frameScale, nextCursorY / frameScale

            local nextCenterX = nextCursorX + dragOffsetX
            local nextCenterY = nextCursorY + dragOffsetY
            local setX, setY = ResolveCenterOffset(nextCenterX, nextCenterY, UIParent, frameScale)
            local roundedX = MB.rounded(setX, 1)
            local roundedY = MB.rounded(setY, 1)
            barCfg.posX = roundedX
            barCfg.posY = roundedY
            SetFrameCenterOffset(movingFrame, UIParent, setX, setY)
            if type(barCfg._smbSyncPositionSliders) == "function" then
                barCfg._smbSyncPositionSliders(roundedX, roundedY)
            end
        end)
    end)

    frame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)

        local centerX, centerY = self:GetCenter()
        local frameScale = self:GetEffectiveScale()
        local setX, setY = ResolveCenterOffset(centerX, centerY, UIParent, frameScale)

        barCfg.posX = MB.rounded(setX, 1)
        barCfg.posY = MB.rounded(setY, 1)
        SetFrameCenterOffset(self, UIParent, barCfg.posX, barCfg.posY)
        if type(barCfg._smbSyncPositionSliders) == "function" then
            barCfg._smbSyncPositionSliders(barCfg.posX, barCfg.posY)
        end
    end)
end

local function AttachWheelHandlers(frame, barCfg)
    frame:SetScript("OnMouseWheel", function(self, delta)
        if ns.db.monitorBars.locked then return end
        local effScale = self:GetEffectiveScale()
        local step = MB.getPixelPerfectScale(effScale)

        if IsShiftKeyDown() then
            barCfg.posX = MB.rounded(MB.getNearestPixel((barCfg.posX or 0) + delta * step, effScale), 1)
        else
            barCfg.posY = MB.rounded(MB.getNearestPixel((barCfg.posY or 0) + delta * step, effScale), 1)
        end
        SetFrameCenterOffset(self, UIParent, barCfg.posX, barCfg.posY)
        if type(barCfg._smbSyncPositionSliders) == "function" then
            barCfg._smbSyncPositionSliders(barCfg.posX, barCfg.posY)
        end
    end)
end

local function AttachTooltipHandlers(frame, barCfg)
    frame:SetScript("OnEnter", function(self)
        if ns.db.monitorBars.locked then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        local name = barCfg.spellName or ""
        if name ~= "" then
            GameTooltip:AddLine(name, 1, 1, 1)
        end
        GameTooltip:AddLine(ns.L.mbNudgeHint or "", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end





local viewerSignalRegistry = {}
local watcherIDsByFrame = {}
local UpdateStackBar
local UpdateDurationBar
local pendingDurationRefresh = {}
local durationFlushFrame = CreateFrame("Frame")

local function QueueDurationRefresh(barFrame)
    if not barFrame or not barFrame._barID then
        return
    end
    pendingDurationRefresh[barFrame._barID] = true
    durationFlushFrame:Show()
end

durationFlushFrame:Hide()
durationFlushFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    if not next(pendingDurationRefresh) then
        return
    end

    for barID in pairs(pendingDurationRefresh) do
        pendingDurationRefresh[barID] = nil
        local barFrame = activeFrames[barID]
        if barFrame and barFrame._cfg and barFrame._cfg.barType == "duration" then
            barFrame._needsDurationRefresh = true
            UpdateDurationBar(barFrame)
        end
    end
end)

local function OnCDMFrameChanged(frame)
    local ids = watcherIDsByFrame[frame]
    if not ids then return end
    for _, id in ipairs(ids) do
        local f = activeFrames[id]
        if f and f._cfg then
            if f._cfg.barType == "stack" then
                UpdateStackBar(f)
            elseif f._cfg.barType == "duration" then
                QueueDurationRefresh(f)
            end
        end
    end
end

local function RegisterViewerSignals(frame, barID)
    -- Hook viewer frame refresh paths once and track owning bar IDs.
    if not frame then return end
    if not viewerSignalRegistry[frame] then
        viewerSignalRegistry[frame] = { barIDs = {} }
        watcherIDsByFrame[frame] = {}
        if frame.RefreshData then
            hooksecurefunc(frame, "RefreshData", OnCDMFrameChanged)
        end
        if frame.RefreshApplications then
            hooksecurefunc(frame, "RefreshApplications", OnCDMFrameChanged)
        end
        if frame.SetAuraInstanceInfo then
            hooksecurefunc(frame, "SetAuraInstanceInfo", OnCDMFrameChanged)
        end
    end
    if not viewerSignalRegistry[frame].barIDs[barID] then
        viewerSignalRegistry[frame].barIDs[barID] = true
        table.insert(watcherIDsByFrame[frame], barID)
    end
end

local function ResetViewerSignals()
    for frame in pairs(viewerSignalRegistry) do
        viewerSignalRegistry[frame].barIDs = {}
        watcherIDsByFrame[frame] = {}
    end
end

local function RebindStackWatchers()
    for _, f in pairs(activeFrames) do
        local cfg = f._cfg
        if cfg and cfg.barType == "stack" and cfg.spellID > 0 then
            local cdID = spellToCooldownID[cfg.spellID]
            if cdID then
                local cdmFrame = FindCDMFrame(cdID)
                if cdmFrame then
                    RegisterViewerSignals(cdmFrame, f._barID)
                    f._cdmFrame = cdmFrame
                end
            end
        end
    end
end

function MB:PostScanHook()
    ResetViewerSignals()
    RebindStackWatchers()
end





local function GetArcDetector(barFrame, threshold)
    barFrame._arcDetectors = barFrame._arcDetectors or {}
    local det = barFrame._arcDetectors[threshold]
    if det then return det end

    det = CreateFrame("StatusBar", nil, barFrame)
    det:SetSize(1, 1)
    det:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
    det:SetAlpha(0)
    det:SetStatusBarTexture(BAR_TEXTURE)
    det:SetMinMaxValues(threshold - 1, threshold)
    ConfigureStatusBar(det)
    barFrame._arcDetectors[threshold] = det
    return det
end

local function FeedArcDetectors(barFrame, secretValue, maxVal)
    for i = 1, maxVal do
        GetArcDetector(barFrame, i):SetValue(secretValue)
    end
end

local function GetExactCount(barFrame, maxVal)
    if not barFrame._arcDetectors then return 0 end
    local count = 0
    for i = 1, maxVal do
        local det = barFrame._arcDetectors[i]
        if det and det:GetStatusBarTexture():IsShown() then
            count = i
        end
    end
    return count
end

local function SetStackSegmentsValue(barFrame, value)
    local segs = barFrame._segments
    if not segs then
        return
    end

    for i = 1, #segs do
        segs[i]:SetValue(value)
    end
end

local function ResetStackAnimationState(barFrame, value)
    if not barFrame then
        return
    end

    local resolvedValue = tonumber(value) or 0
    if resolvedValue < 0 then
        resolvedValue = 0
    end

    barFrame._displayStacks = resolvedValue
    barFrame._targetStacks = resolvedValue
end

local function GetOrCreateShadowCooldown(barFrame)
    if barFrame._shadowCooldown then return barFrame._shadowCooldown end
    local cd = CreateFrame("Cooldown", nil, barFrame, "CooldownFrameTemplate")
    cd:SetAllPoints(barFrame)
    cd:SetDrawSwipe(false)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetAlpha(0)
    barFrame._shadowCooldown = cd
    return cd
end

local function HideChargeVisuals(barFrame)
    if not barFrame then return end
    if barFrame._chargeBG then barFrame._chargeBG:Hide() end
    if barFrame._chargeBar then barFrame._chargeBar:Hide() end
    if barFrame._refreshCharge then barFrame._refreshCharge:Hide() end
    if barFrame._refreshChargeText then barFrame._refreshChargeText:SetText("") end
    if barFrame._chargeBorders then
        for _, border in ipairs(barFrame._chargeBorders) do
            border:Hide()
        end
    end
end





function MB.ApplyMaskAndBorderSettings(barFrame, cfg)
    local styleName = NormalizeMaskAndBorderStyle(cfg.maskAndBorderStyle)
    local style = MB.MASK_AND_BORDER_STYLES[styleName] or MB.MASK_AND_BORDER_STYLES["1"]
    
    local width, height = barFrame:GetSize()
    
    if barFrame._mask then
        barFrame._mask:SetTexture(COVER_TEXTURE)
        barFrame._mask:SetAllPoints(barFrame)
    end

    if style.type == "fixed" then
        if not barFrame._fixedBorders then
            barFrame._fixedBorders = {}
            barFrame._fixedBorders.top    = barFrame._borderFrame:CreateTexture(nil, "OVERLAY")
            barFrame._fixedBorders.bottom = barFrame._borderFrame:CreateTexture(nil, "OVERLAY")
            barFrame._fixedBorders.left   = barFrame._borderFrame:CreateTexture(nil, "OVERLAY")
            barFrame._fixedBorders.right  = barFrame._borderFrame:CreateTexture(nil, "OVERLAY")
        end

        barFrame._border:Hide()
        
        local thickness = (style.thickness or 0) * (cfg.scale or 1)
        local pThickness = MB.getNearestPixel(thickness)
        local borderColor = cfg.borderColor or { 0, 0, 0, 1 }

        if pThickness <= 0 then
            for _, t in pairs(barFrame._fixedBorders) do
                t:Hide()
            end
            return
        end

        for edge, t in pairs(barFrame._fixedBorders) do
            t:ClearAllPoints()
            if edge == "top" then
                t:SetPoint("TOPLEFT", barFrame._borderFrame, "TOPLEFT")
                t:SetPoint("TOPRIGHT", barFrame._borderFrame, "TOPRIGHT")
                t:SetHeight(pThickness)
            elseif edge == "bottom" then
                t:SetPoint("BOTTOMLEFT", barFrame._borderFrame, "BOTTOMLEFT")
                t:SetPoint("BOTTOMRIGHT", barFrame._borderFrame, "BOTTOMRIGHT")
                t:SetHeight(pThickness)
            elseif edge == "left" then
                t:SetPoint("TOPLEFT", barFrame._borderFrame, "TOPLEFT")
                t:SetPoint("BOTTOMLEFT", barFrame._borderFrame, "BOTTOMLEFT")
                t:SetWidth(pThickness)
            elseif edge == "right" then
                t:SetPoint("TOPRIGHT", barFrame._borderFrame, "TOPRIGHT")
                t:SetPoint("BOTTOMRIGHT", barFrame._borderFrame, "BOTTOMRIGHT")
                t:SetWidth(pThickness)
            end
            t:SetColorTexture(borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1)
            t:Show()
        end
    elseif style.type == "texture" then
        barFrame._border:Show()
        barFrame._border:SetTexture(style.border)
        barFrame._border:SetAllPoints(barFrame._borderFrame)
        local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
        barFrame._border:SetVertexColor(borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1)

        if barFrame._fixedBorders then
            for _, t in pairs(barFrame._fixedBorders) do t:Hide() end
        end
    else
        barFrame._border:Hide()
        if barFrame._fixedBorders then
            for _, t in pairs(barFrame._fixedBorders) do t:Hide() end
        end
    end
end


local function GetBaseFrameLevelByStrata(strata)
    if strata == "BACKGROUND" then
        return 0
    end
    return 1
end

local function CreateSegments(barFrame, count, cfg)
    barFrame._segments = barFrame._segments or {}
    barFrame._segBGs = barFrame._segBGs or {}
    barFrame._segBorders = barFrame._segBorders or {}

    for _, seg in ipairs(barFrame._segments) do seg:Hide() end
    for _, bg in ipairs(barFrame._segBGs) do bg:Hide() end
    for _, b in ipairs(barFrame._segBorders) do b:Hide() end
    wipe(barFrame._segments)
    wipe(barFrame._segBGs)
    wipe(barFrame._segBorders)

    if count < 1 then return end

    local container = barFrame._segContainer
    local totalW = container:GetWidth()
    local totalH = container:GetHeight()
    local gap = cfg.segmentGap ~= nil and cfg.segmentGap or SEGMENT_GAP
    local isVertical = IsVerticalBar(cfg)
    local isReverse = IsReverseGrowth(cfg)
    local styleName = NormalizeMaskAndBorderStyle(cfg.maskAndBorderStyle)
    local style = MB.MASK_AND_BORDER_STYLES[styleName] or MB.MASK_AND_BORDER_STYLES["1"]
    local borderSize = style.thickness or 0
    local perSegBorder = (cfg.borderStyle == "segment")
    local primarySize = isVertical and totalH or totalW
    local segSize = (primarySize - (count - 1) * gap) / count
    local barColor = cfg.barColor or { 0.4, 0.75, 1.0, 1 }
    local bgColor = cfg.bgColor or { 0.1, 0.1, 0.1, 0.6 }
    local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
    local texPath = BAR_TEXTURE
    if LSM and LSM.Fetch and cfg.barTexture then
        texPath = LSM:Fetch("statusbar", cfg.barTexture) or BAR_TEXTURE
    end


    for i = 1, count do
        local offset = (i - 1) * (segSize + gap)

        local bg = container:CreateTexture(nil, "BACKGROUND")
        bg:ClearAllPoints()
        if isVertical then
            if isReverse then
                bg:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -offset)
            else
                bg:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, offset)
            end
            bg:SetSize(totalW, segSize)
        else
            if isReverse then
                bg:SetPoint("TOPRIGHT", container, "TOPRIGHT", -offset, 0)
            else
                bg:SetPoint("TOPLEFT", container, "TOPLEFT", offset, 0)
            end
            bg:SetSize(segSize, totalH)
        end
        bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        if barFrame._mask then bg:AddMaskTexture(barFrame._mask) end
        bg:Show()
        barFrame._segBGs[i] = bg

        local bar = CreateFrame("StatusBar", nil, container)
        bar:ClearAllPoints()
        if isVertical then
            if isReverse then
                bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -offset)
            else
                bar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, offset)
            end
            bar:SetSize(totalW, segSize)
        else
            if isReverse then
                bar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -offset, 0)
            else
                bar:SetPoint("TOPLEFT", container, "TOPLEFT", offset, 0)
            end
            bar:SetSize(segSize, totalH)
        end
        bar:SetStatusBarTexture(texPath)
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
        if cfg.barType == "stack" then
            bar:SetMinMaxValues(i - 1, i)
        else
            bar:SetMinMaxValues(0, 1)
        end
        bar:SetValue(0)
        bar:SetFrameLevel(container:GetFrameLevel() + 1)
        ConfigureLinearStatusBar(bar, cfg)
        
        if barFrame._mask then
            bar:GetStatusBarTexture():AddMaskTexture(barFrame._mask)
        end

        if perSegBorder and borderSize > 0 then
            local border = CreateFrame("Frame", nil, container, "BackdropTemplate")
            border:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSize, borderSize)
            border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSize, -borderSize)
            border:SetBackdrop({
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = borderSize,
            })
            border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
            border:SetFrameLevel(bar:GetFrameLevel() + 2)
            border:Show()
            barFrame._segBorders[i] = border
        end

        barFrame._segments[i] = bar
    end

    if perSegBorder then
        if barFrame._mbBorder then barFrame._mbBorder:Hide() end
    else
        MB.ApplyMaskAndBorderSettings(barFrame, cfg)
    end
end






AnchorToJustifyH = function(anchor)
    if anchor == "LEFT" or anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" then
        return "LEFT"
    elseif anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then
        return "CENTER"
    else
        return "RIGHT"
    end
end





ANCHOR_POINT = {
    TOPLEFT     = "BOTTOMLEFT",  TOP     = "BOTTOM",  TOPRIGHT     = "BOTTOMRIGHT",
    LEFT        = "LEFT",        CENTER  = "CENTER",  RIGHT        = "RIGHT",
    BOTTOMLEFT  = "TOPLEFT",     BOTTOM  = "TOP",     BOTTOMRIGHT  = "TOPRIGHT",
}
ANCHOR_REL = {
    TOPLEFT     = "TOPLEFT",     TOP     = "TOP",     TOPRIGHT     = "TOPRIGHT",
    LEFT        = "LEFT",        CENTER  = "CENTER",  RIGHT        = "RIGHT",
    BOTTOMLEFT  = "BOTTOMLEFT",  BOTTOM  = "BOTTOM",  BOTTOMRIGHT  = "BOTTOMRIGHT",
}





function MB:CreateBarFrame(barCfg)
    -- Create persistent frame state once per bar id.
    local id = barCfg.id
    if activeFrames[id] then return activeFrames[id] end

    local f = CreateFrame("Frame", "SimpleMonitorBarsMonitorBar" .. id, UIParent, "BackdropTemplate")
    local w, h = MB.getNearestPixel(barCfg.width, barCfg.scale), MB.getNearestPixel(barCfg.height, barCfg.scale)
    f:SetSize(w, h)
    local pX = MB.getNearestPixel(barCfg.posX, barCfg.scale)
    local pY = MB.getNearestPixel(barCfg.posY, barCfg.scale)
    f:SetPoint("CENTER", UIParent, "CENTER", pX, pY)
    local strata = barCfg.frameStrata or "MEDIUM"
    local baseLevel = GetBaseFrameLevelByStrata(strata)
    f:SetFrameStrata(strata)
    f:SetFrameLevel(baseLevel)
    f:SetClampedToScreen(true)
    f._barID = id

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    local bgc = barCfg.bgColor or { 0.1, 0.1, 0.1, 0.6 }
    f.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])


    f._mask = f:CreateMaskTexture()
    f._mask:SetAllPoints()
    f._mask:SetTexture(COVER_TEXTURE)
    f.bg:AddMaskTexture(f._mask)


    f._borderFrame = CreateFrame("Frame", nil, f)
    f._borderFrame:SetAllPoints()
    f._borderFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    f._border = f._borderFrame:CreateTexture(nil, "OVERLAY")
    f._border:SetAllPoints()
    f._border:SetBlendMode("BLEND")
    f._border:Hide()

    local iconSize = h
    f._icon = f:CreateTexture(nil, "ARTWORK")
    f._icon:SetSize(iconSize, iconSize)
    f._icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local showIcon = barCfg.showIcon ~= false
    local segOffset = showIcon and (iconSize + 2) or 0
    f._segContainer = CreateFrame("Frame", nil, f)
    f._segContainer:SetPoint("TOPLEFT", f, "TOPLEFT", segOffset, 0)
    f._segContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f._segContainer:SetFrameLevel(f:GetFrameLevel() + 1)
    f._segContainer:SetClipsChildren(true)

    f._textHolder = CreateFrame("Frame", nil, f)
    f._textHolder:SetAllPoints(f._segContainer)
    f._textHolder:SetFrameLevel(f:GetFrameLevel() + 6)

    f._text = f._textHolder:CreateFontString(nil, "OVERLAY")
    ConfigurePrimaryText(f, barCfg)
    f._countText = f._textHolder:CreateFontString(nil, "OVERLAY")
    ConfigureCountText(f, barCfg)
    AttachDragHandlers(f, barCfg)
    AttachWheelHandlers(f, barCfg)
    AttachTooltipHandlers(f, barCfg)

    local locked = ns.db and ns.db.monitorBars and ns.db.monitorBars.locked
    f:EnableMouseWheel(not locked)

    f._cfg = barCfg
    f._cooldownID = nil
    f._cdmFrame = nil
    f._cachedMaxCharges = 0
    f._cachedChargeDuration = 0
    f._needsChargeRefresh = true
    f._cachedChargeInfo = nil
    f._needsDurationRefresh = true
    f._cachedChargeDurObj = nil
    f._lastRechargingSlot = nil
    f._chargeBG = nil
    f._chargeBar = nil
    f._refreshCharge = nil
    f._refreshChargeText = nil
    f._chargeBorders = nil
    f._trackedAuraInstanceID = nil
    f._trackedUnit = nil
    f._lastKnownActive = false
    f._lastKnownStacks = 0
    f._nilCount = 0
    f._isChargeSpell = nil
    f._shadowCooldown = nil
    f._arcFeedFrame = 0
    f._recentlyRemovedAuraInstanceID = nil
    f._recentlyRemovedAuraExpiresAt = nil

    activeFrames[id] = f
    return f
end

function MB:GetSize(barFrame)
    local cfg = barFrame._cfg
    if not cfg then return 200, 20 end
    
    local width = cfg.width
    local scale = cfg.scale or 1
    local height = cfg.height
    
    return MB.getNearestPixel(width, scale), MB.getNearestPixel(height, scale)
end

function MB:ApplyStyle(barFrame)
    local cfg = barFrame._cfg
    if not cfg then return end

    local width, height = self:GetSize(barFrame)
    barFrame:SetSize(width, height)

    local strata = cfg.frameStrata or "MEDIUM"
    local baseLevel = GetBaseFrameLevelByStrata(strata)
    barFrame:SetFrameStrata(strata)
    barFrame:SetFrameLevel(baseLevel)
    if barFrame._segContainer then barFrame._segContainer:SetFrameStrata(strata) end
    if barFrame._textHolder    then barFrame._textHolder:SetFrameStrata(strata) end
    if barFrame._borderFrame   then barFrame._borderFrame:SetFrameStrata(strata) end
    if barFrame._segContainer then barFrame._segContainer:SetFrameLevel(baseLevel + 1) end
    if barFrame._textHolder    then barFrame._textHolder:SetFrameLevel(baseLevel + 6) end
    if barFrame._borderFrame   then barFrame._borderFrame:SetFrameLevel(baseLevel + 5) end
    if barFrame._segments then
        for _, seg in ipairs(barFrame._segments) do
            seg:SetFrameStrata(strata)
            seg:SetFrameLevel(baseLevel + 2)
            ConfigureLinearStatusBar(seg, cfg)
        end
    end
    if barFrame._chargeBar then
        barFrame._chargeBar:SetFrameStrata(strata)
        barFrame._chargeBar:SetFrameLevel(baseLevel + 2)
        ConfigureLinearStatusBar(barFrame._chargeBar, cfg)
    end
    if barFrame._refreshCharge then
        barFrame._refreshCharge:SetFrameStrata(strata)
        barFrame._refreshCharge:SetFrameLevel(baseLevel + 3)
        ConfigureLinearStatusBar(barFrame._refreshCharge, cfg)
    end
    if barFrame._segBorders then
        for _, border in ipairs(barFrame._segBorders) do
            border:SetFrameStrata(strata)
            border:SetFrameLevel(baseLevel + 4)
        end
    end
    if barFrame._chargeBorders then
        for _, border in ipairs(barFrame._chargeBorders) do
            border:SetFrameStrata(strata)
            border:SetFrameLevel(baseLevel + 4)
        end
    end

    local bgc = cfg.bgColor or { 0.1, 0.1, 0.1, 0.6 }
    barFrame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])

    local iconSize = height
    barFrame._icon:SetSize(iconSize, iconSize)
    
    local showIcon = cfg.showIcon ~= false
    barFrame._icon:SetShown(showIcon)
    if barFrame._iconMask then barFrame._iconMask:Hide() end


    if cfg.showSpellName then
        if not barFrame._nameText then
            barFrame._nameText = barFrame._textHolder:CreateFontString(nil, "OVERLAY")
        end
        local fontPath = ResolveFontPath(cfg.nameFontName or cfg.fontName)
        barFrame._nameText:SetFont(fontPath, cfg.nameFontSize or 14, cfg.nameOutline or cfg.outline or "OUTLINE")
        
        local nAnchor = cfg.nameAnchor or "RIGHT"
        local nX = cfg.nameOffsetX or 0
        local nY = cfg.nameOffsetY or 0
        
        barFrame._nameText:ClearAllPoints()
        barFrame._nameText:SetPoint(ANCHOR_POINT[nAnchor] or nAnchor, barFrame._textHolder, ANCHOR_REL[nAnchor] or nAnchor, nX, nY)
        barFrame._nameText:SetJustifyH(AnchorToJustifyH(nAnchor))
        barFrame._nameText:SetTextColor(1, 1, 1, 1)
        barFrame._nameText:SetText(cfg.spellName or "")
        barFrame._nameText:Show()
    else
        if barFrame._nameText then barFrame._nameText:Hide() end
    end

    barFrame._icon:ClearAllPoints()
    barFrame._icon:SetPoint("LEFT", barFrame, "LEFT", 0, 0)
    barFrame.bg:Show()

    local segOffset = showIcon and (iconSize + 2) or 0
    barFrame._segContainer:ClearAllPoints()
    barFrame._segContainer:SetPoint("TOPLEFT", barFrame, "TOPLEFT", segOffset, 0)
    barFrame._segContainer:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)

    local count
    if cfg.barType == "charge" then
        count = 0
    elseif cfg.barType == "duration" then
        count = 1
    else
        count = cfg.maxStacks
    end
    if count > 0 then
        C_Timer.After(0, function()
            if barFrame._segContainer then
                CreateSegments(barFrame, count, cfg)
            end
        end)
    end

    local fontPath = ResolveFontPath(cfg.fontName)
    barFrame._text:SetFont(fontPath, cfg.fontSize or 14, cfg.outline or "OUTLINE")
    barFrame._text:SetShown(cfg.barType ~= "stack" and cfg.showText ~= false)
    local anchor = cfg.textAnchor or cfg.textAlign or "CENTER"
    barFrame._text:ClearAllPoints()
    barFrame._text:SetPoint(ANCHOR_POINT[anchor] or anchor, barFrame._textHolder, ANCHOR_REL[anchor] or anchor, cfg.textOffsetX or 0, cfg.textOffsetY or 0)
    barFrame._text:SetJustifyH(AnchorToJustifyH(anchor))
    ConfigureCountText(barFrame, cfg)
    barFrame._countText:SetShown(cfg.showCountText == true)
    if cfg.showCountText ~= true then
        barFrame._countText:SetText("")
    end

    if cfg.borderStyle == "whole" then
        MB.ApplyMaskAndBorderSettings(barFrame, cfg)
    elseif barFrame._borderFrame then
        barFrame._borderFrame:Hide()
    end

    if cfg.spellID and cfg.spellID > 0 then
        local tex = C_Spell.GetSpellTexture(cfg.spellID)
        if tex then barFrame._icon:SetTexture(tex) end
    end
end





local function ApplySegmentColors(barFrame, currentCount)
    local cfg = barFrame._cfg
    if not cfg then return end
    local segs = barFrame._segments
    if not segs then return end

    local threshold1 = cfg.colorThreshold or 0
    local threshold2 = cfg.colorThreshold2 or 0
    local c = cfg.barColor or { 0.4, 0.75, 1.0, 1 }

    if type(currentCount) == "number" then

        if threshold2 > 0 and currentCount >= threshold2 then
            c = cfg.thresholdColor2 or { 1, 1, 0, 1 }
        elseif threshold1 > 0 and currentCount >= threshold1 then
            c = cfg.thresholdColor or { 1, 1, 1, 1 }
        end
    end

    for _, seg in ipairs(segs) do
        seg:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end
end

local function FindHelpfulAuraBySpellID(unit, spellID)
    if not unit or not spellID or spellID <= 0 then return nil end

    if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and aura then
            return aura
        end
    end


    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 255 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not aura then break end
            local auraSpellID = aura.spellId
            if auraSpellID and (not issecretvalue or not issecretvalue(auraSpellID)) and auraSpellID == spellID then
                return aura
            end
        end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and C_Spell and C_Spell.GetSpellName then
        local spellName = C_Spell.GetSpellName(spellID)
        if spellName and spellName ~= "" then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HELPFUL")
            if ok and aura then
                return aura
            end
        end
    end

    if AuraUtil and AuraUtil.ForEachAura then
        local found = nil
        AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
            local auraSpellID = aura and aura.spellId
            if auraSpellID and (not issecretvalue or not issecretvalue(auraSpellID)) and auraSpellID == spellID then
                found = aura
                return true
            end
            return false
        end, true)
        if found then
            return found
        end
    end

    if UnitAura then
        for i = 1, 255 do
            local name, _, count, _, _, _, _, _, _, sid = UnitAura(unit, i, "HELPFUL")
            if not name then break end
            if sid == spellID then
                return { spellId = sid, applications = count or 0, charges = count or 0 }
            end
        end
    end

    return nil
end

local function UpdateBarActiveState(barFrame, isActive)
    local wasActive = barFrame._isActive
    barFrame._isActive = (isActive == true)
    local cfg = barFrame._cfg
    if cfg and cfg.showCondition == "active_only" and wasActive ~= barFrame._isActive then
        barFrame:SetShown(ShouldBarBeVisible(cfg, barFrame))
    end
end

local function ResolveTrackedCooldownID(spellID)
    if not FindCooldownIDBySpellID then
        return nil
    end
    return FindCooldownIDBySpellID(spellID)
end

local function ResolveRuntimeSpellID(spellID)
    if not spellID or spellID <= 0 then
        return nil
    end

    if C_Spell and C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID > 0 and overrideID ~= spellID then
            return overrideID
        end
    end

    return spellID
end

local function GetStackCountFromAuraOrFrame(auraData, cdmFrame)
    if auraData then
        if auraData.applications ~= nil then
            return auraData.applications
        end
        if auraData.charges ~= nil then
            return auraData.charges
        end
    end

    if cdmFrame then
        if cdmFrame.applications ~= nil then
            return cdmFrame.applications
        end
        if cdmFrame.numApplications ~= nil then
            return cdmFrame.numApplications
        end
        if cdmFrame.applicationText and cdmFrame.applicationText.GetText then
            local txt = cdmFrame.applicationText:GetText()
            local n = tonumber(txt)
            if n then
                return n
            end
        end
    end

    return 0
end

local function GetAuraDataByInstanceID(auraInstanceID, preferredUnit, secondUnit)
    if not HasAuraInstanceID(auraInstanceID) or not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then
        return nil, nil
    end

    local units, exists = {}, {}
    local function AddUnit(unit)
        if type(unit) == "string" and unit ~= "" and not exists[unit] then
            exists[unit] = true
            units[#units + 1] = unit
        end
    end

    AddUnit(preferredUnit)
    AddUnit(secondUnit)
    AddUnit("player")
    AddUnit("target")
    AddUnit("pet")
    AddUnit("vehicle")
    AddUnit("focus")

    for _, unit in ipairs(units) do
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
        if auraData then
            return auraData, unit
        end
    end

    return nil, nil
end

local function WasAuraInstanceRemoved(updateInfo, auraInstanceID)
    if not updateInfo or not HasAuraInstanceID(auraInstanceID) then
        return false
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if type(removed) ~= "table" then
        return false
    end

    for i = 1, #removed do
        if removed[i] == auraInstanceID then
            return true
        end
    end

    return false
end

local function ClearRecentlyRemovedAura(barFrame, auraInstanceID)
    if not barFrame then
        return
    end

    if auraInstanceID == nil or barFrame._recentlyRemovedAuraInstanceID == auraInstanceID then
        barFrame._recentlyRemovedAuraInstanceID = nil
        barFrame._recentlyRemovedAuraExpiresAt = nil
    end
end

local function IsRecentlyRemovedAura(barFrame, auraInstanceID)
    if not barFrame or not HasAuraInstanceID(auraInstanceID) then
        return false
    end

    local removedAuraInstanceID = barFrame._recentlyRemovedAuraInstanceID
    local expiresAt = barFrame._recentlyRemovedAuraExpiresAt
    if not removedAuraInstanceID or not expiresAt then
        return false
    end

    if expiresAt <= GetTime() then
        ClearRecentlyRemovedAura(barFrame, removedAuraInstanceID)
        return false
    end

    return removedAuraInstanceID == auraInstanceID
end

local function MarkStackAuraRemoved(barFrame, auraInstanceID)
    if not (barFrame and HasAuraInstanceID(auraInstanceID)) then
        return
    end

    -- Ignore stale viewer updates for this aura briefly after UNIT_AURA reports removal.
    barFrame._recentlyRemovedAuraInstanceID = auraInstanceID
    barFrame._recentlyRemovedAuraExpiresAt = GetTime() + 0.25
    barFrame._lastKnownActive = false
    barFrame._lastKnownStacks = 0
    barFrame._trackedAuraInstanceID = nil
    barFrame._trackedUnit = nil
    barFrame._nilCount = 0
    ResetStackAnimationState(barFrame, 0)
    SetStackSegmentsValue(barFrame, 0)
    ClearCountText(barFrame)
    UpdateBarActiveState(barFrame, false)
end

local function GetIciclesStacks()
    local aura = nil
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ICICLES_SPELL_ID)
        if ok then
            aura = data
        end
    end
    if not aura and AuraUtil and AuraUtil.FindAuraBySpellID then
        local ok, data = pcall(AuraUtil.FindAuraBySpellID, ICICLES_SPELL_ID, "player", "HELPFUL")
        if ok then
            aura = data
        end
    end
    if not aura and UnitAura then
        for i = 1, 255 do
            local name, _, count, _, _, _, _, _, _, sid = UnitAura("player", i, "HELPFUL")
            if not name then break end
            if sid == ICICLES_SPELL_ID then
                aura = { applications = count or 0, charges = count or 0 }
                break
            end
        end
    end

    if not aura then
        return false, 0, nil
    end

    local count = aura.applications or aura.stacks or aura.charges or aura.count or 0
    if type(count) ~= "number" then
        count = tonumber(count) or 0
    end
    if count < 0 then count = 0 end
    if count > 5 then count = 5 end

    return count > 0, count, aura.auraInstanceID
end

local function FormatRemainingTimeText(remaining)
    local ok, result = pcall(function()
        local num = tonumber(remaining)
        if num then
            return string.format("%.1f", num)
        end
        return remaining
    end)
    if ok and result then
        return result
    end
    return remaining or ""
end

UpdateStackBar = function(barFrame)
    local cfg = barFrame._cfg
    if not cfg or cfg.barType ~= "stack" then return end

    HideChargeVisuals(barFrame)

    local spellID = cfg.spellID
    if not spellID or spellID <= 0 then return end

    local stacks = 0
    local auraActive = false
    local unitPref = cfg.unit or "player"
    local isIciclesPlayer = (spellID == ICICLES_SPELL_ID and unitPref == "player")



    if isIciclesPlayer then
        local active, icicleCount, auraInstanceID = GetIciclesStacks()
        auraActive = active
        stacks = icicleCount
        if auraInstanceID then
            barFrame._trackedAuraInstanceID = auraInstanceID
            barFrame._trackedUnit = "player"
        else
            barFrame._trackedAuraInstanceID = nil
            barFrame._trackedUnit = "player"
        end
    end

    local cooldownID = spellToCooldownID[spellID]
    if not isIciclesPlayer and not cooldownID and not auraActive then
        cooldownID = ResolveTrackedCooldownID(spellID)
    end
    barFrame._cooldownID = cooldownID

    if not isIciclesPlayer and cooldownID then
        local cdmFrame = FindCDMFrame(cooldownID)
        if cdmFrame then
            RegisterViewerSignals(cdmFrame, barFrame._barID)
            barFrame._cdmFrame = cdmFrame

            if HasAuraInstanceID(cdmFrame.auraInstanceID) and not IsRecentlyRemovedAura(barFrame, cdmFrame.auraInstanceID) then
                local baseUnit = cdmFrame.auraDataUnit or unitPref or barFrame._trackedUnit or "player"
                local auraData, trackedUnit = GetAuraDataByInstanceID(cdmFrame.auraInstanceID, baseUnit, barFrame._trackedUnit)
                if trackedUnit then
                    barFrame._trackedUnit = trackedUnit
                else
                    barFrame._trackedUnit = baseUnit
                end
                auraActive = auraData ~= nil
                stacks = GetStackCountFromAuraOrFrame(auraData, cdmFrame)
                barFrame._trackedAuraInstanceID = cdmFrame.auraInstanceID
            end
        end
    end

    if not isIciclesPlayer
        and not auraActive
        and HasAuraInstanceID(barFrame._trackedAuraInstanceID)
        and not IsRecentlyRemovedAura(barFrame, barFrame._trackedAuraInstanceID) then
        local auraData, trackedUnit = GetAuraDataByInstanceID(barFrame._trackedAuraInstanceID, barFrame._trackedUnit, unitPref)
        if auraData then
            auraActive = true
            stacks = GetStackCountFromAuraOrFrame(auraData, barFrame._cdmFrame)
            if trackedUnit then
                barFrame._trackedUnit = trackedUnit
            end
        end
    end


    if not isIciclesPlayer and not auraActive then
        local primaryUnit = unitPref
        local auraData = FindHelpfulAuraBySpellID(primaryUnit, spellID)
        local unit = primaryUnit
        if not auraData then
            unit = (primaryUnit == "player") and "target" or "player"
            auraData = FindHelpfulAuraBySpellID(unit, spellID)
        end
        if auraData then
            auraActive = true
            stacks = GetStackCountFromAuraOrFrame(auraData, barFrame._cdmFrame)
            barFrame._trackedAuraInstanceID = auraData.auraInstanceID
            barFrame._trackedUnit = unit
        end
    end

    if not auraActive then
        if barFrame._lastKnownActive then


            if spellID == ICICLES_SPELL_ID then
                barFrame._lastKnownActive = false
                barFrame._lastKnownStacks = 0
                barFrame._trackedAuraInstanceID = nil
                barFrame._nilCount = 0
                ResetStackAnimationState(barFrame, 0)
                stacks = 0
            else
                stacks = barFrame._lastKnownStacks or 0
                barFrame._nilCount = (barFrame._nilCount or 0) + 1
                if barFrame._nilCount > 5 then
                    barFrame._lastKnownActive = false
                    barFrame._lastKnownStacks = 0
                    barFrame._trackedAuraInstanceID = nil
                    barFrame._trackedUnit = nil
                    stacks = 0
                end
            end
        end
    else
        barFrame._nilCount = 0
    end

    local isSecret = issecretvalue and issecretvalue(stacks)
    local rawStacks = stacks

    local stacksResolved = not isSecret
    local maxStacks = cfg.maxStacks or 5
    local stacksForColor = stacks
    local stacksForText = stacks
    local segs = barFrame._segments
    if segs then
        if isSecret then
            stacksForText = rawStacks
        else
            barFrame._arcFeedFrame = 0
            if barFrame._arcDetectors then
                for i = 1, maxStacks do
                    local det = barFrame._arcDetectors[i]
                    if det then det:SetValue(0) end
                end
            end
        end

        if isIciclesPlayer and not isSecret then
            ResetStackAnimationState(barFrame, stacks)
            SetStackSegmentsValue(barFrame, stacks)
        elseif isSecret then
            barFrame._displayStacks = nil
            barFrame._targetStacks = nil
            SetStackSegmentsValue(barFrame, rawStacks)
            FeedArcDetectors(barFrame, rawStacks, maxStacks)
            local resolved = GetExactCount(barFrame, maxStacks)
            if type(resolved) == "number" then
                stacksForColor = resolved
                stacksResolved = true
            else
                stacksResolved = false
            end
        elseif stacksResolved then
            local prevDisplay = barFrame._displayStacks
            local smooth = (cfg.smoothAnimation ~= false)
            if prevDisplay == nil or not smooth then
                barFrame._displayStacks = stacks
                barFrame._targetStacks  = stacks
                SetStackSegmentsValue(barFrame, stacks)
            else
                barFrame._targetStacks = stacks
                if stacks < prevDisplay then
                    barFrame._displayStacks = stacks
                    SetStackSegmentsValue(barFrame, stacks)
                end
            end
        end
    end

    if auraActive then
        barFrame._lastKnownActive = true
        if not isSecret and type(stacks) == "number" then
            barFrame._lastKnownStacks = stacks
        elseif stacksResolved and type(stacksForColor) == "number" then
            barFrame._lastKnownStacks = stacksForColor
        end
    end

    if stacksResolved and type(stacksForColor) == "number" then
        ApplySegmentColors(barFrame, stacksForColor)
    end

    if isSecret then
        SetCountText(barFrame, stacksForText)
    elseif type(stacks) == "number" then
        SetCountText(barFrame, tostring(stacks))
    else
        ClearCountText(barFrame)
    end
    if barFrame._text then
        barFrame._text:SetText("")
    end

    UpdateBarActiveState(barFrame, auraActive)
end

local function UpdateRegularCooldownBar(barFrame)
    local cfg = barFrame._cfg
    local spellID = ResolveRuntimeSpellID(cfg.spellID or 0) or cfg.spellID

    HideChargeVisuals(barFrame)

    local isOnGCD = false
    pcall(function()
        local cdInfo = C_Spell.GetSpellCooldown(spellID)
        if cdInfo and cdInfo.isOnGCD == true then isOnGCD = true end
    end)

    local cooldownID = spellToCooldownID[spellID]
    if not cooldownID and cfg.spellID and cfg.spellID > 0 then
        cooldownID = spellToCooldownID[cfg.spellID]
    end
    if not cooldownID then
        cooldownID = ResolveTrackedCooldownID(spellID)
    end
    if not cooldownID and cfg.spellID and cfg.spellID ~= spellID then
        cooldownID = ResolveTrackedCooldownID(cfg.spellID)
    end
    barFrame._cooldownID = cooldownID

    if cooldownID then
        local cdmFrame = FindCDMFrame(cooldownID)
        if cdmFrame then
            barFrame._cdmFrame = cdmFrame
        end
    end

    local shadowCD = GetOrCreateShadowCooldown(barFrame)
    local durObj = nil
    if isOnGCD then
        shadowCD:SetCooldown(0, 0)
    else
        pcall(function() durObj = C_Spell.GetSpellCooldownDuration(spellID) end)
        if durObj then
            pcall(function() shadowCD:SetCooldownFromDurationObject(durObj, true) end)
        else
            shadowCD:SetCooldown(0, 0)
        end
    end

    local isOnCooldown = shadowCD:IsShown()

    local segs = barFrame._segments
    if not segs or #segs ~= 1 then
        CreateSegments(barFrame, 1, cfg)
        segs = barFrame._segments
    end
    if not segs or #segs < 1 then return end

    local seg = segs[1]
    local durationReady = false
    local interpolation = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or 0
    local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0

    if isOnCooldown and not isOnGCD then
        if barFrame._needsDurationRefresh and durObj then
            seg:SetMinMaxValues(0, 1)
            if seg.SetTimerDuration then
                seg:SetTimerDuration(durObj, interpolation, direction)
                if seg.SetToTargetValue then
                    seg:SetToTargetValue()
                end
            else
                seg:SetMinMaxValues(0, 1)
                seg:SetValue(0)
            end
            barFrame._needsDurationRefresh = false
        end
    else
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(1)
    end

    ApplySegmentColors(barFrame, isOnCooldown and 0 or 1)

    if cfg.showText ~= false and barFrame._text then
        if isOnCooldown and not isOnGCD and durObj then
            barFrame._text:SetText(FormatRemainingTimeText(durObj:GetRemainingDuration()))
        else
            barFrame._text:SetText("")
        end
    end

    UpdateBarActiveState(barFrame, (isOnCooldown and not isOnGCD))
end

local function UpdateChargeBar(barFrame)
    local cfg = barFrame._cfg
    if not cfg or cfg.barType ~= "charge" then return end

    local spellID = ResolveRuntimeSpellID(cfg.spellID or 0) or cfg.spellID
    if not spellID or spellID <= 0 then return end

    local cooldownID = spellToCooldownID[spellID]
    if not cooldownID and cfg.spellID and cfg.spellID > 0 then
        cooldownID = spellToCooldownID[cfg.spellID]
    end
    if not cooldownID then
        cooldownID = ResolveTrackedCooldownID(spellID)
    end
    if not cooldownID and cfg.spellID and cfg.spellID ~= spellID then
        cooldownID = ResolveTrackedCooldownID(cfg.spellID)
    end
    barFrame._cooldownID = cooldownID

    if cooldownID then
        local cdmFrame = FindCDMFrame(cooldownID)
        if cdmFrame then
            barFrame._cdmFrame = cdmFrame
        end
    end

    if barFrame._needsChargeRefresh then
        barFrame._cachedChargeInfo = C_Spell.GetSpellCharges(spellID)
        barFrame._needsChargeRefresh = false
        if cfg.isChargeSpell ~= nil then
            barFrame._isChargeSpell = (cfg.isChargeSpell == true)
        else
            barFrame._isChargeSpell = barFrame._cachedChargeInfo ~= nil
        end
    end

    if barFrame._isChargeSpell == false then
        UpdateRegularCooldownBar(barFrame)
        return
    end

    local chargeInfo = barFrame._cachedChargeInfo
    if not chargeInfo then
        HideChargeVisuals(barFrame)
        if cfg.showText ~= false and barFrame._text then
            barFrame._text:SetText("")
        end
        ClearCountText(barFrame)
        UpdateBarActiveState(barFrame, false)
        return
    end

    local maxCharges = cfg.maxCharges
    if maxCharges <= 0 then
        if chargeInfo.maxCharges then
            if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
                barFrame._cachedMaxCharges = chargeInfo.maxCharges
            end
        end
        maxCharges = barFrame._cachedMaxCharges
    end
    if maxCharges <= 0 then maxCharges = 2 end

    local currentCharges = chargeInfo.currentCharges
    local isSecret = issecretvalue and issecretvalue(currentCharges)
    local exactCharges = currentCharges

    if isSecret then
        FeedArcDetectors(barFrame, currentCharges, maxCharges)
        exactCharges = GetExactCount(barFrame, maxCharges)
    end

    if barFrame._segments then
        for _, seg in ipairs(barFrame._segments) do
            seg:Hide()
        end
    end
    if barFrame._segBGs then
        for _, bg in ipairs(barFrame._segBGs) do
            bg:Hide()
        end
    end
    if barFrame._segBorders then
        for _, border in ipairs(barFrame._segBorders) do
            border:Hide()
        end
    end

    if not barFrame._chargeBG then
        local bg = barFrame._segContainer:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(barFrame._segContainer)
        barFrame._chargeBG = bg
    end
    barFrame._chargeBG:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    if barFrame._mask then
        if not barFrame._chargeBG._masked then
            barFrame._chargeBG:AddMaskTexture(barFrame._mask)
            barFrame._chargeBG._masked = true
        end
    end
    barFrame._chargeBG:Show()

    if not barFrame._chargeBar then
        local chargeBar = CreateFrame("StatusBar", nil, barFrame._segContainer)
        chargeBar:SetFrameLevel(barFrame._segContainer:GetFrameLevel() + 1)
        chargeBar:SetAllPoints(barFrame._segContainer)
        ConfigureLinearStatusBar(chargeBar, cfg)
        barFrame._chargeBar = chargeBar
    end
    barFrame._chargeBar:SetStatusBarTexture(ResolveBarTexturePath(cfg.barTexture))
    barFrame._chargeBar:SetAllPoints(barFrame._segContainer)
    ConfigureLinearStatusBar(barFrame._chargeBar, cfg)
    if barFrame._mask and barFrame._chargeBar:GetStatusBarTexture() and not barFrame._chargeBar._masked then
        barFrame._chargeBar:GetStatusBarTexture():AddMaskTexture(barFrame._mask)
        barFrame._chargeBar._masked = true
    end
    local barColor = cfg.barColor or { 0.4, 0.75, 1.0, 1 }
    barFrame._chargeBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    barFrame._chargeBar:SetMinMaxValues(0, maxCharges)
    barFrame._chargeBar:SetValue(currentCharges)
    barFrame._chargeBar:Show()

    if not barFrame._refreshCharge then
        local refreshCharge = CreateFrame("StatusBar", nil, barFrame._segContainer)
        refreshCharge:SetFrameLevel(barFrame._segContainer:GetFrameLevel() + 2)
        ConfigureLinearStatusBar(refreshCharge, cfg)
        barFrame._refreshCharge = refreshCharge
    end
    barFrame._refreshCharge:SetStatusBarTexture(ResolveBarTexturePath(cfg.barTexture))
    ConfigureLinearStatusBar(barFrame._refreshCharge, cfg)
    if barFrame._mask and barFrame._refreshCharge:GetStatusBarTexture() and not barFrame._refreshCharge._masked then
        barFrame._refreshCharge:GetStatusBarTexture():AddMaskTexture(barFrame._mask)
        barFrame._refreshCharge._masked = true
    end
    if not barFrame._refreshChargeText then
        local txt = barFrame._refreshCharge:CreateFontString(nil, "OVERLAY")
        txt:SetAllPoints(barFrame._refreshCharge)
        txt:SetJustifyH("CENTER")
        txt:SetFont(
            ResolveFontPath(cfg.fontName),
            cfg.fontSize or 14,
            cfg.outline or "OUTLINE"
        )
        txt:SetTextColor(1, 1, 1, 1)
        barFrame._refreshChargeText = txt
    end
    barFrame._refreshChargeText:SetShown(cfg.showText ~= false)

    local chargeDurObj = nil
    pcall(function()
        chargeDurObj = C_Spell.GetSpellChargeDuration(spellID)
    end)
    if chargeDurObj then
        barFrame._cachedChargeDurObj = chargeDurObj
    else
        chargeDurObj = barFrame._cachedChargeDurObj
    end
    barFrame._needsDurationRefresh = false

    local totalW = barFrame._segContainer:GetWidth()
    local totalH = barFrame._segContainer:GetHeight()
    local isVertical = IsVerticalBar(cfg)
    local isReverse = IsReverseGrowth(cfg)
    if totalW > 0 and totalH > 0 then
        local segmentSize = (isVertical and totalH or totalW) / maxCharges
        barFrame._refreshCharge:ClearAllPoints()
        if isVertical then
            barFrame._refreshCharge:SetWidth(totalW)
            barFrame._refreshCharge:SetHeight(segmentSize)
            if isReverse then
                barFrame._refreshCharge:SetPoint("TOP", barFrame._chargeBar:GetStatusBarTexture(), "BOTTOM")
            else
                barFrame._refreshCharge:SetPoint("BOTTOM", barFrame._chargeBar:GetStatusBarTexture(), "TOP")
            end
        else
            barFrame._refreshCharge:SetWidth(segmentSize)
            barFrame._refreshCharge:SetHeight(totalH)
            if isReverse then
                barFrame._refreshCharge:SetPoint("RIGHT", barFrame._chargeBar:GetStatusBarTexture(), "LEFT")
            else
                barFrame._refreshCharge:SetPoint("LEFT", barFrame._chargeBar:GetStatusBarTexture(), "RIGHT")
            end
        end
    end

    local rechargeColor = cfg.rechargeColor or cfg.barColor or { 0.4, 0.75, 1.0, 1 }
    barFrame._refreshCharge:SetStatusBarColor(rechargeColor[1], rechargeColor[2], rechargeColor[3], rechargeColor[4])

    local interpolation = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
    local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
    local activeChargeDurObj = nil
    pcall(function()
        barFrame._refreshCharge:SetTimerDuration(chargeDurObj, interpolation, direction)
    end)
    if barFrame._refreshCharge.GetTimerDuration then
        activeChargeDurObj = barFrame._refreshCharge:GetTimerDuration()
    end

    local shouldShowRecharge = (chargeDurObj ~= nil) and (activeChargeDurObj ~= nil)
    if shouldShowRecharge then
        barFrame._refreshCharge:Show()
    else
        barFrame._refreshCharge:Hide()
    end

    local borderThickness = tonumber((cfg.maskAndBorderStyle and MB.MASK_AND_BORDER_STYLES[NormalizeMaskAndBorderStyle(cfg.maskAndBorderStyle)] and MB.MASK_AND_BORDER_STYLES[NormalizeMaskAndBorderStyle(cfg.maskAndBorderStyle)].thickness) or 1) or 1
    if maxCharges > 1 and borderThickness > 0 and totalW > 0 and totalH > 0 then
        barFrame._chargeBorders = barFrame._chargeBorders or {}
        for i = maxCharges + 1, #barFrame._chargeBorders do
            if barFrame._chargeBorders[i] then
                barFrame._chargeBorders[i]:Hide()
                barFrame._chargeBorders[i] = nil
            end
        end

        local gap = tonumber(cfg.segmentGap) or 0
        local segSize = ((isVertical and totalH or totalW) - (maxCharges - 1) * gap) / maxCharges
        local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
        for i = 1, maxCharges do
            if not barFrame._chargeBorders[i] then
                local border = CreateFrame("Frame", nil, barFrame._segContainer, "BackdropTemplate")
                border:SetFrameLevel(barFrame._segContainer:GetFrameLevel() + 10)
                barFrame._chargeBorders[i] = border
            end
            local border = barFrame._chargeBorders[i]
            local offset = (i - 1) * (segSize + gap)
            border:ClearAllPoints()
            if isVertical then
                if isReverse then
                    border:SetPoint("TOPLEFT", barFrame._segContainer, "TOPLEFT", -borderThickness, -offset + borderThickness)
                    border:SetPoint("BOTTOMRIGHT", barFrame._segContainer, "TOPRIGHT", borderThickness, -(offset + segSize + borderThickness))
                else
                    border:SetPoint("BOTTOMLEFT", barFrame._segContainer, "BOTTOMLEFT", -borderThickness, offset - borderThickness)
                    border:SetPoint("TOPRIGHT", barFrame._segContainer, "BOTTOMRIGHT", borderThickness, offset + segSize + borderThickness)
                end
            else
                if isReverse then
                    border:SetPoint("TOPRIGHT", barFrame._segContainer, "TOPRIGHT", -offset + borderThickness, borderThickness)
                    border:SetPoint("BOTTOMLEFT", barFrame._segContainer, "TOPRIGHT", -(offset + segSize + borderThickness), -totalH - borderThickness)
                else
                    border:SetPoint("TOPLEFT", barFrame._segContainer, "TOPLEFT", offset - borderThickness, borderThickness)
                    border:SetPoint("BOTTOMRIGHT", barFrame._segContainer, "TOPLEFT", offset + segSize + borderThickness, -totalH - borderThickness)
                end
            end
            border:SetBackdrop({
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = borderThickness,
            })
            border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
            border:Show()
        end
    else
        if barFrame._chargeBorders then
            for _, border in ipairs(barFrame._chargeBorders) do
                border:Hide()
            end
        end
    end

    if barFrame._text then
        barFrame._text:SetText("")
    end
    if barFrame._refreshChargeText then
        if cfg.showText ~= false and shouldShowRecharge and activeChargeDurObj then
            barFrame._refreshChargeText:SetText(FormatRemainingTimeText(activeChargeDurObj:GetRemainingDuration()))
        else
            barFrame._refreshChargeText:SetText("")
        end
    end
    if type(exactCharges) == "number" then
        SetCountText(barFrame, tostring(exactCharges))
    else
        ClearCountText(barFrame)
    end

    UpdateBarActiveState(barFrame, type(exactCharges) == "number" and exactCharges < maxCharges)
end

UpdateDurationBar = function(barFrame)
    local cfg = barFrame._cfg
    if not cfg or cfg.barType ~= "duration" then return end

    HideChargeVisuals(barFrame)

    local spellID = ResolveRuntimeSpellID(cfg.spellID or 0) or cfg.spellID
    if not spellID or spellID <= 0 then return end

    local auraActive = false
    local cooldownID = spellToCooldownID[spellID]
    if not cooldownID and cfg.spellID and cfg.spellID > 0 then
        cooldownID = spellToCooldownID[cfg.spellID]
    end
    if not cooldownID then
        cooldownID = ResolveTrackedCooldownID(spellID)
    end
    if not cooldownID and cfg.spellID and cfg.spellID ~= spellID then
        cooldownID = ResolveTrackedCooldownID(cfg.spellID)
    end
    barFrame._cooldownID = cooldownID

    local cdmFrame = nil
    local auraInstanceID = nil
    local unit = nil

    local primaryUnit = cfg.unit or "player"
    local otherUnit = (primaryUnit == "player") and "target" or "player"

    -- Follow the more stable VFlow order:
    -- 1. CDM frame instance id
    -- 2. previously tracked aura instance id
    -- 3. direct aura scan fallback
    if cooldownID then
        cdmFrame = FindCDMFrame(cooldownID)
        if cdmFrame then
            RegisterViewerSignals(cdmFrame, barFrame._barID)
            barFrame._cdmFrame = cdmFrame

            if HasAuraInstanceID(cdmFrame.auraInstanceID) then
                local viewerUnit = cdmFrame.auraDataUnit or primaryUnit
                auraActive = true
                auraInstanceID = cdmFrame.auraInstanceID
                unit = viewerUnit
                barFrame._trackedAuraInstanceID = auraInstanceID
                barFrame._trackedUnit = viewerUnit
            end
        end
    end

    local auraData = nil
    if not auraActive and HasAuraInstanceID(barFrame._trackedAuraInstanceID) then
        auraData, unit = GetAuraDataByInstanceID(barFrame._trackedAuraInstanceID, barFrame._trackedUnit, primaryUnit)
        if auraData then
            auraActive = true
            auraInstanceID = barFrame._trackedAuraInstanceID
            barFrame._trackedUnit = unit
        end
    end

    if not auraActive then
        auraData = FindHelpfulAuraBySpellID(primaryUnit, spellID)
        if auraData then
            auraActive = true
            auraInstanceID = auraData.auraInstanceID
            unit = primaryUnit
            barFrame._trackedAuraInstanceID = auraData.auraInstanceID
            barFrame._trackedUnit = primaryUnit
        else
            auraData = FindHelpfulAuraBySpellID(otherUnit, spellID)
            if auraData then
                auraActive = true
                auraInstanceID = auraData.auraInstanceID
                unit = otherUnit
                barFrame._trackedAuraInstanceID = auraData.auraInstanceID
                barFrame._trackedUnit = otherUnit
            end
        end
    end


    local segs = barFrame._segments
    if not segs or #segs ~= 1 then
        CreateSegments(barFrame, 1, cfg)
        segs = barFrame._segments
    end
    if not segs or #segs < 1 then return end

    local seg = segs[1]

    if auraActive and auraInstanceID and unit then

        local timerOK = pcall(function()
            local durObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
            if durObj then
                if not ApplyDurationTimer(seg, durObj, cfg) then
                    seg:SetMinMaxValues(0, 1)
                    seg:SetValue(1)
                else
                    durationReady = true
                end

                local c = cfg.barColor or { 0.4, 0.75, 1.0, 1 }
                seg:SetStatusBarColor(c[1], c[2], c[3], c[4])


                if cfg.showText ~= false and barFrame._text then
                    local remaining = durObj:GetRemainingDuration()

                    local ok, remainingNum = pcall(tonumber, remaining)
                    if ok and remainingNum then
                        barFrame._text:SetText(string.format("%.1f", remainingNum))
                    else
                        barFrame._text:SetText(remaining)
                    end
                end
                ClearCountText(barFrame)
            else
                if cfg.showText ~= false and barFrame._text then
                    barFrame._text:SetText("")
                end
                ClearCountText(barFrame)
            end
        end)

        if not timerOK then
            seg:SetMinMaxValues(0, 1)
            seg:SetValue(1)

            if cfg.showText ~= false and barFrame._text then
                barFrame._text:SetText("")
            end
            ClearCountText(barFrame)
        end
    else

        barFrame._trackedAuraInstanceID = nil
        barFrame._trackedUnit = nil

        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)

        if cfg.showText ~= false and barFrame._text then
            barFrame._text:SetText("")
        end
        ClearCountText(barFrame)
    end


    UpdateBarActiveState(barFrame, durationReady)
end





local function UpdateAllBars()
    -- Dispatch updates by bar type for active visible bars.
    local bars = ns.db and ns.db.monitorBars and ns.db.monitorBars.bars
    if not bars then return end

    for _, barCfg in ipairs(bars) do
        local f = activeFrames[barCfg.id]
        if f and barCfg.enabled and barCfg.spellID > 0 then
            if barCfg.barType == "stack" then
                UpdateStackBar(f)
            elseif barCfg.barType == "charge" then
                UpdateChargeBar(f)
            elseif barCfg.barType == "duration" then
                UpdateDurationBar(f)
            end
        end
    end
end


local function AnimateStackBars(dt)
    -- Smoothly animate stack growth without delaying stack decreases.
    for _, barFrame in pairs(activeFrames) do
        local cfg = barFrame._cfg
        if cfg and cfg.barType == "stack" and cfg.smoothAnimation ~= false then
            local target  = barFrame._targetStacks
            local display = barFrame._displayStacks
            if target ~= nil and display ~= nil and display < target then
                local diff = target - display
                local speed = STACK_FILL_SPEED
                if diff > 1 then
                    speed = speed * diff
                end
                display = math.min(target, display + speed * dt)
                barFrame._displayStacks = display

                local segs = barFrame._segments
                if segs then
                    for i = 1, #segs do

                        segs[i]:SetValue(math.max(0, math.min(1, display - (i - 1))))
                    end
                end
            end
        end
    end
end

local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function(_, dt)
    frameTick = frameTick + 1


    AnimateStackBars(dt)

    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    UpdateAllBars()
end)
updateFrame:Hide()





local hasTarget = false
local isDragonriding = false

local function IsClassMatchedForCurrentPlayer(classTag)
    if classTag == nil or classTag == "" or classTag == "ALL" then
        return true
    end
    return classTag == PLAYER_CLASS_TAG
end

ShouldBarBeVisible = function(barCfg, barFrame)
    if not IsClassMatchedForCurrentPlayer(barCfg.class) then
        return false
    end
    local cond = barCfg.showCondition or (barCfg.combatOnly and "combat") or "always"
    if cond == "combat"          then return inCombat end
    if cond == "target"          then return hasTarget end
    if cond == "dragonriding"    then return isDragonriding end
    if cond == "not_dragonriding" then return not isDragonriding end
    if cond == "active_only"     then return barFrame and barFrame._isActive end
    return true
end

local function IsBarVisibleForSpec(barCfg)
    local specs = barCfg.specs
    if not specs or #specs == 0 then return true end
    local cur = GetSpecialization() or 1
    for _, s in ipairs(specs) do
        if s == cur then return true end
    end
    return false
end

function MB:InitAllBars()
    local bars = ns.db and ns.db.monitorBars and ns.db.monitorBars.bars
    if not bars then return end

    for _, barCfg in ipairs(bars) do
        if barCfg.enabled
            and barCfg.spellID > 0
            and IsClassMatchedForCurrentPlayer(barCfg.class)
            and IsBarVisibleForSpec(barCfg) then
            local f = self:CreateBarFrame(barCfg)
            self:ApplyStyle(f)

            local count
            if barCfg.barType == "charge" then
                count = (barCfg.maxCharges > 0 and barCfg.maxCharges or 1)
            elseif barCfg.barType == "duration" then
                count = 1
            else
                count = barCfg.maxStacks
            end
            C_Timer.After(0, function()
                if f._segContainer and f._segContainer:GetWidth() > 0 then
                    CreateSegments(f, count, barCfg)
                end
            end)

            if ShouldBarBeVisible(barCfg, f) then
                f:Show()
            else
                f:Hide()
            end
        end
    end

    updateFrame:Show()
end

function MB:DestroyBar(barID)
    local f = activeFrames[barID]
    if f then
        f:Hide()
        f:SetParent(nil)
        activeFrames[barID] = nil
    end
end

function MB:DestroyAllBars()
    for id, f in pairs(activeFrames) do
        f:Hide()
        f:SetParent(nil)
    end
    wipe(activeFrames)
    updateFrame:Hide()
end

function MB:RebuildAllBars()
    self:DestroyAllBars()
    self:InitAllBars()
end

local function RefreshBarVisibility()
    for _, f in pairs(activeFrames) do
        if f._cfg then
            f:SetShown(ShouldBarBeVisible(f._cfg, f))
        end
    end
end

function MB:OnCombatEnter()
    inCombat = true
    RefreshBarVisibility()
end

function MB:OnCombatLeave()
    inCombat = false
    RefreshBarVisibility()
    self:ScanCDMViewers()
    for _, f in pairs(activeFrames) do
        f._needsChargeRefresh = true
        f._needsDurationRefresh = true
        f._nilCount = 0
        f._isChargeSpell = nil
        if f._cfg and f._cfg.barType == "stack" then
            f._arcFeedFrame = 0
            ResetStackAnimationState(f, 0)
            if f._arcDetectors then
                for _, det in pairs(f._arcDetectors) do
                    det:SetValue(0)
                end
            end
        end
        if f._cfg and f._cfg.barType == "charge" and f._cfg.spellID > 0 then
            local chargeInfo = C_Spell.GetSpellCharges(f._cfg.spellID)
            if chargeInfo and chargeInfo.maxCharges then
                if not issecretvalue or not issecretvalue(chargeInfo.maxCharges) then
                    f._cachedMaxCharges = chargeInfo.maxCharges
                end
            end
        end
    end
end

function MB:OnChargeUpdate()
    for _, f in pairs(activeFrames) do
        f._needsChargeRefresh = true
        f._needsDurationRefresh = true
    end
end

function MB:OnCooldownUpdate()
    for _, f in pairs(activeFrames) do
        if f._cfg and f._cfg.barType == "charge" then
            f._needsDurationRefresh = true
        end
    end
end

function MB:OnAuraUpdate(unit, updateInfo)
    if unit ~= "player" and unit ~= "target" then
        return
    end

    local function RefreshStackBarForAuraUpdate(barFrame)
        if barFrame._trackedUnit == unit and WasAuraInstanceRemoved(updateInfo, barFrame._trackedAuraInstanceID) then
            MarkStackAuraRemoved(barFrame, barFrame._trackedAuraInstanceID)
            return
        end
        UpdateStackBar(barFrame)
    end

    for _, f in pairs(activeFrames) do
        if f._cfg then
            local cfgUnit = f._cfg.unit or "player"
            local matched = (cfgUnit == unit)
            if matched then
                if f._cfg.barType == "duration" then
                    QueueDurationRefresh(f)
                elseif f._cfg.barType == "stack" then
                    RefreshStackBarForAuraUpdate(f)
                end
            elseif f._cfg.barType == "duration" and unit == "target" and cfgUnit == "player" then
                QueueDurationRefresh(f)
            elseif f._cfg.barType == "stack" and unit == "target" and cfgUnit == "player" then

                RefreshStackBarForAuraUpdate(f)
            elseif f._cfg.barType == "stack" and unit == "player" and cfgUnit == "target" then

                RefreshStackBarForAuraUpdate(f)
            elseif f._cfg.barType == "duration" and unit == "player" and cfgUnit == "target" then
                QueueDurationRefresh(f)
            end
        end
    end
end

function MB:OnSkyridingChanged()
    local prev = isDragonriding
    isDragonriding = IsSkyriding()
    if isDragonriding ~= prev then
        RefreshBarVisibility()
    end
end

function MB:OnTargetChanged()
    hasTarget = UnitExists("target") == true
    for _, f in pairs(activeFrames) do
        if f._cfg then
            if f._cfg.unit == "target" then
                f._trackedAuraInstanceID = nil
            end
            f:SetShown(ShouldBarBeVisible(f._cfg, f))
        end
    end
end

function MB:SetLocked(locked)
    ns.db.monitorBars.locked = locked
    for _, f in pairs(activeFrames) do
        f:EnableMouse(not locked)
        f:EnableMouseWheel(not locked)
    end
end

function MB:GetActiveFrame(barID)
    return activeFrames[barID]
end
