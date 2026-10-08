-- Drop toasts (who wants the item that just dropped), the gold flash on your loot roll, and item tooltip lines.

local _, ns = ...
local L, T = ns.L, ns.T
local C = T.C

local DEDUPE_SECONDS = 180

-- ---- Tooltips ------------------------------------------------------------------------------

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not ns.Setting("tooltip") then return end
        local itemId = data and ns.safe(data.id)
        if type(itemId) ~= "number" or not ns.ItemsWanted()[itemId] then return end
        local mine = ns.MyWant(itemId)
        if mine and not mine.got then
            tooltip:AddLine(ns.PriorityHex(mine.p) .. "Orion BiS: " .. L["on your list"] .. " (" .. ns.PriorityLabel(mine.p) .. ")|r")
        end
        local others = ns.WantersText(itemId, true)
        if others then tooltip:AddLine(L["Wanted by"] .. "  " .. others, 1, 1, 1, true) end
    end)
end

-- ---- Effects: gold glow, shine sweep, badge ----------------------------------------------------

local function addAlpha(group, from, to, duration, order, smoothing, delay)
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    a:SetOrder(order or 1)
    if smoothing then a:SetSmoothing(smoothing) end
    if delay then a:SetStartDelay(delay) end
    return a
end

--- A band of light clipped to `parent`. Returns the band frame and its sweep animation group;
--- call group.move:SetOffset(width, 0) before playing so it crosses the whole frame.
local function newShine(parent, level)
    local r, g, b = unpack(C.accent)
    local clip = CreateFrame("Frame", nil, parent)
    clip:SetAllPoints()
    clip:SetClipsChildren(true)
    if level then clip:SetFrameLevel(level) end
    local shine = CreateFrame("Frame", nil, clip)
    shine:SetSize(80, 400)
    shine:SetPoint("LEFT", clip, "LEFT", -90, 0)
    local left = shine:CreateTexture(nil, "OVERLAY")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(40)
    left:SetColorTexture(1, 1, 1, 1)
    left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(1, 0.95, 0.75, 0.85))
    left:SetBlendMode("ADD")
    local right = shine:CreateTexture(nil, "OVERLAY")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(40)
    right:SetColorTexture(1, 1, 1, 1)
    right:SetGradient("HORIZONTAL", CreateColor(1, 0.95, 0.75, 0.85), CreateColor(r, g, b, 0))
    right:SetBlendMode("ADD")
    shine:SetAlpha(0)
    local group = shine:CreateAnimationGroup()
    group.move = group:CreateAnimation("Translation")
    group.move:SetDuration(0.85)
    group.move:SetSmoothing("IN_OUT")
    group.move:SetOrder(1)
    addAlpha(group, 1, 1, 0.85, 1)
    group.clip = clip
    return shine, group
end

--- A soft gold glow just outside `frame`'s edges (it never covers what's inside). Returns its holder frame.
local function newHalo(frame, size, strength)
    local r, g, b = unpack(C.accent)
    local halo = CreateFrame("Frame", nil, frame)
    halo:SetPoint("TOPLEFT", -size, size)
    halo:SetPoint("BOTTOMRIGHT", size, -size)
    halo:EnableMouse(false)
    local solid, clear = CreateColor(r, g, b, strength or 0.35), CreateColor(r, g, b, 0)
    local function strip(p1, p2, horizontal, outward)
        local t = halo:CreateTexture(nil, "BACKGROUND")
        t:SetPoint(unpack(p1)); t:SetPoint(unpack(p2))
        if horizontal then t:SetWidth(size) else t:SetHeight(size) end
        t:SetColorTexture(1, 1, 1, 1)
        -- outward: the glow fades towards the outside of the frame.
        if horizontal then t:SetGradient("HORIZONTAL", outward and clear or solid, outward and solid or clear)
        else t:SetGradient("VERTICAL", outward and clear or solid, outward and solid or clear) end
    end
    strip({ "TOPLEFT", 0, -size }, { "BOTTOMLEFT", 0, size }, true, true)        -- left
    strip({ "TOPRIGHT", 0, -size }, { "BOTTOMRIGHT", 0, size }, true, false)     -- right
    strip({ "TOPLEFT", size, 0 }, { "TOPRIGHT", -size, 0 }, false, false)        -- top
    strip({ "BOTTOMLEFT", size, 0 }, { "BOTTOMRIGHT", -size, 0 }, false, true)   -- bottom
    return halo
