--[[----------------------------------------------------------------------------
    Assist/Leveling — Zaehler fuer die Levelleiste.

    Was in diesem Level und in dieser Sitzung passiert ist: Erfahrung, Kills,
    Tode, Quests, Gold — und daraus die Raten: XP je Stunde, Zeit bis zum
    naechsten Level, Gold je Minute. Kein UI; die Leiste (UI/LevelBar) fragt
    Leveling:Snapshot() und malt, was eingeschaltet ist (08.10.2026, Wunsch
    nach einer eigenen Leiste wie in Level Time, Apache 2.0 — hier neu
    geschrieben, nur die Spielmechanik ist dieselbe).

    ZWEI BEREICHE. "Level" zaehlt seit dem letzten Aufstieg und ueberlebt
    /reload (pro Charakter gespeichert). "Sitzung" zaehlt seit dem Einloggen
    oder dem letzten /ga levelbar reset und lebt nur im Arbeitsspeicher.

    DIE XP-RATE IST EIN FENSTER, KEIN DURCHSCHNITT. Ein Durchschnitt ueber das
    ganze Level sagt nach einer Stunde Stadt noch "2000 XP/h"; das Fenster
    der letzten 15 Minuten sagt die Wahrheit. Erst nach einer Minute Messung
    gibt es eine Zahl, davor steht ein Strich.

    KILLS AUS DER CHATZEILE. "X stirbt, Ihr erhaltet N Erfahrung" ist eine
    Chatnachricht (CHAT_MSG_COMBAT_XP_GAIN), kein Kampflog — und der ist auf
    Forever gesperrt. Das Muster kommt aus der Spieltext-Vorlage
    COMBATLOG_XPGAIN_FIRSTPERSON, nicht aus einer eigenen Liste.
------------------------------------------------------------------------------]]

local _, GA = ...

local Leveling = {}
GA.Modules.Leveling = Leveling

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

Leveling.WINDOW = 15 * 60       -- Sekunden, ueber die die XP-Rate gerechnet wird
local SAMPLE_INTERVAL = 30      -- Sekunden zwischen zwei Messpunkten
local MIN_SPAN = 60             -- darunter schwankt die Rate zu stark

local function fresh(ts)
    return { start = ts, xp = 0, kills = 0, deaths = 0, quests = 0, gained = 0, spent = 0 }
end

local function store()
    local char = GA.Core.Database.char
    if not char then return nil end
    char.leveling = char.leveling or {}
    return char.leveling
end

--- Der Levelzaehler, angelegt beim ersten Blick.
function Leveling:Level()
    local db = store()
    if not db then return fresh(Util.Now()) end
    if not db.level or db.level.levelNumber ~= (Compat.GetPlayerIdentity().level or 0) then
        db.level = fresh(Util.Now())
        db.level.levelNumber = Compat.GetPlayerIdentity().level or 0
    end
    return db.level
end

--- Der Sitzungszaehler; neu nach Einloggen oder Reset.
function Leveling:Session()
    if not self.session then self.session = fresh(Util.Now()) end
    return self.session
end

function Leveling:ResetSession()
    self.session = fresh(Util.Now())
    self.samples = {}
    GA.Core.Callbacks:Fire("LEVELING_CHANGED")
end

-- ================================================================ Zaehlen ---

local function bump(self, key, amount)
    amount = amount or 1
    local level, session = self:Level(), self:Session()
    level[key] = (level[key] or 0) + amount
    session[key] = (session[key] or 0) + amount
end

