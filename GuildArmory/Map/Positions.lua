--[[----------------------------------------------------------------------------
    Map/Positions — wer steht gerade wo.

    Kein UI. Meldet die eigene Position an die Gilde, nimmt die der anderen
    entgegen und haelt sie bereit fuer die Nadeln auf der Weltkarte.

    ===========================================================================
    "LAUFEND" HEISST NICHT "STAENDIG"
    ===========================================================================

    Eine Gilde mit fuenfzig Leuten online, jeder sendet alle zehn Sekunden:
    Das sind fuenf Nachrichten je Sekunde auf einem Kanal, der auch den
    Abgleich, die Lootsitzung und die Lagerleiste traegt. Es wuerde
    funktionieren und alles andere langsamer machen.

    Deshalb sendet dieser Client nur dann, wenn es etwas Neues zu sagen gibt:

      * BEWEGUNG. Wer sich nicht weiter als MIN_MOVE bewegt hat, schweigt.
        Die halbe Gilde steht am Auktionshaus — von dort kommt nach der
        ersten Meldung nichts mehr.
      * ABSTAND. Zwischen zwei eigenen Meldungen liegen mindestens
        MIN_INTERVAL Sekunden, egal wie schnell jemand reitet.
      * LEBENSZEICHEN. Alle HEARTBEAT Sekunden einmal, auch im Stehen —
        sonst wuesste niemand, der spaeter einloggt, wo die Stehenden sind.
      * AUF ANFRAGE. Wer die Weltkarte aufzieht, fragt einmal. Alle
        antworten gestreut. Das holt frische Daten genau dann, wenn sie
        jemand ansieht, statt sie rund um die Uhr zu verteilen.

    ===========================================================================
    WAS DAS UEBER DICH VERRAET
    ===========================================================================

    Kartenkennung und Koordinaten, an die ganze Gilde, solange du online bist.
    Das ist mehr als alles andere in diesem Addon und laesst sich nicht
    beschoenigen: Wer es anlaesst, ist fuer seine Gilde jederzeit auffindbar.

    Der Schalter dafuer steht in den Einstellungen und wirkt sofort in beide
    Richtungen — wer nicht sendet, empfaengt auch nicht. Eine Karte, auf der
    man selbst unsichtbar bleibt, waehrend man alle anderen sieht, waere genau
    die Unsitte, die man niemandem zumuten will.

    Die ZONE stand ohnehin schon im Gildenroster, fuer jeden sichtbar. Neu
    sind die Koordinaten darin.

    ===========================================================================
    NICHTS DAVON GEHT IN DIE DATENBANK
    ===========================================================================

    Alle fremden Positionen liegen im Arbeitsspeicher und sind nach dem
    Ausloggen weg. Kein Abgleich, kein Export. Wo jemand gestern stand, geht
    das Addon nichts an — und ein Bewegungsprotokoll erst recht nicht.
------------------------------------------------------------------------------]]

local _, GA = ...

local Positions = {}
GA.Modules.Positions = Positions

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Kuerzester Abstand zwischen zwei eigenen Meldungen, in Sekunden.
---
--- Von 8 auf 15 erhoeht. Eine Karte, auf der eine Nadel bis zu fuenfzehn
--- Sekunden nachhinkt, ist immer noch brauchbar — sie sagt, in welcher Ecke
--- der Zone jemand steckt, und dafuer war sie gedacht. Die Haelfte der
--- Nachrichten dagegen ist die Haelfte.
local MIN_INTERVAL = 15

--- Ab welcher Bewegung es sich zu melden lohnt, in Kartenanteilen.
--- 0,006 sind bei einer grossen Zone gut dreissig Schritte — nah genug, dass
--- die Nadel nicht springt, weit genug, dass Herumstehen still bleibt.
local MIN_MOVE = 0.006

--- Auch ohne Bewegung so oft ein Lebenszeichen.
local HEARTBEAT = 300

--- Nach so langer Stille gilt eine Position als veraltet und verschwindet.
--- Fuenf Minuten: Eine Nadel, die eine halbe Stunde alt ist, schickt
--- jemanden an einen Ort, an dem niemand mehr steht.
local STALE = 300

