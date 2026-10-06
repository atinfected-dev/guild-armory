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
    -- Rundum statt nur vor einem (06.10.2026). Gemessen: Beim Laufen springt
    -- die Markierung mehrmals je Sekunde zwischen Kraut und "nichts", weil
    -- das Objekt aus dem Bogen vor der Figur faellt. 2 = in jeder Richtung.
    { "SoftTargetInteractArc", "2" },
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
-- Daraus wird, was das Zeichen am Objekt zeigt (UI/HighlightFrame):
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

--- Die ersten zwei Woerter ("rocket car") — nil bei nur einem Wort, damit
--- "Iron Deposit" nicht zu jedem Ziel mit "Iron" passt.
function Highlight.TwoWords(text)
    if type(text) ~= "string" then return nil end
    local a, b = string.match(text, "^%s*(%S+)%s+(%S+)")
    return a and (a .. " " .. b) or nil
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
    -- NUR WAS DU KANNST (06.10.2026): Ohne Bergbau keine Erzadern, ohne
    -- Kraeuterkunde keine Kraeuter. Kann der Client die Berufe nicht nennen
    -- (nil), wird gezeigt — lieber eine Erzader zu viel als gar nichts.
    if node and professions and not professions[node[1]] then node = nil end
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
        out.node = line
    end

    if name then
        local lower = string.lower(name)
        local prefix = Highlight.TwoWords(lower)
        for _, quest in ipairs(quests or {}) do
            for _, objective in ipairs(quest.objectives or {}) do
                local text = type(objective.text) == "string" and string.lower(objective.text) or nil
                -- Gleicher Name ("Silverleaf" — "Silverleaf: 2/10"), oder dieselben
                -- ersten zwei Woerter: Das Objekt "Rocket Car Rubble" liefert das
                -- Questziel "Rocket Car Parts".
                local item = text and (string.match(text, "^(.-):") or text)
                if not objective.finished and text and (string.find(text, lower, 1, true)
                    or (prefix and prefix == Highlight.TwoWords(item))) then
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
--- So lange bleibt der Hinweis stehen, nachdem die Markierung weg ist.
Highlight.LINGER = 5
--- So lange klingt dasselbe Objekt nicht noch einmal — gegen das Flackern
--- der Markierung, nicht laenger (06.10.2026: eine Minute war zu lang, "der
--- Sound muss schneller nochmal erklingen").
local SOUND_QUIET = 8

function Highlight:OnSoftInteract(newGUID)
    if not newGUID or not Compat.IsReadable(newGUID) then
        -- MARKIERUNG WEG — DER HINWEIS BLEIBT NOCH EIN WENIG. Gemessen: Sie
        -- flackert beim Laufen mehrmals je Sekunde ab und wieder an. Kommt
        -- dasselbe Objekt binnen LINGER zurueck, hat der Hinweis nie
        -- gewackelt.
        if not self.currentGUID then return end
        self.lingerToken = (self.lingerToken or 0) + 1
        local token = self.lingerToken
        Compat.After(Highlight.LINGER, function()
            if Highlight.lingerToken ~= token then return end
            Highlight.currentGUID = nil
            GA.Core.Callbacks:Fire("HIGHLIGHT_HINT", nil)
        end)
        return
    end
    self.lingerToken = (self.lingerToken or 0) + 1      -- ein laufendes Ausblenden faellt weg
    if newGUID == self.currentGUID then return end      -- dasselbe Objekt meldet sich mehrfach
    self.currentGUID = newGUID
    local okName, name = pcall(_G.UnitName or function() end, "softinteract")
    local result = Highlight.Assess(newGUID, okName and name or nil, readProfessions(), readQuests())
    self.currentResult = result
    GA.Core.Callbacks:Fire("HIGHLIGHT_HINT", result)
    if result and result.wanted and GA.Core.Config:Get("highlightSound") == true then
        -- Ein Ton je Objekt und SOUND_QUIET — nicht bei jedem Flackern.
        self.sounded = self.sounded or {}
        local now = Compat.GetTime()
        if not self.sounded[newGUID] or now - self.sounded[newGUID] > SOUND_QUIET then
            self.sounded[newGUID] = now
            Compat.PlaySoundKit("MAP_PING", 3175)
        end
    end
end

-- ================================================================ Zeichen ---
--
-- EIN EIGENES ZEICHEN AM OBJEKT (06.10.2026). Gemessen am selben Abend: Fuer
-- das markierte Objekt legt das Spiel ein Namensschild an
-- (NAME_PLATE_UNIT_ADDED "nameplate1", UnitGUID = die Objekt-GUID) — auch
-- mit SoftTargetNameplateInteract=0. Ein Namensschild sitzt in der Welt
-- ueber dem Objekt; was man daran haengt, wandert mit. Das Zeichen lebt
-- deshalb genau so lange wie das Schild: Ein Addon kann einen Ort in der
-- Welt nicht selbst festhalten.
--
-- Nur fuer OBJEKTE — Namensschilder kommen auch fuer jede Kreatur, und die
-- gehen dieses Modul nichts an.

--- Ein Namensschild ist erschienen.
--- @return table|nil das Ergebnis, das am Schild gezeigt wird
function Highlight:OnPlateAdded(unit)
    if GA.Core.Config:Get("highlightMarker") == false then return nil end
    if type(unit) ~= "string" or not _G.UnitGUID then return nil end
    local ok, guid = pcall(_G.UnitGUID, unit)
    if not ok or not guid then return nil end
    local kind = Highlight.ParseGUID(guid)
    if kind ~= "GameObject" then return nil end
    local result = self.currentResult
    if guid ~= self.currentGUID or not result then
        local okName, name = pcall(_G.UnitName or function() end, unit)
        result = Highlight.Assess(guid, okName and name or nil, readProfessions(), readQuests())
    end
    if not result then return nil end
    self.plates = self.plates or {}
    self.plates[unit] = true
    GA.Core.Callbacks:Fire("HIGHLIGHT_PLATE", unit, result)
    return result
end

function Highlight:OnPlateRemoved(unit)
    if not self.plates or not self.plates[unit] then return end
    self.plates[unit] = nil
    GA.Core.Callbacks:Fire("HIGHLIGHT_PLATE_GONE", unit)
end

-- ================================================================ Taste ------

--- Blizzards Aktion "Mit Ziel interagieren". Mit eingeschalteter Markierung
--- gilt sie dem markierten Objekt — Kraut abbauen, Erz abbauen, Truhe
--- oeffnen, alles mit einer Taste. Die Aktion fuehrt das SPIEL aus; das
--- Addon legt nur die Taste darauf.
Highlight.INTERACT_ACTION = "INTERACTTARGET"

--- @return boolean gesetzt, string|nil grund
function Highlight:SetInteractKey(key)
    if type(key) ~= "string" or key == "" then return false, "failed" end
    return Compat.SetBindingKey(key, Highlight.INTERACT_ACTION)
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

local MEASURE_EVENTS = { "PLAYER_SOFT_TARGET_INTERACTION", "PLAYER_SOFT_INTERACT_CHANGED",
    -- Legt das Spiel fuer markierte Objekte ein Namensschild an? Dann liesse
    -- sich dort ein eigenes Zeichen anhaengen (06.10.2026).
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

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

--- Gibt es ein Namensschild fuer das markierte Objekt?
function Highlight.PlateInfo()
    local api = _G.C_NamePlate
    if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then return "<keine API>" end
    local ok, plate = pcall(api.GetNamePlateForUnit, "softinteract")
    if not ok then return "<Fehler>" end
    return plate and "ja" or "nein"
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
    values[#values + 1] = "SoftTargetNameplateInteract=" .. tostring(Compat.GetCVar("SoftTargetNameplateInteract"))
    self:Log("Start. " .. table.concat(values, "  "))
    local Events = GA.Core.Events
    for _, event in ipairs(MEASURE_EVENTS) do
        local ok = Events:Register(event, function(name, ...)
            local args = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                args[#args + 1] = (v == nil or Compat.IsReadable(v)) and tostring(v) or "<verschleiert>"
            end
            Highlight:Log(name .. "(" .. table.concat(args, ", ") .. ")  " .. Highlight.Describe("softinteract")
                .. "  plate=" .. Highlight.PlateInfo())
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
    Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit) Highlight:OnPlateAdded(unit) end, "Highlight")
    Events:Register("NAME_PLATE_UNIT_REMOVED", function(_, unit) Highlight:OnPlateRemoved(unit) end, "Highlight")
    Events:Register("PLAYER_REGEN_ENABLED", function()
        if Highlight.deferred ~= nil then Highlight:Apply(Highlight.deferred) end
    end, "Highlight")
    -- Beim Einloggen erneut setzen: Hat jemand die Werte zwischendurch von
    -- Hand geaendert, gilt wieder, was der Schalter sagt.
    if self:IsOn() then Compat.After(3, function() Highlight:Apply(true) end) end
end
