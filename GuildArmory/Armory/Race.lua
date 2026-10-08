--[[----------------------------------------------------------------------------
    Armory/Race — das Rennen zur Hoechststufe.

    Wer in der Gilde wie weit ist, wer zuerst oben war, wer je Klasse zuerst
    (08.10.2026, Wunsch: "Leaderboard fuer das Race to 60"). Die Daten
    kommen aus dem Gildenroster (Stufe, Klasse, online), aus dem Abgleich
    (XP-Prozent und Spielzeit, die jeder ueber sich selbst schickt) und aus
    den Aufstiegen, die dieser Client SIEHT (Armory/Guild feuert
    GUILD_LEVELUP, wenn eine Stufe im Roster steigt).

    DREI ARTEN, OBEN ANGEKOMMEN ZU SEIN — und sie werden nicht vermischt:
      live     Dieser Client hat den Aufstieg gesehen; die Zeit stimmt.
      before   War schon oben, als die Erfassung begann. Reihenfolge
               unbekannt, deshalb stehen sie ganz vorn, ohne Zeit.
      by       Beim ersten Roster einer spaeteren Sitzung schon oben:
               irgendwann, waehrend niemand hinsah — spaetestens dann.
    Ein "Erster" kann nur ein live gesehener sein. Wer behauptet, Erster
    gewesen zu sein, obwohl der Client gar nicht da war, luegt.

    JE GILDE GESPEICHERT, nicht je Charakter: Das Rennen gehoert der Gilde.
------------------------------------------------------------------------------]]

local _, GA = ...

local Race = {}
GA.Modules.Race = Race

local Compat = GA.Core.Compat
local Util = GA.Core.Util

--- So nah am Beginn der Erfassung zaehlt ein Stand als "war schon da".
local FIRST_ROSTER = 60

local function key(name)
    return string.lower(Util.ShortName(name or ""))
end

local function store()
    local account = GA.Core.Database.account
    account.race = account.race or {}
    local guild = (account.guild and account.guild.name) or "?"
    local g = account.race[guild]
    if not g then
        g = { since = Util.Now(), seen = {}, classFirst = {}, dings = {} }
        account.race[guild] = g
    end
    return g
end

function Race:MaxLevel()
    return Compat.GetMaxPlayerLevel() or 60
end

function Race:Data() return store() end

-- ================================================================ Erfassen --

--- Ein Aufstieg, den dieser Client gesehen hat (eigener oder aus dem Roster).
--- @return table|nil finish, table|nil firsts { first, classFirst }
function Race:OnLevelUp(name, level, class)
    level = tonumber(level)
    if not name or not level then return nil end
    local g = store()
    local k = key(name)
    g.dings[k] = g.dings[k] or {}
    if g.dings[k][level] then return nil end          -- schon gesehen (Roster nach PLAYER_LEVEL_UP)
    g.dings[k][level] = Util.Now()
    local finish, firsts
    if level >= self:MaxLevel() then finish, firsts = self:RecordFinish(name, class, true) end
    GA.Core.Callbacks:Fire("RACE_CHANGED")
    return finish, firsts
end

--- Jemand ist oben. live = der Aufstieg wurde gesehen.
function Race:RecordFinish(name, class, live)
    local g = store()
    local k = key(name)
    if g.seen[k] then return nil, nil end
    local entry = { name = Util.ShortName(name), class = class, at = Util.Now(), live = live and true or false }
    g.seen[k] = entry
    local firsts = {}
    if live then
        if not g.first then g.first = entry firsts.first = true end
        if class and not g.classFirst[class] then g.classFirst[class] = entry firsts.classFirst = true end
    end
    return entry, firsts
end

--- Roster-Durchlauf: Wer oben ist, ohne dass wir es sahen, wird mit dem
--- Zeitpunkt des Sehens vermerkt. Beim allerersten Roster heisst das
--- "war schon da".
function Race:Scan()
    local Guild = GA.Modules.Guild
    if not Guild or not Guild.List then return end
    local g = store()
    g.firstRoster = g.firstRoster or Util.Now()
    local max = self:MaxLevel()
    for _, m in ipairs(Guild:List()) do
        if (m.level or 0) >= max and m.name then self:RecordFinish(m.name, m.class, false) end
    end
end

--- "live" | "before" | "by" | nil
function Race:How(entry)
    if not entry then return nil end
    if entry.live then return "live" end
    local g = store()
    local start = g.firstRoster or g.since
    if start and (entry.at or 0) - start <= FIRST_ROSTER then return "before" end
    return "by"
end

-- ================================================================ Tabelle ---

