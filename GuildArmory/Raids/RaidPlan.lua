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

-- ================================================================ Markierungen --
--
-- Schlachtzugsmarkierungen (06.10.2026: "bei 30 Sekunden zum Viereck moven,
-- dass man ein blaues Viereck angezeigt bekommt"). Zwei Wege:
--   * im Text: {square}, {viereck}, {rt6} … wird beim Anzeigen zum Symbol —
--     wie im Chat. Gespeichert bleibt das Wort; das "|" der Textur-Sequenz
--     entsteht erst in der Anzeige, sonst fiele es durch clean().
--   * als Feld "marker": das grosse Symbol links neben der Erinnerung.
-- Die Grafiken sind die des Spiels, ueber ihren Pfad — nichts davon liegt im
-- Addon.

RaidPlan.MARKER_NAMES = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local MARKER_ALIAS = {
    star = 1, stern = 1, yellow = 1,
    circle = 2, kreis = 2, orange = 2,
    diamond = 3, diamant = 3, raute = 3, purple = 3,
    triangle = 4, dreieck = 4, green = 4,
    moon = 5, mond = 5,
    square = 6, quadrat = 6, viereck = 6, blue = 6, blau = 6,
    cross = 7, x = 7, kreuz = 7, red = 7,
    skull = 8, totenkopf = 8, schaedel = 8,
}

--- Markierung aus Name, Alias, "rt6" oder Zahl -> 1..8 (oder nil).
function RaidPlan.MarkerIndex(value)
    if type(value) == "number" then
        return (value >= 1 and value <= 8 and value == math.floor(value)) and value or nil
    end
    if type(value) ~= "string" then return nil end
    local lower = string.lower(Util.Trim(value) or "")
    local n = tonumber(string.match(lower, "^rt(%d)$") or lower)
    if n then return RaidPlan.MarkerIndex(n) end
    return MARKER_ALIAS[lower]
end

function RaidPlan.MarkerTexture(index)
    return index and ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index) or nil
end

