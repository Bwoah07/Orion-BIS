-- Orion BiS look: flat dark panels, gold accent, Inter font. Everything is drawn from solid colours and the addon's
-- own media (Media/), no Blizzard frame templates or textures. Item icons are the game's own item art.

local _, ns = ...

local T = {}
ns.T = T

T.C = {
    bg       = { 0.055, 0.058, 0.075, 0.97 },
    panel    = { 0.085, 0.090, 0.115, 1 },
    row      = { 0.115, 0.120, 0.150, 1 },
    rowHover = { 0.155, 0.160, 0.200, 1 },
    border   = { 0.200, 0.205, 0.255, 1 },
    accent   = { 1.000, 0.784, 0.251, 1 },
    text     = { 0.925, 0.925, 0.950, 1 },
    muted    = { 0.560, 0.565, 0.630, 1 },
    danger   = { 0.950, 0.360, 0.330, 1 },
    b        = { 1.000, 0.784, 0.251, 1 },
    u        = { 0.353, 0.659, 1.000, 1 },
    m        = { 0.561, 0.820, 0.561, 1 },
}
local C = T.C

-- Inter covers Latin, Cyrillic and Greek; Korean and Chinese clients keep the game's font for their scripts.
local CJK = { koKR = true, zhCN = true, zhTW = true }
local FONT = ns.MEDIA .. "Fonts\\Inter-Regular.ttf"
local FONT_BOLD = ns.MEDIA .. "Fonts\\Inter-SemiBold.ttf"
if CJK[ns.LOCALE] then
    FONT = STANDARD_TEXT_FONT
    FONT_BOLD = STANDARD_TEXT_FONT
end

T.ICON = {
    logo  = ns.MEDIA .. "Icons\\Logo",
    close = ns.MEDIA .. "Icons\\Close",
    check = ns.MEDIA .. "Icons\\Check",
    arrow = ns.MEDIA .. "Icons\\Arrow",
}

function T.Fill(frame, color, layer, sublevel)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    tex:SetAllPoints()
    tex:SetColorTexture(unpack(color))
    return tex
end

--- A 1px border drawn with four textures. Returns a handle with :SetColor(r, g, b, a).
function T.Border(frame, color, size)
    size = size or 1
    local edges = {}
    for i = 1, 4 do
        local tex = frame:CreateTexture(nil, "BORDER", nil, 7)
        tex:SetColorTexture(unpack(color))
        edges[i] = tex
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(size)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(size)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(size)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(size)
    return {
        SetColor = function(_, r, g, b, a) for _, e in ipairs(edges) do e:SetColorTexture(r, g, b, a or 1) end end,
        SetShown = function(_, shown) for _, e in ipairs(edges) do e:SetShown(shown) end end,
    }
end

function T.Box(parent, color, borderColor, name)
    local f = CreateFrame("Frame", name, parent)
    f.bg = T.Fill(f, color or C.panel)
    if borderColor ~= false then f.border = T.Border(f, borderColor or C.border) end
    return f
end

-- Text set before the game has loaded the addon's font file can stay invisible until it changes, so every text is
-- re-applied once the player is in the world (and again the first time the window opens).
local fontStrings = setmetatable({}, { __mode = "k" })

function T.SetFont(fs, size, bold)
    fontStrings[fs] = { size = size or 12, bold = bold }
    fs:SetFont(bold and FONT_BOLD or FONT, size or 12, "")
    if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size or 12, "") end
end

function T.RefreshFonts()
    for fs, f in pairs(fontStrings) do
        fs:SetFont(f.bold and FONT_BOLD or FONT, f.size, "")
        if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, f.size, "") end
        if fs:GetObjectType() == "FontString" then
            local text = fs:GetText()
            if text and text ~= "" then
                fs:SetText("")
                fs:SetText(text)
            end
        end
    end
end

local fontLoader = CreateFrame("Frame")
fontLoader:RegisterEvent("PLAYER_LOGIN")
fontLoader:SetScript("OnEvent", function()
    T.RefreshFonts()
    C_Timer.After(1, T.RefreshFonts)
end)

