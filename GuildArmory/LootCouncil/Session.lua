--[[----------------------------------------------------------------------------
    LootCouncil/Session — Lootsession: Bewerbungen sammeln, Council abstimmen
    lassen, vergeben.

    Kein UI. Die reine Logik ist in tools/test/session.test.js geprueft.

    WER IST MASSGEBLICH: der Lootmeister. Nur sein Client legt Vergaben an.
    Die uebrigen Clients bekommen eine Kennung (awardId) zugeschickt, die fuer
    sie undurchsichtig ist, und schicken sie mit ihrer Bewerbung zurueck. So
    gibt es keine zwei Datenbanken, die auseinanderlaufen koennen — es gibt eine,
    und alle anderen reden ueber sie.

    REGELN, DIE HIER DURCHGESETZT WERDEN:

      - Nur EINE offene Session. Ein zweiter Boss, waehrend der erste noch
        verteilt wird, waere eine Einladung zur Verwechslung.
      - Eine Bewerbung nach Sessionende wird abgelehnt, nicht nachgetragen.
      - Eine Stimme je Council-Mitglied und Gegenstand. Eine zweite ersetzt die
        erste (Meinungsaenderung), beide stehen im Journal.
      - Wer selbst beworben hat, darf trotzdem abstimmen — das zu verbieten
        waere eine Regelentscheidung der Gilde, keine des Addons. Die Ansicht
        macht es aber sichtbar.

    REIHENFOLGE DER KANDIDATEN: Stimmen absteigend, dann Gewicht der Antwort
    absteigend, dann Name. Deterministisch — bei gleicher Lage sehen alle
    dieselbe Reihenfolge, sonst diskutiert der Raid ueber Sortierung.
------------------------------------------------------------------------------]]

local _, GA = ...

local Session = {}
GA.Modules.Session = Session

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Schema = GA.Data.Schema

local STATUS_OPEN = "OPEN"
local STATUS_CLOSED = "CLOSED"

local function store()
    return GA.Core.Database.account.sessions
end

local function comm()
    return GA.Core.Comm
end

-- ================================================================== Antworten -

