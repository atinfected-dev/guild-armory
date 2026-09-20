--[[----------------------------------------------------------------------------
    Schema — Datenmodell der SavedVariables und Migrationskette.

    Reine Daten und Migrationsfunktionen. Keine Logik, kein UI.

    ZWEI ENTSCHEIDUNGEN, DIE SPAETER NICHT MEHR NACHRUESTBAR WAEREN:

    1. GUID ALS SCHLUESSEL FUER CHARAKTERE. Namen brechen bei Umbenennung,
       Transfer und Cross-Realm. Der Name ist Anzeige und Suchindex.

    2. MIGRATIONSKETTE AB VERSION 1. Nachtraeglich eingefuehrte Migrationen sind
       der haeufigste Grund, warum Addons die Daten ihrer Nutzer verlieren.

    STATUS EINER LOOTVERGABE (Abschnitt 7 der Vorgabe) — als Konstanten, damit
    kein Modul einen Tippfehler als neuen Zustand einfuehrt.
------------------------------------------------------------------------------]]

local _, GA = ...

local Schema = {}
GA.Data.Schema = Schema

-- ================================================================== Status ----

Schema.LootStatus = {
    DETECTED         = "DETECTED",          -- als Loot erkannt
    SESSION_OPEN     = "SESSION_OPEN",      -- Bewerbungsphase laeuft
    AWARDED          = "AWARDED",           -- Gewinner gewaehlt
    TRANSFER_PENDING = "TRANSFER_PENDING",  -- Uebergabe steht aus
    RECEIVED         = "RECEIVED",          -- Uebergabe bestaetigt
    EQUIPPED         = "EQUIPPED",          -- spaeter als angelegt erkannt
    CANCELLED        = "CANCELLED",         -- abgebrochen
    CORRECTED        = "CORRECTED",         -- nachvollziehbar korrigiert
}

--- Erlaubte Uebergaenge. Alles andere ist ein Fehler, kein Sonderfall.
Schema.LootTransitions = {
    DETECTED         = { SESSION_OPEN = true, CANCELLED = true },
    SESSION_OPEN     = { AWARDED = true, CANCELLED = true },
    AWARDED          = { TRANSFER_PENDING = true, RECEIVED = true, CANCELLED = true, CORRECTED = true },
    TRANSFER_PENDING = { RECEIVED = true, CANCELLED = true, CORRECTED = true },
    RECEIVED         = { EQUIPPED = true, CORRECTED = true },
    EQUIPPED         = { CORRECTED = true },
    CANCELLED        = {},
    CORRECTED        = {},
}

--- Wie eine Uebergabe bestaetigt wurde. "MANUAL" ist ausdruecklich gekennzeichnet:
--- Das Addon verbucht eine Vergabe nie als erfolgreich, nur weil ein Gewinner
--- gewaehlt wurde (Vorgabe, Abschnitt 7).
Schema.Confirmation = {
    MASTER_LOOT = "MASTER_LOOT",  -- GiveMasterLoot + LOOT_SLOT_CLEARED
    TRADE       = "TRADE",        -- Item im Handelsfenster, TRADE_CLOSED nach Accept
    LOOT_CHAT   = "LOOT_CHAT",    -- CHAT_MSG_LOOT "X erhaelt Y" (schwaecher)
    MANUAL      = "MANUAL",       -- vom Lootmeister von Hand bestaetigt
}

--- Antwortmoeglichkeiten bei einer Bewerbung. Konfigurierbar — das hier sind
--- die Vorgaben, die Settings kann sie ueberschreiben.
--- `short` ist die Beschriftung im Bewerbungsfenster: Dort stehen alle
--- Antworten nebeneinander in einer Zeile, und "Major Upgrade" waere auf einem
--- Knopf dieser Breite abgeschnitten. `label` bleibt die ausgeschriebene Form
--- fuer die Council-Ansicht und die Historie.
Schema.DefaultResponses = {
    { key = "BIS",     label = "Best in Slot",  short = "BiS",   weight = 100, color = { 1.00, 0.50, 0.00 } },
    { key = "MAIN",    label = "Main-Spec",     short = "Main",  weight = 80,  color = { 0.64, 0.21, 0.93 } },
    { key = "MAJOR",   label = "Major Upgrade", short = "Major", weight = 60,  color = { 0.00, 0.44, 0.87 } },
    { key = "MINOR",   label = "Minor Upgrade", short = "Minor", weight = 40,  color = { 0.12, 1.00, 0.00 } },
    { key = "OFFSPEC", label = "Off-Spec",      short = "Off",   weight = 20,  color = { 0.62, 0.62, 0.62 } },
    { key = "TRANSMOG",label = "Transmog",      short = "Mog",   weight = 10,  color = { 0.80, 0.80, 0.80 } },
    { key = "PASS",    label = "Pass",          short = "Pass",  weight = 0,   color = { 0.40, 0.40, 0.40 } },
}

