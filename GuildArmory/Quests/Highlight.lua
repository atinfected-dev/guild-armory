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
    { "SoftTargetInteractRange", "20" },
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
                args[#args + 1] = Compat.IsReadable(v) and tostring(v) or "<verschleiert>"
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
    Events:Register("PLAYER_REGEN_ENABLED", function()
        if Highlight.deferred ~= nil then Highlight:Apply(Highlight.deferred) end
    end, "Highlight")
    -- Beim Einloggen erneut setzen: Hat jemand die Werte zwischendurch von
    -- Hand geaendert, gilt wieder, was der Schalter sagt.
    if self:IsOn() then Compat.After(3, function() Highlight:Apply(true) end) end
end