--- Die Rangliste. Oben, wer oben ist (erst "war schon da", dann nach
--- Zeit), dann alle anderen nach Stufe, XP-Prozent und Name.
--- @param filter table|nil { class = "MAGE", online = true }
--- @return table rows { position, name, class, level, pct, played, online, finish, how, lastDing }
function Race:Board(filter)
    filter = filter or {}
    local Guild = GA.Modules.Guild
    local db = GA.Core.Database
    local identity = Compat.GetPlayerIdentity()
    local g = store()
    local max = self:MaxLevel()
    local rows = {}
    for _, m in ipairs(Guild and Guild.List and Guild:List() or {}) do
        local keep = m.name ~= nil
        if keep and filter.class and m.class ~= filter.class then keep = false end
        if keep and filter.online and not m.online then keep = false end
        if keep then
            local k = key(m.name)
            local character = db.FindCharacterByName and db:FindCharacterByName(m.name) or nil
            local me = identity.name and Util.SameCharacter(m.name, identity.name)
            local pct = character and character.xpPct or nil
            if me then
                local xp, xpMax = Compat.GetXP()
                if xp and xpMax and xpMax > 0 then pct = xp / xpMax * 100 end
            end
            local finish = (m.level or 0) >= max and g.seen[k] or nil
            local lastDing
            for level, ts in pairs(g.dings[k] or {}) do
                if not lastDing or ts > lastDing.ts then lastDing = { level = level, ts = ts } end
            end
            rows[#rows + 1] = {
                name = m.name, class = m.class, level = m.level or 0, pct = pct,
                played = character and character.played and character.played.total or nil,
                online = m.online and true or false, me = me or nil,
                finish = finish, how = self:How(finish), lastDing = lastDing,
            }
        end
    end
    local function stage(r)
        if not r.finish then return 3 end
        return r.how == "before" and 1 or 2
    end
    table.sort(rows, function(a, b)
        local sa, sb = stage(a), stage(b)
        if sa ~= sb then return sa < sb end
        if sa == 2 and (a.finish.at or 0) ~= (b.finish.at or 0) then return (a.finish.at or 0) < (b.finish.at or 0) end
        if a.level ~= b.level then return a.level > b.level end
        if (a.pct or -1) ~= (b.pct or -1) then return (a.pct or -1) > (b.pct or -1) end
        return a.name < b.name
    end)
    for index, r in ipairs(rows) do r.position = index end
    return rows
end

--- Mein Platz im ganzen Feld.
--- @return number|nil platz, number gesamt
function Race:MyPosition()
    local rows = self:Board()
    for _, r in ipairs(rows) do
        if r.me then return r.position, #rows end
    end
    return nil, #rows
end

--- Die Ersten: gesamt und je Klasse, nur live gesehene.
function Race:Firsts()
    local g = store()
    return g.first, g.classFirst, g.firstRoster or g.since
end

-- ================================================================ Start -----

function Race:OnEnable()
    GA.Core.Callbacks:On("GUILD_LEVELUP", function(aufstieg)
        if not aufstieg then return end
        local finish, firsts = Race:OnLevelUp(aufstieg.name, aufstieg.level, aufstieg.class)
        local identity = Compat.GetPlayerIdentity()
        local me = identity.name and Util.SameCharacter(aufstieg.name, identity.name)
        if me then return end
        -- Die Gilde erfaehrt es als Meldung; ein Erster bekommt das Banner.
        local worth = GA.Modules.LevelUp and GA.Modules.LevelUp:IsWorthAnnouncing(aufstieg.level)
        if worth and GA.UI.Notifications and GA.UI.Notifications.Push then
            GA.UI.Notifications:Push({
                kind = "DING", who = aufstieg.name, class = aufstieg.class,
                text = GA.L.NOTIFY_DING, object = tostring(aufstieg.level), objectColor = GA.UI.Theme.color.goldBright,
                action = { label = GA.L.NOTIFY_ACT_RACE, view = "race" },
            })
        end
        if firsts and (firsts.first or firsts.classFirst) and GA.UI.DingFrame then
            GA.UI.DingFrame:ShowFirst(aufstieg.name, aufstieg.class, firsts.first and true or false)
        end
    end, "Race")
    GA.Core.Callbacks:On("GUILD_UPDATED", function() Race:Scan() end, "Race")
    GA.Core.Events:Register("PLAYER_LEVEL_UP", function(_, level)
        local identity = Compat.GetPlayerIdentity()
        Race:OnLevelUp(identity.name, tonumber(level), identity.class)
    end, "Race")
    if GA.UI.DingFrame then GA.UI.DingFrame:OnEnable() end
end
