--[[----------------------------------------------------------------------------
    LootCouncil/Dkp — Punkte verdienen, Punkte ausgeben.

    Kein UI. Fuehrt ein KONTOBUCH und rechnet daraus Staende.

    DIE ENTSCHEIDUNG, DIE DAS GANZE TRAEGT:

      EIN DKP-STAND IST KEINE ZAHL, SONDERN EINE SUMME.

      Die naheliegende Umsetzung waere ein Guthaben je Spieler, das man
      erhoeht und senkt. Das laeuft frueher oder spaeter von dem weg, was
      wirklich passiert ist: eine Korrektur, ein verpasster Boss, ein
      doppelt gebuchter Abzug — und ab da behauptet die Zahl etwas, das
      niemand mehr nachvollziehen kann. Bei Punkten, um die gestritten
      wird, ist das die schlimmste aller Eigenschaften.

      Hier steht stattdessen JEDE BUCHUNG einzeln im Kontobuch: wann, wie
      viel, wofuer, von wem. Der Stand wird bei jedem Abruf daraus
      gerechnet. Er KANN dem Kontobuch nicht widersprechen, weil er nichts
      anderes ist als das Kontobuch, summiert.

      Wer fragt "warum habe ich nur 40 Punkte", bekommt keine Behauptung,
      sondern eine Liste.

    WAS DAS KOSTET: Bei tausend Buchungen wird jede Abfrage zur Summe ueber
    tausend Zeilen. Deshalb wird das Ergebnis gemerkt und erst verworfen,
    wenn sich das Buch aendert — gerechnet, nicht gefuehrt, aber nicht bei
    jedem Bildaufbau neu.

    GEBUCHT WIRD NUR AUF DEM CLIENT DES PLUENDERMEISTERS. Er fuehrt die
    Sitzung, er vergibt, er bucht ab. Andere Clients bekommen Staende ueber
    den Abgleich — ein Kontobuch, das an zwei Stellen unabhaengig waechst,
    laesst sich nicht wieder zusammenfuehren.
------------------------------------------------------------------------------]]

local _, GA = ...

local Dkp = {}
GA.Modules.Dkp = Dkp

local Util = GA.Core.Util
local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

--- Buchungsarten. Sie stehen im Kontobuch und in der Anzeige.
Dkp.KIND = {
    ATTEND  = "ATTEND",   -- Anwesenheit bei einem Raidabend
    BOSS    = "BOSS",     -- Bosskill
    SPEND   = "SPEND",    -- fuer einen Gegenstand ausgegeben
    ADJUST  = "ADJUST",   -- von Hand, mit Grund
    DECAY   = "DECAY",    -- Verfall
    REFUND  = "REFUND",   -- Rueckbuchung einer Ausgabe
}

local function buch()
    local account = GA.Core.Database.account
    account.dkp = account.dkp or { entries = {} }
    account.dkp.entries = account.dkp.entries or {}
    return account.dkp
end

--- Der gemerkte Stand. Verworfen, sobald gebucht wird.
local cache = nil

local function verwerfen()
    cache = nil
    GA.Core.Callbacks:Fire("DKP_CHANGED")
end

-- ================================================================== Buchen ---

