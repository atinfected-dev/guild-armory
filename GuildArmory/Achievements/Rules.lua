--[[----------------------------------------------------------------------------
    Achievements/Rules — wann ein Erfolg auslöst.

    Kein UI. Getrennt vom Katalog, weil der aus dem Dokument erneuert wird und
    diese Datei von Hand gepflegt ist.

    ===========================================================================
    DIE ENTSCHEIDUNG, DIE DIESE DATEI PRAEGT
    ===========================================================================

    EIN ERFOLG OHNE DATENQUELLE IST "NOCH NICHT MESSBAR" — NICHT "0 VON 50".

    Von 272 Erfolgen sind 52 direkt messbar, und selbst davon brauchen etliche
    Zaehler, die es noch nicht gibt (Raidstunden, Teilnahmen, Berufe). Der
    bequeme Weg waere, fuer alles einen Fortschritt von null anzuzeigen.

    Das waere gelogen. "0 von 50 Raidteilnahmen" behauptet, gezaehlt zu
    werden. Wer das liest, denkt, er habe nichts erreicht — dabei schaut das
    Addon gar nicht hin. Deshalb liefert Progress fuer eine fehlende Quelle
    `measurable = false`, und die Oberflaeche schreibt "noch nicht messbar".

    Eine Regel steht hier trotzdem, auch wenn ihre Quelle fehlt: Sie
    dokumentiert, was gemessen werden MUESSTE, und sobald der Zaehler
    existiert, laeuft sie ohne weitere Aenderung an.

    ===========================================================================
    WAS RUECKWIRKEND GILT UND WAS NICHT
    ===========================================================================

    Zaehler ueber die eigene Datenbank (verteilte Items, Paesse) sind
    rueckwirkend richtig, weil die Daten da sind. Zaehler ueber Ereignisse
    (Raidstunden) sind es nicht — sie beginnen mit der Installation. Deshalb
    haelt Achievements den Zeitpunkt achievementsSince fest, und die
    Oberflaeche nennt ihn. Ohne den waere "50 Raids" eine Aussage ueber das
    Addon statt ueber den Spieler.
------------------------------------------------------------------------------]]

local _, GA = ...

local Rules = {}
GA.Modules.Rules = Rules

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Hoechststufe auf Forever. Gemessen 18.09.2026: Stufengrenze 60.
local MAX_LEVEL = 60

--- Ab welcher Qualitaet ein Ausruestungsteil als "episch oder besser" zaehlt.
local EPIC = 4

--- Plaetze, die NICHT mitzaehlen: Hemd und Wappenrock sind kosmetisch und
--- nie episch. Sie mitzuzaehlen waere harmlos, sie zu erwaehnen nicht: Wer
--- spaeter eine Obergrenze rechnet, rechnet sonst mit neunzehn.
local COSMETIC_SLOTS = { [4] = true, [19] = true }

--- WIE VIELE PLAETZE KOENNEN UEBERHAUPT EPISCH SEIN.
---
--- Gemeldet am 21.09.2026 aus dem Spiel: hoechstens 15, mit zwei
--- Einhandwaffen 16. Nachgerechnet: 19 Plaetze minus Hemd und Wappenrock
--- sind 17; davon ist die Schildhand nur mit einer Einhandwaffe belegt, und
--- der Distanzplatz traegt bei den meisten Klassen nichts Episches.
---
--- Diese Zahl aendert KEINE Zaehlung. Sie dient nur dazu, ein Ziel, das
--- darueber liegt, als unerreichbar zu kennzeichnen — statt es bei "15 von
--- 18" stehen zu lassen, wo niemand erfaehrt, dass die 18 nie kommen.
local MAX_EPIC_SLOTS = 16

--- Klassen in Vanilla-Inhalt: Krieger, Magier, Schurke, Jaeger, Hexenmeister,
--- Priester, Paladin, Schamane, Druide. Der Katalog fuehrt genau diese neun
--- als Erstlingserfolge — die Zahl stammt also aus dem Katalog und nicht aus
--- einer Annahme ueber den Client.
local CLASS_COUNT = 9

--- Ab wann eine Tasche als "gross" gilt. Vanilla-Grenze.
local BIG_BAG_SLOTS = 16

