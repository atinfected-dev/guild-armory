--[[----------------------------------------------------------------------------
    Quests/Questhub — wer sucht Leute fuer welche Quest.

    Kein UI. Ein GESUCH ist: "Ich habe diese Quest und suche Leute dafuer."
    Es entsteht mit Alt-Klick auf eine Quest im eigenen Log (oder ueber den
    Knopf in der Ansicht), geht an die Gilde und steht dort zwei Stunden —
    oder bis der Sucher es zuruecknimmt oder die Quest abgibt. Andere
    koennen sagen "ich suche auch"; das steht als Liste am Gesuch.

    WAS MITGEHT: Questkennung, Titel, Stufe, Art, die Ueberschrift im Log
    (auf Vanilla die Zone) und bis zu drei Ziele mit ihrem Stand — DIE ZIELE
    DES SUCHERS, aus seinem Log. Was der Empfaenger selbst davon hat, liest
    er aus seinem eigenen Log; das Gesuch behauptet darueber nichts.

    WAS DAS ADDON NICHT TUT: Gruppen bilden. "Einladen" schickt die
    Gruppeneinladung des Spiels, aus dem Klick heraus, wie GiveMasterLoot.
    Wer sie annimmt, ist Sache des Spiels.

    NICHTS DAVON IST GEMESSEN, BIS /ga probe ES SAGT: Welcher Questlog-Weg
    auf dieser Linie etwas hergibt, ob der Alt-Klick ankommt, ob es einen
    Questlink gibt — Compatibility.lua versucht zwei Wege je Frage, und die
    Sonde "questLog" nennt den, der traegt.
------------------------------------------------------------------------------]]

local _, GA = ...

local Questhub = {}
GA.Modules.Questhub = Questhub

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local L = GA.L

--- Ein Gesuch lebt zwei Stunden. Wer laenger sucht, stellt es neu ein.
Questhub.TTL = 2 * 3600
--- Hoechstens drei Ziele, je hoechstens vierzig Zeichen: Die Nachricht
--- fasst 240, und Titel plus Zone brauchen ihren Teil.
Questhub.MAX_OBJECTIVES = 3
Questhub.OBJECTIVE_LEN = 40
Questhub.TITLE_LEN = 60
Questhub.REQUEST_COOLDOWN = 30

Questhub.requests = {}
Questhub.hookPath = nil

local function store()
    local account = GA.Core.Database and GA.Core.Database.account
    if not account then return nil end
    account.questhub = account.questhub or { own = {} }
    account.questhub.own = account.questhub.own or {}
    return account.questhub
end

local function comm() return GA.Core.Comm end

local function ownName()
    local identity = Compat.GetPlayerIdentity()
    return identity.name and Util.ShortName(identity.name) or nil
end

--- Die Klasse zu einem Namen, aus dem Roster. nil = unbekannt.
local function klasseVon(name)
    local members = GA.Core.Database.account.guild and GA.Core.Database.account.guild.members
    local kurz = string.lower(Util.ShortName(name or ""))
    for _, member in pairs(members or {}) do
        if member.name and string.lower(Util.ShortName(member.name)) == kurz then
            return member.class
        end
    end
    return nil
end

local function kuerzen(text, laenge)
    text = tostring(text or "")
    text = string.gsub(text, "[|;]", "")
    if #text > laenge then return string.sub(text, 1, laenge - 1) .. "…" end
    return text
end

-- ================================================================== Eigene ---

