--[[----------------------------------------------------------------------------
    Communication/Sync — Abgleich zwischen den Clients der Gilde.

    Kein UI. Entscheidet, WAS geschickt wird, WER etwas schicken darf und was
    bei Widerspruch geschieht. Der Transport liegt in Communication/Comm.

    ===========================================================================
    DIE EINE SICHERHEITSEIGENSCHAFT, DIE ES WIRKLICH GIBT
    ===========================================================================

    Clientseitig laesst sich nichts gegen Manipulation absichern — das steht
    seit Abschnitt 1.6 der Architektur so da und gilt weiter. Mit EINER
    Ausnahme, und die traegt dieses Modul:

        Der Absendername einer Addon-Nachricht kommt vom SERVER, nicht aus der
        Nachricht. Ein Addon kann ihn nicht faelschen.

    Daraus folgt die Grundregel:

        EIN CLIENT DARF NUR DEN CHARAKTER VEROEFFENTLICHEN, ALS DER ER GERADE
        EINGELOGGT IST.

    Kommt ein Charakterdatensatz herein, dessen Name nicht der Absendername
    ist, wird er verworfen und im Journal vermerkt. Das schliesst die
    haesslichste Luecke: dass jemand fremde Ausruestung oder fremde
    Wunschlisten in die Gildendatenbank schreibt.

    Fuer Lootvergaben gilt dasselbe Muster mit dem Lootmeister: Maßgeblich ist,
    wer die Vergabe angelegt hat. Meldet ein anderer Client dieselbe Vergabe
    anders, wird NICHT ueberschrieben, sondern ein Konflikt ins Journal
    geschrieben und angezeigt.

    WAS DAS NICHT LEISTET: Es hindert niemanden daran, ueber seinen EIGENEN
    Charakter Unsinn zu behaupten — ein erfundenes Itemlevel etwa. Dagegen
    hilft kein Addon. Deshalb traegt jeder so erhaltene Stand source = "sync"
    und wird nie als eigene Messung dargestellt.
------------------------------------------------------------------------------]]

local _, GA = ...

local Sync = {}
GA.Modules.Sync = Sync

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Json = GA.Core.Json

--- Protokollfassung dieses Moduls. Steigt, wenn sich die Nutzlasten aendern.
Sync.VERSION = 1

--- Wer laeuft noch mit diesem Addon? [name] = { version, ts }
Sync.peers = {}

local function comm()
    return GA.Core.Comm
end

-- ================================================================== Hilfen ---

--- Ist dieser Absender der Charakter, um den es im Datensatz geht?
--- Der Absendername kommt vom Server und laesst sich nicht faelschen.
--- Der Server sagt, wer sendet — aber nicht immer mit demselben Namen wie
--- UnitName. Der Vergleich liegt in Util.SameCharacter und ist dort
--- begruendet: Namen auf diesem Realm haben zwei Teile, und nicht jede
--- Quelle nennt beide.
local function isOwner(sender, name)
    if not sender or not name then return false end
    return Util.SameCharacter(sender, name)
end

local function journalConflict(kind, target, detail)
    GA.Core.Database:Journal("SYNC_CONFLICT", target, kind, detail)
    Sync.conflicts = (Sync.conflicts or 0) + 1
    GA.Core.Callbacks:Fire("SYNC_CONFLICT", kind, target, detail)
end

-- ================================================================== Senden ---

--- Meldet sich in der Gruppe/Gilde. Die Antworten fuellen Sync.peers.
function Sync:Hello(channel)
    if not comm() then return end
    comm():Send("HELLO", { Sync.VERSION, GA.version }, channel)
end

