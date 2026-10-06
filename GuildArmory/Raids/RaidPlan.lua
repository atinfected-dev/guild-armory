--[[----------------------------------------------------------------------------
    Raids/RaidPlan — Raidplaene aus der Webapp: einlesen, ablegen, verteilen.
    Kein UI. Gebaut 06.10.2026 auf Wunsch: "auf unserer Webapp geplant, dann
    per Import in unser Addon je Raid die Gruppen geordnet und die Boss-
    Reminder angezeigt". Das Format beschreibt docs/RAIDPLAN-FORMAT.md.

    GEPLANT WIRD IN DER WEBAPP, NICHT HIER:
      Das Addon liest einen fertigen Plan — Gruppen, Rollen, je Boss Notiz,
      Phasen und Erinnerungen — und zeigt ihn. Es bearbeitet ihn nicht. Wer
      etwas aendern will, aendert es in der Webapp und importiert neu; die
      Revision (rev) sagt, welcher Stand der neuere ist.

    VERTEILT WIRD VOR DEM RAID, UEBER DIE GILDE:
      Mit den Einschraenkungen aus Retail (Addon-Nachrichten in Instanzen
      gesperrt) kann der Raidleiter im Raid nichts mehr verschicken. Deshalb
      geht ein importierter Plan sofort an die Gilde, jeder legt ihn ab, und
      wer spaeter einloggt, fragt nach (RPREQ) — wie bei der Gildenbank. Ist
      der Versand gerade gesperrt, wartet der Plan, bis es wieder geht.

    DER TEXT IST FREMDE EINGABE:
      Er kommt aus einer Zwischenablage oder von einem anderen Client. Alles
      wird geprueft, gekuerzt und von Steuerzeichen befreit ("|" baut im
      Spiel Links und Texturen), bevor es irgendwo angezeigt wird.
------------------------------------------------------------------------------]]

local _, GA = ...

local RaidPlan = {}
GA.Modules.RaidPlan = RaidPlan

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

RaidPlan.PREFIX = "GARP1:"
RaidPlan.FORMAT = "guildarmory-raidplan"
RaidPlan.VERSION = 1

--- Laenger ist kein Plan, sondern ein Versehen (oder Absicht).
local MAX_INPUT = 100000
local MAX_PLANS = 20
local MAX_BOSSES = 40
local MAX_REMINDERS = 200
--- So lange nach dem geplanten Beginn bleibt ein Plan liegen.
local KEEP_AFTER_START = 3 * 86400
--- Ohne Beginn: so lange nach dem Empfang.
local KEEP_WITHOUT_START = 30 * 86400
--- So lange nach dem Einloggen wird nach Plaenen gefragt.
local REQUEST_DELAY = 45
--- Hoechstens so viele Plaene beantwortet ein Client je Anfrage.
local ANSWER_LIMIT = 3

RaidPlan.ROLES = { tank = true, healer = true, melee = true, ranged = true, dps = true }
RaidPlan.LEVELS = { info = true, warn = true, alert = true }
RaidPlan.SOUNDS = { none = true, info = true, warn = true, alert = true }
local DEFAULT_SOUND = { info = "none", warn = "warn", alert = "alert" }

-- ================================================================ Base64 ----
--
-- Der Plan reist als Base64: Darin gibt es kein "|", keine Zeilenumbrueche
-- und keine Anfuehrungszeichen — nichts, was das Eingabefeld des Spiels oder
-- der Nachrichtenweg veraendern koennte. Ohne Bitoperationen gerechnet,
-- weil Lua 5.1 keine hat.

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, 64 do B64_VALUE[string.byte(B64, i)] = i - 1 end
-- Die URL-sichere Schreibweise gilt auch.
B64_VALUE[string.byte("-")] = 62
B64_VALUE[string.byte("_")] = 63

--- @return string|nil
function RaidPlan.Base64Decode(text)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "[%s=]", "")
    local out, n = {}, 0
    local value, bits = 0, 0
    for i = 1, #text do
        local v = B64_VALUE[string.byte(text, i)]
        if not v then return nil end
        value = value * 64 + v
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local scale = 2 ^ bits
            local byte = math.floor(value / scale)
            value = value - byte * scale
            n = n + 1
            out[n] = string.char(byte)
        end
    end
    return table.concat(out)
