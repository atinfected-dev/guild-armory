--[[----------------------------------------------------------------------------
    Communication/GuildNotes — EINE Notiz je Mitglied, die alle mit Guild
    Armory sehen.

    Kein UI. Warum es dieses Modul gibt (28.09.2026): Blizzards oeffentliche
    und Offiziersnotiz lassen sich auf diesem Client aus einem Addon nicht
    schreiben — gemessen auf drei Wegen, alle geblockt. Die Gilde will eine
    Notiz, die im Roster steht und ueberall dieselbe ist. Also traegt das
    Addon sie selbst: gespeichert je Client, verteilt ueber den Gildenkanal,
    die JUENGSTE gewinnt.

    Das ist AUSDRUECKLICH GETEILT — anders als Armory/Notes, dessen Zettel
    den Client nie verlassen. Wer hier schreibt, schreibt fuer die Gilde,
    und die Beschriftung im Roster sagt das.

    Rechte: Wer im Spiel die oeffentliche Notiz schreiben duerfte, darf
    auch diese (Compat.CanEditPublicNote). Was der Client nicht misst,
    ist kein Nein — dann darf jeder, und die Notiz nennt, wer schrieb.

    Protokoll (GUILD-Kanal, kurze Nachrichten):
      GNOTE   key, name, ts, text     eine Notiz; text leer = geloescht
      GNOTEQ  since                   "schickt mir, was juenger ist als since"
    Auf GNOTEQ antwortet jeder Client, der Juengeres hat — mit zufaelliger
    Verzoegerung, und ohne, was er inzwischen von anderen schon sah.
------------------------------------------------------------------------------]]

local _, GA = ...

local GuildNotes = {}
GA.Modules.GuildNotes = GuildNotes

local Util = GA.Core.Util
local Compat = GA.Core.Compat

GuildNotes.MAX = 120          -- Zeichen je Notiz: passt mit Kopf in eine Nachricht
GuildNotes.MAX_MOTD = 180     -- die Nachricht des Tages darf laenger sein; ohne Namen im Paket
GuildNotes.MOTD_KEY = "@motd" -- kein Mitglied hat diesen Schluessel
GuildNotes.REPLY_EVERY = 60   -- Sekunden: hoechstens so oft auf GNOTEQ antworten
GuildNotes.SEEN_TTL = 30      -- Sekunden: so lange gilt "das sah ich schon"

local function store()
    local db = GA.Core.Database and GA.Core.Database.account
    if not db then return nil end
    db.guildNotes = db.guildNotes or {}
    return db.guildNotes
end

local function comm() return GA.Core.Comm end

--- Schneidet zu und entfernt, was eine Zeile sprengt: Trennzeichen des
--- Protokolls, Farbcodes, Zeilenumbrueche.
local function clean(text, limit)
    if type(text) ~= "string" then return "" end
    text = string.gsub(text, "|", "")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s*(.-)%s*$", "%1")
    return string.sub(text, 1, limit or GuildNotes.MAX)
end

local function limitFor(key)
    return key == GuildNotes.MOTD_KEY and GuildNotes.MAX_MOTD or GuildNotes.MAX
end

--- Der Schluessel eines Mitglieds: die GUID, wo der Client sie nennt,
--- sonst der Name ohne Realm — auf beiden Seiten gleich gebildet.
function GuildNotes.Key(guid, name)
    if type(guid) == "string" and guid ~= "" then return guid end
    if type(name) == "string" and name ~= "" then return string.lower(Util.ShortName(name)) end
    return nil
end

-- ================================================================== Lesen -----

--- @return string|nil text, table|nil eintrag {text, by, ts}
function GuildNotes:Get(key)
    local entry = key and (store() or {})[key] or nil
    if not entry or not entry.text or entry.text == "" then return nil, entry end
    return entry.text, entry
end

--- Ob dieser Client schreiben darf. nil vom Spiel ist kein Nein.
function GuildNotes:CanEdit()
    return Compat.CanEditPublicNote() ~= false
end

-- ============================================================ Nachricht des Tages

--- DIE NACHRICHT DES TAGES UEBER DAS ADDON (28.09.2026): GuildSetMOTD ist
--- auf diesem Client aus einem Addon geblockt wie die Notizen. Also ist
--- sie ein Sondereintrag derselben Verteilung — Schluessel "@motd", das
--- Recht dazu ist das, das im Spiel fuer die Nachricht des Tages gilt.
function GuildNotes:CanEditMOTD()
    return Compat.CanEditMOTD() ~= false
end

