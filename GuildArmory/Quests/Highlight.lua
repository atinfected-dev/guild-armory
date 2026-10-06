--[[----------------------------------------------------------------------------
    Quests/Highlight — Objekte in der Welt hervorheben (Sammeln & Quests).
    Kein UI. Gebaut 06.10.2026.

    EIN ADDON KANN DIE WELT NICHT EINFAERBEN. Was es gibt, ist das "Soft
    Interact"-System des Spiels: Es setzt ueber das naechste benutzbare
    Objekt vor einem — Kraut, Erzader, Questobjekt, Truhe, Briefkasten — ein
    Symbol. Gesteuert wird das ueber Konsolenvariablen, die das Spiel im
    Menue kaum zeigt. Dieser Schalter setzt sie:

      SoftTargetInteract        3   Interaktionsziel immer waehlen
      SoftTargetIconGameObject  1   Symbol ueber Objekten
      SoftTargetIconInteract    1   Symbol ueber dem Interaktionsziel
      SoftTargetInteractRange   20  Reichweite (Spiel: hoechstens etwa 20)

    WAS VORHER GALT, KOMMT ZURUECK: Beim Einschalten merkt sich das Addon die
    bisherigen Werte (einmal — ein zweites Einschalten ueberschreibt sie
    nicht), beim Ausschalten stellt es genau diese wieder her. Nicht die
    Standardwerte: Wer vorher selbst etwas eingestellt hatte, bekommt das
    zurueck.

    GESCHUETZTE VARIABLEN: Im Kampf laesst das Spiel sie nicht aendern. Dann
    wartet die Aenderung bis zum Kampfende.

    MESSUNG (/ga probe softinteract): Ob Forever den Namen des markierten
    Objekts herausgibt, ist nicht bekannt. Die Messung schreibt bei jedem
    Wechsel des markierten Objekts mit, was der Client liefert, und zeigt
    das Protokoll beim zweiten Aufruf zum Kopieren.
------------------------------------------------------------------------------]]

local _, GA = ...

local Highlight = {}
GA.Modules.Highlight = Highlight

local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

Highlight.CVARS = {
    { "SoftTargetInteract", "3" },
    { "SoftTargetIconGameObject", "1" },
    { "SoftTargetIconInteract", "1" },
    { "SoftTargetInteractRange", "20" },   -- ersetzt durch Highlight.Range()
}

local function config() return GA.Core.Database.account.config end

function Highlight:IsOn() return GA.Core.Config:Get("objectHighlight") == true end

