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

--- Wer bedient "/discord"? Sucht die globalen SLASH_<NAME>n.
--- @return string|nil schluessel, function|nil handler
function Discord:SlashHandler(command)
    command = string.lower(command or "/discord")
    local list = _G.SlashCmdList
    if type(list) ~= "table" then return nil end
    for key in pairs(list) do
        for i = 1, 9 do
            local alias = _G["SLASH_" .. key .. i]
            if alias == nil then break end
            if type(alias) == "string" and string.lower(alias) == command then
                return key, list[key]
            end
        end
    end
    return nil
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
    pcall(self.listener.RegisterAllEvents, self.listener)
    return seconds
end

--- Schickt "ga-test <Uhrzeit>" ueber den Befehl "/discord", so wie ein
--- Spieler ihn tippt. Was dabei passiert, steht im Ergebnis.
--- @return boolean ok, string bericht
function Discord:SendTest()
    local key, handler = self:SlashHandler("/discord")
    if not handler then return false, "Kein Handler fuer /discord gefunden." end
    local text = "ga-test " .. date("%H:%M:%S")
    local ok, err = pcall(handler, text, _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)
    local entry = date("%H:%M:%S") .. " SEND via SlashCmdList." .. tostring(key) .. ": " .. (ok and "kein Fehler" or ("Fehler: " .. tostring(err)))
    local list = log()
    list[#list + 1] = entry
    return ok, entry
end