--- Ersetzt {square} usw. durch das Symbol — nur fuer die Anzeige.
--- @param size number|nil  Pixel; 0 = so hoch wie die Schrift
function RaidPlan.RenderText(text, size)
    if type(text) ~= "string" then return text end
    return (string.gsub(text, "{([%w]+)}", function(word)
        local index = RaidPlan.MarkerIndex(word)
        if not index then return nil end
        return "|T" .. RaidPlan.MarkerTexture(index) .. ":" .. (size or 0) .. "|t"
    end))
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
    -- Eine Markierung allein reicht auch ("zum Viereck" als blosses Symbol).
    if not text and not spell and not RaidPlan.MarkerIndex(raw.marker) then
        warnings.noText = (warnings.noText or 0) + 1
        return nil
    end
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
        marker = RaidPlan.MarkerIndex(raw.marker),
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
        phases = {}, reminders = {}, prepull = {} }
    -- Vor dem Pull (06.10.2026): Hinweise, die beim Ready Check erscheinen —
    -- "Frostresistenz anziehen", "Feuerschutztrank". Ein Text, eine Liste von
    -- Texten oder { text, to } wie bei Erinnerungen.
    local prepull = raw.prepull
    if type(prepull) == "string" then prepull = { prepull } end
    if type(prepull) == "table" then
        for _, item in ipairs(prepull) do
            if #boss.prepull >= 10 then break end
            local text = clean(type(item) == "table" and item.text or item, 200)
            local to = selectors(type(item) == "table" and item.to or "all")
            if text and #to > 0 then boss.prepull[#boss.prepull + 1] = { text = text, to = to } end
        end
    end
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
        for index, r in ipairs(raw.reminders) do
            if #boss.reminders >= MAX_REMINDERS then warnings.tooMany = true break end
            local reminder = normalizeReminder(r, phaseStart, warnings)
            -- src: die Stelle in der Rohform — der Editor findet sie darueber wieder.
            if reminder then
                reminder.src = index
                boss.reminders[#boss.reminders + 1] = reminder
            end
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
        for index, b in ipairs(raw.bosses) do
            if #plan.bosses >= MAX_BOSSES then warnings.tooMany = true break end
            local boss = normalizeBoss(b, warnings)
            if boss then
                boss.src = index
                plan.bosses[#plan.bosses + 1] = boss
            end
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

-- ================================================================ Entwurf ---
--
-- Von Hand im Addon planen (06.10.2026: "Man muss das alles auch im Addon
-- von Hand eintragen koennen"). Bearbeitet wird die ROHFORM — genau das
-- Format, das die Webapp liefert. Speichern laeuft durch dieselbe Pruefung
-- wie ein Import, und der Plan reist danach wie jeder andere: hoehere
-- Revision, an die Gilde. Eine Webapp-Fassung und eine Hand-Fassung sind
-- damit dasselbe Ding.

--- "1:30" oder "90" -> 90. nil, wenn es keine Zeit ist.
function RaidPlan.ParseClock(text)
    text = Util.Trim(tostring(text or "")) or ""
    local m, sec = string.match(text, "^(%d+):(%d%d?)$")
    if m then
        sec = tonumber(sec)
        if sec >= 60 then return nil end
        return tonumber(m) * 60 + sec
    end
    local n = tonumber(text)
    if n and n >= 0 then return n end
    return nil
end

function RaidPlan.FormatClock(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

--- Phasen als Text, je Zeile "2 2:30 Luftphase".
function RaidPlan.PhasesToText(phases)
    local lines = {}
    for _, p in ipairs(phases or {}) do
        lines[#lines + 1] = p.phase .. " " .. RaidPlan.FormatClock(p.at) .. (p.name and (" " .. p.name) or "")
    end
    return table.concat(lines, "\n")
end

--- @return table|nil phasen, string|nil fehlerhafte Zeile
function RaidPlan.ParsePhases(text)
    local out = {}
    for line in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
        line = Util.Trim(line) or ""
        if line ~= "" then
            local phase, clock, name = string.match(line, "^(%d+)%s+([%d:]+)%s*(.*)$")
            local at = clock and RaidPlan.ParseClock(clock)
            phase = tonumber(phase)
            if not phase or phase < 2 or phase > 20 or not at then return nil, line end
            out[#out + 1] = { phase = phase, at = at, name = name ~= "" and name or nil }
        end
    end
    return out
end

--- Ziele als Text: "all, role:healer, group:2, Larrin Lasereule".
--- @return table|nil liste, string|nil unbekannter Teil
function RaidPlan.ParseTargets(text)
    local out = {}
    for part in string.gmatch(tostring(text or ""), "[^,]+") do
        part = Util.Trim(part) or ""
        if part ~= "" then
            if not selector(part) then return nil, part end
            out[#out + 1] = part
        end
    end
    if #out == 0 then out[1] = "all" end
    return out
end

--- "08.10.2026" + "20:00" -> Unix-Zeit (Ortszeit). Leeres Datum = kein Beginn.
function RaidPlan.ParseStart(dateText, clockText)
    dateText = Util.Trim(dateText or "") or ""
    if dateText == "" then return nil, true end
    local d, m, y = string.match(dateText, "^(%d%d?)%.(%d%d?)%.(%d*)$")
    if not d then return nil, false end
    local now = date("*t")
    y = tonumber(y) or now.year
    if y < 100 then y = y + 2000 end
    -- Ohne Uhrzeit 20:00; eine unlesbare Uhrzeit ist ein Fehler, kein 20:00.
    local clock = Util.Trim(clockText or "") or ""
    local hh, mm = string.match(clock, "^(%d%d?):(%d%d)$")
    if clock ~= "" and not hh then return nil, false end
    hh, mm = tonumber(hh) or 20, tonumber(mm) or 0
    d, m = tonumber(d), tonumber(m)
    if m < 1 or m > 12 or d < 1 or d > 31 or hh > 23 or mm > 59 then return nil, false end
    return time({ year = y, month = m, day = d, hour = hh, min = mm, sec = 0 }), true
end

--- Ein gespeicherter Plan zurueck in die Rohform — zum Bearbeiten und als Text.
function RaidPlan.ToRaw(plan)
    -- Namen in der Schreibweise des Plans, nicht als Vergleichsschluessel.
    local display = {}
    for g = 1, 8 do
        for _, name in ipairs(plan.groups[g] or {}) do display[RaidPlan.NameKey(name)] = name end
    end
    for _, name in ipairs(plan.bench or {}) do display[RaidPlan.NameKey(name)] = display[RaidPlan.NameKey(name)] or name end
    -- Ziele zurueck in die Schreibweise der Rohform.
    local function displayTargets(list)
        local to = {}
        for _, sel in ipairs(list or {}) do
            local kind, value = string.match(sel, "^(%a+):(.+)$")
            if sel == "all" then to[#to + 1] = "all"
            elseif kind == "name" then to[#to + 1] = display[value] or value
            elseif kind == "class" then to[#to + 1] = "class:" .. string.upper(value)
            else to[#to + 1] = sel end
        end
        return to
    end

    local raw = {
        format = RaidPlan.FORMAT, version = RaidPlan.VERSION, id = plan.id, rev = plan.rev, updated = plan.updated,
        title = plan.title, author = plan.author, guild = plan.guild, start = plan.start,
        raid = { name = plan.raid and plan.raid.name, instanceID = plan.raid and plan.raid.instanceID },
        note = plan.note, groups = {}, roles = {}, bench = {}, bosses = {},
    }
    for g = 1, 8 do
        raw.groups[g] = {}
        for i, name in ipairs(plan.groups[g] or {}) do raw.groups[g][i] = name end
    end
    for key, role in pairs(plan.roles or {}) do raw.roles[display[key] or key] = role end
    for i, name in ipairs(plan.bench or {}) do raw.bench[i] = name end
    for _, boss in ipairs(plan.bosses or {}) do
        local b = { encounterID = boss.encounterID, name = boss.name, note = boss.note, phases = {}, reminders = {},
            prepull = {} }
        for i, p in ipairs(boss.phases or {}) do b.phases[i] = { phase = p.phase, at = p.at, name = p.name } end
        -- In der Reihenfolge der Rohform, nicht nach Zeit sortiert: Der Editor
        -- haengt Neues hinten an, und src muss danach noch stimmen.
        local reminders = {}
        for _, r in ipairs(boss.reminders or {}) do reminders[#reminders + 1] = r end
        table.sort(reminders, function(x, y) return (x.src or 0) < (y.src or 0) end)
        for _, r in ipairs(reminders) do
            local to = displayTargets(r.to)
            b.reminders[#b.reminders + 1] = { at = r.at, phase = r.phase, text = r.text, spell = r.spell, to = to,
                marker = r.marker and RaidPlan.MARKER_NAMES[r.marker] or nil,
                lead = r.lead, dur = r.dur, level = r.level, sound = r.sound }
        end
        for _, item in ipairs(boss.prepull or {}) do
            b.prepull[#b.prepull + 1] = { text = item.text, to = displayTargets(item.to) }
        end
        raw.bosses[#raw.bosses + 1] = b
    end
    return raw
end

--- Vor-dem-Pull-Hinweise als Text: je Zeile ein Hinweis, Ziele in eckigen
--- Klammern davor ("[role:tank] Frostresistenz-Set"). Ohne Klammern: alle.
function RaidPlan.PrepullToText(list)
    local lines = {}
    for _, item in ipairs(list or {}) do
        local to = item.to or { "all" }
        local prefix = (#to == 1 and to[1] == "all") and "" or ("[" .. table.concat(to, ", ") .. "] ")
        lines[#lines + 1] = prefix .. (item.text or "")
    end
    return table.concat(lines, "\n")
end

--- @return table|nil liste, string|nil fehlerhafte Zeile
function RaidPlan.ParsePrepull(text)
    local out = {}
    for line in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
        line = Util.Trim(line) or ""
        if line ~= "" then
            local targets, rest = string.match(line, "^%[(.-)%]%s*(.*)$")
            local to = { "all" }
            if targets then
                to = RaidPlan.ParseTargets(targets)
                if not to then return nil, line end
                line = rest
            end
            if line == "" then return nil, targets end
            out[#out + 1] = { text = line, to = to }
        end
    end
    return out
end

--- Ein leerer Plan, gleich mit acht leeren Gruppen.
function RaidPlan.NewDraft(title)
    local identity = Compat.GetPlayerIdentity() or {}
    local raw = {
        format = RaidPlan.FORMAT, version = RaidPlan.VERSION,
        id = string.format("ga-%x-%04x", Util.Now(), math.random(0, 65535)),
        rev = 0, title = title or GA.L.RP_NEW_TITLE,
        author = identity.name and Util.ShortName(identity.name) or nil,
        raid = {}, groups = {}, roles = {}, bench = {}, bosses = {},
    }
    for g = 1, 8 do raw.groups[g] = {} end
    return raw
end

--- Der Text zum Weitergeben (wie ein Webapp-Export).
function RaidPlan.EncodeRaw(raw)
    return RaidPlan.PREFIX .. RaidPlan.Base64Encode(GA.Core.Json.Encode(raw))
end

--- Speichert einen bearbeiteten Plan: neue Revision, pruefen, ablegen,
--- aktiv setzen, an die Gilde.
--- @return table|nil plan, string|nil grund
function RaidPlan:SaveDraft(raw)
    local old = self:Get(raw.id)
    raw.rev = math.max(tonumber(raw.rev) or 0, old and old.plan.rev or 0) + 1
    raw.updated = Util.Now()
    local identity = Compat.GetPlayerIdentity() or {}
    local me = identity.name and Util.ShortName(identity.name) or nil
    raw.author = raw.author or me
    local plan, reason = RaidPlan.Normalize(raw)
    if not plan then return nil, reason end
    local wire = RaidPlan.EncodeRaw(raw)
    if #wire > MAX_INPUT then return nil, "toolong" end
    local ok, why = self:Store(plan, wire, me)
    if not ok then return nil, why end
    self:Get(plan.id).mine = true
    self:SetActive(plan.id)
    self:Publish(plan.id)
    return plan
end

--- Die Aufstellung des Raids als Gruppen eines Plans.
function RaidPlan.GroupsFromRoster(roster)
    local groups = {}
    for g = 1, 8 do groups[g] = {} end
    for _, m in ipairs(roster or {}) do
        local g = tonumber(m.group)
        if g and groups[g] and #groups[g] < 5 then groups[g][#groups[g] + 1] = Util.ShortName(m.name) end
    end
    return groups
end

--- Wo steht ein Name in der Rohform? @return gruppe, platz | nil
function RaidPlan.FindInGroups(raw, name)
    local key = RaidPlan.NameKey(name)
    for g = 1, 8 do
        for i, n in ipairs(raw.groups[g] or {}) do
            if RaidPlan.NameKey(n) == key then return g, i end
        end
    end
    return nil
end

--- Setzt einen Namen auf einen Platz. Steht er schon woanders, wird er dort
--- entfernt — zwei Plaetze kann niemand einnehmen. Ein belegter Platz wird
--- ersetzt, ein freier haengt hinten an.
--- @return boolean gesetzt
function RaidPlan.PlaceName(raw, group, slot, name)
    name = clean(name, 48)
    local list = raw.groups[group]
    if not name or not list then return false end
    local og, oi = RaidPlan.FindInGroups(raw, name)
    if og == group and oi == slot then return true end
    if not list[slot] and #list >= 5 and og ~= group then return false end
    if og then
        table.remove(raw.groups[og], oi)
        if og == group and oi < slot then slot = slot - 1 end
    end
    if list[slot] then list[slot] = name else list[#list + 1] = name end
    -- Von der Bank geholt: dort nicht mehr.
    local key = RaidPlan.NameKey(name)
    for i = #raw.bench, 1, -1 do
        if RaidPlan.NameKey(raw.bench[i]) == key then table.remove(raw.bench, i) end
    end
    return true
end

--- Rolle eines Namens setzen (nil = keine).
function RaidPlan.SetRole(raw, name, role)
    local key = RaidPlan.NameKey(name)
    for n in pairs(raw.roles) do
        if RaidPlan.NameKey(n) == key then raw.roles[n] = nil end
    end
    if role and RaidPlan.ROLES[role] then raw.roles[name] = role end
end

function RaidPlan.RoleOf(raw, name)
    local key = RaidPlan.NameKey(name)
    for n, role in pairs(raw.roles or {}) do
        if RaidPlan.NameKey(n) == key then return role end
    end
    return nil
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

--- Lesbare Ziele einer Erinnerung.
function RaidPlan.TargetText(reminder)
    local parts = {}
    for _, sel in ipairs(reminder.to or {}) do
        local kind, value = string.match(sel, "^(%a+):(.+)$")
        if sel == "all" then parts[#parts + 1] = GA.L.RP_TO_ALL
        elseif kind == "role" then parts[#parts + 1] = GA.L["RP_ROLE_" .. string.upper(value)] or value
        elseif kind == "group" then parts[#parts + 1] = string.format(GA.L.RP_GROUP, tonumber(value) or 0)
        elseif kind == "class" then
            local token = string.upper(value)
            local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token]
            parts[#parts + 1] = name or token
        elseif kind == "name" then parts[#parts + 1] = value
        end
    end
    return table.concat(parts, ", ")
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
    -- Anmeldungen zu Plaenen, die es nicht mehr gibt, fallen mit weg.
    local signups = GA.Core.Database.account.raidSignups
    if signups then
        for id in pairs(signups) do
            if not plans[id] then signups[id] = nil end
        end
    end
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
    plans[plan.id] = { plan = plan, wire = wire, from = from, at = Util.Now(), mine = entry and entry.mine or nil }
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
    -- Selbst importiert: Dieser Client verteilt die Anmeldeliste.
    if self:Get(plan.id) then self:Get(plan.id).mine = true end
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
    if not self:CanSend() then return end
    for id in pairs(self.pending or {}) do self:Publish(id) end
    for id in pairs(self.pendingSignups or {}) do self:SendSignup(id) end
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
    -- Anmeldungen fuer den, der gerade kommt: die eigenen, und wer den Plan
    -- verwaltet, die ganze Liste. Gestreut, einmal je Anfrage.
    Compat.After(3 + math.random() * 9, function()
        RaidPlan:SendOwnSignups()
        RaidPlan:PublishSignupLists()
    end)
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

-- ================================================================ Anmeldung --
--
-- Wer kommt? (06.10.2026). Zu jedem Plan sagt jeder fuer SICH zu, vielleicht
-- oder ab. Gespeichert je Plan unter dem Namen des Absenders — der kommt vom
-- Server und ist nicht faelschbar, also kann niemand fuer andere zusagen.
--
-- VERTEILT WIE DER PLAN, VOR DEM RAID: Eine Anmeldung geht als kurze
-- Nachricht an die Gilde. Wer spaeter einloggt, fragt ohnehin nach Plaenen
-- (RPREQ) — dann schickt jeder seine eigenen Anmeldungen noch einmal, und
-- wer den Plan angelegt oder importiert hat, die gesammelte Liste. So sieht
-- auch, wer spaet kommt, wer zugesagt hat, der gerade nicht online ist.
-- In gesperrten Instanzen wartet der Versand wie beim Plan.

RaidPlan.SIGN = { yes = true, maybe = true, no = true }
--- Anmeldungen gelten fuer Plaene, die heute oder spaeter beginnen.
local SIGNUP_WINDOW = 12 * 3600

local function signupStore()
    local account = GA.Core.Database.account
    account.raidSignups = account.raidSignups or {}
    return account.raidSignups
end

--- [nameKey] = { name, status, ts, class }
function RaidPlan:Signups(planId)
    return planId and signupStore()[planId] or {}
end

function RaidPlan:SignupCounts(planId)
    local counts = { yes = 0, maybe = 0, no = 0 }
    for _, s in pairs(self:Signups(planId)) do
        if counts[s.status] then counts[s.status] = counts[s.status] + 1 end
    end
    return counts
end

function RaidPlan:SignupOf(planId, name)
    local key = RaidPlan.NameKey(name)
    return key and self:Signups(planId)[key] or nil
end

--- Uebernimmt eine Anmeldung, wenn sie neuer ist als die bekannte.
--- @return boolean uebernommen
function RaidPlan:MergeSignup(planId, name, status, ts, class)
    name = clean(name, 48)
    if type(planId) ~= "string" or not string.match(planId, "^[%w_%-]+$") then return false end
    if not name or not RaidPlan.SIGN[status] then return false end
    ts = tonumber(ts)
    if not ts or ts > Util.Now() + 300 then return false end
    local list = signupStore()
    list[planId] = list[planId] or {}
    local key = RaidPlan.NameKey(name)
    local old = list[planId][key]
    if old and (old.ts or 0) >= ts then return false end
    list[planId][key] = { name = name, status = status, ts = ts, class = clean(class, 20) }
    GA.Core.Callbacks:Fire("RAIDPLAN_SIGNUPS", planId)
    return true
end

--- Die eigene Anmeldung setzen und an die Gilde schicken.
function RaidPlan:SetSignup(planId, status)
    if not self:Get(planId) or not RaidPlan.SIGN[status] then return false end
    local identity = Compat.GetPlayerIdentity() or {}
    if not identity.name then return false end
    self:MergeSignup(planId, Util.ShortName(identity.name), status, Util.Now(), identity.class)
    return self:SendSignup(planId)
end

function RaidPlan:SendSignup(planId)
    local identity = Compat.GetPlayerIdentity() or {}
    local mine = identity.name and self:SignupOf(planId, Util.ShortName(identity.name))
    if not mine then return false end
    if not self:CanSend() then
        self.pendingSignups = self.pendingSignups or {}
        self.pendingSignups[planId] = true
        return false, "later"
    end
    if self.pendingSignups then self.pendingSignups[planId] = nil end
    return GA.Core.Comm:Send("RPSIGN", { planId, mine.status, mine.ts, mine.class or "" }, "GUILD", nil, true) and true or false
end

function RaidPlan:OnSignup(sender, fields)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    fields = fields or {}
    -- Der Name ist der des Absenders, nie ein Feld der Nachricht.
    self:MergeSignup(fields[1], Util.ShortName(sender), fields[2], fields[3], fields[4])
end

--- Laeuft dieser Plan noch (heute oder spaeter, oder ohne Datum)?
local function upcoming(entry)
    local start = entry.plan.start
    return not start or start >= Util.Now() - SIGNUP_WINDOW
end

--- Die eigenen Anmeldungen noch einmal — fuer alle, die gerade eingeloggt sind.
function RaidPlan:SendOwnSignups()
    local identity = Compat.GetPlayerIdentity() or {}
    if not identity.name then return end
    for _, entry in ipairs(self:All()) do
        if upcoming(entry) and self:SignupOf(entry.plan.id, Util.ShortName(identity.name)) then
            self:SendSignup(entry.plan.id)
        end
    end
end

--- Vorschlaege fuer einen Platz: Zusagen zuerst, dann Vielleicht, dann der
--- Rest — je nach Name.
function RaidPlan.SortCandidates(names, signups)
    local rank = { yes = 1, maybe = 2 }
    local function r(name)
        local s = signups and signups[RaidPlan.NameKey(name)]
        return s and rank[s.status] or 3
    end
    table.sort(names, function(a, b)
        local ra, rb = r(a), r(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return names
end

--- Die gesammelte Liste eines Plans als Text: "planId\nname~status~ts~klasse;…"
function RaidPlan.EncodeSignups(planId, list)
    local parts = {}
    for _, s in pairs(list or {}) do
        local name = string.gsub(s.name or "", "[~;]", "")
        -- In Klammern: gsub liefert zwei Werte, der zweite gehoert nicht in die Liste.
        local class = (string.gsub(s.class or "", "[~;]", ""))
        parts[#parts + 1] = table.concat({ name, s.status, s.ts, class }, "~")
    end
    table.sort(parts)
    return planId .. "\n" .. table.concat(parts, ";")
end

function RaidPlan:OnSignupList(sender, text)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local planId, rest = string.match(tostring(text or ""), "^([%w_%-]+)\n(.*)$")
    if not planId then return end
    for rec in string.gmatch(rest, "[^;]+") do
        local name, status, ts, class = string.match(rec, "^([^~]+)~(%a+)~(%d+)~([^~]*)$")
        if name then self:MergeSignup(planId, name, status, ts, class) end
    end
end

--- Die gesammelte Liste — nur von dem, der den Plan angelegt oder
--- importiert hat; sonst schickten sie alle.
function RaidPlan:PublishSignupLists()
    if not self:CanSend() then return end
    for _, entry in ipairs(self:All()) do
        local list = self:Signups(entry.plan.id)
        if entry.mine and upcoming(entry) and next(list) then
            GA.Core.Comm:SendBlob("RPSIGNS", RaidPlan.EncodeSignups(entry.plan.id, list), "GUILD", nil, true)
        end
    end
end

-- ================================================================ Ordnen ----
--
-- Schritt 3 (06.10.2026): den Schlachtzug nach den Gruppen des Plans ordnen.
--
-- EIN ZUG, DANN WARTEN: Das Spiel nimmt eine Umstellung an, meldet sie mit
-- GROUP_ROSTER_UPDATE, und erst dann stimmt die Aufstellung, aus der der
-- naechste Zug gerechnet wird. Mehrere Zuege auf einmal rechnen mit einer
-- Aufstellung, die es nicht mehr gibt.
--
-- JEDER ZUG SETZT EINEN AN SEINEN PLATZ, UND WER RICHTIG STEHT, WIRD NIE
-- MEHR BEWEGT. Damit endet es sicher: hoechstens ein Zug je Mitglied.
--
-- Wer nicht im Plan steht, bleibt, wo er ist — ausser er steht auf einem
-- Platz, den der Plan braucht; dann wird er weggetauscht.

local ARRANGE_WAIT = 1.5     -- so lange wird auf die Bestaetigung gewartet
local ARRANGE_MAX = 60       -- Sicherheitsnetz gegen einen Kreisel
local ARRANGE_REPEAT = 3     -- derselbe Zug so oft ohne Wirkung: aufgeben

--- Plan gegen Schlachtzug: wer fehlt, wer zu viel ist, wer falsch steht.
--- @param roster table aus Compat.GetRaidRoster
function RaidPlan.Compare(plan, roster)
    local target = {}
    for g = 1, 8 do
        for _, name in ipairs(plan.groups[g] or {}) do target[RaidPlan.NameKey(name)] = g end
    end
    local out = { members = {}, missing = {}, extras = {}, wrong = 0, placed = 0, byKey = {} }
    local present = {}
    for _, m in ipairs(roster or {}) do
        local key = RaidPlan.NameKey(m.name)
        if key then
            present[key] = true
            local entry = { index = m.index, name = Util.ShortName(m.name), key = key, group = m.group, target = target[key] }
            out.members[#out.members + 1] = entry
            out.byKey[key] = entry
            if not entry.target then out.extras[#out.extras + 1] = entry.name
            elseif entry.target == entry.group then out.placed = out.placed + 1
            else out.wrong = out.wrong + 1 end
        end
    end
    for g = 1, 8 do
        for _, name in ipairs(plan.groups[g] or {}) do
            if not present[RaidPlan.NameKey(name)] then out.missing[#out.missing + 1] = { name = name, group = g } end
        end
    end
    return out
end

--- Der naechste Zug, oder nil, wenn alle, die da sind, richtig stehen.
--- @return table|nil { kind = "set", index, group, name } | { kind = "swap", a, b, name, other }
function RaidPlan.NextMove(plan, roster)
    local cmp = RaidPlan.Compare(plan, roster)
    local count, inGroup = {}, {}
    for g = 1, 8 do count[g], inGroup[g] = 0, {} end
    for _, m in ipairs(cmp.members) do
        if count[m.group] then
            count[m.group] = count[m.group] + 1
            table.insert(inGroup[m.group], m)
        end
    end
    for _, m in ipairs(cmp.members) do
        local T = m.target
        if T and T ~= m.group then
            if count[T] < 5 then
                return { kind = "set", index = m.index, group = T, name = m.name }, cmp
            end
            -- Tauschpartner in der Zielgruppe: wer dort nicht hingehoert —
            -- am liebsten jemand, der genau in meine Gruppe soll, dann wer
            -- gar nicht im Plan steht, dann jeder andere Falsche.
            local best, bestScore
            for _, y in ipairs(inGroup[T]) do
                if y.target ~= T then
                    local score = (y.target == m.group) and 3 or (y.target == nil and 2 or 1)
                    if not best or score > bestScore then best, bestScore = y, score end
                end
            end
            if best then
                return { kind = "swap", a = m.index, b = best.index, name = m.name, other = best.name, group = T }, cmp
            end
        end
    end
    return nil, cmp
end

--- Warum gerade nicht geordnet werden kann — oder nil.
function RaidPlan:ArrangeProblem()
    if not self:Active() then return "noplan" end
    if not Compat.IsInRaid() then return "noraid" end
    if not Compat.CanArrangeRaid() then return "norights" end
    if Compat.IsArrangeBlocked() then return "combat" end
    return nil
end

--- Startet das Ordnen nach dem aktiven Plan.
--- @return boolean gestartet, string|nil grund
function RaidPlan:Arrange()
    local problem = self:ArrangeProblem()
    if problem then return false, problem end
    self.arranging = { planId = self:Active().plan.id, moves = 0, steps = 0, token = 0 }
    GA.Core.Callbacks:Fire("RAIDPLAN_ARRANGE", "start")
    self:ArrangeStep()
    return true
end

function RaidPlan:StopArrange(reason, cmp)
    local job = self.arranging
    if not job then return end
    self.arranging = nil
    self.lastArrange = { reason = reason, moves = job.moves, missing = cmp and cmp.missing or {}, at = Util.Now() }
    local L = GA.L
    if reason == "done" then
        local missing = {}
        for _, m in ipairs(cmp and cmp.missing or {}) do missing[#missing + 1] = m.name end
        Debug:Info(L.RP_ARRANGED, job.moves)
        if #missing > 0 then Debug:Info(L.RP_ARRANGE_MISSING, table.concat(missing, ", ")) end
    else
        Debug:Warn(L["RP_ARRANGE_" .. string.upper(reason)] or reason)
    end
    GA.Core.Callbacks:Fire("RAIDPLAN_ARRANGE", reason)
end

--- Ein Zug. Danach wird auf GROUP_ROSTER_UPDATE gewartet (oder ARRANGE_WAIT).
function RaidPlan:ArrangeStep()
    local job = self.arranging
    if not job then return end
    local entry = store()[job.planId]
    if not entry then return self:StopArrange("noplan") end
    if not Compat.IsInRaid() then return self:StopArrange("noraid") end
    if not Compat.CanArrangeRaid() then return self:StopArrange("norights") end
    if Compat.IsArrangeBlocked() then return self:StopArrange("combat") end

    local move, cmp = RaidPlan.NextMove(entry.plan, Compat.GetRaidRoster())
    if not move then return self:StopArrange("done", cmp) end

    job.steps = job.steps + 1
    if job.steps > ARRANGE_MAX then return self:StopArrange("stuck", cmp) end
    local key = move.kind .. ":" .. tostring(move.index or move.a) .. ":" .. tostring(move.group or move.b)
    if key == job.lastKey then
        job.repeats = (job.repeats or 0) + 1
        if job.repeats >= ARRANGE_REPEAT then return self:StopArrange("stuck", cmp) end
    else
        job.lastKey, job.repeats = key, 0
        job.moves = job.moves + 1
    end

    local ok
    if move.kind == "set" then ok = Compat.SetRaidSubgroup(move.index, move.group)
    else ok = Compat.SwapRaidSubgroup(move.a, move.b) end
    if not ok then return self:StopArrange("failed", cmp) end
    Debug:Print("raidplan", "Zug %d: %s -> Gruppe %d%s", job.moves, tostring(move.name), move.group or 0,
        move.other and (" (Tausch mit " .. move.other .. ")") or "")

    job.token = job.token + 1
    local token = job.token
    job.waiting = token
    Compat.After(ARRANGE_WAIT, function()
        if RaidPlan.arranging == job and job.waiting == token then RaidPlan:ArrangeStep() end
    end)
end

--- Die Aufstellung hat sich geaendert: Laeuft das Ordnen, kommt der naechste Zug.
function RaidPlan:OnRosterUpdate()
    local job = self.arranging
    if job and job.waiting then
        local token = job.waiting
        job.waiting = nil
        Compat.After(0.2, function()
            if RaidPlan.arranging == job and job.token == token then RaidPlan:ArrangeStep() end
        end)
    end
    GA.Core.Callbacks:Fire("RAIDPLAN_ROSTER")
end

-- ================================================================ Start ----

function RaidPlan:OnEnable()
    self:Prune()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:OnBlob("RPLAN", function(sender, text) RaidPlan:OnPlan(sender, text) end, "RaidPlan")
        Comm:On("RPREQ", function(sender, fields) RaidPlan:OnRequest(sender, fields) end, "RaidPlan")
        Comm:On("RPSIGN", function(sender, fields) RaidPlan:OnSignup(sender, fields) end, "RaidPlan")
        Comm:OnBlob("RPSIGNS", function(sender, text) RaidPlan:OnSignupList(sender, text) end, "RaidPlan")
    end
    local Events = GA.Core.Events
    local function flush() Compat.After(5, function() RaidPlan:Flush() end) end
    Events:Register("PLAYER_ENTERING_WORLD", flush, "RaidPlan")
    Events:Register("ZONE_CHANGED_NEW_AREA", flush, "RaidPlan")
    Events:Register("PLAYER_REGEN_ENABLED", flush, "RaidPlan")
    Events:Register("GROUP_ROSTER_UPDATE", function() RaidPlan:OnRosterUpdate() end, "RaidPlan")
    -- Kampf beginnt mitten im Ordnen: sofort aufhoeren, nicht erst beim naechsten Zug.
    Events:Register("PLAYER_REGEN_DISABLED", function()
        if RaidPlan.arranging then RaidPlan:StopArrange("combat") end
    end, "RaidPlan")
    Compat.After(REQUEST_DELAY, function()
        RaidPlan:Request()
        -- Wer einloggt, meldet seine Anmeldungen selbst noch einmal.
        Compat.After(5 + math.random() * 10, function() RaidPlan:SendOwnSignups() end)
    end)
end
