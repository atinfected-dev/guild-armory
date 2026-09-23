--[[----------------------------------------------------------------------------
    Camp/Camp — wer in dieser Zone ein Lager bauen kann.

    Kein UI. Misst den eigenen Zustand, verteilt ihn an die Gilde, nimmt den der
    anderen entgegen und stellt daraus die Liste fuer die Leiste zusammen.

    ===========================================================================
    ZWEI EREIGNISSE, DIE MAN LEICHT VERWECHSELT
    ===========================================================================

    Ein LAGERFEUER ist der Platz. Wer eines aufstellt, sagt allen in der Zone,
    WO es steht — die Meldung mit Koordinaten und Kartenpin.

    Eine AUSBAUTE (Amboss, Gewaechshaus, Verbandskasten) stellt man auf ein
    vorhandenes Lagerfeuer. Wer das tut, hat seinen Beitrag fuer diese Stunde
    geleistet und steht bis dahin auf Sperrzeit.

    Beides kommt als UNIT_SPELLCAST_SUCCEEDED herein und unterscheidet sich nur
    an der Zauberkennung. Wer die beiden zusammenwirft, meldet entweder bei
    jedem Amboss einen Kartenpin oder sperrt Leute, die bloss ein Feuer
    angezuendet haben.

    ===========================================================================
    WAS HINAUSGEHT — UND WAS NICHT
    ===========================================================================

    Regelmaessig an die GILDE:
        Zone, gelernte Berufe mit Fertigkeitswert, welche Lagerausbauten im
        Beutel liegen, ob ein Lagerfeuer dabei ist, eigene Sperrzeit,
        Restlaufzeit des Lagerbuffs.

    Einmalig, und nur beim Aufstellen eines LAGERFEUERS:
        Die eigene Position.

    Nicht: der uebrige Beutelinhalt, die Ausruestung, das Ziel, die Gruppe.

    DIE POSITION IST DER HEIKLE TEIL, und sie geht deshalb nur in dem einen
    Augenblick hinaus, in dem sie ohnehin oeffentlich ist: Es steht ein
    Lagerfeuer da, jeder in Sichtweite sieht es. Nicht laufend, nicht auf
    Anfrage, nicht wenn man nur herumsteht.

    Wer gar nichts davon verschicken will, schaltet das Lager in den
    Einstellungen ab. Dann sendet dieser Client nichts mehr — und empfaengt
    auch nichts mehr, denn eine Leiste, die von anderen lebt, waehrend man
    selbst schweigt, waere genau die Unsitte, die man niemandem zumuten will.

    ===========================================================================
    NICHTS DAVON GEHT IN DIE DATENBANK
    ===========================================================================

    Alle fremden Zustaende liegen im Arbeitsspeicher und sind nach dem Ausloggen
    weg. Kein Abgleich, kein Export, keine Wanderung in die Gildendatei. Das ist
    kein Versaeumnis, sondern die Entscheidung: Wo jemand vor zwei Wochen stand,
    geht das Addon nichts an.

    Die einzige Ausnahme steht pro Charakter und ist die EIGENE Sperrzeit — die
    ueberlebt ein /reload, weil sie sonst eine Stunde lang falsch waere.
------------------------------------------------------------------------------]]

local _, GA = ...

local Camp = {}
GA.Modules.Camp = Camp

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Catalog = GA.Data.CampCatalog

--- Sammelfenster fuer den Versand, in Sekunden. Kuerzer als bei den
--- Tauschangeboten: Wer die Zone wechselt, will nicht zehn Sekunden lang
--- unsichtbar sein.
local SETTLE = 4

--- Kuerzester Abstand zwischen zwei eigenen Meldungen.
local MIN_GAP = 8

--- Nach so vielen Sekunden ohne Lebenszeichen wird ein fremder Zustand
--- vergessen. Eine halbe Stunde: lang genug fuer eine Instanz, kurz genug,
--- dass niemand als anwesend gilt, der laengst weg ist.
local STALE = 1800