--- Sammelfenster fuer Ereignisse, die in Salven kommen (Geld, Taschen).
local COLLECT_WINDOW = 5

--- Ruhiger Takt fuer Quellen, die mit der Uhr wachsen statt mit einem
--- Ereignis — es gibt genau eine davon, guildDays.
local SLOW_CHECK = 600

local function account()
    return GA.Core.Database.account
end

local function ownProfile()
    local guid = Compat.GetPlayerIdentity().guid
    return guid and GA.Modules.Players:GetProfileFor(guid) or nil
end

-- ================================================================== Quellen --
--
-- Jede Quelle liefert eine ZAHL oder nil. nil heisst "nicht messbar" und ist
-- etwas anderes als 0. Genau diese Unterscheidung traegt die Datei.

Rules.SOURCES = {}

--- Hoechste Stufe unter allen Charakteren des Spielers.
function Rules.SOURCES.characterLevel()
    local profile = ownProfile()
    if not profile then
        -- Ohne Profil kennt das Addon nur den aktuellen Charakter.
        return Compat.GetPlayerIdentity().level
    end

    local best = 0
    for _, character in ipairs(GA.Modules.Players:CharactersOf(profile)) do
        best = math.max(best, tonumber(character.level) or 0)
    end
    return best
end

--- Hat der Spieler einen Charakter dieser Klasse auf Hoechststufe?
--- @return number 1 oder 0
function Rules.SOURCES.classAtMax(class)
    local profile = ownProfile()
    if not profile then return 0 end

    for _, character in ipairs(GA.Modules.Players:CharactersOf(profile)) do
        if character.class == class and (tonumber(character.level) or 0) >= MAX_LEVEL then
            return 1
        end
    end
    return 0
end

--- Wie viele Ausruestungsplaetze sind gerade episch oder besser?
---
--- Gezaehlt wird der GETRAGENE Stand, nicht was jemals besessen wurde. Der
--- Erfolg heisst "gleichzeitig", und das ist der Unterschied zwischen einer
--- Ausruestung und einer Sammlung.
function Rules.SOURCES.epicSlots()
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and account().characters[identity.guid]
    if not character or not character.equipment then return nil end

    local count = 0
    for slotID, entry in pairs(character.equipment) do
        if not COSMETIC_SLOTS[slotID] and (tonumber(entry.quality) or 0) >= EPIC then
            count = count + 1
        end
    end
    return count
end

--- Die Obergrenze als Quelle, damit Progress sie ohne Sonderfall kennt.
function Rules.SOURCES.epicSlotsMax()
    return MAX_EPIC_SLOTS
end

--- Von mir verteilte Gegenstaende.
---
--- Nur BESTAETIGTE: Eine Vergabe ohne Bestaetigungsart ist eine Absicht, kein
--- Erhalt (Abschnitt 4.3). Und keine Probevergaben — die sind zum Ueben da.
function Rules.SOURCES.awardsGiven()
    local own = Compat.GetPlayerIdentity().guid
    if not own then return nil end

    local count = 0
    for _, award in pairs(account().awards) do
        if award.lootMasterGuid == own and award.confirmation and not award.test then
            count = count + 1
        end
    end
    return count
end

--- Vergaben, bei denen ein Grund dokumentiert ist.
---
--- NUR EINE ECHTE NOTIZ ZAEHLT.
---
--- Zuerst zaehlte hier auch die Antwort ("Bestausruestung", "Zweitspec") mit.
--- Die setzt das Addon aber bei JEDER Bewerbung selbst — damit haette
--- praktisch jede Vergabe als "dokumentiert" gegolten, und der Erfolg haette
--- nichts mehr ausgesagt.
---
--- Dokumentieren heisst: Jemand hat sich hingesetzt und aufgeschrieben,
--- warum. Genau das soll der Erfolg wuerdigen.
function Rules.SOURCES.awardsDocumented()
    local own = Compat.GetPlayerIdentity().guid
    if not own then return nil end

    local count = 0
    for _, award in pairs(account().awards) do
        if award.lootMasterGuid == own and not award.test
            and award.note and award.note ~= ""
        then
            count = count + 1
        end
    end
    return count
end

