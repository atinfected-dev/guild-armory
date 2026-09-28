--[[----------------------------------------------------------------------------
    Communication/GuildChat — der Gildenchat, wie er beim Client ankommt.

    Kein UI. Hoert CHAT_MSG_GUILD und CHAT_MSG_OFFICER mit und bewahrt die
    letzten fuenfhundert Zeilen auf — auch ueber einen Reload, in der Datei.

    Was VOR dem Login gesagt wurde, hat auf der neueren Linie das Spiel
    selbst: Die Gilde ist dort ein "Club" mit Chatverlauf, und Blizzards
    Gildenfenster zeigt ihn. Compat.GetClubChatHistory liest dieselben
    Zeilen; PullHistory fuehrt sie hier mit den mitgehoerten zusammen —
    eine Nachricht, die beide Wege liefern, steht einmal da. Wo es den
    Verlauf nicht gibt (aeltere Linien), bleibt es beim Mitgehoerten, und
    das Modul erfindet nichts.

    Senden geht ueber Compat.SendChatMessage in den Gildenkanal, der fuer
    Addons offen ist. Die eigene Zeile kommt danach wie jede andere ueber
    das Ereignis zurueck — sie wird nicht vorab eingetragen, sonst stuende
    sie zweimal da.
------------------------------------------------------------------------------]]

local _, GA = ...

local GuildChat = {}
GA.Modules.GuildChat = GuildChat

local Util = GA.Core.Util
local Compat = GA.Core.Compat

GuildChat.LIMIT = 500
GuildChat.PULL_EVERY = 5
GuildChat.REQUEST = 300

local function store()
    local account = GA.Core.Database and GA.Core.Database.account
    if not account then return nil end
    account.guildChat = account.guildChat or { lines = {} }
    account.guildChat.lines = account.guildChat.lines or {}
    return account.guildChat.lines
end

local function klasseVon(name, guid)
    local db = GA.Core.Database
    if guid and db.account.characters[guid] then return db.account.characters[guid].class end
    local members = db.account.guild and db.account.guild.members
    local kurz = string.lower(Util.ShortName(name or ""))
    for _, member in pairs(members or {}) do
        if member.name and string.lower(Util.ShortName(member.name)) == kurz then return member.class end
    end
    return nil
end

--- Eine Zeile aus dem Chat.
--- @param channel string "GUILD" | "OFFICER"
function GuildChat:OnMessage(channel, text, sender, guid)
    local lines = store()
    if not lines or type(text) ~= "string" or text == "" then return nil end
    local line = {
        channel = channel, text = text,
        who = Util.ShortName(sender or "?"), class = klasseVon(sender, guid),
        ts = Util.Now(),
    }
    lines[#lines + 1] = line
    while #lines > self.LIMIT do table.remove(lines, 1) end
    GA.Core.Callbacks:Fire("GUILD_CHAT", line)
    return line
end

--- Fuehrt Zeilen aus dem Verlauf des Spiels mit den mitgehoerten zusammen.
--- Doppelt ist, was dieselbe Kennung traegt — oder denselben Absender und
--- Text binnen zwei Minuten (die mitgehoerte Zeile hat keine Kennung, und
--- ihr Stempel ist der Empfang, nicht das Senden).
--- @return number wie viele Zeilen neu dazukamen
GuildChat.SAME_WINDOW = 120

local function sameLine(line, who, text, ts)
    return string.lower(line.who or "") == string.lower(who) and line.text == text
        and math.abs((line.ts or 0) - (ts or 0)) <= GuildChat.SAME_WINDOW
end

--- Raeumt auf, was ein frueherer, engerer Vergleich doppelt liegen liess:
--- Eine mitgehoerte Zeile ohne Kennung, die eine Zeile aus dem Verlauf
--- spiegelt, geht — der Verlauf ist die Quelle des Spiels.
local function dropShadowed(lines)
    local removed = 0
    for index = #lines, 1, -1 do
        local line = lines[index]
        if not line.id then
            for _, other in ipairs(lines) do
                if other ~= line and other.id and other.channel == line.channel
                    and sameLine(other, line.who or "", line.text, line.ts) then
                    table.remove(lines, index)
                    removed = removed + 1
                    break
                end
            end
        end
    end
    return removed
end

function GuildChat:MergeHistory(channel, entries)
    local lines = store()
    if not lines or type(entries) ~= "table" then return 0 end
    local added = 0
    for _, entry in ipairs(entries) do
        if type(entry.text) == "string" and entry.text ~= "" then
            local who = Util.ShortName(entry.who or "?")
            local doppelt = false
            for _, line in ipairs(lines) do
                if line.channel == channel then
                    if entry.id and line.id == entry.id then doppelt = true break end
                    if not line.id and sameLine(line, who, entry.text, entry.ts) then
                        line.id = entry.id
                        line.ts = entry.ts or line.ts
                        doppelt = true
                        break
                    end
                end
            end
            if not doppelt then
                lines[#lines + 1] = {
                    channel = channel, text = entry.text, who = who,
                    class = entry.class or klasseVon(entry.who), ts = entry.ts or Util.Now(),
                    id = entry.id, history = true,
                }
                added = added + 1
            end
        end
    end
    local removed = dropShadowed(lines)
    if added > 0 or removed > 0 then
        for index, line in ipairs(lines) do line.order = index end
        table.sort(lines, function(a, b)
            if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) < (b.ts or 0) end
            return a.order < b.order
        end)
        for _, line in ipairs(lines) do line.order = nil end
        while #lines > self.LIMIT do table.remove(lines, 1) end
        GA.Core.Callbacks:Fire("GUILD_CHAT_HISTORY", added)
    end
    return added