Schema.WishlistPriority = {
    { key = "BIS",      label = "Best in Slot",   weight = 4 },
    { key = "HIGH",     label = "Hoch",           weight = 3 },
    { key = "MEDIUM",   label = "Mittel",         weight = 2 },
    { key = "LOW",      label = "Niedrig",        weight = 1 },
    { key = "TRANSMOG", label = "Transmog",       weight = 0 },
}

-- ================================================================== Defaults --

Schema.ACCOUNT_DEFAULTS = {
    schemaVersion = GA.const.DB_SCHEMA_VERSION,

    config = {
        debug = false,
        -- Antworten fuer Bewerbungen; nil = Schema.DefaultResponses
        responses = nil,
        -- Sichtbarkeit der Council-Stimmen: "council" | "all" | "lootmaster"
        voteVisibility = "council",
        -- Ab welcher Qualitaet Loot erfasst wird (2=gruen, 3=blau, 4=episch).
        lootThresholdQuality = 3,
        -- Auch ausserhalb einer Gruppe erfassen. Standard AUS: Sonst landet
        -- jeder Questgegenstand in der Gildenhistorie. Zum Testen einschaltbar.
        trackOutsideGroup = false,
        -- Bestaetigte Vergaben im Gildenchat bekanntgeben. Standard AUS: Ein
        -- Addon, das ungefragt in den Gildenchat schreibt, fliegt zu Recht
        -- raus. Siehe Communication/Announce.lua.
        announceLoot = false,
        announceChannel = "GUILD",

        -- Council-Rotation (siehe LootCouncil/Rotation.lua). Standard AUS:
        -- Wer sie nicht kennt, soll nicht ploetzlich fremde Stimmberechtigte
        -- im Council haben.
        rotationEnabled = false,
        -- Wie viele Sitze je Rotation vergeben werden.
        rotationSeats = 2,
        -- Wie lange ein Sitz gilt, in Stunden. Ein Raidabend ist der Anlass;
        -- die Uhr ist die Grenze.
        rotationHours = 5,
        -- Nur Gildenraenge bis zu diesem Index (kleiner = hoeher). nil = alle.
        rotationMaxRankIndex = nil,
        -- Rotation im Schlachtzug ankuendigen und die Gewaehlten anfluestern.
        rotationAnnounce = true,
        -- Tooltips ergaenzen. Standard AN: Es sind eigene Daten, die nur
        -- angezeigt werden, und der Nutzen ist sofort sichtbar.
        tooltipItems = true,
        tooltipPlayers = true,
        -- Sammlerbetrieb: Der Client laedt regelmaessig neu, damit die
        -- SavedVariables-Datei frisch bleibt. Nur fuer EINEN Client gedacht,
        -- der genau dafuer parkt — siehe Core/Export.lua. Standard AUS.
        collectorMode = false,
        collectorMinutes = 60,
    },

    ui = {
        main = { point = "CENTER", x = 0, y = 0, width = 1000, height = 640,
                 scale = 1.0, lastView = "dashboard" },
        -- Minimap-Knopf: Position als WINKEL, nicht als x/y — sonst wandert er,
        -- sobald jemand die Minimapgroesse aendert.
        minimap = { angle = 200, hidden = false },
    },

    --- [guid] = Charakterdatensatz
    --- {
    ---   guid, name, realm, class, className, race, level,
    ---   guildRank, guildRankIndex, guildName,
    ---   playerId,                -- Verknuepfung zum Spielerprofil (Main/Twink)
    ---   ownAccount,              -- true: auf DIESEM Account eingeloggt (Beweis)
    ---   specID, loadout = { value, ts },
    ---   itemLevel = { value, count, ts },
    ---   equipment = { [slotID] = { link, itemID, itemLevel, quality, enchantID,
    ---                              gems = {}, name, icon } },
    ---   equipmentTs,             -- Zeitstempel des Standes — NIE als live darstellen
    ---   source = "self" | "inspect" | "sync",
    ---   firstSeen, lastSeen,
    --- }
    characters = {},

    --- ["Name-Realm"] = guid. Suchindex, aus characters abgeleitet.
    nameIndex = {},

    --- [playerId] = Spielerprofil (Main + Twinks)
    --- { id, displayName, mainGuid, mainSetByUser,
    ---   characterGuids = { guid = true },
    ---   origin = { [guid] = "account" | "claim" | "manual" },
    ---   createdTs }
    ---
    --- origin ist Pflicht und wird angezeigt: "account" ist bewiesen (derselbe
    --- WoW-Account, also dieselbe SavedVariables-Datei), alles andere ist
    --- behauptet oder von Hand gesetzt. Siehe Armory/Players.lua.
    players = {},

    --- Ausruestungshistorie: [guid] = { { ts, itemLevel, slots = { [slotID] = itemID }, changes = {..} } }
    --- Nur eigene Charaktere; begrenzt (siehe Database.PruneSnapshots).
    snapshots = {},

    --- [awardId] = Lootvergabe. Feldliste in Abschnitt 8 der Vorgabe.
    --- { id, itemID, itemLink, itemName, quality,
    ---   recipientGuid, recipientName,
    ---   lootMasterGuid, lootMasterName,
    ---   bossName (oder nil), instanceName (oder nil), zone,
    ---   ts, sessionId, response, note,
    ---   status, statusHistory = { { status, ts, by, reason } },
    ---   confirmation = Schema.Confirmation.*, confirmedTs,
    ---   votes = { [voterGuid] = candidateGuid }, decision,
    ---   equippedTs }
    awards = {},

    --- [sessionId] = Lootsession
    sessions = {},

    --- [guid] = { { itemID, priority, note, addedTs, fulfilledByAwardId } }
    wishlists = {},

    --- Berechtigungen: [guid] = ROLE_*. Der eigene Charakter ist beim ersten
    --- Start Administrator (es gibt sonst niemanden).
    roles = {},

    --- Aenderungsjournal: { { ts, by, action, target, before, after } }
    --- Begrenzt auf JOURNAL_LIMIT Eintraege.
    journal = {},

    --- Spitznamen und Notizen: [guid] = { nickname, note, ts }. Lokal.
    notes = {},

    --- ZEITLICH BEGRENZTE COUNCIL-SITZE: [guid] = { expires, by, ts, name }
    --- Getrennt von `roles`, und das ist der ganze Punkt: Ein Sitz auf Zeit
    --- darf keine dauerhafte Berechtigung hinterlassen. Ein Absturz, ein
    --- Verbindungsabbruch oder ein vergessenes Aufraeumen wuerden sonst
    --- jemanden stillschweigend dauerhaft befoerdern.
    --- Der Sitz endet an der Uhr, nicht an einer Aufraeumroutine, die
    --- vielleicht nie laeuft.
    rotation = {},

    --- Wer in diesem Zyklus schon einen Sitz hatte: [guid] = ts.
    --- Traegt die Fairness: Niemand kommt zweimal, bevor alle einmal dran waren.
    rotationSeen = {},

    --- Verlauf der Rotationen: { { ts, names, by } }
    rotationLog = {},

    --- Abgeschlossene Wurfrunden: { { ts, itemID, min, max, rolls, extra } }
    --- Ein Wurf, den niemand mitgeschrieben hat, ist am naechsten Tag nicht
    --- mehr nachvollziehbar — deshalb wird er aufgehoben.
    rollLog = {},

    --- Laufende Reservierungsrunde: { id, ts, expires, limit, entries }
    --- Eine Runde, nicht eine Liste: Ohne Ablauf wird aus "heute meins"
    --- lautlos "immer meins".
    softResRound = nil,

    --- Von Hand gesetzte Plus-Eins-Ausgleiche: [playerId] = zahl.
    --- Der Zaehler selbst wird gerechnet, nicht gefuehrt — hier steht nur,
    --- was jemand bewusst danebengestellt hat.
    plusOneOffsets = {},

    --- Rosterhistorie: { { ts, kind, name, class, rank, detail } }
    --- guildSeen haelt den letzten bekannten Stand fuer den Vergleich.
    guildLog = {},
    guildSeen = nil,

    --- Gegenstandsverzeichnis: [itemID] = { name, icon, quality, equipLoc, level, ts }
    --- Gefuellt aus allem, was der Client aufloest (siehe Database/ItemIndex.lua).
    --- Traegt die Namenssuche — ein Addon kann Wowhead nicht abfragen.
    items = {},

    --- Was dieser Client tatsaechlich BEOBACHTET hat — im Unterschied zu dem,
    --- was die API verspricht. { lootMethods = { [methode] = ts } }
    measured = { lootMethods = {} },

    --- Gildendaten aus dem Roster, [guid] = { name, rankName, rankIndex, online, lastSeen }
    guild = { name = nil, members = {}, updatedTs = nil },
}

Schema.CHARACTER_DEFAULTS = {
    debug = false,
}

Schema.JOURNAL_LIMIT = 500
Schema.SNAPSHOT_LIMIT_PER_CHARACTER = 60

-- ================================================================== Migration --

--- [n] = function(db)  migriert von Schema n auf n+1.
--- Noch leer — die Kette steht trotzdem.
Schema.MIGRATIONS = {
    -- [1] = function(db) ... end,
}
