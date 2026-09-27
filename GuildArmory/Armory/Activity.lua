--[[----------------------------------------------------------------------------
    Armory/Activity — was heute in der Gilde passiert ist, als eine Liste.

    Kein UI. Das Dashboard (Entwurf D1, 27.09.2026) zeigt einen Strom
    "Heute in der Gilde": Stufenaufstiege, Beitritte und Befoerderungen,
    Vergaben, Erfolge, Lagerfeuer. Jede dieser Sachen wird an einer anderen
    Stelle des Addons GEMESSEN und dort als Ereignis gemeldet — aber keine
    davon wird als Ereignis AUFBEWAHRT: Ein Aufstieg ist nach dem Rosterlauf
    nur noch eine hoehere Zahl im Roster, ein Lagerfeuer nur noch ein Pin.

    Dieses Modul hoert die Ereignisse mit und schreibt sie als Eintraege
    weg. Es misst NICHTS selbst: Was hier steht, hat ein anderes Modul
    gemessen, und der Eintrag traegt, welches — die Zeile im Dashboard sagt
    "vom Spiel bestaetigt" oder "von Hand", weil es hier so steht.

    WAS NICHT HINEINKOMMT: Handelbares (steht als Liste daneben, ein Angebot
    ist kein Ereignis), Rezepte (der Scan meldet keine Namen), Positionen
    (das waere ein Strom aus Zonenwechseln). Weniger ist hier mehr: Der
    Strom soll lesbar sein, nicht vollstaendig.

    BEGRENZT. 150 Eintraege, sieben Tage. Ein Dashboard zeigt "heute", eine
    Chronik ist das Journal.
------------------------------------------------------------------------------]]

local _, GA = ...

local Activity = {}
GA.Modules.Activity = Activity

local Util = GA.Core.Util

Activity.LIMIT = 150
Activity.MAX_AGE = 7 * 86400
--- Zwei Meldungen derselben Sache innerhalb dieser Spanne sind eine.
Activity.DEDUPE = 600

Activity.LEVELUP     = "LEVELUP"
Activity.ROSTER      = "ROSTER"
Activity.LOOT        = "LOOT"
Activity.ACHIEVEMENT = "ACHIEVEMENT"
Activity.CAMP        = "CAMP"

local function store()
    local account = GA.Core.Database and GA.Core.Database.account
    if not account then return nil end
    account.activity = account.activity or {}
    return account.activity
end

--- Die Klasse zu einem Namen, aus dem, was das Addon kennt. nil = unbekannt.
local function klasseVon(name)
    if not name then return nil end
    local db = GA.Core.Database
    local character = db and db.FindCharacterByName and db:FindCharacterByName(name)
    if character and character.class then return character.class end

    local kurz = string.lower(Util.ShortName(name))
    local members = db and db.account and db.account.guild and db.account.guild.members
    for _, member in pairs(members or {}) do
        if member.name and string.lower(Util.ShortName(member.name)) == kurz then
            return member.class
        end
    end
    return nil
end