--- Streuung fuer Antworten auf eine Anfrage.
local ANSWER_SPREAD = 6

--- Kuerzester Abstand zwischen zwei eigenen Anfragen.
local REQUEST_COOLDOWN = 30

--- Wie oft der Takt nachsieht, ob sich etwas bewegt hat.
---
--- Von 2 auf 3 erhoeht. Publish sendet ohnehin hoechstens alle
--- MIN_INTERVAL Sekunden — haeufiger nachzusehen heisst nur, haeufiger
--- "nein" zu sagen.
local TICK = 3

--- Wartezeit nach dem Anmelden, bevor der Takt anlaeuft.
local START_DELAY = 15

--- So lange gilt die Namensliste aus dem Gildenroster als frisch genug.
--- Klasse und Rang aendern sich im Monatstakt, nicht im Sekundentakt.
local ROSTER_TTL = 30

--- [kurzerName] = { mapID, x, y, ts }
Positions.states = {}

Positions.rejected = { field = 0, map = 0 }

function Positions:Enabled()
    return GA.Core.Config:Get("mapShare") ~= false
end

function Positions:OwnName()
    local identity = Compat.GetPlayerIdentity()
    return Util.ShortName(identity and identity.name or "")
end

-- ================================================================== Senden ---

--- Meldet die eigene Position, falls es etwas zu melden gibt.
--- @param force boolean  auch ohne Bewegung senden (Anfrage, Lebenszeichen)
--- @return boolean gesendet, string|nil grund
function Positions:Publish(force)
    if not self:Enabled() then return false, "off" end

    local Comm = GA.Core.Comm
    if not Comm or not GA.has.chatInfo then return false, "noapi" end
    if not Compat.IsInGuild() then return false, "noguild" end

    local mapID, x, y = Compat.GetMapPosition()
    if not mapID then return false, "nopos" end

    local jetzt = Compat.Now()
    local zuletzt = self.lastSent

    if not force then
        if zuletzt and jetzt - zuletzt < MIN_INTERVAL then return false, "tooSoon" end

        -- NUR BEI BEWEGUNG. Der Grund, warum eine grosse Gilde diesen Kanal
        -- nicht erstickt: Wer steht, sendet nicht.
        local alt = self.lastOwn
        if alt and alt.mapID == mapID then
            local dx, dy = x - alt.x, y - alt.y
            local weit = (dx * dx + dy * dy) >= (MIN_MOVE * MIN_MOVE)
            local faellig = (jetzt - (zuletzt or 0)) >= HEARTBEAT
            if not weit and not faellig then return false, "still" end
        end
    end

    local ok = Comm:Send("GPOS", {
        mapID,
        math.floor(x * 10000 + 0.5),
        math.floor(y * 10000 + 0.5),
    }, "GUILD", nil, true)
    if not ok then return false, "send" end

    self.lastSent = jetzt
    self.lastOwn = { mapID = mapID, x = x, y = y }
    self:NoticeOnce()

    -- Der eigene Eintrag kommt aus der Messung, nicht aus der eigenen
    -- Nachricht: genauer und ohne Rundung auf Zehntausendstel.
    self.states[self:OwnName()] = { mapID = mapID, x = x, y = y, ts = jetzt, own = true }
    return true
end

--- EINMAL SAGEN, WAS HINAUSGEHT.
---
--- Diese Karte ist an, sobald das Addon laeuft — anders bliebe sie leer und
--- niemand legte je den Schalter um fuer etwas, das er noch nie gesehen hat.
--- Wer aber ungefragt seine Koordinaten verschickt, soll das wenigstens ein
--- einziges Mal schwarz auf weiss lesen, mitsamt dem Weg, es abzustellen.
---
--- Es steht hier und nicht in den Einstellungen: Dort liest es nur, wer
--- ohnehin schon hinsieht.
function Positions:NoticeOnce()
    if GA.Core.Config:Get("mapNoticeSeen") then return end
    GA.Core.Config:Set("mapNoticeSeen", true)
    Debug:Info("%s", GA.L.MAP_NOTICE)
end