end

function RaidPlan.Base64Encode(text)
    local out = {}
    local function digit(v) return string.sub(B64, v + 1, v + 1) end
    for i = 1, #text, 3 do
        local a, b, c = string.byte(text, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = digit(math.floor(n / 262144) % 64) .. digit(math.floor(n / 4096) % 64)
            .. (b and digit(math.floor(n / 64) % 64) or "=") .. (c and digit(n % 64) or "=")
    end
    return table.concat(out)
end

-- ================================================================ Pruefen ---

--- Text aus fremder Hand: kein "|", keine Steuerzeichen, hoechstens max Bytes —
--- und nicht mitten in einem UTF-8-Zeichen abgeschnitten.
local function clean(value, max, keepNewlines)
    if type(value) ~= "string" and type(value) ~= "number" then return nil end
    local text = tostring(value)
    text = string.gsub(text, "|", "/")
    if keepNewlines then
        text = string.gsub(text, "\r\n?", "\n")
        text = string.gsub(text, "[%z\1-\9\11-\31\127]", "")
    else
        text = string.gsub(text, "[%z\1-\31\127]", " ")
    end
    text = Util.Trim(text) or ""
    if #text > max then
        text = string.sub(text, 1, max)
        -- Ein angeschnittenes Mehrbyte-Zeichen am Ende faellt weg — ein
        -- vollstaendiges bleibt.
        local lead = string.find(text, "[\192-\255][\128-\191]*$")
        if lead then
            local b = string.byte(text, lead)
            local need = b >= 240 and 4 or (b >= 224 and 3 or 2)
            if #text - lead + 1 < need then text = string.sub(text, 1, lead - 1) end
        end
    end
    if text == "" then return nil end
    return text
end
RaidPlan.Clean = clean

local function number(value, min, max)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    if min and value < min then return nil end
    if max and value > max then return nil end
    return value
end

--- Vergleichsschluessel fuer Namen: ohne Realm, klein geschrieben.
function RaidPlan.NameKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return string.lower(Util.ShortName(name))
end

--- Ein Ziel einer Erinnerung, vereinheitlicht: "all", "role:healer",
--- "group:3", "class:priest" oder "name:<kurzname klein>".
local function selector(value)
    local text = clean(value, 60)
    if not text then return nil end
    local lower = string.lower(text)
    if lower == "all" or lower == "*" then return "all" end
    local kind, rest = string.match(lower, "^(%a+):(.+)$")
    if kind == "role" then
        return RaidPlan.ROLES[rest] and ("role:" .. rest) or nil
    elseif kind == "group" then
        local n = number(rest, 1, 8)
        return n and ("group:" .. math.floor(n)) or nil
    elseif kind == "class" then
        return "class:" .. string.gsub(rest, "%s", "")
    elseif kind == "name" then
        local key = RaidPlan.NameKey(Util.Trim(string.sub(text, 6)))
        return key and ("name:" .. key) or nil
    end
    local key = RaidPlan.NameKey(text)
    return key and ("name:" .. key) or nil
end

local function selectors(value)
    local list = type(value) == "table" and value or { value or "all" }
    local out, seen = {}, {}
    for _, item in ipairs(list) do
        local sel = selector(item)
        if sel and not seen[sel] then
            seen[sel] = true
            out[#out + 1] = sel
        end
    end
    return out
end

local function normalizeReminder(raw, phaseStart, warnings)
    if type(raw) ~= "table" then return nil end
    local at = number(raw.at, 0, 3600)
    if not at then warnings.badTime = (warnings.badTime or 0) + 1 return nil end
    local text = clean(raw.text, 200)
    local spell = number(raw.spell, 1, 10000000)
    if not text and not spell then warnings.noText = (warnings.noText or 0) + 1 return nil end
    local phase = math.floor(number(raw.phase, 1, 20) or 1)
    local level = type(raw.level) == "string" and RaidPlan.LEVELS[raw.level] and raw.level or "warn"
    local sound = type(raw.sound) == "string" and RaidPlan.SOUNDS[raw.sound] and raw.sound or DEFAULT_SOUND[level]
    local to = selectors(raw.to)
    if #to == 0 then warnings.badTarget = (warnings.badTarget or 0) + 1 return nil end
    return {
        at = at,
        phase = phase,
        -- Sekunden ab Pull: Phasenbeginn (geschaetzt, aus der Webapp) plus at.
        time = (phaseStart[phase] or 0) + at,
        text = text,
        spell = spell and math.floor(spell) or nil,
        to = to,
        lead = number(raw.lead, 0, 30) or 5,
        dur = number(raw.dur, 1, 60) or 4,
        level = level,
        sound = sound,
    }
end

local function normalizeBoss(raw, warnings)
    if type(raw) ~= "table" then return nil end
    local id = number(raw.encounterID, 1, 100000000)
    local name = clean(raw.name, 80)
    if not id and not name then warnings.noBoss = (warnings.noBoss or 0) + 1 return nil end
    local boss = { encounterID = id and math.floor(id) or nil, name = name, note = clean(raw.note, 2000, true),
        phases = {}, reminders = {} }
    -- Phase 1 beginnt mit dem Pull; spaetere zur geschaetzten Zeit.
    local phaseStart = { [1] = 0 }
    if type(raw.phases) == "table" then
        for _, p in ipairs(raw.phases) do
            local phase = type(p) == "table" and number(p.phase, 2, 20)
            local at = type(p) == "table" and number(p.at, 0, 3600)
            if phase and at then
                phase = math.floor(phase)
                phaseStart[phase] = at
                boss.phases[#boss.phases + 1] = { phase = phase, at = at, name = clean(p.name, 60) }
            end
        end
        table.sort(boss.phases, function(a, b) return a.phase < b.phase end)
    end
    if type(raw.reminders) == "table" then
        for _, r in ipairs(raw.reminders) do
            if #boss.reminders >= MAX_REMINDERS then warnings.tooMany = true break end
            local reminder = normalizeReminder(r, phaseStart, warnings)
            if reminder then boss.reminders[#boss.reminders + 1] = reminder end
        end
    end
    table.sort(boss.reminders, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        return (a.text or "") < (b.text or "")
    end)
    return boss
end

--- Ein gelesener Plan wird zu dem, was das Addon ablegt — alles geprueft.
--- @return table|nil plan, string|nil grund
function RaidPlan.Normalize(raw)
    if type(raw) ~= "table" or raw.format ~= RaidPlan.FORMAT then return nil, "format" end
    local version = number(raw.version)
    if not version or version < 1 then return nil, "format" end
    if version > RaidPlan.VERSION then return nil, "newer" end
    local id = type(raw.id) == "string" and string.match(raw.id, "^[%w_%-]+$") and #raw.id <= 40 and raw.id or nil
    if not id then return nil, "id" end

    local warnings = {}
    local raid = type(raw.raid) == "table" and raw.raid or {}
    local plan = {
        id = id,
        rev = math.floor(number(raw.rev, 1) or 1),
        updated = math.floor(number(raw.updated, 0) or 0),
        title = clean(raw.title, 80),
        author = clean(raw.author, 48),
        guild = clean(raw.guild, 64),
        raid = { name = clean(raid.name, 80), instanceID = number(raid.instanceID, 1) },
        start = number(raw.start, 1) and math.floor(number(raw.start, 1)) or nil,
        note = clean(raw.note, 2000, true),
        groups = {},
        roles = {},
        bench = {},
        bosses = {},
        warnings = warnings,
    }
    plan.title = plan.title or plan.raid.name or id

    -- Gruppen: hoechstens acht zu je fuenf. Wer doppelt steht, zaehlt dort,
    -- wo er zuerst steht — zwei Plaetze kann niemand einnehmen.
    local placed = {}
    if type(raw.groups) == "table" then
        for g = 1, 8 do
            local group = {}
            for _, name in ipairs(type(raw.groups[g]) == "table" and raw.groups[g] or {}) do
                local clean_ = clean(name, 48)
                local key = clean_ and RaidPlan.NameKey(clean_)
                if key and not placed[key] and #group < 5 then
                    placed[key] = g
                    group[#group + 1] = clean_
                elseif key then
                    warnings.duplicate = (warnings.duplicate or 0) + 1
                end
            end
            plan.groups[g] = group
        end
    end
    for g = 1, 8 do plan.groups[g] = plan.groups[g] or {} end

    if type(raw.roles) == "table" then
        for name, role in pairs(raw.roles) do
            local key = RaidPlan.NameKey(clean(name, 48))
            role = type(role) == "string" and string.lower(role)
            if key and role and RaidPlan.ROLES[role] then plan.roles[key] = role end
        end
    end
    if type(raw.bench) == "table" then
        for _, name in ipairs(raw.bench) do
            local c = clean(name, 48)
            if c and #plan.bench < 40 then plan.bench[#plan.bench + 1] = c end
        end
    end
    if type(raw.bosses) == "table" then
        for _, b in ipairs(raw.bosses) do
            if #plan.bosses >= MAX_BOSSES then warnings.tooMany = true break end
            local boss = normalizeBoss(b, warnings)
            if boss then plan.bosses[#plan.bosses + 1] = boss end
        end
    end
    return plan
end

--- Liest den Text aus dem Importfeld oder von einem anderen Client.
--- @return table|nil plan, string|nil grund, string|nil transporttext
function RaidPlan.Parse(text)
    if type(text) ~= "string" then return nil, "empty" end
    text = Util.Trim(text) or ""
    if text == "" then return nil, "empty" end
    if #text > MAX_INPUT then return nil, "toolong" end

    local json, wire
    if string.sub(text, 1, #RaidPlan.PREFIX) == RaidPlan.PREFIX then
        json = RaidPlan.Base64Decode(string.sub(text, #RaidPlan.PREFIX + 1))
        if not json then return nil, "base64" end
        wire = RaidPlan.PREFIX .. (string.gsub(string.sub(text, #RaidPlan.PREFIX + 1), "%s", ""))
    elseif string.sub(text, 1, 1) == "{" then
        -- Rohes JSON — zum Ausprobieren. Auf den Weg geht es als Base64.
        json = text
        wire = RaidPlan.PREFIX .. RaidPlan.Base64Encode(text)
    else
        return nil, "format"
    end

    local raw = GA.Core.Json.Decode(json)
    if type(raw) ~= "table" then return nil, "json" end
    local plan, reason = RaidPlan.Normalize(raw)
    if not plan then return nil, reason end
    return plan, nil, wire
end

--- Zahlen fuer Vorschau und Anzeige.
function RaidPlan.Summary(plan)
    local players, reminders = 0, 0
    for g = 1, 8 do players = players + #(plan.groups[g] or {}) end
    for _, boss in ipairs(plan.bosses or {}) do reminders = reminders + #boss.reminders end
    local skipped = 0
    for key, value in pairs(plan.warnings or {}) do
        if key ~= "tooMany" and type(value) == "number" then skipped = skipped + value end
    end
    return { players = players, bosses = #(plan.bosses or {}), reminders = reminders,
             bench = #(plan.bench or {}), skipped = skipped }
end

-- ================================================================ Wer bin ich --

--- Gilt eine Erinnerung fuer diese Person?
--- @param who table { name, class, group, role }
function RaidPlan.Matches(reminder, who)
    local nameKey = RaidPlan.NameKey(who.name)
    local class = who.class and string.lower(who.class)
    for _, sel in ipairs(reminder.to or {}) do
        if sel == "all" then return true end
        local kind, value = string.match(sel, "^(%a+):(.+)$")
        if kind == "name" and value == nameKey then return true end
        if kind == "class" and value == class then return true end
        if kind == "group" and tonumber(value) == who.group then return true end
        if kind == "role" then
            if value == who.role then return true end
            if value == "dps" and (who.role == "melee" or who.role == "ranged") then return true end
        end
    end
    return false
end

--- Der eigene Platz in einem Plan: Gruppe und Rolle laut Plan.
function RaidPlan.WhoAmI(plan, identity)
    identity = identity or Compat.GetPlayerIdentity() or {}
    local key = RaidPlan.NameKey(identity.name)
    local group
    for g = 1, 8 do
        for _, name in ipairs(plan.groups[g] or {}) do
            if RaidPlan.NameKey(name) == key then group = g end
        end
    end
    return { name = identity.name, class = identity.class, group = group, role = key and plan.roles[key] or nil }
end

--- Der Boss eines Plans zu einem Kampf — ueber die Kennung, sonst den Namen.
function RaidPlan.FindBoss(plan, encounterID, encounterName)
    for _, boss in ipairs(plan.bosses or {}) do
        if encounterID and boss.encounterID == encounterID then return boss end
    end
    if type(encounterName) == "string" and Compat.IsReadable(encounterName) then
        local lower = string.lower(encounterName)
        for _, boss in ipairs(plan.bosses or {}) do
            if boss.name and string.lower(boss.name) == lower then return boss end
        end
    end
    return nil
end

-- ================================================================ Ablage ----

local function store()
    local account = GA.Core.Database.account
    account.raidPlans = account.raidPlans or {}
    return account.raidPlans
end

function RaidPlan:All()
    local list = {}
    for _, entry in pairs(store()) do list[#list + 1] = entry end
    -- Naechster Beginn zuerst, Plaene ohne Datum danach.
    table.sort(list, function(a, b)
        local sa, sb = a.plan.start, b.plan.start
        if (sa ~= nil) ~= (sb ~= nil) then return sa ~= nil end
        if sa and sb and sa ~= sb then return sa < sb end
        return (a.plan.title or "") < (b.plan.title or "")
    end)
    return list
end

function RaidPlan:Get(id) return id and store()[id] or nil end

--- Der Plan, der gerade gilt: der gewaehlte — sonst der naechste, der heute
--- oder spaeter beginnt — sonst der zuletzt erhaltene.
function RaidPlan:Active()
    local account = GA.Core.Database.account
    local chosen = account.raidPlanActive and store()[account.raidPlanActive]
    if chosen then return chosen end
    local now = Util.Now()
    local best, latest
    for _, entry in pairs(store()) do
        local start = entry.plan.start
        if start and start >= now - 12 * 3600 and (not best or start < best.plan.start) then best = entry end
        if not latest or (entry.at or 0) > (latest.at or 0) then latest = entry end
    end
    return best or latest
end

function RaidPlan:SetActive(id)
    GA.Core.Database.account.raidPlanActive = id
    GA.Core.Callbacks:Fire("RAIDPLAN_CHANGED")
end

function RaidPlan:Delete(id)
    store()[id] = nil
    if GA.Core.Database.account.raidPlanActive == id then GA.Core.Database.account.raidPlanActive = nil end
    GA.Core.Callbacks:Fire("RAIDPLAN_CHANGED")
end

--- Ist der angebotene Stand neuer als der abgelegte?
local function newer(plan, entry)
    if not entry then return true end
    if plan.rev ~= entry.plan.rev then return plan.rev > entry.plan.rev end
    return plan.updated > (entry.plan.updated or 0)
end

--- Alte Plaene fallen weg; mehr als MAX_PLANS werden es nie.
function RaidPlan:Prune()
    local plans, now = store(), Util.Now()
    for id, entry in pairs(plans) do
        local start = entry.plan and entry.plan.start
        if not entry.plan
            or (start and start < now - KEEP_AFTER_START)
            or (not start and (entry.at or 0) < now - KEEP_WITHOUT_START) then
            plans[id] = nil
        end
    end
    local list = {}
    for _, entry in pairs(plans) do list[#list + 1] = entry end
    if #list <= MAX_PLANS then return end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    for i = MAX_PLANS + 1, #list do plans[list[i].plan.id] = nil end
end

--- Legt einen gelesenen Plan ab.
--- @return boolean abgelegt, string|nil grund ("older", "same")
function RaidPlan:Store(plan, wire, from)
    local plans = store()
    local entry = plans[plan.id]
    if entry and entry.plan.rev == plan.rev and entry.plan.updated == plan.updated then return false, "same" end
    if not newer(plan, entry) then return false, "older" end
    plans[plan.id] = { plan = plan, wire = wire, from = from, at = Util.Now() }
    self:Prune()
    GA.Core.Callbacks:Fire("RAIDPLAN_CHANGED", plan.id)
    return true
end

--- Import aus dem Eingabefeld: ablegen und an die Gilde schicken.
--- @return table|nil plan, string|nil grund
function RaidPlan:Import(text)
    local plan, reason, wire = RaidPlan.Parse(text)
    if not plan then return nil, reason end
    local identity = Compat.GetPlayerIdentity() or {}
    local ok, why = self:Store(plan, wire, identity.name and Util.ShortName(identity.name) or nil)
    if not ok and why == "older" then return nil, "older" end
    self:SetActive(plan.id)
    self:Publish(plan.id)
    return plan, why
end

-- ================================================================ Teilen ----

--- Darf gerade gesendet werden? In gesperrten Instanzen (Retail-Regeln)
--- wartet der Versand, bis man wieder draussen ist.
function RaidPlan:CanSend()
    if Compat.IsCommRestricted and Compat.IsCommRestricted() then return false end
    return Compat.IsInGuild() and GA.Core.Comm ~= nil
end

function RaidPlan:Publish(id)
    local entry = store()[id]
    if not entry or not entry.wire then return false end
    if not self:CanSend() then
        self.pending = self.pending or {}
        self.pending[id] = true
        return false, "later"
    end
    if self.pending then self.pending[id] = nil end
    self.heard = self.heard or {}
    self.heard[id] = math.max(self.heard[id] or 0, entry.plan.rev)
    return GA.Core.Comm:SendBlob("RPLAN", entry.wire, "GUILD", nil, true) and true or false
end

--- Was wartete, geht jetzt hinaus.
function RaidPlan:Flush()
    if not self.pending or not self:CanSend() then return end
    for id in pairs(self.pending) do self:Publish(id) end
end

function RaidPlan:OnPlan(sender, text)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local plan, reason, wire = RaidPlan.Parse(text)
    if not plan then
        Debug:Print("raidplan", "Plan von %s nicht lesbar: %s", tostring(sender), tostring(reason))
        return
    end
    self.heard = self.heard or {}
    self.heard[plan.id] = math.max(self.heard[plan.id] or 0, plan.rev)
    self:Store(plan, wire, Util.ShortName(sender))
end

--- "id:rev,id:rev" — was dieser Client hat. Passt in eine Nachricht.
function RaidPlan:Inventory()
    local parts, length = {}, 0
    for _, entry in ipairs(self:All()) do
        local part = entry.plan.id .. ":" .. entry.plan.rev
        if length + #part + 1 > 180 then break end
        parts[#parts + 1] = part
        length = length + #part + 1
    end
    return table.concat(parts, ",")
end

function RaidPlan.ParseInventory(text)
    local out = {}
    for id, rev in string.gmatch(tostring(text or ""), "([%w_%-]+):(%d+)") do out[id] = tonumber(rev) end
    return out
end

--- Jemand fragt, was es gibt. Geantwortet wird nur mit dem, was er nicht
--- oder aelter hat — gestreut, und nicht, wenn es inzwischen ein anderer
--- geschickt hat.
function RaidPlan:OnRequest(sender, fields)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local theirs = RaidPlan.ParseInventory(fields and fields[1])
    local answered = 0
    for _, entry in ipairs(self:All()) do
        local plan = entry.plan
        if answered >= ANSWER_LIMIT then break end
        if entry.wire and (theirs[plan.id] or 0) < plan.rev then
            answered = answered + 1
            Compat.After(2 + math.random() * 8, function()
                local current = store()[plan.id]
                if not current or current.plan.rev ~= plan.rev then return end
                if ((RaidPlan.heard or {})[plan.id] or 0) >= plan.rev then return end
                RaidPlan:Publish(plan.id)
            end)
        end
    end
end

function RaidPlan:Request()
    if not self:CanSend() then return false end
    return GA.Core.Comm:Send("RPREQ", { self:Inventory() }, "GUILD", nil, true) and true or false
end

-- ================================================================ Start ----

function RaidPlan:OnEnable()
    self:Prune()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:OnBlob("RPLAN", function(sender, text) RaidPlan:OnPlan(sender, text) end, "RaidPlan")
        Comm:On("RPREQ", function(sender, fields) RaidPlan:OnRequest(sender, fields) end, "RaidPlan")
    end
    local Events = GA.Core.Events
    local function flush() Compat.After(5, function() RaidPlan:Flush() end) end
    Events:Register("PLAYER_ENTERING_WORLD", flush, "RaidPlan")
    Events:Register("ZONE_CHANGED_NEW_AREA", flush, "RaidPlan")
    Events:Register("PLAYER_REGEN_ENABLED", flush, "RaidPlan")
    Compat.After(REQUEST_DELAY, function() RaidPlan:Request() end)
end