--- Stellt eine Quest aus dem eigenen Log ein.
--- @param entry table  ein Eintrag aus Compat.GetQuestLog()
--- @return table|nil request, string|nil reason
function Questhub:Post(entry)
    if not entry or not entry.questID then return nil, "noquest" end
    if not Compat.IsInGuild() then return nil, "noguild" end
    local db = store()
    if not db then return nil, "nodb" end

    -- Dieselbe Quest nicht zweimal: Ein zweites Gesuch ersetzt das erste.
    for id, request in pairs(db.own) do
        if request.questID == entry.questID then self:Withdraw(id, true) end
    end

    local ziele = {}
    for _, objective in ipairs(Compat.GetQuestObjectives(entry.index, entry.questID) or {}) do
        if #ziele >= self.MAX_OBJECTIVES then break end
        ziele[#ziele + 1] = (objective.finished and "+" or "-") .. kuerzen(objective.text, self.OBJECTIVE_LEN)
    end

    local identity = Compat.GetPlayerIdentity()
    local request = {
        id = Util.NewId("q"), questID = entry.questID,
        title = kuerzen(entry.title, self.TITLE_LEN), level = entry.level,
        tag = entry.tag, zone = kuerzen(entry.header, 40),
        objectives = ziele, ts = Util.Now(),
        seeker = ownName() or "?", class = identity.class, own = true,
        joiners = {},
    }
    db.own[request.id] = request
    self.requests[request.id] = request
    self:Send(request)
    GA.Core.Callbacks:Fire("QUESTHUB_CHANGED", "post", request)
    return request
end

--- Stellt die Quest mit dieser Kennung (oder an diesem Platz) ein — der
--- Weg des Alt-Klicks. Ein zweiter Alt-Klick auf dieselbe nimmt sie zurueck.
function Questhub:Toggle(questID, index)
    local log = Compat.GetQuestLog()
    if not log then
        Debug:Info("%s", L.QH_NO_LOG)
        return false
    end
    local entry
    for _, candidate in ipairs(log) do
        if (questID and candidate.questID == questID) or (not questID and candidate.index == index) then
            entry = candidate
            break
        end
    end
    if not entry then return false end

    local db = store()
    for id, request in pairs(db and db.own or {}) do
        if request.questID == entry.questID then
            self:Withdraw(id)
            Debug:Info(L.QH_WITHDRAWN, tostring(entry.title))
            return true
        end
    end

    local request, reason = self:Post(entry)
    if request then
        Debug:Info(L.QH_POSTED, tostring(entry.title))
    else
        Debug:Info("%s", L["QH_ERR_" .. tostring(reason)] or tostring(reason))
    end
    return request ~= nil
end

function Questhub:Send(request)
    if not comm() then return false end
    return comm():Send("QHUB", {
        request.id, request.questID, request.title, request.level or 0,
        request.tag or "", request.zone or "", table.concat(request.objectives or {}, ";"),
        request.ts,
    }, "GUILD", nil, true) and true or false
end

--- Nimmt ein eigenes Gesuch zurueck.
function Questhub:Withdraw(id, quiet)
    local db = store()
    if not db or not db.own[id] then return false end
    db.own[id] = nil
    self.requests[id] = nil
    if comm() then comm():Send("QHUBX", { id }, "GUILD", nil, true) end
    if not quiet then GA.Core.Callbacks:Fire("QUESTHUB_CHANGED", "withdraw", id) end
    return true
end

--- "Ich suche auch" — oder nicht mehr.
function Questhub:Join(id, on)
    local request = self.requests[id]
    if not request or request.own then return false end
    local me = ownName()
    if not me then return false end
    if on then request.joiners[me] = Util.Now() else request.joiners[me] = nil end
    if comm() then comm():Send("QJOIN", { id, on and 1 or 0 }, "GUILD", nil, true) end
    GA.Core.Callbacks:Fire("QUESTHUB_CHANGED", "join", request)
    return true
end

function Questhub:HasJoined(request)
    local me = ownName()
    return me ~= nil and request.joiners[me] ~= nil
end

-- ================================================================== Fremde ---

function Questhub:OnPost(sender, fields)
    if comm() and comm():IsSelf(sender) then return end
    local id = fields[1]
    local questID = tonumber(fields[2])
    local title = fields[3]
    local ts = tonumber(fields[8])
    if type(id) ~= "string" or id == "" or not questID or questID <= 0
        or type(title) ~= "string" or title == "" or not ts then
        return
    end
    -- Ein Gesuch aus der Zukunft oder aelter als seine Lebensdauer ist
    -- keines. Die Uhren zweier Clients weichen ab; drei Stunden sind Luft.
    if math.abs(Util.Now() - ts) > self.TTL + 3600 then return end

    local ziele = {}
    for teil in string.gmatch(tostring(fields[7] or ""), "[^;]+") do ziele[#ziele + 1] = teil end

    local alt = self.requests[id]
    local request = {
        id = id, questID = questID, title = kuerzen(title, self.TITLE_LEN),
        level = tonumber(fields[4]), tag = fields[5] ~= "" and fields[5] or nil,
        zone = fields[6] ~= "" and fields[6] or nil, objectives = ziele, ts = ts,
        seeker = Util.ShortName(sender), class = klasseVon(sender), own = false,
        joiners = alt and alt.joiners or {},
    }
    self.requests[id] = request
    GA.Core.Callbacks:Fire("QUESTHUB_CHANGED", alt and "update" or "new", request)
end

function Questhub:OnWithdraw(sender, fields)
    local request = self.requests[fields[1] or ""]
    if not request or request.own then return end
    if Util.ShortName(sender) ~= request.seeker then return end
    self.requests[request.id] = nil
    GA.Core.Callbacks:Fire("QUESTHUB_CHANGED", "withdraw", request.id)
end

function Questhub:OnJoin(sender, fields)
    if comm() and comm():IsSelf(sender) then return end
    local request = self.requests[fields[1] or ""]
    if not request then return end
    local name = Util.ShortName(sender)
    if tonumber(fields[2]) == 1 then request.joiners[name] = Util.Now()
    else request.joiners[name] = nil end
    GA.Core.Callbacks:Fire("QUESTHUB_CHANGED", "join", request)
end

--- Jemand fragt nach allen Gesuchen: die eigenen noch einmal schicken.
function Questhub:OnRequest(sender)
    if comm() and comm():IsSelf(sender) then return end
    for _, request in pairs(store() and store().own or {}) do self:Send(request) end
end

function Questhub:Request()
    if not comm() or not Compat.IsInGuild() then return false end
    local jetzt = Util.Now()
    if self.lastRequest and jetzt - self.lastRequest < self.REQUEST_COOLDOWN then return false end
    self.lastRequest = jetzt
    return comm():Send("QREQ", {}, "GUILD", nil, true) and true or false
end

-- ================================================================== Lesen ----

--- Wirft weg, was abgelaufen ist. Eigene Gesuche gehen dabei auch aus der
--- Datei.
function Questhub:Prune()
    local grenze = Util.Now() - self.TTL
    local db = store()
    for id, request in pairs(self.requests) do
        if (request.ts or 0) < grenze then
            self.requests[id] = nil
            if db and db.own[id] then db.own[id] = nil end
        end
    end
end

--- Alle Gesuche, nach Zone, dann neueste zuerst.
function Questhub:List()
    self:Prune()
    local out = {}
    for _, request in pairs(self.requests) do out[#out + 1] = request end
    table.sort(out, function(a, b)
        local za, zb = a.zone or "~", b.zone or "~"
        if za ~= zb then return za < zb end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return out
end

function Questhub:Get(id) return id and self.requests[id] or nil end

function Questhub:JoinerCount(request)
    local n = 0
    for _ in pairs(request.joiners or {}) do n = n + 1 end
    return n
end

--- Steht die Quest in MEINEM Log? Dann mit meinen Zielen.
--- @return table|nil { entry, objectives }
function Questhub:MatchOwn(questID)
    if not questID then return nil end
    for _, entry in ipairs(Compat.GetQuestLog() or {}) do
        if entry.questID == questID then
            return { entry = entry, objectives = Compat.GetQuestObjectives(entry.index, entry.questID) or {} }
        end
    end
    return nil
end

function Questhub:Invite(request)
    if not request or not request.seeker then return false, "noname" end
    return Compat.InviteUnit(request.seeker)
end

--- Schreibt das Gesuch in den Gildenchat — mit Questlink, wenn der Client
--- einen hergibt, sonst mit dem Titel.
function Questhub:Announce(request)
    if not request then return false end
    local eigene = self:MatchOwn(request.questID)
    local link = Compat.GetQuestLink(eigene and eigene.entry.index, request.questID)
    local text = string.format(L.QH_CHAT, link or ("[" .. request.title .. "]"),
        request.zone and (" · " .. request.zone) or "")
    return Compat.SendChatMessage(text, "GUILD")
end

-- ================================================================== Start ----

function Questhub:OnEnable()
    local Comm = comm()
    if Comm then
        Comm:On("QHUB", function(sender, fields) Questhub:OnPost(sender, fields) end, "Questhub")
        Comm:On("QHUBX", function(sender, fields) Questhub:OnWithdraw(sender, fields) end, "Questhub")
        Comm:On("QJOIN", function(sender, fields) Questhub:OnJoin(sender, fields) end, "Questhub")
        Comm:On("QREQ", function(sender) Questhub:OnRequest(sender) end, "Questhub")
    end

    -- Eigene Gesuche aus der Datei: zurueck ins Gedaechtnis, abgelaufene weg.
    local db = store()
    for id, request in pairs(db and db.own or {}) do
        request.own = true
        request.joiners = request.joiners or {}
        self.requests[id] = request
    end
    self:Prune()

    self.hookPath = Compat.HookQuestLogClicks(function(questID, index)
        Questhub:Toggle(questID, index)
    end)
    Debug:Print("quest", "Alt-Klick im Questlog: %s", tostring(self.hookPath or "kein Weg"))

    -- Abgegebene Quest: das Gesuch dazu ist erledigt.
    local frame = CreateFrame("Frame")
    if pcall(frame.RegisterEvent, frame, "QUEST_TURNED_IN") then
        frame:SetScript("OnEvent", function(_, _, questID)
            questID = tonumber(questID)
            for id, request in pairs(db and db.own or {}) do
                if request.questID == questID then Questhub:Withdraw(id) end
            end
        end)
    end

    -- Nach dem Start: die eigenen noch einmal, und die anderen fragen.
    Compat.After(6, function()
        for _, request in pairs(db and db.own or {}) do Questhub:Send(request) end
        Questhub:Request()
    end)
end
