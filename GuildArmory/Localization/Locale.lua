--[[----------------------------------------------------------------------------
    Locale — Auswahl der Sprachtabelle.

    Reihenfolge in der .toc: Locale.lua, dann enUS.lua, dann deDE.lua.
    enUS ist die Grundlage und wird IMMER geladen; deDE ueberschreibt, was es
    uebersetzt hat. Fehlt ein Schluessel in beiden, liefert die Metatabelle aus
    Core\Init.lua den Schluessel selbst — sichtbar als Text, statt nil im UI.

    Der Forever-Client wechselt nachweislich die Sprache (deutsch und englisch am
    selben Tag beobachtet). Deshalb entscheidet GetLocale() zur Laufzeit, nicht
    eine Konstante.
------------------------------------------------------------------------------]]

local _, GA = ...

local Locale = {}
GA.Core.Locale = Locale

Locale.tables = {}

--- Registriert eine Sprachtabelle. Aufruf aus enUS.lua / deDE.lua.
function Locale:Register(code, entries)
    self.tables[code] = entries
end

--- Baut GA.L aus der Grundlage (enUS) und der aktiven Sprache.
function Locale:Apply()
    local active = (type(GetLocale) == "function" and GetLocale()) or "enUS"
    self.active = active

    local base = self.tables.enUS or {}
    local override = self.tables[active] or {}

    for key, value in pairs(base) do GA.L[key] = value end
    for key, value in pairs(override) do GA.L[key] = value end

    return active
end
