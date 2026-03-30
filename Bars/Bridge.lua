
-- Cooldown viewer scanning and spellID <-> cooldownID cache management.
local _, ns = ...

local MB = {}
ns.MonitorBars = MB

local LSM = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"

ns._mbConst = {
    DEFAULT_FONT = DEFAULT_FONT,
    BAR_TEXTURE  = BAR_TEXTURE,
    SEGMENT_GAP  = 1,
    UPDATE_INTERVAL = 0.1,
}

local spellToCooldownID = {}
local cooldownIDToFrame = {}
local nativeHiddenFrames = setmetatable({}, { __mode = "k" })
local viewerHooksInstalled = setmetatable({}, { __mode = "k" })
local nativeRefreshFrame = CreateFrame("Frame")

MB._spellToCooldownID = spellToCooldownID
MB._cooldownIDToFrame = cooldownIDToFrame

local function QueueNativeVisibilityRefresh()
    nativeRefreshFrame:Show()
end

nativeRefreshFrame:Hide()
nativeRefreshFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    if MB.RefreshNativeViewerVisibility then
        MB:RefreshNativeViewerVisibility()
    end
end)

local function HasAuraInstanceID(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return true end
    if type(value) == "number" and value == 0 then return false end
    return true
end
MB.HasAuraInstanceID = HasAuraInstanceID

function MB.ResolveFontPath(fontName)
    if not fontName or fontName == "" then return DEFAULT_FONT end
    if LSM and LSM.Fetch then
        local path = LSM:Fetch("font", fontName)
        if path then return path end
    end
    return DEFAULT_FONT
end

function MB.ConfigureStatusBar(bar)
    local tex = bar:GetStatusBarTexture()
    if tex then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
end

local VIEWER_SOURCES = {
    { name = "BuffIconCooldownViewer", aura = true },
    { name = "BuffBarCooldownViewer", aura = true },
    { name = "EssentialCooldownViewer", aura = false },
    { name = "UtilityCooldownViewer", aura = false },
}

local function GetCooldownIDFromFrame(frame)
    local cdID = frame.cooldownID
    if not cdID and frame.cooldownInfo then
        cdID = frame.cooldownInfo.cooldownID
    end
    return cdID
end

local function ResolveSpellID(info)
    if not info then return nil end
    if info.overrideSpellID and info.overrideSpellID > 0 then
        return info.overrideSpellID
    end

    local base = info.spellID or 0
    if base > 0 and C_Spell and C_Spell.GetOverrideSpell then
        local override = C_Spell.GetOverrideSpell(base)
        if override and override > 0 and override ~= base then
            return override
        end
    end

    local linked = info.linkedSpellIDs and info.linkedSpellIDs[1]
    if linked and linked > 0 then
        return linked
    end

    return (base > 0 and base) or nil
end

local function MapSpellAlias(spellID, cdID, forceOverwrite)
    if not spellID or spellID <= 0 then
        return
    end

    if forceOverwrite or not spellToCooldownID[spellID] then
        spellToCooldownID[spellID] = cdID
    end

    if C_Spell and C_Spell.GetBaseSpell then
        local baseID = C_Spell.GetBaseSpell(spellID)
        if baseID and baseID > 0 and baseID ~= spellID then
            if forceOverwrite or not spellToCooldownID[baseID] then
                spellToCooldownID[baseID] = cdID
            end
        end
    end
end

local function MapSpellInfo(info, cdID, forceOverwrite)
    if not info then return end
    local sid = ResolveSpellID(info)
    MapSpellAlias(sid, cdID, forceOverwrite)
    if info.linkedSpellIDs then
        for _, lid in ipairs(info.linkedSpellIDs) do
            MapSpellAlias(lid, cdID, forceOverwrite)
        end
    end
    MapSpellAlias(info.spellID, cdID, forceOverwrite)
end

local function BuildSpellCandidateSet(spellID)
    local candidates = {}
    if not spellID or spellID <= 0 then
        return candidates
    end

    candidates[spellID] = true

    if C_Spell and C_Spell.GetBaseSpell then
        local baseID = C_Spell.GetBaseSpell(spellID)
        if baseID and baseID > 0 then
            candidates[baseID] = true
        end
    end

    if C_Spell and C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID > 0 then
            candidates[overrideID] = true
        end
    end

    return candidates
end

local function IterateViewerFrames(viewer, visit)
    if not viewer or not visit then
        return
    end

    if viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            visit(frame)
        end
        return
    end

    for _, child in ipairs({ viewer:GetChildren() }) do
        visit(child)
    end
end

local function IterateViewerSources(visit)
    for i = 1, #VIEWER_SOURCES do
        local source = VIEWER_SOURCES[i]
        local viewer = _G[source.name]
        if viewer then
            visit(viewer, source)
        end
    end
end

local function BuildHiddenSpellSet()
    local hidden = {}
    local bars = ns.db and ns.db.monitorBars and ns.db.monitorBars.bars
    if type(bars) ~= "table" then
        return hidden
    end

    for _, barCfg in ipairs(bars) do
        if type(barCfg) == "table"
            and barCfg.enabled ~= false
            and barCfg.hideInNativeCooldownViewer == true
            and type(barCfg.spellID) == "number"
            and barCfg.spellID > 0 then
            hidden[barCfg.spellID] = true
            if C_Spell and C_Spell.GetBaseSpell then
                local baseID = C_Spell.GetBaseSpell(barCfg.spellID)
                if type(baseID) == "number" and baseID > 0 then
                    hidden[baseID] = true
                end
            end
            if C_Spell and C_Spell.GetOverrideSpell then
                local overrideID = C_Spell.GetOverrideSpell(barCfg.spellID)
                if type(overrideID) == "number" and overrideID > 0 then
                    hidden[overrideID] = true
                end
            end
        end
    end

    return hidden
end

local function IsPositiveSpellID(spellID)
    if spellID == nil then
        return false
    end
    if issecretvalue and issecretvalue(spellID) then
        return false
    end
    return type(spellID) == "number" and spellID > 0
end

local function AddSpellCandidate(candidates, spellID)
    if IsPositiveSpellID(spellID) then
        candidates[#candidates + 1] = spellID
    end
end

local function CollectFrameSpellCandidates(frame)
    local candidates = {}
    if not frame then
        return candidates
    end

    if frame.GetSpellID then
        AddSpellCandidate(candidates, frame:GetSpellID())
    end
    if frame.GetAuraSpellID then
        AddSpellCandidate(candidates, frame:GetAuraSpellID())
    end

    local cdID = GetCooldownIDFromFrame(frame)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        if info then
            AddSpellCandidate(candidates, info.overrideSpellID)
            if info.linkedSpellIDs then
                for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                    AddSpellCandidate(candidates, linkedSpellID)
                end
            end
            AddSpellCandidate(candidates, ResolveSpellID(info))
            AddSpellCandidate(candidates, info.spellID)
        end
    end

    return candidates
end

local function ShouldHideNativeFrame(frame, hiddenSpellSet)
    if not frame then
        return false
    end

    for _, spellID in ipairs(CollectFrameSpellCandidates(frame)) do
        if hiddenSpellSet[spellID] then
            return true
        end
    end
    return false
end

local function RestoreNativeFrame(frame, isAuraViewer)
    if not nativeHiddenFrames[frame] then
        return
    end

    nativeHiddenFrames[frame] = nil
    if frame.SetAlpha and frame:GetAlpha() < 0.1 then
        frame:SetAlpha(1)
    end
    if not isAuraViewer and frame.Show and not frame:IsShown() then
        frame:Show()
    end
end

local function HideNativeFrame(frame, isAuraViewer)
    if not frame then
        return
    end
    nativeHiddenFrames[frame] = true
    if not isAuraViewer and frame.Hide then
        frame:Hide()
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
    end
end

local function EnsureViewerHooks(viewer)
    if not viewer or viewerHooksInstalled[viewer] then
        return
    end

    if viewer.RefreshData then
        hooksecurefunc(viewer, "RefreshData", QueueNativeVisibilityRefresh)
    end
    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", QueueNativeVisibilityRefresh)
    end
    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", QueueNativeVisibilityRefresh)
    end
    if viewer.itemFramePool then
        hooksecurefunc(viewer.itemFramePool, "Acquire", QueueNativeVisibilityRefresh)
        hooksecurefunc(viewer.itemFramePool, "Release", QueueNativeVisibilityRefresh)
    end

    viewerHooksInstalled[viewer] = true
end

local function ResetViewerCaches()
    wipe(spellToCooldownID)
    wipe(cooldownIDToFrame)
end

local function RememberViewerFrame(frame, isAuraViewer)
    local cdID = GetCooldownIDFromFrame(frame)
    if not cdID then
        return
    end

    cooldownIDToFrame[cdID] = frame
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    MapSpellInfo(info, cdID, isAuraViewer)
end

local function SeedCooldownCatalogMappings()
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        return
    end

    for _, categoryID in ipairs({ 2, 3 }) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(categoryID, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                MapSpellInfo(info, cdID, true)
            end
        end
    end
end

local function RefreshViewerCaches()
    ResetViewerCaches()
    SeedCooldownCatalogMappings()

    IterateViewerSources(function(viewer, source)
        IterateViewerFrames(viewer, function(frame)
            RememberViewerFrame(frame, source.aura)
        end)
    end)
end

local function BuildCatalogEntry(frame, source, seen)
    local cdID = GetCooldownIDFromFrame(frame)
    if not cdID then
        return nil
    end

    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    local spellID = ResolveSpellID(info)
    if not spellID or spellID <= 0 or seen[spellID] then
        return nil
    end

    local name = C_Spell.GetSpellName(spellID)
    if not name then
        return nil
    end

    seen[spellID] = true
    return {
        spellID = spellID,
        name = name,
        icon = C_Spell.GetSpellTexture(spellID),
        unit = frame.auraDataUnit or "player",
        isAura = source.aura,
    }
end

function MB:ScanCDMViewers()
    if InCombatLockdown() then return end

    RefreshViewerCaches()
    IterateViewerSources(function(viewer)
        EnsureViewerHooks(viewer)
    end)

    self:PostScanHook()
end

function MB:RefreshNativeViewerVisibility()
    local hiddenSpellSet = BuildHiddenSpellSet()

    IterateViewerSources(function(viewer, source)
        EnsureViewerHooks(viewer)
        IterateViewerFrames(viewer, function(frame)
            if ShouldHideNativeFrame(frame, hiddenSpellSet) then
                HideNativeFrame(frame, source.aura)
            else
                RestoreNativeFrame(frame, source.aura)
            end
        end)
    end)
end

function MB.FindCDMFrame(cooldownID)
    if not cooldownID then return nil end

    local cached = cooldownIDToFrame[cooldownID]
    if cached then
        return cached
    end

    IterateViewerSources(function(viewer)
        if cached then
            return
        end

        IterateViewerFrames(viewer, function(frame)
            if cached then
                return
            end

            local frameCooldownID = GetCooldownIDFromFrame(frame)
            if frameCooldownID == cooldownID then
                cooldownIDToFrame[frameCooldownID] = frame
                cached = frame
            end
        end)
    end)

    return cached
end

function MB.FindCooldownIDBySpellID(spellID)
    if not spellID or spellID <= 0 then
        return nil
    end

    local cached = spellToCooldownID[spellID]
    if cached then
        return cached
    end

    local foundCooldownID
    local wantedSpellIDs = BuildSpellCandidateSet(spellID)
    IterateViewerSources(function(viewer)
        if foundCooldownID then
            return
        end

        IterateViewerFrames(viewer, function(frame)
            if foundCooldownID then
                return
            end

            local cdID = GetCooldownIDFromFrame(frame)
            if not cdID then
                return
            end

            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if not info then
                return
            end

            local resolvedSpellID = ResolveSpellID(info)
            if (resolvedSpellID and wantedSpellIDs[resolvedSpellID])
                or (info.spellID and wantedSpellIDs[info.spellID]) then
                foundCooldownID = cdID
            elseif info.linkedSpellIDs then
                for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                    if wantedSpellIDs[linkedSpellID] then
                        foundCooldownID = cdID
                        break
                    end
                end
            end

            if foundCooldownID then
                for wantedSpellID in pairs(wantedSpellIDs) do
                    spellToCooldownID[wantedSpellID] = foundCooldownID
                end
                cooldownIDToFrame[foundCooldownID] = frame
            end
        end)
    end)

    return foundCooldownID
end

function MB:GetSpellCatalog()
    local cooldowns, auras = {}, {}
    local seen = {}

    IterateViewerSources(function(viewer, source)
        IterateViewerFrames(viewer, function(frame)
            local entry = BuildCatalogEntry(frame, source, seen)
            if not entry then
                return
            end

            if entry.isAura then
                auras[#auras + 1] = entry
            else
                cooldowns[#cooldowns + 1] = entry
            end
        end)
    end)

    table.sort(cooldowns, function(a, b) return a.name < b.name end)
    table.sort(auras, function(a, b) return a.name < b.name end)
    return cooldowns, auras
end