--- Wie viele eigene Charaktere stehen auf Hoechststufe?
---
--- Ueber das PROFIL, nicht ueber die Charakterliste: Gezaehlt werden die
--- Charaktere, die nachweislich demselben Menschen gehoeren. Sonst zaehlte
--- ein Gildenmitglied auf Stufe 60 als eigener Twink.
function Rules.SOURCES.charactersAtMax()
    local profile = ownProfile()
    if not profile then return nil end

    local count = 0
    for _, character in ipairs(GA.Modules.Players:CharactersOf(profile)) do
        if (tonumber(character.level) or 0) >= MAX_LEVEL then count = count + 1 end
    end
    return count
end

--- Wie viele VERSCHIEDENE Klassen davon?
function Rules.SOURCES.classesAtMax()
    local profile = ownProfile()
    if not profile then return nil end

    local seen, count = {}, 0
    for _, character in ipairs(GA.Modules.Players:CharactersOf(profile)) do
        local class = character.class
        if class and (tonumber(character.level) or 0) >= MAX_LEVEL and not seen[class] then
            seen[class] = true
            count = count + 1
        end
    end
    return count
end

--- Wie viele Klassen gibt es ueberhaupt? Dient als Obergrenze, damit ein
--- Ziel darueber als unerreichbar erkennbar wird.
function Rules.SOURCES.classCount()
    return CLASS_COUNT
end

--- Seit wie vielen Tagen bin ich dokumentiert in der Gilde?
---
--- KnownSince liefert den beobachteten Beitritt, sonst den Zeitpunkt, seit
--- dem das Addon die Gilde ueberhaupt kennt. Beides ist hier richtig: Der
--- Katalog sagt "dokumentierte Gildenmitgliedschaft", und dokumentiert ist,
--- was dieses Addon gesehen hat. Ein Beitritt von 2019 zaehlt nicht mit, und
--- das ist keine Luecke, sondern die Aussage.
function Rules.SOURCES.guildDays()
    local History = GA.Modules.GuildHistory
    if not History then return nil end

    local name = Compat.GetPlayerIdentity().name
    if not name then return nil end

    local since = History:KnownSince(name)
    if not since then return nil end
    return math.floor((Util.Now() - since) / 86400)
end

--- Von mir verteilte Gegenstaende, bei denen nichts nachkorrigiert wurde.
---
--- Eine Korrektur ist kein Makel — sie ist der Beweis, dass jemand hingesehen
--- hat. Der Erfolg heisst trotzdem "Null Beschwerden", und dafuer zaehlt nur,
--- was unangetastet geblieben ist.
function Rules.SOURCES.awardsClean()
    local own = Compat.GetPlayerIdentity().guid
    if not own then return nil end

    local status = GA.Data.Schema.LootStatus
    local count = 0
    for _, award in pairs(account().awards) do
        if award.lootMasterGuid == own and award.confirmation and not award.test then
            local clean = true
            for _, step in ipairs(award.statusHistory or {}) do
                if step.status == status.CORRECTED or step.status == status.CANCELLED then
                    clean = false
                end
            end
            if clean then count = count + 1 end
        end
    end
    return count
end

--- Wie viele VERSCHIEDENE Gegenstaende habe ich bestaetigt erhalten?
--- Verschieden, nicht insgesamt: Der Erfolg heisst "Archivar".
function Rules.SOURCES.distinctItemsReceived()
    local guid = Compat.GetPlayerIdentity().guid
    if not guid then return nil end

    local seen, count = {}, 0
    for _, award in pairs(account().awards) do
        if award.recipientGuid == guid and award.confirmation and not award.test
            and award.itemID and not seen[award.itemID]
        then
            seen[award.itemID] = true
            count = count + 1
        end
    end
    return count
end

--- Die meisten Gegenstaende an EINEM Abend.
---
--- Gezaehlt wird der beste Abend, nicht der heutige: Der Erfolg ist einmal
--- geschafft und bleibt es. Ein Zaehler, der taeglich auf null faellt, waere
--- ein Tageszaehler und kein Erfolg.
function Rules.SOURCES.bestNightHaul()
    local guid = Compat.GetPlayerIdentity().guid
    if not guid then return nil end

    local byDay, best = {}, 0
    for _, award in pairs(account().awards) do
        if award.recipientGuid == guid and award.confirmation and not award.test then
            local day = math.floor((award.ts or 0) / 86400)
            byDay[day] = (byDay[day] or 0) + 1
            if byDay[day] > best then best = byDay[day] end
        end
    end
    return best