--- Setzt die Variablen (an) oder stellt die gemerkten wieder her (aus).
--- @return boolean|string ok ("later" im Kampf), table|nil nicht gesetzte Namen
function Highlight:Apply(on)
    if Compat.InCombat() then
        self.deferred = on and true or false
        return "later"
    end
    self.deferred = nil
    local cfg = config()
    if on then
        cfg.objectHighlightSaved = cfg.objectHighlightSaved or {}
        local failed = {}
        for _, entry in ipairs(Highlight.CVARS) do
            local name, value = entry[1], entry[2]
            if name == "SoftTargetInteractRange" then value = tostring(Highlight.Range()) end
            local current = Compat.GetCVar(name)
            if current == nil then
                failed[#failed + 1] = name
            else
                if cfg.objectHighlightSaved[name] == nil then cfg.objectHighlightSaved[name] = current end
                if not Compat.SetCVar(name, value) then failed[#failed + 1] = name end
            end
        end
        return #failed == 0, failed
    end
    for name, value in pairs(cfg.objectHighlightSaved or {}) do Compat.SetCVar(name, value) end
    cfg.objectHighlightSaved = nil
    return true
end

function Highlight:SetEnabled(on)
    GA.Core.Config:Set("objectHighlight", on and true or false)
    local ok, failed = self:Apply(on)
    if ok == "later" then
        Debug:Info(GA.L.HL_LATER)
    elseif on and not ok then
        Debug:Warn(GA.L.HL_FAILED, table.concat(failed or {}, ", "))
    end
    return ok
end

-- ================================================================ Hinweis ---
--
-- WAS DAS MARKIERTE OBJEKT FUER DICH IST (06.10.2026). Gemessen am selben
-- Abend auf Forever: PLAYER_SOFT_INTERACT_CHANGED(alt, neu) liefert die
-- Objekt-GUID ("GameObject-0-4621-1-35165-1617-…", das sechste Feld ist die
-- Objektkennung: 1617 = Silberblatt), UnitName("softinteract") den Namen.
-- UnitExists ist fuer Objekte false — das ist kein Fehler, Objekte sind
-- keine Einheiten.
--
-- Daraus wird ein kleiner Hinweis unter der Bildmitte:
--   * Kraut oder Erz: die noetige Berufsstufe, gefaerbt wie im Spiel
--     (rot: noch nicht, orange/gelb/gruen: steigert, grau: nicht mehr),
--     und ob dein Beruf reicht.
--   * Ein offenes Questziel, in dessen Text der Objektname steht: die Quest
--     mit Fortschritt.
-- Sonst nichts. Bekannte Kraeuter und Erze stehen unten mit Kennung und
-- Stufe — Kennungen sind nicht uebersetzt, Namen schon.

Highlight.HERBALISM, Highlight.MINING = 182, 186

--- [Objektkennung] = { Fertigkeitslinie, noetige Stufe }
Highlight.NODES = {
    -- Kraeuterkunde
    [1618] = { 182, 1 }, [1617] = { 182, 1 }, [1619] = { 182, 15 }, [1620] = { 182, 50 },
    [1621] = { 182, 70 }, [2045] = { 182, 85 }, [1622] = { 182, 100 }, [1623] = { 182, 115 },
    [1628] = { 182, 120 }, [1624] = { 182, 125 }, [2041] = { 182, 150 }, [2042] = { 182, 160 },
    [2046] = { 182, 170 }, [2043] = { 182, 185 }, [2044] = { 182, 195 }, [2866] = { 182, 205 },
    [142140] = { 182, 210 }, [142141] = { 182, 220 }, [142142] = { 182, 230 }, [142143] = { 182, 235 },
    [142144] = { 182, 245 }, [142145] = { 182, 250 }, [176583] = { 182, 260 }, [176584] = { 182, 270 },
    [176586] = { 182, 280 }, [176587] = { 182, 285 }, [176588] = { 182, 290 }, [176589] = { 182, 300 },
    -- Bergbau
    [1731] = { 186, 1 }, [1732] = { 186, 65 }, [1610] = { 186, 65 }, [1733] = { 186, 75 },
    [2653] = { 186, 75 }, [1735] = { 186, 125 }, [19903] = { 186, 150 }, [1734] = { 186, 155 },
    [2040] = { 186, 175 }, [2047] = { 186, 230 }, [165658] = { 186, 230 }, [324] = { 186, 245 },
    [175404] = { 186, 275 },
}

--- "GameObject-0-4621-1-35165-1617-…" -> "GameObject", 1617
function Highlight.ParseGUID(guid)
    -- Zerlegt wird nur in Compat.ParseGUID: Dort sitzt die Probe auf
    -- verschleierte Werte (siehe tools/test/secrets.test.js).
    return Compat.ParseGUID(guid)
end

--- Farbe wie beim Sammeln im Spiel: rot, orange, gelb, gruen, grau.
function Highlight.SkillColor(rank, required)
    if not rank or rank < required then return "red" end
    if rank < required + 25 then return "orange" end
    if rank < required + 50 then return "yellow" end
    if rank < required + 100 then return "green" end
    return "gray"
end

--- Was ist dieses Objekt fuer mich?
--- @param professions table|nil [linie] = stufe (nil = nicht messbar)
--- @param quests table|nil { { title, objectives = { { text, finished } } } }
--- @return table|nil { name, lines = { { text, color } }, wanted }
function Highlight.Assess(guid, name, professions, quests)
    local kind, id = Highlight.ParseGUID(guid)
    if kind ~= "GameObject" then return nil end
    if type(name) ~= "string" or not Compat.IsReadable(name) or name == "" then name = nil end
    local L = GA.L
    local out = { name = name, lines = {}, wanted = false }

    local node = id and Highlight.NODES[id]
    if node then
        local line, required = node[1], node[2]
        local profName = line == Highlight.HERBALISM and L.HL_HERBALISM or L.HL_MINING
        local rank = professions and professions[line]
        local color = Highlight.SkillColor(rank, required)
        local text = string.format(L.HL_NEEDS, profName, required)
        if professions and not rank then
            text = text .. "  " .. L.HL_NOT_LEARNED
        elseif rank and rank < required then
            text = text .. "  " .. string.format(L.HL_YOU_HAVE, rank)
        end
        out.lines[#out.lines + 1] = { text = text, color = color }
        out.wanted = rank ~= nil and rank >= required
    end

    if name then
        local lower = string.lower(name)
        for _, quest in ipairs(quests or {}) do
            for _, objective in ipairs(quest.objectives or {}) do
                if not objective.finished and type(objective.text) == "string"
                    and string.find(string.lower(objective.text), lower, 1, true) then
                    out.lines[#out.lines + 1] = { text = string.format(L.HL_QUEST, quest.title or "?", objective.text), color = "quest" }
                    out.wanted = true
                end
            end
        end
    end

    if #out.lines == 0 then return nil end
    return out
end

--- Die eigenen Berufe als [linie] = stufe; nil, wenn der Client sie nicht nennt.
local function readProfessions()
    local list = Compat.GetProfessionLines()
    if not list then return nil end
    local out = {}
    for _, p in ipairs(list) do out[p.line] = p.rank end
    return out
end

--- Offene Questziele (nur unfertige Quests).
local function readQuests()
    local log = Compat.GetQuestLog()
    if not log then return nil end
    local out = {}
    for _, quest in ipairs(log) do
        if not quest.complete then
            local objectives = Compat.GetQuestObjectives(quest.index, quest.questID)
            if objectives then out[#out + 1] = { title = quest.title, objectives = objectives } end
        end
    end
    return out
end

--- Das markierte Objekt hat gewechselt.
function Highlight:OnSoftInteract(newGUID)
    if GA.Core.Config:Get("highlightHints") == false then return end
    if newGUID == self.currentGUID then return end      -- dasselbe Objekt meldet sich mehrfach
    self.currentGUID = newGUID
    if not newGUID or not Compat.IsReadable(newGUID) then
        self.currentGUID = nil
        GA.Core.Callbacks:Fire("HIGHLIGHT_HINT", nil)
        return
    end
    local okName, name = pcall(_G.UnitName or function() end, "softinteract")
    local result = Highlight.Assess(newGUID, okName and name or nil, readProfessions(), readQuests())
    GA.Core.Callbacks:Fire("HIGHLIGHT_HINT", result)
    if result and result.wanted and GA.Core.Config:Get("highlightSound") == true then
        Compat.PlaySoundKit("MAP_PING", 3175)
    end
end

-- ================================================================ Reichweite --

Highlight.RANGE_MIN, Highlight.RANGE_MAX, Highlight.RANGE_STEP = 10, 60, 5

function Highlight.Range()
    local range = tonumber(GA.Core.Config:Get("objectHighlightRange")) or 20
    return math.max(Highlight.RANGE_MIN, math.min(Highlight.RANGE_MAX, range))
end

--- Reichweite aendern. Ob das Spiel mehr als 20 annimmt, ist nicht
--- bekannt — deshalb wird zurueckgelesen und gesagt, was gilt.
--- @return number reichweite, boolean|nil angenommen (nil = Schalter aus)
function Highlight:SetRange(range)
    range = math.max(Highlight.RANGE_MIN, math.min(Highlight.RANGE_MAX, math.floor(tonumber(range) or 20)))
    GA.Core.Config:Set("objectHighlightRange", range)
    if not self:IsOn() or Compat.InCombat() then return range, nil end
    local accepted = Compat.SetCVar("SoftTargetInteractRange", range)
    return range, accepted, Compat.GetCVar("SoftTargetInteractRange")
end

-- ================================================================ Messung ---

local MEASURE_EVENTS = { "PLAYER_SOFT_TARGET_INTERACTION", "PLAYER_SOFT_INTERACT_CHANGED" }

--- Was der Client ueber das markierte Objekt sagt — jeder Wert einzeln
--- geprueft, nichts davon vorausgesetzt.
function Highlight.Describe(unit)
    local parts = {}
    local function add(label, fn, ...)
        if type(fn) ~= "function" then parts[#parts + 1] = label .. "=<fehlt>" return end
        local ok, a, b = pcall(fn, ...)
        if not ok then parts[#parts + 1] = label .. "=<Fehler>" return end
        if a ~= nil and not Compat.IsReadable(a) then parts[#parts + 1] = label .. "=<verschleiert>" return end
        -- (nil ist "nil": IsReadable(nil) ist false, verschleiert ist es nicht.)
        parts[#parts + 1] = label .. "=" .. tostring(a) .. (b ~= nil and Compat.IsReadable(b) and ("/" .. tostring(b)) or "")
    end
    add("exists", _G.UnitExists, unit)
    add("name", _G.UnitName, unit)
    add("guid", _G.UnitGUID, unit)
    add("creature", _G.UnitCreatureType, unit)
    add("isPlayer", _G.UnitIsPlayer, unit)
    return table.concat(parts, "  ")
end

function Highlight:Log(line)
    local log = self.measureLog
    if not log then return end
    log[#log + 1] = date("%H:%M:%S") .. "  " .. line
    Debug:Info("|cff8a8a8a[softinteract]|r %s", line)
end

function Highlight:StartMeasure()
    self.measureLog = {}
    local values = {}
    for _, entry in ipairs(Highlight.CVARS) do
        values[#values + 1] = entry[1] .. "=" .. tostring(Compat.GetCVar(entry[1]))
    end
    self:Log("Start. " .. table.concat(values, "  "))
    local Events = GA.Core.Events
    for _, event in ipairs(MEASURE_EVENTS) do
        local ok = Events:Register(event, function(name, ...)
            local args = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                args[#args + 1] = (v == nil or Compat.IsReadable(v)) and tostring(v) or "<verschleiert>"
            end
            Highlight:Log(name .. "(" .. table.concat(args, ", ") .. ")  " .. Highlight.Describe("softinteract"))
        end, "HighlightMeasure")
        self:Log(event .. (ok and ": registriert" or ": GIBT ES NICHT"))
    end
    self:Log("Jetzt ein Kraut, eine Erzader oder ein Questobjekt anschauen. Nochmal /ga probe softinteract beendet.")
end

--- Beendet die Messung. @return string Protokoll
function Highlight:StopMeasure()
    local Events = GA.Core.Events
    for _, event in ipairs(MEASURE_EVENTS) do Events:Unregister(event, "HighlightMeasure") end
    local text = table.concat(self.measureLog or {}, "\n")
    self.measureLog = nil
    return text
end

function Highlight:ToggleMeasure()
    if self.measureLog then return false, self:StopMeasure() end
    self:StartMeasure()
    return true
end

function Highlight:OnEnable()
    local Events = GA.Core.Events
    Events:Register("PLAYER_SOFT_INTERACT_CHANGED", function(_, _, newGUID) Highlight:OnSoftInteract(newGUID) end, "Highlight")
    Events:Register("PLAYER_REGEN_ENABLED", function()
        if Highlight.deferred ~= nil then Highlight:Apply(Highlight.deferred) end
    end, "Highlight")
    -- Beim Einloggen erneut setzen: Hat jemand die Werte zwischendurch von
    -- Hand geaendert, gilt wieder, was der Schalter sagt.
    if self:IsOn() then Compat.After(3, function() Highlight:Apply(true) end) end
end
