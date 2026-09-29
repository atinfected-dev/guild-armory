--[[----------------------------------------------------------------------------
    Quests/Dungeonhub — wer laeuft wann welchen Dungeon, und wer fehlt noch.

    Kein UI. Ein LAUF ist: "Ich gehe um 20:00 nach Blackrock Depths und
    brauche noch Leute." Er hat genau fuenf Plaetze — Tank, Heiler, dreimal
    Schaden —, einen Leiter, eine Notiz und eine Startzeit in den naechsten
    24 Stunden. Wer beitritt, waehlt eine Rolle; nur Rollen mit freiem Platz
    lassen sich waehlen. Der Leiter steht mit seiner Rolle von Anfang an
    drin.

    Ein Lauf steht 24 Stunden nach dem Eintragen, oder bis der Leiter ihn
    zuruecknimmt. Jeder in der Gilde darf eintragen (Entscheidung 29.09.2026).

    PROTOKOLL (Gildenkanal, kurze Nachrichten):
      DHUB   id, dungeon, at, note, ts, leaderRole   ein Lauf (neu oder erneut)
      DJOIN  id, role|0                              beitreten (Rolle) oder gehen (0)
      DMEMB  id, "TANK:Name;HEAL:Name;DPS:A,B,C"     die Besetzung, vom Leiter
      DHUBX  id                                      zurueckgenommen
      DREQ                                           "schickt mir eure Laeufe"
    DER LEITER IST DIE QUELLE DER BESETZUNG: Er antwortet auf jeden Beitritt
    mit DMEMB, und wer spaeter einloggt, bekommt sie auf DREQ. Ohne den
    Leiter online gilt, was die anderen an DJOIN gesehen haben.

    WAS DAS ADDON NICHT TUT: Gruppen bilden. "Gruppe einladen" schickt die
    Einladungen des Spiels aus dem Klick heraus; wer annimmt, ist Sache des
    Spiels.
------------------------------------------------------------------------------]]

local _, GA = ...

local Dungeonhub = {}
GA.Modules.Dungeonhub = Dungeonhub

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local L = GA.L

Dungeonhub.TTL = 24 * 3600          -- ab dem Eintragen
Dungeonhub.HORIZON = 24 * 3600      -- wie weit im Voraus die Startzeit liegen darf
Dungeonhub.GRACE = 3600             -- so weit darf die Startzeit zurueckliegen
Dungeonhub.NOTE_LEN = 60
Dungeonhub.DUNGEON_LEN = 30
Dungeonhub.REQUEST_COOLDOWN = 30

--- Die Rollen, in der Reihenfolge der Plaetze, und wie viele es je gibt.
Dungeonhub.ROLES = { "TANK", "HEAL", "DPS" }
Dungeonhub.SLOTS = { TANK = 1, HEAL = 1, DPS = 3 }

--- Die Instanzen, in der Reihenfolge der Stufen — die Liste der Vorlage.
Dungeonhub.DUNGEONS = {
    "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep",
    "Blackfathom Deeps", "The Stockade", "Gnomeregan", "Razorfen Kraul",
    "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak",
    "Maraudon", "Sunken Temple", "Blackrock Depths", "Lower Blackrock Spire",
    "Upper Blackrock Spire", "Scholomance", "Stratholme", "Dire Maul",
}

Dungeonhub.runs = {}

local function store()
    local account = GA.Core.Database and GA.Core.Database.account
    if not account then return nil end
    account.dungeonhub = account.dungeonhub or { own = {} }
    account.dungeonhub.own = account.dungeonhub.own or {}
    return account.dungeonhub
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
    text = string.gsub(text, "[|;:,]", "")
    text = string.gsub(text, "^%s*(.-)%s*$", "%1")
    if #text > laenge then return string.sub(text, 1, laenge - 1) .. "…" end
    return text
end

local function validRole(role)
    return role == "TANK" or role == "HEAL" or role == "DPS"
end

-- ================================================================== Zeit -----

--- Die Startzeit aus Tag (0 = heute, 1 = morgen) und Uhrzeit, als Stempel.
--- Aus der Uhr des Clients (date/time), denn "20:00" meint die Uhr des
--- Spielers, nicht die des Servers.
--- @return number|nil stempel, string|nil grund
function Dungeonhub.StartTime(dayOffset, hh, mm, now)
    hh, mm = tonumber(hh), tonumber(mm)
    if not hh or not mm or hh < 0 or hh > 23 or mm < 0 or mm > 59 then return nil, "time" end
    now = now or time()
    local t = date("*t", now)
    t.hour, t.min, t.sec = hh, mm, 0
    t.day = t.day + (tonumber(dayOffset) or 0)
    local at = time(t)
    if not at then return nil, "time" end
    if at < now - Dungeonhub.GRACE or at > now + Dungeonhub.HORIZON then return nil, "time" end
    return at