end

--- Gold auf diesem Charakter. Nicht kontoweit: Das Spiel kennt keinen
--- gemeinsamen Geldbeutel, und zusammenzuzaehlen, was nie zusammen war,
--- waere eine Erfindung.
function Rules.SOURCES.gold()
    local copper = Compat.GetMoney()
    if copper == nil then return nil end
    return math.floor(copper / 10000)
end

--- Angelegte Taschen mit mindestens sechzehn Plaetzen.
function Rules.SOURCES.bigBags()
    local sizes = Compat.GetBagSizes()
    if not sizes then return nil end

    local count = 0
    for bag = 1, 4 do
        if (sizes[bag] or 0) >= BIG_BAG_SLOTS then count = count + 1 end
    end
    return count
end

--- Gelernte Hauptberufe. nil heisst hier "weiss nicht", nicht "keine" —
--- siehe Compat.GetProfessions.
function Rules.SOURCES.professions()
    local list = Compat.GetProfessions()
    if not list then return nil end
    return #list
end

--- Auf Hoechstrang gebrachte Hauptberufe.
function Rules.SOURCES.professionsMaxed()
    local list = Compat.GetProfessions()
    if not list then return nil end

    local count = 0
    for _, profession in ipairs(list) do
        if profession.maxRank > 0 and profession.rank >= profession.maxRank then
            count = count + 1
        end
    end
    return count
end

--- Raidstunden. Kommen aus Raids/Attendance.
---
--- Diese Quelle ist NICHT rueckwirkend: Sie beginnt mit der Installation.
--- Die Oberflaeche nennt deshalb achievementsSince daneben.
function Rules.SOURCES.raidHours()
    local Attendance = GA.Modules.Attendance
    if not Attendance then return nil end
    return math.floor(Attendance:Hours())
end

--- Raidteilnahmen, je Abend und Instanz einmal.
function Rules.SOURCES.raidsAttended()
    local Attendance = GA.Modules.Attendance
    if not Attendance then return nil end
    return Attendance:Count()
end

--- Wie oft habe ich im Council gepasst?
---
--- Gezaehlt wird ueber die aufbewahrten Sessions. Eine Bewerbung mit der
--- Antwort PASS ist eine bewusste Entscheidung zugunsten anderer — das
--- unterscheidet sie davon, sich gar nicht erst zu bewerben, und nur das
--- Erste ist ein Erfolg wert.
function Rules.SOURCES.passes()
    local name = Compat.GetPlayerIdentity().name
    if not name then return nil end
    local wanted = Util.NormalizeName(name)

    local count = 0
    for _, session in pairs(account().sessions or {}) do
        for _, byName in pairs(session.responses or {}) do
            for candidate, bid in pairs(byName) do
                if bid.response == "PASS" and Util.NormalizeName(candidate) == wanted then
                    count = count + 1
                end
            end
        end
    end
    return count
end

--- Erhaltene Gegenstaende, fuer die ich Zweitausruestung angegeben habe.
function Rules.SOURCES.offspecReceived()
    local name = Compat.GetPlayerIdentity().name
    if not name then return nil end
    local wanted = Util.NormalizeName(name)

    local count = 0
    for _, award in pairs(account().awards) do
        if award.response == "OFFSPEC" and award.confirmation and not award.test
            and award.recipientName and Util.NormalizeName(award.recipientName) == wanted
        then
            count = count + 1
        end
    end
    return count
end

--- Ein erhaltener Gegenstand, der auf meiner Wunschliste ganz oben stand.
function Rules.SOURCES.topWishlistHit()
    local identity = Compat.GetPlayerIdentity()
    if not identity.guid then return nil end

    local top = {}
    for _, entry in ipairs(GA.Modules.Wishlist:Get(identity.guid)) do
        -- Der erste Prioritaetsschluessel im Schema ist der hoechste.
        if entry.priority == GA.Data.Schema.WishlistPriority[1].key then
            top[entry.itemID] = true
        end
    end

    local count = 0
    for _, award in pairs(account().awards) do
        if award.confirmation and not award.test and top[award.itemID]
            and award.recipientGuid == identity.guid
        then
            count = count + 1
        end
    end
    return count
