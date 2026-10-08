-- Orion BiS: raid wishlists in game, for any guild.
--   * Browse every boss's loot and mark items BiS / Upgrade / Minor, or import a list from your guild's website.
--   * Lists are shared with your guild automatically (hidden addon messages), so everyone sees who wants what.
--   * A drop alert when an item on your list drops, and who else wants it; item tooltips list who wants the item.
-- Data: OrionBiSDB.lists (one list per character, newest wins). Sources: your own edits, pasted codes, the guild,
-- and an optional private companion addon (OrionBiS_GuildData, never published) that sets ORION_BIS_DATA = { code = "..." }.
-- This file is the data layer; UI/*.lua draw it and listen through ns.On("LISTS_CHANGED", fn).

local ADDON, ns = ...
local L = ns.L

OrionBiSDB = OrionBiSDB or {}

ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local PREFIX = "OrionBiS"
ns.PRIORITIES = { "b", "u", "m" }
ns.PRIORITY_ORDER = { b = 1, u = 2, m = 3 }
local PRIORITY_ORDER = ns.PRIORITY_ORDER
local DEFAULTS = { alerts = true, sound = true, rollFlash = true, soundChoice = "achievement", alertStyle = "orion", tooltip = true, minimap = true, scale = 1, lootFilter = "spec" }

function ns.PriorityLabel(p)
    if p == "b" then return L["BiS"] elseif p == "u" then return L["Upgrade"] else return L["Minor"] end
end

local function safe(value)
    if value ~= nil and type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end
ns.safe = safe

local function key(name, realm)
    return string.lower(tostring(name or "")) .. "-" .. string.lower(tostring(realm or "")):gsub("[^%w]", "")
end
ns.key = key

local function myRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
end

local function playerKey() return key(UnitName("player"), myRealm()) end
ns.playerKey = playerKey

local function now() return (GetServerTime and GetServerTime()) or time() end

function ns.ClassColored(name, classId)
    local _, classFile = GetClassInfo(tonumber(classId) or 0)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
    return name
end

function ns.Print(text) print("|cffffc840Orion BiS:|r " .. text) end

function ns.Setting(name)
    local value = OrionBiSDB.settings and OrionBiSDB.settings[name]
    if value == nil then return DEFAULTS[name] end
    return value
end

function ns.SetSetting(name, value)
    OrionBiSDB.settings = OrionBiSDB.settings or {}
    OrionBiSDB.settings[name] = value
    ns.Fire("SETTINGS_CHANGED", name, value)
end

-- ---- Callbacks -----------------------------------------------------------------------------

local listeners = {}
function ns.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end
function ns.Fire(event, ...)
    for _, fn in ipairs(listeners[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- ---- Data ----------------------------------------------------------------------------------

-- One list: <Name>-<realm>=<classId>:<itemId><b|u|m>[!],...   ("!" = already received; empty items = cleared list)
-- A code:   ORIONBIS1;<unix time>;<raid name>;<list>;<list>;...
-- Names never contain "-", realms never contain ";", "=", "," or tabs. Any website can produce the same code.
local function parseEntry(entry, at)
    local who, classId, items = entry:match("^([^=]+)=(%d*):(.*)$")
    if not who then return nil end
    local name, realm = who:match("^([^-]+)-(.+)$")
    if not name then return nil end
    local list = { name = name, realm = realm, classId = tonumber(classId), at = at, items = {} }
    for itemId, priority, got in items:gmatch("(%d+)([bum])(!?)") do
        list.items[tonumber(itemId)] = { p = priority, got = got == "!" or nil }
    end
    return list
end

local function encodeEntry(list)
    local ids = {}
    for itemId in pairs(list.items) do ids[#ids + 1] = itemId end
    table.sort(ids)
    local parts = {}
    for _, itemId in ipairs(ids) do
        local want = list.items[itemId]
        parts[#parts + 1] = itemId .. want.p .. (want.got and "!" or "")
    end
    return list.name .. "-" .. list.realm .. "=" .. (list.classId or "") .. ":" .. table.concat(parts, ",")
end

local function parseCode(code)
    if type(code) ~= "string" then return nil, L["No code"] end
    code = code:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
    local parts = {}
    for part in (code .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = part end
    if parts[1] ~= "ORIONBIS1" or #parts < 3 then return nil, L["That isn't an Orion BiS code"] end
    local at = tonumber(parts[2]) or now()
    local data = { at = at, raid = parts[3], lists = {} }
    for i = 4, #parts do
        local list = parseEntry(parts[i], at)
        if list then data.lists[key(list.name, list.realm)] = list end
    end
    return data
end
ns.parseCode = parseCode

local lists = {} -- = OrionBiSDB.lists, set on load
local byItem = {}

local function rebuild()
    byItem = {}
    for _, list in pairs(lists) do
        for itemId, want in pairs(list.items) do
            byItem[itemId] = byItem[itemId] or {}
            table.insert(byItem[itemId], { list = list, p = want.p, got = want.got })
        end
    end
    for _, wanters in pairs(byItem) do
        table.sort(wanters, function(a, b)
            if PRIORITY_ORDER[a.p] ~= PRIORITY_ORDER[b.p] then return PRIORITY_ORDER[a.p] < PRIORITY_ORDER[b.p] end
            return a.list.name < b.list.name
        end)
    end
end

local function listsChanged()
    rebuild()
    ns.Fire("LISTS_CHANGED")
end

function ns.Lists() return lists end
function ns.ItemsWanted() return byItem end
function ns.ListCount()
    local count = 0
    for _ in pairs(lists) do count = count + 1 end
    return count
end

--- Store a list if it's newer than ours. Returns true when it changed something.
local function merge(k, list, src)
    local current = lists[k]
    if current and (current.at or 0) >= (list.at or 0) then return false end
    list.src = src or list.src
    lists[k] = list
    return true
end

local function setRaid(name, at)
    if name and name ~= "" and (not OrionBiSDB.raid or (OrionBiSDB.raid.at or 0) < at) then
        OrionBiSDB.raid = { name = name, at = at }
    end
end

function ns.RaidName() return OrionBiSDB.raid and OrionBiSDB.raid.name end
function ns.MyList() return lists[playerKey()] end

function ns.MyWant(itemId)
    local list = lists[playerKey()]
    return list and list.items[itemId]
end

--- Others (or everyone) who still want an item, best priority first: { { list=, p=, got= }, ... }
function ns.Wanters(itemId, skipMe)
    local result = {}
    local me = playerKey()
    for _, w in ipairs(byItem[itemId] or {}) do
        if not w.got and not (skipMe and key(w.list.name, w.list.realm) == me) then result[#result + 1] = w end
    end
    return result
end

--- "BiS: A, B · Upgrade: C" (received ones left out; skipMe leaves you out).
function ns.WantersText(itemId, skipMe)
    local wanters = ns.Wanters(itemId, skipMe)
    if #wanters == 0 then return nil end
    local groups, order = {}, {}
    for _, w in ipairs(wanters) do
        if not groups[w.p] then groups[w.p] = {}; order[#order + 1] = w.p end
        table.insert(groups[w.p], ns.ClassColored(w.list.name, w.list.classId))
    end
    local parts = {}
    for _, p in ipairs(order) do
        parts[#parts + 1] = ns.PriorityHex(p) .. ns.PriorityLabel(p) .. ":|r " .. table.concat(groups[p], ", ")
    end
    return table.concat(parts, "  ·  ")
end

function ns.PriorityHex(p)
    if p == "b" then return "|cffffc840" elseif p == "u" then return "|cff5aa8ff" else return "|cff8fd18f" end
end

-- ---- Guild sync ----------------------------------------------------------------------------
-- Payloads (split into 255-byte addon messages as "<id>:<part>:<parts>:<text>"):
--   S \t <raid at> \t <raid name> \t <Name-realm>=<at>,...   what I have (sent on login; answers fill the gaps)
--   L \t <at> \t <src> \t <list entry>                       one list
-- On an S, whoever holds a newer list sends it (after a random delay, skipped if someone else sent it first), and
-- whoever is behind answers with their own S. Everyone hears every message, so the guild converges.
-- Unchanged since 1.1, so older versions in the guild keep syncing.

local sync = { queue = {}, queued = {}, lines = {}, offers = {}, partial = {}, nextId = 0, wait = 0 }

local function syncOn() return not OrionBiSDB.noSync and IsInGuild and IsInGuild() end
ns.SyncOn = syncOn

local function queuePayload(id)
    if not syncOn() or sync.queued[id] then return end
    sync.queued[id] = true
    sync.queue[#sync.queue + 1] = id
end

local function shareList(k) queuePayload("L" .. k) end

local function buildPayload(id)
    if id == "S" then
        local entries = {}
        for _, list in pairs(lists) do entries[#entries + 1] = list.name .. "-" .. list.realm .. "=" .. (list.at or 0) end
        table.sort(entries)
        local raid = OrionBiSDB.raid or {}
        return "S\t" .. (raid.at or 0) .. "\t" .. (raid.name or "") .. "\t" .. table.concat(entries, ",")
    end
    local list = lists[id:sub(2)]
    if not list then return nil end
    return "L\t" .. (list.at or 0) .. "\t" .. (list.src or "game") .. "\t" .. encodeEntry(list)
end

local function sendLine(line)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return true end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, line, "GUILD")
    return ok and (result == nil or result == true or result == 0)
end

-- One message per tick keeps us under Blizzard's addon-message throttle. Failures (throttle, or the
-- instance/encounter lockdown) are retried a few seconds later.
local pump = CreateFrame("Frame")
pump.elapsed = 0
pump:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < 0.8 then return end
    self.elapsed = 0
    if sync.wait > 0 then sync.wait = sync.wait - 1; return end
    if #sync.lines == 0 then
        local id = table.remove(sync.queue, 1)
        if not id then return end
        sync.queued[id] = nil
        local payload = buildPayload(id)
        if not payload then return end
        sync.nextId = (sync.nextId % 999) + 1
        local size = 230
        local parts = math.max(1, math.ceil(#payload / size))
        for i = 1, parts do
            sync.lines[#sync.lines + 1] = sync.nextId .. ":" .. i .. ":" .. parts .. ":" .. payload:sub((i - 1) * size + 1, i * size)
        end
    end
    if not syncOn() then wipe(sync.lines); return end
    if sendLine(sync.lines[1]) then
        table.remove(sync.lines, 1)
    else
        sync.wait = 6
    end
end)

local function cancelOffer(k)
    if sync.offers[k] then sync.offers[k]:Cancel(); sync.offers[k] = nil end
end

local function offerList(k)
    if sync.offers[k] or sync.queued["L" .. k] then return end
    -- Your own list goes first; for others' lists a random wait spreads the answers out so one copy usually wins.
    local delay = k == playerKey() and 0.5 or (2 + math.random() * 10)
    sync.offers[k] = C_Timer.NewTimer(delay, function()
        sync.offers[k] = nil
        shareList(k)
    end)
end

local function onSummary(text)
    local raidAt, raidName, entries = text:match("^S\t(%d*)\t([^\t]*)\t?(.*)$")
    if not raidAt then return end
    local theirs = {}
    for who, at in entries:gmatch("([^,=]+)=(%d+)") do
        local name, realm = who:match("^([^-]+)-(.+)$")
        if name then theirs[key(name, realm)] = tonumber(at) end
    end
    for k, list in pairs(lists) do
        if (theirs[k] or -1) < (list.at or 0) then offerList(k) end
    end
    local behind = (tonumber(raidAt) or 0) > ((OrionBiSDB.raid and OrionBiSDB.raid.at) or 0)
    for k, at in pairs(theirs) do
        if not lists[k] or (lists[k].at or 0) < at then behind = true; break end
    end
    -- Ask for what we're missing by sending our own summary (once a minute at most, after a random delay;
    -- by then their lists may already have arrived through someone else's answer).
    if behind and not sync.summaryTimer and (now() - (sync.lastSummary or 0)) > 60 then
        sync.summaryTimer = C_Timer.NewTimer(2 + math.random() * 6, function()
            sync.summaryTimer = nil
            for k, at in pairs(theirs) do
                if not lists[k] or (lists[k].at or 0) < at then
                    sync.lastSummary = now()
                    queuePayload("S")
                    return
                end
            end
        end)
    end
    if behind and tonumber(raidAt) and raidName ~= "" then setRaid(raidName, tonumber(raidAt)) end
end

local function onList(text)
    local at, src, entry = text:match("^L\t(%d+)\t(%a*)\t(.+)$")
    local list = entry and parseEntry(entry, tonumber(at))
    if not list then return end
    local k = key(list.name, list.realm)
    if merge(k, list, src ~= "" and src or "game") then listsChanged() end
    if (lists[k].at or 0) <= list.at then
        -- Someone else already shared this version: don't send it again.
        cancelOffer(k)
        if sync.queued["L" .. k] then
            sync.queued["L" .. k] = nil
            for i, id in ipairs(sync.queue) do if id == "L" .. k then table.remove(sync.queue, i); break end end
        end
    end
end

local function onAddonMessage(text, sender)
    text, sender = safe(text), safe(sender)
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    local id, part, parts, chunk = text:match("^(%d+):(%d+):(%d+):(.*)$")
    if not id then return end
    part, parts = tonumber(part), tonumber(parts)
    local buffers = sync.partial[sender] or {}
    sync.partial[sender] = buffers
    local buffer = buffers[id]
    if part == 1 or not buffer or buffer.next ~= part then
        if part ~= 1 then buffers[id] = nil; return end
        buffer = { chunks = {}, next = 1 }
        buffers[id] = buffer
    end
    buffer.chunks[part] = chunk
    buffer.next = part + 1
    if part < parts then return end
    buffers[id] = nil
    local payload = table.concat(buffer.chunks)
    local kind = payload:sub(1, 1)
    if kind == "S" then onSummary(payload) elseif kind == "L" then onList(payload) end
end

function ns.SetSync(on)
    if on then
        OrionBiSDB.noSync = nil
        sync.lastSummary = now()
        queuePayload("S")
        if ns.MyList() then shareList(playerKey()) end
        ns.Print(L["Guild sync is on; asking your guild for lists."])
    else
        OrionBiSDB.noSync = true
        ns.Print(L["Guild sync is off. Your list stays on this PC."])
    end
    ns.Fire("SETTINGS_CHANGED", "sync", on)
end

-- ---- Your own list -------------------------------------------------------------------------

--- Add, change (priority) or remove (priority nil) an item on this character's list, and share it.
function ns.EditMine(itemId, priority, got)
    local k = playerKey()
    local list = lists[k]
    local copy = { name = UnitName("player"), realm = list and list.realm or myRealm(), classId = select(3, UnitClass("player")), items = {} }
    if list then for id, want in pairs(list.items) do copy.items[id] = { p = want.p, got = want.got } end end
    if priority then
        copy.items[itemId] = copy.items[itemId] or {}
        copy.items[itemId].p = priority
        if got ~= nil then copy.items[itemId].got = got or nil end
    else
        copy.items[itemId] = nil
    end
    copy.at = math.max(now(), ((list and list.at) or 0) + 1)
    copy.src = "game"
    lists[k] = copy
    shareList(k)
    listsChanged()
end

--- Remove every item from this character's list (shared as an empty list, so the guild clears it too).
function ns.ClearMine()
    local list = ns.MyList()
    if not list then return end
    local copy = { name = list.name, realm = list.realm, classId = list.classId, items = {}, src = "game" }
    copy.at = math.max(now(), (list.at or 0) + 1)
    lists[playerKey()] = copy
    shareList(playerKey())
    listsChanged()
end

function ns.ImportCode(code, src)
    local data, err = parseCode(code)
    if not data then return nil, err end
    local changed = 0
    for k, list in pairs(data.lists) do
        if merge(k, list, src) then
            changed = changed + 1
            shareList(k)
        end
    end
    setRaid(data.raid, data.at)
    if changed > 0 then listsChanged() end
    return changed
end

--- Your own list as a code you can paste elsewhere (another PC, a website, a friend).
function ns.ExportMine()
    local list = ns.MyList()
    if not list then return nil end
    return "ORIONBIS1;" .. (list.at or now()) .. ";;" .. encodeEntry(list)
end

-- ---- Events --------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        OrionBiSDB.lists = OrionBiSDB.lists or {}
        lists = OrionBiSDB.lists
        -- 1.0 kept the pasted code as text; move it into lists.
        if OrionBiSDB.code then ns.ImportCode(OrionBiSDB.code, "site"); OrionBiSDB.code = nil end
        -- Private guild data: the companion addon OrionBiS_GuildData (loaded first via OptionalDeps) holds everyone's
        -- lists from the guild website. It is installed by hand by the guild, never shipped with this addon.
        if type(ORION_BIS_DATA) == "table" and type(ORION_BIS_DATA.code) == "string" then
            local changed = ns.ImportCode(ORION_BIS_DATA.code, "site")
            if changed and changed > 0 then
                C_Timer.After(5, function() ns.Print(L["%d lists loaded from your guild data."]:format(changed)) end)
            end
        end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        rebuild()
        ns.Fire("LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if isLogin or isReload then
            -- Tell the guild what we have; anyone with newer lists answers.
            C_Timer.After(12, function() sync.lastSummary = now(); queuePayload("S") end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix ~= PREFIX or channel ~= "GUILD" then return end
        local me = UnitName("player") .. "-" .. myRealm()
        if sender == me or sender == UnitName("player") then return end
        onAddonMessage(text, sender)
    end
end)

-- ---- Slash command -------------------------------------------------------------------------

SLASH_ORIONBIS1 = "/bis"
SLASH_ORIONBIS2 = "/orionbis"
SlashCmdList.ORIONBIS = function(msg)
    msg = string.lower(msg or ""):match("^%s*(.-)%s*$")
    if msg == "import" then
        ns.Fire("OPEN", "mine", "import")
    elseif msg == "export" then
        ns.Fire("OPEN", "mine", "export")
    elseif msg == "loot" then
        ns.Fire("OPEN", "loot")
    elseif msg == "mine" or msg == "list" then
        ns.Fire("OPEN", "mine")
    elseif msg == "all" or msg == "everyone" or msg == "guild" then
        ns.Fire("OPEN", "guild")
    elseif msg == "settings" or msg == "options" or msg == "config" then
        ns.Fire("OPEN", "settings")
    elseif msg == "sync off" then
        ns.SetSync(false)
    elseif msg == "sync on" or msg == "sync" then
        ns.SetSync(true)
    elseif msg == "help" or msg == "?" then
        ns.Print("/bis  " .. L["open or close the window"])
        ns.Print("/bis loot  " .. L["browse loot by boss"])
        ns.Print("/bis mine  " .. L["your list"])
        ns.Print("/bis guild  " .. L["everyone's lists in your guild"])
        ns.Print("/bis import | export  " .. L["paste or copy a list code"])
        ns.Print("/bis sync off | on  " .. L["stop or resume sharing with your guild"])
        ns.Print("/bis settings  " .. L["settings"])
    else
        ns.Fire("TOGGLE")
    end
end

-- Addon compartment (the addons button by the minimap); named in the .toc.
function OrionBiS_OnAddonCompartmentClick() ns.Fire("TOGGLE") end