end

local function badgeText(p)
    return "★ " .. L["YOUR %s"]:format(string.upper(ns.PriorityLabel(p)))
end

--- Gold flash on a frame (the loot roll window, or an item in the loot window): three quick flashes,
--- a shine sweeping across every couple of seconds, then a slow gold pulse and a "YOUR BiS" badge.
--- opts.outset: how far the gold edge sits outside the frame. opts.badgeInside: badge inside the
--- frame's bottom right instead of on top of it.
local function buildFlash(f, opts)
    opts = opts or {}
    local out = opts.outset or 3
    local flash = CreateFrame("Frame", nil, f)
    flash:SetPoint("TOPLEFT", -out, out)
    flash:SetPoint("BOTTOMRIGHT", out, -out)
    flash:SetFrameLevel(f:GetFrameLevel() + 5)
    flash:EnableMouse(false)

    -- Gold edge, and a glow outside it that flashes then breathes. Nothing covers the item itself.
    flash.border = T.Border(flash, C.accent, 2)
    local halo = newHalo(flash, opts.badgeInside and 6 or 10)
    halo:SetAlpha(0)

    -- One faint shine across when it starts.
    local _, sweep = newShine(flash)
    sweep.clip:SetPoint("TOPLEFT", 2, -2)
    sweep.clip:SetPoint("BOTTOMRIGHT", -2, 2)
    sweep.clip:SetAlpha(0.35)

    local badge = T.Box(flash, C.bg, C.accent)
    badge:SetHeight(opts.badgeInside and 18 or 20)
    if opts.badgeInside then
        badge:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT", -6, 6)
    else
        badge:SetPoint("BOTTOMLEFT", flash, "TOPLEFT", 6, -1)
    end
    badge.text = T.Text(badge, opts.badgeInside and 10 or 11, C.accent, true)
    badge.text:SetPoint("CENTER")
    flash.badge = badge

    local intro = halo:CreateAnimationGroup()
    for i = 1, 3 do
        addAlpha(intro, 0.2, 1, 0.15, i * 2 - 1, "OUT")
        addAlpha(intro, 1, 0.2, 0.35, i * 2, "IN")
    end
    local pulse = halo:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    addAlpha(pulse, 0.2, 0.7, 0.9, 1, "IN_OUT")
    intro:SetScript("OnFinished", function() pulse:Play() end)

    function flash:Start(p)
        self.badge.text:SetText(badgeText(p))
        self.badge:SetWidth((self.badge.text:GetStringWidth() or 60) + 16)
        sweep.move:SetOffset(math.max(sweep.clip:GetWidth() or 0, 240) + 100, 0)
        if self:IsShown() and self.p == p then return end -- already flashing
        self.p = p
        pulse:Stop(); intro:Stop(); sweep:Stop()
        self:Show()
        intro:Play()
        sweep:Play()
    end
    function flash:Stop()
        intro:Stop(); pulse:Stop(); sweep:Stop()
        halo:SetAlpha(0)
        self.p = nil
        self:Hide()
    end
    f:HookScript("OnHide", function() flash:Stop() end)
    return flash
end

-- ---- Sounds ----------------------------------------------------------------------------------

-- The "achievement earned" fanfare: sound kit 12891, with its sound file as a fallback.
local ACHIEVEMENT_KIT, ACHIEVEMENT_FILE = 12891, 569143

function ns.PlayAlertSound(choice)
    choice = choice or ns.Setting("soundChoice")
    if choice == "raid" then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    elseif choice == "loot" then
        PlaySound(SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or 31578, "Master")
    else
        local willPlay = PlaySound(ACHIEVEMENT_KIT, "Master")
        if not willPlay then PlaySoundFile(ACHIEVEMENT_FILE, "Master") end
    end
end

-- ---- Toasts --------------------------------------------------------------------------------
-- A wanted drop pops up a toast under a movable anchor. Two looks: "orion" (our box with a soft glow
-- behind it, the default) and "achievement" (Blizzard's achievement toast with the item in it).
-- Up to three show at once, newest on top; each stays TOAST_SECONDS, longer while hovered.

local TOAST_SECONDS = 15
local MAX_TOASTS = 3
local TOAST_GAP = 10

local anchor = CreateFrame("Frame", "OrionBiSToastAnchor", UIParent)
anchor:SetSize(320, 64)
anchor:SetPoint("TOP", UIParent, "TOP", 0, -160)
anchor:SetFrameStrata("HIGH")
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)