--- Das Kill-Muster aus der Spieltext-Vorlage: "%s dies, you gain %d experience."
local killPattern
local function isKillLine(message)
    if killPattern == nil then
        local template = _G.COMBATLOG_XPGAIN_FIRSTPERSON
        if type(template) ~= "string" then killPattern = false
        else
            local p = string.gsub(template, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            p = string.gsub(p, "%%%%s", "(.-)")
            p = string.gsub(p, "%%%%d", "(%%d+)")
            killPattern = "^" .. p
        end
    end
    if not killPattern then
        -- Ohne Vorlage: jede Zeile mit einem Namen vor dem Gewinn zaehlt.
        return string.find(message or "", "%S+.-%d+") ~= nil and not string.find(message or "", "^You")
    end
    return string.find(message or "", killPattern) ~= nil
end
Leveling.IsKillLine = isKillLine

function Leveling:OnXpGainLine(message)
    if isKillLine(message) then bump(self, "kills") end
end

function Leveling:OnXpUpdate()
    local xp, xpMax = Compat.GetXP()
    if not xp then return end
    local last = self.lastXp
    self.lastXp, self.lastXpMax = xp, xpMax
    if last == nil then return end
    local gained = xp - last
    -- Aufstieg: Der neue Stand ist der Gewinn seit null, der Rest des alten
    -- Levels war schon gezaehlt, als PLAYER_LEVEL_UP kam.
    if gained < 0 then gained = xp end
    if gained > 0 then
        bump(self, "xp", gained)
        self:Sample(gained)
    end
end

function Leveling:OnLevelUp(newLevel)
    local db = store()
    local level = self:Level()
    -- Das alte Level ins Archiv: wie lange, wie viele — fuer spaeter.
    if db then
        db.history = db.history or {}
        local played = self:PlayedLevel()
        db.history[#db.history + 1] = { level = level.levelNumber, seconds = played,
            kills = level.kills, deaths = level.deaths, quests = level.quests, xp = level.xp,
            gained = level.gained, ts = Util.Now() }
        while #db.history > 80 do table.remove(db.history, 1) end
        db.level = fresh(Util.Now())
        db.level.levelNumber = tonumber(newLevel) or ((level.levelNumber or 0) + 1)
    end
    self.playedLevelBase = { seconds = 0, ts = Util.Now() }
    self.lastXp = 0
    GA.Core.Callbacks:Fire("LEVELING_CHANGED")
end

function Leveling:OnMoney()
    local money = Compat.GetMoney()
    if not money then return end
    local last = self.lastMoney
    self.lastMoney = money
    if last == nil then return end
    local delta = money - last
    if delta > 0 then bump(self, "gained", delta)
    elseif delta < 0 then bump(self, "spent", -delta) end
end

-- ================================================================ Rate ------

--- Ein Messpunkt: wie viel XP seit dem letzten dazukam.
function Leveling:Sample(gained)
    self.samples = self.samples or {}
    local now = Util.Now()
    local last = self.samples[#self.samples]
    if last and now - last.at < SAMPLE_INTERVAL then
        last.gained = last.gained + gained
    else
        self.samples[#self.samples + 1] = { at = now, gained = gained }
    end
    while self.samples[1] and now - self.samples[1].at > self.WINDOW do
        table.remove(self.samples, 1)
    end
end

--- XP je Stunde im Fenster; nil, solange weniger als eine Minute gemessen ist.
function Leveling:XpPerHour()
    local samples = self.samples or {}
    local now = Util.Now()
    local since = self.windowStart or now
    local total = 0
    local oldest = since
    for _, s in ipairs(samples) do
        if s.at < oldest then oldest = s.at end
        total = total + s.gained
    end
    if oldest > now - self.WINDOW then oldest = math.max(since, now - self.WINDOW) end
    local span = now - oldest
    if span < MIN_SPAN then return nil end
    return total / span * 3600
end

-- ================================================================ Zeit ------

--- Spielzeit in diesem Level: der letzte Stand vom Server plus das, was
--- seither verging. Ohne Stand: seit dem Zaehlerstart.
function Leveling:PlayedLevel()
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    local played = character and character.played
    if played and played.level and played.ts then
        return played.level + (Util.Now() - played.ts)
    end
    return Util.Now() - (self:Level().start or Util.Now())
end

function Leveling:PlayedTotal()
    local identity = Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    local played = character and character.played
    if played and played.total and played.ts then
        return played.total + (Util.Now() - played.ts)
    end
    return nil
end

--- "1d 02:03", "02:03:04", "03:04" — immer mindestens Minuten:Sekunden.
function Leveling.FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local d = math.floor(seconds / 86400)
    local h = math.floor(seconds % 86400 / 3600)
    local m = math.floor(seconds % 3600 / 60)
    local s = seconds % 60
    if d > 0 then return string.format("%dd %02d:%02d", d, h, m) end
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- ================================================================ Snapshot --

--- Alles, was die Leiste zeigt — einmal gerechnet, je Takt.
--- @param scope string "level" | "session"
function Leveling:Snapshot(scope)
    local counters = scope == "session" and self:Session() or self:Level()
    local identity = Compat.GetPlayerIdentity()
    local xp, xpMax, rested = Compat.GetXP()
    local maxLevel = (xpMax or 0) <= 0 or (identity.level or 0) >= (Compat.GetMaxPlayerLevel() or 60)
    local now = Util.Now()
    local elapsed = math.max(1, now - (counters.start or now))
    local rate = self:XpPerHour()
    local out = {
        level = identity.level, xp = xp, xpMax = xpMax, rested = rested, maxLevel = maxLevel,
        pct = (xp and xpMax and xpMax > 0) and xp / xpMax or 0,
        playedLevel = self:PlayedLevel(), playedTotal = self:PlayedTotal(),
        session = now - (self:Session().start or now),
        xpPerHour = rate,
        kills = counters.kills or 0, deaths = counters.deaths or 0, quests = counters.quests or 0,
        gained = counters.gained or 0, spent = counters.spent or 0,
        goldPerMinute = (counters.gained or 0) / (elapsed / 60),
        scope = scope,
    }
    if rate and rate > 0 and xp and xpMax and xpMax > xp then
        out.timeToLevel = (xpMax - xp) / rate * 3600
    end
    return out
end

-- ================================================================ Start -----

function Leveling:OnEnable()
    local Events = GA.Core.Events
    self.windowStart = Util.Now()
    self.samples = {}
    Events:Register("PLAYER_XP_UPDATE", function() Leveling:OnXpUpdate() end, "Leveling")
    Events:Register("PLAYER_LEVEL_UP", function(_, level) Leveling:OnLevelUp(level) end, "Leveling")
    Events:Register("PLAYER_MONEY", function() Leveling:OnMoney() end, "Leveling")
    Events:Register("PLAYER_DEAD", function() bump(Leveling, "deaths") GA.Core.Callbacks:Fire("LEVELING_CHANGED") end, "Leveling")
    Events:Register("QUEST_TURNED_IN", function() bump(Leveling, "quests") end, "Leveling")
    Events:Register("CHAT_MSG_COMBAT_XP_GAIN", function(_, message) Leveling:OnXpGainLine(message) end, "Leveling")
    Events:Register("PLAYER_ENTERING_WORLD", function()
        Leveling.lastXp = Compat.GetXP()
        Leveling.lastMoney = Compat.GetMoney()
        Leveling:Level()
        -- Blizzards XP-Leiste: aus, wenn so eingestellt. Etwas spaeter, weil
        -- das Spiel seine Leisten nach dem Betreten erst anordnet.
        if GA.Core.Config:Get("hideBlizzardXpBar") then
            Compat.After(1, function() Compat.SetBlizzardXpBarHidden(true) end)
        end
    end, "Leveling")
    -- Nach dem Kampf nachholen, was im Kampf nicht ging.
    Events:Register("PLAYER_REGEN_ENABLED", function()
        if GA.Core.Config:Get("hideBlizzardXpBar") then Compat.SetBlizzardXpBarHidden(true) end
    end, "Leveling")
    if GA.UI.LevelBar then GA.UI.LevelBar:OnEnable() end
    Debug:Print("level", "Levelzaehler an")
end