--- @return string|nil text, table|nil eintrag {text, by, ts}
function GuildNotes:GetMOTD()
    return self:Get(self.MOTD_KEY)
end

function GuildNotes:SetMOTD(text)
    if not self:CanEditMOTD() then return false, "noright" end
    return self:Set(nil, nil, text, self.MOTD_KEY)
end

-- ================================================================== Schreiben -

--- Setzt die Notiz und verteilt sie. Leer heisst loeschen — auch das
--- wandert, sonst kaeme die alte Notiz vom naechsten Client zurueck.
--- @return boolean ok, string|nil grund
function GuildNotes:Set(guid, name, text, key)
    key = key or GuildNotes.Key(guid, name)
    local notes = store()
    if not key or not notes then return false, "nokey" end
    if key ~= self.MOTD_KEY and not self:CanEdit() then return false, "noright" end
    text = clean(text, limitFor(key))
    local identity = Compat.GetPlayerIdentity and Compat.GetPlayerIdentity() or nil
    local by = identity and identity.name and Util.ShortName(identity.name) or "?"
    local entry = { text = text, by = by, ts = Util.Now() }
    notes[key] = entry
    GA.Core.Callbacks:Fire("GUILD_NOTES", key)
    if comm() then
        comm():Send("GNOTE", { key, tostring(name or ""), tostring(entry.ts), text }, "GUILD", nil, true)
    end
    return true
end

-- ================================================================== Empfang ---

local seen = {}

local function markSeen(key, ts)
    seen[key .. "@" .. tostring(ts)] = Util.Now()
end

local function wasSeen(key, ts)
    local at = seen[key .. "@" .. tostring(ts)]
    return at ~= nil and Util.Now() - at <= GuildNotes.SEEN_TTL
end

--- Eine Notiz von einem anderen Client: die juengere gewinnt.
function GuildNotes:OnNote(sender, fields)
    if comm() and comm():IsSelf(sender) then return false end
    local key, ts = fields[1], tonumber(fields[3])
    local text = clean(fields[4], limitFor(key))
    if type(key) ~= "string" or key == "" or not ts then return false end
    local notes = store()
    if not notes then return false end
    markSeen(key, ts)
    local alt = notes[key]
    if alt and alt.ts and alt.ts >= ts then return false end
    notes[key] = { text = text, by = Util.ShortName(sender), ts = ts }
    GA.Core.Callbacks:Fire("GUILD_NOTES", key)
    return true
end

--- Jemand fragt nach allem, was juenger ist als sein Stand. Antwort mit
--- Verzoegerung, hoechstens einmal je Minute, und ohne, was inzwischen
--- ein anderer schon schickte.
function GuildNotes:OnRequest(sender, fields)
    if comm() and comm():IsSelf(sender) then return 0 end
    local since = tonumber(fields and fields[1]) or 0
    local now = Util.Now()
    if self.lastReply and now - self.lastReply < self.REPLY_EVERY then return 0 end
    local pending = {}
    for key, entry in pairs(store() or {}) do
        if entry.ts and entry.ts > since then pending[#pending + 1] = key end
    end
    if #pending == 0 then return 0 end
    self.lastReply = now
    local function reply()
        local sent = 0
        for _, key in ipairs(pending) do
            local entry = (store() or {})[key]
            if entry and not wasSeen(key, entry.ts) and comm() then
                comm():Send("GNOTE", { key, "", tostring(entry.ts), entry.text or "" }, "GUILD", nil, true)
                sent = sent + 1
            end
        end
        return sent
    end
    if type(Compat.After) == "function" then
        Compat.After(math.random() * 5, reply)
        return #pending
    end
    return reply()
end

--- Der eigene Stand: der juengste Stempel, den dieser Client kennt.
function GuildNotes:Newest()
    local newest = 0
    for _, entry in pairs(store() or {}) do
        if entry.ts and entry.ts > newest then newest = entry.ts end
    end
    return newest
end

--- Bittet die Gilde um alles, was juenger ist als der eigene Stand.
function GuildNotes:Request()
    if not comm() then return false end
    return comm():Send("GNOTEQ", { tostring(self:Newest()) }, "GUILD", nil, true)
end

-- ================================================================== Start -----

function GuildNotes:OnEnable()
    local Comm = comm()
    if Comm then
        Comm:On("GNOTE", function(sender, fields) GuildNotes:OnNote(sender, fields) end, "GuildNotes")
        Comm:On("GNOTEQ", function(sender, fields) GuildNotes:OnRequest(sender, fields) end, "GuildNotes")
    end
    if type(Compat.After) == "function" then
        Compat.After(8, function() GuildNotes:Request() end)
    end
end
