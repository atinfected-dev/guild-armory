--[[----------------------------------------------------------------------------
    Communication/GuildChat — der Gildenchat, wie er beim Client ankommt.

    Kein UI. Hoert CHAT_MSG_GUILD und CHAT_MSG_OFFICER mit und bewahrt die
    letzten fuenfhundert Zeilen auf — auch ueber einen Reload, in der Datei.
    Das ist die DAUERHAFTE Quelle: Was das Ereignis liefert, ist Text.

    Auf der neueren Linie hat das Spiel den Chat selbst: Die Gilde ist
    dort ein "Club" mit Verlauf, und Blizzards Gildenfenster zeigt ihn —
    auch, was vor dem Login gesagt wurde. GEMESSEN 28.09.2026 (/ga clubchat,
    1919 Nachrichten): Der Inhalt dort ist KEIN Text, sondern ein Schluessel
    des Spiels, "|Kw14208|k". Den echten Text setzt der Client erst beim
    Anzeigen ein, und der Schluessel gilt nur fuer die laufende Sitzung —
    nach dem naechsten Login zeigt er "Unknown". Daraus folgt alles:

      * Der Verlauf wird NIE gespeichert. Er lebt in dieser Sitzung.
      * Der Verlauf zeigt nur, was VOR dem Start dieser Sitzung gesagt
        wurde. Alles danach hoert das Modul selbst, als Text.
      * Zwei Zeilen lassen sich nicht am Text vergleichen (Schluessel
        gegen Text). Wo sich Verlauf und Gespeichertes ueberlappen —
        die vorige Sitzung —, gilt: derselbe Absender binnen zehn
        Sekunden ist dieselbe Nachricht, und die gespeicherte gewinnt,
        denn sie ist Text und bleibt.

    Wo es den Verlauf nicht gibt (aeltere Linien), bleibt es beim
    Mitgehoerten, und das Modul erfindet nichts.

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

GuildChat.LIMIT = 500          -- gespeicherte Zeilen
GuildChat.PULL_EVERY = 5       -- Sekunden zwischen zwei Lesungen des Verlaufs
GuildChat.RELOAD_EVERY = 20    -- Sekunden, nach denen ein geladener Verlauf neu gelesen wird
GuildChat.REQUEST = 300        -- Zeilen je Anfrage an das Spiel
GuildChat.SAME_WINDOW = 10     -- Sekunden: derselbe Absender = dieselbe Nachricht
GuildChat.EVENT_WINDOW = 5     -- Sekunden: dasselbe Ereignis zweimal
-- Die Kanaele. DISCORD (seit 0.1.33) ist die mit Discord verbundene
-- Unterhaltung der Gilde: Ihr Text kommt nur als Schluessel des Spiels
-- (|K…|k, gemessen 03.10.2026), den der Client beim ANZEIGEN aufloest —
-- lesbar fuer Menschen, nicht fuer das Addon, und nur in dieser Sitzung.
-- Darum lebt Discord ganz in der Sitzung und kommt nie in die Datei.
GuildChat.CHANNELS = { "GUILD", "OFFICER", "DISCORD" }
GuildChat.SEND_TYPE = { GUILD = "GUILD", OFFICER = "OFFICER", DISCORD = "GUILD_DISCORD" }

-- Der Verlauf dieser Sitzung: nie in der Datei.
GuildChat.session = {}

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

local function sameWho(a, b)
    return string.lower(a or "") == string.lower(b or "")
end

--- Ein Schluessel des Spiels statt Text: "|K...|k". Aus einer frueheren
--- Sitzung gespeichert, zeigt er nur noch "Unknown".
local function isKey(text)
    return type(text) == "string" and text:find("^|K") ~= nil
end

-- ============================================================ Mitgehoert ---

--- Eine Zeile aus dem Chat — Text, dauerhaft.
--- @param channel string "GUILD" | "OFFICER"
function GuildChat:OnMessage(channel, text, sender, guid)
    -- Ein geheimer Wert (Instanz, Kampf) laesst sich weder vergleichen noch
    -- speichern; er steht ohnehin im Chatfenster des Spiels.
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and (isSecret(text) or isSecret(sender)) then return nil end
    if type(text) ~= "string" or text == "" then return nil end
    if channel == "DISCORD" or isKey(text) then
        return self:Remember({ channel = channel, text = text, who = Util.ShortName(sender or "?"),
            class = klasseVon(sender, guid), ts = Util.Now(), remote = channel == "DISCORD" and (guid == nil or guid == "") or nil })
    end
    return self:Store({
        channel = channel, text = text,
        who = Util.ShortName(sender or "?"), class = klasseVon(sender, guid),
        ts = Util.Now(),
    })
end

--- Traegt eine Zeile ein und haelt das Limit. NICHT ZWEIMAL DASSELBE
--- EREIGNIS: Liegt dieselbe Zeile (Kanal, Absender, Text) binnen weniger
--- Sekunden schon da, ist das ein doppelt gemeldetes Ereignis, nicht
--- dieselbe Aussage noch einmal.
function GuildChat:Store(line)
    local lines = store()
    if not lines then return nil end
    for index = #lines, math.max(1, #lines - 20), -1 do
        local other = lines[index]
        if other.channel == line.channel and sameWho(other.who, line.who) and other.text == line.text
            and math.abs((other.ts or 0) - (line.ts or 0)) <= self.EVENT_WINDOW then
            return other
        end
    end
    lines[#lines + 1] = line
    while #lines > self.LIMIT do table.remove(lines, 1) end
    GA.Core.Callbacks:Fire("GUILD_CHAT", line)
    return line
end

--- Eine Zeile nur fuer diese Sitzung (Discord: ein Schluessel, kein Text).
--- Dasselbe Ereignis zweimal binnen Sekunden bleibt eine Zeile.
function GuildChat:Remember(line)
    for index = #self.session, math.max(1, #self.session - 20), -1 do
        local other = self.session[index]
        if other.channel == line.channel and sameWho(other.who, line.who) and other.text == line.text
            and math.abs((other.ts or 0) - (line.ts or 0)) <= self.EVENT_WINDOW then
            return other
        end
    end
    self.session[#self.session + 1] = line
    while #self.session > self.LIMIT do
        local gone = table.remove(self.session, 1)
        if gone and gone.id and self.sessionIds then self.sessionIds[gone.id] = nil end
    end
    GA.Core.Callbacks:Fire("GUILD_CHAT", line)
    return line
end

-- ============================================================ Verlauf ------

--- Der Beginn dieser Sitzung: Ab hier hoert das Modul selbst. Was der
--- Verlauf danach traegt, ist schon als Text da.
function GuildChat:SessionStart()
    if not self.sessionStart then self.sessionStart = Util.Now() end
    return self.sessionStart
end

--- Bittet das Spiel um Inhalte und aeltere Zeilen — hoechstens alle halbe
--- Minute, denn die Antwort kommt als Ereignis und braucht ihre Zeit.
function GuildChat:RequestHistory(force)
    if type(Compat.RequestClubChatHistory) ~= "function" then return false end
    local now = Util.Now()
    if not force and self.lastRequest and now - self.lastRequest < 30 then return false end
    self.lastRequest = now
    for _, channel in ipairs(self.CHANNELS) do pcall(Compat.RequestClubChatHistory, channel, self.REQUEST) end
    -- Die Antwort kommt spaeter, und nicht immer mit einem Ereignis, das
    -- dieser Client kennt (28.09.2026: voller Speicher, kein Zug). Also
    -- zweimal nachlesen, nach zwei und nach sechs Sekunden.
    if type(Compat.After) == "function" then
        Compat.After(2, function() GuildChat:PullHistory("timer") end)
        Compat.After(6, function() GuildChat:PullHistory("timer") end)
        -- Und noch einmal spaeter: Die Schluessel der ersten Ladung koennen
        -- schon tot sein, wenn das Spiel den Kanal danach neu fokussiert
        -- (gesehen 29.09.2026: erst nach der Minute lesbar).
        Compat.After(15, function() GuildChat:PullHistory("event") end)
    end
    return true
end

--- Liest den Verlauf des Spiels in die Sitzung — nur, was vor ihrem
--- Beginn gesagt wurde, und nur, was nicht schon als gespeicherter Text
--- daliegt (derselbe Absender binnen SAME_WINDOW).
--- @return number neu dazugekommene Zeilen
--- @param reason string|nil  nil = Anzeige, "timer" = nach der Anfrage,
---   "event" = das Spiel meldet Neues. Ist der Verlauf einmal geladen,
---   liest nur noch "event" — die Anzeige und die Timer lesen sonst bei
---   jedem Oeffnen 1924 Nachrichten neu (gemessen 28.09.2026: Ruckler).
function GuildChat:PullHistory(reason)
    if type(Compat.GetClubChatHistory) ~= "function" then return 0 end
    if reason == true then reason = "timer" end
    local now = Util.Now()
    -- Nach dem ersten vollen Zug liest die Anzeige nur noch jede Minute
    -- nach — nicht nie mehr. GESEHEN 29.09.2026: "Unknown" fuer alles von
    -- gestern, obwohl der Verlauf morgens noch stand. Die Schluessel des
    -- Spiels (|Kw…|k) sind nicht stabil: Blizzards Fenster oder ein neuer
    -- Fokus vergibt sie neu, und wer die alten haelt, zeigt Platzhalter.
    -- Ein Zug je Minute ist billig (die neuesten 500, vom Ende her).
    if self.loaded and reason ~= "event" and self.lastPull and now - self.lastPull < self.RELOAD_EVERY then return 0 end
    if not reason and self.lastPull and now - self.lastPull < self.PULL_EVERY then return 0 end
    self.lastPull = now

    -- Altlasten: Schluessel, die eine fruehere Fassung speicherte, zeigen
    -- nur noch "Unknown". Sie gehen, samt allem, was je aus dem Verlauf
    -- in die Datei kam.
    local lines = store() or {}
    local dropped = 0
    for index = #lines, 1, -1 do
        if lines[index].id or lines[index].history or isKey(lines[index].text) then
            table.remove(lines, index)
            dropped = dropped + 1
        end
    end

    -- Nachschlagen statt suchen: Kennungen der Sitzung (mit ihrer Zeile,
    -- damit ein neuer Schluessel die alte Zeile erneuert), und die
    -- gespeicherten Zeilen je Kanal und Absender.
    self.sessionIds = self.sessionIds or {}
    local byId = {}
    for _, line in ipairs(self.session) do if line.id then byId[line.id] = line end end
    local stored = {}
    for _, line in ipairs(lines) do
        local key = tostring(line.channel) .. "/" .. string.lower(line.who or "")
        stored[key] = stored[key] or {}
        table.insert(stored[key], line.ts or 0)
    end

    local start = self:SessionStart()
    local added = 0
    self.source = self.source or {}
    for _, channel in ipairs(self.CHANNELS) do
        local entries, weg = Compat.GetClubChatHistory(channel, self.LIMIT)
        self.source[channel] = weg
        if entries and #entries > 0 then self.loaded = true end
        local renewed = 0
        for _, entry in ipairs(entries or {}) do
            local known = byId[entry.id]
            if known and type(entry.text) == "string" and entry.text ~= "" and known.text ~= entry.text then
                -- Dieselbe Nachricht, neuer Schluessel: die Zeile folgt dem Spiel.
                known.text = entry.text
                renewed = renewed + 1
            end
            if entry.ts and entry.ts < start and type(entry.text) == "string" and entry.text ~= ""
                and not self.sessionIds[entry.id] then
                local who = Util.ShortName(entry.who or (channel == "DISCORD" and "Discord" or "?"))
                local known = false
                for _, ts in ipairs(stored[channel .. "/" .. string.lower(who)] or {}) do
                    if math.abs(ts - entry.ts) <= self.SAME_WINDOW then known = true break end
                end
                if not known then
                    self.sessionIds[entry.id] = true
                    self.session[#self.session + 1] = {
                        channel = channel, text = entry.text,
                        who = who, class = entry.class or klasseVon(entry.who),
                        ts = entry.ts, id = entry.id, history = true, remote = entry.remote, extra = entry.extra,
                    }
                    added = added + 1
                end
            end
        end
        if renewed > 0 then added = added + renewed end
    end
    -- Die Sitzung haelt hoechstens LIMIT Zeilen: die aeltesten gehen.
    if #self.session > self.LIMIT then
        table.sort(self.session, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
        while #self.session > self.LIMIT do
            local gone = table.remove(self.session, 1)
            if gone and gone.id then self.sessionIds[gone.id] = nil end
        end
    end
    if added > 0 or dropped > 0 then GA.Core.Callbacks:Fire("GUILD_CHAT_HISTORY", added) end
    return added
end

--- Ob der Verlauf des Spiels hier ankommt — fuer die Anzeige.
function GuildChat:HasHistory()
    return self.source ~= nil and self.source.GUILD == "C_Club"
end

-- ============================================================ Lesen --------

--- Die Zeilen eines Kanals, aelteste zuerst: der Verlauf dieser Sitzung
--- (vor ihrem Beginn) und das Gespeicherte, nach Zeit sortiert.
function GuildChat:List(channel)
    local out = {}
    for _, line in ipairs(self.session) do
        if not channel or line.channel == channel then out[#out + 1] = line end
    end
    for _, line in ipairs(store() or {}) do
        if not channel or line.channel == channel then out[#out + 1] = line end
    end
    for index, line in ipairs(out) do line.order = index end
    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) < (b.ts or 0) end
        return a.order < b.order
    end)
    for _, line in ipairs(out) do line.order = nil end
    return out
end

--- Leert den gespeicherten Chat und den Verlauf der Sitzung — fuer
--- /ga chatclear. Was danach kommt, wird neu gesammelt.
--- @return number wie viele Zeilen weg sind
function GuildChat:Clear()
    local lines = store()
    local count = #self.session
    self.session = {}
    self.sessionIds = {}
    self.loaded = nil
    if lines then
        count = count + #lines
        for index = #lines, 1, -1 do lines[index] = nil end
    end
    self.lastPull = nil
    GA.Core.Callbacks:Fire("GUILD_CHAT_HISTORY", 0)
    return count
end

--- Die letzten Zeilen ROH, ohne jeden Vergleich — fuer /ga chatdupes.
--- Text in %q (Steuerzeichen sichtbar), Laenge, Absender, Stempel,
--- Kennung, Kanal, Herkunft.
function GuildChat:Raw(count)
    local lines = self:List()
    local out = {}
    for index = math.max(1, #lines - (count or 12) + 1), #lines do
        local line = lines[index]
        out[#out + 1] = string.format("#%d %s ts=%s who=%q(%d) text=%q(%d) id=%s hist=%s",
            index, tostring(line.channel), tostring(line.ts),
            tostring(line.who), #tostring(line.who or ""),
            tostring(line.text), #tostring(line.text or ""),
            tostring(line.id), tostring(line.history))
    end
    return out
end

--- Paare, die gleich aussehen — derselbe Absender, derselbe Kanal, binnen
--- zehn Minuten, gleicher Text ODER eine der beiden ein Schluessel.
function GuildChat:Duplicates()
    local lines = self:List()
    local out = {}
    for i = 1, #lines do
        for j = i + 1, #lines do
            local a, b = lines[i], lines[j]
            if a.channel == b.channel and sameWho(a.who, b.who)
                and math.abs((a.ts or 0) - (b.ts or 0)) <= 600
                and (a.text == b.text or isKey(a.text) or isKey(b.text)) then
                local function describe(line)
                    return string.format("text=%q ts=%s id=%s hist=%s",
                        tostring(line.text), tostring(line.ts), tostring(line.id), tostring(line.history))
                end
                out[#out + 1] = string.format("%s | A %s | B %s", tostring(a.who), describe(a), describe(b))
            end
        end
    end
    return out
end

-- ============================================================ Gelesen ------

--- Den Kanal im Spiel als gelesen markieren (Hinweis am Gilden-Knopf weg).
--- Hoechstens einmal je zwei Sekunden und Kanal; das Ergebnis der ersten
--- Antwort wird gemerkt, damit ein blockierter Aufruf nicht dauernd laeuft.
function GuildChat:MarkRead(channel)
    if type(Compat.MarkClubStreamRead) ~= "function" then return nil end
    self.readAt = self.readAt or {}
    local now = Util.Now()
    if self.readAt[channel] and now - self.readAt[channel] < 2 then return nil end
    if self.readBlocked then return false end
    self.readAt[channel] = now
    local ok = Compat.MarkClubStreamRead(channel)
    if ok == false then
        self.readBlocked = true
        if GA.Core.Debug and GA.Core.Debug.Info then GA.Core.Debug:Info("Guild chat: the game refused to mark messages as read.") end
    end
    return ok
end

-- ============================================================ Senden -------

--- Schreibt in den Kanal. Die Zeile kommt ueber das Ereignis zurueck.
function GuildChat:Send(text, channel)
    text = text and string.gsub(text, "^%s+", "") or ""
    text = string.gsub(text, "%s+$", "")
    if text == "" then return false, "empty" end
    if not Compat.IsInGuild() then return false, "noguild" end
    local ok, why = Compat.SendChatMessage(text, self.SEND_TYPE[channel or "GUILD"] or "GUILD")
    if not ok and (why == "locked" or why == "blocked") then return false, "locked" end
    return ok and true or false, ok and nil or "send"
end

-- ============================================================ Start --------

function GuildChat:OnEnable()
    local Events = GA.Core.Events
    self:SessionStart()
    -- CHAT_MSG_*: text, sender, language, channelString, target, flags,
    -- zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid
    Events:Register("CHAT_MSG_GUILD", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
        GuildChat:OnMessage("GUILD", text, sender, guid)
    end, "GuildChat")
    Events:Register("CHAT_MSG_OFFICER", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
        GuildChat:OnMessage("OFFICER", text, sender, guid)
    end, "GuildChat")
    -- Discord: der Text ist ein Schluessel (|K…|k), der Absender lesbar.
    Events:Register("CHAT_MSG_GUILD_DISCORD", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
        GuildChat:OnMessage("DISCORD", text, sender, guid)
        -- Der Discord-Kanal wird im Addon gelesen: der Hinweis am Gilden-Knopf geht sofort weg.
        if type(Compat.After) == "function" then Compat.After(1, function() GuildChat:MarkRead("DISCORD") end)
        else GuildChat:MarkRead("DISCORD") end
    end, "GuildChat")

    -- Der Verlauf des Spiels: beim Betreten der Welt um Zeilen bitten, und
    -- lesen, wann immer das Spiel welche liefert.
    Events:Register("PLAYER_ENTERING_WORLD", function()
        if type(Compat.After) ~= "function" then return end
        Compat.After(3, function()
            GuildChat:RequestHistory(true)
            GuildChat:PullHistory("timer")
        end)
        Compat.After(8, function() GuildChat:MarkRead("DISCORD") end)
    end, "GuildChat")
    -- Sperrt der Client die Lesemarke fuer Addons, meldet pcall trotzdem
    -- Erfolg; das Spiel zeigt nur "Blocked by Blizzard". Dieses Ereignis sagt
    -- es dem Addon — dann wird es nie wieder versucht (keine Fensterflut).
    Events:Register("ADDON_ACTION_BLOCKED", function(_, addon, fn)
        if type(fn) == "string" and fn:find("AdvanceStreamViewMarker") then GuildChat.readBlocked = true end
        -- Blockierte Chatzeilen (11.10.2026): Compat merkt sich die Sperre.
        if Compat.NoteActionBlocked then Compat.NoteActionBlocked(addon) end
    end, "GuildChat")
    -- Mehr Namen als noetig: Was der Client nicht kennt, weist Register
    -- still ab, und welcher Name die Lieferung meldet, ist nicht gemessen.
    for _, event in ipairs({ "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAMS_LOADED", "CLUB_MESSAGE_ADDED",
        "CLUB_MESSAGE_UPDATED", "CLUB_UPDATED", "CLUB_STREAM_SUBSCRIBED" }) do
        Events:Register(event, function()
            if type(Compat.After) == "function" then
                Compat.After(0.5, function() GuildChat:PullHistory("event") end)
            end
        end, "GuildChat")
    end
end