--- So frisch muss eine Standortmeldung sein, damit sie noch angezeigt wird.
---
--- Nicht als Schutz gedacht — der Absendername kommt vom Server und ist
--- nicht faelschbar. Es geht um Sinn: Ein Lagerfeuer, das vor zehn Minuten
--- gemeldet wurde, ist keine Neuigkeit mehr, und ein Kartenpin darauf
--- schickt jemanden womoeglich zu einem Platz, an dem nichts mehr steht.
local FRESH = 60

--- Streuung fuer Antworten auf eine Anfrage. Ohne sie antworten alle in
--- derselben Zone im selben Augenblick.
local ANSWER_SPREAD = 5

--- Fremde Zustaende, im Arbeitsspeicher. [kurzerName] = Zustand
Camp.states = {}

--- Die zuletzt verschickte Nutzlast. Gleiches wird nicht zweimal gesendet.
Camp.lastPayload = nil
Camp.lastSent = nil

--- Zaehlt, was nicht angenommen wurde. `/ga camp why` nennt es.
Camp.rejected = { width = 0, field = 0, stale = 0, zone = 0, map = 0 }

local pending = false

-- ================================================================== Ablage ---

--- Die eigene Sperrzeit. Pro Charakter, weil sie es ist.
local function ownStore()
    local char = GA.Core.Database and GA.Core.Database.char
    if not char then return { cdExpires = 0 } end
    char.camp = char.camp or { cdExpires = 0 }
    return char.camp
end

function Camp:Enabled()
    return GA.Core.Config:Get("campEnabled") ~= false
end

--- Der eigene Name, so wie er in den Zustaenden steht.
function Camp:OwnName()
    local identity = Compat.GetPlayerIdentity()
    return Util.ShortName(identity and identity.name or "")
end

-- ================================================================== Messen ---

--- Welche Lagerausbauten liegen im Beutel?
---
--- EINE STELLE JE KATALOGEINTRAG, "1" oder "0". Die leere Zeichenkette
--- heisst ausdruecklich WEISS NICHT — dieser Client kann seinen eigenen
--- Beutel nicht zaehlen. Sie ist nicht dasselbe wie lauter Nullen, und die
--- Oberflaeche zeigt sie auch anders an: einmal "hat nichts", einmal
--- "keine Auskunft".
---
--- @return string  Laenge Catalog.WIDTH, oder "" fuer nicht messbar
function Camp:CarriedString()
    local out = {}
    for index = 1, Catalog.WIDTH do
        local item = Catalog.items[index]
        local count = Compat.GetItemCountByID(item.id)
        if count == nil then
            -- Faellt die Zaehlung fuer EINEN Gegenstand aus, faellt sie fuer
            -- alle aus: Es ist immer dieselbe Funktion. Eine halb gefuellte
            -- Zeichenkette waere eine Behauptung ueber den Rest.
            return ""
        end
        out[index] = (count > 0) and "1" or "0"
    end
    return table.concat(out)
end

--- Welches Lagerfeuer traegt dieser Charakter? Das hoechste gewinnt.
--- @return number itemID, oder 0
function Camp:OwnCampfire()
    local best = 0
    for _, itemID in ipairs(Catalog.CAMPFIRES) do
        local count = Compat.GetItemCountByID(itemID)
        if count and count > 0 then best = itemID end
    end
    return best
end

