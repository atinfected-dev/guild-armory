--[[----------------------------------------------------------------------------
    Communication/Comm — Addon-Nachrichten zwischen den Clients der Gilde.

    Kein UI. Transportschicht: Kodierung, Versand, Empfang, Verteilung nach
    Nachrichtentyp. Was in den Nachrichten steht, entscheidet der Aufrufer.

    NICHT GEMESSEN — und das steht hier, weil es wichtig ist: In keinem der
    bisherigen Probe-Laeufe ist CHAT_MSG_ADDON auch nur einmal gefeuert. Der
    Grund ist einfach (es laeuft noch kein zweiter Client mit diesem Addon),
    aber er bedeutet auch: Dieser Weg ist ungeprueft. Alles hier ist deshalb
    defensiv gebaut und meldet Fehler, statt sie zu verschlucken.

    FORMAT — bewusst kein JSON:
        GA1|<typ>|<feld>|<feld>|...
    Eine Addon-Nachricht fasst 255 Zeichen. JSON kostet davon ein Drittel an
    Klammern und Anfuehrungszeichen. Die Nachrichten hier sind flach und kurz,
    da traegt ein Trennzeichen weiter.

    KEINE ITEM-LINKS IM TRANSPORT. Ein Itemlink enthaelt selbst "|" und
    Steuersequenzen — er wuerde das Trennzeichen sprengen und unterwegs vom
    Chatsystem veraendert. Verschickt wird die Item-ID; der Empfaenger baut den
    Link selbst aus seinem eigenen Client. Das ist kuerzer UND richtiger.

    DROSSELUNG (Phase 7): Der Client verwirft Addon-Nachrichten stillschweigend,
    wenn zu viele auf einmal kommen — kein Fehler, kein Rueckgabewert, die
    Nachricht ist einfach weg. Deshalb geht alles durch eine Warteschlange, die
    hoechstens eine Nachricht je RATE Sekunden abschickt. Eilige Nachrichten
    (eine Lootsession laeuft) draengeln sich vor Massendaten (Abgleich).

    STUECKELUNG (Phase 7): Was nicht in 240 Zeichen passt, wird als Blob in
    Stuecke zerlegt und beim Empfaenger wieder zusammengesetzt. Unvollstaendige
    Blobs werden nach BLOB_TIMEOUT verworfen, statt ewig Speicher zu halten.

    WAS DIESE SCHICHT WEITERHIN NICHT LEISTET: Wiederholung bei Verlust. Geht
    ein Stueck verloren, faellt der ganze Blob nach dem Zeitfenster weg und der
    Absender erfaehrt nichts davon. Das ist bewusst so: Eine Quittierung je
    Stueck wuerde den Nachrichtenverkehr verdoppeln, und die Daten hier sind
    allesamt solche, die beim naechsten Anlass erneut geschickt werden.
------------------------------------------------------------------------------]]

local _, GA = ...

local Comm = {}
GA.Core.Comm = Comm

local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

--- Protokollfassung. Steigt, sobald sich das Format aendert; Nachrichten einer
--- unbekannten Fassung werden verworfen statt falsch gelesen.
Comm.VERSION = "GA1"

--- Groesse einer Addon-Nachricht. Laengere werden vom Client abgeschnitten —
--- lieber vorher ablehnen und melden.
local MAX_PAYLOAD = 240

--- Abstand zwischen zwei Nachrichten. 0.2 s sind fuenf je Sekunde — deutlich
--- unter dem, was der Client verwirft, und schnell genug, dass eine Lootsession
--- mit fuenf Gegenstaenden in gut einer Sekunde draussen ist.
local RATE = 0.2

--- So lange wird auf fehlende Stuecke eines Blobs gewartet.
local BLOB_TIMEOUT = 30

--- Nutzlast je Stueck: Von MAX_PAYLOAD gehen Kopfdaten ab (Fassung, Typ,
--- Blob-Kennung, Index, Anzahl, Art) — grosszuegig gerechnet.
local CHUNK_SIZE = 150

local handlers = {}
local blobHandlers = {}

--- Warteschlange. urgent zuerst, dann bulk.
local queue = { urgent = {}, bulk = {} }
local draining = false