local active = {} -- toasts on screen, newest first

local function layout()
    local y = 0
    for _, t in ipairs(active) do
        t:ClearAllPoints()
        t:SetPoint("TOP", anchor, "TOP", 0, -y)
        y = y + t:GetHeight() + TOAST_GAP
    end
end

local function release(t)
    for i, other in ipairs(active) do
        if other == t then table.remove(active, i) break end
    end
    t.inUse = false
    layout()
end

local function qualityName(link)
    local name, _, quality = C_Item.GetItemInfo(link)
    local color = T.QualityColor(quality)
    if name and color then
        return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name)
    end
    return name or link
end

local function showItemTooltip(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
end

-- Orion look ---------------------------------------------------------------------------------

local GLOW = ns.MEDIA .. "Icons\\Glow"
local orionPool = {}

local function newOrionToast()
    local t = CreateFrame("Button", nil, anchor)
    t:SetSize(320, 64)
    t:SetFrameStrata("HIGH")
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Soft glow behind the box (a 9-slice texture, so it hugs the box at any size).
    t.glow = CreateFrame("Frame", nil, t)
    t.glow:SetPoint("TOPLEFT", -34, 34)
    t.glow:SetPoint("BOTTOMRIGHT", 34, -34)
    t.glow:SetFrameLevel(math.max(t:GetFrameLevel() - 1, 0))
    t.glowTex = t.glow:CreateTexture(nil, "BACKGROUND")
    t.glowTex:SetAllPoints()
    t.glowTex:SetTexture(GLOW)
    t.glowTex:SetBlendMode("ADD") -- additive, so it reads as light on dark backgrounds
    if t.glowTex.SetTextureSliceMargins then
        t.glowTex:SetTextureSliceMargins(48, 48, 48, 48)
        if Enum and Enum.UITextureSliceMode then t.glowTex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end
    end

    t.box = T.Box(t, C.bg, C.border)
    t.box:SetAllPoints()
    -- Faint lighter band along the top, and a coloured stripe on the left.
    local sheen = t.box:CreateTexture(nil, "BORDER")
    sheen:SetPoint("TOPLEFT", 1, -1); sheen:SetPoint("TOPRIGHT", -1, -1); sheen:SetHeight(24)
    sheen:SetColorTexture(1, 1, 1, 1)
    sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.05))
    t.stripe = t.box:CreateTexture(nil, "ARTWORK")
    t.stripe:SetPoint("TOPLEFT", 1, -1); t.stripe:SetPoint("BOTTOMLEFT", 1, 1); t.stripe:SetWidth(3)

    t.icon = T.ItemIcon(t.box, 40)
    t.icon:SetPoint("LEFT", 14, 0)
    t.header = T.Text(t.box, 10, C.muted, true)
    t.header:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 12, 1)
    t.header:SetPoint("RIGHT", -12, 0)
    t.name = T.Text(t.box, 14, C.text, true)
    t.name:SetPoint("TOPLEFT", t.header, "BOTTOMLEFT", 0, -4)
    t.name:SetPoint("RIGHT", -12, 0)
    t.sub = T.Text(t.box, 11, C.muted)
    t.sub:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -4)
    t.sub:SetPoint("RIGHT", -12, 0)

    local _, sweep = newShine(t.box, t.box:GetFrameLevel() + 3)
    sweep.clip:SetPoint("TOPLEFT", 1, -1)
    sweep.clip:SetPoint("BOTTOMRIGHT", -1, 1)
    sweep.clip:SetAlpha(0.4)
    t.sweep = sweep

    -- In: fade and drop into place. Glow swells, then settles.
    t.animIn = t:CreateAnimationGroup()
    addAlpha(t.animIn, 0, 1, 0.25, 2)
    local lift = t.animIn:CreateAnimation("Translation") -- start 12px higher...
    lift:SetOffset(0, 12)
    lift:SetDuration(0)
    lift:SetOrder(1)
    local drop = t.animIn:CreateAnimation("Translation") -- ...and settle into place
    drop:SetOffset(0, -12)
    drop:SetDuration(0.25)
    drop:SetSmoothing("OUT")
    drop:SetOrder(2)
    -- Glow: a bright flash, then it settles and keeps breathing gently while the toast is up.
    t.glowIn = t.glow:CreateAnimationGroup()
    addAlpha(t.glowIn, 0, 1, 0.25, 1, "OUT")
    addAlpha(t.glowIn, 1, 0.8, 0.8, 2, "IN_OUT")
    t.breathe = t.glow:CreateAnimationGroup()
    addAlpha(t.breathe, 0.8, 0.5, 1.4, 1, "IN_OUT")
    t.breathe:SetLooping("BOUNCE")
    t.glowIn:SetScript("OnFinished", function() t.glow:SetAlpha(0.8); t.breathe:Play() end)
    t.animOut = t:CreateAnimationGroup()
    t.fade = addAlpha(t.animOut, 1, 0, 1.2, 1, nil, TOAST_SECONDS)
    t.animOut:SetScript("OnFinished", function() t:Hide() end)

    t:SetScript("OnEnter", function(self) self.animOut:Stop(); self:SetAlpha(1); showItemTooltip(self) end)
    t:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.fade:SetStartDelay(2)
        self.animOut:Play()
    end)
    t:SetScript("OnClick", function(self, button)
        if button == "RightButton" then self:Hide() return end
        if self.link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    end)
    t:SetScript("OnHide", function(self) self.animOut:Stop(); self.glowIn:Stop(); self.breathe:Stop(); release(self) end)
    t:Hide()

    function t:Fill(data)
        self.link = data.link
        self.icon:SetItem(data.icon, data.quality)
        local c = data.p and C[data.p] or C.border
        self.header:SetText(data.p and badgeText(data.p) or string.upper(L["Loot alert"]))
        self.header:SetTextColor(unpack(data.p and C[data.p] or C.muted))
        self.name:SetText(qualityName(data.link))
        self.sub:SetText(data.wanted or L["Nobody else wants it"])
        self.box.border:SetColor(c[1], c[2], c[3], data.p and 0.9 or 1)
        self.stripe:SetColorTexture(c[1], c[2], c[3], 1)
        self.stripe:SetShown(data.p and true or false)
        local g = data.p and C[data.p] or C.accent
        self.glowTex:SetVertexColor(g[1], g[2], g[3], data.p and 1 or 0.35)
    end
    function t:Play(data)
        self.breathe:Stop()
        self.glow:SetAlpha(data.p and 0.8 or 0.6)
        self.sweep.move:SetOffset(420, 0)
        self.animIn:Play()
        if data.p then self.glowIn:Play(); self.sweep:Play() end
        self.fade:SetStartDelay(TOAST_SECONDS)
        self.animOut:Play()
    end
    return t
