--[[----------------------------------------------------------------------------
    Armory/Guild — Gildenroster erfassen.

    Kein UI. Liest GetGuildRosterInfo nach GUILD_ROSTER_UPDATE aus, pflegt
    GA.Core.Database.account.guild.members und feuert GUILD_UPDATED.

    Gemessen 19.09.2026: GetNumGuildMembers und GetGuildRosterInfo existieren,
    die globale GuildRoster() fehlt — die Aktualisierung geht nur ueber
    C_GuildInfo.GuildRoster (Compat.RequestGuildRoster kennt beide Wege).
    GUILD_ROSTER_UPDATE feuerte beim Login 2x, die Antwort kommt asynchron.

    Was hier NICHT passiert: Kein automatisches Anlegen von Charakterdatensaetzen
    fuer alle Gildenmitglieder. Ein Roster-Eintrag ist kein Ausruestungsstand,
    und die Armory darf nicht so aussehen, als kenne sie 60 Charaktere, von
    denen sie nur Name und Rang hat.
------------------------------------------------------------------------------]]

local _, GA = ...

local Guild = {}
GA.Modules.Guild = Guild

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

local pending = false

-- ================================================================== Aufbau ----

function Guild:Rebuild()
    local db = GA.Core.Database.account.guild
    local total, online = Compat.GetNumGuildMembers()

    if total == 0 then
        Util.Wipe(db.members)
        db.updatedTs = Util.Now()
        GA.Core.Callbacks:Fire("GUILD_UPDATED")
        return
    end

    local seen, read = {}, 0
    for index = 1, total do
        local member = Compat.GetGuildMember(index)
        if member and member.name then
            read = read + 1
            -- GUID, wenn der Client sie liefert; sonst der normalisierte Name.
            local key = member.guid or Util.NormalizeName(member.name)
            seen[key] = true

            local entry = db.members[key] or {}
            entry.guid = member.guid
            entry.name = Util.ShortName(member.name)
            entry.fullName = Util.NormalizeName(member.name)
            entry.rankName = member.rankName
            entry.rankIndex = member.rankIndex
            entry.level = member.level
            entry.class = member.class
            entry.className = member.className
            entry.zone = member.zone
            entry.online = member.online
            entry.publicNote = member.publicNote
            if member.online then entry.lastOnlineTs = Util.Now() end
            db.members[key] = entry

            -- Bekannte Charaktere (mit Ausruestungsstand) bekommen den Rang
            -- mitgepflegt — aber nur die, die es schon gibt.
            if member.guid then
                local character = GA.Core.Database.account.characters[member.guid]
                if character then
                    character.guildRank = member.rankName
                    character.guildRankIndex = member.rankIndex
                end
            end
        end
    end

    -- UNVOLLSTAENDIG GELESEN IST NICHT DASSELBE WIE AUSGETRETEN.
    --
    -- Der Client nennt zwei Zahlen: wie viele Mitglieder die Gilde hat, und —
    -- ueber GetGuildRosterInfo — wie viele er gerade herausgeben kann. Kurz
    -- nach dem Einloggen klaffen die auseinander: Die Antwort auf die
    -- Roster-Anfrage kommt asynchron, und wer vorher liest, bekommt eine
    -- Handvoll Eintraege statt sechzig.
    --
    -- Wer in diesem Moment aufraeumt, loescht die halbe Gilde und traegt sie
    -- beim naechsten Durchlauf als Neuzugaenge wieder ein. Die Differenz der
    -- beiden Zahlen ist gemessen, nicht geraten — deshalb wird hier nicht
    -- geloescht, sondern vermerkt.
    db.partial = (read < total) or nil

    if not db.partial then
        -- Wer nicht mehr im Roster ist, fliegt raus — Austritte sollen nicht als
        -- Karteileichen weiterleben.
        for key in pairs(db.members) do
            if not seen[key] then db.members[key] = nil end
        end
    else
        Debug:Print("guild", "Roster unvollstaendig: %d von %d gelesen", read, total)
    end

    local guildName = Compat.GetOwnGuildInfo()
    db.name = guildName or db.name
    db.updatedTs = Util.Now()
    db.total = total
    db.online = online

    Debug:Print("guild", "Roster: %d Mitglieder, %d online", total, online)
    GA.Core.Callbacks:Fire("GUILD_UPDATED", db.partial and true or false)
end

function Guild:RequestRebuild(delay)
    if pending then return end
    pending = true
    Compat.After(delay or 0.5, function()
        pending = false
        Guild:Rebuild()
    end)
end

-- ================================================================== Abfrage ---

--- Mitglieder als Liste, online zuerst, dann nach Rang und Name.
function Guild:List(onlineOnly)
    local list = {}
    for _, member in pairs(GA.Core.Database.account.guild.members) do
        if not onlineOnly or member.online then
            list[#list + 1] = member
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if (a.rankIndex or 99) ~= (b.rankIndex or 99) then
            return (a.rankIndex or 99) < (b.rankIndex or 99)
        end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- ================================================================== Start ------

function Guild:OnEnable()
    local Events = GA.Core.Events

    Events:Register("GUILD_ROSTER_UPDATE", function()
        Guild:RequestRebuild(0.5)
    end, "Guild")
    Events:Register("PLAYER_GUILD_UPDATE", function()
        Compat.RequestGuildRoster()
    end, "Guild")

    -- Beim Start anfordern; die Antwort kommt ueber GUILD_ROSTER_UPDATE.
    if Compat.IsInGuild() then
        Compat.RequestGuildRoster()
        -- Falls das Roster schon geladen ist, sofort lesen.
        self:RequestRebuild(2)
    end
end
