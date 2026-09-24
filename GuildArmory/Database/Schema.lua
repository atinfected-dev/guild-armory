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

--- Die Wurfstufen fuer Verteilung per Wurf.
---
--- WER MEHR ANSPRUCH HAT, WUERFELT IN EINER GROESSEREN SPANNE. Das ist
--- die uebliche Abmachung: /roll 100 fuer den Hauptskillungsbedarf,
--- /roll 50 fuer die Zweitskillung, /roll 25 fuer die Optik.
---
--- ENTSCHIEDEN WIRD ABER NICHT NACH DER ZAHL, sondern zuerst nach der
--- Stufe. Eine 3 auf 100 schlaegt eine 49 auf 50 — sonst waere die
--- groessere Spanne ein Nachteil, und genau umgekehrt ist sie gemeint.
Schema.RollTiers = {
    { key = "MAIN",     max = 100, label = "Main-Spec" },
    { key = "OFFSPEC",  max = 50,  label = "Off-Spec" },
    { key = "TRANSMOG", max = 25,  label = "Transmog" },
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

        -- ------------------------------------------------ Lootvergabe -----
        -- Diese Schalter entscheiden, WIE eine Gilde verteilt. Sie stehen
        -- beieinander, weil sie zusammen eine Regel ergeben: Wer sie
        -- einzeln verstellt, ohne die anderen zu sehen, bekommt einen
        -- Abend, den niemand erklaeren kann.

        -- WIE VERTEILT WIRD. Drei Arten, eine Einstellung:
        --
        --   COUNCIL  Es wird geboten, das Council stimmt ab.
        --   SOFTRES  Reservierungen entscheiden. Was niemand reserviert
        --            hat, wird verrollt.
        --   ROLL     Es wird verrollt, ohne weitere Regeln.
        --
        -- In ALLEN dreien vergibt am Ende der Plündermeister. Das ist die
        -- Gemeinsamkeit, an der der ganze Aufbau haengt: Ein Wurf ist ein
        -- Gebot mit einer Zahl, eine Reservierung ist ein Gebot mit einem
        -- Anspruch. Der Vergabeweg bleibt derselbe.
        lootMode = "COUNCIL",

        -- Bleibt fuer den Rueckweg: Wer frueher "Council aus" gesetzt hat,
        -- soll nicht ploetzlich wieder abstimmen. Wird beim ersten Lesen
        -- in lootMode uebersetzt.
        councilEnabled = true,

        -- Wer abstimmen darf: "COUNCIL" | "LOOTMASTER" | "ALL".
        -- Voreinstellung COUNCIL — Plündermeister und Admin stehen
        -- darueber und stimmen damit ohnehin mit.
        voteRole = "COUNCIL",

        -- Soft Reserves benutzen. AUS blendet sie ueberall aus, statt eine
        -- leere Liste zu zeigen, die nie jemand fuellt.
        softResEnabled = true,

        -- Plus Eins mitfuehren und anzeigen.
        plusOneEnabled = true,

        -- Welche Antworten den Bietern angeboten werden. nil = alle aus
        -- Schema.DefaultResponses. Eine Gilde ohne Transmog soll den Knopf
        -- nicht sehen muessen.
        activeResponses = nil,

        -- Wie lange eine Sitzung auf Gebote wartet, in Sekunden. 0 = ohne
        -- Uhr; dann schliesst der Plündermeister von Hand.
        bidSeconds = 60,

        -- Beim Oeffnen eines Handels hineinlegen, was diesem Partner
        -- vergeben wurde. STANDARD AN: Es fuellt nur das Fenster — handeln
        -- muessen weiterhin beide Seiten selbst, und bis dahin ist jeder
        -- Schritt zuruecknehmbar. Der Nutzen ist jedes Mal da, der Schaden
        -- nirgends.
        autoTrade = true,

        -- Wurfzeilen einer laufenden Sitzung aus dem EIGENEN Chatfenster
        -- heraushalten. Gewuerfelt wird trotzdem auf dem Server, und alle
        -- anderen sehen die Zeile weiterhin — nachpruefbar bleibt der Wurf.
        -- Was das Fenster ohnehin zeigt, muss den Chat nicht zuschuetten.
        quietRolls = true,

        -- ---------------------------------------------------- Lager -------
        -- Die Lagerleiste mitfuehren.
        --
        -- STANDARD AN, und das ist eine Entscheidung mit einem Preis: Dieser
        -- Client meldet der Gilde dann von allein Zone, Berufe und die
        -- Lagerausbauten im Beutel. Aus gegeben werden waere sauberer — und
        -- die Leiste bliebe fuer immer leer, weil niemand einen Schalter
        -- umlegt fuer etwas, das er noch nie gesehen hat.
        --
        -- Der Ausgleich steht in Camp:NoticeOnce: Beim ersten Versand sagt
        -- das Addon EINMAL im Chat, was hinausgeht und wie man es abstellt.
        campEnabled = true,

        -- Ob dieser Hinweis schon kam.
        campNoticeSeen = false,

        -- ---------------------------------------------------- Karte -------
        -- Die eigene Position laufend an die Gilde melden, und die der
        -- anderen als Nadeln auf der Weltkarte zeigen.
        --
        -- DAS IST DER WEITGEHENDSTE SCHALTER IM GANZEN ADDON. Kartenkennung
        -- und Koordinaten gehen hinaus, solange man online ist; wer das
        -- anlaesst, ist fuer seine Gilde jederzeit auffindbar. Die ZONE
        -- stand ohnehin im Gildenroster — neu sind die Koordinaten darin.
        --
        -- Er wirkt in BEIDE Richtungen: Wer nicht sendet, empfaengt auch
        -- nicht. Eine Karte, auf der man selbst unsichtbar bleibt, waehrend
        -- man alle anderen sieht, waere genau die Unsitte, die man niemandem
        -- zumuten will.
        mapShare = true,

        -- Ob der einmalige Hinweis dazu schon kam.
        mapNoticeSeen = false,


        -- Woher die Wurfzahl kommt: "MASTER" | "CHAT". Siehe
        -- Session:RollSource — es ist Nachpruefbarkeit gegen Ruhe, und die
        -- Voreinstellung ist Ruhe.
        rollSource = "MASTER",

        -- Wer an einer Lootsitzung teilnehmen darf: "GUILD" | "RAID".
        --
        -- GUILD ist die Voreinstellung und die engere: nur
        -- Gildenmitglieder, die auch im Raid stehen. RAID laesst jeden im
        -- Schlachtzug mitbieten, auch Leute von aussen — das ist eine
        -- Entscheidung der Gilde, keine des Addons.
        --
        -- ES GILT NUR FUER DIE SITZUNG. Charaktere, Wunschlisten und
        -- bestaetigte Vergaben bleiben in jedem Fall unter
        -- Gildenmitgliedern; daran aendert diese Einstellung nichts.
        sessionScope = "GUILD",

        -- DKP. Nur wirksam, wenn lootMode auf "DKP" steht.
        --
        -- Das Mindestgebot verhindert Ein-Punkt-Gebote auf alles: Wer
        -- bietet, soll etwas aufgeben. 0 laesst Nullgebote zu.
        -- Elf, nicht eins: Ein Mindestgebot soll etwas bedeuten. Wer auf
        -- alles den kleinsten moeglichen Betrag bietet, hat nichts
        -- abgewogen — und genau das Abwaegen ist der Sinn von Punkten.
        dkpMinBid = 11,
        -- Punkte fuer einen Bosskill und fuer einen Raidabend. Gebucht
        -- wird von Hand oder ueber die Anwesenheit — das Addon bucht
        -- nichts von allein, weil es einen verpassten Boss nicht von einem
        -- nicht stattgefundenen unterscheiden kann.
        dkpPerBoss = 10,
        dkpPerRaid = 20,
        -- Den bisherigen Hoechstbietenden anfluestern, wenn er ueberboten
        -- wurde. OHNE den neuen Betrag — das Gebot bleibt verdeckt.
        dkpOutbidWhisper = true,
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
        -- Neue seltene Funde ungefragt der Gilde anbieten. STANDARD AUS:
        -- Wer einen blauen Guertel fuer seinen Twink aufhebt, will ihn nicht
        -- beworben sehen. Siehe Armory/Tradables.lua.
        offerNewFinds = false,

        -- Combat Log beim Betreten eines Raids selbst einschalten.
        -- STANDARD AUS: Es entsteht eine Datei auf der Festplatte mit den
        -- Namen aller Anwesenden, auch der Nicht-Gildenmitglieder. Das fragt
        -- man, statt es zu tun. Siehe Raids/CombatLog.lua.
        autoCombatLog = false,

        -- Sammlerbetrieb: Der Client laedt regelmaessig neu, damit die
        -- SavedVariables-Datei frisch bleibt. Nur fuer EINEN Client gedacht,
        -- der genau dafuer parkt — siehe Core/Export.lua. Standard AUS.
        collectorMode = false,
        collectorMinutes = 60,
    },

    --- Sprache: "enUS" | "deDE" | "auto".
    ---
    --- ENGLISCH IST DIE GRUNDEINSTELLUNG, nicht die Clientsprache. Der
    --- Forever-Client wechselt sie (deutsch und englisch am selben Tag
    --- beobachtet), und eine Gilde spricht ohnehin nicht die Sprache ihres
    --- Clients. "auto" bleibt als ausdrueckliche Wahl erhalten.
    language = "enUS",

    ui = {
        main = { point = "CENTER", x = 0, y = 0, width = 1000, height = 640,
                 scale = 1.0, lastView = "dashboard" },
        -- Minimap-Knopf: Position als WINKEL, nicht als x/y — sonst wandert er,
        -- sobald jemand die Minimapgroesse aendert.
        minimap = { angle = 200, hidden = false },
        -- Lagerleiste: freischwebend, deshalb Punkt und Versatz wie beim
        -- Hauptfenster. `collapsed` ist die zugeklappte Kopfzeile, `hidden`
        -- der ausdrueckliche Wunsch, sie gar nicht zu sehen — zwei
        -- verschiedene Dinge, die sich sonst gegenseitig ueberschreiben.
        --- `width` ist die gezogene Breite, `height` die gezogene OBERGRENZE
        --- der Hoehe — nicht die Hoehe selbst. Wie viele Zeilen es gibt,
        --- entscheidet die Zone; eine feste Hoehe waere entweder tote
        --- Flaeche oder abgeschnittene Zeilen. `height` fehlt anfangs
        --- absichtlich: Ohne sie richtet sich die Leiste nach ihrem Inhalt,
        --- und das ist die richtige Vorgabe fuer jemanden, der noch nie
        --- gezogen hat.
        camp = { point = "CENTER", x = -320, y = 220, width = 248,
                 hidden = false, collapsed = false },
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

    --- Das DKP-Kontobuch: jede Buchung einzeln, der Stand wird gerechnet.
    --- Siehe LootCouncil/Dkp.lua.
    dkp = { entries = {} },

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

    --- Freigeschaltete Erfolge: [playerId][achievementId] = { ts, evidence, ... }
    --- Nach SPIELER, nicht nach Charakter: Sonst haette derselbe Mensch mit
    --- drei Twinks dreimal "Stufe 60 erreicht".
    achievements = {},

    --- Einmalige Gilden-Firsts: [achievementId] = { playerId, ts, state, claims }
    --- Getrennt, weil dort nicht "habe ich es geschafft" zaehlt, sondern
    --- "war jemand frueher" — eine Frage, die ein Client allein nicht
    --- beantworten kann.
    guildFirsts = {},

    --- Seit wann ueberhaupt gezaehlt wird. Ohne das waere "50 Raids" eine
    --- Aussage ueber das Addon und nicht ueber den Spieler.
    achievementsSince = nil,

    --- AUFGEKLAPPTE Erfolgskategorien: [category] = true.
    ---
    --- Gespeichert wird das Offene, nicht das Geschlossene, und darin steckt
    --- die Grundeinstellung: Leer heisst "alles zu". Beim ersten Oeffnen
    --- stehen dreizehn Kopfzeilen da statt 272 Zeilen.
    ---
    --- Eine Ansichtseinstellung, keine Messung — sie steht hier nur, damit sie
    --- einen Reload ueberlebt, und sie wird nicht ins Journal geschrieben.
    achievementsExpanded = {},

    --- Abgeschlossene Raidabschnitte: { { start, stop, seconds, name, ... } }
    --- Abschnitte statt eines laufenden Zaehlers: Ein Zaehler ueberlebt
    --- keinen Absturz, und niemand weiss danach, ob die Zahl stimmt.
    raidBlocks = {},

    --- Der gerade laufende Abschnitt, oder nil.
    raidOpen = nil,

    --- Rosterhistorie: { { ts, kind, name, class, rank, detail } }
    --- guildSeen haelt den letzten bekannten Stand fuer den Vergleich.
    guildLog = {},
    guildSeen = nil,

    --- Tauschbare Gegenstaende je Charakter: [guid] = { name, ts, sure, items }
    --- Seltene Beutelstuecke, die beim Anlegen binden — eigene und fremde.
    --- Woher sie stammen (Welt, Dungeon, Raid), spielt keine Rolle: Gescannt
    --- wird der Beutel. Siehe Armory/Tradables.lua.
    tradables = {},

    --- Berufe und Rezepte je Charakter:
    ---   [guid] = { name, ts, lines = { [skillLineID] = {
    ---                name, rank, maxRank, items, spells, ts } } }
    ---
    --- `items` und `spells` sind KEINE Tabellen, sondern Zeichenketten:
    --- aufsteigend sortiert, als Differenzen, zur Basis 36. Ein
    --- Hoechstberuf hat gut 300 Rezepte; als Lua-Tabelle waeren das fuer
    --- eine Gilde Zehntausende Eintraege in den SavedVariables, als Text
    --- sind es etwa 500 Zeichen je Beruf. Dieselbe Darstellung geht ueber
    --- die Leitung — es gibt genau einen Kodierer (Professions/Crafting).
    ---
    --- Zwei Listen, weil es zwei Arten Rezept gibt: `items` sind die, die
    --- einen Gegenstand ergeben, `spells` die, die keinen ergeben
    --- (Verzauberungen). Wer nur die erste fuehrt, verliert die
    --- Verzauberkunst vollstaendig.
    crafting = {},

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

    --- Lager: die eigene Sperrzeit als SERVERZEIT.
    ---
    --- Sie steht hier und nicht im Arbeitsspeicher, weil sie eine Stunde
    --- laeuft und ein /reload mitten hinein faellt. Danach behauptete die
    --- Leiste sonst, man duerfe wieder — und der Spielserver saehe das
    --- anders.
    ---
    --- PRO CHARAKTER, weil die Sperre am Charakter haengt und nicht am
    --- Konto. Ein Twink hat seine eigene.
    camp = { cdExpires = 0 },
}

Schema.JOURNAL_LIMIT = 500
Schema.SNAPSHOT_LIMIT_PER_CHARACTER = 60

-- ================================================================== Migration --

--- [n] = function(db)  migriert von Schema n auf n+1.
--- Noch leer — die Kette steht trotzdem.
Schema.MIGRATIONS = {
    -- [1] = function(db) ... end,
}
