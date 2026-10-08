-- Minimap button (drag to move around the minimap). The addon compartment entry is set up in the .toc.

local _, ns = ...
local L, T = ns.L, ns.T

local button = CreateFrame("Button", "OrionBiSMinimapButton", Minimap)
button:SetSize(30, 30)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button.icon = button:CreateTexture(nil, "ARTWORK")
button.icon:SetAllPoints()
button.icon:SetTexture(T.ICON.logo)
button.glow = button:CreateTexture(nil, "OVERLAY")
button.glow:SetAllPoints()
button.glow:SetTexture(T.ICON.logo)
button.glow:SetBlendMode("ADD")
button.glow:SetAlpha(0)
button:Hide()

local function place()
    local angle = math.rad(OrionBiSDB.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        OrionBiSDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        place()
    end)
end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then ns.Fire("OPEN", "settings") else ns.Fire("TOGGLE") end
end)
button:SetScript("OnEnter", function(self)
    self.glow:SetAlpha(0.35)
    T.ShowTooltip(self, { "Orion BiS", L["Click: open or close"], L["Right-click: settings"], L["Drag: move"] })
end)
button:SetScript("OnLeave", function(self)
    self.glow:SetAlpha(0)
    GameTooltip:Hide()
end)

local function update()
    button:SetShown(ns.Setting("minimap"))
    place()
end

ns.On("LOADED", update)
ns.On("SETTINGS_CHANGED", function(name) if name == "minimap" then update() end end)
