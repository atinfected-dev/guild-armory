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

                    -- DAS ROSTER IST JUENGER ALS JEDE MESSUNG VON FRUEHER.
                    --
                    -- Wer hier steht, ist in dieser Gilde — auch wenn ein
                    -- Inspizieren vor drei Wochen eine andere ergeben hat.
                    -- Ohne diese Zeile bliebe ein Neuzugang, den man vorher
                    -- einmal angesehen hat, fuer immer aus den Listen
                    -- ausgeblendet (siehe DB:IsForeignCharacter).
                    if db.name and db.name ~= "" then
                        character.guildName = db.name
                    end
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

    self:AdoptFullNames(db)

    local guildName = Compat.GetOwnGuildInfo()
    db.name = guildName or db.name
    db.updatedTs = Util.Now()
    db.total = total
    db.online = online

    Debug:Print("guild", "Roster: %d Mitglieder, %d online", total, online)
    GA.Core.Callbacks:Fire("GUILD_UPDATED", db.partial and true or false)
end

--- Zieht volle Namen aus dem Roster in die Charakterdatensaetze nach.
---
--- GEMELDET 25.09.2026: "Ich werde weiterhin als nur Total angezeigt — in
--- equipment, in characters."
---
--- Namen auf diesem Realm haben zwei Teile ("Horst Hodenhagen"), aber
--- UnitName("player") gibt nur den ersten her — daran ist schon das
--- Veroeffentlichen gescheitert (siehe Util.SameCharacter). Der eigene
--- Datensatz entsteht aus genau dieser Quelle und heisst deshalb "Total",
--- waehrend die Gilde einen "Total Tumult" kennt.
---
--- DAS ROSTER IST DIE BESSERE QUELLE. GetGuildRosterInfo nennt den Namen so,
--- wie der Server ihn fuehrt — dieselbe Schreibweise, die auch im
--- Absenderfeld einer Addon-Nachricht steht.
---
--- EINMAL DURCH JEDE LISTE, nicht Namen gegen Namen. Bei 200 Mitgliedern und
--- ein paar Dutzend Datensaetzen waere der paarweise Vergleich ein paar
--- tausend Zeichenkettenoperationen je Rosteraktualisierung — und die laeuft
--- beim Anmelden mehrfach. Was dabei herauskommt, hat schon einmal 18 MB
--- gekostet.
---
--- BEI ZWEI PASSENDEN WIRD KEINER GENOMMEN. Gibt es "Total Tumult" und
--- "Total Terror", ist "Total" nicht aufloesbar — dann lieber der kurze Name
--- als der falsche lange. Dieselbe Regel wie bei DB:FindCharacterByName.
function Guild:AdoptFullNames(db)
    local kurzform = {}
    for _, member in pairs(db.members) do
        local voll = member.name
        local erstes = voll and string.match(voll, "^(%S+)%s")
        if erstes then
            local key = string.lower(erstes)
            if kurzform[key] == nil then
                kurzform[key] = voll
            elseif kurzform[key] ~= voll then
                kurzform[key] = false  -- mehrdeutig
            end
        end
    end
    if next(kurzform) == nil then return end

    local geaendert = false
    for _, character in pairs(GA.Core.Database.account.characters) do
        local name = character.name
        -- Nur kurze Namen ueberhaupt ansehen: Wer schon zwei Teile hat,
        -- braucht nichts, und die Suche kostet dann auch nichts.
        if name and name ~= "" and not string.find(name, " ", 1, true) then
            local voll = kurzform[string.lower(name)]
            if voll then
                character.name = voll
                geaendert = true
            end
        end
    end

    -- Der Namensindex zeigt sonst weiter auf die alte Schreibweise. Er wird
    -- ohnehin nur nebenbei gepflegt; hier ist der Moment, in dem er falsch
    -- wird, also wird er hier neu gebaut.
    if geaendert then GA.Core.Database:RebuildNameIndex() end
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

--- Ist dieser Name ein Mitglied MEINER Gilde?
---
--- DREI ANTWORTEN, NICHT ZWEI.
---
---   true   steht im Roster
---   false  steht nicht drin, obwohl das Roster vollstaendig gelesen ist
---   nil    weiss nicht — Roster leer oder unvollstaendig
---
--- Die dritte ist der Grund fuer diese Funktion. Kurz nach dem Einloggen ist
--- das Roster noch nicht da; ein blosses "nicht gefunden" waere dann ein
--- falsches Nein, und der Aufrufer wuerde jedes Gildenmitglied abweisen.
--- Was in diesem Fall geschieht, entscheidet der Aufrufer — nicht diese
--- Funktion, die es gar nicht wissen kann.
---
--- Verglichen wird ueber den KURZNAMEN. Der Absender einer Addon-Nachricht
--- kommt als "Name-Realm", das Roster fuehrt ihn ohne — und auf Forever
--- stehen Leerzeichen im Namen, also wird am Bindestrich getrennt.
function Guild:IsMember(name)
    if not name or name == "" then return false end

    local db = GA.Core.Database.account.guild
    local members = db and db.members
    if not members or next(members) == nil then return nil end

    local wanted = string.lower(Util.ShortName(name))
    for _, member in pairs(members) do
        if member.name and string.lower(member.name) == wanted then return true end
    end

    -- NICHT GEFUNDEN HEISST HIER WIRKLICH NEIN — und zwar auch bei einem
    -- unvollstaendig gelesenen Roster.
    --
    -- Der erste Entwurf gab bei db.partial ein "weiss nicht" zurueck. Das
    -- waere falsch gewesen: Ob das Roster vollstaendig ist, haengt daran, ob
    -- der Spieler abgemeldete Mitglieder eingeblendet hat — eine Einstellung
    -- im Gildenfenster, die dieses Addon nicht kennt und nicht anfassen
    -- sollte. Bei ausgeblendeten Offline-Mitgliedern waere partial DAUERHAFT
    -- gesetzt, und jede Pruefung endete fuer immer im "weiss nicht".
    --
    -- Der Filter blendet aber nur ABGEMELDETE aus. Wer gerade eine Nachricht
    -- schickt, ist angemeldet und steht deshalb im Roster — egal wie
    -- gefiltert wird. Wer nicht drinsteht, ist kein Mitglied.
    return false
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