--- Eingehende Blobs: [absender.."/"..blobId] = { parts, total, kind, ts }
local incoming = {}

--- EIN FLUESTERZIEL IST NUR DER NAME — OHNE REALM.
---
--- Gemessen 20.09.2026 mit einem zweiten Client. Erst schlug das hier fehl:
---
---   "No player named 'Larrin Lasereule-ClassicBetaPvE2' is currently playing"
---
--- Das war die aus Util.NormalizeName zusammengebaute Form (Leerzeichen im
--- Realm entfernt). Der zweite Versuch — die Schreibweise unveraendert
--- zurueckgeben, so wie der Server sie geschickt hat, also
--- "Larrin Lasereule-Classic Beta PvE 2" — funktionierte ebenfalls nicht.
---
--- Was funktioniert, ist der blosse Name: "Larrin Lasereule".
---
--- WAS DAS KOSTET: Fluestern ueber Realmgrenzen hinweg geht damit nicht. Das
--- ist kein Versehen, sondern die Folge der Messung — und auf einem Realm
--- ohne Verbund gibt es die Grenze ohnehin nicht. Taucht der Fall auf, wird
--- er gemessen und dann behandelt, nicht vorher geraten.
---
--- Nebenbei gemessen: Charakternamen auf Forever duerfen LEERZEICHEN
--- enthalten ("Larrin Lasereule", "Günther Gammelbein"). Getrennt wird
--- deshalb am BINDESTRICH, nie am Leerzeichen — wer Namen an Leerzeichen
--- zerlegt, zerlegt hier Personen.

--- @return string der Name, unter dem dieser Spieler erreichbar ist
function Comm:WhisperTarget(name)
    if not name or name == "" then return name end
    return GA.Core.Util.ShortName(name)
end

--- Laufende Nummer fuer Blob-Kennungen.
local blobCounter = 0

-- ================================================================== Kodierung -

--- "|" und "\" sind die einzigen Zeichen, die das Format stoeren.
local function escape(text)
    if text == nil then return "" end
    text = tostring(text)
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, "|", "\\p")
    return text
end

local function unescape(text)
    text = string.gsub(text, "\\p", "|")
    text = string.gsub(text, "\\\\", "\\")
    return text
end