end

--- "HH:MM" -> Stunde, Minute
function Dungeonhub.ParseClock(text)
    local hh, mm = tostring(text or ""):match("^%s*(%d%d?)[:%.](%d%d)%s*$")
    if not hh then return nil end
    return tonumber(hh), tonumber(mm)
end

-- ================================================================== Plaetze --

--- Die fuenf Plaetze eines Laufs, in fester Reihenfolge: T, H, D, D, D —
--- jeder mit Rolle und, wenn besetzt, Name und Klasse.
function Dungeonhub:Slots(run)
    local byRole = { TANK = {}, HEAL = {}, DPS = {} }
    for name, member in pairs(run.members or {}) do
        if byRole[member.role] then
            byRole[member.role][#byRole[member.role] + 1] = { name = name, class = member.class, ts = member.ts or 0 }
        end
    end
    for _, list in pairs(byRole) do
        table.sort(list, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.name < b.name end)
    end
    local out = {}
    for _, role in ipairs(self.ROLES) do
        for index = 1, self.SLOTS[role] do
            local m = byRole[role][index]
            out[#out + 1] = { role = role, name = m and m.name or nil, class = m and m.class or nil }
        end
    end
    return out
end

function Dungeonhub:Count(run, role)
    local n = 0
    for _, member in pairs(run.members or {}) do
        if member.role == role then n = n + 1 end
    end
    return n
end

function Dungeonhub:IsFull(run)
    local n = 0
    for _ in pairs(run.members or {}) do n = n + 1 end
    return n >= 5
end

function Dungeonhub:MyRole(run)
    local me = ownName()
    local member = me and run.members and run.members[me]
    return member and member.role or nil
end

--- Darf ich dieser Rolle beitreten?
--- @return boolean ok, string|nil grund
function Dungeonhub:CanJoin(run, role)
    if not run or not validRole(role) then return false, "role" end
    local me = ownName()
    if not me then return false, "noname" end
    local mine = self:MyRole(run)
    if mine == role then return false, "already" end
    if self:Count(run, role) >= self.SLOTS[role] then return false, "full" end
    return true
end

-- ================================================================== Eigene ---

--- Traegt einen Lauf ein.
--- @return table|nil run, string|nil grund
function Dungeonhub:Post(dungeon, at, note, role)
    if not Compat.IsInGuild() then return nil, "noguild" end
    dungeon = kuerzen(dungeon, self.DUNGEON_LEN)
    if dungeon == "" then return nil, "nodungeon" end
    at = tonumber(at)
    local now = Util.Now()
    if not at or at < now - self.GRACE or at > now + self.HORIZON then return nil, "time" end
    if not validRole(role) then return nil, "role" end
    local db = store()
    if not db then return nil, "nodb" end
    local me = ownName()
    if not me then return nil, "noname" end

    local identity = Compat.GetPlayerIdentity()
    local run = {
        id = Util.NewId("d"), dungeon = dungeon, at = at,
        note = kuerzen(note, self.NOTE_LEN), ts = now,
        leader = me, class = identity.class, own = true,
        members = { [me] = { role = role, class = identity.class, ts = now } },
    }
    db.own[run.id] = run
    db.lastRole = role
    self.runs[run.id] = run
    self:Send(run)
    self:SendMembers(run)
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "post", run)
    return run
end

function Dungeonhub:Send(run)
    if not comm() then return false end
    local leaderRole = run.members and run.members[run.leader] and run.members[run.leader].role or "DPS"
    return comm():Send("DHUB", { run.id, run.dungeon, run.at, run.note or "", run.ts, leaderRole },
        "GUILD", nil, true) and true or false
end

--- Die Besetzung als eine Zeichenkette: "TANK:A;HEAL:B;DPS:C,D,E".
function Dungeonhub.EncodeMembers(run)
    local teile = {}
    for _, role in ipairs(Dungeonhub.ROLES) do
        local namen = {}
        for name, member in pairs(run.members or {}) do
            if member.role == role then namen[#namen + 1] = name end
        end
        table.sort(namen)
        teile[#teile + 1] = role .. ":" .. table.concat(namen, ",")
    end
    return table.concat(teile, ";")
end

function Dungeonhub.DecodeMembers(text, klassen)
    local members = {}
    local order = 0
    for teil in string.gmatch(tostring(text or ""), "[^;]+") do
        local role, namen = teil:match("^(%u+):(.*)$")
        if validRole(role) then
            for name in string.gmatch(namen, "[^,]+") do
                order = order + 1
                members[name] = { role = role, class = klassen and klassen(name) or nil, ts = order }
            end
        end
    end
    return members
end

--- Der Leiter schickt die Besetzung — nach jeder Aenderung und auf Anfrage.
function Dungeonhub:SendMembers(run)
    if not comm() or not run.own then return false end
    return comm():Send("DMEMB", { run.id, self.EncodeMembers(run) }, "GUILD", nil, true) and true or false
end

--- Nimmt einen eigenen Lauf zurueck.
function Dungeonhub:Withdraw(id, quiet)
    local db = store()
    if not db or not db.own[id] then return false end
    db.own[id] = nil
    self.runs[id] = nil
    if comm() then comm():Send("DHUBX", { id }, "GUILD", nil, true) end
    if not quiet then GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "withdraw", id) end
    return true
end

--- Beitreten mit einer Rolle. Wer schon mit einer anderen drin ist,
--- wechselt. Der Leiter wechselt nur die Rolle; gehen kann er nicht.
--- @return boolean ok, string|nil grund
function Dungeonhub:Join(id, role)
    local run = self.runs[id]
    if not run then return false, "norun" end
    local ok, grund = self:CanJoin(run, role)
    if not ok then return false, grund end
    local me = ownName()
    local identity = Compat.GetPlayerIdentity()
    run.members[me] = { role = role, class = identity.class, ts = Util.Now() }
    local db = store()
    if db then db.lastRole = role end
    if comm() then comm():Send("DJOIN", { id, role }, "GUILD", nil, true) end
    if run.own then self:SendMembers(run) end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "join", run)
    return true
end

function Dungeonhub:Leave(id)
    local run = self.runs[id]
    if not run then return false, "norun" end
    local me = ownName()
    if not me or not run.members[me] then return false, "notin" end
    if run.leader == me then return false, "leader" end
    run.members[me] = nil
    if comm() then comm():Send("DJOIN", { id, 0 }, "GUILD", nil, true) end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "leave", run)
    return true