function T.Text(parent, size, color, bold, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    T.SetFont(fs, size, bold)
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function T.ShowTooltip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
        if i == 1 then GameTooltip:SetText(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.8, 0.8, 0.85, true) end
    end
    GameTooltip:Show()
end

local function hoverTooltip(frame, tooltip)
    if not tooltip then return end
    frame:HookScript("OnEnter", function(self)
        T.ShowTooltip(self, type(tooltip) == "function" and tooltip() or tooltip)
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--- Flat button. style: "accent" (gold), "ghost" (no fill until hovered), "nav" (ghost; active = gold bar on the left)
--- or nil (panel).
--- b:SetActive(on, color) paints it as a selected chip/tab.
function T.Button(parent, text, width, height, onClick, style, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 100, height or 24)
    b.style = style
    b.bg = T.Fill(b, C.row, "BACKGROUND")
    b.border = T.Border(b, C.border)
    b.label = T.Text(b, 12, C.text, true, "CENTER")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetText(text or "")
    if style == "nav" then
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(2)
        b.bar:SetColorTexture(unpack(C.accent))
    end
    function b:SetText(t) self.label:SetText(t) end
    function b:Paint()
        local hover = self:IsMouseOver() and self:IsEnabled()
        if self.bar then self.bar:SetShown(self.active and true or false) end
        if self.style == "nav" then
            self.bg:SetColorTexture(1, 1, 1, self.active and 0.06 or (hover and 0.04 or 0))
            self.border:SetColor(1, 1, 1, 0)
            self.label:SetTextColor(unpack(self.active and C.accent or (hover and C.text or C.muted)))
        elseif self.active then
            local c = self.activeColor or C.accent
            self.bg:SetColorTexture(c[1], c[2], c[3], hover and 0.32 or 0.22)
            self.border:SetColor(c[1], c[2], c[3], 1)
            self.label:SetTextColor(c[1], c[2], c[3], 1)
        elseif self.style == "accent" then
            self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], hover and 1 or 0.88)
            self.border:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self.label:SetTextColor(0.08, 0.07, 0.04, 1)
        elseif self.style == "ghost" then
            self.bg:SetColorTexture(1, 1, 1, hover and 0.07 or 0)
            self.border:SetColor(1, 1, 1, 0)
            self.label:SetTextColor(unpack(hover and C.text or C.muted))
        else
            local c = hover and C.rowHover or C.row
            self.bg:SetColorTexture(unpack(c))
            self.border:SetColor(unpack(C.border))
            self.label:SetTextColor(unpack(self:IsEnabled() and C.text or C.muted))
        end
    end
    function b:SetActive(on, color)
        self.active = on and true or nil
        self.activeColor = color
        self:Paint()
    end
    b:SetScript("OnEnter", b.Paint)
    b:SetScript("OnLeave", b.Paint)
    b:SetScript("OnEnable", b.Paint)
    b:SetScript("OnDisable", b.Paint)
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    hoverTooltip(b, tooltip)
    b:Paint()
    return b
end

