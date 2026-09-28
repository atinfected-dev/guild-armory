--[[----------------------------------------------------------------------------
    Communication/GuildChat — der Gildenchat, wie er beim Client ankommt.

    Kein UI. Hoert CHAT_MSG_GUILD und CHAT_MSG_OFFICER mit und bewahrt die
    letzten hundert Zeilen auf — auch ueber einen Reload, in der Datei. Was
    VOR dem Login gesagt wurde, gibt es nicht: Das Spiel liefert keine
    Historie, und dieses Modul erfindet keine.

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

GuildChat.LIMIT = 100

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
end
