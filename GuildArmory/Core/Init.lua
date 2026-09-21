--[[----------------------------------------------------------------------------
    Guild Armory — Namensraum und Grundgeruest.

    Alles haengt an der privaten Addon-Tabelle aus dem zweiten Rueckgabewert von
    `...`. Es gibt genau EINE globale Variable (`GuildArmory`, ganz unten) und die
    SavedVariables. Nichts anderes landet in _G.

    Schichtung:
        Core            Infrastruktur. Kennt weder Module noch UI.
        Compatibility   Alle versionsabhaengigen API-Aufrufe. NUR hier.
        Database        Datenmodell, Persistenz, Migration.
        Module          Armory, LootCouncil, LootHistory, Wishlist, Analytics,
                        Communication — Logik, ruft NIE CreateFrame auf.
        UI              Rendert. Enthaelt KEINE Auswertungslogik.
        Localization    Alle sichtbaren Texte.

    Module und UI reden ausschliesslich ueber Core\Callbacks miteinander.

    Guild Armory teilt sich das Fundament (Compat-Muster, Theme, Widgets, JSON,
    Datenbankmigration) mit RaidBrain. Beide Addons koennen nebeneinander laden:
    Alle globalen Frame- und Fontnamen tragen das Praefix "GuildArmory".
------------------------------------------------------------------------------]]

local ADDON_NAME, GA = ...

GA.name = ADDON_NAME
GA.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version"))
    or "0.1.0"

GA.Core = {}
GA.Data = {}
GA.Modules = {}
GA.UI = {}

--- Lokalisierungstabelle. Wird von Localization\Locale.lua befuellt; bis dahin
--- gibt jeder Zugriff den Schluessel selbst zurueck, damit nie nil im UI landet.
GA.L = setmetatable({}, { __index = function(_, key) return tostring(key) end })

GA.const = {
    -- Schema-Version der SavedVariables. Bei jeder Strukturaenderung erhoehen
    -- und in Database\Schema.lua eine Migration ergaenzen.
    DB_SCHEMA_VERSION = 1,

    -- Praefix fuer Addon-Nachrichten. Maximal 16 Zeichen.
    COMM_PREFIX = "GuildArmory",

    -- Kopfzeile von Export-Strings. Formatversion, nicht Addon-Version.
    EXPORT_PREFIX = "GA1:",

    -- Rollen im Berechtigungssystem, absteigend nach Rechten.
    ROLE_ADMIN = "ADMIN",
    ROLE_LOOTMASTER = "LOOTMASTER",
    ROLE_COUNCIL = "COUNCIL",
    ROLE_MEMBER = "MEMBER",
}

--- Wird von Compatibility\Compatibility.lua beim Laden befuellt.
GA.has = {}

--- Beschriftungen fuer Bindings.xml. Diese Namen MUESSEN global sein — die
--- Tastatureinstellungen suchen sie genau so. Ohne sie stuende dort der nackte
--- Bezeichner. Sie werden hier gesetzt und nicht in der Lokalisierung, weil das
--- Tastaturmenue sie schon beim Laden liest, bevor Locale:Apply() gelaufen ist.
--- ENGLISCH, und zwar fest: Diese Namen liest das Tastaturmenue, bevor
--- irgendetwas von der Datenbank steht — die Spracheinstellung kann sie also
--- gar nicht erreichen. Eine der beiden Sprachen muss hier stehen, und es ist
--- dieselbe wie die Grundeinstellung.
_G.BINDING_HEADER_GUILDARMORY = "Guild Armory"
_G.BINDING_NAME_GUILDARMORY_TOGGLE = "Toggle window"
_G.BINDING_NAME_GUILDARMORY_COUNCIL = "Open loot council"
_G.BINDING_NAME_GUILDARMORY_EXPORT = "Refresh export"

_G.GuildArmory = GA