--- Schreibt eine Buchung ins Kontobuch.
---
--- JEDE BUCHUNG BRAUCHT EINEN GRUND. Nicht aus Ordnungsliebe: Eine Zeile
--- ohne Grund ist in drei Wochen nicht mehr zu erklaeren, und bei Punkten
--- endet das in einem Streit, den niemand entscheiden kann.
--- @return table|nil eintrag, string|nil grund
function Dkp:Post(guid, name, points, kind, reason, options)
    options = options or {}

    if not guid or guid == "" then return nil, "noplayer" end
    points = tonumber(points)
    if not points or points == 0 then return nil, "nopoints" end
    if not self.KIND[kind] then return nil, "nokind" end
    if not reason or reason == "" then return nil, "noreason" end

    local by = options.by or Compat.GetPlayerIdentity().guid

    local eintrag = {
        id = Util.NewId("d"),
        ts = options.ts or Util.Now(),
        guid = guid,
        name = name,
        points = points,
        kind = kind,
        reason = reason,
        by = by,
        awardId = options.awardId,
        simulated = options.simulated or nil,
    }

    local b = buch()
    b.entries[#b.entries + 1] = eintrag

    GA.Core.Database:Journal("DKP_POST", eintrag.id, nil,
        string.format("%s %+d %s", tostring(name or guid), points, kind))
    verwerfen()
    return eintrag
end

--- Bucht Punkte ab, wenn das Guthaben reicht.
---
--- DER STAND WIRD VORHER GEPRUEFT, nicht nachher. Ein Konto, das ins Minus
--- laufen darf, macht aus einer Obergrenze eine Empfehlung — und dann
--- bietet jemand mehr, als er hat, und bekommt den Gegenstand.
--- @return table|nil eintrag, string|nil grund
function Dkp:Charge(guid, name, points, reason, options)
    points = tonumber(points)
    if not points or points <= 0 then return nil, "nopoints" end

    if points > self:Balance(guid) then return nil, "insufficient" end

    return self:Post(guid, name, -points, self.KIND.SPEND, reason, options)
end

--- Nimmt eine Ausgabe zurueck.
---
--- ALS EIGENE BUCHUNG, NICHT ALS LOESCHUNG. Wer eine Zeile aus dem
--- Kontobuch entfernt, nimmt dem Spieler die Moeglichkeit zu sehen, was
--- geschehen ist. Eine Rueckbuchung steht daneben und erklaert sich.
function Dkp:Refund(entryId, reason, byGuid)
    local original
    for _, eintrag in ipairs(buch().entries) do
        if eintrag.id == entryId then original = eintrag break end
    end
    if not original then return nil, "unknown" end
    if original.kind ~= self.KIND.SPEND then return nil, "notaspend" end
    if original.refundedBy then return nil, "already" end

    local zurueck = self:Post(original.guid, original.name, -original.points,
        self.KIND.REFUND, reason or "Rueckbuchung", { by = byGuid })
    if not zurueck then return nil, "failed" end

    original.refundedBy = zurueck.id
    zurueck.refunds = original.id
    verwerfen()
    return zurueck
end

-- ================================================================== Lesen ----

--- Rechnet alle Staende aus dem Kontobuch.
local function rechnen()
    if cache then return cache end

    local staende = {}
    for _, eintrag in ipairs(buch().entries) do
        local stand = staende[eintrag.guid]
        if not stand then
            stand = { guid = eintrag.guid, name = eintrag.name,
                      total = 0, earned = 0, spent = 0, entries = 0 }
            staende[eintrag.guid] = stand
        end

        stand.total = stand.total + eintrag.points
        if eintrag.points > 0 then stand.earned = stand.earned + eintrag.points
        else stand.spent = stand.spent - eintrag.points end
        stand.entries = stand.entries + 1
        -- Der zuletzt gesehene Name gewinnt: Umbenennungen sollen nicht
        -- dazu fuehren, dass jemand unter altem Namen in der Liste steht.
        if eintrag.name then stand.name = eintrag.name end
    end

    cache = staende
    return cache
end

--- Der Stand eines Spielers.
function Dkp:Balance(guid)
    if not guid then return 0 end
    local stand = rechnen()[guid]
    return stand and stand.total or 0
end

--- Stand mit Herkunft: verdient, ausgegeben, wie viele Buchungen.
function Dkp:Standing(guid)
    if not guid then return nil end
    return rechnen()[guid]
end

--- Alle Staende, absteigend.
function Dkp:List()
    local out = {}
    for _, stand in pairs(rechnen()) do out[#out + 1] = stand end
    table.sort(out, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

--- Die Buchungen eines Spielers, neueste zuerst.
---
--- DAS IST DIE ANTWORT AUF "WARUM HABE ICH NUR 40 PUNKTE". Ohne sie waere
--- der Stand eine Behauptung.
function Dkp:History(guid, limit)
    local out = {}
    for _, eintrag in ipairs(buch().entries) do
        if not guid or eintrag.guid == guid then out[#out + 1] = eintrag end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)

    if limit and #out > limit then
        for index = #out, limit + 1, -1 do out[index] = nil end
    end
    return out
end

--- Entfernt alle Buchungen eines Probelaufs.
function Dkp:ClearSimulated()
    local b = buch()
    local weg = 0
    for index = #b.entries, 1, -1 do
        if b.entries[index].simulated then
            table.remove(b.entries, index)
            weg = weg + 1
        end
    end
    if weg > 0 then verwerfen() end
    return weg
end

-- ================================================================== Gebote ---

--- Was mindestens geboten werden muss.
function Dkp:MinBid()
    return math.max(0, tonumber(GA.Core.Config:Get("dkpMinBid")) or 1)
end

--- Darf dieser Spieler so viel bieten?
---
--- DREI GRUENDE, UND JEDER SAGT ETWAS ANDERES. "Geht nicht" waere hier
--- besonders aergerlich: Der Bieter sieht seine eigene Zahl und weiss
--- nicht, ob sie zu klein, zu gross oder nicht rund ist.
--- @return boolean, string|nil grund
--- @param verfuegbar number|nil  Was noch frei ist. nil = der ganze Stand.
function Dkp:MayBid(guid, points, verfuegbar)
    points = tonumber(points)
    if not points or points ~= math.floor(points) then return false, "notanumber" end
    if points < self:MinBid() then return false, "toolow" end

    -- OFFENE GEBOTE BINDEN PUNKTE. Wer 500 hat und auf einen Gegenstand
    -- 100 bietet, kann auf die uebrigen zusammen noch 400 bieten — sonst
    -- boete er auf fuenf Stuecke je 500 und koennte eines bezahlen.
    --
    -- Gerechnet wird das in Session:AvailableDkp, denn nur dort ist
    -- bekannt, was in dieser Sitzung offen steht. Hier steht nur die
    -- Schranke.
    local frei = tonumber(verfuegbar) or self:Balance(guid)
    if points > frei then return false, "insufficient" end
    return true
end

function Dkp:OnEnable()
    GA.Core.Callbacks:On("AWARDS_CHANGED", verwerfen, "Dkp")
end