--- Die eigenen Berufe, gefiltert auf die, fuer die es Lagerausbauten gibt.
--- @return table|nil { { line, rank } }  nil = nicht messbar
function Camp:OwnProfessions()
    local lines = Compat.GetProfessionLines()
    if not lines then return nil end

    local out = {}
    for _, entry in ipairs(lines) do
        if Catalog.byLine[entry.line] then
            out[#out + 1] = { line = entry.line, rank = entry.rank or 0 }
        end
    end
    return out
end

--- Der eigene Zustand, frisch gemessen.
function Camp:ScanSelf()
    local buff = Compat.GetPlayerBuff(Catalog.BUFF)
    local store = ownStore()
    local jetzt = Compat.Now()

    -- Eine abgelaufene Sperrzeit ist keine. Aufraeumen statt mitschleppen.
    if (store.cdExpires or 0) <= jetzt then store.cdExpires = 0 end

    local state = {
        name = self:OwnName(),
        zone = Compat.GetZone(),
        carried = self:CarriedString(),
        campfire = self:OwnCampfire(),
        professions = self:OwnProfessions(),
        cdExpires = store.cdExpires or 0,
        buffExpires = buff and buff.expires or 0,
        buffDuration = buff and buff.duration or 0,
        ts = jetzt,
        own = true,
    }

    self.states[state.name] = state
    return state
end

-- ================================================================== Format ---

--- Berufe als "171:300,129:225".
local function encodeProfessions(list)
    if not list then return "" end
    local parts = {}
    for _, entry in ipairs(list) do
        parts[#parts + 1] = string.format("%d:%d", entry.line, math.floor(entry.rank or 0))
    end
    return table.concat(parts, ",")
end

--- @return table|nil  nil = unbrauchbares Feld
local function decodeProfessions(text)
    if type(text) ~= "string" then return nil end
    if text == "" then return {} end

    local out = {}
    for part in string.gmatch(text, "[^,]+") do
        local line, rank = string.match(part, "^(%d+):(%d+)$")
        line, rank = tonumber(line), tonumber(rank)
        if not line or not rank then return nil end
        if rank > 1000 then return nil end
        -- Ein Beruf ohne Lagerausbaute wird still uebergangen, nicht
        -- abgelehnt: Vielleicht kennt die Gegenseite einen Katalogeintrag
        -- mehr als dieser Client.
        if Catalog.byLine[line] then
            out[#out + 1] = { line = line, rank = rank }
        end
    end
    return out
end

--- Prueft eine Beutel-Zeichenkette.
--- @return string|nil
local function checkCarried(text)
    if type(text) ~= "string" then return nil end
    if text == "" then return "" end
    if #text ~= Catalog.WIDTH then return nil end
    if string.match(text, "^[01]+$") ~= text then return nil end
    return text
end

--- Eine Zeitangabe aus einer Nachricht.
---
--- Zeiten sind SERVERZEIT und damit zwischen Clients vergleichbar. Was
--- laengst abgelaufen ist, wird zu 0 — das ist dasselbe wie "keine".
--- @return number|nil  nil = keine brauchbare Zahl
local function checkTime(text, jetzt, maxAhead)
    local wert = tonumber(text)
    if not wert then return nil end
    if wert ~= math.floor(wert) or wert < 0 then return nil end
    if wert > jetzt + maxAhead then return nil end
    if wert <= jetzt then return 0 end
    return wert
end

-- ================================================================== Senden ---

--- Meldet den eigenen Zustand an die Gilde.
--- @return boolean gesendet, string|nil grund
function Camp:Publish(force)
    if not self:Enabled() then return false, "off" end

    local Comm = GA.Core.Comm
    if not Comm or not GA.has.chatInfo then return false, "noapi" end
    if not Compat.IsInGuild() then return false, "noguild" end

    local state = self:ScanSelf()
    if not state.zone then return false, "nozone" end

    local fields = {
        state.zone,
        state.carried,
        state.campfire,
        encodeProfessions(state.professions),
        math.floor(state.cdExpires),
        math.floor(state.buffExpires),
        math.floor(state.buffDuration),
    }

    -- GLEICHES NICHT ZWEIMAL. Ein Raidabend erzeugt Dutzende
    -- Beutelaenderungen, von denen keine einzige das Lager betrifft.
    local payload = table.concat(fields, "\1")
    local jetzt = Compat.Now()
    if not force then
        if payload == self.lastPayload then return false, "same" end
        if self.lastSent and jetzt - self.lastSent < MIN_GAP then
            self:ScheduleSend()
            return false, "tooSoon"
        end
    end

    if not Comm:Send("CAMP", fields, "GUILD", nil, true) then
        return false, "send"
    end

    self.lastPayload, self.lastSent = payload, jetzt
    self:NoticeOnce()
    return true
end

--- Meldet einen Versand an, ohne ihn sofort auszufuehren.
function Camp:ScheduleSend()
    if pending then return end
    pending = true
    Compat.After(SETTLE, function()
        pending = false
        Camp:Publish()
    end)
end

--- EINMAL SAGEN, WAS HINAUSGEHT.
---
--- Diese Leiste beginnt von allein zu senden, sobald das Addon laeuft —
--- anders waere sie leer und bliebe es, weil niemand einen Schalter umlegt
--- fuer etwas, das er noch nie gesehen hat. Wer aber ungefragt etwas ueber
--- sich verschickt, soll es wenigstens ein einziges Mal schwarz auf weiss
--- lesen, mitsamt dem Weg, es abzustellen.
function Camp:NoticeOnce()
    if GA.Core.Config:Get("campNoticeSeen") then return end
    GA.Core.Config:Set("campNoticeSeen", true)
    Debug:Info("%s", GA.L.CAMP_NOTICE)
end

--- Fragt, wer in dieser Zone schon da ist.
function Camp:Request()
    if not self:Enabled() then return false end
    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end

    local zone = Compat.GetZone()
    if not zone then return false end

    return Comm:Send("CREQ", { zone }, "GUILD", nil, true) and true or false
end

-- =============================================================== Empfangen ---

--- Der Zustand eines anderen.
function Camp:OnCamp(sender, fields)
    if not self:Enabled() then return end

    local Comm = GA.Core.Comm
    -- Die eigene Nachricht kommt zurueck. Der gemessene Zustand ist genauer
    -- als der verschickte — den eigenen Eintrag nicht ueberschreiben.
    if Comm and Comm:IsSelf(sender) then return end

    local jetzt = Compat.Now()
    local zone = fields[1]
    if type(zone) ~= "string" or zone == "" or #zone > 64 then
        self.rejected.zone = self.rejected.zone + 1
        return
    end

    local carried = checkCarried(fields[2])
    if carried == nil then
        -- Die haeufigste Ursache ist eine andere Addon-Fassung mit einem
        -- anderen Katalog. Verwerfen ist richtig: Dieselben Stellen
        -- bedeuteten dann etwas anderes.
        self.rejected.width = self.rejected.width + 1
        return
    end

    local campfire = tonumber(fields[3]) or 0
    if campfire ~= 0 and not Catalog.isCampfire[campfire] then
        self.rejected.field = self.rejected.field + 1
        return
    end

    local professions = decodeProfessions(fields[4])
    if not professions then
        self.rejected.field = self.rejected.field + 1
        return
    end

    local cd = checkTime(fields[5], jetzt, Catalog.COOLDOWN + 60)
    local buffExpires = checkTime(fields[6], jetzt, 86400)
    local buffDuration = tonumber(fields[7])
    if cd == nil or buffExpires == nil or type(buffDuration) ~= "number"
        or buffDuration < 0 or buffDuration > 86400 then
        self.rejected.field = self.rejected.field + 1
        return
    end

    local name = Util.ShortName(sender)
    self.states[name] = {
        name = name,
        zone = zone,
        carried = carried,
        campfire = campfire,
        professions = professions,
        cdExpires = cd,
        buffExpires = buffExpires,
        buffDuration = math.floor(buffDuration),
        ts = jetzt,
    }

    GA.Core.Callbacks:Fire("CAMP_CHANGED", name)
end

--- Jemand fragt, wer da ist.
function Camp:OnRequest(sender, fields)
    if not self:Enabled() then return end

    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end

    -- NUR WER IN DERSELBEN ZONE STEHT, ANTWORTET. Sonst antwortet bei jedem
    -- Zonenwechsel die halbe Gilde auf eine Frage, die sie nichts angeht.
    local zone = Compat.GetZone()
    if not zone or fields[1] ~= zone then return end

    -- Gestreut, damit nicht alle im selben Augenblick senden.
    local delay = 0.5 + (math.random() * ANSWER_SPREAD)
    Compat.After(delay, function()
        Camp:Publish(true)
    end)
end

-- ============================================================= Aufstellen ----

--- Zauberkennung -> was dort aufgestellt wurde.
--- Wird beim ersten Bedarf gebaut: Vorher sind die Gegenstaende meist noch
--- nicht im Client geladen und GetItemSpell liefert nichts.
function Camp:UseSpells()
    self.spells = self.spells or {}
    self.spellsComplete = true

    for _, itemID in ipairs(Catalog.CAMPFIRES) do
        local spellID = Compat.GetItemSpell(itemID)
        if spellID then self.spells[spellID] = { kind = "CAMPFIRE", itemID = itemID }
        else self.spellsComplete = false end
    end

    for _, item in ipairs(Catalog.items) do
        local spellID = Compat.GetItemSpell(item.id)
        if spellID then self.spells[spellID] = { kind = "UPGRADE", itemID = item.id }
        else self.spellsComplete = false end
    end

    return self.spells
end

--- Der eigene Charakter hat etwas gewirkt.
--- @return string|nil  was erkannt wurde: "CAMPFIRE" | "UPGRADE"
function Camp:OnCast(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end

    local hit = self:UseSpells()[spellID]
    if not hit then return nil end

    if hit.kind == "CAMPFIRE" then
        self:AnnouncePlacement(hit.itemID)
        return "CAMPFIRE"
    end

    -- EINE AUSBAUTE GESTELLT — die Stunde laeuft.
    ownStore().cdExpires = Compat.Now() + Catalog.COOLDOWN
    self:Publish(true)
    GA.Core.Callbacks:Fire("CAMP_CHANGED", self:OwnName())
    return "UPGRADE"
end

--- Sagt der Zone, wo das Lagerfeuer steht.
--- @return boolean gesendet, string|nil grund
function Camp:AnnouncePlacement(itemID)
    if not self:Enabled() then return false, "off" end

    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false, "noguild" end

    local zone = Compat.GetZone()
    if not zone then return false, "nozone" end

    local mapID, x, y = Compat.GetMapPosition()
    if not mapID then
        -- OHNE POSITION KEINE MELDUNG. "Irgendwo in den Barrens" schickt
        -- Leute los, ohne ihnen zu sagen wohin.
        Debug:Print("camp", "Lagerfeuer aufgestellt, aber keine Position messbar.")
        return false, "nopos"
    end

    -- Nicht gebuendelt: Die Meldung ist nur fuer eine Minute etwas wert.
    return Comm:Send("CPLACE", {
        zone, mapID,
        math.floor(x * 10000 + 0.5),
        math.floor(y * 10000 + 0.5),
        itemID, math.floor(Compat.Now()),
    }, "GUILD", nil, false)
end

--- Jemand hat ein Lagerfeuer aufgestellt.
function Camp:OnPlaced(sender, fields)
    if not self:Enabled() then return end

    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end

    local zone = Compat.GetZone()
    if not zone or fields[1] ~= zone then
        -- Was in einer anderen Zone steht, kann man nicht erreichen und auf
        -- der eigenen Karte auch nicht anzeigen.
        self.rejected.zone = self.rejected.zone + 1
        return
    end

    local mapID = tonumber(fields[2])
    if not mapID or mapID <= 0 or mapID ~= math.floor(mapID) or not Compat.MapExists(mapID) then
        self.rejected.map = self.rejected.map + 1
        return
    end

    local x, y = tonumber(fields[3]), tonumber(fields[4])
    if not x or not y or x ~= math.floor(x) or y ~= math.floor(y)
        or x < 0 or x > 10000 or y < 0 or y > 10000 then
        self.rejected.field = self.rejected.field + 1
        return
    end

    local itemID = tonumber(fields[5])
    if not itemID or not Catalog.isCampfire[itemID] then
        self.rejected.field = self.rejected.field + 1
        return
    end

    local stamp = tonumber(fields[6])
    if not stamp or math.abs(Compat.Now() - stamp) > FRESH then
        self.rejected.stale = self.rejected.stale + 1
        return
    end

    GA.Core.Callbacks:Fire("CAMP_PLACED", {
        name = Util.ShortName(sender),
        zone = zone,
        mapID = mapID,
        x = x / 10000,
        y = y / 10000,
        itemID = itemID,
        ts = stamp,
    })
end

-- ================================================================== Liste ----

--- Die vier Spalten fuer einen Zustand.
---
--- Spalte 1 und 2 sind die Hauptberufe in der Reihenfolge des Clients,
--- Spalte 3 ist Erste Hilfe, Spalte 4 Angeln. Feste Plaetze fuer die beiden,
--- weil sonst in jeder Zeile etwas anderes an derselben Stelle staende.
--- @return table { [1..4] = slot }
function Camp:SlotsFor(state)
    local slots = {}
    for index = 1, 4 do slots[index] = { empty = true } end
    if not state or not state.professions then return slots end

    local carried = state.carried
    local known = (carried ~= nil and carried ~= "")
    local naechsterHaupt = 1

    for _, entry in ipairs(state.professions) do
        local profession = Catalog.byLine[entry.line]
        if profession then
            local spalte
            if profession.kind == "FIRSTAID" then spalte = 3
            elseif profession.kind == "FISHING" then spalte = 4
            elseif naechsterHaupt <= 2 then
                spalte = naechsterHaupt
                naechsterHaupt = naechsterHaupt + 1
            end

            if spalte and slots[spalte].empty then
                local tier = Catalog.TierFor(entry.rank)
                local slot = {
                    empty = false,
                    key = profession.key,
                    line = entry.line,
                    rank = entry.rank,
                    icon = profession.icon,
                    tier = tier,
                    known = known,
                    bestTier = 0,
                    carried = {},
                }

                -- NICHT `known and false or nil`. Das ergibt IMMER nil —
                -- `true and false` ist false, und `false or nil` ist nil.
                -- Damit war der ganze Unterschied zwischen "hat nichts" und
                -- "keine Auskunft" weg, und zwar zur unsicheren Seite hin:
                -- Jeder sah aus wie jemand, ueber den man nichts weiss.
                if known then
                    slot.hasItem, slot.hasUsable = false, false
                end

                for _, item in ipairs(profession.items) do
                    local traegt = nil
                    if known then
                        traegt = string.sub(carried, item.index, item.index) == "1"
                    end
                    local benutzbar = traegt and (tier >= item.tier) or false
                    if traegt then
                        slot.hasItem = true
                        if benutzbar then
                            slot.hasUsable = true
                            if item.tier > slot.bestTier then slot.bestTier = item.tier end
                        end
                    end
                    slot.carried[#slot.carried + 1] = {
                        id = item.id, tier = item.tier,
                        held = traegt, usable = benutzbar,
                    }
                end

                slots[spalte] = slot
            end
        end
    end

    return slots
end

--- Vergisst, was zu lange her ist.
function Camp:Prune()
    local jetzt = Compat.Now()
    for name, state in pairs(self.states) do
        if not state.own and (jetzt - (state.ts or 0)) > STALE then
            self.states[name] = nil
        end
    end
end

--- Alle Gildenmitglieder in der eigenen Zone.
---
--- @return table rows, table summary { total, ready, known }
function Camp:Roster()
    self:Prune()

    local zone = Compat.GetZone()
    local rows, summary = {}, { total = 0, ready = 0, known = 0, zone = zone }
    if not zone then return rows, summary end

    local eigen = self:ScanSelf()
    local eigenName = eigen.name
    local jetzt = Compat.Now()

    local function zeile(name, class, state, istSelbst)
        local cd = (state and state.cdExpires or 0)
        if cd <= jetzt then cd = 0 end
        local buff = (state and state.buffExpires or 0)
        if buff <= jetzt then buff = 0 end

        local row = {
            name = name,
            class = class,
            own = istSelbst or false,
            known = state ~= nil,
            campfire = state and state.campfire or 0,
            cdExpires = cd,
            onCooldown = cd > 0,
            buffExpires = buff,
            buffDuration = state and state.buffDuration or 0,
            hasBuff = buff > 0,
            slots = self:SlotsFor(state),
        }
        row.icon = (row.campfire > 0) and Compat.GetItemIcon(row.campfire) or nil
        rows[#rows + 1] = row

        summary.total = summary.total + 1
        if row.known then summary.known = summary.known + 1 end
        if not row.onCooldown then summary.ready = summary.ready + 1 end
    end

    if not Compat.IsInGuild() then
        zeile(eigenName, (Compat.GetPlayerIdentity() or {}).class, eigen, true)
        return rows, summary
    end

    local total = Compat.GetNumGuildMembers()
    for index = 1, total do
        local member = Compat.GetGuildMember(index)
        if member and member.online and member.name then
            local name = Util.ShortName(member.name)
            local state = self.states[name]

            -- DIE ZONE AUS DER NACHRICHT SCHLAEGT DIE AUS DEM ROSTER. Das
            -- Gildenroster wird in Abstaenden aktualisiert; wer gerade die
            -- Zone gewechselt hat, steht dort noch am alten Ort. Die eigene
            -- Zone weiss dieser Client ohnehin genauer als jede Liste.
            local memberZone = (name == eigenName) and zone
                or (state and state.zone)
                or member.zone

            if memberZone == zone then
                zeile(name, member.class, state, name == eigenName)
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.own ~= b.own then return a.own end
        return a.name < b.name
    end)

    return rows, summary
end

-- ================================================================ Diagnose ---

--- Was dieser Client aus dem Katalog macht.
---
--- "Geht nicht" laesst sich nicht reparieren. Diese Ausgabe macht daraus
--- eine Liste von Werten, von denen einer nein sagt.
--- @return table Zeilen
function Camp:Explain()
    local zeilen = {}
    local function sag(text, ...)
        zeilen[#zeilen + 1] = select("#", ...) > 0 and string.format(text, ...) or text
    end

    local zone = Compat.GetZone()
    local mapID, x, y = Compat.GetMapPosition()
    local lines = Compat.GetProfessionLines()
    local buff = Compat.GetPlayerBuff(Catalog.BUFF)

    sag(GA.L.CAMP_WHY_ENABLED, self:Enabled() and GA.L.SLASH_ON or GA.L.SLASH_OFF)
    sag(GA.L.CAMP_WHY_ZONE, zone or GA.L.UNKNOWN)
    sag(GA.L.CAMP_WHY_POSITION, mapID and string.format("%d  %.1f / %.1f",
        mapID, (x or 0) * 100, (y or 0) * 100) or GA.L.UNKNOWN)
    sag(GA.L.CAMP_WHY_WAYPOINT, mapID and Compat.CanSetWaypoint(mapID)
        and GA.L.SLASH_ON or GA.L.SLASH_OFF)
    sag(GA.L.CAMP_WHY_BUFF, buff and string.format("%ds", math.max(0,
        buff.expires - Compat.Now())) or GA.L.CAMP_WHY_NOBUFF)

    if not lines then
        sag(GA.L.CAMP_WHY_NOPROF)
    else
        for _, entry in ipairs(lines) do
            local profession = Catalog.byLine[entry.line]
            sag("  %s %d — %s", tostring(entry.name or entry.line), entry.rank or 0,
                profession and profession.key or GA.L.CAMP_WHY_NOCAMP)
        end
    end

    -- Der Kern der Sache: Was macht dieser Client aus den Kennungen?
    local bekannt, gesamt, getragen = 0, 0, 0
    local counting = Compat.GetItemCountByID(Catalog.items[1].id) ~= nil
    for _, item in ipairs(Catalog.items) do
        gesamt = gesamt + 1
        local info = Compat.GetItemInfo(item.id)
        if info and info.name then bekannt = bekannt + 1 end
        local count = Compat.GetItemCountByID(item.id)
        if count and count > 0 then getragen = getragen + 1 end
    end
    sag(GA.L.CAMP_WHY_ITEMS, bekannt, gesamt)
    sag(GA.L.CAMP_WHY_COUNT, counting and GA.L.SLASH_ON or GA.L.SLASH_OFF, getragen)

    local spells, zauber = self:UseSpells(), 0
    for _ in pairs(spells) do zauber = zauber + 1 end
    sag(GA.L.CAMP_WHY_SPELLS, zauber, gesamt + #Catalog.CAMPFIRES)

    local _, summary = self:Roster()
    sag(GA.L.CAMP_WHY_ROSTER, summary.total, summary.known)
    sag(GA.L.CAMP_WHY_REJECTED, self.rejected.width, self.rejected.field,
        self.rejected.zone + self.rejected.map, self.rejected.stale)

    return zeilen
end

-- ================================================================== Start ----

function Camp:OnEnable()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:On("CAMP", function(sender, fields) Camp:OnCamp(sender, fields) end, "Camp")
        Comm:On("CREQ", function(sender, fields) Camp:OnRequest(sender, fields) end, "Camp")
        Comm:On("CPLACE", function(sender, fields) Camp:OnPlaced(sender, fields) end, "Camp")
    end

    -- Die Gegenstaende laden, damit Name, Symbol und Benutzen-Zauber da
    -- sind, bevor jemand danach fragt.
    for _, itemID in ipairs(Catalog.CAMPFIRES) do Compat.RequestItemData(itemID) end
    for _, item in ipairs(Catalog.items) do Compat.RequestItemData(item.id) end

    GA.Core.Events:Register("BAG_UPDATE_DELAYED", function()
        Camp:ScheduleSend()
    end, "Camp")

    -- Zonenwechsel: sofort melden und fragen, wer schon da ist. Die Zone
    -- steht in jeder Nachricht, also aendert sich die Nutzlast ohnehin.
    local function zonenwechsel()
        Camp:Publish(true)
        Camp:Request()
        GA.Core.Callbacks:Fire("CAMP_CHANGED")
    end
    GA.Core.Events:Register("ZONE_CHANGED_NEW_AREA", zonenwechsel, "Camp")
    GA.Core.Events:Register("ZONE_CHANGED", zonenwechsel, "Camp")
    GA.Core.Events:Register("ZONE_CHANGED_INDOORS", zonenwechsel, "Camp")

    -- NUR WENN SICH DER LAGERBUFF GEAENDERT HAT.
    --
    -- UNIT_AURA feuert im Kampf im Sekundentakt — jeder Tick, jeder Stapel,
    -- jedes auslaufende Gift. Ein Versand pro Ereignis anzumelden hiesse,
    -- alle vier Sekunden den ganzen Katalog durch den Beutel zu zaehlen,
    -- und das den ganzen Abend, auch bei zugeklappter Leiste.
    --
    -- Geprueft wird deshalb zuerst das Einzige, was diese Leiste an einer
    -- Aura interessiert: die Ablaufzeit des Lagerbuffs.
    GA.Core.Events:Register("UNIT_AURA", function(_, unit)
        if unit ~= "player" then return end
        local buff = Compat.GetPlayerBuff(Catalog.BUFF)
        local expires = buff and buff.expires or 0
        if expires == Camp.lastBuffExpires then return end
        Camp.lastBuffExpires = expires
        Camp:ScheduleSend()
    end, "Camp")

    GA.Core.Events:Register("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if unit ~= "player" then return end
        Camp:OnCast(spellID)
    end, "Camp")

    GA.Core.Events:Register("GUILD_ROSTER_UPDATE", function()
        GA.Core.Callbacks:Fire("CAMP_CHANGED")
    end, "Camp")

    -- Nach dem Anmelden einmal melden und fragen. Nicht sofort: Beutel,
    -- Berufe und Gildenroster stehen in den ersten Sekunden noch nicht.
    Compat.After(10, function()
        Camp:Publish(true)
        Camp:Request()
    end)
end
