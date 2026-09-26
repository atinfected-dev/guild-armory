--[[----------------------------------------------------------------------------
    Armory/LevelUp — Glueckwunsch im Gildenchat, wenn jemand aufsteigt.

    Kein UI. Haengt an GUILD_LEVELUP (Armory/Guild.lua) und schreibt in den
    Gildenchat.

    ===========================================================================
    ZWEI DINGE MACHEN DAS HEIKEL, UND BEIDE STEHEN IM AUFBAU
    ===========================================================================

    1. FUENF LEUTE MIT DEM ADDON HEISST FUENF GLUECKWUENSCHE.

       Jeder Client liest dasselbe Roster und sieht denselben Aufstieg. Ohne
       Absprache schreiben alle dasselbe in denselben Chat — und aus einer
       netten Geste wird das, was die Gilde als Erstes abschaltet.

       Deshalb meldet der, der es zuerst sieht, seinen Anspruch ueber den
       Addon-Kanal an und wartet kurz. Wer in dieser Zeit einen fremden
       Anspruch fuer denselben Aufstieg sieht, schweigt. Wer keinen sieht,
       schreibt.

       DIE WARTEZEIT IST ZUFAELLIG VERTEILT. Warteten alle gleich lang,
       schickten alle gleichzeitig ihren Anspruch und keiner saehe den
       anderen rechtzeitig — dasselbe Muster wie bei den Kartenpositionen.

    2. ES SCHREIBT IM NAMEN DES SPIELERS.

       Ein Addon, das ungefragt in den Gildenchat schreibt, ist ein Addon,
       das man erklaeren muss. Deshalb ist es AUS, bis jemand es einschaltet,
       und es sagt beim Einschalten, was es tun wird.

    ===========================================================================
    NICHT JEDE STUFE
    ===========================================================================

    Von 1 auf 2 gratuliert niemand. Voreingestellt sind runde Zehner und die
    Hoechststufe — das sind die Stufen, bei denen in einer Gilde tatsaechlich
    etwas gesagt wird. Wer alles will, stellt den Schwellwert auf 1.
------------------------------------------------------------------------------]]

local _, GA = ...

local LevelUp = {}
GA.Modules.LevelUp = LevelUp

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local L = GA.L

--- Wie lange auf fremde Ansprueche gewartet wird, bevor geschrieben wird.
--- Zufaellig verteilt: siehe Dateikopf.
local ANSPRUCH_SPREIZUNG = 4

--- Wie lange ein Anspruch gilt. Laenger als die Spreizung, kuerzer als ein
--- Abend — sonst sammelt sich der Speicher mit Aufstiegen von gestern.
local ANSPRUCH_TTL = 60

--- [name .. ":" .. level] = Zeitpunkt. Wer hier steht, ist vergeben.
LevelUp.beansprucht = {}

local function comm()
    return GA.Core.Comm
end

local function schluessel(name, level)
    return string.lower(Util.ShortName(name or "")) .. ":" .. tostring(level)
end

--- Alte Ansprueche wegraeumen. Billig und selten: laeuft nur, wenn ohnehin
--- ein Aufstieg verarbeitet wird.
function LevelUp:Prune()
    local jetzt = Util.Now()
    for key, ts in pairs(self.beansprucht) do
        if (jetzt - ts) > ANSPRUCH_TTL then self.beansprucht[key] = nil end
    end
end

--- Lohnt sich fuer diese Stufe eine Ansage?
---
--- @return boolean
function LevelUp:IsWorthAnnouncing(level)
    if type(level) ~= "number" then return false end

    local ab = GA.Core.Config:Get("levelUpMinLevel") or 10
    if level < ab then return false end

    if GA.Core.Config:Get("levelUpEveryLevel") then return true end

    -- Runde Zehner und die Hoechststufe. Die Hoechststufe steht NICHT fest
    -- verdrahtet: Forever hat 60, und eine Zahl im Code waere beim naechsten
    -- Mal falsch.
    local max = Compat.GetMaxPlayerLevel()
    if max and level >= max then return true end
    return level % 10 == 0
end

-- ================================================================ Ansage -----

function LevelUp:OnLevelUp(aufstieg)
    if not aufstieg or not aufstieg.name or not aufstieg.level then return end
    if not GA.Core.Config:Get("levelUpAnnounce") then return end
    if not self:IsWorthAnnouncing(aufstieg.level) then return end

    -- NICHT UEBER SICH SELBST. Wer aufsteigt, bekommt vom Spiel schon einen
    -- Tusch; sich selbst im Gildenchat zu gratulieren ist etwas anderes als
    -- gratuliert zu werden.
    local identity = Compat.GetPlayerIdentity()
    if identity.name and Util.SameCharacter(aufstieg.name, identity.name) then return end

    self:Prune()
    local key = schluessel(aufstieg.name, aufstieg.level)
    if self.beansprucht[key] then return end
    self.beansprucht[key] = Util.Now()

    -- Anspruch anmelden und warten. Sieht in der Zeit jemand anders
    -- dasselbe, hat einer von beiden zuerst gesendet — und der andere
    -- schweigt (siehe OnClaim).
    if comm() then
        comm():Send("LVLUP", { Util.ShortName(aufstieg.name), aufstieg.level })
    end

    local wartezeit = 1 + math.random() * ANSPRUCH_SPREIZUNG
    Compat.After(wartezeit, function()
        -- In der Wartezeit kann ein fremder Anspruch gekommen sein; der
        -- traegt den Schluessel dann als "fremd" ein.
        if LevelUp.beansprucht[key] == false then return end
        LevelUp:Announce(aufstieg)
    end)
end

function LevelUp:Announce(aufstieg)
    local text = string.format(L.LEVELUP_MESSAGE,
        Util.ShortName(aufstieg.name), tostring(aufstieg.level))

    if not Compat.SendChatMessage(text, "GUILD") then
        Debug:Print("guild", "Glueckwunsch nicht gesendet: %s", text)
        return
    end
    Debug:Print("guild", "Glueckwunsch gesendet: %s", text)
end

--- Ein fremder Client meldet denselben Aufstieg.
---
--- WER ZUERST KOMMT, SCHREIBT. Der eigene Anspruch wird auf false gesetzt —
--- das heisst "vergeben, aber nicht von mir", und beide Zustaende muessen
--- unterscheidbar bleiben: nil waere "noch frei" und fuehrte dazu, dass der
--- naechste Durchlauf es doch noch schreibt.
function LevelUp:OnClaim(sender, fields)
    local name, level = fields[1], tonumber(fields[2])
    if not name or not level then return end

    local identity = Compat.GetPlayerIdentity()
    if identity.name and Util.SameCharacter(sender, identity.name) then return end

    self.beansprucht[schluessel(name, level)] = false
    Debug:Print("guild", "%s uebernimmt den Glueckwunsch fuer %s (%d)",
        tostring(sender), tostring(name), level)
end

-- ================================================================== Start ----

function LevelUp:OnEnable()
    GA.Core.Callbacks:On("GUILD_LEVELUP", function(aufstieg)
        LevelUp:OnLevelUp(aufstieg)
    end, "LevelUp")

    if comm() then
        comm():On("LVLUP", function(sender, fields) LevelUp:OnClaim(sender, fields) end,
            "LevelUp")
    end
end