--- Zerlegt an unmaskierten "|". Ein einfaches gmatch wuerde auch die
--- maskierten treffen, deshalb Zeichen fuer Zeichen.
local function split(payload)
    local fields, current, index = {}, {}, 1
    while index <= #payload do
        local char = string.sub(payload, index, index)
        if char == "\\" then
            current[#current + 1] = string.sub(payload, index, index + 1)
            index = index + 2
        elseif char == "|" then
            fields[#fields + 1] = unescape(table.concat(current))
            current = {}
            index = index + 1
        else
            current[#current + 1] = char
            index = index + 1
        end
    end
    fields[#fields + 1] = unescape(table.concat(current))
    return fields
end

function Comm:Encode(messageType, fields)
    local parts = { Comm.VERSION, escape(messageType) }
    for _, value in ipairs(fields or {}) do
        parts[#parts + 1] = escape(value)
    end
    return table.concat(parts, "|")
end

--- @return string|nil typ, table|nil felder
function Comm:Decode(payload)
    if type(payload) ~= "string" or payload == "" then return nil end

    local fields = split(payload)
    if fields[1] ~= Comm.VERSION then return nil end

    local messageType = fields[2]
    if not messageType or messageType == "" then return nil end

    local rest = {}
    for index = 3, #fields do rest[#rest + 1] = fields[index] end
    return messageType, rest
end

-- ================================================================== Versand ---

--- Welcher Kanal passt zur aktuellen Gruppe? Ausserhalb einer Gruppe gibt es
--- keinen — dann wird nicht gesendet, statt an die Gilde zu streuen.
function Comm:GroupChannel()
    if Compat.IsInRaid() then return "RAID" end
    if Compat.IsInGroup() then return "PARTY" end
    return nil
end

--- Schiebt eine fertige Nutzlast in die Warteschlange.
--- Reiht eine fertige Nutzlast ein.
---
--- HIER wird das Fluesterziel gekuerzt, nicht bei den Aufrufern.
---
--- Gemeldet 21.09.2026 aus dem Spiel: "No player named 'Heisenberg
--- Runeblight-ClassicBetaPvE2' is currently playing." Comm:Send kuerzte
--- laengst richtig — aber Comm:SendBlob reichte sein Ziel ungekuerzt an
--- diese Funktion durch. Der Kommentar in Send sagte damals schon, warum das
--- an EINER Stelle stehen muss, und die naechste Funktion hat es trotzdem
--- vergessen. Also steht es jetzt an der Stelle, durch die beide Wege
--- muessen.
local function enqueue(payload, channel, target, bulk)
    if channel == "WHISPER" and target then
        target = Comm:WhisperTarget(target)
    end

    local list = bulk and queue.bulk or queue.urgent
    list[#list + 1] = { payload = payload, channel = channel, target = target }
    Comm:Drain()
end

--- Schickt die naechste wartende Nachricht und plant die uebernaechste ein.
--- Eine Nachricht je RATE Sekunden: Der Client verwirft Addon-Nachrichten
--- stillschweigend, wenn zu viele auf einmal kommen.
function Comm:Drain()
    if draining then return end

    local entry = table.remove(queue.urgent, 1) or table.remove(queue.bulk, 1)
    if not entry then return end

    draining = true
    Compat.SendAddonMessage(GA.const.COMM_PREFIX, entry.payload, entry.channel, entry.target)

    Compat.After(RATE, function()
        draining = false
        Comm:Drain()
    end)
end

function Comm:QueueLength()
    return #queue.urgent + #queue.bulk
end

--- @param channel string|nil  "RAID" | "PARTY" | "GUILD" | "WHISPER"; nil = Gruppe
--- @param bulk boolean|nil  true = Massendaten, duerfen warten
--- @return boolean eingereiht, string|nil grund
function Comm:Send(messageType, fields, channel, target, bulk)
    if not GA.has.chatInfo then return false, "noapi" end

    channel = channel or self:GroupChannel()
    if not channel then return false, "nochannel" end
    if channel == "WHISPER" and not target then return false, "notarget" end

    -- Das Fluesterziel kuerzt enqueue, nicht diese Funktion: Dort laufen
    -- Send UND SendBlob durch. Hier stand es vorher, und SendBlob ging daran
    -- vorbei (siehe Kommentar bei enqueue).

    local payload = self:Encode(messageType, fields)
    if #payload > MAX_PAYLOAD then
        -- Nicht abschneiden: Eine halbe Nachricht wird beim Empfaenger zu
        -- falschen Daten, und das faellt erst viel spaeter auf. Wer laengere
        -- Nutzlasten hat, nimmt SendBlob.
        Debug:Warn("Nachricht %s zu lang (%d Zeichen) — nicht gesendet.", messageType, #payload)
        return false, "toolong"
    end

    enqueue(payload, channel, target, bulk)
    Debug:Print("comm", "eingereiht %s -> %s%s", messageType, channel,
        target and (" " .. target) or "")
    return true
end

-- ================================================================== Blobs -----

--- Verschickt beliebig langen Text in Stuecken.
---
--- Die Stuecke tragen eine gemeinsame Kennung und ihre Nummer. Der Empfaenger
--- setzt sie wieder zusammen — auch wenn sie in anderer Reihenfolge ankommen,
--- was bei getrennten Nachrichten nicht ausgeschlossen ist.
--- @return boolean eingereiht, number|nil anzahlStuecke
function Comm:SendBlob(kind, text, channel, target, bulk)
    if not GA.has.chatInfo then return false end
    if type(text) ~= "string" or text == "" then return false end

    channel = channel or self:GroupChannel()
    if not channel then return false end

    blobCounter = blobCounter + 1
    -- Die Kennung muss nur beim selben Absender eindeutig sein: Der Empfaenger
    -- schluesselt ohnehin nach Absender UND Kennung.
    local blobId = string.format("%x%x", Compat.Now() % 65536, blobCounter % 256)

    local total = math.ceil(#text / CHUNK_SIZE)
    for index = 1, total do
        local part = string.sub(text, (index - 1) * CHUNK_SIZE + 1, index * CHUNK_SIZE)
        local payload = self:Encode("B", { blobId, index, total, kind, part })
        -- Sicherheitsnetz: Sollte ein Stueck durch Maskierung doch zu lang
        -- werden, faellt der ganze Blob aus — halb ankommen darf er nicht.
        if #payload > MAX_PAYLOAD then
            Debug:Warn("Blobstueck zu lang (%d) — %s nicht gesendet.", #payload, tostring(kind))
            return false
        end
        enqueue(payload, channel, target, bulk ~= false)
    end

    Debug:Print("comm", "Blob %s: %d Stueck(e), %d Zeichen", tostring(kind), total, #text)
    return true, total
end

--- @param handler function(sender, text, channel)
function Comm:OnBlob(kind, handler, owner)
    blobHandlers[kind] = blobHandlers[kind] or {}
    table.insert(blobHandlers[kind], { handler = handler, owner = owner })
end

--- Nimmt ein Stueck entgegen und stellt den Blob fertig, sobald alle da sind.
function Comm:ReceiveChunk(sender, fields, channel)
    local blobId, index, total, kind, part =
        fields[1], tonumber(fields[2]), tonumber(fields[3]), fields[4], fields[5] or ""
    if not blobId or not index or not total or not kind then return end
    if total < 1 or index < 1 or index > total then return end

    local key = tostring(sender) .. "/" .. blobId
    local buffer = incoming[key]

    -- EINE KENNUNG KANN WIEDERVERWENDET WERDEN. Der Blobzaehler des Absenders
    -- faengt nach einem /reload wieder bei eins an. Trifft die neue Kennung
    -- auf einen halben alten Puffer, gilt Stueck 1 als "schon da" und wird
    -- verworfen — der neue Blob wird nie fertig, und niemand erfaehrt davon.
    --
    -- Eine abweichende Stueckzahl ist der messbare Hinweis darauf, dass es
    -- ein anderer Blob ist. Bei gleicher Stueckzahl bleibt der Fall
    -- unerkennbar; dann greift nach BLOB_TIMEOUT das Zeitfenster.
    if buffer and buffer.total ~= total then
        Debug:Print("comm", "Blob-Kennung %s von %s neu belegt (%d statt %d Stuecke)",
            tostring(blobId), tostring(sender), total, buffer.total)
        incoming[key] = nil
        buffer = nil
    end

    if not buffer then
        buffer = { parts = {}, have = 0, total = total, kind = kind, ts = Compat.Now() }
        incoming[key] = buffer

        Compat.After(BLOB_TIMEOUT, function()
            local stale = incoming[key]
            if stale and stale.ts == buffer.ts then
                incoming[key] = nil
                Debug:Print("comm", "Blob von %s unvollstaendig (%d/%d) — verworfen",
                    tostring(sender), stale.have, stale.total)
            end
        end)
    end

    -- Ein doppelt angekommenes Stueck zaehlt nicht zweimal.
    if buffer.parts[index] then return end
    buffer.parts[index] = part
    buffer.have = buffer.have + 1

    if buffer.have < buffer.total then return end
    incoming[key] = nil

    local text = table.concat(buffer.parts)
    local list = blobHandlers[buffer.kind]
    if not list then
        Debug:Print("comm", "Kein Empfaenger fuer Blob %s", tostring(buffer.kind))
        return
    end

    for _, entry in ipairs(list) do
        local ok, err = pcall(entry.handler, sender, text, channel)
        if not ok then
            Debug:Warn("Fehler im Blob-Empfaenger fuer %s: %s", tostring(buffer.kind), tostring(err))
        end
    end
end

-- ================================================================== Empfang ---

--- @param handler function(sender, fields, channel)
function Comm:On(messageType, handler, owner)
    handlers[messageType] = handlers[messageType] or {}
    table.insert(handlers[messageType], { handler = handler, owner = owner })
end

--- Zaehlt, was abgewiesen wurde. /ga sync nennt es.
Comm.rejected = { stranger = 0, unknown = 0 }

--- Darf ich diese Nachricht ueberhaupt annehmen?
---
--- NUR CLIENTS DERSELBEN GILDE.
---
--- Bis 22.09.2026 nahm OnMessage jede Nachricht von jedem an. Ueber den
--- GUILD-Kanal ist das harmlos: Dorthin kommt nur, wer in der Gilde ist —
--- das entscheidet der Server, nicht das Addon. Ueber RAID und PARTY sitzt
--- aber jeder Fremde im Schlachtzug mit, und eine FLUESTERNACHRICHT kann
--- jeder auf dem Server schicken.
---
--- Damit konnte jeder Beliebige Charakterdaten, Vergaben und Erfolge in eine
--- fremde Gildendatenbank schreiben. Nicht aus Boesartigkeit — es genuegt,
--- dass zwei Gilden dasselbe Addon in derselben Schlachtzugsgruppe benutzen.
---
--- Der Absendername kommt vom Server und ist nicht faelschbar. Das ist die
--- einzige belastbare Eigenschaft, die dieser Transportweg hat, und genau
--- darauf baut die Pruefung.
---
--- @return boolean darf, string|nil grund
function Comm:MayAccept(sender, channel)
    -- Der GUILD-Kanal traegt die Antwort in sich: Der Server stellt ihn nur
    -- Gildenmitgliedern zu.
    if channel == "GUILD" then return true end

    -- Eigene Nachrichten kommen zurueck; manche Empfaenger brauchen sie.
    if self:IsSelf(sender) then return true end

    local Guild = GA.Modules.Guild
    if not Guild then return false, "unknown" end

    local member = Guild:IsMember(sender)
    if member == true then return true end
    if member == false then return false, "stranger" end

    -- WEISS NICHT — das Roster ist noch nicht da (kurz nach dem Einloggen)
    -- oder unvollstaendig. Abgewiesen wird trotzdem: Eine fremde Nachricht
    -- anzunehmen schreibt in die Datenbank, und das laesst sich nicht
    -- zurueckholen. Eine verworfene Nachricht dagegen kommt wieder — der
    -- Abgleich laeuft alle zehn Minuten von selbst.
    Guild:RequestRebuild(2)
    return false, "unknown"
end

function Comm:OnMessage(prefix, payload, channel, sender)
    if prefix ~= GA.const.COMM_PREFIX then return end

    local allowed, reason = self:MayAccept(sender, channel)
    if not allowed then
        self.rejected[reason] = (self.rejected[reason] or 0) + 1
        Debug:Print("comm", "Nachricht von %s ueber %s verworfen (%s)",
            tostring(sender), tostring(channel), tostring(reason))
        return
    end

    local messageType, fields = self:Decode(payload)
    if not messageType then
        Debug:Print("comm", "Unlesbare Nachricht von %s verworfen", tostring(sender))
        return
    end

    -- Der Absendername kommt als "Name-Realm". Der eigene Realm wird
    -- weggelassen — aber nicht ueberall, deshalb normalisiert weitergeben.
    local normalized = GA.Core.Util.NormalizeName(sender)

    -- Blobstuecke gehen nicht an die normalen Empfaenger, sondern in die
    -- Zusammensetzung.
    if messageType == "B" then
        self:ReceiveChunk(normalized, fields, channel)
        return
    end

    local list = handlers[messageType]
    if not list then
        Debug:Print("comm", "Kein Empfaenger fuer %s (von %s)", messageType, tostring(sender))
        return
    end

    for _, entry in ipairs(list) do
        local ok, err = pcall(entry.handler, normalized, fields, channel)
        if not ok then
            Debug:Warn("Fehler im Empfaenger fuer %s: %s", messageType, tostring(err))
        end
    end
end

--- Ist der Absender ich selbst? Eigene Nachrichten kommen zurueck; manche
--- Empfaenger wollen sie (Gleichlauf), andere nicht.
function Comm:IsSelf(sender)
    local identity = Compat.GetPlayerIdentity()
    return GA.Core.Util.NormalizeName(sender) == GA.Core.Util.NormalizeName(identity.name)
end

-- ================================================================== Start ------

function Comm:OnEnable()
    if not GA.has.chatInfo then
        Debug:Warn("Keine Addon-Nachrichten moeglich — Synchronisation faellt aus.")
        return
    end

    Compat.RegisterAddonPrefix(GA.const.COMM_PREFIX)

    GA.Core.Events:Register("CHAT_MSG_ADDON", function(_, prefix, payload, channel, sender)
        Comm:OnMessage(prefix, payload, channel, sender)
    end, "Comm")
end
