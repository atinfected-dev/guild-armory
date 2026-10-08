--[[----------------------------------------------------------------------------
    Quests/Together — "Was koennen wir zusammen machen?" Kein UI.
    Gebaut 07.10.2026 auf Wunsch: ein Knopf, der aus Online-Mitgliedern,
    Stufen und Rollen Dungeon-Gruppen vorschlaegt, und dazu die Dungeon-,
    Elite- und Gruppenquests, die mehrere gerade offen haben.

    DREI QUELLEN, ALLE SCHON DA:
      Gildenroster   wer online ist, Stufe, Klasse — live vom Server
      Charaktere     die gesetzte Kampfrolle (Tank, Heiler, Schaden), gesynct
      Dungeonkatalog die Instanzen mit Stufenspannen (Quests/Dungeonhub)
    Dazu NEU: die Gruppenquests. Jeder teilt die Quests seines Logs, die das
    Spiel als Dungeon, Elite, Gruppe oder Schlachtzug kennzeichnet — nur
    diese, nur Kennung, Art und Titel. Was man allein erledigt, bleibt bei
    einem. Abschaltbar (Einstellungen › Daten).

    DIE ROLLE IST GESETZT ODER GERATEN, UND DAS STEHT DRAN. Wer seine Rolle
    hier unter "Zusammen" setzt — oder zuerst im Dungeonhub eine waehlt —,
    wird so gefuehrt. Wer nicht, wird nach
    Klasse eingeteilt: Krieger, Druide, Paladin koennen tanken; Priester,
    Druide, Schamane, Paladin koennen heilen; alle machen Schaden. Eine
    geratene Rolle traegt ein Fragezeichen — die Vorschlagsliste behauptet
    nichts, was sie nicht weiss.
------------------------------------------------------------------------------]]

local _, GA = ...

local Together = {}
GA.Modules.Together = Together

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

Together.ROLES = { "TANK", "HEAL", "DPS" }
Together.CAN_TANK = { WARRIOR = true, DRUID = true, PALADIN = true }
Together.CAN_HEAL = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
--- So weit darf jemand UEBER der Spanne liegen und noch mit.
Together.LEVEL_SLACK = 2
--- Welche Quests geteilt werden.
Together.GROUP_TAGS = { DUNGEON = true, ELITE = true, GROUP = true, RAID = true }
--- Hoechstens so viele je Charakter.
local QUEST_LIMIT = 15
--- Ruhe nach einer Aenderung des Questlogs, bevor gesendet wird.
local QUEST_SETTLE = 20

-- ================================================================ Rollen ----

--- Die eigene Kampfrolle setzen (nil = keine) — wird mit dem Charakter gesynct.
function Together:SetMyRole(role)
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    if not character then return false end
    if role ~= nil and role ~= "TANK" and role ~= "HEAL" and role ~= "DPS" then return false end
    if character.combatRole == role then return true end
    character.combatRole = role
    GA.Core.Callbacks:Fire("EQUIPMENT_UPDATED", identity.guid)
    if GA.Modules.Sync then GA.Modules.Sync:PublishCharacter("GUILD") end
    return true
end

--- Rolle eines Mitglieds: gesetzt, sonst nach Klasse geraten.
--- @param member table { class, combatRole? }
--- @return string|nil rolle, boolean geraten, table faehigkeiten { TANK, HEAL }
function Together.RoleOf(member)
    local class = member.class and string.upper(member.class) or nil
    local can = { TANK = class and Together.CAN_TANK[class] or false,
                  HEAL = class and Together.CAN_HEAL[class] or false, DPS = true }
    local set = member.combatRole
    if set == "TANK" or set == "HEAL" or set == "DPS" then return set, false, can end
    return nil, true, can
end

-- ================================================================ Dungeons --

--- "33–41" (oder "33-41") -> 33, 41
function Together.ParseLevels(text)
    local a, b = string.match(tostring(text or ""), "(%d+)%D+(%d+)")
    a, b = tonumber(a), tonumber(b)
    if not a or not b then return nil end
    if a > b then a, b = b, a end
    return a, b
end