function T.IconButton(parent, icon, size, onClick, tooltip, color)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.bg = T.Fill(b, { 1, 1, 1, 0 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(size * 0.6, size * 0.6)
    b.icon:SetTexture(icon)
    b.color = color or C.muted
    local function paint(self)
        local hover = self:IsMouseOver()
        self.bg:SetColorTexture(1, 1, 1, hover and 0.08 or 0)
        local c = (hover or self.on) and (self.hoverColor or C.text) or self.color
        self.icon:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
    b.Paint = paint
    b:SetScript("OnEnter", paint)
    b:SetScript("OnLeave", paint)
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    hoverTooltip(b, tooltip)
    paint(b)
    return b
end

--- Checkbox with label. get() returns the current value; set(value) stores it.
function T.Check(parent, label, get, set, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.box = T.Box(b, C.row, C.border)
    b.box:SetSize(18, 18)
    b.box:SetPoint("LEFT")
    b.mark = b.box:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("CENTER")
    b.mark:SetSize(16, 16)
    b.mark:SetTexture(T.ICON.check)
    b.mark:SetVertexColor(0.08, 0.07, 0.04)
    b.label = T.Text(b, 12, C.text)
    b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.label:SetText(label)
    b:SetWidth(30 + b.label:GetStringWidth())
    function b:Refresh()
        local on = get()
        self.mark:SetShown(on and true or false)
        if on then self.box.bg:SetColorTexture(unpack(C.accent)) else self.box.bg:SetColorTexture(unpack(C.row)) end
        self.box.border:SetColor(unpack((on or self:IsMouseOver()) and C.accent or C.border))
    end
    b:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
    b:SetScript("OnEnter", b.Refresh)
    b:SetScript("OnLeave", b.Refresh)
    b:SetScript("OnShow", b.Refresh)
    hoverTooltip(b, tooltip)
    b:Refresh()
    return b
end

function T.EditBox(parent, width, placeholder)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 200, 26)
    e:SetAutoFocus(false)
    e:SetTextInsets(8, 8, 0, 0)
    e:SetFontObject(ChatFontNormal)
    T.SetFont(e, 12)
    e:SetTextColor(unpack(C.text))
    e.bg = T.Fill(e, C.bg)
    e.border = T.Border(e, C.border)
    e.hint = T.Text(e, 12, C.muted)
    e.hint:SetPoint("LEFT", 9, 0)
    e.hint:SetPoint("RIGHT", -8, 0)
    e.hint:SetText(placeholder or "")
    e:SetScript("OnEditFocusGained", function(self) self.border:SetColor(unpack(C.accent)) end)
    e:SetScript("OnEditFocusLost", function(self) self.border:SetColor(unpack(C.border)) end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:HookScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    return e
end

--- Scrolling area with a thin custom scrollbar. Put children on s.content and call s:SetContentHeight(h).
function T.Scroll(parent)
    local s = CreateFrame("ScrollFrame", nil, parent)
    s.content = CreateFrame("Frame", nil, s)
    s.content:SetSize(1, 1)
    s:SetScrollChild(s.content)
    s.track = s:CreateTexture(nil, "ARTWORK")
    s.track:SetColorTexture(1, 1, 1, 0.04)
    s.track:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
    s.track:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    s.track:SetWidth(4)
    s.thumb = CreateFrame("Frame", nil, s)
    s.thumb:SetWidth(4)
    s.thumb.tex = T.Fill(s.thumb, { C.muted[1], C.muted[2], C.muted[3], 0.6 }, "OVERLAY")
    s.thumb:EnableMouse(true)

    function s:MaxScroll() return math.max(0, self.content:GetHeight() - self:GetHeight()) end
    function s:UpdateBar()
        local max, h = self:MaxScroll(), self:GetHeight()
        local show = max > 1
        self.track:SetShown(show)
        self.thumb:SetShown(show)
        if not show then return end
        local thumbH = math.max(24, h * h / self.content:GetHeight())
        self.thumb:SetHeight(thumbH)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(h - thumbH) * (self:GetVerticalScroll() / max))
    end
    function s:ScrollTo(value)
        self:SetVerticalScroll(math.max(0, math.min(self:MaxScroll(), value)))
        self:UpdateBar()
    end
    function s:SetContentHeight(height)
        self.content:SetHeight(math.max(1, height))
        self:ScrollTo(self:GetVerticalScroll())
    end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:GetVerticalScroll() - delta * 48) end)
    s:SetScript("OnSizeChanged", function(self, width)
        self.content:SetWidth(math.max(1, width - 10))
        self:UpdateBar()
    end)
    -- Drag the thumb.
    s.thumb:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.startY, self.startScroll = y / self:GetEffectiveScale(), s:GetVerticalScroll()
        self:SetScript("OnUpdate", function(me)
            local _, cy = GetCursorPosition()
            local range = s:GetHeight() - me:GetHeight()
            if range > 0 then s:ScrollTo(me.startScroll + (me.startY - cy / me:GetEffectiveScale()) * s:MaxScroll() / range) end
        end)
    end)
    s.thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    return s
end

-- One shared dropdown menu; T.Dropdown buttons fill it on click.
local menu = T.Box(UIParent, C.panel, C.border, "OrionBiSMenu")
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:Hide()
menu.scroll = T.Scroll(menu)
menu.scroll:SetPoint("TOPLEFT", 4, -4)
menu.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
menu.buttons = {}
tinsert(UISpecialFrames, "OrionBiSMenu")
menu:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
end)
menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN"); self.owner = nil end)

local function openMenu(owner, choices, onSelect, selected)
    if menu:IsShown() and menu.owner == owner then menu:Hide(); return end
    menu.owner = owner
    local width = owner:GetWidth()
    for i, choice in ipairs(choices) do
        local b = menu.buttons[i]
        if not b then
            b = T.Button(menu.scroll.content, "", width, 24, nil, "ghost")
            b.label:SetJustifyH("LEFT")
            menu.buttons[i] = b
        end
        b:SetWidth(width - 18)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
        b:SetText(choice.text)
        b:SetActive(choice.value == selected)
        b:SetScript("OnClick", function() menu:Hide(); onSelect(choice.value, choice) end)
        b:Show()
    end
    for i = #choices + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu.scroll:SetContentHeight(#choices * 24)
    menu:SetSize(width, math.min(#choices, 14) * 24 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu:Show()
    menu.scroll:ScrollTo(0)
end

--- A select box. getChoices() -> { { value=, text= }, ... }; d:SetValue(value, text).
function T.Dropdown(parent, width, getChoices, onSelect)
    local d = T.Button(parent, "", width, 26)
    d.label:ClearAllPoints()
    d.label:SetPoint("LEFT", 10, 0)
    d.label:SetPoint("RIGHT", -24, 0)
    d.label:SetJustifyH("LEFT")
    d.arrow = d:CreateTexture(nil, "OVERLAY")
    d.arrow:SetTexture(T.ICON.arrow)
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", -8, 0)
    d.arrow:SetRotation(-math.pi / 2)
    d.arrow:SetVertexColor(unpack(C.muted))
    function d:SetValue(value, text) self.value = value; self:SetText(text or "") end
    d:SetScript("OnClick", function(self)
        openMenu(self, getChoices(), function(value, choice)
            self:SetValue(value, choice.text)
            onSelect(value, choice)
        end, self.value)
    end)
    return d
end

--- Horizontal slider. get() / set(value).
function T.Slider(parent, width, min, max, step, get, set, format)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetColorTexture(unpack(C.border))
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(4)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpack(C.accent))
    thumb:SetSize(10, 16)
    s:SetThumbTexture(thumb)
    s.valueText = T.Text(s, 12, C.muted)
    s.valueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetScript("OnValueChanged", function(self, value, byUser)
        self.valueText:SetText((format or "%s"):format(value))
        if byUser then set(value) end
    end)
    s:SetScript("OnShow", function(self) self:SetValue(get()) end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local v = math.max(min, math.min(max, self:GetValue() + delta * step))
        self:SetValue(v)
        set(v)
    end)
    s:SetValue(get())
    return s
end

--- Colour of an item quality: a number (Enum.ItemQuality) or a hex colour like "ffa335ee" (what the
--- Adventure Guide gives). Returns { r=, g=, b= } or nil.
function T.QualityColor(quality)
    if type(quality) == "number" then return ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] end
    if type(quality) == "string" then
        local hex = quality:match("(%x%x%x%x%x%x)$")
        if hex then
            return { r = tonumber(hex:sub(1, 2), 16) / 255, g = tonumber(hex:sub(3, 4), 16) / 255, b = tonumber(hex:sub(5, 6), 16) / 255 }
        end
    end
