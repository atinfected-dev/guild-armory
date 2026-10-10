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
      DHUB   Feld 7: "1" = steht in Discord, "2" = dazu Marken fuer den Bot
             (seit 0.1.31; aeltere Clients lassen es weg)
      DHUBR  wie DHUB, dazu leader (Feld 7), Discord in Feld 8                  Weitergabe durch einen Dritten
      DMEMBR id, Besetzung, mts, leader              Weitergabe der Besetzung
      DHUBXR id, leader                              Weitergabe eines Grabsteins
    DER LEITER IST DIE QUELLE DER BESETZUNG: Er antwortet auf jeden Beitritt
    mit DMEMB (mit Stempel mts), und wer spaeter einloggt, bekommt sie auf
    DREQ. Ist der Leiter nicht da, geben die anderen weiter, was sie von ihm
    haben (02.10.2026) — der Stempel sagt, was juenger ist.

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

-- "MORGEN 20:00" UM 13:45 GING NICHT (Bild vom 05.10.2026): Das Formular
-- bietet "Morgen" an, die Grenze lag aber bei 24 Stunden — morgen 20:00 sind
-- dann 30 Stunden. Und ein Lauf verschwand 24 Stunden nach dem Eintragen,
-- also womoeglich vor seinem Start. Jetzt: Startzeit bis morgen 23:59 (hoechstens
-- 48 Stunden voraus); ein Lauf lebt bis eine Stunde nach seinem Start. TTL
-- bleibt nur als Sicherheitsdeckel fuer Altes, das nie endet.
Dungeonhub.HORIZON = 48 * 3600      -- wie weit im Voraus die Startzeit liegen darf
Dungeonhub.GRACE = 3600             -- so weit darf die Startzeit zurueckliegen
Dungeonhub.TTL = Dungeonhub.HORIZON + Dungeonhub.GRACE  -- Deckel ab dem Eintragen
Dungeonhub.NOTE_LEN = 60
Dungeonhub.DUNGEON_LEN = 30
Dungeonhub.REQUEST_COOLDOWN = 30
Dungeonhub.SEEN_TTL = 20            -- Sekunden: so lange gilt "den Lauf hoerte ich eben"
Dungeonhub.RELAY_DELAY = 6          -- Sekunden: Weitergabe fremder Laeufe zufaellig verzoegert

--- Die Rollen, in der Reihenfolge der Plaetze, und wie viele es je gibt.
Dungeonhub.ROLES = { "TANK", "HEAL", "DPS" }
Dungeonhub.SLOTS = { TANK = 1, HEAL = 1, DPS = 3 }

--- Die Instanzen von WoW: Forever, in der Reihenfolge der Stufen — die
--- neuen wie die klassischen, Fluegel einzeln, wie die Karte von
--- mobalytics.gg sie fuehrt (Stand 26.09.2026; die Beta oeffnet sie nach
--- und nach). Was der Client selbst im Kompendium nennt, steht davor
--- (Dungeons()); was hier fehlt, tippt man ein.
Dungeonhub.DUNGEONS = {
    "Ragefire Chasm", "Hall of Thanes", "Ruins of Lordaeron", "Wailing Caverns",
    "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade",
    "Excavation Site", "City of Dalaran", "Gnomeregan", "Razorfen Kraul",
    "Scarlet Monastery Graveyard", "Scarlet Monastery Library",
    "The Drowned City", "Scarlet Monastery Armory", "Razorfen Downs",
    "Scarlet Monastery Cathedral", "Krol'dok", "Uldaman", "Zul'Farrak",
    "Maraudon", "Alcaz Prison", "The Temple of Atal'Hakkar", "Blackrock Depths",
    "Dire Maul East", "Lower Blackrock Spire", "Blackmaw Hold",
    "Dire Maul North", "Dire Maul West", "Scholomance", "Shaper's Terrace",
    "Stratholme Main Gate", "Stratholme Service Gate", "Upper Blackrock Spire",
}