--- Fragt, wer gerade wo steht. Beim Aufziehen der Weltkarte.
function Positions:Request()
    if not self:Enabled() then return false end

    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end

    local jetzt = Compat.Now()
    if self.lastRequest and jetzt - self.lastRequest < REQUEST_COOLDOWN then
        return false
    end
    self.lastRequest = jetzt

    return Comm:Send("GMREQ", {}, "GUILD", nil, true) and true or false
end

-- =============================================================== Empfangen ---

function Positions:OnPosition(sender, fields)
    if not self:Enabled() then return end

    local Comm = GA.Core.Comm
    -- Die eigene Nachricht kommt zurueck. Der gemessene Wert ist genauer.
    if Comm and Comm:IsSelf(sender) then return end

    local mapID = tonumber(fields[1])
    if not mapID or mapID <= 0 or mapID ~= math.floor(mapID)
        or not Compat.MapExists(mapID) then
        self.rejected.map = self.rejected.map + 1
        return
    end

    local x, y = tonumber(fields[2]), tonumber(fields[3])
    if not x or not y or x ~= math.floor(x) or y ~= math.floor(y)
        or x < 0 or x > 10000 or y < 0 or y > 10000 then
        self.rejected.field = self.rejected.field + 1
        return
    end

    local name = Util.ShortName(sender)
    self.states[name] = {
        mapID = mapID, x = x / 10000, y = y / 10000, ts = Compat.Now(),
    }

    GA.Core.Callbacks:Fire("POSITIONS_CHANGED", name)
end

function Positions:OnRequest(sender)
    if not self:Enabled() then return end

    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end

    -- Gestreut: Ohne das antwortet die halbe Gilde in derselben Zehntelsekunde.
    Compat.After(0.5 + math.random() * ANSWER_SPREAD, function()
        Positions:Publish(true)
    end)
end

-- ================================================================== Lesen ----

--- Vergisst, was zu lange her ist.
function Positions:Prune()
    local jetzt = Compat.Now()
    for name, state in pairs(self.states) do
        if (jetzt - (state.ts or 0)) > STALE then self.states[name] = nil end
    end
end

--- Klasse und Rang je Name, aus dem Gildenroster.
---
--- GEMERKT, NICHT BEI JEDEM ZEICHNEN NEU GEBAUT.
---
--- Diese beiden Tabellen entstanden frueher in jedem Aufruf von All() — und
--- All() laeuft zweimal je Sekunde, solange die Weltkarte offen ist. Bei
--- zweihundert Gildenmitgliedern sind das vierhundert Tabelleneintraege je
--- Aufruf, achthundert je Sekunde, fuer Daten, die sich im Minutentakt
--- aendern.
---
--- Das bleibt nicht liegen — Lua raeumt es weg —, aber WoWs Speicheranzeige
--- je Addon zaehlt das ANGEFORDERTE. Genau so kommen 18 MB zustande, ohne
--- dass ein Byte haengenbleibt.
---
--- Was der Server ohnehin liefert, muss niemand verschicken; was sich kaum
--- aendert, muss niemand staendig neu bauen.
function Positions:RosterLookup()
    local jetzt = Compat.Now()
    if self.rosterAt and (jetzt - self.rosterAt) < ROSTER_TTL then
        return self.rosterClass, self.rosterRank
    end

    local klassen, raenge = {}, {}
    for index = 1, Compat.GetNumGuildMembers() do
        local member = Compat.GetGuildMember(index)
        if member and member.name then
            local kurz = Util.ShortName(member.name)
            klassen[kurz] = member.class
            raenge[kurz] = member.rankName
        end
    end

    self.rosterClass, self.rosterRank, self.rosterAt = klassen, raenge, jetzt
    return klassen, raenge
end