end

--- One box split into options, like BiS | Upgrade | Minor. onPick(value) fires on click;
--- seg:Set(value) highlights one (nil for none). Each part is as wide as its label (opt.width overrides).
function T.Segmented(parent, options, height, onPick)
    local seg = CreateFrame("Frame", nil, parent)
    seg:SetHeight(height or 24)
    seg.bg = T.Fill(seg, C.panel)
    seg.border = T.Border(seg, C.border)
    seg.buttons = {}
    local x = 0
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, seg)
        b:SetPoint("TOPLEFT", x, 0)
        b.value = opt.value
        b.bg = T.Fill(b, { 1, 1, 1, 0 }, "ARTWORK")
        b.bg:SetPoint("TOPLEFT", 1, -1)
        b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        b.label = T.Text(b, 11, C.muted, true, "CENTER")
        b.label:SetPoint("LEFT", 2, 0)
        b.label:SetPoint("RIGHT", -2, 0)
        b.label:SetText(opt.text)
        local width = opt.width or math.max(opt.minWidth or 44, math.ceil((b.label:GetStringWidth() or 0) + 18))
        b:SetSize(width, height or 24)
        if i > 1 then
            local line = seg:CreateTexture(nil, "BORDER")
            line:SetColorTexture(unpack(C.border))
            line:SetPoint("TOPLEFT", x, 0)
            line:SetPoint("BOTTOMLEFT", x, 0)
            line:SetWidth(1)
        end
        function b:Paint()
            local hover = self:IsMouseOver()
            local c = self.color
            if seg.current == self.value and c then
                self.bg:SetColorTexture(c[1], c[2], c[3], hover and 0.34 or 0.24)
                self.label:SetTextColor(c[1], c[2], c[3], 1)
            else
                self.bg:SetColorTexture(1, 1, 1, hover and 0.07 or 0)
                self.label:SetTextColor(unpack(hover and C.text or C.muted))
            end
        end
        b:SetScript("OnEnter", function(self) self:Paint(); if seg.onEnter then seg.onEnter() end end)
        b:SetScript("OnLeave", function(self) self:Paint(); if seg.onLeave then seg.onLeave() end end)
        b:SetScript("OnClick", function(self) onPick(self.value) end)
        b.color = opt.color
        seg.buttons[i] = b
        x = x + width
    end
    seg:SetWidth(x)
    function seg:Set(value)
        self.current = value
        local c = C.border
        for _, b in ipairs(self.buttons) do
            b:Paint()
            if b.value == value and b.color then c = b.color end
        end
        self.border:SetColor(c[1], c[2], c[3], value and 0.9 or 1)
    end
    seg:Set(nil)
    return seg
end

--- Square item icon with a quality-coloured edge.
function T.ItemIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.edge = T.Border(f, C.border)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function f:SetItem(icon, quality)
        self.tex:SetTexture(icon or 134400)
        local color = T.QualityColor(quality)
        if color then self.edge:SetColor(color.r, color.g, color.b, 1) else self.edge:SetColor(unpack(C.border)) end
    end
    return f
end

--- Thin horizontal rule.
function T.Rule(parent, color)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(unpack(color or C.border))
    tex:SetHeight(1)
    return tex
end
