--[[----------------------------------------------------------------------------
    Communication/Discord — Messwerkzeug fuer die Discord-Anbindung von Forever.

    Stand 03.10.2026: Die Gilde hat Gildenchat und Discord verbunden, und
    "/discord <text>" schreibt in einen Discord-Kanal (Meldung des Nutzers).
    Geplant ist ein Anmelder fuer Dungeon-Laeufe ueber einen Discord-Bot, in
    beide Richtungen. Dafuer muss erst GEMESSEN werden, was der Client hier
    tut — bisher steht dazu im Addon nur Theorie (siehe Announce.lua).

    DREI FRAGEN, DREI BEFEHLE:
      /ga discord api      Welche Funktionen hat C_Discord, und wer bedient
                           "/discord"? Nur Namen lesen, nichts aufrufen.
      /ga discord listen   Zwei Minuten lang jedes Chat-, Club- und Discord-
                           Ereignis mitschreiben. Waehrenddessen in Discord
                           "ga-test" schreiben: Dann steht fest, ueber welches
                           Ereignis und in welcher Form Discord ins Spiel kommt.
      /ga discord send     Den Weg von "/discord" aus dem Addon heraus nehmen,
                           mit dem Text "ga-test <Uhrzeit>". Kommt die Zeile in
                           Discord an, kann das Addon dort schreiben.
      /ga discord show     Zeigt das Mitgeschriebene zum Kopieren.

    WAS HIER NIE AUFGERUFEN WIRD (feste Regel des Projekts):
      C_Discord.Authorize, RefreshAuth, GuildLink, GuildUnlink,
      SetGuildSetting, UpdateDiscordServers, UpdateGuildLobby.
      "api" liest nur die Namen der Funktionen, ruft keine auf.
------------------------------------------------------------------------------]]

local _, GA = ...

local Discord = {}
GA.Modules.Discord = Discord

local Util = GA.Core.Util

Discord.LISTEN_SECONDS = 120
Discord.MAX_LOG = 40

local function log()
    local db = GA.Core.Database.account
    db.measured = db.measured or {}
    db.measured.discordLog = db.measured.discordLog or {}
    return db.measured.discordLog
end

--- Welche Funktionen kennt C_Discord? Nur die Namen.
--- @return table namen
function Discord:ApiNames()
    local api = _G.C_Discord
    local out = {}
    if type(api) ~= "table" then return out end
    for name, value in pairs(api) do
        if type(value) == "function" then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