--- Antwortsatz: aus den Einstellungen, sonst die Vorgabe.
function Session:Responses()
    local alle = GA.Core.Config:Get("responses") or Schema.DefaultResponses
    local aktiv = GA.Core.Config:Get("activeResponses")
    if type(aktiv) ~= "table" then return alle end

    local out = {}
    for _, entry in ipairs(alle) do
        -- PASS BLEIBT IMMER. Wer nicht will, muss das sagen koennen —
        -- sonst bleibt nur Schweigen, und das ist von "noch nicht
        -- geantwortet" nicht zu unterscheiden.
        if entry.key == "PASS" or aktiv[entry.key] then
            out[#out + 1] = entry
        end
    end

    -- Eine leere Liste waere ein Gebotsfenster ohne Knoepfe. Dann lieber
    -- alle: Eine unbrauchbare Einstellung soll nicht das Fenster
    -- unbrauchbar machen.
    if #out <= 1 then return alle end
    return out
end

function Session:ResponseByKey(key)
    for _, response in ipairs(self:Responses()) do
        if response.key == key then return response end
    end
    return nil
end

local function responseWeight(self, key)
    local response = self:ResponseByKey(key)
    return response and response.weight or -1
end

--- Wie heute verteilt wird: "COUNCIL" | "SOFTRES" | "ROLL".
---
--- Liest die alte Einstellung mit: Wer frueher "Council aus" gesetzt hat,
--- soll nicht beim naechsten Start wieder abstimmen lassen.
--- Die Regeln, nach denen GERADE gespielt wird.
---
--- Eine laufende Sitzung schlaegt die eigene Einstellung — auch die eigene.
--- Wer mitten im Abend umstellt, aendert damit nicht, was gerade laeuft;
--- und ein Mitglied richtet sich nach dem, was der Plündermeister
--- angekuendigt hat, nicht nach dem, was bei ihm eingestellt ist.
--- @return string|nil
function Session:ActiveRules()
    local eigene = self:Current()
    if eigene then return eigene.mode, eigene.rollSource end
    if self.incoming then return self.incoming.mode, self.incoming.rollSource end
    return nil, nil
end

function Session:Mode()
    local laufend = self:ActiveRules()
    if laufend then return laufend end

    local mode = GA.Core.Config:Get("lootMode")
    if mode == "SOFTRES" or mode == "ROLL" or mode == "COUNCIL" or mode == "DKP" then
        return mode
    end

    if GA.Core.Config:Get("councilEnabled") == false then
        return GA.Core.Config:Get("softResEnabled") ~= false and "SOFTRES" or "ROLL"
    end
    return "COUNCIL"
end

--- Wird in diesem Modus gewuerfelt — und fuer diesen Gegenstand?
---
--- Bei SOFTRES nur, wenn ihn NIEMAND reserviert hat. Ist er reserviert,
--- entscheidet die Reservierung, und ein Wurf daneben waere ein zweites
--- Verfahren fuer dieselbe Sache.
--- @return boolean
function Session:RollsFor(itemID)
    local mode = self:Mode()
    if mode == "DKP" then return false end
    if mode == "ROLL" then return true end
    if mode ~= "SOFTRES" then return false end

    local SoftRes = GA.Modules.SoftRes
    local reserviert = SoftRes and SoftRes:For(itemID)
    return not reserviert or #reserviert == 0
end

--- Die Wurfstufen, wie sie den Bietern angeboten werden.
function Session:RollTiers()
    return Schema.RollTiers
end

--- Die Stufe zu einer Spanne, oder nil.
function Session:TierByMax(max)
    for index, tier in ipairs(Schema.RollTiers) do
        if tier.max == max then return tier, index end
    end
    return nil
end

-- ================================================================== Zugriff ---

function Session:Get(sessionId)
    return sessionId and store()[sessionId] or nil
end

--- Die eine offene Session, oder nil.
function Session:Current()
    for _, session in pairs(store()) do
        if session.status == STATUS_OPEN then return session end
    end
    return nil
end

function Session:IsOpen(session)
    return session ~= nil and session.status == STATUS_OPEN
end

--- Darf dieser Charakter eine Session fuehren?
function Session:CanHost(guid)
    guid = guid or Compat.GetPlayerIdentity().guid
    return GA.Core.Database:HasAtLeast(guid, GA.const.ROLE_LOOTMASTER)
end

--- Laeuft die Gebotsfrist noch?
---
--- MASSGEBLICH IST DIE UHR DES PLUENDERMEISTERS. Die Anzeige beim Bieter
--- zaehlt herunter, aber abgelehnt wird hier — zwei Clients haben nie
--- genau dieselbe Zeit, und die letzte Sekunde ist genau die, um die
--- gestritten wird.
--- @return boolean offen, number|nil verbleibend
function Session:BidsOpen(session)
    session = session or self:Current()
    if not session then return false end
    if session.status ~= STATUS_OPEN then return false end
    if not session.bidsCloseAt then return true end

    local rest = session.bidsCloseAt - Util.Now()
    if rest <= 0 then return false, 0 end
    return true, rest
end

function Session:CanVote(guid)
    guid = guid or Compat.GetPlayerIdentity().guid

    -- Ohne Council stimmt niemand ab: Der Plündermeister entscheidet
    -- allein, und ein Stimmknopf, der nichts bewirkt, ist schlimmer als
    -- keiner.
    if GA.Core.Config:Get("councilEnabled") == false then return false end

    local wer = GA.Core.Config:Get("voteRole") or GA.const.ROLE_COUNCIL
    if wer == "ALL" then return true end
    return GA.Core.Database:HasAtLeast(guid, wer)
end

-- ================================================================== Eroeffnen -

--- Oeffnet eine Session fuer die angegebenen Vergaben.
--- @return table|nil session, string|nil grund
function Session:Open(awardIds, options)
    options = options or {}
    local identity = Compat.GetPlayerIdentity()

    if not options.force and not self:CanHost(identity.guid) then
        return nil, "notallowed"
    end
    if self:Current() then return nil, "alreadyopen" end
    if not awardIds or #awardIds == 0 then return nil, "noitems" end

    local session = {
        id = Util.NewId("s"),
        ts = Util.Now(),
        openedBy = identity.guid,
        openedByName = identity.name,
        status = STATUS_OPEN,
        -- FESTGEHALTEN BEIM OEFFNEN, nicht bei jeder Frage neu gelesen.
        -- Wer mitten in einer Sitzung die Einstellung umstellt, aendert
        -- damit nicht rueckwirkend, wonach heute Abend gespielt wird.
        mode = nil,
        rollSource = nil,
        awardIds = {},
        responses = {},
        votes = {},
    }

    local Awards = GA.Modules.Awards
    for _, awardId in ipairs(awardIds) do
        local award = Awards:Get(awardId)
        -- Nur frisch erkannte Gegenstaende. Etwas bereits Vergebenes noch
        -- einmal zur Abstimmung zu stellen, waere eine Korrektur — und die
        -- laeuft ueber Awards:Correct, nicht heimlich ueber eine neue Session.
        if award and award.status == Schema.LootStatus.DETECTED then
            if Awards:Transition(awardId, Schema.LootStatus.SESSION_OPEN,
                { by = identity.guid, reason = "Session " .. session.id }) then
                session.awardIds[#session.awardIds + 1] = awardId
                award.sessionId = session.id
                session.responses[awardId] = {}
                session.votes[awardId] = {}
            end
        end
    end

    if #session.awardIds == 0 then return nil, "noeligible" end

    session.mode = self:Mode()
    session.rollSource = self:RollSource()

    -- DIE FRIST WIRD BEIM OEFFNEN FESTGEHALTEN, nicht bei jeder Frage neu
    -- gerechnet. Wer die Einstellung mitten in einer Sitzung aendert,
    -- verlaengert damit nicht rueckwirkend, was schon laeuft.
    --
    -- 0 heisst: ohne Uhr. Dann schliesst der Plündermeister von Hand —
    -- manche Gilden wollen das, und eine Uhr, die man nicht abstellen
    -- kann, zwingt zu Hast.
    local sekunden = tonumber(GA.Core.Config:Get("bidSeconds")) or 0
    session.bidSeconds = sekunden
    if sekunden > 0 then
        session.bidsCloseAt = Util.Now() + sekunden
    end

    store()[session.id] = session
    GA.Core.Database:Journal("SESSION_OPEN", session.id, nil, #session.awardIds)

    self:Announce(session)
    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    Debug:Print("loot", "Session %s geoeffnet: %d Gegenstaende", session.id, #session.awardIds)
    return session
end

--- Schickt Session und Gegenstaende an die Gruppe.
function Session:Announce(session)
    if not comm() then return end

    -- DIE REGELN REISEN MIT.
    --
    -- Sonst liest jeder Client seine EIGENE Einstellung, und ein Mitglied
    -- im Wurfmodus saehe Council-Knoepfe, waehrend der Plündermeister
    -- Wuerfe erwartet. Massgeblich ist, wer die Sitzung fuehrt — er hat
    -- die Gegenstaende, und er vergibt.
    -- ALS VERBLEIBENDE SEKUNDEN, NICHT ALS ZEITPUNKT. Zwei Clients haben
    -- nie genau dieselbe Uhr; eine Zahl von Sekunden bedeutet ueberall
    -- dasselbe, ein Zeitstempel nicht.
    local _, rest = self:BidsOpen(session)
    comm():Send("SOPEN", { session.id, #session.awardIds,
        session.mode, session.rollSource, rest and math.floor(rest) or 0 })
    for _, awardId in ipairs(session.awardIds) do
        local award = GA.Modules.Awards:Get(awardId)
        if award and award.itemID then
            comm():Send("SITEM", { session.id, awardId, award.itemID })
        end
    end
end

function Session:Close(sessionId, reason)
    local session = self:Get(sessionId) or self:Current()
    if not session or session.status ~= STATUS_OPEN then return false, "notopen" end

    local identity = Compat.GetPlayerIdentity()
    if not self:CanHost(identity.guid) then return false, "notallowed" end

    session.status = STATUS_CLOSED
    session.closedTs = Util.Now()
    session.closedReason = reason

    GA.Core.Database:Journal("SESSION_CLOSE", session.id, nil, reason)
    if comm() then comm():Send("SCLOSE", { session.id }) end

    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    Debug:Print("loot", "Session %s geschlossen (%s)", session.id, tostring(reason))
    return true
end

-- ================================================================== Bewerbung -

--- Traegt eine Bewerbung ein. Auf dem Client des Lootmeisters.
--- @param bid table { response, note, itemLevel, class, guid }
--- @return boolean ok, string|nil grund
function Session:RecordBid(sessionId, awardId, playerName, bid)
    local session = self:Get(sessionId)
    if not session then return false, "unknownsession" end
    if session.status ~= STATUS_OPEN then return false, "closed" end
    if not self:BidsOpen(session) then return false, "timeup" end
    if not session.responses[awardId] then return false, "unknownitem" end
    if not playerName or playerName == "" then return false, "noplayer" end

    local key = bid and bid.response
    if not self:ResponseByKey(key) then return false, "unknownresponse" end

    local name = Util.ShortName(playerName)
    local previous = session.responses[awardId][name]

    session.responses[awardId][name] = {
        response = key,
        note = bid.note,
        itemLevel = bid.itemLevel,
        class = bid.class,
        guid = bid.guid,
        ts = Util.Now(),
    }

    -- Meinungsaenderungen sind erlaubt, aber nachvollziehbar.
    if previous and previous.response ~= key then
        GA.Core.Database:Journal("BID_CHANGE", awardId, previous.response, key)
    end

    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    return true
end

--- Schickt die eigene Bewerbung an den Lootmeister. Auf dem Client des Spielers.
function Session:SendBid(sessionId, awardId, responseKey, note)
    if not self:ResponseByKey(responseKey) then return false, "unknownresponse" end

    -- Das eigene Itemlevel im betroffenen Platz waere hier nuetzlich — es steht
    -- aber nur fest, wenn der Gegenstand einen bekannten Platz hat. Solange das
    -- nicht sicher ist, wird das Gesamt-Itemlevel geschickt und als solches
    -- beschriftet, statt eine Platzangabe zu erfinden.
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    local itemLevel = character and character.itemLevel and character.itemLevel.value

    -- Notizen kuerzen und von Trennzeichen befreien: Sie kommen von Menschen.
    note = note and string.sub(string.gsub(note, "|", ""), 1, 60) or ""

    -- IST DIE SITZUNG HIER ZU HAUSE, WIRD DIREKT EINGETRAGEN.
    --
    -- Session:Get findet nur Sitzungen, die auf DIESEM Client liegen — ein
    -- Raidmitglied hat von einer fremden Sitzung nur self.incoming. Trifft
    -- es zu, waere die Nachricht eine an sich selbst.
    --
    -- Das war auch der Grund fuer "nochannel": Der Weg fuehrte ueber den
    -- Gruppenkanal, und allein gibt es keinen. Ein Plündermeister, der auf
    -- seinen eigenen Gegenstand bietet, kam so nie durch — im Probebetrieb
    -- nie, und im Raid nur, weil dort zufaellig ein Kanal existiert.
    if self:Get(sessionId) then
        return self:RecordBid(sessionId, awardId, identity.name, {
            response = responseKey,
            note = note,
            itemLevel = itemLevel,
            class = identity.class,
            guid = identity.guid,
        })
    end

    if not comm() then return false, "nocomm" end

    return comm():Send("BID", {
        sessionId, awardId, responseKey,
        itemLevel and string.format("%.2f", itemLevel) or "",
        note,
    })
end

--- Nimmt einen Wurf als Gebot entgegen.
---
--- EIN WURF IST EIN GEBOT MIT EINER ZAHL.
---
--- Das ist die Entscheidung, an der der ganze Aufbau haengt. Statt neben
--- der Sitzung ein zweites Verfahren mit eigener Liste, eigener Anzeige
--- und eigener Vergabe zu fuehren, landet der Wurf in derselben Tabelle
--- wie jedes andere Gebot — nur mit `roll` daran. Damit gilt fuer alle
--- drei Arten derselbe Satz: Der Plündermeister vergibt aus der Liste der
--- Bewerber.
---
--- Die Stufe kommt aus der SPANNE, nicht aus einer Behauptung: Wer
--- /roll 50 wuerfelt, hat sich damit auf die Zweitskillung festgelegt, und
--- das steht fuer alle sichtbar im Chat. Eine Angabe, die das Addon
--- mitschickt, koennte jeder abweichend eintragen.
---
--- @return boolean angenommen, string|nil grund
function Session:RecordRoll(sessionId, awardId, playerName, result, min, max)
    local session = self:Get(sessionId)
    if not session then return false, "unknownsession" end
    if session.status ~= STATUS_OPEN then return false, "closed" end
    if not self:BidsOpen(session) then return false, "timeup" end
    if not session.responses[awardId] then return false, "unknownitem" end

    local tier, rang = self:TierByMax(tonumber(max))
    if not tier then return false, "range" end
    if tonumber(min) ~= 1 then return false, "range" end

    local name = Util.ShortName(playerName or "")
    if name == "" then return false, "noplayer" end

    -- NUR DER ERSTE WURF ZAEHLT. Ein zweiter waere ein zweiter Versuch,
    -- und den hat sonst niemand. Rolls.lua haelt dieselbe Regel.
    local vorher = session.responses[awardId][name]
    if vorher and vorher.roll then return false, "alreadyrolled" end

    session.responses[awardId][name] = {
        response = tier.key,
        roll = tonumber(result),
        rollMax = tier.max,
        rollRank = rang,
        ts = Util.Now(),
        guid = vorher and vorher.guid,
        class = vorher and vorher.class,
    }

    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    return true
end

--- Nimmt ein DKP-Gebot entgegen.
---
--- EIN DKP-GEBOT IST EIN GEBOT MIT EINER ZAHL — dieselbe Form wie ein
--- Wurf. Es landet in derselben Tabelle, wird nach derselben Regel
--- sortiert und vom Plündermeister auf demselben Weg vergeben. Ein
--- eigenes Verfahren daneben haette dieselbe Anzeige noch einmal
--- gebraucht, und die zweite waere irgendwann von der ersten abgewichen.
---
--- GEPRUEFT WIRD GEGEN DAS KONTOBUCH, nicht gegen das, was der Bieter
--- schickt. Sein Client koennte jede Zahl behaupten; massgeblich ist der
--- Stand, den dieser Client kennt.
---
--- ABGEBUCHT WIRD HIER NOCH NICHT. Geboten ist nicht bekommen — abgebucht
--- wird bei der Vergabe, und nur beim Gewinner. Wer frueher abbucht, muss
--- allen anderen wieder zurueckbuchen, und jede dieser Buchungen kann
--- schiefgehen.
--- @return boolean, string|nil grund
function Session:RecordDkpBid(sessionId, awardId, playerName, points, guid)
    local session = self:Get(sessionId)
    if not session then return false, "unknownsession" end
    if session.status ~= STATUS_OPEN then return false, "closed" end
    if not self:BidsOpen(session) then return false, "timeup" end
    if not session.responses[awardId] then return false, "unknownitem" end

    local name = Util.ShortName(playerName or "")
    if name == "" then return false, "noplayer" end

    local Dkp = GA.Modules.Dkp
    if not Dkp then return false, "nodkp" end

    local vorher = session.responses[awardId][name]
    guid = guid or (vorher and vorher.guid)

    local frei = self:AvailableDkp(sessionId, name, guid, awardId)
    local ok, grund = Dkp:MayBid(guid, points, frei)
    if not ok then return false, grund end

    -- AENDERN DARF MAN, IN BEIDE RICHTUNGEN.
    --
    -- Hier stand erst "hoeher ja, niedriger nein" — uebernommen vom Wurf,
    -- wo die Regel stimmt: Ein Wurf ist oeffentlich, ein zweiter waere ein
    -- zweiter Versuch.
    --
    -- Ein DKP-Gebot ist VERDECKT. Niemand sieht die Betraege der anderen,
    -- also gibt es nichts, worauf man reagieren koennte, und kein Vorteil
    -- ist zu holen. Was die Regel dagegen sicher verhinderte: dass jemand
    -- einen Vertipper geradezieht. Wer 500 statt 50 tippt, soll das
    -- korrigieren koennen, solange die Sitzung laeuft.

    -- Wer bisher vorn lag — vor dem Eintragen, sonst ist es schon dieser
    -- hier.
    local bisher, bisherPunkte
    for anderer, gebot in pairs(session.responses[awardId]) do
        if gebot.dkp and anderer ~= name then
            if not bisherPunkte or gebot.dkp > bisherPunkte then
                bisher, bisherPunkte = anderer, gebot.dkp
            end
        end
    end

    session.responses[awardId][name] = {
        response = "DKP",
        dkp = tonumber(points),
        ts = Util.Now(),
        guid = guid,
        class = vorher and vorher.class,
        note = vorher and vorher.note,
    }

    -- UEBERBOTEN? Dann eine Nachricht an den, der vorn lag.
    --
    -- OHNE DEN NEUEN BETRAG. Das Gebot ist verdeckt: Wer weiss, wie hoch
    -- der Hoechststand ist, bietet genau eins darueber, und aus der
    -- Versteigerung wird ein Wettrennen um die letzte Sekunde. "Du bist
    -- ueberboten" genuegt, um noch einmal nachzudenken.
    if bisher and bisherPunkte and tonumber(points) > bisherPunkte then
        self:NotifyOutbid(session, awardId, bisher)
    end

    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    return true
end

--- Wie viele Punkte dieser Spieler in DIESER Sitzung schon gebunden hat.
---
--- Ohne den Gegenstand, auf den gerade geboten wird: Ein erhoehtes Gebot
--- ersetzt das alte, es kommt nicht dazu.
--- @return number
function Session:CommittedDkp(sessionId, playerName, exceptAwardId)
    local session = self:Get(sessionId)
    if not session then return 0 end

    local name = Util.ShortName(playerName or "")
    local summe = 0
    for awardId, gebote in pairs(session.responses) do
        if awardId ~= exceptAwardId then
            local gebot = gebote[name]
            if gebot and gebot.dkp then summe = summe + gebot.dkp end
        end
    end
    return summe
end

--- Was dieser Spieler gerade noch bieten kann.
---
--- Der Stand minus dem, was in dieser Sitzung schon offen steht. DAS IST
--- DIE ZAHL, DIE IM GEBOTSFENSTER STEHEN MUSS — wer 500 liest und nur 400
--- ausgeben kann, bietet ins Leere und versteht die Ablehnung nicht.
--- @return number
function Session:AvailableDkp(sessionId, playerName, guid, exceptAwardId)
    local Dkp = GA.Modules.Dkp
    if not Dkp then return 0 end
    return Dkp:Balance(guid) - self:CommittedDkp(sessionId, playerName, exceptAwardId)
end

--- Nimmt ein DKP-Gebot ganz zurueck.
---
--- ABGEBUCHT IST NOCH NICHTS — bezahlt wird erst bei der Vergabe, und nur
--- vom Gewinner. Zurueckziehen heisst deshalb wirklich nur: aus der Liste
--- verschwinden. Es gibt nichts zurueckzubuchen.
--- @return boolean, string|nil grund
function Session:CancelDkpBid(sessionId, awardId, playerName)
    local session = self:Get(sessionId)
    if not session then return false, "unknownsession" end
    if session.status ~= STATUS_OPEN then return false, "closed" end
    -- AUCH DAS ZURUECKNEHMEN. Sonst koennte jemand nach Ablauf noch
    -- aussteigen, wenn er die Lage sieht — und genau darum geht die
    -- Frist.
    if not self:BidsOpen(session) then return false, "timeup" end
    if not session.responses[awardId] then return false, "unknownitem" end

    local name = Util.ShortName(playerName or "")
    local gebot = session.responses[awardId][name]
    if not gebot or not gebot.dkp then return false, "nobid" end

    session.responses[awardId][name] = nil
    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    return true
end

--- Sagt jemandem, dass sein Gebot nicht mehr das hoechste ist.
---
--- NUR VOM CLIENT DES PLUENDERMEISTERS, denn nur dort stehen die Gebote.
--- Und nur an den Betroffenen: Eine Ansage an die Gruppe waere die
--- Bekanntgabe, wer ueberhaupt bietet.
function Session:NotifyOutbid(session, awardId, name)
    if GA.Core.Config:Get("dkpOutbidWhisper") == false then return end
    if not comm() then return end

    -- An sich selbst wird nicht gefluestert; das eigene Fenster zeigt es.
    if comm():IsSelf(name) then
        GA.Core.Debug:Info("%s", GA.L.DKP_OUTBID_SELF)
        return
    end

    local award = GA.Modules.Awards:Get(awardId)
    local was = (award and award.itemName) or "?"
    Compat.SendChatMessage(string.format(GA.L.DKP_OUTBID, was), "WHISPER",
        Util.ShortName(name))
end

-- ================================================================== Wuerfe ---

--- Woher die Wurfzahl kommt: "MASTER" | "CHAT".
---
--- DIE EIGENTLICHE FRAGE IST NICHT "LAUT ODER LEISE", SONDERN WER WUERFELT.
---
--- CHAT   Jeder wuerfelt selbst mit /roll. Der SERVER zieht die Zahl, und
---        der ganze Raid liest sie mit — niemand kann sie faelschen, auch
---        der Plündermeister nicht. Preis: Bei 20 Leuten und 10
---        Gegenstaenden sind das 200 Zeilen, und wer das Addon nicht hat,
---        sieht sie alle.
---
--- MASTER Der Client des Plündermeisters zieht die Zahl, sobald eine
---        Bewerbung ankommt. Kein Chat, kein Verkehr.
---
---        DAS IST NACHPRUEFBARKEIT GEGEN RUHE, und der Tausch ist ehrlich
---        zu benennen: Die Zahl ist fuer den Raid nicht mehr
---        kontrollierbar. Wogegen er trotzdem schuetzt, ist der Fall, der
---        haeufiger vorkommt — dass ein BEWERBER seine eigene Zahl
---        schoenrechnet. Der kann es hier nicht, weil sein Client die Zahl
---        gar nicht zieht.
---
---        Wer dem Plündermeister nicht traut, hat ein groesseres Problem
---        als Wuerfel: Er verteilt ohnehin.
---
--- Voreinstellung MASTER, weil eine Gilde ihrem Plündermeister das
--- Verteilen ohnehin anvertraut und 200 Chatzeilen niemandem helfen.
function Session:RollSource()
    local _, laufend = self:ActiveRules()
    if laufend then return laufend end

    local quelle = GA.Core.Config:Get("rollSource")
    if quelle == "CHAT" or quelle == "MASTER" then return quelle end
    return "MASTER"
end

--- Zieht eine Zahl auf dem Client des Plündermeisters.
---
--- math.random ohne randomseed: Den Faden zu SETZEN waere ein Eingriff in
--- das Spiel und jedes andere Addon — ihn zu BENUTZEN ist genau das,
--- wofuer er da ist.
function Session:MasterRoll(sessionId, awardId, name, tierKey)
    local tier
    for _, entry in ipairs(Schema.RollTiers) do
        if entry.key == tierKey then tier = entry break end
    end
    if not tier then return false, "unknowntier" end

    local zahl = math.random(1, tier.max)
    local ok, grund = self:RecordRoll(sessionId, awardId, name, zahl, 1, tier.max)
    if not ok then return false, grund end
    return true, zahl, tier.max
end

--- Angekuendigte Wuerfe: [normalisierter Name] = { awardId, max, ts }.
---
--- WARUM EINE ANKUENDIGUNG NOETIG IST.
---
--- Ein /roll im Chat sagt WER und WIE VIEL — aber nicht, FUER WELCHEN
--- GEGENSTAND. Liegen drei Stuecke zur Wahl, ist die Zahl allein nicht
--- zuzuordnen. Deshalb sagt der Client vorher, worauf gewuerfelt wird, und
--- der Wurf selbst bleibt das, was er sein muss: eine Zeile im Chat, die
--- jeder im Raid mitlesen und nachrechnen kann.
---
--- Ein vom Addon ausgedachter Wurf waere bequemer und wertlos: Niemand
--- koennte ihn pruefen, und bei Lootstreit ist genau das der Punkt.
Session.pendingRolls = {}

--- Wie lange eine Ankuendigung gilt. Wer nach einer halben Minute wuerfelt,
--- wuerfelt fuer etwas anderes.
local ROLL_GRACE = 30

--- Kuendigt einen Wurf an und wuerfelt.
--- @return boolean, string|nil grund
function Session:DeclareRoll(sessionId, awardId, tierKey)
    local tier
    for _, entry in ipairs(Schema.RollTiers) do
        if entry.key == tierKey then tier = entry break end
    end
    if not tier then return false, "unknowntier" end

    local identity = Compat.GetPlayerIdentity()
    if not identity.name then return false, "noname" end

    local hier = self:Get(sessionId) ~= nil

    -- Liegt die Sitzung nicht hier, muss der Plündermeister die Bewerbung
    -- erfahren: Sein Client sieht weder den Klick noch — im leisen Betrieb
    -- — eine Chatzeile.
    if not hier then
        if not comm() then return false, "nocomm" end
        comm():Send("RDECL", { sessionId, awardId, tier.key })
    end

    if self:RollSource() == "MASTER" then
        -- DER BEWERBER WUERFELT NICHT SELBST. Liegt die Sitzung hier, zieht
        -- dieser Client die Zahl; sonst tut es gleich der des
        -- Plündermeisters, wenn die Ankuendigung ankommt. In beiden Faellen
        -- zieht sie jemand, der nichts davon hat.
        if hier then
            return self:MasterRoll(sessionId, awardId, identity.name, tier.key)
        end
        return true
    end

    -- IM CHATBETRIEB IMMER NUR EINER ZUR ZEIT.
    --
    -- Eine Chatzeile sagt WER und WIE VIEL, aber nie WOFUER. Zugeordnet
    -- wird ueber Name und Spanne — und das geht nur, solange von dieser
    -- Person genau eine Ankuendigung offen ist. Wer auf zwei Gegenstaende
    -- hintereinander 100 ankuendigt, erzeugt zwei ununterscheidbare
    -- Zeilen, und die zweite Ankuendigung wuerde die erste ueberschreiben:
    -- Der Wurf fuer den ersten Gegenstand landete beim zweiten.
    --
    -- Lieber ablehnen als raten. Wer den einen Wurf abwartet, verliert ein
    -- paar Sekunden; wer falsch zugeordnet wird, verliert den Gegenstand.
    --
    -- Beim Plündermeister gibt es das Problem nicht: Dort kommt die
    -- Gegenstandskennung MIT der Bewerbung an.
    local offen = self.pendingRolls[Util.NormalizeName(identity.name) or identity.name]
    if offen and Util.Now() - (offen.ts or 0) <= ROLL_GRACE then
        return false, "pending"
    end

    self:NotePendingRoll(identity.name, awardId, tier.max)

    if not Compat.RandomRoll(1, tier.max) then return false, "noroll" end
    return true
end

--- Merkt sich, worauf jemand gleich wuerfelt.
function Session:NotePendingRoll(name, awardId, max)
    local key = Util.NormalizeName and Util.NormalizeName(name) or Util.ShortName(name)
    self.pendingRolls[key] = { awardId = awardId, max = max, ts = Util.Now() }
end

--- Ordnet eine Wurfzeile aus dem Chat der angekuendigten Bewerbung zu.
---
--- ZUGEORDNET WIRD UEBER NAME UND SPANNE. Stimmt die Spanne nicht mit der
--- Ankuendigung ueberein, hat derjenige etwas anderes gewuerfelt — dann
--- gilt der Wurf nicht, statt dass ihm eine Absicht untergeschoben wird.
--- @return boolean verarbeitet
function Session:OnSystemRoll(message)
    local session = self:Current()
    if not session then return false end

    local name, roll, min, max = Compat.ParseRoll(message)
    if not name or not roll then return false end

    local key = Util.NormalizeName and Util.NormalizeName(name) or Util.ShortName(name)
    local pending = self.pendingRolls[key]
    if not pending then return false end

    if Util.Now() - (pending.ts or 0) > ROLL_GRACE then
        self.pendingRolls[key] = nil
        return false
    end

    if tonumber(max) ~= pending.max then return false end

    self.pendingRolls[key] = nil
    local ok = self:RecordRoll(session.id, pending.awardId, name, roll, min, max)
    return ok and true or false
end

--- Nimmt eine Wurfzeile entgegen und sagt, ob sie im Chat zu sehen sein soll.
---
--- DIE ZUORDNUNG PASSIERT HIER, NICHT DANEBEN.
---
--- Es gaebe zwei Wege, an dieselbe Zeile zu kommen: den Ereignishaken auf
--- CHAT_MSG_SYSTEM und den Chatfilter. Beide zu benutzen hiesse, sich auf
--- ihre Reihenfolge zu verlassen — und die ist nicht zugesichert. Dann
--- waere mal die Zeile weg und der Wurf nicht gezaehlt, mal umgekehrt.
---
--- Also EIN Weg: Der Filter ordnet zu und entscheidet danach. Was er
--- zuordnen konnte, gehoert zur Sitzung und steht gleich im
--- Loot-Session-Fenster; die Zeile im Chat waere eine Dopplung. Was er
--- nicht zuordnen konnte, ist ein fremder Wurf und bleibt stehen.
---
--- AUSGEBLENDET WIRD NUR HIER. Auf dem Server ist gewuerfelt worden, und
--- alle anderen im Raid sehen die Zeile weiterhin — daran aendert ein
--- Chatfilter nichts und soll es auch nicht. Nachpruefbar bleibt der Wurf.
--- @return boolean verstecken
function Session:HandleRollLine(message)
    local zugeordnet = self:OnSystemRoll(message)
    if not zugeordnet then return false end
    return GA.Core.Config:Get("quietRolls") ~= false
end

-- ================================================================== Stimmen ---

--- Eine Stimme je Waehler und Gegenstand. Eine zweite ersetzt die erste.
function Session:RecordVote(sessionId, awardId, voterGuid, candidateName, voterName)
    local session = self:Get(sessionId)
    if not session then return false, "unknownsession" end
    if session.status ~= STATUS_OPEN then return false, "closed" end
    if not session.votes[awardId] then return false, "unknownitem" end
    if not voterGuid then return false, "novoter" end

    local candidate = candidateName and Util.ShortName(candidateName) or nil
    -- Nur fuer jemanden stimmen, der sich auch beworben hat. Alles andere
    -- waere eine Stimme fuer einen Namen, den niemand geprueft hat.
    if candidate and not session.responses[awardId][candidate] then
        return false, "nobid"
    end

    local previous = session.votes[awardId][voterGuid]

    -- ENTHALTUNG IST false, NICHT nil. Eine Zuweisung von nil loescht den
    -- Schluessel — die Enthaltung waere dann nicht von "hat noch nicht
    -- abgestimmt" zu unterscheiden, und der Lootmeister wartet auf eine Stimme,
    -- die nie kommt. false bleibt in der Tabelle und zaehlt als abgegeben.
    session.votes[awardId][voterGuid] = candidate or false

    if previous ~= candidate then
        GA.Core.Database:Journal("VOTE", awardId, previous, candidate, voterGuid)
    end

    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    return true
end

function Session:SendVote(sessionId, awardId, candidateName)
    -- Wie bei SendBid: Liegt die Sitzung hier, wird direkt eingetragen
    -- statt eine Nachricht an sich selbst zu schicken.
    if self:Get(sessionId) then
        local identity = Compat.GetPlayerIdentity()
        return self:RecordVote(sessionId, awardId, identity.guid,
            candidateName, identity.name)
    end

    if not comm() then return false, "nocomm" end
    return comm():Send("VOTE", { sessionId, awardId, candidateName or "" })
end

--- Kandidaten eines Gegenstands, fertig sortiert.
--- @return table  { { name, response, weight, note, itemLevel, class, votes } }
function Session:Tally(sessionId, awardId)
    local session = self:Get(sessionId)
    if not session or not session.responses[awardId] then return {} end

    local counts = {}
    for _, candidate in pairs(session.votes[awardId] or {}) do
        if candidate then counts[candidate] = (counts[candidate] or 0) + 1 end
    end

    local list = {}
    for name, bid in pairs(session.responses[awardId]) do
        list[#list + 1] = {
            name = name,
            guid = bid.guid,
            response = bid.response,
            weight = responseWeight(self, bid.response),
            note = bid.note,
            itemLevel = bid.itemLevel,
            class = bid.class,
            votes = counts[name] or 0,
            roll = bid.roll,
            rollMax = bid.rollMax,
            rollRank = bid.rollRank,
            dkp = bid.dkp,
            ts = bid.ts,
        }
    end

    table.sort(list, function(a, b)
        -- WURFRUNDEN ENTSCHEIDEN NACH STUFE, DANN NACH ZAHL.
        --
        -- Eine 3 auf 100 schlaegt eine 49 auf 50. Sonst waere die
        -- groessere Spanne ein Nachteil — und genau umgekehrt ist sie
        -- gemeint: Wer mehr Anspruch anmeldet, wuerfelt hoeher hinaus.
        -- DKP ENTSCHEIDET ALLEIN DIE ZAHL. Es gibt keine Stufen: Wer mehr
        -- bietet, hat mehr bezahlt, und mehr gibt es dazu nicht zu sagen.
        if a.dkp or b.dkp then
            local da, db = a.dkp or -1, b.dkp or -1
            if da ~= db then return da > db end
            return a.name < b.name
        end

        if a.rollRank or b.rollRank then
            local ra, rb = a.rollRank or 99, b.rollRank or 99
            if ra ~= rb then return ra < rb end
            local va, vb = a.roll or -1, b.roll or -1
            if va ~= vb then return va > vb end
            return a.name < b.name
        end

        if a.votes ~= b.votes then return a.votes > b.votes end
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.name < b.name
    end)
    return list
end

--- Wie viele Council-Mitglieder haben fuer diesen Gegenstand schon abgestimmt?
--- Enthaltungen zaehlen mit: Sie sind eine Entscheidung, kein Schweigen.
function Session:VoteCount(sessionId, awardId)
    local session = self:Get(sessionId)
    if not session or not session.votes[awardId] then return 0 end
    local count = 0
    for _ in pairs(session.votes[awardId]) do count = count + 1 end
    return count
end

-- ================================================================== Vergeben --

--- Vergibt einen Gegenstand an einen Kandidaten und schliesst ihn ab.
--- Die Uebergabe selbst passiert NICHT hier — sie braucht einen Mausklick
--- (Master Loot) oder einen Handel. Siehe LootHistory/LootTracker.
function Session:AwardTo(sessionId, awardId, candidateName)
    local session = self:Get(sessionId)
    if not session then return false, "unknownsession" end

    local identity = Compat.GetPlayerIdentity()
    if not self:CanHost(identity.guid) then return false, "notallowed" end

    local bid = session.responses[awardId] and session.responses[awardId][Util.ShortName(candidateName or "")]
    if not bid then return false, "nobid" end

    -- Fuer den Buchungstext: Ein Kontobuch mit "d17901664160027" darin ist
    -- kein Kontobuch, sondern eine Liste von Kennungen.
    local award = GA.Modules.Awards:Get(awardId)

    -- ERST ABBUCHEN, DANN VERGEBEN.
    --
    -- Andersherum waere die Vergabe schon eingetragen, wenn die Buchung
    -- scheitert — und dann haette jemand den Gegenstand, ohne bezahlt zu
    -- haben. Scheitert es hier, ist nichts passiert.
    --
    -- Nur beim GEWINNER: Die anderen haben geboten, nicht bezahlt.
    local gebucht
    if bid.dkp and GA.Modules.Dkp then
        local eintrag, grund = GA.Modules.Dkp:Charge(bid.guid,
            Util.ShortName(candidateName), bid.dkp,
            string.format("%s (%s)", tostring(award and award.itemName or awardId),
                session.id),
            { by = identity.guid, awardId = awardId })
        if not eintrag then return false, grund end
        gebucht = eintrag
    end

    local ok, reason = GA.Modules.Awards:Award(awardId, {
        guid = bid.guid,
        name = Util.ShortName(candidateName),
        response = bid.response,
        note = bid.note,
        dkp = bid.dkp,
    }, { by = identity.guid, byName = identity.name, reason = "Council " .. session.id })

    if not ok then
        -- DIE BUCHUNG ZURUECKNEHMEN. Sonst haette jemand bezahlt und
        -- nichts bekommen — und das faellt erst beim naechsten Blick ins
        -- Kontobuch auf, wenn niemand mehr weiss, warum.
        if gebucht then
            GA.Modules.Dkp:Refund(gebucht.id, "Vergabe fehlgeschlagen", identity.guid)
        end
        return false, reason
    end

    if comm() then
        comm():Send("AWARD", { session.id, awardId, Util.ShortName(candidateName), bid.response })
    end

    GA.Core.Callbacks:Fire("SESSION_CHANGED", session.id)
    return true
end

--- Sind alle Gegenstaende der Session erledigt?
function Session:IsSettled(sessionId)
    local session = self:Get(sessionId)
    if not session then return false end
    for _, awardId in ipairs(session.awardIds) do
        local award = GA.Modules.Awards:Get(awardId)
        if award and award.status == Schema.LootStatus.SESSION_OPEN then return false end
    end
    return true
end

-- ================================================================== Empfang ---

--- Der Spieler-seitige Teil: Ankuendigungen aufnehmen und den Bewerbungsdialog
--- fuellen. Die Gegenstaende werden hier NICHT als Vergaben angelegt — die
--- Wahrheit liegt beim Lootmeister.
function Session:OnEnable()
    local Comm = comm()
    if not Comm then return end

    Comm:On("SOPEN", function(sender, fields)
        local sessionId = fields[1]
        if not sessionId then return end
        -- Alte Wurfzahlen und Gebote gehoeren zur vorigen Sitzung.
        Session.myRolls = {}
        Session.myBids = {}
        local rest = tonumber(fields[5]) or 0
        self.incoming = {
            id = sessionId, host = sender, items = {},
            -- Die Regeln des GASTGEBERS, nicht die eigenen.
            mode = fields[3],
            rollSource = fields[4],
            -- Die eigene Uhr, aus den verbleibenden Sekunden gerechnet.
            closeAt = rest > 0 and (Util.Now() + rest) or nil,
        }
        Debug:Print("comm", "Session %s von %s angekuendigt", sessionId, tostring(sender))
    end, "Session")

    Comm:On("SITEM", function(sender, fields)
        local sessionId, awardId, itemID = fields[1], fields[2], tonumber(fields[3])
        if not self.incoming or self.incoming.id ~= sessionId then return end
        if not awardId or not itemID then return end

        self.incoming.items[#self.incoming.items + 1] = { awardId = awardId, itemID = itemID }

        -- Den Dialog erst zeigen, wenn die Salve durch ist.
        if self.showPending then return end
        self.showPending = true
        Compat.After(1, function()
            self.showPending = false
            if GA.UI.BidFrame and self.incoming and #self.incoming.items > 0 then
                GA.UI.BidFrame:Show(self.incoming)
            end
        end)
    end, "Session")

    Comm:On("SCLOSE", function(sender, fields)
        if self.incoming and self.incoming.id == fields[1] then
            self.incoming = nil
            if GA.UI.BidFrame then GA.UI.BidFrame:Hide() end
        end
    end, "Session")

    -- Lootmeister-Seite: Bewerbungen und Stimmen entgegennehmen.
    Comm:On("BID", function(sender, fields)
        local sessionId, awardId, response = fields[1], fields[2], fields[3]
        local session = self:Get(sessionId)
        if not session or session.openedBy ~= Compat.GetPlayerIdentity().guid then return end

        local character = GA.Core.Database:FindCharacterByName(sender)
        self:RecordBid(sessionId, awardId, sender, {
            response = response,
            itemLevel = tonumber(fields[4]),
            note = fields[5] ~= "" and fields[5] or nil,
            class = character and character.class or nil,
            guid = character and character.guid or nil,
        })
    end, "Session")

    Comm:On("VOTE", function(sender, fields)
        local sessionId, awardId, candidate = fields[1], fields[2], fields[3]
        local session = self:Get(sessionId)
        if not session or session.openedBy ~= Compat.GetPlayerIdentity().guid then return end

        local voter = GA.Core.Database:FindCharacterByName(sender)
        local voterGuid = voter and voter.guid or sender
        if not GA.Core.Database:HasAtLeast(voterGuid, GA.const.ROLE_COUNCIL) then
            Debug:Print("comm", "Stimme von %s verworfen — nicht im Council", tostring(sender))
            return
        end
        self:RecordVote(sessionId, awardId, voterGuid, candidate ~= "" and candidate or nil, sender)
    end, "Session")

    -- Alle: Vergabe zur Kenntnis. Nur Anzeige, keine eigene Buchung.
    Comm:On("AWARD", function(sender, fields)
        GA.Core.Callbacks:Fire("AWARD_ANNOUNCED", fields[1], fields[2], fields[3])
    end, "Session")
    -- Wurfzeilen zuordnen — moeglichst ueber den Chatfilter, weil nur der
    -- sie auch ausblenden kann.
    --
    -- NUR EINER VON BEIDEN WEGEN. Haetten wir Filter UND Ereignishaken,
    -- liefe dieselbe Zeile zweimal durch die Zuordnung, und die zweite
    -- faende die Ankuendigung schon verbraucht.
    local filter = _G.ChatFrame_AddMessageEventFilter
    local angemeldet = false
    if type(filter) == "function" then
        angemeldet = pcall(filter, "CHAT_MSG_SYSTEM", function(_, message)
            return Session:HandleRollLine(message)
        end)
    end

    if not angemeldet then
        -- Ohne Filter wenigstens zaehlen. Die Zeile bleibt dann im Chat
        -- stehen; das ist unschoen, aber besser als ein nicht gezaehlter
        -- Wurf.
        Debug:Print("council", "Kein Chatfilter — Wurfzeilen bleiben sichtbar.")
        GA.Core.Events:Register("CHAT_MSG_SYSTEM", function(_, message)
            Session:OnSystemRoll(message)
        end, "SessionRolls")
    end

    -- Ankuendigung eines fremden Clients: Er sagt, worauf er gleich
    -- wuerfelt. Die Zahl kommt gleich danach aus dem Chat.
    -- Ein DKP-Gebot von aussen. GEPRUEFT WIRD HIER, nicht beim Absender:
    -- Sein Client koennte jede Zahl behaupten, massgeblich ist der Stand,
    -- den dieser Client kennt.
    Comm:On("DBID", function(sender, fields)
        local sessionId, awardId, punkte = fields[1], fields[2], tonumber(fields[3])
        if not sessionId or not awardId or not punkte then return end

        -- NULL HEISST ZURUECKNEHMEN. Eine eigene Nachrichtenart dafuer
        -- waere eine mehr, die jeder Client kennen muss — und null ist
        -- ohnehin kein gueltiges Gebot, das Mindestgebot liegt darueber.
        if punkte <= 0 then
            local weg = Session:CancelDkpBid(sessionId, awardId, sender)
            if weg and comm() then
                comm():Send("DACK", { awardId, 0 }, "WHISPER", sender)
            end
            return
        end

        local character = GA.Core.Database:FindCharacterByName(sender)
        local ok, grund = Session:RecordDkpBid(sessionId, awardId, sender, punkte,
            character and character.guid)

        -- BESTAETIGEN ODER ABLEHNEN, IN BEIDEN FAELLEN ZURUECK.
        --
        -- Der Bieter kennt seinen eigenen Stand nicht so genau wie dieser
        -- Client: Was er gebunden hat, steht hier. Ohne Rueckmeldung
        -- sieht er nicht, ob sein Gebot angekommen ist — und eine
        -- Ablehnung erfuehre er gar nicht.
        if comm() then
            comm():Send("DACK", { awardId, ok and punkte or -1,
                ok and "" or tostring(grund) }, "WHISPER", sender)
        end
    end, "Session")

    -- Das eigene DKP-Gebot, vom Plündermeister bestaetigt oder abgelehnt.
    Comm:On("DACK", function(sender, fields)
        local awardId, punkte, grund = fields[1], tonumber(fields[2]), fields[3]
        if not awardId or not punkte then return end

        -- Nur vom Gastgeber der angekuendigten Sitzung: Sonst koennte
        -- jeder einem ein Gebot vorspiegeln, das es nicht gibt.
        local incoming = Session.incoming
        if not incoming then return end
        if incoming.host and Util.ShortName(sender) ~= Util.ShortName(incoming.host) then
            return
        end

        Session.myBids = Session.myBids or {}
        if punkte > 0 then
            Session.myBids[awardId] = punkte
        else
            Session.myBids[awardId] = nil
        end

        if GA.UI.BidFrame then
            if punkte < 0 and grund and grund ~= "" then
                GA.UI.BidFrame:ShowBidError(awardId, grund)
            else
                GA.UI.BidFrame:RefreshDkpRows()
            end
        end
    end, "Session")

    -- Die eigene Wurfzahl, vom Plündermeister zurueckgemeldet.
    Comm:On("RROLL", function(sender, fields)
        local awardId, zahl, max = fields[1], tonumber(fields[2]), tonumber(fields[3])
        if not awardId or not zahl then return end

        -- NUR VOM GASTGEBER DER ANGEKUENDIGTEN SITZUNG. Sonst koennte
        -- jeder beliebige Spieler einem eine Zahl vorspiegeln — sie steht
        -- zwar nur in der eigenen Anzeige, aber auch die soll nicht luegen.
        local incoming = Session.incoming
        if not incoming then return end
        if incoming.host and Util.ShortName(sender) ~= Util.ShortName(incoming.host) then
            return
        end

        Session.myRolls = Session.myRolls or {}
        Session.myRolls[awardId] = { roll = zahl, max = max }
        if GA.UI.BidFrame then GA.UI.BidFrame:Relabel() end
    end, "Session")

    Comm:On("RDECL", function(sender, fields)
        local sessionId, awardId, tierKey = fields[1], fields[2], fields[3]
        local session = Session:Get(sessionId)
        if not session or session.status ~= STATUS_OPEN then return end
        if Session:RollSource() == "MASTER" then
            -- Die Zahl zieht der Client des Plündermeisters, also dieser
            -- hier. Der Absender hat sie nicht in der Hand.
            local ok, zahl, max = Session:MasterRoll(sessionId, awardId, sender, tierKey)

            -- UND ZURUECK AN DEN BEWERBER.
            --
            -- Ohne das erfaehrt er seine eigene Zahl nie: Er hat keine
            -- Sitzung liegen, und im leisen Betrieb gibt es auch keine
            -- Chatzeile. Er haette auf einen Knopf gedrueckt und nichts
            -- gesehen — und das sieht aus wie ein kaputtes Addon.
            if ok and comm() then
                comm():Send("RROLL", { awardId, zahl, max }, "WHISPER", sender)
            end
            return
        end

        for _, tier in ipairs(Schema.RollTiers) do
            if tier.key == tierKey then
                Session:NotePendingRoll(sender, awardId, tier.max)
                return
            end
        end
    end, "Session")

end
