-- Translations: English text is the key. Each locale file fills ns.L only on its own client language; anything
-- missing falls back to English.
local _, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.LOCALE = GetLocale and GetLocale() or "enUS"

--- Add translations for one client language: ns.Translate("deDE", { ["English"] = "Deutsch", ... })
function ns.Translate(locale, strings)
    if locale ~= ns.LOCALE and not (locale == "esES" and ns.LOCALE == "esMX") then return end
    for k, v in pairs(strings) do
        if v and v ~= "" then rawset(ns.L, k, v) end
    end
end