--- ALLE bekannten Positionen, ohne Rücksicht auf die Karte.
---
--- Die Auswahl trifft die Anzeige, nicht dieses Modul: Sie weiss, welche
--- Karte gerade offen ist, und kann eine Zonenposition auf die
--- Kontinentkarte umrechnen. Wer hier filtert, nimmt ihr die Moeglichkeit —
--- und genau daran lag es, dass die Kontinentkarte leer blieb.
---
--- @return table { { name, class, rank, mapID, x, y, ts, own } }
function Positions:All()
    self:Prune()

    local out = {}
    if not self:Enabled() then return out end

    local klassen, raenge = self:RosterLookup()

    for name, state in pairs(self.states) do
        out[#out + 1] = {
            name = name,
            class = klassen[name],
            rank = raenge[name],
            mapID = state.mapID,
            x = state.x, y = state.y,
            ts = state.ts,
            own = state.own or false,
        }
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--- Nur die auf DIESER Karte. Fuer `/ga map` und die Tests.
--- @return table
function Positions:OnMap(mapID)
    mapID = tonumber(mapID)
    local out = {}
    if not mapID then return out end

    for _, entry in ipairs(self:All()) do
        if entry.mapID == mapID then out[#out + 1] = entry end
    end
    return out
end

--- Zahlen fuer `/ga map`.
function Positions:Stats()
    self:Prune()
    local anzahl, karten = 0, {}
    for _, state in pairs(self.states) do
        anzahl = anzahl + 1
        karten[state.mapID] = true
    end
    local kartenzahl = 0
    for _ in pairs(karten) do kartenzahl = kartenzahl + 1 end
    return anzahl, kartenzahl
end

--- Was dieser Client wirklich kann.
function Positions:Explain()
    local zeilen = {}
    local function sag(text, ...)
        zeilen[#zeilen + 1] = select("#", ...) > 0 and string.format(text, ...) or text
    end

    local mapID, x, y = Compat.GetMapPosition()
    local canvas = Compat.GetMapCanvas()
    local angezeigt = Compat.GetDisplayedMapID()
    local anzahl, karten = self:Stats()

    sag(GA.L.MAP_WHY_SHARE, self:Enabled() and GA.L.SLASH_ON or GA.L.SLASH_OFF)
    sag(GA.L.MAP_WHY_OWN, mapID and string.format("%d  %.1f / %.1f",
        mapID, (x or 0) * 100, (y or 0) * 100) or GA.L.UNKNOWN)
    sag(GA.L.MAP_WHY_CANVAS, canvas and GA.L.SLASH_ON or GA.L.SLASH_OFF)
    sag(GA.L.MAP_WHY_SHOWN, angezeigt and tostring(angezeigt) or GA.L.UNKNOWN)
    sag(GA.L.MAP_WHY_KNOWN, anzahl, karten)
    sag(GA.L.MAP_WHY_REJECTED, self.rejected.map, self.rejected.field)
    return zeilen
end

-- ================================================================== Start ----

function Positions:OnEnable()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:On("GPOS", function(sender, fields) Positions:OnPosition(sender, fields) end,
            "Positions")
        Comm:On("GMREQ", function(sender) Positions:OnRequest(sender) end, "Positions")
    end

    -- EIN TAKT, NICHT EIN EREIGNIS JE SCHRITT. Es gibt kein Ereignis fuer
    -- "der Spieler hat sich bewegt". Nachgesehen wird in Abstaenden; Publish
    -- entscheidet dann selbst, ob es etwas zu senden gibt.
    --
    -- EIN RAHMEN, KEINE KETTE VON ZEITGEBERN.
    --
    -- Hier stand `Compat.After(2, takt)` und darin wieder dasselbe — eine
    -- Kette, die alle zwei Sekunden einen neuen Zeitgeber samt Abschluss
    -- anlegt, den ganzen Abend. Nichts davon bleibt liegen, aber WoWs
    -- Speicheranzeige je Addon zaehlt das ANGEFORDERTE, und so kommen
    -- zweistellige Megabyte zustande, ohne dass ein Byte haengenbleibt.
    --
    -- Ein Rahmen mit OnUpdate legt nichts an: Er zaehlt nur die Zeit
    -- zusammen und ruft alle TICK Sekunden einmal.
    local takt = CreateFrame("Frame")
    local seit, gestartet = 0, 0
    takt:SetScript("OnUpdate", function(_, delta)
        -- Die ersten Sekunden nach dem Anmelden stehen Beutel, Karte und
        -- Roster noch nicht.
        if gestartet < START_DELAY then gestartet = gestartet + delta return end

        seit = seit + delta
        if seit < TICK then return end
        seit = 0
        Positions:Publish()
    end)

    GA.Core.Events:Register("ZONE_CHANGED_NEW_AREA", function()
        Positions:Publish(true)
    end, "Positions")
end