--- Der eigene Charakter als Datensatz — nur das, was andere brauchen.
--- Itemlinks werden NICHT verschickt: Sie enthalten Steuerzeichen, sind lang
--- und der Empfaenger baut sie ohnehin aus der ID selbst.
function Sync:BuildCharacterPayload()
    local identity = Compat.GetPlayerIdentity()
    if not identity.guid then return nil end

    local character = GA.Core.Database.account.characters[identity.guid]
    if not character then return nil end

    local equipment = {}
    for slotID, entry in pairs(character.equipment or {}) do
        if entry.itemID then
            equipment[#equipment + 1] = {
                s = slotID, i = entry.itemID, l = entry.itemLevel, e = entry.enchantID,
            }
        end
    end

    return Json.Encode({
        v = Sync.VERSION,
        guid = identity.guid,
        name = identity.name,
        realm = identity.realm,
        class = identity.class,
        level = identity.level,
        rank = character.guildRank,
        ilvl = character.itemLevel and character.itemLevel.value,
        count = character.itemLevel and character.itemLevel.count,
        ts = character.equipmentTs,
        eq = equipment,
    })
end

--- Veroeffentlicht den eigenen Charakter — nur mit ausdruecklicher Freigabe.
--- @return boolean gesendet, string|nil grund
function Sync:PublishCharacter(channel)
    -- KEIN AUSSCHALTER MEHR (20.09.2026, auf Ansage der Gilde).
    --
    -- Bis hierher war das Veroeffentlichen eine Freigabe, die jeder selbst
    -- setzt, und der Standard war AUS. Die Gilde hat entschieden, dass
    -- Ausruestungsdaten geteilt werden — also wird geteilt, und es gibt
    -- keinen Schalter, der so tut, als koenne man es sich aussuchen.
    --
    -- WAS EIN ADDON DABEI NICHT KANN: es erzwingen. Wer nicht teilen will,
    -- deaktiviert das Addon oder installiert es nicht. Sichtbar wird das
    -- ueber die Versionsuebersicht — wer nicht antwortet, steht dort. Das
    -- ist die einzige Durchsetzung, die es gibt, und sie ist sozial, nicht
    -- technisch.
    if not comm() then return false, "nocomm" end

    local payload = self:BuildCharacterPayload()
    if not payload then return false, "nodata" end

    local ok = comm():SendBlob("CHAR", payload, channel)
    if ok then
        self.lastPublish = Util.Now()
        Debug:Print("comm", "Charakter veroeffentlicht (%d Zeichen)", #payload)
    end
    return ok and true or false
end

--- Die eigene Wunschliste. Nur die offenen Eintraege: Erfuelltes ist Historie
--- des eigenen Clients und geht die Gilde nichts an.
function Sync:PublishWishlist(channel)
    if not comm() then return false, "nocomm" end

    local identity = Compat.GetPlayerIdentity()
    if not identity.guid then return false, "nodata" end

    local entries = {}
    for _, entry in ipairs(GA.Modules.Wishlist:Get(identity.guid)) do
        if not entry.fulfilledByAwardId then
            entries[#entries + 1] = { i = entry.itemID, p = entry.priority }
        end
    end

    local payload = Json.Encode({
        v = Sync.VERSION, guid = identity.guid, name = identity.name, w = entries,
    })
    return comm():SendBlob("WISH", payload, channel) and true or false
end

--- Eine Vergabe an die Gruppe. Nur der Lootmeister, der sie angelegt hat.
function Sync:PublishAward(awardId, channel, target)
    if not comm() then return false, "nocomm" end

    local award = GA.Modules.Awards:Get(awardId)
    if not award then return false, "unknown" end

    local identity = Compat.GetPlayerIdentity()
    if award.lootMasterGuid and award.lootMasterGuid ~= identity.guid then
        return false, "notmine"
    end

    -- EIN FEHLENDES lootMasterGuid IST KEIN EIGENTUMSNACHWEIS. Ein Datensatz,
    -- der ueber den Abgleich oder aus einer Sicherung hereinkam, hat keins —
    -- und wuerde ohne diese Zeile von jedem Empfaenger weiterverbreitet. Bei
    -- 40 Leuten in der Gilde ist das keine Synchronisation mehr, sondern eine
    -- Lawine: Jeder schickt an alle, jeder Empfang loest den naechsten aus.
    if award.source == "sync" or award.source == "import" then
        return false, "notmine"
    end

    -- ERFUNDENES BLEIBT HIER, AUCH WENN DER PROBEBETRIEB LAENGST AUS IST.
    --
    -- Der Riegel in Comm greift nur, solange er laeuft. Wer danach
    -- ausschaltet, um sich das Ergebnis anzusehen, und dabei einen echten
    -- Abgleich ausloest, wuerde seine Testvergaben an die ganze Gilde
    -- schicken — und dort sind sie nicht von echten zu unterscheiden. Das
    -- Merkmal am Datensatz gilt laenger als der Schalter.
    if award.simulated then return false, "simulated" end

    local payload = Json.Encode({
        v = Sync.VERSION,
        id = award.id,
        item = award.itemID,
        name = award.itemName,
        q = award.quality,
        to = award.recipientName,
        toGuid = award.recipientGuid,
        by = identity.name,
        resp = award.response,
        status = award.status,
        conf = award.confirmation,
        src = award.encounterName or award.sourceName,
        ts = award.ts,
    })
    return comm():SendBlob("AWARDSYNC", payload, channel, target, true) and true or false
end

-- ================================================================== Empfang --

--- Ein Charakterdatensatz von einem anderen Client.
function Sync:OnCharacter(sender, text)
    local ok, data = pcall(Json.Decode, text)
    if not ok or type(data) ~= "table" or not data.guid then return end

    -- DIE Regel: Nur der eigene Charakter, und der Server sagt, wer sendet.
    if not isOwner(sender, data.name) then
        journalConflict("CHAR_FOREIGN", data.name,
            { sender = sender, reason = "Absender ist nicht der Charakter" })
        Debug:Warn("Verworfen: %s wollte den Charakter %s veroeffentlichen.",
            tostring(sender), tostring(data.name))
        return
    end

    local identity = Compat.GetPlayerIdentity()
    if data.guid == identity.guid then return end  -- die eigene Nachricht zurueck

    local db = GA.Core.Database
    local character = db:GetCharacter(data.guid, {
        name = data.name, realm = data.realm, class = data.class,
        level = data.level, guildRank = data.rank,
    })

    -- Eine eigene Messung wird NICHT von einer Fremdmeldung ueberschrieben.
    -- Wer den Charakter selbst gespielt oder inspiziert hat, weiss es besser.
    if character.source == "self" then return end
    if character.source == "inspect" and (character.equipmentTs or 0) > (data.ts or 0) then
        return
    end

    local equipment = {}
    for _, entry in ipairs(data.eq or {}) do
        if entry.s and entry.i then
            equipment[entry.s] = { itemID = entry.i, itemLevel = entry.l, enchantID = entry.e }
            GA.Modules.ItemIndex:Learn(entry.i)
        end
    end

    character.equipment = equipment
    character.equipmentTs = data.ts or Util.Now()
    character.source = "sync"
    character.syncFrom = sender
    character.itemLevel = { value = data.ilvl, count = data.count, ts = character.equipmentTs }

    Debug:Print("comm", "Charakter uebernommen: %s (%d Plaetze)", tostring(data.name), #(data.eq or {}))
    GA.Core.Callbacks:Fire("EQUIPMENT_UPDATED", data.guid)
end

function Sync:OnWishlist(sender, text)
    local ok, data = pcall(Json.Decode, text)
    if not ok or type(data) ~= "table" or not data.guid then return end

    if not isOwner(sender, data.name) then
        journalConflict("WISH_FOREIGN", data.name, { sender = sender })
        return
    end

    local identity = Compat.GetPlayerIdentity()
    if data.guid == identity.guid then return end

    -- Die fremde Liste ersetzt die bisher bekannte fremde Liste vollstaendig:
    -- Der Absender ist dafuer massgeblich, und ein Zusammenfuehren wuerde
    -- geloeschte Wuensche wieder auferstehen lassen.
    local Wishlist = GA.Modules.Wishlist
    GA.Core.Database.account.wishlists[data.guid] = {}
    for _, entry in ipairs(data.w or {}) do
        if entry.i and entry.p then
            Wishlist:Add(data.guid, entry.i, entry.p)
            GA.Modules.ItemIndex:Learn(entry.i)
        end
    end

    Debug:Print("comm", "Wunschliste uebernommen: %s (%d Eintraege)",
        tostring(data.name), #(data.w or {}))
end

--- Eine Vergabe von einem anderen Client.
function Sync:OnAward(sender, text)
    local ok, data = pcall(Json.Decode, text)
    if not ok or type(data) ~= "table" or not data.id then return end

    -- Der Lootmeister im Datensatz muss der Absender sein.
    if not isOwner(sender, data.by) then
        journalConflict("AWARD_FOREIGN", data.id, { sender = sender, claimed = data.by })
        return
    end

    -- Die eigene Nachricht kommt zurueck: Der Server spiegelt, was an GILDE
    -- oder SCHLACHTZUG hinausgeht, an den Absender zurueck. OnCharacter und
    -- OnWishlist verwerfen das ueber die GUID; hier ging es bis Phase 8
    -- durch — und weil der Empfang AWARD_CHANGED feuert und AWARD_CHANGED
    -- wieder PublishAward aufruft, war das ein Kreisel ohne Abbruch.
    if comm() and comm():IsSelf(sender) then return end

    local Awards = GA.Modules.Awards
    local existing = Awards:Get(data.id)

    if existing then
        -- Schon bekannt. Stammt sie von jemand anderem, ist das ein Widerspruch,
        -- der NICHT durch Ueberschreiben aufgeloest wird: Die Historie wuerde
        -- sich lautlos aendern, und niemand wuesste es.
        local owner = existing.lootMasterName
        if owner and not isOwner(sender, owner) then
            journalConflict("AWARD_OWNER", data.id,
                { sender = sender, owner = owner, to = data.to })
            Debug:Warn("Widerspruch bei Vergabe %s: %s meldet sie, angelegt hat sie %s.",
                tostring(data.id), tostring(sender), tostring(owner))
            return
        end
        if existing.recipientName ~= data.to and existing.recipientName then
            journalConflict("AWARD_RECIPIENT", data.id,
                { was = existing.recipientName, now = data.to, sender = sender })
        end
        -- Nur feuern, wenn sich wirklich etwas geaendert hat. Ein Ereignis
        -- fuer eine Nicht-Aenderung ist nicht bloss ueberfluessig: Am anderen
        -- Ende haengt PublishAward, und damit wuerde jede eingehende Meldung
        -- eine ausgehende erzeugen.
        local before = { existing.status, existing.confirmation, existing.recipientName }
        existing.status = data.status or existing.status
        existing.confirmation = data.conf or existing.confirmation
        existing.recipientName = data.to or existing.recipientName

        if before[1] ~= existing.status or before[2] ~= existing.confirmation
            or before[3] ~= existing.recipientName then
            GA.Core.Callbacks:Fire("AWARD_CHANGED", data.id, before[1], existing.status)
        end
        return
    end

    -- UNTER DER SCHWELLE KOMMT NICHTS HEREIN, WAS NOCH NICHT VERGEBEN IST.
    --
    -- GEFUNDEN 26.09.2026 in den gespeicherten Daten: ein "Schattenedelstein"
    -- mit quality = 2 in der Liste, bei einer Schwelle von 3. Die lokale
    -- Erfassung hatte ihn nie gesehen — er kam ueber den Abgleich, und dort
    -- galt keine Schwelle. Wer auf seinem Client gruen mitschreibt, fuellte
    -- damit die Listen aller anderen.
    --
    -- WAS SCHON VERGEBEN IST, BLEIBT. Das ist Geschichte und gehoert in die
    -- Historie, auch wenn es unterhalb der eigenen Schwelle liegt: Wer es
    -- bekommen hat, hat es bekommen.
    local Schema = GA.Data.Schema
    local schwelle = GA.Core.Config:Get("lootThresholdQuality") or 3
    local status = data.status or Schema.LootStatus.AWARDED

    -- EINE BLOSSE BEOBACHTUNG WIRD NICHT UEBERNOMMEN.
    --
    -- AUF ANSAGE 26.09.2026: "Der Loot soll nur detected werden im
    -- Sessionfenster, wenn ein Lootmeister ausgewaehlt ist."
    --
    -- Die eigene Erfassung haelt sich daran (siehe LootTracker:ShouldTrack).
    -- Ueber den Abgleich kam sie trotzdem herein: Jeder Client schickte, was
    -- er gesehen hatte, und was dort galt, wusste dieser hier nicht.
    --
    -- DETECTED heisst "hier lag etwas" und sonst nichts — keine Sitzung,
    -- keine Entscheidung, niemand, der es verteilt. Drei Leute mit dem
    -- Addon beobachten denselben Fund dreimal, und mit verschiedenen
    -- Sprachen stand er dreimal verschieden da ("Kobrahns Griff",
    -- "Cobrahn's Grasp"). Gemeldet genau so, mit Bild.
    --
    -- WAS WEITER HEREINKOMMT: alles, worin eine Entscheidung steckt — eine
    -- Sitzung, eine Vergabe, eine Uebergabe. Dafuer ist der Abgleich da.
    if status == Schema.LootStatus.DETECTED then
        Debug:Print("comm", "Fremde Erfassung ohne Sitzung verworfen: %s",
            tostring(data.name))
        return
    end

    local nochOffen = status == Schema.LootStatus.SESSION_OPEN
    if nochOffen and (data.q or 0) < schwelle then
        Debug:Print("comm", "Unter Schwelle verworfen: %s (%s)",
            tostring(data.name), tostring(data.q))
        return
    end

    -- DERSELBE FUND, AUF ZWEI CLIENTS ERKANNT.
    --
    -- GEMELDET 26.09.2026: "Muster gruene Wolltasche wird doppelt
    -- detected." Jeder Client legt beim Pluendern seine eigene Kennung an;
    -- kommt der Fund dann ueber den Abgleich herein, steht er zweimal da —
    -- und keine Kennung passt zur anderen.
    --
    -- DIE MELDUNG DES LOOTMEISTERS GILT. Die eigene Erfassung war eine
    -- Beobachtung, seine ist das Ergebnis. Die eigene wird deshalb
    -- abgeraeumt — abgebrochen, nicht geloescht, damit im Journal steht, was
    -- passiert ist.
    --
    -- NUR EIGENE, NOCH NICHT IN EINER SITZUNG. Steht der Gegenstand in
    -- meiner laufenden Sitzung und jemand anders meldet ihn als vergeben,
    -- ist das ein Widerspruch und kein Doppel — der gehoert ins Journal,
    -- nicht stillschweigend weggeraeumt.
    -- DIE EIGENE BEOBACHTUNG WEICHT DER ENTSCHEIDUNG — ABER NUR AUS DEM
    -- EIGENEN SCHLACHTZUG.
    --
    -- Was hier ankommt, traegt eine Entscheidung: eine Sitzung, eine
    -- Vergabe, eine Uebergabe. Die eigene Erfassung desselben Teils war die
    -- Beobachtung davor und stuende sonst als zweiter Eintrag daneben.
    --
    -- EINGEWANDT 26.09.2026: "Wenn 2 verschiedene Lootmeister in 2
    -- verschiedenen Raids oder Dungeons unterwegs sind, muss das ja auch
    -- funktionieren." Und ohne diese Pruefung tut es das nicht: Die
    -- Nachricht laeuft ueber den Gildenkanal, also erreicht sie auch den,
    -- der gerade woanders steht. Faellt dasselbe Teil in beiden Instanzen
    -- innerhalb einer Stunde — bei zwei Gruppen in derselben Instanz eher
    -- die Regel als die Ausnahme —, haette die Vergabe der einen Gruppe die
    -- Erfassung der anderen abgeraeumt.
    --
    -- Der Absender muss also in MEINER Gruppe stehen. Dann ist es derselbe
    -- Fund; sonst sind es zwei, und beide bleiben.
    local vorhanden = GA.Modules.Awards:FindLocalDetected(data.item, data.ts)
    if vorhanden and Compat.IsInMyGroup(sender) then
        GA.Modules.Awards:Cancel(vorhanden.id, "durch die Meldung des Lootmeisters ersetzt")
        Debug:Print("comm", "Erfassung ersetzt: %s", tostring(data.name))
    end

    -- Neu: uebernehmen, aber als fremden Datensatz kenntlich.
    GA.Core.Database.account.awards[data.id] = {
        id = data.id,
        ts = data.ts or Util.Now(),
        itemID = data.item,
        itemName = data.name,
        quality = data.q,
        recipientName = data.to,
        recipientGuid = data.toGuid,
        lootMasterName = data.by,
        response = data.resp,
        status = data.status or GA.Data.Schema.LootStatus.AWARDED,
        confirmation = data.conf,
        encounterName = data.src,
        source = "sync",
        statusHistory = { { status = data.status, ts = data.ts, by = data.by,
                            reason = "vom Lootmeister uebernommen" } },
        votes = {},
    }
    if data.item then GA.Modules.ItemIndex:Learn(data.item) end

    Debug:Print("comm", "Vergabe uebernommen: %s an %s", tostring(data.name), tostring(data.to))
    GA.Core.Callbacks:Fire("AWARD_CREATED", data.id)
end

-- ============================================================ Abgleich ------
--
-- WIE GLEICHEN SICH ZWEI CLIENTS AB, OHNE DIE GILDE ZUZUSPAMMEN?
--
-- Der naive Weg waere: Jeder schickt regelmaessig alles an die Gilde. Bei 40
-- Leuten mit je hundert Vergaben ist das unbenutzbar — und 39 von 40
-- Empfaengern kennen das meiste schon.
--
-- Stattdessen zwei Stufen:
--
--   1. JEDER SENDET EINEN WINZIGEN STECKBRIEF an die Gilde: wie viele
--      Vergaben er hat und wie alt die neueste ist. Das sind drei Zahlen.
--
--   2. WER MERKT, DASS IHM ETWAS FEHLT, FRAGT GEZIELT NACH — per Fluester-
--      nachricht, nicht an die Gilde. Die Antwort geht ebenfalls nur an den
--      Fragenden. So traegt die Gildenverbindung nur die drei Zahlen; die
--      Nutzlast laeuft zwischen genau zwei Clients.
--
-- Dazu zwei Bremsen gegen den Herdeneffekt: Wer nachfragt, wartet eine
-- zufaellige Zeit (sonst fragen alle gleichzeitig denselben), und es laeuft
-- immer nur EINE Anfrage.

--- Wie oft der Steckbrief hinausgeht. 10 Minuten sind eine winzige Nachricht
--- je Spieler und Viertelstunde — auch in einer grossen Gilde unauffaellig.
local DIGEST_INTERVAL = 600

--- Hoechstens so viele Vergaben je Anfrage. Wer weit zurueckliegt, holt beim
--- naechsten Steckbrief nach, statt eine Salve von 200 Blobs auszuloesen.
local MAX_DELTA = 20

--- Der eigene Stand in drei Zahlen.
function Sync:Digest()
    local newest, count = 0, 0
    for _, award in pairs(GA.Core.Database.account.awards) do
        count = count + 1
        if (award.ts or 0) > newest then newest = award.ts end
    end

    local characters = 0
    for _ in pairs(GA.Core.Database.account.characters) do characters = characters + 1 end

    return count, newest, characters
end

function Sync:SendDigest(channel)
    if not comm() then return false end
    local count, newest, characters = self:Digest()
    return comm():Send("DIGEST", { count, newest, characters }, channel or "GUILD", nil, true)
end

--- Hat der Absender etwas, das mir fehlt?
local function peerIsAhead(peerCount, peerNewest, myCount, myNewest)
    if peerNewest > myNewest then return true end
    -- Gleich alt, aber mehr Eintraege: Da fehlt mir etwas aus der
    -- Vergangenheit, das ein anderer Lootmeister angelegt hat.
    if peerNewest == myNewest and peerCount > myCount then return true end
    return false
end

Sync.peerIsAhead = peerIsAhead  -- fuer die Tests

--- Beantwortet eine Nachfrage: alles, was neuer ist als der Stand des Fragenden.
function Sync:AnswerWant(sender, sinceTs)
    sinceTs = tonumber(sinceTs) or 0

    local missing = {}
    for id, award in pairs(GA.Core.Database.account.awards) do
        if (award.ts or 0) > sinceTs then
            missing[#missing + 1] = { id = id, ts = award.ts or 0 }
        end
    end
    if #missing == 0 then return 0 end

    -- Aelteste zuerst: Wer mehrfach nachfragt, schliesst die Luecke von unten
    -- und bekommt bei jeder Runde ein Stueck mehr.
    table.sort(missing, function(a, b) return a.ts < b.ts end)

    local sent = 0
    for index = 1, math.min(#missing, MAX_DELTA) do
        if self:PublishAward(missing[index].id, "WHISPER", sender) then
            sent = sent + 1
        end
    end

    Debug:Print("comm", "Nachfrage von %s beantwortet: %d von %d", tostring(sender),
        sent, #missing)
    return sent
end

--- Plant eine Nachfrage mit zufaelliger Verzoegerung ein.
function Sync:RequestFrom(peer)
    if self.requestPending then return false end
    self.requestPending = peer

    -- Zufall gegen den Herdeneffekt: Ohne ihn fragen alle im selben Moment
    -- denselben Client, und dessen Warteschlange laeuft ueber.
    local delay = 2 + math.random() * 8
    Compat.After(delay, function()
        self.requestPending = nil
        if not comm() then return end
        local _, newest = self:Digest()
        comm():Send("WANT", { newest }, "WHISPER", peer)
        Debug:Print("comm", "Nachfrage an %s (ab %s)", tostring(peer), tostring(newest))
    end)
    return true
end

--- Startet den Takt. Laeuft, solange der Spieler eingeloggt ist.
function Sync:StartHeartbeat()
    if self.heartbeatRunning then return end
    self.heartbeatRunning = true

    local function tick()
        if not Compat.IsInGuild() then
            -- Ohne Gilde gibt es niemanden zum Abgleichen; trotzdem weiterticken,
            -- falls der Spieler spaeter einer beitritt.
            Compat.After(DIGEST_INTERVAL, tick)
            return
        end

        Sync:SendDigest("GUILD")
        Sync:PublishCharacter("GUILD")

        -- Streuung, damit nicht alle Clients zur selben Sekunde senden.
        Compat.After(DIGEST_INTERVAL + math.random() * 60, tick)
    end

    -- Beim Start etwas warten: Erst muss die Datenbank stehen und das
    -- Gildenroster geladen sein.
    Compat.After(20 + math.random() * 20, tick)
end

-- ================================================================== Anlaesse -

--- Alles Eigene einmal hinausschicken. Als Massendaten — es eilt nicht.
function Sync:PublishAll(channel)
    self:PublishCharacter(channel)
    self:PublishWishlist(channel)
    return true
end

function Sync:PeerCount()
    local count = 0
    for _ in pairs(self.peers) do count = count + 1 end
    return count
end

-- ================================================================== Start ------

function Sync:OnEnable()
    local Comm = comm()
    if not Comm then return end

    Comm:On("HELLO", function(sender, fields)
        if Comm:IsSelf(sender) then return end
        Sync.peers[sender] = { version = tonumber(fields[1]), addon = fields[2], ts = Util.Now() }
        -- Antworten, damit der andere uns auch kennt — aber nur ihm, nicht
        -- der ganzen Gruppe: Sonst antworten auf ein HELLO vierzig Clients.
        -- DIE ANTWORT TRAEGT DEN STECKBRIEF MIT.
        --
        -- Ohne ihn hatte das Anmelden eine Luecke: Beim Reload schickte der
        -- Client seinen eigenen Steckbrief hinaus, damit andere merken, dass
        -- SIE zurueckliegen — aber er erfuhr selbst erst beim naechsten
        -- fremden Takt, ob ER zurueckliegt. Das konnte zehn Minuten dauern.
        --
        -- Zwei Zahlen an die ohnehin verschickte Antwort zu haengen kostet
        -- nichts und schliesst die Luecke: Nach einem Reload weiss der Client
        -- binnen Sekunden, ob jemand mehr hat.
        local count, newest = Sync:Digest()
        Comm:Send("HERE", { Sync.VERSION, GA.version, count, newest }, "WHISPER", sender)
        GA.Core.Callbacks:Fire("SYNC_PEERS")
    end, "Sync")

    Comm:On("HERE", function(sender, fields)
        Sync.peers[sender] = { version = tonumber(fields[1]), addon = fields[2], ts = Util.Now() }

        -- Felder 3 und 4 kamen spaeter dazu. Ein aelterer Client schickt sie
        -- nicht — dann sind sie nil, und es passiert schlicht nichts. Deshalb
        -- brauchte es dafuer KEINE neue Protokollfassung: Alt und neu reden
        -- weiter miteinander, nur ohne diesen Vorteil.
        local peerCount = tonumber(fields[3])
        local peerNewest = tonumber(fields[4])
        if peerCount then
            Sync.peers[sender].awards = peerCount
            local myCount, myNewest = Sync:Digest()
            if peerIsAhead(peerCount, peerNewest or 0, myCount, myNewest) then
                Sync:RequestFrom(sender)
            end
        end

        GA.Core.Callbacks:Fire("SYNC_PEERS")
    end, "Sync")

    Comm:OnBlob("CHAR", function(sender, text) Sync:OnCharacter(sender, text) end, "Sync")
    Comm:OnBlob("WISH", function(sender, text) Sync:OnWishlist(sender, text) end, "Sync")
    Comm:OnBlob("AWARDSYNC", function(sender, text) Sync:OnAward(sender, text) end, "Sync")

    -- Eine bestaetigte Vergabe geht an die Gruppe: Ab da ist sie Historie,
    -- und die soll bei allen gleich aussehen.
    GA.Core.Callbacks:On("AWARD_CHANGED", function(awardId, _, newStatus)
        if newStatus ~= GA.Data.Schema.LootStatus.RECEIVED then return end
        Sync:PublishAward(awardId)
    end, "Sync")

    -- Beim Betreten einer Gruppe melden und das Eigene anbieten.
    GA.Core.Events:Register("GROUP_ROSTER_UPDATE", function()
        if not Compat.IsInGroup() then return end
        if Sync.groupPending then return end
        Sync.groupPending = true
        Compat.After(5, function()
            Sync.groupPending = false
            if not Compat.IsInGroup() then return end
            Sync:Hello()
            Sync:PublishAll()
        end)
    end, "Sync")

    -- Steckbrief eines anderen Clients: Habe ich weniger als er?
    Comm:On("DIGEST", function(sender, fields)
        if Comm:IsSelf(sender) then return end

        local peerCount = tonumber(fields[1]) or 0
        local peerNewest = tonumber(fields[2]) or 0
        local myCount, myNewest = Sync:Digest()

        Sync.peers[sender] = Sync.peers[sender] or {}
        Sync.peers[sender].ts = Util.Now()
        Sync.peers[sender].awards = peerCount

        if peerIsAhead(peerCount, peerNewest, myCount, myNewest) then
            Sync:RequestFrom(sender)
        end
    end, "Sync")

    -- Nachfrage: Der andere sagt, bis wann er versorgt ist.
    Comm:On("WANT", function(sender, fields)
        Sync:AnswerWant(sender, fields[1])
    end, "Sync")

    Compat.After(10, function()
        if Compat.IsInGuild() then Sync:Hello("GUILD") end
    end)

    Sync:StartHeartbeat()
end