--- Die Stufen dazu, fuer die Liste — nicht fuer die Nachricht.
Dungeonhub.LEVELS = {
    ["Ragefire Chasm"] = "13–18", ["Hall of Thanes"] = "13–18", ["Ruins of Lordaeron"] = "15–20",
    ["Wailing Caverns"] = "17–24", ["The Deadmines"] = "17–26", ["Shadowfang Keep"] = "22–30",
    ["Blackfathom Deeps"] = "24–32", ["The Stockade"] = "24–32", ["Excavation Site"] = "24–29",
    ["City of Dalaran"] = "28–33", ["Gnomeregan"] = "29–38", ["Razorfen Kraul"] = "29–38",
    ["Scarlet Monastery Graveyard"] = "30–38", ["Scarlet Monastery Library"] = "33–41",
    ["The Drowned City"] = "35–40", ["Scarlet Monastery Armory"] = "36–44", ["Razorfen Downs"] = "37–46",
    ["Scarlet Monastery Cathedral"] = "38–46", ["Krol'dok"] = "40–45", ["Uldaman"] = "41–51",
    ["Zul'Farrak"] = "44–54", ["Maraudon"] = "46–55", ["Alcaz Prison"] = "48–53",
    ["The Temple of Atal'Hakkar"] = "50–60", ["Blackrock Depths"] = "52–60", ["Dire Maul East"] = "54–60",
    ["Lower Blackrock Spire"] = "55–60", ["Blackmaw Hold"] = "55–60", ["Dire Maul North"] = "56–60",
    ["Dire Maul West"] = "56–60", ["Scholomance"] = "58–60", ["Shaper's Terrace"] = "58–60",
    ["Stratholme Main Gate"] = "58–60", ["Stratholme Service Gate"] = "58–60", ["Upper Blackrock Spire"] = "59–60",
}

Dungeonhub.runs = {}

--- Die Liste zum Auswaehlen: was der Client im Kompendium hat, dahinter
--- die feste Liste fuer alles, was er nicht nennt. Eindeutig, in dieser
--- Reihenfolge. Frei eintippen geht daneben immer.
function Dungeonhub:Dungeons()
    local out, seen = {}, {}
    local measured = type(Compat.GetDungeonNames) == "function" and Compat.GetDungeonNames() or nil
    for _, list in ipairs({ measured or {}, self.DUNGEONS }) do
        for _, name in ipairs(list) do
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out, measured ~= nil
end

local function store()
    local account = GA.Core.Database and GA.Core.Database.account
    if not account then return nil end
    account.dungeonhub = account.dungeonhub or { own = {} }
    account.dungeonhub.own = account.dungeonhub.own or {}
    account.dungeonhub.known = account.dungeonhub.known or {}   -- fremde Laeufe, fuer die Weitergabe
    account.dungeonhub.gone = account.dungeonhub.gone or {}     -- Grabsteine: zurueckgenommene Laeufe
    account.dungeonhub.announced = account.dungeonhub.announced or {} -- schon gemeldet: id -> Zeit
    return account.dungeonhub
end

local function comm() return GA.Core.Comm end

--- WEITERGABE (02.10.2026): Ein Lauf lebte nur beim Leiter und bei denen,
--- die ihn direkt hoerten. Wer spaeter einloggte, fragte — und bekam nur
--- Antwort, wenn der Leiter gerade da war. Jetzt gibt JEDER Client weiter,
--- was er kennt: fremde Laeufe wandern in die Datei, auf eine Anfrage
--- gehen sie als DHUBR/DMEMBR hinaus, mit dem Leiter als Feld, weil der
--- Absender dann nicht der Leiter ist. Zurueckgenommene Laeufe bleiben
--- als Grabstein, damit eine Weitergabe sie nicht wiederbelebt.
---
--- Wer einen Lauf eben erst hoerte, schickt ihn auf eine Anfrage nicht
--- noch einmal — sonst antworten dreissig Clients mit demselben Lauf.
local seen = {}
local function markSeen(id) seen[id] = Util.Now() end
local function seenLately(id)
    local at = seen[id]
    return at ~= nil and Util.Now() - at <= Dungeonhub.SEEN_TTL
end
local function remember(run)
    local db = store()
    if db and not run.own then db.known[run.id] = run end
end
local function forget(id, leader)
    local db = store()
    if not db then return end
    db.known[id] = nil
    db.gone[id] = { leader = leader, ts = Util.Now() }
end
local function isGone(id)
    local db = store()
    return db ~= nil and db.gone[id] ~= nil
end

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

--- Der eigene Charakterdatensatz — dort steht die gesetzte Kampfrolle.
local function myCharacter()
    local identity = Compat.GetPlayerIdentity()
    local account = GA.Core.Database and GA.Core.Database.account
    local characters = account and account.characters
    return identity.guid and characters and characters[identity.guid] or nil
end

