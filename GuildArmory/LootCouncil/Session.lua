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
    return GA.Core.Config:Get("responses") or Schema.DefaultResponses
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

function Session:CanVote(guid)
    guid = guid or Compat.GetPlayerIdentity().guid
    return GA.Core.Database:HasAtLeast(guid, GA.const.ROLE_COUNCIL)
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

    comm():Send("SOPEN", { session.id, #session.awardIds })
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
    if not comm() then return false, "nocomm" end

    -- Das eigene Itemlevel im betroffenen Platz waere hier nuetzlich — es steht
    -- aber nur fest, wenn der Gegenstand einen bekannten Platz hat. Solange das
    -- nicht sicher ist, wird das Gesamt-Itemlevel geschickt und als solches
    -- beschriftet, statt eine Platzangabe zu erfinden.
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    local itemLevel = character and character.itemLevel and character.itemLevel.value

    -- Notizen kuerzen und von Trennzeichen befreien: Sie kommen von Menschen.
    note = note and string.sub(string.gsub(note, "|", ""), 1, 60) or ""

    return comm():Send("BID", {
        sessionId, awardId, responseKey,
        itemLevel and string.format("%.2f", itemLevel) or "",
        note,
    })
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
            ts = bid.ts,
        }
    end

    table.sort(list, function(a, b)
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

    local ok, reason = GA.Modules.Awards:Award(awardId, {
        guid = bid.guid,
        name = Util.ShortName(candidateName),
        response = bid.response,
        note = bid.note,
    }, { by = identity.guid, byName = identity.name, reason = "Council " .. session.id })

    if not ok then return false, reason end

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
        self.incoming = { id = sessionId, host = sender, items = {} }
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
end