--- Schreibt einen Eintrag. Derselbe Schluessel innerhalb der Spanne ersetzt
--- den alten (ein Loot, das von "vergeben" auf "erhalten" geht, ist EIN
--- Eintrag mit neuem Stand — nicht zwei Zeilen).
function Activity:Add(entry)
    local log = store()
    if not log or not entry or not entry.kind then return nil end

    entry.ts = entry.ts or Util.Now()
    entry.class = entry.class or klasseVon(entry.name)
    local key = entry.key or (entry.kind .. ":" .. string.lower(entry.name or "") .. ":" .. tostring(entry.detail or ""))
    entry.key = key

    for index = #log, 1, -1 do
        local alt = log[index]
        if alt.key == key and (entry.ts - (alt.ts or 0)) <= self.DEDUPE then
            -- Ersetzen, Zeitpunkt des Ersten behalten: Es ist dieselbe Sache.
            entry.ts = alt.ts
            log[index] = entry
            self:Prune()
            GA.Core.Callbacks:Fire("ACTIVITY_CHANGED")
            return entry
        end
    end

    log[#log + 1] = entry
    self:Prune()
    GA.Core.Callbacks:Fire("ACTIVITY_CHANGED")
    return entry
end

function Activity:Prune()
    local log = store()
    if not log then return end
    local grenze = Util.Now() - self.MAX_AGE
    local behalten = {}
    for _, entry in ipairs(log) do
        if (entry.ts or 0) >= grenze then behalten[#behalten + 1] = entry end
    end
    while #behalten > self.LIMIT do table.remove(behalten, 1) end
    for index = #log, 1, -1 do log[index] = nil end
    for index, entry in ipairs(behalten) do log[index] = entry end
end

--- Die Eintraege, neueste zuerst.
--- @param limit number|nil
--- @param since number|nil  nur ab diesem Zeitpunkt
function Activity:List(limit, since)
    local log = store()
    local out = {}
    if not log then return out end
    for index = #log, 1, -1 do
        local entry = log[index]
        if not since or (entry.ts or 0) >= since then
            out[#out + 1] = entry
            if limit and #out >= limit then break end
        end
    end
    return out
end

--- Der juengste Eintrag einer Art, oder nil.
function Activity:Latest(kind)
    for _, entry in ipairs(self:List()) do
        if entry.kind == kind then return entry end
    end
    return nil
end

-- ================================================================== Quellen ---

local LOOT_STATUS = {
    AWARDED = true, TRANSFER_PENDING = true, RECEIVED = true, EQUIPPED = true,
}

function Activity:OnEnable()
    local Callbacks = GA.Core.Callbacks

    -- Armory/Guild.lua misst den Aufstieg beim Rosterlauf.
    Callbacks:On("GUILD_LEVELUP", function(aufstieg)
        if not aufstieg or not aufstieg.name or not aufstieg.level then return end
        Activity:Add({
            kind = Activity.LEVELUP, name = Util.ShortName(aufstieg.name),
            class = aufstieg.class, level = aufstieg.level, von = aufstieg.von,
            detail = aufstieg.level,
        })
    end, "Activity")

    -- Armory/GuildHistory.lua schreibt Beitritt, Austritt, Rangwechsel.
    Callbacks:On("GUILD_HISTORY", function(kind)
        local GuildHistory = GA.Modules.GuildHistory
        local entry = GuildHistory and GuildHistory:List()[1]
        if not entry then return end
        Activity:Add({
            kind = Activity.ROSTER, sub = entry.kind, name = entry.name,
            class = entry.class, rank = entry.rank, detail = entry.kind .. ":" .. tostring(entry.rank or ""),
            ts = entry.ts,
        })
    end, "Activity")

    -- LootHistory/Awards.lua meldet jeden Statuswechsel. Ein Eintrag je
    -- Vergabe, der mit dem Stand mitgeht — der Schluessel ist die Vergabe.
    Callbacks:On("AWARD_CHANGED", function(awardId, _, newStatus)
        if not LOOT_STATUS[newStatus] then return end
        local award = GA.Modules.Awards and GA.Modules.Awards:Get(awardId)
        if not award or not award.recipientName then return end
        Activity:Add({
            kind = Activity.LOOT, name = Util.ShortName(award.recipientName),
            itemID = award.itemID, itemName = award.itemName, quality = award.quality,
            itemLink = award.itemLink, status = newStatus, confirmation = award.confirmation,
            awardId = awardId, key = "LOOT:" .. tostring(awardId),
        })
    end, "Activity")

    -- Achievements/Achievements.lua: eigene und Gildenerste.
    Callbacks:On("ACHIEVEMENT_UNLOCKED", function(id, playerId)
        local Achievements = GA.Modules.Achievements
        local entry = Achievements and Achievements:Entry(id)
        if not entry then return end

        local account = GA.Core.Database.account
        local erster = entry.category == "FIRSTS"
        local who
        if erster then
            local first = account.guildFirsts and account.guildFirsts[id]
            who = first and first.name
        else
            local unlock = account.achievements and account.achievements[playerId]
                and account.achievements[playerId][id]
            who = unlock and unlock.character
        end
        if not who then return end

        Activity:Add({
            kind = Activity.ACHIEVEMENT, name = Util.ShortName(who),
            achievement = entry.name, achievementId = id, first = erster or nil,
            points = entry.points, detail = id,
        })
    end, "Activity")

    -- Camp/Camp.lua: ein Lagerfeuer in der eigenen Zone.
    Callbacks:On("CAMP_PLACED", function(feuer)
        if not feuer or not feuer.name then return end
        Activity:Add({
            kind = Activity.CAMP, name = feuer.name, zone = feuer.zone,
            mapID = feuer.mapID, x = feuer.x, y = feuer.y, detail = feuer.zone,
            ts = feuer.ts,
        })
    end, "Activity")

    self:Prune()
end