end

--- Holt den Verlauf des Spiels fuer beide Kanaele — nicht oefter als alle
--- paar Sekunden, denn jeder Aufruf liest alles neu.
--- @return number neu dazugekommene Zeilen
function GuildChat:PullHistory(force)
    if type(Compat.GetClubChatHistory) ~= "function" then return 0 end
    local now = Util.Now()
    if not force and self.lastPull and now - self.lastPull < self.PULL_EVERY then return 0 end
    self.lastPull = now
    local added = 0
    for _, channel in ipairs({ "GUILD", "OFFICER" }) do
        local entries, weg = Compat.GetClubChatHistory(channel)
        self.source = self.source or {}
        self.source[channel] = weg
        if entries then added = added + self:MergeHistory(channel, entries) end
    end
    return added
end

--- Ob der Verlauf des Spiels hier ankommt — fuer die Anzeige.
function GuildChat:HasHistory()
    return self.source ~= nil and self.source.GUILD == "C_Club"
end

--- Die Zeilen eines Kanals, aelteste zuerst.
function GuildChat:List(channel)
    local out = {}
    for _, line in ipairs(store() or {}) do
        if not channel or line.channel == channel then out[#out + 1] = line end
    end
    return out
end

--- Schreibt in den Kanal. Die Zeile kommt ueber das Ereignis zurueck.
function GuildChat:Send(text, channel)
    text = text and string.gsub(text, "^%s+", "") or ""
    text = string.gsub(text, "%s+$", "")
    if text == "" then return false, "empty" end
    if not Compat.IsInGuild() then return false, "noguild" end
    local ok = Compat.SendChatMessage(text, channel or "GUILD")
    return ok and true or false, ok and nil or "send"
end

function GuildChat:OnEnable()
    local Events = GA.Core.Events
    -- CHAT_MSG_*: text, sender, language, channelString, target, flags,
    -- zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid
    Events:Register("CHAT_MSG_GUILD", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
        GuildChat:OnMessage("GUILD", text, sender, guid)
    end, "GuildChat")
    Events:Register("CHAT_MSG_OFFICER", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
        GuildChat:OnMessage("OFFICER", text, sender, guid)
    end, "GuildChat")

    -- Der Verlauf des Spiels: beim Betreten der Welt um aeltere Zeilen
    -- bitten, und lesen, wann immer das Spiel welche liefert.
    Events:Register("PLAYER_ENTERING_WORLD", function()
        Compat.After(3, function()
            if type(Compat.RequestClubChatHistory) == "function" then
                Compat.RequestClubChatHistory("GUILD", GuildChat.REQUEST)
                Compat.RequestClubChatHistory("OFFICER", GuildChat.REQUEST)
            end
            GuildChat:PullHistory(true)
        end)
    end, "GuildChat")
    for _, event in ipairs({ "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAMS_LOADED", "CLUB_MESSAGE_ADDED" }) do
        Events:Register(event, function() Compat.After(0.5, function() GuildChat:PullHistory() end) end, "GuildChat")
    end
end
