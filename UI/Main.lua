-- The /bis window: Loot (every boss's drops, click to add), My list, Guild (everyone's lists) and Settings.

local _, ns = ...
local L, T, Loot = ns.L, ns.T, ns.Loot
local C = T.C

local HEADER, FOOTER, SIDEBAR = 52, 28, 236
local ITEM_ROW = 50

local win = T.Box(UIParent, C.bg, C.border, "OrionBiSWindow")
win:SetSize(900, 600)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetToplevel(true)
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, "OrionBiSWindow")

-- ---- Helpers -------------------------------------------------------------------------------

local function itemInfo(itemId)
    local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemId)
    if not name then
        C_Item.RequestLoadItemDataByID(itemId)
        icon = icon or select(5, C_Item.GetItemInfoInstant(itemId))
    end
    return name, link, quality, icon
end

local function pool(create)
    local items = {}
    return function(i)
        if not items[i] then items[i] = create(i) end
        return items[i]
    end, function(from)
        for i = from, #items do items[i]:Hide() end
    end
end

local function showItemTooltip(owner, itemId, link)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(itemId) end
    GameTooltip:Show()
end

local function linkToChat(link)
    if link and IsModifiedClick and IsModifiedClick("CHATLINK") then
        if ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return true
    end
end

--- BiS / Upgrade / Minor chips. onPick(p) fires on click; chips:Set(p) highlights one.
--- Anchored from the right edge of `right` when given, otherwise call chips.first:SetPoint(...) yourself.
local function priorityChips(parent, onPick, prefix, right)
    local chips = {}
    for _, p in ipairs(ns.PRIORITIES) do
        local b = T.Button(parent, (prefix or "") .. ns.PriorityLabel(p), 0, 24, function() onPick(p) end)
        b:SetWidth(math.max(64, b.label:GetStringWidth() + 20))
        chips[p] = b
    end
    chips.first = chips[ns.PRIORITIES[1]]
    chips.last = chips[ns.PRIORITIES[#ns.PRIORITIES]]
    if right then
        chips.last:SetPoint("RIGHT", right, "RIGHT", -8, 0)
        for i = #ns.PRIORITIES - 1, 1, -1 do
            chips[ns.PRIORITIES[i]]:SetPoint("RIGHT", chips[ns.PRIORITIES[i + 1]], "LEFT", -4, 0)
        end
    else
        for i = 2, #ns.PRIORITIES do
            chips[ns.PRIORITIES[i]]:SetPoint("LEFT", chips[ns.PRIORITIES[i - 1]], "RIGHT", 4, 0)
        end
    end
    function chips:Set(current)
        for _, p in ipairs(ns.PRIORITIES) do self[p]:SetActive(current == p, C[p]) end
    end
    return chips
end

-- ---- Header / footer -----------------------------------------------------------------------

local header = CreateFrame("Frame", nil, win)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
header:SetHeight(HEADER)
T.Fill(header, C.panel)
local headerRule = T.Rule(header)
headerRule:SetPoint("BOTTOMLEFT")
headerRule:SetPoint("BOTTOMRIGHT")

local title = T.Text(header, 16, C.text, true)
title:SetPoint("LEFT", 18, 1)
title:SetText("Orion BiS")
local version = T.Text(header, 10, C.muted)
version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
version:SetText("v" .. ns.VERSION)

local closeButton = T.IconButton(header, T.ICON.close, 28, function() win:Hide() end, { CLOSE or "Close" })
closeButton:SetPoint("RIGHT", -10, 0)

local footer = CreateFrame("Frame", nil, win)
footer:SetPoint("BOTTOMLEFT")
footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER)
T.Fill(footer, C.panel)
local footerRule = T.Rule(footer)
footerRule:SetPoint("TOPLEFT")
footerRule:SetPoint("TOPRIGHT")
local status = T.Text(footer, 11, C.muted)
status:SetPoint("LEFT", 14, 0)
status:SetPoint("RIGHT", -14, 0)

local function refreshStatus()
    local parts = {}
    local raid = ns.RaidName()
    if raid and raid ~= "" then parts[#parts + 1] = raid end
    local count = ns.ListCount()
    parts[#parts + 1] = (count == 1 and L["%d list"] or L["%d lists"]):format(count)
    if OrionBiSDB.noSync then
        parts[#parts + 1] = L["guild sync off"]
    elseif IsInGuild() then
        parts[#parts + 1] = L["shared with your guild"]
    else
        parts[#parts + 1] = L["not in a guild"]
    end
    if type(ORION_BIS_DATA) == "table" then parts[#parts + 1] = L["guild data loaded"] end
    status:SetText(table.concat(parts, "   ·   "))
end

local body = CreateFrame("Frame", nil, win)
body:SetPoint("TOPLEFT", 0, -HEADER)
body:SetPoint("BOTTOMRIGHT", 0, FOOTER)

-- ---- Tabs ----------------------------------------------------------------------------------

local pages, tabs, currentPage = {}, {}, nil
local TAB_ORDER = { "loot", "mine", "guild", "settings" }
local TAB_LABEL = { loot = L["Loot"], mine = L["My list"], guild = L["Guild"], settings = L["Settings"] }

local function showPage(id)
    currentPage = id
    OrionBiSDB.page = id
    for key, page in pairs(pages) do page:SetShown(key == id) end
    for key, tab in pairs(tabs) do tab:SetActive(key == id) end
    if pages[id] and pages[id].Refresh then pages[id]:Refresh() end
end

local prevTab
for _, id in ipairs(TAB_ORDER) do
    local tab = T.Button(header, TAB_LABEL[id], 0, 30, function() showPage(id) end, "ghost")
    tab:SetWidth(math.max(72, tab.label:GetStringWidth() + 28))
    if prevTab then tab:SetPoint("LEFT", prevTab, "RIGHT", 4, 0) else tab:SetPoint("LEFT", version, "RIGHT", 28, -1) end
    tabs[id] = tab
    prevTab = tab
end

local function newPage(id)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    page:Hide()
    pages[id] = page
    return page
end

-- ============================================================================================
-- Loot
-- ============================================================================================

local loot = newPage("loot")
local browse -- = OrionBiSDB.browse: { mode=, tier=, instance=, encounter=, difficulty = { [mode] = id } }

-- Raids, dungeons, or this season's Mythic+ dungeons (the journal's current tier at Mythic+ item levels).
local MODES = { "raid", "dungeon", "mplus" }
local MODE_LABEL = { raid = L["Raids"], dungeon = L["Dungeons"], mplus = L["Mythic+"] }
local DIFFICULTIES = { raid = { 17, 14, 15, 16 }, dungeon = { 1, 2, 23 }, mplus = { 8, 23 } }
local DEFAULT_DIFFICULTY = { raid = 16, dungeon = 23, mplus = 8 }
local DIFFICULTY_FALLBACK = { [1] = "Normal", [2] = "Heroic", [14] = "Normal", [15] = "Heroic", [16] = "Mythic", [23] = "Mythic" }

local function difficultyLabel(id)
    if id == 17 then return "LFR" end
    if id == 8 then return L["Mythic+"] end
    return (GetDifficultyInfo and GetDifficultyInfo(id)) or DIFFICULTY_FALLBACK[id] or tostring(id)
end

local sidebar = T.Box(loot, C.panel, false)
sidebar:SetPoint("TOPLEFT")
sidebar:SetPoint("BOTTOMLEFT")
sidebar:SetWidth(SIDEBAR)
local sideRule = sidebar:CreateTexture(nil, "ARTWORK")
sideRule:SetColorTexture(unpack(C.border))
sideRule:SetPoint("TOPRIGHT")
sideRule:SetPoint("BOTTOMRIGHT")
sideRule:SetWidth(1)

local tierDrop = T.Dropdown(sidebar, SIDEBAR - 28, function()
    local choices = {}
    local tiers = Loot.Tiers()
    for i = #tiers, 1, -1 do choices[#choices + 1] = { value = tiers[i].id, text = tiers[i].name } end
    return choices
end, function(tier)
    browse.tier, browse.instance, browse.encounter = tier, nil, nil
    if browse.mode == "mplus" then browse.mode = "dungeon" end
    loot:Refresh()
end)
tierDrop:SetPoint("TOPLEFT", 14, -14)

local modeButtons = {}
for i, mode in ipairs(MODES) do
    local b = T.Button(sidebar, MODE_LABEL[mode], (SIDEBAR - 28 - 8) / 3, 26, function()
        if mode == "mplus" then browse.tier = nil end
        browse.mode, browse.instance, browse.encounter = mode, nil, nil
        loot:Refresh()
    end)
    T.SetFont(b.label, 11, true)
    b.label:SetPoint("LEFT", 2, 0)
    b.label:SetPoint("RIGHT", -2, 0)
    if i == 1 then b:SetPoint("TOPLEFT", tierDrop, "BOTTOMLEFT", 0, -8)
    else b:SetPoint("LEFT", modeButtons[MODES[i - 1]], "RIGHT", 4, 0) end
    modeButtons[mode] = b
end

local instanceList = {}
local instanceDrop = T.Dropdown(sidebar, SIDEBAR - 28, function()
    local choices = {}
    for _, inst in ipairs(instanceList) do choices[#choices + 1] = { value = inst.id, text = inst.name } end
    return choices
end, function(id)
    browse.instance, browse.encounter = id, nil
    loot:Refresh()
end)
instanceDrop:SetPoint("TOPLEFT", modeButtons.raid, "BOTTOMLEFT", 0, -8)

-- Difficulty chips (only the ones this instance has).
local DIFF_WIDTH = (SIDEBAR - 28 - 12) / 4
local diffButton, hideDiffButtons = pool(function()
    local b = T.Button(sidebar, "", DIFF_WIDTH, 24)
    T.SetFont(b.label, 11, true)
    b.label:SetPoint("LEFT", 2, 0)
    b.label:SetPoint("RIGHT", -2, 0)
    return b
end)

local bossLabel = T.Text(sidebar, 10, C.muted, true)
bossLabel:SetPoint("TOPLEFT", instanceDrop, "BOTTOMLEFT", 2, -48)
bossLabel:SetText(string.upper(L["Bosses"]))

local bossScroll = T.Scroll(sidebar)
bossScroll:SetPoint("TOPLEFT", bossLabel, "BOTTOMLEFT", -2, -6)
bossScroll:SetPoint("BOTTOMRIGHT", -8, 10)

local bossButton, hideBossButtons = pool(function()
    local b = T.Button(bossScroll.content, "", SIDEBAR - 34, 30, nil, "nav")
    b.label:SetJustifyH("LEFT")
    b.label:SetPoint("LEFT", 12, 0)
    return b
end)

-- Right side: boss header, spec filter, items.
local main = CreateFrame("Frame", nil, loot)
main:SetPoint("TOPLEFT", SIDEBAR, 0)
main:SetPoint("BOTTOMRIGHT")

local bossTitle = T.Text(main, 18, C.text, true)
bossTitle:SetPoint("TOPLEFT", 20, -16)
bossTitle:SetPoint("RIGHT", main, "RIGHT", -280, 0)
local bossSub = T.Text(main, 11, C.muted)
bossSub:SetPoint("TOPLEFT", bossTitle, "BOTTOMLEFT", 0, -4)
bossSub:SetPoint("RIGHT", main, "RIGHT", -280, 0)

local filterButtons = {}
local FILTERS = { { "spec", L["My spec"] }, { "class", L["My class"] }, { "all", L["All"] } }
local prevFilter
for i = #FILTERS, 1, -1 do
    local id, label = FILTERS[i][1], FILTERS[i][2]
    local b = T.Button(main, label, 0, 26, function()
        ns.SetSetting("lootFilter", id)
        loot:Refresh()
    end)
    b:SetWidth(math.max(64, b.label:GetStringWidth() + 22))
    if prevFilter then b:SetPoint("RIGHT", prevFilter, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -20, -18) end
    filterButtons[id] = b
    prevFilter = b
end

local lootNotice = T.Text(main, 12, C.muted, false, "CENTER")
lootNotice:SetPoint("TOPLEFT", 20, -100)
lootNotice:SetPoint("TOPRIGHT", -20, -100)
lootNotice:SetWordWrap(true)

local itemScroll = T.Scroll(main)
itemScroll:SetPoint("TOPLEFT", 20, -68)
itemScroll:SetPoint("BOTTOMRIGHT", -12, 12)

local function itemRow(parent, withChips)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ITEM_ROW - 4)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = T.Fill(row, C.row)
    row.icon = T.ItemIcon(row, 36)
    row.icon:SetPoint("LEFT", 6, 0)
    row.name = T.Text(row, 13, C.text, true)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.sub = T.Text(row, 11, C.muted)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(unpack(C.rowHover))
        showItemTooltip(self, self.itemId, self.link)
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(unpack(C.row))
        GameTooltip:Hide()
    end)
    return row
end

local lootRow, hideLootRows = pool(function()
    local row = itemRow(itemScroll.content)
    -- On your list: a stripe in the priority's colour and a faint tint.
    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT"); row.stripe:SetPoint("BOTTOMLEFT"); row.stripe:SetWidth(3)
    row.icon:SetPoint("LEFT", 10, 0)
    local options = {}
    for _, p in ipairs(ns.PRIORITIES) do options[#options + 1] = { value = p, text = ns.PriorityLabel(p), color = C[p] } end
    row.seg = T.Segmented(row, options, 26, function(p)
        local want = ns.MyWant(row.itemId)
        if want and want.p == p then
            ns.EditMine(row.itemId, nil)
        else
            Loot.Remember(row.itemId, row.boss, row.instance)
            ns.EditMine(row.itemId, p)
        end
    end)
    row.seg:SetPoint("RIGHT", -10, 0)
    -- Keep the row lit while the mouse is on its buttons.
    row.seg.onEnter = function() row:GetScript("OnEnter")(row) end
    row.seg.onLeave = function() row:GetScript("OnLeave")(row) end
    row.level = T.Text(row, 12, C.muted, true, "RIGHT")
    row.level:SetPoint("RIGHT", row.seg, "LEFT", -12, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -10, 0)
    row.sub:SetPoint("RIGHT", row.level, "LEFT", -10, 0)
    function row:Paint()
        local want = self.want
        local hover = self:IsMouseOver()
        if want then
            local c = C[want.p]
            self.bg:SetColorTexture(c[1] * 0.18 + 0.09, c[2] * 0.18 + 0.09, c[3] * 0.18 + 0.11, 1)
            self.stripe:SetColorTexture(c[1], c[2], c[3], 1)
        else
            self.bg:SetColorTexture(unpack(hover and C.rowHover or C.row))
        end
        self.stripe:SetShown(want and true or false)
        if hover and want then self.bg:SetAlpha(0.85) else self.bg:SetAlpha(1) end
    end
    row:SetScript("OnEnter", function(self)
        self:Paint()
        showItemTooltip(self, self.itemId, self.link)
    end)
    row:SetScript("OnLeave", function(self)
        self:Paint()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self) linkToChat(self.link) end)
    return row
end)

--- Gear first (in the journal's order), then tokens, mounts, decor and the rest.
local function sortForShow(items)
    local sorted = {}
    for i, item in ipairs(items) do sorted[i] = item; item.order = i end
    table.sort(sorted, function(a, b)
        local ga = (a.slot and a.slot ~= "") and 0 or 1
        local gb = (b.slot and b.slot ~= "") and 0 or 1
        if ga ~= gb then return ga < gb end
        return a.order < b.order
    end)
    return sorted
end

local function itemLevel(link)
    if not link or not (C_Item and C_Item.GetDetailedItemLevelInfo) then return end
    local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and type(level) == "number" and level > 1 then return level end
end

local function defaultInstance(list, isRaid)
    -- Where you are now, if it's in this list; otherwise the newest raid (journal lists raids oldest first).
    local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local here = mapId and EJ_GetInstanceForMap and EJ_GetInstanceForMap(mapId)
    for _, inst in ipairs(list) do if inst.id == here then return inst end end
    return isRaid and list[#list] or list[1]
end

local lootPending = false
local itemsShown = {}

local function renderLootRows()
    local encounterName, instanceName = bossTitle:GetText(), bossSub.instanceName
    local y = 0
    for i, item in ipairs(itemsShown) do
        local row = lootRow(i)
        row.itemId, row.link, row.boss, row.instance = item.itemId, item.link, encounterName, instanceName
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", itemScroll.content, "RIGHT", 0, 0)
        row.icon:SetItem(item.icon, item.quality)
        row.name:SetText(item.link or item.name or (L["Loading..."]))
        local info = {}
        if item.slot and item.slot ~= "" then info[#info + 1] = item.slot end
        if item.armorType and item.armorType ~= "" then info[#info + 1] = item.armorType end
        local wanted = ns.WantersText(item.itemId, true)
        local subText = table.concat(info, "  ·  ")
        if wanted then subText = (subText ~= "" and (subText .. "     ") or "") .. wanted end
        row.sub:SetText(subText)
        local level = item.slot and item.slot ~= "" and itemLevel(item.link)
        row.level:SetText(level and ("|cff8f90a1" .. (ITEM_LEVEL_ABBR or "iLvl") .. "|r  " .. level) or "")
        local want = ns.MyWant(item.itemId)
        row.want = want
        row.seg:Set(want and want.p)
        row:Paint()
        row:Show()
        y = y + ITEM_ROW
    end
    hideLootRows(#itemsShown + 1)
    itemScroll:SetContentHeight(y)
end

function loot:Refresh()
    if not self:IsShown() then return end
    browse = OrionBiSDB.browse or {}
    OrionBiSDB.browse = browse
    if not browse.mode then browse.mode = browse.isRaid == false and "dungeon" or "raid" end -- 2.0.0 kept isRaid
    browse.isRaid = nil
    browse.difficulty = browse.difficulty or {}
    local mode = browse.mode
    local isRaid = mode == "raid"
    local filter = ns.Setting("lootFilter")
    for id, b in pairs(filterButtons) do b:SetActive(id == filter) end
    for id, b in pairs(modeButtons) do b:SetActive(id == mode) end

    lootNotice:SetText("")
    if not Loot.Available() then
        lootNotice:SetText(L["The Adventure Guide isn't available on this game version."])
        return
    end
    if Loot.JournalBusy() then
        itemsShown = {}
        renderLootRows()
        lootNotice:SetText(L["Close the Adventure Guide to browse loot here."])
        return
    end

    -- Tier
    local tiers = Loot.Tiers()
    local tierName
    if mode == "mplus" then browse.tier = Loot.CurrentTier() end
    for _, t in ipairs(tiers) do if t.id == browse.tier then tierName = t.name end end
    if not tierName then
        browse.tier = Loot.CurrentTier()
        for _, t in ipairs(tiers) do if t.id == browse.tier then tierName = t.name end end
    end
    tierDrop:SetValue(browse.tier, tierName)

    -- Instance
    instanceList = Loot.Instances(browse.tier, isRaid)
    local instance
    for _, inst in ipairs(instanceList) do if inst.id == browse.instance then instance = inst end end
    instance = instance or defaultInstance(instanceList, isRaid)
    if not instance then
        instanceDrop:SetValue(nil, L["None"])
        hideBossButtons(1)
        hideDiffButtons(1)
        itemsShown = {}
        renderLootRows()
        bossTitle:SetText("")
        bossSub:SetText("")
        lootNotice:SetText(L["Nothing here in this expansion."])
        return
    end
    browse.instance = instance.id
    instanceDrop:SetValue(instance.id, instance.name)

    -- Difficulty
    local valid = Loot.ValidDifficulties(instance.id, DIFFICULTIES[mode])
    local difficulty = browse.difficulty[mode] or DEFAULT_DIFFICULTY[mode]
    local found = false
    for _, id in ipairs(valid) do if id == difficulty then found = true end end
    if not found then difficulty = valid[#valid] end
    browse.difficulty[mode] = browse.difficulty[mode] or difficulty
    for i, id in ipairs(valid) do
        local b = diffButton(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", instanceDrop, "BOTTOMLEFT", (i - 1) * (DIFF_WIDTH + 4), -8)
        b:SetText(difficultyLabel(id))
        b:SetActive(id == difficulty)
        b:SetScript("OnClick", function()
            browse.difficulty[mode] = id
            loot:Refresh()
        end)
        b:Show()
    end
    hideDiffButtons(#valid + 1)

    -- Bosses
    local encounters = Loot.Encounters(instance.id)
    local encounter
    for _, enc in ipairs(encounters) do if enc.id == browse.encounter then encounter = enc end end
    encounter = encounter or encounters[1]
    for i, enc in ipairs(encounters) do
        local b = bossButton(i)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
        b:SetText(enc.name)
        b:SetActive(encounter and enc.id == encounter.id)
        b:SetScript("OnClick", function()
            browse.encounter = enc.id
            loot:Refresh()
            itemScroll:ScrollTo(0)
        end)
        b:Show()
    end
    hideBossButtons(#encounters + 1)
    bossScroll:SetContentHeight(#encounters * 32)
    if not encounter then
        itemsShown = {}
        renderLootRows()
        return
    end
    browse.encounter = encounter.id
    bossTitle:SetText(encounter.name)
    bossSub.instanceName = instance.name
    bossSub:SetText(instance.name .. (difficulty and ("  ·  " .. difficultyLabel(difficulty)) or ""))

    -- Items
    local items, pending = Loot.Items(instance.id, encounter.id, difficulty, filter)
    for _, item in ipairs(items) do
        if not Loot.Source(item.itemId) then Loot.Remember(item.itemId, encounter.name, instance.name) end
    end
    itemsShown = sortForShow(items)
    lootPending = pending
    renderLootRows()
    if #items == 0 then
        lootNotice:SetText(filter == "all" and L["No loot listed for this boss."]
            or L["Nothing for your spec here. Try All to see every item."])
    end
end


-- ============================================================================================
-- My list
-- ============================================================================================

local mine = newPage("mine")

local addBox = T.EditBox(mine, 280, L["Shift-click an item, or type an item ID"])
addBox:SetPoint("TOPLEFT", 20, -18)
local function insertLink(link)
    if addBox:HasFocus() and type(link) == "string" then addBox:SetText(link) end
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end

local function addFromBox(priority)
    local text = addBox:GetText() or ""
    local itemId = tonumber(text:match("item[:=](%d+)") or text:match("^%s*(%d+)%s*$"))
    if not itemId then ns.Print(L["Shift-click an item into the box first (or type its item ID)."]); return end
    ns.EditMine(itemId, priority)
    addBox:SetText("")
    addBox:ClearFocus()
end
addBox:SetScript("OnEnterPressed", function() addFromBox("b") end)
local addChips = priorityChips(mine, addFromBox, "+ ")
addChips.first:SetPoint("LEFT", addBox, "RIGHT", 8, 0)

local dialog -- import / export, defined below
local exportButton = T.Button(mine, L["Export"], 84, 26, function() dialog:Open("export") end, nil,
    { L["Export"], L["Copy your list as a code for another PC or a website."] })
exportButton:SetPoint("TOPRIGHT", -20, -18)
local importButton = T.Button(mine, L["Import"], 84, 26, function() dialog:Open("import") end, nil,
    { L["Import"], L["Paste a code from your guild's website."] })
importButton:SetPoint("RIGHT", exportButton, "LEFT", -6, 0)

local mineNote = T.Text(mine, 11, C.muted)
mineNote:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, -12)
mineNote:SetPoint("RIGHT", mine, "RIGHT", -20, 0)

local mineScroll = T.Scroll(mine)
mineScroll:SetPoint("TOPLEFT", 20, -82)
mineScroll:SetPoint("BOTTOMRIGHT", -12, 12)

local emptyText = T.Text(mineScroll.content, 13, C.muted, false, "CENTER")
emptyText:SetPoint("TOP", 0, -70)
emptyText:SetWordWrap(true)
emptyText:SetWidth(460)
local browseButton = T.Button(mineScroll.content, L["Browse loot"], 150, 30, function() showPage("loot") end, "accent")
browseButton:SetPoint("TOP", emptyText, "BOTTOM", 0, -16)

local sectionHeader, hideSectionHeaders = pool(function()
    local fs = T.Text(mineScroll.content, 10, C.muted, true)
    return fs
end)

local mineRow, hideMineRows = pool(function()
    local row = itemRow(mineScroll.content)
    row.del = T.IconButton(row, T.ICON.close, 26, function(self) ns.EditMine(self:GetParent().itemId, nil) end,
        { L["Remove"] })
    row.del:SetPoint("RIGHT", -8, 0)
    row.got = T.IconButton(row, T.ICON.check, 26, function(self)
        local want = ns.MyWant(self:GetParent().itemId)
        if want then ns.EditMine(self:GetParent().itemId, want.p, not want.got) end
    end, { L["Received"], L["Mark as received (or not)."] })
    row.got:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
    row.prio = T.Button(row, "", 80, 24, function(self)
        local want = ns.MyWant(self:GetParent().itemId)
        if not want then return end
        local nextP = ns.PRIORITIES[(ns.PRIORITY_ORDER[want.p] % #ns.PRIORITIES) + 1]
        ns.EditMine(self:GetParent().itemId, nextP)
    end, nil, { L["Priority"], L["Click to change."] })
    row.prio:SetPoint("RIGHT", row.got, "LEFT", -8, 0)
    row.name:SetPoint("RIGHT", row.prio, "LEFT", -10, 0)
    row.sub:SetPoint("RIGHT", row.prio, "LEFT", -10, 0)
    row:SetScript("OnClick", function(self, button)
        if linkToChat(self.link) then return end
        local want = ns.MyWant(self.itemId)
        if button == "RightButton" and want then ns.EditMine(self.itemId, want.p, not want.got) end
    end)
    return row
end)

local indexed = false
function mine:Refresh()
    if not self:IsShown() then return end
    if not indexed and Loot.Available() and not Loot.JournalBusy() then
        indexed = true
        pcall(Loot.IndexTier, Loot.CurrentTier())
    end
    local list = ns.MyList()
    local groups = { b = {}, u = {}, m = {} }
    local total = 0
    if list then
        for itemId, want in pairs(list.items) do
            table.insert(groups[want.p], itemId)
            total = total + 1
        end
    end
    if list and list.src == "site" then
        mineNote:SetText(L["From your guild's website. Edit it there: changes here last until the website's lists next change."])
    else
        mineNote:SetText(L["Click the priority to change it. Right-click an item to mark it received. Shift-click links it in chat."])
    end

    local y, rowIndex, headerIndex = 0, 0, 0
    for _, p in ipairs(ns.PRIORITIES) do
        local ids = groups[p]
        if #ids > 0 then
            table.sort(ids, function(a, b)
                local ga, gb = list.items[a].got and 1 or 0, list.items[b].got and 1 or 0
                if ga ~= gb then return ga < gb end
                return a < b
            end)
            headerIndex = headerIndex + 1
            local h = sectionHeader(headerIndex)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 2, -y - 6)
            h:SetText(ns.PriorityHex(p) .. string.upper(ns.PriorityLabel(p)) .. "|r   " .. #ids)
            h:Show()
            y = y + 26
            for _, itemId in ipairs(ids) do
                rowIndex = rowIndex + 1
                local want = list.items[itemId]
                local name, link, quality, icon = itemInfo(itemId)
                local row = mineRow(rowIndex)
                row.itemId, row.link = itemId, link
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("RIGHT", mineScroll.content, "RIGHT", 0, 0)
                row.icon:SetItem(icon, quality)
                row.icon:SetAlpha(want.got and 0.45 or 1)
                row.name:SetText((link or name or ("item " .. itemId)) .. (want.got and ("   |cff8f909f" .. L["received"] .. "|r") or ""))
                local others = ns.WantersText(itemId, true)
                row.sub:SetText(Loot.SourceText(itemId) .. (others and ("     " .. L["also"] .. " " .. others) or ""))
                row.prio:SetText(ns.PriorityLabel(want.p))
                row.prio:SetActive(true, C[want.p])
                row.got.on = want.got
                row.got.hoverColor = C.m
                row.got.color = want.got and C.m or C.muted
                row.got:Paint()
                row:Show()
                y = y + ITEM_ROW
            end
        end
    end
    hideMineRows(rowIndex + 1)
    hideSectionHeaders(headerIndex + 1)
    emptyText:SetShown(total == 0)
    browseButton:SetShown(total == 0)
    if total == 0 then
        emptyText:SetText(L["Nothing on %s's list yet."]:format(UnitName("player") or "") .. "\n\n"
            .. L["Pick items boss by boss in Loot, shift-click items into the box above, or import a code from your guild's website."])
        y = 260
    end
    mineScroll:SetContentHeight(y)
end


-- Import / export dialog
dialog = T.Box(win, C.panel, C.accent)
dialog:SetSize(520, 170)
dialog:SetPoint("CENTER")
dialog:SetFrameLevel(win:GetFrameLevel() + 40)
dialog:EnableMouse(true)
dialog:Hide()
dialog.title = T.Text(dialog, 14, C.text, true)
dialog.title:SetPoint("TOPLEFT", 18, -16)
dialog.hint = T.Text(dialog, 11, C.muted)
dialog.hint:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -6)
dialog.hint:SetPoint("RIGHT", -18, 0)
dialog.box = T.EditBox(dialog, 484, "")
dialog.box:SetPoint("TOPLEFT", 18, -66)
dialog.box:SetMaxLetters(0)
dialog.msg = T.Text(dialog, 11, C.danger)
dialog.msg:SetPoint("TOPLEFT", dialog.box, "BOTTOMLEFT", 0, -8)
dialog.close = T.IconButton(dialog, T.ICON.close, 24, function() dialog:Hide() end)
dialog.close:SetPoint("TOPRIGHT", -6, -6)
dialog.ok = T.Button(dialog, L["Import"], 110, 28, function() dialog:Confirm() end, "accent")
dialog.ok:SetPoint("BOTTOMRIGHT", -18, 16)
dialog.cancel = T.Button(dialog, CANCEL or "Cancel", 90, 28, function() dialog:Hide() end)
dialog.cancel:SetPoint("RIGHT", dialog.ok, "LEFT", -6, 0)
dialog.box:SetScript("OnEscapePressed", function() dialog:Hide() end)
dialog.box:SetScript("OnEnterPressed", function() dialog:Confirm() end)

function dialog:Open(kind)
    self.kind = kind
    self.msg:SetText("")
    if kind == "export" then
        local code = ns.ExportMine()
        if not code then ns.Print(L["Add an item to your list first."]); return end
        self.title:SetText(L["Export your list"])
        self.hint:SetText(L["Press Ctrl+C to copy, then paste it anywhere that reads Orion BiS codes."])
        self.ok:SetText(L["Done"])
        self.cancel:Hide()
        self.code = code
        self.box:SetText(code)
        self.box:SetScript("OnTextChanged", function(box, user) if user then box:SetText(self.code); box:HighlightText() end end)
        self:Show()
        self.box:SetFocus()
        self.box:HighlightText()
    else
        self.title:SetText(L["Import a list"])
        self.hint:SetText(L["Paste a code from your guild's website (Ctrl+V)."])
        self.ok:SetText(L["Import"])
        self.cancel:Show()
        self.box:SetScript("OnTextChanged", nil)
        self.box:SetText("")
        self:Show()
        self.box:SetFocus()
    end
end

function dialog:Confirm()
    if self.kind == "export" then self:Hide(); return end
    local changed, err = ns.ImportCode(self.box:GetText(), "site")
    if not changed then self.msg:SetText(err); return end
    self:Hide()
    ns.Print(changed == 0 and L["Nothing new in that code."] or ((changed == 1 and L["%d list imported."] or L["%d lists imported."]):format(changed)))
end
dialog:SetScript("OnHide", function(self) self.box:ClearFocus() end)

-- ============================================================================================
-- Guild
-- ============================================================================================

local guild = newPage("guild")

local search = T.EditBox(guild, 280, L["Search items or players"])
search:SetPoint("TOPLEFT", 20, -18)
search:HookScript("OnTextChanged", function() guild:Refresh() end)
local onlyOpen = false
local openButton = T.Button(guild, L["Hide received"], 0, 26, function()
    onlyOpen = not onlyOpen
    guild:Refresh()
end)
openButton:SetWidth(openButton.label:GetStringWidth() + 26)
openButton:SetPoint("LEFT", search, "RIGHT", 8, 0)
local guildCount = T.Text(guild, 11, C.muted, false, "RIGHT")
guildCount:SetPoint("TOPRIGHT", -20, -24)

local guildScroll = T.Scroll(guild)
guildScroll:SetPoint("TOPLEFT", 20, -60)
guildScroll:SetPoint("BOTTOMRIGHT", -12, 12)
local guildEmpty = T.Text(guildScroll.content, 13, C.muted, false, "CENTER")
guildEmpty:SetPoint("TOP", 0, -70)
guildEmpty:SetWidth(460)
guildEmpty:SetWordWrap(true)

local guildRow, hideGuildRows = pool(function()
    local row = itemRow(guildScroll.content)
    row.name:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.source = T.Text(row, 11, C.muted, false, "RIGHT")
    row.source:SetPoint("TOPRIGHT", -12, -8)
    row.source:SetWidth(260)
    row.name:SetPoint("RIGHT", row.source, "LEFT", -10, 0)
    row:SetScript("OnClick", function(self) linkToChat(self.link) end)
    return row
end)

local function plain(text) return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower() end

function guild:Refresh()
    if not self:IsShown() then return end
    openButton:SetActive(onlyOpen)
    local query = plain(search:GetText()):match("^%s*(.-)%s*$")
    local entries = {}
    for itemId, wanters in pairs(ns.ItemsWanted()) do
        local text = onlyOpen and ns.WantersText(itemId, false)
        if not onlyOpen then
            -- Everyone, received ones included (struck through in grey).
            local parts, groups, order = {}, {}, {}
            for _, w in ipairs(wanters) do
                if not groups[w.p] then groups[w.p] = {}; order[#order + 1] = w.p end
                local name = w.got and ("|cff6f7080" .. w.list.name .. " ✓|r") or ns.ClassColored(w.list.name, w.list.classId)
                table.insert(groups[w.p], name)
            end
            for _, p in ipairs(order) do parts[#parts + 1] = ns.PriorityHex(p) .. ns.PriorityLabel(p) .. ":|r " .. table.concat(groups[p], ", ") end
            text = table.concat(parts, "  ·  ")
        end
        if text and text ~= "" then
            local name, link, quality, icon = itemInfo(itemId)
            local source = Loot.Source(itemId)
            local hay = plain((name or "") .. " " .. text .. " " .. (source and (source.boss .. " " .. source.instance) or ""))
            if query == "" or hay:find(query, 1, true) then
                entries[#entries + 1] = {
                    itemId = itemId, name = name, link = link, quality = quality, icon = icon, text = text,
                    sort = (source and (source.instance .. "\1" .. source.boss) or "\255") .. "\1" .. (name or tostring(itemId)),
                    source = source and (source.boss .. "  ·  " .. source.instance) or "",
                }
            end
        end
    end
    table.sort(entries, function(a, b) return a.sort < b.sort end)
    for i, e in ipairs(entries) do
        local row = guildRow(i)
        row.itemId, row.link = e.itemId, e.link
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW)
        row:SetPoint("RIGHT", guildScroll.content, "RIGHT", 0, 0)
        row.icon:SetItem(e.icon, e.quality)
        row.name:SetText(e.link or e.name or ("item " .. e.itemId))
        row.source:SetText(e.source)
        row.sub:SetText(e.text)
        row:Show()
    end
    hideGuildRows(#entries + 1)
    guildCount:SetText((#entries == 1 and L["%d item"] or L["%d items"]):format(#entries))
    guildEmpty:SetShown(#entries == 0)
    if #entries == 0 then
        guildEmpty:SetText(query ~= "" and L["No matches."] or L["No lists yet. They arrive from guild members who use Orion BiS."])
    end
    guildScroll:SetContentHeight(#entries == 0 and 200 or #entries * ITEM_ROW)
end


-- ============================================================================================
-- Settings
-- ============================================================================================

local settings = newPage("settings")
local column

local function section(x, y, text)
    local fs = T.Text(settings, 10, C.accent, true)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(string.upper(text))
    column = { x = x, y = y - 26 }
    return fs
end

local function add(widget, height)
    widget:SetPoint("TOPLEFT", column.x, column.y)
    column.y = column.y - (height or 30)
    return widget
end

local function note(text)
    local fs = T.Text(settings, 11, C.muted)
    fs:SetWordWrap(true)
    fs:SetWidth(380)
    fs:SetText(text)
    add(fs, fs:GetStringHeight() + 14)
    return fs
end

local function setting(name) return function() return ns.Setting(name) end, function(v) ns.SetSetting(name, v) end end

section(28, -24, L["Loot alerts"])
add(T.Check(settings, L["Show an alert when a wanted item drops"], setting("alerts")))
local STYLES = { { value = "orion", text = "Orion" }, { value = "achievement", text = L["Achievement"] } }
local styleDrop = T.Dropdown(settings, 200, function() return STYLES end, function(value)
    ns.SetSetting("alertStyle", value)
    ns.TestAlert()
end)
styleDrop:SetPoint("TOPLEFT", column.x + 26, column.y + 2)
styleDrop:SetScript("OnShow", function(self)
    for _, choice in ipairs(STYLES) do
        if choice.value == ns.Setting("alertStyle") then self:SetValue(choice.value, choice.text) end
    end
end)
column.y = column.y - 34
add(T.Check(settings, L["Play a sound for items on your list"], setting("sound")))
local SOUNDS = { { value = "achievement", text = L["Achievement"] }, { value = "loot", text = L["Epic loot"] },
    { value = "raid", text = L["Raid warning"] } }
local soundDrop = T.Dropdown(settings, 200, function() return SOUNDS end, function(value)
    ns.SetSetting("soundChoice", value)
    ns.PlayAlertSound(value)
end)
soundDrop:SetPoint("TOPLEFT", column.x + 26, column.y + 2)
soundDrop:SetScript("OnShow", function(self)
    for _, choice in ipairs(SOUNDS) do
        if choice.value == ns.Setting("soundChoice") then self:SetValue(choice.value, choice.text) end
    end
end)
column.y = column.y - 34
add(T.Check(settings, L["Make items on your list flash gold when they drop"], setting("rollFlash")))
local testButton = add(T.Button(settings, L["Test alert"], 110, 26, function() ns.TestAlert() end), 34)
local moveButton = T.Button(settings, L["Move alerts"], 110, 26, function() ns.ToggleAlertMover() end)
moveButton:SetPoint("LEFT", testButton, "RIGHT", 6, 0)
local resetButton = T.Button(settings, L["Reset position"], 120, 26, function() ns.ResetAlertPosition() end)
resetButton:SetPoint("LEFT", moveButton, "RIGHT", 6, 0)

section(28, -300, L["Display"])
add(T.Check(settings, L["Show who wants an item in tooltips"], setting("tooltip")))
add(T.Check(settings, L["Show the minimap button"], setting("minimap")))
local scaleLabel = add(T.Text(settings, 12, C.text), 22)
scaleLabel:SetText(L["Window size"])
add(T.Slider(settings, 220, 0.7, 1.4, 0.05, function() return ns.Setting("scale") end, function(v)
    ns.SetSetting("scale", math.floor(v * 100 + 0.5) / 100)
end, "%.2f"), 30)

section(470, -24, L["Guild"])
add(T.Check(settings, L["Share lists with my guild"], function() return not OrionBiSDB.noSync end, function(v) ns.SetSync(v) end))
note(L["Lists are sent on your guild's hidden addon channel, so only guild members running Orion BiS see them. Nothing is posted in chat and the addon never goes online."])

section(470, -190, L["Your list"])
local clearArmed = false
local clearButton
clearButton = add(T.Button(settings, L["Clear my list"], 150, 26, function()
    if not clearArmed then
        clearArmed = true
        clearButton:SetText(L["Click again to clear"])
        clearButton:SetActive(true, C.danger)
        C_Timer.After(4, function()
            clearArmed = false
            clearButton:SetText(L["Clear my list"])
            clearButton:SetActive(false)
        end)
        return
    end
    clearArmed = false
    ns.ClearMine()
    clearButton:SetText(L["Clear my list"])
    clearButton:SetActive(false)
end), 34)
note(L["Removes every item from this character's list, for your guild too."])

section(470, -320, L["About"])
note(L["Orion BiS %s. Websites can make codes for /bis import in the ORIONBIS1 format described on the addon page."]:format(ns.VERSION))

function settings:Refresh() end

-- ============================================================================================
-- Open / close
-- ============================================================================================

local function applyScale() win:SetScale(ns.Setting("scale") or 1) end

local function open(page, action)
    applyScale()
    win:Show()
    showPage(page or currentPage or OrionBiSDB.page or "loot")
    if action then dialog:Open(action) end
end

ns.On("OPEN", open)
ns.On("TOGGLE", function()
    if win:IsShown() then win:Hide() else open() end
end)
ns.On("SETTINGS_CHANGED", function(name)
    if name == "scale" then applyScale() end
    refreshStatus()
end)

local pendingRefresh = false
local function refreshSoon()
    if pendingRefresh or not win:IsShown() then return end
    pendingRefresh = true
    C_Timer.After(0.25, function()
        pendingRefresh = false
        if not win:IsShown() then return end
        refreshStatus()
        if currentPage == "loot" then renderLootRows()
        elseif pages[currentPage] and pages[currentPage].Refresh then pages[currentPage]:Refresh() end
    end)
end
ns.On("LISTS_CHANGED", refreshSoon)

local fontsRefreshed = false
win:SetScript("OnShow", function()
    if not fontsRefreshed then
        fontsRefreshed = true
        T.RefreshFonts()
        for _, tab in pairs(tabs) do tab:SetWidth(math.max(72, tab.label:GetStringWidth() + 28)) end
    end
    refreshStatus()
end)
win:SetScript("OnHide", function()
    dialog:Hide()
    if OrionBiSMenu then OrionBiSMenu:Hide() end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
watcher:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
    if not win:IsShown() then return end
    if currentPage == "loot" then
        if event == "GET_ITEM_INFO_RECEIVED" and not lootPending then return end
        if not watcher.pending then
            watcher.pending = true
            C_Timer.After(0.3, function() watcher.pending = false; loot:Refresh() end)
        end
    else
        refreshSoon()
    end
end)