end

-- ================================================================== Regeln ---
--
-- kind:
--   threshold  Quelle >= value
--   flag       Quelle >= 1 (arg wird an die Quelle durchgereicht)
--
-- Eine Regel, deren Quelle in SOURCES fehlt, ist NICHT kaputt — sie ist noch
-- nicht messbar und wird auch so angezeigt.

Rules.RULES = {
    -- Stufen
    ["GA-046"] = { kind = "threshold", source = "characterLevel", value = 10 },
    ["GA-047"] = { kind = "threshold", source = "characterLevel", value = 30 },
    ["GA-048"] = { kind = "threshold", source = "characterLevel", value = 40 },
    ["GA-049"] = { kind = "threshold", source = "characterLevel", value = 50 },
    ["GA-050"] = { kind = "threshold", source = "characterLevel", value = MAX_LEVEL },

    -- Mehrere eigene Charaktere auf Hoechststufe
    ["GA-051"] = { kind = "threshold", source = "charactersAtMax", value = 2 },
    ["GA-052"] = { kind = "threshold", source = "charactersAtMax", value = 3 },
    ["GA-053"] = { kind = "threshold", source = "charactersAtMax", value = 5 },
    ["GA-054"] = { kind = "threshold", source = "charactersAtMax", value = 10 },
    ["GA-064"] = { kind = "threshold", source = "classesAtMax", value = 5, max = "classCount" },
    ["GA-065"] = { kind = "threshold", source = "classesAtMax", value = 9, max = "classCount" },

    -- Klassen auf Hoechststufe
    ["GA-055"] = { kind = "flag", source = "classAtMax", arg = "WARRIOR" },
    ["GA-056"] = { kind = "flag", source = "classAtMax", arg = "MAGE" },
    ["GA-057"] = { kind = "flag", source = "classAtMax", arg = "ROGUE" },
    ["GA-058"] = { kind = "flag", source = "classAtMax", arg = "HUNTER" },
    ["GA-059"] = { kind = "flag", source = "classAtMax", arg = "WARLOCK" },
    ["GA-060"] = { kind = "flag", source = "classAtMax", arg = "PRIEST" },
    ["GA-061"] = { kind = "flag", source = "classAtMax", arg = "PALADIN" },
    ["GA-062"] = { kind = "flag", source = "classAtMax", arg = "SHAMAN" },
    ["GA-063"] = { kind = "flag", source = "classAtMax", arg = "DRUID" },

    -- Ausruestung
    ["GA-071"] = { kind = "threshold", source = "epicSlots", value = 5, max = "epicSlotsMax" },
    ["GA-072"] = { kind = "threshold", source = "epicSlots", value = 10, max = "epicSlotsMax" },
    ["GA-073"] = { kind = "threshold", source = "epicSlots", value = 15, max = "epicSlotsMax" },
    ["GA-074"] = { kind = "threshold", source = "epicSlots", value = 18, max = "epicSlotsMax" },

    -- Verzicht im Council
    ["GA-079"] = { kind = "threshold", source = "passes", value = 1 },
    ["GA-080"] = { kind = "threshold", source = "passes", value = 10 },
    ["GA-081"] = { kind = "threshold", source = "passes", value = 25 },
    ["GA-082"] = { kind = "threshold", source = "passes", value = 50 },
    ["GA-045"] = { kind = "threshold", source = "passes", value = 10 },  -- Gilden-First

    -- Wunschliste und Zweitausruestung
    ["GA-084"] = { kind = "threshold", source = "topWishlistHit", value = 1 },
    ["GA-085"] = { kind = "threshold", source = "offspecReceived", value = 10 },

    -- Lootmeister
    ["GA-142"] = { kind = "threshold", source = "awardsGiven", value = 1 },
    ["GA-143"] = { kind = "threshold", source = "awardsGiven", value = 25 },
    ["GA-144"] = { kind = "threshold", source = "awardsGiven", value = 100 },
    ["GA-145"] = { kind = "threshold", source = "awardsGiven", value = 250 },
    ["GA-146"] = { kind = "threshold", source = "awardsGiven", value = 500 },
    ["GA-153"] = { kind = "threshold", source = "awardsDocumented", value = 100 },
    ["GA-151"] = { kind = "threshold", source = "awardsClean", value = 50 },

    -- Gildenzugehoerigkeit, in Tagen seit dem ersten dokumentierten Beleg
    ["GA-128"] = { kind = "threshold", source = "guildDays", value = 30 },
    ["GA-129"] = { kind = "threshold", source = "guildDays", value = 90 },
    ["GA-130"] = { kind = "threshold", source = "guildDays", value = 180 },
    ["GA-131"] = { kind = "threshold", source = "guildDays", value = 365 },
    ["GA-132"] = { kind = "threshold", source = "guildDays", value = 730 },
    ["GA-133"] = { kind = "threshold", source = "guildDays", value = 1825 },

    -- Eigene Beute
    ["GA-249"] = { kind = "threshold", source = "distinctItemsReceived", value = 100 },
    ["GA-252"] = { kind = "threshold", source = "bestNightHaul", value = 3 },

    -- Besitz. Direkt beim Client erfragt, deshalb rueckwirkend richtig.
    ["GA-182"] = { kind = "threshold", source = "gold", value = 100 },
    ["GA-183"] = { kind = "threshold", source = "gold", value = 1000 },
    ["GA-184"] = { kind = "threshold", source = "gold", value = 5000 },
    ["GA-246"] = { kind = "threshold", source = "bigBags", value = 4 },

    -- Berufe
    ["GA-163"] = { kind = "threshold", source = "professions", value = 1 },
    ["GA-164"] = { kind = "threshold", source = "professionsMaxed", value = 1 },
    ["GA-165"] = { kind = "threshold", source = "professionsMaxed", value = 2 },

    -- ----------------------------------------------------------------------
    -- Angemeldet, aber noch nicht messbar. Die Quellen fehlen; die Regeln
    -- stehen hier, damit sichtbar ist, WAS gezaehlt werden muesste, und damit
    -- sie anlaufen, sobald der Zaehler existiert.
    -- ----------------------------------------------------------------------
    ["GA-096"] = { kind = "threshold", source = "raidHours", value = 10 },
    ["GA-097"] = { kind = "threshold", source = "raidHours", value = 50 },
    ["GA-098"] = { kind = "threshold", source = "raidHours", value = 100 },
    ["GA-099"] = { kind = "threshold", source = "raidHours", value = 250 },
    ["GA-100"] = { kind = "threshold", source = "raidHours", value = 500 },

    ["GA-123"] = { kind = "threshold", source = "raidsAttended", value = 1 },
    ["GA-124"] = { kind = "threshold", source = "raidsAttended", value = 10 },
    ["GA-125"] = { kind = "threshold", source = "raidsAttended", value = 50 },
    ["GA-126"] = { kind = "threshold", source = "raidsAttended", value = 100 },
    ["GA-127"] = { kind = "threshold", source = "raidsAttended", value = 250 },

    -- GA-163 stand hier ebenfalls, bis Compat.GetProfessions da war. Die
    -- Regel ist nach oben zu den Berufen gewandert; hier bliebe sie sonst
    -- doppelt stehen, und die zweite haette die erste ueberschrieben.
    ["GA-158"] = { kind = "threshold", source = "syncedRecords", value = 1000 },
}