--- Der Stand der Verbindung, nur ueber Abfragefunktionen ohne Wirkung.
--- Die verbotenen (Authorize, RefreshAuth, GuildLink, GuildUnlink,
--- SetGuildSetting, UpdateDiscordServers, UpdateGuildLobby) fehlen hier mit
--- Absicht.
--- @return string
function Discord:Status()
    local api = _G.C_Discord
    if type(api) ~= "table" then return "C_Discord fehlt" end
    local teile = {}
    for _, name in ipairs({ "IsEnabled", "IsUserOAuthed", "IsGuildChannelLinked", "GetGuildLinkStatus",
                            "GetNumDiscordChannels", "GetNumDiscordServers", "GetDisplayNameType" }) do
        local fn = api[name]
        if type(fn) == "function" then
            local werte = { pcall(fn) }
            local out = {}
            for i = 2, math.min(#werte, 4) do out[#out + 1] = tostring(werte[i]) end
            teile[#teile + 1] = name .. "=" .. (werte[1] and table.concat(out, ",") or "Fehler")
        end
    end
    return table.concat(teile, " | ")
end

--- Wer steckt hinter "/discord"? Ein Chattyp (wie "/g" -> GUILD), kein
--- Slash-Befehl: Gemessen 03.10.2026 — SlashCmdList kennt "/discord" nicht.
--- Gesucht wird in den globalen SLASH_<NAME>n und in Blizzards Chattyp-Tabelle.
--- @return string|nil chattyp, string|nil globalname
function Discord:ChatType(command)
    command = string.lower(command or "/discord")
    local hash = _G.hash_ChatTypeInfoList
    if type(hash) == "table" then
        local typ = hash[string.upper(command)]
        if type(typ) == "string" then return typ, "hash_ChatTypeInfoList" end
    end
    for key, value in pairs(_G) do
        if type(value) == "string" and type(key) == "string" and string.sub(key, 1, 6) == "SLASH_"
            and string.lower(value) == command then
            local typ = string.match(key, "^SLASH_(.-)%d+$")
            return typ, key
        end
    end
    return nil
end

--- Fuer "api": der Chattyp mit seinem Eintrag in ChatTypeInfo.
function Discord:SlashHandler(command)
    local typ, global = self:ChatType(command)
    if not typ then return nil end
    local info = type(_G.ChatTypeInfo) == "table" and _G.ChatTypeInfo[typ]
    return typ .. " (" .. tostring(global) .. (info and ", in ChatTypeInfo" or ", nicht in ChatTypeInfo") .. ")"
end

--- Zwei Minuten lang alles mitschreiben, was nach Chat, Club oder Discord
--- aussieht. Jede Zeile: Ereignis und seine ersten Werte als Text.
function Discord:Listen(seconds)
    seconds = tonumber(seconds) or self.LISTEN_SECONDS
    local entries = log()
    for i = #entries, 1, -1 do entries[i] = nil end

    if not self.listener then
        self.listener = CreateFrame("Frame")
        self.listener:SetScript("OnEvent", function(_, event, ...)
            if not Discord.listenUntil or Util.Now() > Discord.listenUntil then
                Discord.listener:UnregisterAllEvents()
                return
            end
            local upper = string.upper(event)
            if not (string.find(upper, "^CHAT_MSG") or string.find(upper, "CLUB") or string.find(upper, "DISCORD")) then return end
            if string.find(upper, "ADDON") then return end
            local werte = {}
            for i = 1, math.min(select("#", ...), 8) do
                local v = select(i, ...)
                werte[#werte + 1] = string.sub(tostring(v), 1, 80)
            end
            local list = log()
            if #list < Discord.MAX_LOG then
                list[#list + 1] = date("%H:%M:%S") .. " " .. event .. " | " .. table.concat(werte, " | ")
            end
        end)
    end
    self.listenUntil = Util.Now() + seconds
    -- NICHT RegisterAllEvents: Das ist auf diesem Client Blizzards Code
    -- vorbehalten und loeste "Blocked by Blizzard" aus (03.10.2026). Statt
    -- dessen die Ereignisse des Discord-Chattyps aus Blizzards eigener
    -- Tabelle ChatTypeGroup, und ein paar Verwandte zur Sicherheit.
    local events = {}
    local group = type(_G.ChatTypeGroup) == "table" and _G.ChatTypeGroup.GUILD_DISCORD
    for _, event in ipairs(type(group) == "table" and group or {}) do events[#events + 1] = event end
    for _, event in ipairs({ "CHAT_MSG_GUILD_DISCORD", "CHAT_MSG_GUILD", "CHAT_MSG_COMMUNITIES_CHANNEL",
                             "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM", "CLUB_MESSAGE_ADDED" }) do
        events[#events + 1] = event
    end
    local angemeldet = {}
    for _, event in ipairs(events) do
        if not angemeldet[event] and pcall(self.listener.RegisterEvent, self.listener, event) then
            angemeldet[event] = true
        end
    end
    local namen = {}
    for event in pairs(angemeldet) do namen[#namen + 1] = event end
    table.sort(namen)
    local list = log()
    list[#list + 1] = date("%H:%M:%S") .. " LISTEN auf: " .. table.concat(namen, ", ")
        .. " (ChatTypeGroup.GUILD_DISCORD: " .. (type(group) == "table" and table.concat(group, ", ") or "fehlt") .. ")"
    return seconds
end

--- Schickt "ga-test <Uhrzeit>" ueber den Befehl "/discord", so wie ein
--- Spieler ihn tippt. Was dabei passiert, steht im Ergebnis.
--- @return boolean ok, string bericht
function Discord:SendTest()
    -- Der Chattyp hinter "/discord", sonst die Vermutung des Nutzers.
    local typ = self:ChatType("/discord") or "GUILD_DISCORD"
    local text = "ga-test " .. date("%H:%M:%S")
    if not _G.SendChatMessage then return false, "SendChatMessage fehlt" end
    local ok, err = pcall(_G.SendChatMessage, text, typ)
    local entry = date("%H:%M:%S") .. " SEND SendChatMessage(\"" .. text .. "\", \"" .. typ .. "\"): "
        .. (ok and "kein Fehler — kommt die Zeile in Discord an?" or ("Fehler: " .. tostring(err)))
    local list = log()
    list[#list + 1] = entry
    return ok, entry
end