end

function Dungeonhub:LastRole()
    local db = store()
    local role = db and db.lastRole
    return validRole(role) and role or "DPS"
end

-- ================================================================== Fremde ---

function Dungeonhub:OnPost(sender, fields)
    if comm() and comm():IsSelf(sender) then return end
    local id, dungeon = fields[1], fields[2]
    local at, ts = tonumber(fields[3]), tonumber(fields[5])
    if type(id) ~= "string" or id == "" or type(dungeon) ~= "string" or dungeon == "" or not at or not ts then return end
    -- Aelter als seine Lebensdauer oder weit in der Zukunft: kein Lauf.
    -- Zwei Uhren weichen ab; eine Stunde ist Luft.
    local now = Util.Now()
    if ts > now + 3600 or now - ts > self.TTL then return end
    local leader = Util.ShortName(sender)
    local alt = self.runs[id]
    local run = {
        id = id, dungeon = kuerzen(dungeon, self.DUNGEON_LEN), at = at,
        note = kuerzen(fields[4], self.NOTE_LEN), ts = ts,
        leader = leader, class = klasseVon(sender), own = false,
        members = alt and alt.members or {},
    }
    if not run.members[leader] then
        local role = validRole(fields[6]) and fields[6] or "DPS"
        run.members[leader] = { role = role, class = run.class, ts = ts }
    end
    self.runs[id] = run
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", alt and "update" or "new", run)
end

function Dungeonhub:OnWithdraw(sender, fields)
    local run = self.runs[fields[1] or ""]
    if not run or run.own then return end
    if Util.ShortName(sender) ~= run.leader then return end
    self.runs[run.id] = nil
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "withdraw", run.id)
end