-- ================================================================== Messen ---

--- Der Stand einer Regel.
---
--- @return table { measurable, current, target, done }
function Rules:Progress(id)
    local rule = self.RULES[id]
    if not rule then return { measurable = false, reason = "norule" } end

    local source = self.SOURCES[rule.source]
    if not source then
        -- NICHT 0 von N. Siehe Dateikopf: Das waere eine Behauptung, gezaehlt
        -- zu werden.
        return { measurable = false, reason = "nosource", target = rule.value }
    end

    local ok, value = pcall(source, rule.arg)
    if not ok or value == nil then
        return { measurable = false, reason = "nodata", target = rule.value }
    end

    local target = rule.kind == "flag" and 1 or rule.value

    -- EIN ZIEL UEBER DER OBERGRENZE IST UNERREICHBAR, und das gehoert
    -- gesagt. "15 von 18" sieht aus wie fehlende drei Gegenstaende; in
    -- Wahrheit gibt es die Plaetze gar nicht.
    local ceiling = rule.max and Rules.SOURCES[rule.max] and Rules.SOURCES[rule.max]()
    local unreachable = ceiling ~= nil and target > ceiling or nil

    return {
        measurable = true,
        current = value,
        target = target,
        done = value >= target,
        unreachable = unreachable,
        ceiling = ceiling,
    }