end

local function orionToast()
    for _, t in ipairs(orionPool) do if not t.inUse then return t end end
    local t = newOrionToast()
    orionPool[#orionPool + 1] = t
    return t
end

-- Achievement look ---------------------------------------------------------------------------

local achievementPool = {}

-- The template's shield calls AchievementShield_OnLoad, which lives in the load-on-demand
-- achievement UI. Load it first, or the game logs a warning for every toast we build.
local function loadAchievementUI()
    if AchievementShield_OnLoad then return end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if load then pcall(load, "Blizzard_AchievementUI") end
end

local function newAchievementToast()
    loadAchievementUI()
    local ok, t = pcall(CreateFrame, "ContainedAlertFrame", nil, anchor, "AchievementAlertFrameTemplate")
    if not ok or not t then return nil end
    t:SetFrameStrata("HIGH")
    t.Background:SetAtlas("ui-achievement-alert-background", true)
    t.Icon.Overlay:SetAtlas("ui-achievement-iconframe", true)
    t.Icon.Overlay:SetPoint("CENTER", -1, 1)
    t.Icon:SetPoint("TOPLEFT", -4, -15)
    t.Shield:SetPoint("TOPRIGHT", -8, -15)
    t.Shield.Points:Hide()
    t.Shield.Icon:SetAtlas("UI-Achievement-Shield-NoPoints", true)
    t.GuildName:Hide(); t.GuildBorder:Hide(); t.GuildBanner:Hide()
    t.glow:SetAtlas("ui-achievement-glow-glow", true)
    t.shine:SetAtlas("ui-achievement-glow-shine", true)
    t.shine:SetPoint("BOTTOMLEFT", 0, 8)
    t:SetHeight(101)
    t.Unlocked:SetPoint("TOP", 7, -23)
    t.waitAndAnimOut.animOut:SetScript("OnFinished", function() t:Hide() end)
    t:SetScript("OnEnter", function(self) self.waitAndAnimOut:Stop(); self:SetAlpha(1); showItemTooltip(self) end)
    t:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.waitAndAnimOut.animOut:SetStartDelay(2)
        self.waitAndAnimOut:Play()
    end)
    t:SetScript("OnClick", function(self, button)
        if button == "RightButton" then self:Hide() return end
        if self.link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    end)
    t:SetScript("OnHide", function(self) self.waitAndAnimOut:Stop(); release(self) end)
    t:Hide()

    function t:Fill(data)
        self.link = data.link
        self.Unlocked:SetText(data.p and badgeText(data.p) or data.wanted or L["Loot alert"])
        self.Name:SetText(qualityName(data.link))
        self.Icon.Texture:SetTexture(data.icon or 134400)
    end
    function t:Play()
        self.animIn:Play()
        self.glow:Show(); self.glow.animIn:Play()
        self.shine:Show(); self.shine.animIn:Play()
        self.waitAndAnimOut.animOut:SetStartDelay(TOAST_SECONDS)
        self.waitAndAnimOut:Play()
    end
    return t