--- Baut aus Mitgliedern eine Fuenfergruppe fuer einen Dungeon.
---
--- ERST, WER ES WEISS, DANN, WER ES KOENNTE. Gesetzte Rollen besetzen ihre
--- Plaetze zuerst. Freie Tank- und Heilerplaetze bekommen, wer die Klasse
--- dafuer hat, und zwar mit Fragezeichen. Wer uebrig ist, macht Schaden.
--- @param members table { { name, class, level, combatRole, me } }, schon nach Stufe gefiltert
--- @return table { TANK = eintrag|nil, HEAL = eintrag|nil, DPS = { eintraege } }, number besetzt
function Together.FillGroup(members)
    local slots = { TANK = nil, HEAL = nil, DPS = {} }
    local used = {}
    local function take(m, role, guessed)
        used[m] = true
        local entry = { name = m.name, class = m.class, level = m.level, me = m.me, guessed = guessed }
        if role == "DPS" then slots.DPS[#slots.DPS + 1] = entry else slots[role] = entry end
    end
    -- Hoehere Stufe zuerst: Wer hoeher ist, traegt die Gruppe eher.
    local sorted = {}
    for _, m in ipairs(members) do sorted[#sorted + 1] = m end
    table.sort(sorted, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
    end)
    -- 1. Gesetzte Rollen.
    for _, m in ipairs(sorted) do
        local role, guessed = Together.RoleOf(m)
        if not guessed then
            if role == "DPS" and #slots.DPS < 3 then take(m, "DPS", false)
            elseif role ~= "DPS" and not slots[role] then take(m, role, false) end
        end
    end
    -- 2. Geratene Tanks und Heiler.
    for _, role in ipairs({ "TANK", "HEAL" }) do
        if not slots[role] then
            for _, m in ipairs(sorted) do
                local _, guessed, can = Together.RoleOf(m)
                if not used[m] and guessed and can[role] then take(m, role, true) break end
            end
        end
    end
    -- 3. Der Rest macht Schaden.
    for _, m in ipairs(sorted) do
        if not used[m] and #slots.DPS < 3 then
            local role, guessed = Together.RoleOf(m)
            if guessed or role == "DPS" then take(m, "DPS", guessed) end
        end
    end
    local filled = (slots.TANK and 1 or 0) + (slots.HEAL and 1 or 0) + #slots.DPS
    return slots, filled
end

--- Vorschlaege: je Dungeon die beste Gruppe aus den Online-Mitgliedern.
--- @param members table { { name, class, level, combatRole, me } } alle online
--- @param dungeons table { name, ... }
--- @param levels table [name] = "33–41"
--- @return table sortiert: { { dungeon, min, max, slots, filled, candidates } }
function Together.Suggest(members, dungeons, levels)
    local out = {}
    for _, name in ipairs(dungeons or {}) do
        local lo, hi = Together.ParseLevels(levels and levels[name])
        if lo then
            local fitting = {}
            for _, m in ipairs(members or {}) do
                local level = tonumber(m.level)
                if level and level >= lo and level <= hi + Together.LEVEL_SLACK then fitting[#fitting + 1] = m end
            end
            if #fitting >= 2 then
                local slots, filled = Together.FillGroup(fitting)
                out[#out + 1] = { dungeon = name, min = lo, max = hi, slots = slots, filled = filled, candidates = #fitting }
            end
        end
    end
    -- Vollste Gruppe zuerst; bei Gleichstand, wo mehr passen; dann der
    -- hoehere Dungeon — wer es sich aussuchen kann, geht lieber dorthin,
    -- wo es noch etwas zu holen gibt.
    table.sort(out, function(a, b)
        if a.filled ~= b.filled then return a.filled > b.filled end
        if a.candidates ~= b.candidates then return a.candidates > b.candidates end
        return a.max > b.max
    end)
    return out
end

--- Die Online-Mitglieder als Kandidaten: Roster plus gesetzte Rolle aus der
--- Charakterdatenbank, der eigene Charakter mit `me`.
function Together:Candidates()
    local identity = Compat.GetPlayerIdentity()
    local characters = GA.Core.Database.account.characters
    local out, seenMe = {}, false
    for _, member in ipairs(GA.Modules.Guild and GA.Modules.Guild:List(true) or {}) do
        local character = member.guid and characters[member.guid]
        local me = identity.guid and member.guid == identity.guid
        if me then seenMe = true end
        out[#out + 1] = { name = member.name, class = member.class, level = member.level,
            combatRole = character and character.combatRole or nil, me = me or nil, guid = member.guid }
    end
    if not seenMe and identity.guid and identity.name then
        local mine = characters[identity.guid]
        out[#out + 1] = { name = Util.ShortName(identity.name), class = identity.class, level = identity.level,
            combatRole = mine and mine.combatRole or nil, me = true, guid = identity.guid }
    end
    return out
end

function Together:Suggestions()
    local Hub = GA.Modules.Dungeonhub
    if not Hub then return {} end
    return Together.Suggest(self:Candidates(), (Hub:Dungeons()), Hub.LEVELS)
end

-- ================================================================ Quests ----

--- Die eigenen Gruppenquests: { { id, tag, title } }
function Together:MyGroupQuests()
    local log = Compat.GetQuestLog()
    local out = {}
    for _, quest in ipairs(log or {}) do
        if quest.tag and Together.GROUP_TAGS[quest.tag] and quest.questID and not quest.complete then
            out[#out + 1] = { id = quest.questID, tag = quest.tag, title = quest.title }
            if #out >= QUEST_LIMIT then break end
        end
    end
    return out
end

local function clean(text, max)
    text = string.gsub(tostring(text or ""), "[|~;]", "")
    if #text > max then text = string.sub(text, 1, max) end
    return text
end

--- "id~TAG~Titel;id~TAG~Titel"
function Together.EncodeQuests(list)
    local parts = {}
    for _, q in ipairs(list or {}) do
        parts[#parts + 1] = tostring(q.id) .. "~" .. clean(q.tag, 10) .. "~" .. clean(q.title, 60)
    end
    return table.concat(parts, ";")
end

function Together.DecodeQuests(text)
    local out = {}
    for rec in string.gmatch(tostring(text or ""), "[^;]+") do
        local id, tag, title = string.match(rec, "^(%d+)~(%u+)~(.*)$")
        if id and Together.GROUP_TAGS[tag] then
            out[#out + 1] = { id = tonumber(id), tag = tag, title = title ~= "" and title or nil }
            if #out >= QUEST_LIMIT then break end
        end
    end
    return out
end

--- Schickt die eigenen Gruppenquests — nur, wenn sie sich geaendert haben.
function Together:PublishQuests(force)
    if GA.Core.Config:Get("shareGroupQuests") == false then return false end
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    if not character then return false end
    local list = self:MyGroupQuests()
    local text = Together.EncodeQuests(list)
    character.groupQuests = { list = list, ts = Util.Now() }
    if not force and text == self.lastSent then return false end
    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end
    self.lastSent = text
    -- Auch eine leere Liste geht hinaus: "nichts mehr offen" ist eine Auskunft.
    return Comm:SendBlob("GQ", identity.guid .. "|" .. text, "GUILD", nil, true) and true or false
end

function Together:OnQuests(sender, text)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local guid, rest = string.match(tostring(text or ""), "^([^|]+)|(.*)$")
    if not guid then return end
    local character = GA.Core.Database.account.characters[guid]
    -- Nur ein Charakter, den der Absender selbst ist: Der Server sagt, wer sendet.
    if not character or not character.name or not Util.SameCharacter(sender, character.name) then return end
    character.groupQuests = { list = Together.DecodeQuests(rest), ts = Util.Now(), from = sender }
    GA.Core.Callbacks:Fire("TOGETHER_CHANGED")
end

--- Quests, die mindestens zwei der Kandidaten gemeinsam haben.
--- @return table { { id, tag, title, holders = { namen } } } — meiste zuerst
function Together.SharedQuests(members, characters)
    local byQuest = {}
    for _, m in ipairs(members or {}) do
        local character = m.guid and characters[m.guid]
        for _, q in ipairs(character and character.groupQuests and character.groupQuests.list or {}) do
            local e = byQuest[q.id]
            if not e then
                e = { id = q.id, tag = q.tag, title = q.title, holders = {}, levels = {} }
                byQuest[q.id] = e
            end
            e.title = e.title or q.title
            e.holders[#e.holders + 1] = m.name
            e.levels[#e.levels + 1] = tonumber(m.level) or 0
        end
    end
    local out = {}
    for _, e in pairs(byQuest) do
        if #e.holders >= 2 then
            table.sort(e.holders)
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if #a.holders ~= #b.holders then return #a.holders > #b.holders end
        return (a.title or "") < (b.title or "")
    end)
    return out
end

function Together:Shared()
    return Together.SharedQuests(self:Candidates(), GA.Core.Database.account.characters)
end

-- ================================================================ Start -----

function Together:OnEnable()
    local Comm = GA.Core.Comm
    if Comm then Comm:OnBlob("GQ", function(sender, text) Together:OnQuests(sender, text) end, "Together") end
    local Events = GA.Core.Events
    -- Questlog geaendert: nach einer Ruhepause senden, falls sich etwas tat.
    Events:Register("QUEST_LOG_UPDATE", function()
        Together.settleToken = (Together.settleToken or 0) + 1
        local token = Together.settleToken
        Compat.After(QUEST_SETTLE, function()
            if Together.settleToken == token then Together:PublishQuests(false) end
        end)
    end, "Together")
    Compat.After(50, function() Together:PublishQuests(true) end)
end
