
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
ns.cdmSuppressedCooldownIDs = {}

MB._spellToCooldownID = spellToCooldownID
MB._cooldownIDToFrame = cooldownIDToFrame

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
    local base = info.spellID or 0
    local linked = info.linkedSpellIDs and info.linkedSpellIDs[1]
    return linked or info.overrideSpellID or (base > 0 and base) or nil
end

local function MapSpellInfo(info, cdID, forceOverwrite)
    if not info then return end
    local sid = ResolveSpellID(info)
    if sid and sid > 0 then
        if forceOverwrite or not spellToCooldownID[sid] then
            spellToCooldownID[sid] = cdID
        end
    end
    if info.linkedSpellIDs then
        for _, lid in ipairs(info.linkedSpellIDs) do
            if lid and lid > 0 and (forceOverwrite or not spellToCooldownID[lid]) then
                spellToCooldownID[lid] = cdID
            end
        end
    end
    if info.spellID and info.spellID > 0 then
        if forceOverwrite or not spellToCooldownID[info.spellID] then
            spellToCooldownID[info.spellID] = cdID
        end
    end
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

    self:PostScanHook()
    if self.RebuildCDMSuppressedSet then
        self:RebuildCDMSuppressedSet()
    end
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
            if resolvedSpellID == spellID or info.spellID == spellID then
                foundCooldownID = cdID
            elseif info.linkedSpellIDs then
                for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                    if linkedSpellID == spellID then
                        foundCooldownID = cdID
                        break
                    end
                end
            end

            if foundCooldownID then
                spellToCooldownID[spellID] = foundCooldownID
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
