--[[----------------------------------------------------------------------------
    Locale — Auswahl der Sprachtabelle.

    Reihenfolge in der .toc: Locale.lua, dann enUS.lua, dann deDE.lua.
    enUS ist die Grundlage und wird IMMER geladen; deDE ueberschreibt, was es
    uebersetzt hat. Fehlt ein Schluessel in beiden, liefert die Metatabelle aus
    Core\Init.lua den Schluessel selbst — sichtbar als Text, statt nil im UI.

    ===========================================================================
    DIE SPRACHE WAEHLT DER SPIELER, NICHT DER CLIENT (21.09.2026)
    ===========================================================================

    Vorher entschied GetLocale(). Das klingt hilfreich und ist es nicht:

      Der Forever-Client wechselt die Sprache — deutsch und englisch am selben
      Tag beobachtet. Das Addon wechselte dann mit, ohne dass jemand etwas
      getan hatte.

      Und eine Gilde spricht nicht die Sprache ihres Clients. Wer auf einem
      deutschen Client mit englischen Begriffen arbeitet, bekam Deutsch
      aufgezwungen.

    Deshalb: ENGLISCH IST DIE GRUNDEINSTELLUNG, und wer etwas anderes will,
    stellt es ein. "auto" bleibt als ausdrueckliche Wahl erhalten — dann
    entscheidet wieder der Client, aber weil jemand das so wollte.

    ===========================================================================
    WANN DIE EINSTELLUNG GREIFT
    ===========================================================================

    Apply() laeuft ZWEIMAL:

      Beim Laden der Dateien — da gibt es noch keine Datenbank (SavedVariables
      kommen erst mit ADDON_LOADED), also gilt die Grundeinstellung.

      Bei PLAYER_LOGIN — jetzt steht die Einstellung, und GA.L wird neu
      gefuellt. Zu diesem Zeitpunkt ist noch kein Fenster gebaut: Views
      entstehen erst beim ersten Oeffnen.

    Daraus folgt eine Regel, die eingehalten werden MUSS: Auf Dateiebene wird
    kein L.X in eine Variable kopiert. Eine solche Kopie entsteht beim Laden
    und weiss vom zweiten Apply nichts mehr. Wer eine Beschriftung braucht,
    merkt sich den SCHLUESSEL und loest ihn beim Anzeigen auf — so wie die
    Navigationsleiste in MainFrame.lua es tut.
------------------------------------------------------------------------------]]

local _, GA = ...

local Locale = {}
GA.Core.Locale = Locale

Locale.tables = {}

--- Die Sprachen, die vollstaendig vorliegen. Reihenfolge der Auswahlliste.
Locale.SUPPORTED = { "enUS", "deDE" }

--- Ohne Einstellung: Englisch.
Locale.DEFAULT = "enUS"

--- Registriert eine Sprachtabelle. Aufruf aus enUS.lua / deDE.lua.
function Locale:Register(code, entries)
    self.tables[code] = entries
end

--- Gibt es diese Sprache ueberhaupt?
function Locale:Has(code)
    return code ~= nil and self.tables[code] ~= nil
end

--- Welche Sprache gilt — und warum.
---
--- Die Begruendung wird mitgeliefert, damit /ga status sie nennen kann. Ohne
--- sie steht dort nur ein Code, und niemand weiss, ob er aus der Einstellung
--- oder vom Client kommt.
---
--- @return string code
--- @return string reason  "setting" | "client" | "default"
function Locale:Resolve()
    local account = GA.Core.Database and GA.Core.Database.account
    local choice = account and account.language

    if choice == "auto" then
        local client = (type(GetLocale) == "function" and GetLocale()) or nil
        if self:Has(client) then return client, "client" end
        -- Ein Client auf Franzoesisch bekommt Englisch, nicht den nackten
        -- Schluessel: "auto" heisst "such es aus", nicht "brich ab".
        return self.DEFAULT, "client"
    end

    if self:Has(choice) then return choice, "setting" end
    return self.DEFAULT, "default"
end

--- Baut GA.L aus der Grundlage (enUS) und der aktiven Sprache.
--- @param force string|nil  Sprache erzwingen, sonst entscheidet Resolve
function Locale:Apply(force)
    local active, reason
    if self:Has(force) then
        active, reason = force, "forced"
    else
        active, reason = self:Resolve()
    end

    self.active = active
    self.reason = reason

    local base = self.tables[self.DEFAULT] or {}
    local override = self.tables[active] or {}

    for key, value in pairs(base) do GA.L[key] = value end
    for key, value in pairs(override) do GA.L[key] = value end

    return active
end

--- Setzt die Sprache und schreibt sie in die Datenbank.
---
--- Das neu Gefuellte GA.L reicht NICHT: Was schon als Text in einem Fenster
--- steht, wurde beim Bauen kopiert und aendert sich nicht mehr. Deshalb gibt
--- diese Funktion zurueck, ob ein /reload noetig ist — und die Einstellungen
--- sagen es dann auch.
---
--- @return boolean geaendert
function Locale:Choose(code)
    if code ~= "auto" and not self:Has(code) then return false end

    local account = GA.Core.Database and GA.Core.Database.account
    if not account then return false end
    if account.language == code then return false end

    account.language = code
    self:Apply()
    return true
end