function Dungeonhub:OnJoin(sender, fields)
    if comm() and comm():IsSelf(sender) then return end
    local run = self.runs[fields[1] or ""]
    if not run then return end
    local name = Util.ShortName(sender)
    local role = fields[2]
    if validRole(role) then
        -- Voll ist voll — auch, wenn zwei gleichzeitig klicken. Der
        -- Leiter entscheidet mit DMEMB, wer es war.
        if not run.members[name] and self:Count(run, role) >= self.SLOTS[role] then return end
        run.members[name] = { role = role, class = klasseVon(sender), ts = Util.Now() }
    else
        if name == run.leader then return end
        run.members[name] = nil
    end
    if run.own then self:SendMembers(run) end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "join", run)
end

function Dungeonhub:OnMembers(sender, fields)
    if comm() and comm():IsSelf(sender) then return end
    local run = self.runs[fields[1] or ""]
    if not run or run.own then return end
    if Util.ShortName(sender) ~= run.leader then return end
    run.members = self.DecodeMembers(fields[2], klasseVon)
    if not run.members[run.leader] then
        run.members[run.leader] = { role = "DPS", class = run.class, ts = 0 }
    end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "members", run)
end

--- Jemand fragt nach allen Laeufen: die eigenen noch einmal, samt Besetzung.
function Dungeonhub:OnRequest(sender)
    if comm() and comm():IsSelf(sender) then return end
    for _, run in pairs(store() and store().own or {}) do
        self:Send(run)
        self:SendMembers(run)
    end
end

function Dungeonhub:Request()
    if not comm() or not Compat.IsInGuild() then return false end
    local jetzt = Util.Now()
    if self.lastRequest and jetzt - self.lastRequest < self.REQUEST_COOLDOWN then return false end
    self.lastRequest = jetzt
    return comm():Send("DREQ", {}, "GUILD", nil, true) and true or false
end

-- ================================================================== Lesen ----

--- Wirft weg, was abgelaufen ist: 24 Stunden nach dem Eintragen, oder eine
--- Stunde nach der Startzeit — ein Lauf, der laengst laeuft, sucht niemanden.
function Dungeonhub:Prune()
    local now = Util.Now()
    local db = store()
    for id, run in pairs(self.runs) do
        if now - (run.ts or 0) > self.TTL or now - (run.at or 0) > self.GRACE then
            self.runs[id] = nil
            if db and db.own[id] then db.own[id] = nil end
        end
    end
end

--- Alle Laeufe, nach Startzeit.
function Dungeonhub:List()
    self:Prune()
    local out = {}
    for _, run in pairs(self.runs) do out[#out + 1] = run end
    table.sort(out, function(a, b)
        if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) < (b.at or 0) end
        return (a.ts or 0) < (b.ts or 0)
    end)
    return out
end

function Dungeonhub:Get(id) return id and self.runs[id] or nil end

--- Einladungen des Spiels an alle Mitglieder ausser mir — aus dem Klick
--- des Leiters heraus.
function Dungeonhub:InviteAll(run)
    if not run then return 0 end
    local me = ownName()
    local n = 0
    for name in pairs(run.members or {}) do
        if name ~= me and Compat.InviteUnit(name) then n = n + 1 end
    end
    return n
end

-- ================================================================== Start ----

function Dungeonhub:OnEnable()
    local Comm = comm()
    if Comm then
        Comm:On("DHUB", function(sender, fields) Dungeonhub:OnPost(sender, fields) end, "Dungeonhub")
        Comm:On("DHUBX", function(sender, fields) Dungeonhub:OnWithdraw(sender, fields) end, "Dungeonhub")
        Comm:On("DJOIN", function(sender, fields) Dungeonhub:OnJoin(sender, fields) end, "Dungeonhub")
        Comm:On("DMEMB", function(sender, fields) Dungeonhub:OnMembers(sender, fields) end, "Dungeonhub")
        Comm:On("DREQ", function(sender) Dungeonhub:OnRequest(sender) end, "Dungeonhub")
    end

    -- Eigene Laeufe aus der Datei: zurueck ins Gedaechtnis, abgelaufene weg.
    local db = store()
    for id, run in pairs(db and db.own or {}) do
        run.own = true
        run.members = run.members or {}
        self.runs[id] = run
    end
    self:Prune()

    -- Nach dem Start: die eigenen noch einmal, und die anderen fragen.
    if type(Compat.After) == "function" then
        Compat.After(7, function()
            for _, run in pairs(db and db.own or {}) do
                Dungeonhub:Send(run)
                Dungeonhub:SendMembers(run)
            end
            Dungeonhub:Request()
        end)
    end
end