--- EINE GESPEICHERTE ROLLE, NICHT ZWEI. Bis 0.1.42 merkte sich der
--- Dungeonhub die zuletzt gewaehlte Rolle fuer sich (lastRole), und
--- "Zusammen" fuehrte die gesetzte Kampfrolle daneben. Jetzt gilt die
--- gesetzte: Wer noch keine hat, bekommt mit der ersten Wahl im Dungeonhub
--- eine — mit allem, was daran haengt (Vorschlag in "Zusammen", Sync an
--- die Gilde). Wer eine hat, behaelt sie: Ein Lauf als Zweitrolle macht
--- nicht die Hauptrolle zur Zweitrolle.
local function rememberRole(role)
    local me = myCharacter()
    if not me or me.combatRole then return end
    if GA.Modules.Together and GA.Modules.Together.SetMyRole then
        GA.Modules.Together:SetMyRole(role)
    else
        me.combatRole = role
    end
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
function Dungeonhub.ParseTime(text)
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
--- @param discord boolean|nil  auch in Discord ankuendigen (Variante 1, 03.10.2026)
function Dungeonhub:Post(dungeon, at, note, role, discord)
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
        mts = now,
    }
    run.discord = discord and true or nil
    run.discordBot = discord and GA.Core.Config and GA.Core.Config:Get("discordBot") and true or nil
    db.own[run.id] = run
    rememberRole(role)
    self.runs[run.id] = run
    self:Send(run)
    self:SendMembers(run)
    if run.discord then self:AnnounceDiscord(run, "new") end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "post", run)
    return run
end

function Dungeonhub:Send(run)
    if not comm() then return false end
    local leaderRole = run.members and run.members[run.leader] and run.members[run.leader].role or "DPS"
    return comm():Send("DHUB", { run.id, run.dungeon, run.at, run.note or "", run.ts, leaderRole, Dungeonhub.DiscordFlag(run) },
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
    run.mts = run.mts or Util.Now()
    return comm():Send("DMEMB", { run.id, self.EncodeMembers(run), tostring(run.mts) }, "GUILD", nil, true) and true or false
end

--- Weitergabe eines fremden Laufs samt Besetzung: wie DHUB und DMEMB,
--- nur mit dem Leiter als letztem Feld.
function Dungeonhub:Relay(run)
    if not comm() or run.own then return false end
    local leaderRole = run.members and run.members[run.leader] and run.members[run.leader].role or "DPS"
    comm():Send("DHUBR", { run.id, run.dungeon, run.at, run.note or "", run.ts, leaderRole, run.leader, Dungeonhub.DiscordFlag(run) }, "GUILD", nil, true)
    comm():Send("DMEMBR", { run.id, self.EncodeMembers(run), tostring(run.mts or 0), run.leader }, "GUILD", nil, true)
    return true
end

--- Nimmt einen eigenen Lauf zurueck.
function Dungeonhub:Withdraw(id, quiet)
    local db = store()
    if not db or not db.own[id] then return false end
    local run = db.own[id]
    if run and run.discord and run.discordSent then self:AnnounceDiscord(run, "cancel") end
    db.own[id] = nil
    self.runs[id] = nil
    forget(id, ownName())
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
    rememberRole(role)
    if comm() then comm():Send("DJOIN", { id, role }, "GUILD", nil, true) end
    if run.own then run.mts = Util.Now() self:SendMembers(run) end
    self:AnnounceDiscord(run, "join", me, role)
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
    self:AnnounceDiscord(run, "leave", me)
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "leave", run)
    return true
end

-- ================================================================ Leiter ---
--
-- DER LEITER TRAEGT EIN (08.10.2026): Wer per Discord oder Stimme zugesagt
-- hat, aber im Spiel nicht klickt, steht sonst nirgends. Nur im eigenen
-- Lauf, nur in einen freien Platz; die Besetzung geht wie bei jedem
-- Beitritt an die Gilde (DMEMB) und nach Discord.

--- @return boolean ok, string|nil grund ("notleader" | "noname" | "role" | "full")
function Dungeonhub:AddMember(id, name, role)
    local run = self.runs[id]
    if not run or not run.own then return false, "notleader" end
    name = Util.ShortName(Util.Trim(name or "") or "")
    if name == "" then return false, "noname" end
    if not validRole(role) then return false, "role" end
    local vorher = run.members[name]
    if vorher and vorher.role == role then return true end
    if self:Count(run, role) >= self.SLOTS[role] then return false, "full" end
    -- Von Hand getippt: Eine bekannte Klasse, die die Rolle nicht spielen
    -- kann, kommt nicht hinein (11.10.2026). Unbekannte Namen schon — der
    -- Leiter weiss, wen er meint.
    local klasse = klasseVon(name)
    if klasse and not Dungeonhub.CanPlay(klasse, role) then return false, "cantrole" end
    run.members[name] = { role = role, class = klasse, ts = Util.Now(), byLeader = true }
    run.mts = Util.Now()
    self:SendMembers(run)
    self:AnnounceDiscord(run, "join", name, role)
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "join", run)
    return true
end