end

--- Prueft alle Regeln und schaltet frei, was neu erfuellt ist.
--- @return number neu freigeschaltet
function Rules:Evaluate()
    local Achievements = GA.Modules.Achievements
    local unlocked = 0

    for id in pairs(self.RULES) do
        if not Achievements:IsUnlocked(id) then
            local progress = self:Progress(id)
            if progress.measurable and progress.done then
                local ok = Achievements:Unlock(id, {
                    evidence = Achievements.EVIDENCE.MEASURED,
                    value = progress.current,
                })
                if ok then unlocked = unlocked + 1 end
            end
        end
    end

    if unlocked > 0 then
        Debug:Print("core", "Erfolge geprueft: %d neu", unlocked)
    end
    return unlocked
end

--- Auswerten, aber nicht sofort.
---
--- PLAYER_MONEY feuert bei jedem aufgesammelten Kupferstueck, BAG_UPDATE bei
--- jedem Beutezug. 47 Regeln bei jedem dieser Ereignisse durchzurechnen waere
--- Rechenzeit fuer nichts. Stattdessen wird EIN Durchlauf angemeldet und alles
--- dazwischen faellt in dasselbe Fenster.
function Rules:Soon()
    if self.pending then return end
    self.pending = true
    Compat.After(COLLECT_WINDOW, function()
        Rules.pending = nil
        Rules:Evaluate()
    end)
end

--- Wie viele Regeln sind ueberhaupt messbar?
function Rules:Coverage()
    local total, measurable = 0, 0
    for id in pairs(self.RULES) do
        total = total + 1
        if self:Progress(id).measurable then measurable = measurable + 1 end
    end
    return { rules = total, measurable = measurable,
             catalog = GA.Data.Catalog.COUNT }
end

-- ================================================================== Start ------

function Rules:OnEnable()
    -- Ausgewertet wird an den Anlaessen, an denen sich etwas geaendert haben
    -- KANN, nicht in einer Schleife. Ein Erfolgssystem, das jede Sekunde
    -- rechnet, kostet Rechenzeit fuer nichts.
    for _, event in ipairs({ "EQUIPMENT_UPDATED", "AWARD_CHANGED", "PLAYERS_CHANGED",
                             "RAID_ATTENDANCE_CHANGED" }) do
        GA.Core.Callbacks:On(event, function() Rules:Evaluate() end, "Rules")
    end

    -- Clientereignisse fuer die Quellen, die direkt beim Spiel nachfragen.
    -- PLAYER_MONEY feuert bei jedem Kupferstueck — deshalb steht dahinter
    -- kein Evaluate, sondern ein Sammelfenster (siehe below()).
    GA.Core.Events:Register("PLAYER_LEVEL_UP", function() Rules:Evaluate() end, "Rules")
    for _, event in ipairs({ "PLAYER_MONEY", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
        GA.Core.Events:Register(event, function() Rules:Soon() end, "Rules")
    end

    -- Einmal kurz nach dem Anmelden: Der Datenbestand kann sich zwischen zwei
    -- Sitzungen geaendert haben, etwa durch einen Abgleich.
    Compat.After(15, function() Rules:Evaluate() end)

    -- Und danach ruhig weiter. Der Grund ist genau EINE Quelle: guildDays
    -- waechst mit der Uhr, ohne dass irgendein Ereignis feuert. Ein Erfolg,
    -- der erst beim naechsten Anmelden auffaellt, waere kein Fehler — aber
    -- eine Pruefung alle zehn Minuten kostet nichts.
    local function tick()
        Rules:Evaluate()
        Compat.After(SLOW_CHECK, tick)
    end
    Compat.After(SLOW_CHECK, tick)
end
