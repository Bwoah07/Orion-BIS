-- Loot tables, read live from the game's Encounter Journal (Adventure Guide), so every raid and dungeon of every
-- expansion works without shipping item data, and new seasons need no addon update.
-- Also keeps an index itemId -> "Boss · Instance" so lists can show where each item drops.

local _, ns = ...
local L = ns.L

local Loot = {}
ns.Loot = Loot


local function available() return type(EJ_GetInstanceByIndex) == "function" and C_EncounterJournal ~= nil end
Loot.Available = available

-- The Adventure Guide shares this state with us; leave it alone while it's open.
local function journalBusy() return EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() end
Loot.JournalBusy = journalBusy

function Loot.Tiers()
    local tiers = {}
    if not available() then return tiers end
    for i = 1, (EJ_GetNumTiers() or 0) do
        tiers[#tiers + 1] = { id = i, name = EJ_GetTierInfo(i) }
    end
    return tiers
end

function Loot.CurrentTier()
    return (EJ_GetCurrentTier and EJ_GetCurrentTier()) or (EJ_GetNumTiers and EJ_GetNumTiers()) or 1
end

--- Raids (isRaid true) or dungeons of a tier: { { id=, name=, art= }, ... }, as the journal lists them.
--- art is the journal's lore picture (or its background), used as the loot page banner.
function Loot.Instances(tier, isRaid)
    local result = {}
    if not available() then return result end
    EJ_SelectTier(tier)
    local i = 1
    while true do
        local instanceId, name, _, bgImage, _, loreImage = EJ_GetInstanceByIndex(i, isRaid)
        if not instanceId then break end
        local art = (loreImage and loreImage ~= 0 and loreImage) or (bgImage and bgImage ~= 0 and bgImage) or nil
        result[#result + 1] = { id = instanceId, name = name, art = art }
        i = i + 1
    end
    return result
end

function Loot.Encounters(instanceId)
    local result = {}
    if not available() then return result end
    EJ_SelectInstance(instanceId)
    local i = 1
    while true do
        local name, _, encounterId = EJ_GetEncounterInfoByIndex(i, instanceId)
        if not encounterId then break end
        -- The boss's journal portrait (a 128x64 bust).
        local portrait
        if type(EJ_GetCreatureInfo) == "function" then
            local ok, _, _, _, _, icon = pcall(EJ_GetCreatureInfo, 1, encounterId)
            if ok and icon and icon ~= 0 then portrait = icon end
        end
        result[#result + 1] = { id = encounterId, name = name, portrait = portrait }
        i = i + 1
    end
    return result
end

--- The difficulties (from `ids`, in that order) the journal has for an instance.
function Loot.ValidDifficulties(instanceId, ids)
    local result = {}
    if not available() then return result end
    EJ_SelectInstance(instanceId)
    for _, id in ipairs(ids) do
        if not EJ_IsValidInstanceDifficulty or EJ_IsValidInstanceDifficulty(id) then result[#result + 1] = id end
    end
    return result
end

local function applyFilter(filter)
    if C_EncounterJournal.ResetSlotFilter then C_EncounterJournal.ResetSlotFilter() end
    local _, _, classId = UnitClass("player")
    if filter == "spec" and GetSpecialization and GetSpecializationInfo then
        local specId = GetSpecialization() and GetSpecializationInfo(GetSpecialization())
        EJ_SetLootFilter(classId, specId or 0)
    elseif filter == "class" then
        EJ_SetLootFilter(classId, 0)
    elseif EJ_ResetLootFilter then
        EJ_ResetLootFilter()
    end
end

--- Items of one encounter: { { itemId=, name=, link=, icon=, slot=, armorType=, quality= }, ... }.
--- difficulty: a difficulty ID (sets the item levels in links) or nil to leave it.
--- filter: "spec" (your loot spec's items), "class" or "all". `pending` is true while item data is still loading;
--- EJ_LOOT_DATA_RECIEVED fires when more arrives.
function Loot.Items(instanceId, encounterId, difficulty, filter)
    local items, pending = {}, false
    if not available() then return items, false end
    -- The loot filter and difficulty are shared with the Adventure Guide: put them back afterwards.
    local oldClass, oldSpec = EJ_GetLootFilter and EJ_GetLootFilter()
    local oldDifficulty = EJ_GetDifficulty and EJ_GetDifficulty()
    EJ_SelectInstance(instanceId)
    if difficulty and EJ_SetDifficulty and (not EJ_IsValidInstanceDifficulty or EJ_IsValidInstanceDifficulty(difficulty)) then
        EJ_SetDifficulty(difficulty)
    end
    applyFilter(filter)
    EJ_SelectEncounter(encounterId)
    local getNum = C_EncounterJournal.GetNumLoot or EJ_GetNumLoot
    local count = (getNum and getNum()) or 0
    for i = 1, count do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then
            if not info.name then pending = true end
            items[#items + 1] = {
                itemId = info.itemID, name = info.name, link = info.link, icon = info.icon,
                slot = info.slot, armorType = info.armorType, quality = info.itemQuality,
            }
        end
    end
    if oldClass then EJ_SetLootFilter(oldClass, oldSpec or 0) end
    if oldDifficulty and EJ_SetDifficulty then EJ_SetDifficulty(oldDifficulty) end
    return items, pending
end

-- ---- Where an item drops -------------------------------------------------------------------

local sources = {}   -- itemId -> { boss=, instance= }
local indexedTiers = {}

--- Index every raid and dungeon of a tier (once per session). Cheap: the journal is local data.
function Loot.IndexTier(tier)
    if indexedTiers[tier] or not available() or journalBusy() then return end
    indexedTiers[tier] = true
    for _, isRaid in ipairs({ true, false }) do
        for _, instance in ipairs(Loot.Instances(tier, isRaid)) do
            for _, encounter in ipairs(Loot.Encounters(instance.id)) do
                for _, item in ipairs(Loot.Items(instance.id, encounter.id, nil, "all")) do
                    if not sources[item.itemId] then
                        sources[item.itemId] = { boss = encounter.name, instance = instance.name }
                    end
                end
            end
        end
    end
end

function Loot.Remember(itemId, boss, instance)
    sources[itemId] = { boss = boss, instance = instance }
    OrionBiSDB.sources = OrionBiSDB.sources or {}
    OrionBiSDB.sources[itemId] = boss .. "\t" .. instance
end

--- "Boss · Instance", or nil if we don't know.
function Loot.Source(itemId)
    local s = sources[itemId]
    if not s and OrionBiSDB.sources and OrionBiSDB.sources[itemId] then
        local boss, instance = OrionBiSDB.sources[itemId]:match("^(.-)\t(.*)$")
        if boss then s = { boss = boss, instance = instance }; sources[itemId] = s end
    end
    return s
end

function Loot.SourceText(itemId)
    local s = Loot.Source(itemId)
    return s and (s.boss .. "  ·  " .. s.instance) or L["Unknown source"]
end