end

local function achievementToast()
    for _, t in ipairs(achievementPool) do if not t.inUse then return t end end
    local ok, t = pcall(newAchievementToast) -- Blizzard's template could change; then the Orion look is used
    if ok and t then achievementPool[#achievementPool + 1] = t return t end
end

-- Showing ------------------------------------------------------------------------------------

local function showToast(data)
    local t = ns.Setting("alertStyle") == "achievement" and achievementToast() or orionToast()
    t.inUse = true
    t:Fill(data)
    t:SetAlpha(1)
    t:Show()
    table.insert(active, 1, t)
    while #active > MAX_TOASTS do active[#active]:Hide() end -- oldest goes
    layout()
    t:Play(data)
end

local recent = {}

local function onDrop(link, force)
    link = ns.safe(link)
    if type(link) ~= "string" or not ns.Setting("alerts") then return end
    local itemId, _, _, _, icon = C_Item.GetItemInfoInstant(link)
    if not itemId or (not force and not ns.ItemsWanted()[itemId]) then return end
    local mine = ns.MyWant(itemId)
    if not force and not ns.WantersText(itemId, false) and not (mine and not mine.got) then return end -- all received
    local t = GetTime()
    if not force and recent[itemId] and t - recent[itemId] < DEDUPE_SECONDS then return end
    recent[itemId] = t

    local mineOpen = mine and not mine.got
    if mineOpen and ns.Setting("sound") then ns.PlayAlertSound() end
    if mineOpen then ns.Print(L["%s is on your list (%s)"]:format(link, ns.PriorityLabel(mine.p))) end
    local others = ns.WantersText(itemId, true)
    showToast({
        link = link, icon = icon, quality = select(3, C_Item.GetItemInfo(link)),
        p = mineOpen and mine.p or nil,
        wanted = others and (L["Wanted by"] .. "  " .. others:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")),
    })
end

function ns.TestAlert()
    local list = ns.MyList()
    local itemId = list and next(list.items) or next(ns.ItemsWanted())
    if not itemId then ns.Print(L["Add an item to your list first."]); return end
    local _, link = C_Item.GetItemInfo(itemId)
    onDrop(link or ("|cffa335ee|Hitem:" .. itemId .. "::::::::::::|h[item " .. itemId .. "]|h|r"), true)
end

-- Moving: a gold outline you can drag, with a hint. Right-click or the Settings button locks it.
do
    local mover = T.Box(anchor, { C.accent[1], C.accent[2], C.accent[3], 0.12 }, C.accent)
    mover:SetAllPoints()
    mover:SetFrameLevel(anchor:GetFrameLevel() + 20)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.text = T.Text(mover, 12, C.accent, true, "CENTER")
    mover.text:SetPoint("LEFT", 8, 0)
    mover.text:SetPoint("RIGHT", -8, 0)
    mover.text:SetWordWrap(true)
    mover:SetScript("OnDragStart", function() anchor:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        local point, _, relPoint, x, y = anchor:GetPoint()
        OrionBiSDB.alertPos = { point, relPoint, x, y }
    end)
    mover:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then self:Hide() end end)
    mover:Hide()

    function ns.ToggleAlertMover()
        if mover:IsShown() then mover:Hide() return end
        mover.text:SetText(L["Drag the alert to move it. Right-click it to close."])
        mover:Show()
        ns.TestAlert()
    end
end

function ns.ResetAlertPosition()
    OrionBiSDB.alertPos = nil
    anchor:ClearAllPoints()
    anchor:SetPoint("TOP", UIParent, "TOP", 0, -160)
end

-- ---- Loot roll window and loot window -----------------------------------------------------

local function flashRollFrame(rollID, p)
    local frames = {}
    if GroupLootContainer and GroupLootContainer.rollFrames then
        for _, f in pairs(GroupLootContainer.rollFrames) do frames[#frames + 1] = f end
    end
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        if _G["GroupLootFrame" .. i] then frames[#frames + 1] = _G["GroupLootFrame" .. i] end
    end
    for _, f in ipairs(frames) do
        if type(f) == "table" and f.rollID == rollID and f.IsShown and f:IsShown() then
            f.orionBiSFlash = f.orionBiSFlash or buildFlash(f)
            f.orionBiSFlash:Start(p)
            return true
        end
    end
end
ns.FlashRollFrame = flashRollFrame

--- Items on your list light up in the loot window (the corpse or chest you're looting).
--- The window reuses its item frames, so every frame is checked again each time.
local function markLootFrame(frame)
    local slot = frame.GetSlotIndex and frame:GetSlotIndex()
    local ok, link = pcall(GetLootSlotLink, slot or 0)
    link = ok and ns.safe(link)
    local itemId = type(link) == "string" and C_Item.GetItemInfoInstant(link)
    local mine = itemId and ns.MyWant(itemId)
    if mine and not mine.got and ns.Setting("rollFlash") then
        frame.orionBiSFlash = frame.orionBiSFlash or buildFlash(frame, { outset = 0, badgeInside = true })
        frame.orionBiSFlash:Start(mine.p)
    elseif frame.orionBiSFlash then
        frame.orionBiSFlash:Stop()
    end
end

local function markLootWindow()
    local box = LootFrame and LootFrame.ScrollBox
    if not (box and box.ForEachFrame and LootFrame:IsShown()) then return end
    box:ForEachFrame(function(frame) pcall(markLootFrame, frame) end)
end
ns.MarkLootWindow = markLootWindow

if LootFrame and LootFrame.ScrollBox and ScrollBoxListMixin and LootFrame.ScrollBox.RegisterCallback then
    -- Mark again whenever the list is rebuilt or scrolled.
    pcall(LootFrame.ScrollBox.RegisterCallback, LootFrame.ScrollBox, ScrollBoxListMixin.Event.OnDataRangeChanged,
        function() C_Timer.After(0, markLootWindow) end, ns)
end

-- ---- Loot events ---------------------------------------------------------------------------

local seenDrops = {}
local events = CreateFrame("Frame")
events:RegisterEvent("START_LOOT_ROLL")
events:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
events:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_SLOT_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "START_LOOT_ROLL" then
        local rollID = ...
        local ok, link = pcall(GetLootRollItemLink, rollID)
        if ok then
            onDrop(link)
            local itemId = ns.safe(link) and C_Item.GetItemInfoInstant(link)
            local mine = itemId and ns.MyWant(itemId)
            if mine and not mine.got and ns.Setting("rollFlash") then
                C_Timer.After(0.1, function() pcall(flashRollFrame, rollID, mine.p) end)
            end
        end
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        local encounterID, lootListID = ...
        local dropKey = tostring(encounterID) .. ":" .. tostring(lootListID)
        if seenDrops[dropKey] or not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
        local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
        if ok and info and info.itemHyperlink then
            seenDrops[dropKey] = true
            onDrop(info.itemHyperlink)
        end
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        local _, itemId, itemLink, _, playerName = ...
        onDrop(itemLink)
        -- You got an item from your own list: mark it received (and share that).
        itemId, playerName = ns.safe(itemId), ns.safe(playerName)
        local mine = itemId and ns.MyWant(itemId)
        if mine and not mine.got and playerName and Ambiguate(playerName, "short") == UnitName("player") then
            ns.EditMine(itemId, mine.p, true)
        end
    elseif event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" then
        C_Timer.After(0, markLootWindow)
        if event == "LOOT_SLOT_CHANGED" then return end
        for i = 1, (GetNumLootItems() or 0) do
            local ok, link = pcall(GetLootSlotLink, i)
            if ok then onDrop(link) end
        end
    end
end)

ns.On("LOADED", function()
    local p = OrionBiSDB.alertPos
    if p then
        anchor:ClearAllPoints()
        anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
end)