--- Der Leiter nimmt jemanden heraus — nicht sich selbst.
--- @return boolean ok, string|nil grund ("notleader" | "leader" | "notin")
function Dungeonhub:RemoveMember(id, name)
    local run = self.runs[id]
    if not run or not run.own then return false, "notleader" end
    name = Util.ShortName(name or "")
    if name == run.leader then return false, "leader" end
    if not run.members[name] then return false, "notin" end
    run.members[name] = nil
    run.mts = Util.Now()
    self:SendMembers(run)
    self:AnnounceDiscord(run, "leave", name)
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "leave", run)
    return true
end

--- Wer in Frage kommt: Gildenmitglieder, online zuerst, ohne die, die
--- schon drin sind, und ohne mich.
--- Kann diese Klasse die Rolle spielen? (11.10.2026: "wenn ich einen Tank
--- per Hand eintragen will, sollen nur Tanks angezeigt werden, bei Heal nur
--- Klassen, die heilen koennen".) Dieselben Tabellen wie im Reiter
--- Together; Schaden kann jeder. Ohne bekannte Klasse: nein fuer Tank und
--- Heiler — raten hiesse hier, einen Magier als Tank vorzuschlagen.
local CAN = {
    TANK = { WARRIOR = true, DRUID = true, PALADIN = true },
    HEAL = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true },
}
function Dungeonhub.CanPlay(class, role)
    if role ~= "TANK" and role ~= "HEAL" then return true end
    local T = GA.Modules.Together
    local tabelle = (T and (role == "TANK" and T.CAN_TANK or T.CAN_HEAL)) or CAN[role]
    return class ~= nil and tabelle[string.upper(class)] == true
end

--- Wer sich eintragen laesst. Mit role (TANK/HEAL) nur, wer die Rolle
--- spielen kann; wer sie als Kampfrolle gesetzt hat, steht oben, dann wer
--- online ist, dann nach Name.
--- @param role string|nil
function Dungeonhub:Candidates(run, limit, role)
    local Guild = GA.Modules.Guild
    local characters = GA.Core.Database.account.characters or {}
    local out = {}
    local me = ownName()
    for _, m in ipairs(Guild and Guild.List and Guild:List() or {}) do
        local name = m.name and Util.ShortName(m.name)
        if name and name ~= me and not (run and run.members[name]) and Dungeonhub.CanPlay(m.class, role) then
            local character = m.guid and characters[m.guid]
            out[#out + 1] = { name = name, class = m.class, online = m.online and true or false, level = m.level,
                combatRole = character and character.combatRole or nil }
        end
    end
    table.sort(out, function(a, b)
        local am, bm = role ~= nil and a.combatRole == role, role ~= nil and b.combatRole == role
        if am ~= bm then return am end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
    return out
end

--- Die Rolle, die das Formular vorschlaegt: die gesetzte Kampfrolle.
--- Ein alter lastRole-Wert (bis 0.1.42) wird einmal uebernommen, dann
--- vergessen.
function Dungeonhub:LastRole()
    local me = myCharacter()
    if me and validRole(me.combatRole) then return me.combatRole end
    local db = store()
    local alt = db and db.lastRole
    if db then db.lastRole = nil end
    if validRole(alt) then rememberRole(alt) return alt end
    return "DPS"
end

-- ================================================================== Discord --
--
-- NUR IN EINE RICHTUNG (03.10.2026). Gemessen: Das Addon kann ueber den
-- Chattyp GUILD_DISCORD nach Discord schreiben, aber Discord-Text nicht lesen
-- (Communication/Discord). Jeder schreibt nur fuer sich selbst:
--   * der Leiter, wenn er den Lauf eintraegt ("new") und wenn er ihn absagt
--     ("cancel");
--   * wer beitritt oder die Rolle wechselt ("join") und wer geht ("leave"),
--     mit den danach freien Plaetzen — oder "jetzt voll".
-- Ob ein Lauf in Discord steht, reist als Feld im DHUB mit (run.discord),
-- damit die anderen Clients wissen, dass ihre Zeile dorthin gehoert.

--- Freie Plaetze als Text: "Tank, Heiler, 2x Schaden" — oder nil, wenn voll.
function Dungeonhub:FreeText(run)
    local teile = {}
    for _, role in ipairs(self.ROLES) do
        local frei = self.SLOTS[role] - self:Count(run, role)
        local name = L["DH_ROLE_" .. role] or role
        if frei == 1 then teile[#teile + 1] = name
        elseif frei > 1 then teile[#teile + 1] = string.format(L.DH_DC_COUNT, frei, name) end
    end
    if #teile == 0 then return nil end
    return table.concat(teile, ", ")
end

--- Die Zeile fuer Discord.
--- @param kind string "new" | "join" | "leave" | "cancel"
--- @param who string|nil  wer beitritt oder geht
--- @param role string|nil  mit welcher Rolle
function Dungeonhub:DiscordLine(run, kind, who, role)
    local wann = date("%H:%M", run.at or 0)
    local heute = date("%Y-%m-%d", Util.Now()) == date("%Y-%m-%d", run.at or 0)
    local tag = heute and L.DH_DC_TODAY or L.DH_DC_TOMORROW
    local dungeon = run.dungeon or "?"
    local frei = self:FreeText(run)
    local rest = frei and string.format(L.DH_DC_OPEN, frei) or L.DH_DC_NOW_FULL
    local text
    if kind == "cancel" then
        text = string.format(L.DH_DC_CANCEL, dungeon, tag, wann)
    elseif kind == "new" then
        local note = run.note and run.note ~= "" and (" - " .. run.note) or ""
        text = string.format(L.DH_DC_NEW, dungeon, tag, wann, run.leader or "?", rest, note)
    elseif kind == "leave" then
        text = string.format(L.DH_DC_LEAVE, who or "?", dungeon, tag, wann, rest)
    else
        local rolle = L["DH_ROLE_" .. tostring(role)] or tostring(role)
        text = string.format(L.DH_DC_JOIN, who or "?", rolle, dungeon, tag, wann, rest)
    end
    if run.discordBot then
        local tag = self:DiscordTag(run, kind, who, role)
        -- DIE MARKE ZUERST, UND UNTER DER GRENZE DER BRUECKE (09.10.2026).
        -- Gemessen mit einer vollen Gruppe: 254 Zeichen gingen hinaus, die
        -- Discord-Bruecke des Spiels gab 246 weiter und haengte "..." an —
        -- das "]" der Marke fehlte, der Bot las nichts, und der Anmelder
        -- blieb beim Stand davor stehen. Jetzt steht die Marke vorn (wird
        -- etwas abgeschnitten, dann der lesbare Teil, den der Bot ohnehin
        -- loescht) und die ganze Zeile bleibt unter DISCORD_MAX.
        local platz = self.DISCORD_MAX - #tag - 1
        if #text > platz then text = string.sub(text, 1, math.max(platz - 3, 0)) .. "..." end
        text = tag .. " " .. text
    end
    -- Kein | im Text: Der Chat liest es als Steuerzeichen.
    return (string.gsub(text, "|", "/"))
end

Dungeonhub.CHAT_MAX = 255
--- Was die Discord-Bruecke des Spiels unversehrt weitergibt: gemessen 246
--- (09.10.2026), mit Luft darunter.
Dungeonhub.DISCORD_MAX = 236
local KIND_LETTER = { new = "n", join = "j", leave = "l", cancel = "x" }

--- Das Feld 7 im DHUB: "0" nicht in Discord, "1" lesbar, "2" mit Marken.
function Dungeonhub.DiscordFlag(run)
    if not run.discord then return "0" end
    return run.discordBot and "2" or "1"
end

--- Die Maschinenmarke fuer den Bot (Format 2 seit 0.1.32):
---   [ga2 <art> <id> <start> <leiter> <besetzung> <dungeon> <notiz>]
--- art n/j/l/x; besetzung "TANK:Name.KLASSE;HEAL:;DPS:Name.KLASSE,…".
--- In Namen und Dungeon stehen Unterstriche fuer Leerzeichen, so trennt das
--- Leerzeichen die Felder eindeutig; die Notiz ist der Rest bis "]".
---
--- WARUM FORMAT 2 (04.10.2026): Format 1 (0.1.31) schrieb die Namen wie sie
--- sind — und auf WoW: Forever haben Namen Leerzeichen ("Total Tumult").
--- Der Bot las dann "Total" als Schaden und "Tumult" als Dungeon. Die
--- Klasse reist jetzt mit, damit der Anmelder Klassensymbole zeigen kann.
local function tagName(name)
    return (string.gsub(tostring(name or "?"), "[%s%]%[;:,%.]", "_"))
end

function Dungeonhub:TagMembers(run)
    local teile = {}
    for _, role in ipairs(self.ROLES) do
        local namen = {}
        for name, member in pairs(run.members or {}) do
            if member.role == role then
                local cls = member.class or klasseVon(name)
                namen[#namen + 1] = tagName(name) .. (cls and ("." .. cls) or "")
            end
        end
        table.sort(namen)
        teile[#teile + 1] = role .. ":" .. table.concat(namen, ",")
    end
    return table.concat(teile, ";")
end

function Dungeonhub:DiscordTag(run, kind, who, role)
    local dungeon = string.gsub(run.dungeon or "?", "[%s%]]", "_")
    local note = string.gsub(run.note or "", "[%]%[]", "")
    local tag = string.format("[ga2 %s %s %d %s %s %s", KIND_LETTER[kind] or "j", tostring(run.id),
        tonumber(run.at) or 0, tagName(run.leader), self:TagMembers(run), dungeon)
    if note ~= "" then tag = tag .. " " .. note end
    return tag .. "]"
end

-- ================================================================ Import ----
--
-- AUS DISCORD ZURUECK INS SPIEL (08.10.2026). Discord -> Spiel gibt es
-- nicht, aber Discord -> Mensch -> Spiel: Der Bot schreibt ueber jeden
-- Anmelder die Marke des aktuellen Stands, und wer den Lauf nicht sieht —
-- weil sein Client nicht da war, als er angekuendigt wurde —, fuegt sie
-- hier ein. Dasselbe Format 2, das AnnounceDiscord hinausschreibt.

--- Alle Marken in einem Text.
--- @return table { { id, at, leader, dungeon, note, members = { [name] = { role, class } } } }
function Dungeonhub.ParseTags(text)
    local out = {}
    for kind, id, at, leader, members, rest in string.gmatch(tostring(text or ""),
        "%[ga2 ([njlx]) (%S+) (%d+) (%S+) (TANK:[^;%s%]]*;HEAL:[^;%s%]]*;DPS:[^;%s%]]*) ([^%]]*)%]") do
        local dungeon, note = string.match(rest, "^(%S+)%s*(.-)$")
        local tag = { kind = kind, id = id, at = tonumber(at), leader = (string.gsub(leader, "_", " ")),
                      dungeon = (string.gsub(dungeon or "?", "_", " ")), note = note or "", members = {} }
        for teil in string.gmatch(members, "[^;]+") do
            local role, namen = teil:match("^(%u+):(.*)$")
            if validRole(role) then
                for item in string.gmatch(namen, "[^,]+") do
                    local raw, cls = item:match("^([^%.]+)%.?(%u*)$")
                    local name = (string.gsub(raw or item, "_", " "))
                    tag.members[name] = { role = role, class = cls ~= "" and cls or nil }
                end
            end
        end
        out[#out + 1] = tag
    end
    return out
end

--- Uebernimmt Laeufe aus eingefuegten Marken. Ein eigener Lauf (Leiter =
--- ich) wird wieder meiner; ein fremder kommt als weitergegebener herein
--- und geht als Weitergabe an die Gilde, damit auch die anderen ihn sehen.
--- @return number uebernommen, number uebersprungen
function Dungeonhub:ImportTags(text)
    local tags = self.ParseTags(text)
    local now = Util.Now()
    local me = ownName()
    local db = store()
    local taken, skipped = 0, 0
    for _, tag in ipairs(tags) do
        local at = tag.at or 0
        local alt = self.runs[tag.id]
        if tag.kind == "x" or at < now - self.GRACE or at > now + self.HORIZON or not db then
            skipped = skipped + 1
        elseif alt and (alt.mts or alt.ts or 0) >= now - 60 then
            skipped = skipped + 1          -- gerade erst gehoert, nichts zu tun
        else
            local members = {}
            local order = 0
            for name, m in pairs(tag.members) do
                order = order + 1
                members[name] = { role = m.role, class = m.class or klasseVon(name), ts = at - 1000 + order }
            end
            local leaderRole = members[tag.leader] and members[tag.leader].role or "DPS"
            members[tag.leader] = members[tag.leader] or { role = leaderRole, class = klasseVon(tag.leader), ts = at - 1000 }
            local run = {
                id = tag.id, dungeon = kuerzen(tag.dungeon, self.DUNGEON_LEN), at = at,
                note = kuerzen(tag.note, self.NOTE_LEN), ts = now, mts = now,
                leader = tag.leader, class = members[tag.leader].class,
                members = members, discord = true, discordBot = true,
            }
            if me and tag.leader == me then
                run.own = true
                db.own[run.id] = run
                self.runs[run.id] = run
                self:Send(run)
                self:SendMembers(run)
            else
                run.own = false
                self.runs[run.id] = run
                markSeen(run.id)
                remember(run)
                self:Relay(run)
            end
            db.announced[run.id] = db.announced[run.id] or now
            taken = taken + 1
            GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", alt and "update" or "new", run)
        end
    end
    return taken, skipped
end

--- Schreibt die eigene Zeile nach Discord, wenn der Lauf dort angekuendigt
--- ist und die Gilde verbunden ist.
--- @return boolean gesendet
function Dungeonhub:AnnounceDiscord(run, kind, who, role)
    if not run or not run.discord then return false end
    if Compat.IsDiscordBridgeEnabled and Compat.IsDiscordBridgeEnabled() == false then return false end
    if type(Compat.SendChatMessage) ~= "function" then return false end
    local line = self:DiscordLine(run, kind, who, role)
    if not Compat.SendChatMessage(line, "GUILD_DISCORD") then return false end
    run.discordSent = Util.Now()
    return true
end

--- Die letzte Wahl im Formular, und ob es Discord hier ueberhaupt gibt.
--- @return boolean|nil  nil = keine Verbindung, Haken verstecken
function Dungeonhub:DiscordDefault()
    if not Compat.IsDiscordBridgeEnabled or Compat.IsDiscordBridgeEnabled() ~= true then return nil end
    local db = store()
    if db and db.discordChoice ~= nil then return db.discordChoice end
    return true
end

function Dungeonhub:SetDiscordDefault(on)
    local db = store()
    if db then db.discordChoice = on and true or false end
end

-- ================================================================== Fremde ---

--- @param relayedLeader string|nil  bei einer Weitergabe der eigentliche Leiter
function Dungeonhub:OnPost(sender, fields, relayedLeader)
    if comm() and comm():IsSelf(sender) then return end
    local id, dungeon = fields[1], fields[2]
    local at, ts = tonumber(fields[3]), tonumber(fields[5])
    if type(id) ~= "string" or id == "" or type(dungeon) ~= "string" or dungeon == "" or not at or not ts then return end
    if relayedLeader then
        -- Ein weitergegebener Lauf: nicht, wenn er zurueckgenommen wurde,
        -- nicht mein eigener, und nichts Aelteres ueber Bekanntes.
        if isGone(id) or relayedLeader == ownName() then return end
        local alt = self.runs[id]
        if alt and (alt.ts or 0) >= ts then markSeen(id) return end
    end
    -- Aelter als seine Lebensdauer oder weit in der Zukunft: kein Lauf.
    -- Zwei Uhren weichen ab; eine Stunde ist Luft.
    local now = Util.Now()
    if ts > now + 3600 or now - ts > self.TTL then return end
    -- Laengst gestartet ist abgelaufen — auch, wenn ihn ein Client weitergibt,
    -- der noch nicht aufgeraeumt hat. Ohne diese Pruefung kam ein Lauf, den
    -- Prune eine Stunde nach Start loeschte, mit der naechsten Weitergabe als
    -- NEU zurueck und meldete sich wieder (gesehen 03.10.2026).
    if at < now - self.GRACE then return end
    local leader = relayedLeader or Util.ShortName(sender)
    local alt = self.runs[id]
    local run = {
        id = id, dungeon = kuerzen(dungeon, self.DUNGEON_LEN), at = at,
        note = kuerzen(fields[4], self.NOTE_LEN), ts = ts,
        leader = leader, class = klasseVon(leader), own = false,
        members = alt and alt.members or {}, mts = alt and alt.mts or nil,
    }
    local flag = fields[relayedLeader and 8 or 7]
    run.discord = (flag == "1" or flag == "2") or nil
    run.discordBot = flag == "2" or nil
    if not run.members[leader] then
        local role = validRole(fields[6]) and fields[6] or "DPS"
        run.members[leader] = { role = role, class = run.class, ts = ts }
    end
    self.runs[id] = run
    markSeen(id)
    remember(run)
    -- NEU nur einmal je Lauf und Client, auch ueber einen Reload hinweg:
    -- Die Meldung haengt an "new".
    local db = store()
    local gemeldet = db and db.announced[id]
    if db then db.announced[id] = now end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", (alt or gemeldet) and "update" or "new", run)
end

function Dungeonhub:OnRelayPost(sender, fields)
    local leader = fields[7]
    if type(leader) ~= "string" or leader == "" then return end
    self:OnPost(sender, fields, leader)
end

--- @param relayedLeader string|nil  bei einer Weitergabe der eigentliche Leiter
function Dungeonhub:OnWithdraw(sender, fields, relayedLeader)
    local id = fields[1] or ""
    local run = self.runs[id]
    local leader = relayedLeader or Util.ShortName(sender)
    if not run then
        -- Nichts zu entfernen, aber der Grabstein verhindert, dass eine
        -- spaetere Weitergabe den Lauf zurueckbringt.
        if relayedLeader and id ~= "" and not isGone(id) then forget(id, leader) end
        return
    end
    if run.own or leader ~= run.leader then return end
    self.runs[id] = nil
    forget(id, leader)
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "withdraw", id)
end

function Dungeonhub:OnRelayWithdraw(sender, fields)
    local leader = fields[2]
    if type(leader) ~= "string" or leader == "" then return end
    self:OnWithdraw(sender, fields, leader)
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
    if run.own then run.mts = Util.Now() self:SendMembers(run) else remember(run) end
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "join", run)
end

--- @param relayedLeader string|nil  bei einer Weitergabe der eigentliche Leiter
function Dungeonhub:OnMembers(sender, fields, relayedLeader)
    if comm() and comm():IsSelf(sender) then return end
    local run = self.runs[fields[1] or ""]
    if not run or run.own then return end
    local leader = relayedLeader or Util.ShortName(sender)
    if leader ~= run.leader then return end
    local mts = tonumber(fields[3])
    if relayedLeader then
        -- Eine weitergegebene Besetzung zaehlt nur, wenn sie juenger ist
        -- als die, die ich habe: Der Stempel des Leiters entscheidet.
        if not mts or mts <= (run.mts or 0) then markSeen(run.id) return end
    end
    run.members = self.DecodeMembers(fields[2], klasseVon)
    run.mts = mts or Util.Now()
    if not run.members[run.leader] then
        run.members[run.leader] = { role = "DPS", class = run.class, ts = 0 }
    end
    markSeen(run.id)
    remember(run)
    GA.Core.Callbacks:Fire("DUNGEONHUB_CHANGED", "members", run)
end

function Dungeonhub:OnRelayMembers(sender, fields)
    local leader = fields[4]
    if type(leader) ~= "string" or leader == "" then return end
    self:OnMembers(sender, fields, leader)
end

--- Jemand fragt nach allen Laeufen: die eigenen noch einmal, samt Besetzung.
--- Jemand fragt: die eigenen sofort, die fremden nach einer kurzen
--- zufaelligen Pause — und nur die, die in der Zwischenzeit kein anderer
--- schon geschickt hat. Grabsteine gehen mit, damit der Fragende nichts
--- Zurueckgenommenes von einem Dritten annimmt.
--- @return number angekuendigt (fremde Laeufe plus Grabsteine)
function Dungeonhub:OnRequest(sender)
    if comm() and comm():IsSelf(sender) then return 0 end
    -- Erst aufraeumen: Weitergegeben wird nur, was noch gilt.
    self:Prune()
    local db = store()
    for _, run in pairs(db and db.own or {}) do
        self:Send(run)
        self:SendMembers(run)
    end
    local pending, gone = {}, {}
    for id, run in pairs(self.runs) do
        if not run.own and not seenLately(id) then pending[#pending + 1] = run end
    end
    for id, g in pairs(db and db.gone or {}) do gone[#gone + 1] = { id = id, leader = g.leader or "" } end
    if #pending + #gone == 0 then return 0 end
    local function relay()
        for _, run in ipairs(pending) do
            if self.runs[run.id] and not seenLately(run.id) then self:Relay(run) end
        end
        if comm() then
            for _, g in ipairs(gone) do comm():Send("DHUBXR", { g.id, g.leader }, "GUILD", nil, true) end
        end
    end
    if type(Compat.After) == "function" then
        Compat.After(math.random() * self.RELAY_DELAY, relay)
    else
        relay()
    end
    return #pending + #gone
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
            if db and db.known[id] then db.known[id] = nil end
        end
    end
    if db then
        for id, run in pairs(db.known) do
            if now - (run.ts or 0) > self.TTL or now - (run.at or 0) > self.GRACE then db.known[id] = nil end
        end
        for id, g in pairs(db.gone) do
            if now - (g.ts or 0) > self.TTL then db.gone[id] = nil end
        end
        for id, ts in pairs(db.announced) do
            if now - (ts or 0) > self.TTL + self.GRACE then db.announced[id] = nil end
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

--- Laedt alle Mitglieder eines Laufs ein — ueber Guild:Invite, die EINE
--- Einladen-Funktion (Offline-Filter und Rueckmeldung dort).
--- @return number eingeladen, table offline (Namen)
function Dungeonhub:InviteAll(run)
    if not run then return 0, {} end
    local names = {}
    for name in pairs(run.members or {}) do names[#names + 1] = name end
    table.sort(names)
    local result = GA.Modules.Guild:Invite(names)
    return result.invited, result.offline
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
        Comm:On("DHUBR", function(sender, fields) Dungeonhub:OnRelayPost(sender, fields) end, "Dungeonhub")
        Comm:On("DMEMBR", function(sender, fields) Dungeonhub:OnRelayMembers(sender, fields) end, "Dungeonhub")
        Comm:On("DHUBXR", function(sender, fields) Dungeonhub:OnRelayWithdraw(sender, fields) end, "Dungeonhub")
    end

    -- Eigene und bekannte fremde Laeufe aus der Datei: zurueck ins
    -- Gedaechtnis, abgelaufene weg.
    local db = store()
    for id, run in pairs(db and db.known or {}) do
        run.own = false
        run.members = run.members or {}
        self.runs[id] = run
    end
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
