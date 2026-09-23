--[[----------------------------------------------------------------------------
    Armory/Tradables — seltene Gegenstaende im Beutel, die noch weitergehen.

    Kein UI. Sammelt die eigenen, verteilt sie an die Gilde und nimmt die der
    anderen entgegen.

    ===========================================================================
    WAS "TAUSCHBAR" HEISST — UND DIE FALLE DARIN
    ===========================================================================

    Selten oder besser, bindet erst beim Anlegen, und liegt im Beutel.

    Der zweite Punkt ist heikler, als er klingt: DIE BINDUNGSART GEHOERT DEM
    GEGENSTAND, NICHT DEM STUECK. GetItemInfo sagt "bindet beim Anlegen" auch
    dann, wenn genau dieses Exemplar laengst angelegt WAR und damit gebunden
    ist. Wer nur bindType liest, bietet der Gilde Sachen an, die niemand mehr
    weitergeben kann — und das faellt erst beim Handel auf, vor Publikum.

    Deshalb wird zusaetzlich gefragt, ob das Stueck schon gebunden ist. Kann
    dieser Client das nicht beantworten, wird die Liste als UNSICHER
    gekennzeichnet, statt sie fuer bare Muenze auszugeben.

    ===========================================================================
    GESENDET WIRD BEI AENDERUNG, ABER GEBUENDELT
    ===========================================================================

    Ein Raidabend erzeugt Dutzende BAG_UPDATE-Ereignisse. Bei jedem zu senden
    waere ein Sturm ueber einen Kanal, der eine Nachricht je 0,2 Sekunden
    vertraegt.

    Deshalb: Nach jeder Beutelaenderung wird neu gezaehlt, aber nur, wenn sich
    die LISTE wirklich geaendert hat, wird ein Versand angemeldet — und der
    wartet SETTLE Sekunden, in denen alles Weitere im selben Fenster landet.
    Zwanzig aufgesammelte Gegenstaende ergeben eine Nachricht, nicht zwanzig.

    ===========================================================================
    WAS HINAUSGEHT
    ===========================================================================

    Nur die Gegenstands-IDs der seltenen Beutelstuecke, die beim Anlegen
    binden. NICHT der Rest des Beutels, nicht die Anzahl der Plaetze, nicht
    was sonst darin liegt. Wer wissen will, was jemand mit sich herumtraegt,
    erfaehrt hier nur das, was er ohnehin anbieten wollte.
------------------------------------------------------------------------------]]

local _, GA = ...

local Tradables = {}
GA.Modules.Tradables = Tradables

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Ab welcher Qualitaet. 3 = selten (blau).
--- ZWEI SCHWELLEN, UND SIE BEDEUTEN VERSCHIEDENES.
---
--- MIN_AUTO   ab hier laeuft ein Fund VON ALLEIN mit, wenn
---            "Neue Funde automatisch anbieten" an ist.
--- MIN_CHOICE ab hier darf man einen Gegenstand ueberhaupt WAEHLEN.
---
--- Gruene Stuecke stehen dazwischen: anbietbar, aber nie automatisch. Ein
--- Beutel voll gruener Questbelohnungen wuerde die Liste der Gilde sonst
--- so zuschuetten, dass niemand mehr das eine blaue Teil darin findet —
--- und genau darum geht es bei dieser Liste. Wer ein gruenes Stueck
--- loswerden will, sagt es ausdruecklich.
local MIN_AUTO = 3
local MIN_CHOICE = 2

--- Sammelfenster fuer den Versand, in Sekunden.
local SETTLE = 10

--- Wie viele Eintraege hoechstens verschickt werden. Eine Obergrenze, damit
--- ein Beutel voller blauer Gegenstaende nicht die Leitung belegt.
local MAX_ITEMS = 40

--- Wie lange nach einer Anfrage dieselbe nicht noch einmal geht.
---
--- Eine Minute: lang genug, dass Ungeduld nicht zur Belaestigung wird,
--- kurz genug, dass eine wirklich vergessene Anfrage nachgeholt werden
--- kann.
local ASK_COOLDOWN = 60

local pending = false

local function store()
    local account = GA.Core.Database.account
    account.tradables = account.tradables or {}
    return account.tradables
end

-- ================================================================== Messen ---

--- Die eigenen tauschbaren Gegenstaende.
---
--- @return table items  { { itemID, count } }, nach ID sortiert
--- @return boolean sure  false = Bindungszustand nicht pruefbar
--- TESTSCHALTER. Nimmt ALLES aus dem Beutel, egal welche Qualitaet und
--- egal ob es ueberhaupt bindet.
---
--- Graue Gegenstaende binden gar nicht (bindType 0) — eine bloss gesenkte
--- Qualitaetsgrenze liesse sie deshalb NICHT durch. Zum Ausprobieren muessen
--- beide Filter fallen, und genau das tut dieser Schalter.
---
--- Er liegt bewusst NICHT in den Einstellungen: Er gehoert nicht zur
--- Bedienung, sondern zum Ausprobieren. /ga trade test schaltet ihn um, und
--- /ga trade sagt, wenn er an ist — damit ihn niemand vergisst und sich
--- wundert, warum die Gilde graue Lumpen angeboten bekommt.
Tradables.testMode = false

--- Nur die IDs, als Text — zum Vergleichen und zum Verschicken.
--- Macht aus einem Itemlink die Kennung, die uebertragen wird.
---
--- DAS IST DER ITEMSTRING, NICHT DIE ITEM-ID — und das ist der ganze Punkt.
---
--- "Nomad Tunic of the Boar" und "Nomad Tunic of the Bear" haben DIESELBE
--- Item-ID. Was sie unterscheidet, sind die +3 Staerke gegen +3 Ausdauer,
--- und die stehen im Zufallssuffix des Links. Wer nur die ID verschickt,
--- verschickt "irgendeine Nomadentunika": Der Empfaenger bekommt einen
--- Tooltip ohne Werte, ohne Haltbarkeit und mit dem falschen Namen.
---
--- Der Itemstring wird NICHT ZERLEGT, sondern unveraendert durchgereicht
--- und beim Empfaenger wieder zu "item:..." zusammengesetzt. Damit muss
--- dieser Code nicht wissen, an welcher Stelle dieser Client den Suffix
--- fuehrt — eine Frage, die sich zwischen den WoW-Versionen mehrfach anders
--- beantwortet hat. Was nicht gelesen wird, kann nicht falsch gelesen
--- werden.
local function itemKey(link)
    if type(link) ~= "string" then return nil end
    local itemString = string.match(link, "item:([%-%d:]+)")
    if not itemString then return nil end
    -- Leere Felder am Ende weg: Sie tragen nichts und kosten Platz in einer
    -- Nachricht, die auf 240 Zeichen begrenzt ist.
    itemString = string.gsub(itemString, ":+$", "")
    return itemString ~= "" and itemString or nil
end

--- Baut aus der uebertragenen Kennung wieder einen Link.
local function keyToLink(itemString)
    if type(itemString) ~= "string" or itemString == "" then return nil end
    return "item:" .. itemString
end

--- Die erste Zahl eines Itemstrings ist die Item-ID.
local function keyToID(itemString)
    if type(itemString) ~= "string" then return nil end
    return tonumber(string.match(itemString, "^(%d+)"))
end

--- Schreibt eine Gegenstandsliste fuer die Uebertragung.
local function encodeList(items, limit)
    local parts = {}
    for index, item in ipairs(items) do
        if limit and index > limit then break end
        local key = item.itemString or tostring(item.itemID)
        parts[#parts + 1] = key .. ((item.count or 1) > 1 and ("x" .. item.count) or "")
    end
    return table.concat(parts, ",")
end

--- Liest eine Gegenstandsliste zurueck.
---
--- Vertraegt beide Formen: den Itemstring und die blosse Zahl, die aeltere
--- Fassungen des Addons geschickt haben. Ein Gildenmitglied, das noch nicht
--- aktualisiert hat, verschwindet sonst wortlos aus der Liste.
local function decodeList(text)
    local items = {}
    for part in string.gmatch(text or "", "[^,]+") do
        local key, count = string.match(part, "^([%-%d:]+)x(%d+)$")
        if not key then key, count = string.match(part, "^([%-%d:]+)$"), "1" end
        local id = key and keyToID(key)
        if id then
            items[#items + 1] = {
                itemID = id,
                itemString = key,
                link = keyToLink(key),
                count = tonumber(count) or 1,
            }
        end
    end
    return items
end

function Tradables:Scan()
    local items, sure = {}, true
    local seen = {}
    local test = self.testMode

    for _, entry in ipairs(Compat.GetBagItems()) do
        local info = Compat.GetItemInfo(entry.itemID)

        if info and (test or ((tonumber(info.quality) or 0) >= MIN_CHOICE
            and info.bindType == Compat.BIND_ON_EQUIP))
        then
            -- Schon gebunden? Dann ist es keins mehr.
            --
            -- WEISS NICHT IST NICHT NEIN. Hier stand "if bound ~= true",
            -- und damit galt ein Stueck, dessen Bindung sich nicht pruefen
            -- liess, als tauschbar. Gemessen im Spiel: Ein laengst
            -- gebundenes gruenes Teil kam so in die Liste, waehrend das
            -- blaue daneben korrekt fehlte — weil es beim Aufheben bindet
            -- und schon am bindType scheitert.
            --
            -- Ein unsicheres Stueck bleibt WAEHLBAR: Du siehst im Spiel,
            -- was gebunden ist, und darfst es sagen. Es laeuft nur nicht
            -- mehr von allein mit (siehe SeedNewFinds) und traegt seine
            -- Unsicherheit bis in die Anzeige.
            local bound = Compat.ItemIsBound(entry.bag, entry.slot)
            if bound == nil then sure = false end

            if bound ~= true then
                -- GRUPPIERT WIRD NACH ITEMSTRING, NICHT NACH ID. Zwei
                -- Tuniken mit verschiedenem Zufallssuffix sind zwei
                -- Angebote, keine Stapelung von zwei gleichen.
                local key = itemKey(entry.link) or tostring(entry.itemID)
                local existing = seen[key]
                if existing then
                    existing.count = existing.count + 1
                else
                    local item = { itemID = entry.itemID, itemString = key,
                                   link = entry.link, count = 1,
                                   quality = tonumber(info.quality) or 0,
                                   -- Je Stueck, nicht nur fuer den ganzen
                                   -- Beutel: Sonst faerbt ein einziges
                                   -- unklares Teil alle anderen mit ein.
                                   bindKnown = bound ~= nil }
                    seen[key] = item
                    items[#items + 1] = item
                end
            end
        end
    end

    table.sort(items, function(a, b)
        return (a.itemString or "") < (b.itemString or "")
    end)
    return items, sure
end


local function fingerprint(items)
    -- Ueber den Itemstring, nicht die ID: Sonst gilt ein Tausch von
    -- "of the Boar" gegen "of the Bear" als keine Aenderung.
    return encodeList(items)
end

-- ================================================================== Auswahl --
--
-- ERKANNT WIRD ALLES, ANGEBOTEN NUR DAS GEWAEHLTE.
--
-- Die erste Fassung schickte jeden seltenen Fund automatisch in die Gilde.
-- Das ist bequem und falsch: Wer einen blauen Guertel fuer seinen Twink
-- aufhebt, will ihn nicht angeboten sehen — und merkt es erst, wenn jemand
-- danach fragt.
--
-- Gewaehlt wird je GEGENSTANDSART, nicht je Stueck. Wer zwei gleiche hat,
-- bietet beide an oder keins; eine Unterscheidung zwischen "dieses Exemplar
-- ja, jenes nein" waere im Beutel nicht wiederzufinden, sobald etwas
-- umsortiert wird.

local function choices()
    local account = GA.Core.Database.account
    account.tradableChoice = account.tradableChoice or {}
    return account.tradableChoice
end

--- Soll dieser Gegenstand angeboten werden?
---
--- Drei Zustaende: ausdruecklich ja, ausdruecklich nein, noch nicht
--- entschieden. Der dritte faellt auf die Einstellung zurueck — Vorgabe
--- NEIN, denn ungefragt anzubieten ist genau das, was hier vermieden wird.
--- Sagt Zeile fuer Zeile, warum ein Gegenstand angeboten werden kann — oder
--- warum nicht.
---
--- "Geht nicht" ist keine Beobachtung, mit der sich etwas anfangen laesst.
--- An jeder Bedingung, die das Anbieten verhindern kann, steht hier ihr
--- gemessener Wert. Was hier "nein" sagt, ist die Antwort.
---
--- @return table zeilen
function Tradables:Explain(itemID)
    local zeilen = {}
    local function sag(text, ...) zeilen[#zeilen + 1] = string.format(text, ...) end

    if not itemID then
        sag("Keine Item-ID erkannt.")
        return zeilen
    end

    local info = Compat.GetItemInfo(itemID)
    if not info then
        sag("GetItemInfo(%d) liefert nichts — der Client kennt das Stueck "
            .. "gerade nicht. Tooltip einmal ansehen und erneut versuchen.", itemID)
        return zeilen
    end

    local quality = tonumber(info.quality) or -1
    sag("Name:       %s", tostring(info.name))
    sag("Qualitaet:  %d  (waehlbar ab %d, automatisch ab %d)",
        quality, MIN_CHOICE, MIN_AUTO)
    sag("Bindung:    bindType=%s  (gesucht: %s = beim Anlegen)",
        tostring(info.bindType), tostring(Compat.BIND_ON_EQUIP))

    -- Liegt es ueberhaupt im Beutel, und was sagt die Bindungspruefung?
    local gefunden, gebunden
    for _, entry in ipairs(Compat.GetBagItems()) do
        if entry.itemID == itemID then
            gefunden = entry
            gebunden = Compat.ItemIsBound(entry.bag, entry.slot)
            break
        end
    end

    if not gefunden then
        sag("Im Beutel:  NEIN — nur was in deinen Taschen liegt, kann angeboten werden.")
    else
        sag("Im Beutel:  Tasche %d, Platz %d", gefunden.bag, gefunden.slot)
        sag("Gebunden:   %s   (C_Item.IsBound=%s, Beutelauskunft=%s)",
            gebunden == nil and "UNBEKANNT" or tostring(gebunden),
            tostring(Compat.IsItemBound(gefunden.bag, gefunden.slot)),
            tostring(Compat.IsItemBoundByContainer(gefunden.bag, gefunden.slot)))
    end

    sag("Testmodus:  %s", tostring(self.testMode == true))
    sag("Automatik:  %s", tostring(GA.Core.Config:Get("offerNewFinds") and true or false))
    sag("Waehlbar:   %s", tostring(self:IsCandidate(itemID)))
    sag("Angeboten:  %s", tostring(self:IsOffered(itemID)))
    sag("Alt-Klick:  %s", tostring(self.hookPath or "NICHT eingehaengt"))

    return zeilen
end

--- Traegt neue Funde einmalig ein, wenn die Automatik an ist.
---
--- DIE AUTOMATIK SAEHT, SIE UEBERSTIMMT NICHT.
---
--- Vorher war sie ein lebender Vorgabewert: Ein blaues Stueck ohne
--- Eintrag GALT als angeboten, solange das Haekchen gesetzt war. Damit
--- machte ein Alt-Klick darauf genau das Gegenteil dessen, was der Spieler
--- wollte — er nahm es weg. Bei gruenen Stuecken fuegte derselbe Klick
--- etwas hinzu, weil die Automatik sie nicht erfasst. Ein Knopf, der mal
--- so und mal so wirkt, ist kaputt, auch wenn jede einzelne Regel fuer
--- sich stimmt.
---
--- Die Einstellung heisst "Neue Funde automatisch anbieten". Genau das tut
--- sie jetzt: eintragen, einmal, beim Finden. Danach gehoert der Eintrag
--- dem Spieler.
--- @return number wie viele neu eingetragen wurden
function Tradables:SeedNewFinds()
    if not GA.Core.Config:Get("offerNewFinds") then return 0 end

    local gewaehlt = choices()
    local neu = 0
    for _, item in ipairs(self:Scan()) do
        -- NUR WAS GEPRUEFT IST, GEHT VON ALLEIN HINAUS. Ein Angebot, das
        -- niemand annehmen kann, schickt jemanden quer durch die Welt —
        -- und wer es nicht selbst angeklickt hat, weiss nicht einmal,
        -- warum sein Name daransteht.
        if gewaehlt[item.itemID] == nil and item.bindKnown
            and (item.quality or 0) >= MIN_AUTO
        then
            gewaehlt[item.itemID] = true
            neu = neu + 1
        end
    end
    return neu
end

--- Bietest du dieses Stueck an?
---
--- Eine einzige Quelle: der Eintrag. Kein Vorgabewert, der davon abweichen
--- koennte.
function Tradables:IsOffered(itemID)
    return choices()[itemID] == true
end

--- Setzt die Wahl. nil loescht sie wieder (zurueck zur Vorgabe).
function Tradables:SetOffered(itemID, on)
    if not itemID then return end
    choices()[itemID] = on
    GA.Core.Callbacks:Fire("TRADABLES_CHANGED")
    self:Refresh()
end

--- Umschalten — das, was ein Alt-Klick tut.
--- @return boolean|nil neuer Zustand, nil wenn der Gegenstand kein Kandidat ist
function Tradables:Toggle(itemID)
    if not itemID or not self:IsCandidate(itemID) then return nil end
    local on = not self:IsOffered(itemID)
    self:SetOffered(itemID, on)
    return on
end

--- Kaeme dieser Gegenstand ueberhaupt in Frage? (selten, BoE, im Beutel)
function Tradables:IsCandidate(itemID)
    for _, item in ipairs(self:Scan()) do
        if item.itemID == itemID then return true end
    end
    return false
end

--- Was tatsaechlich hinausgeht.
function Tradables:Offered()
    local out = {}
    for _, item in ipairs(self:Scan()) do
        if self:IsOffered(item.itemID) then out[#out + 1] = item end
    end
    return out
end

-- ================================================================== Ablegen --

--- Legt eine Liste ab — die eigene oder eine fremde.
function Tradables:Put(guid, name, items, sure, ts)
    if not guid then return end
    store()[guid] = {
        name = name,
        ts = ts or Util.Now(),
        -- ALS ECHTER WAHRHEITSWERT, NICHT ALS WEGGELASSENES FELD.
        --
        -- Hier stand "sure ~= false or nil", was bei false ein nil
        -- speicherte. All() liest mit "entry.sure ~= false" zurueck — und
        -- nil ~= false ist true. Eine ungepruefte Meldung kam damit als
        -- geprueft wieder heraus, und das Dashboard liess die Warnfarbe
        -- weg.
        --
        -- Ein gespartes Feld ist es nicht wert, dass "weiss nicht" zu "ja"
        -- wird.
        sure = sure ~= false,
        items = items,
    }
    GA.Core.Callbacks:Fire("TRADABLES_CHANGED", guid)
end

--- Alles, was die Gilde anzubieten hat.
---
--- Veraltetes fliegt raus: Wer seit Tagen nichts gemeldet hat, hat den
--- Gegenstand vermutlich laengst verkauft. Eine Liste, die Karteileichen
--- zeigt, schickt Leute auf die Suche nach etwas, das es nicht mehr gibt.
--- @param maxAge number|nil  Sekunden, Vorgabe drei Tage
function Tradables:All(maxAge)
    local limit = Util.Now() - (maxAge or 3 * 86400)
    local out = {}

    for guid, entry in pairs(store()) do
        if (entry.ts or 0) >= limit and entry.items and #entry.items > 0 then
            out[#out + 1] = {
                guid = guid, name = entry.name, ts = entry.ts,
                sure = entry.sure ~= false, items = entry.items,
            }
        end
    end

    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

-- ================================================================== Senden ---

--- Prueft den eigenen Beutel und meldet einen Versand an, wenn sich etwas
--- geaendert hat.
function Tradables:Refresh()
    local identity = Compat.GetPlayerIdentity()
    if not identity.guid then return end

    -- ERST SAEEN, DANN LESEN: Ein Fund, der gerade erst im Beutel gelandet
    -- ist, muss eingetragen sein, bevor gezaehlt wird, was angeboten wird.
    self:SeedNewFinds()

    local _, sure = self:Scan()
    local items = self:Offered()
    local mine = store()[identity.guid]
    local before = mine and fingerprint(mine.items or {}) or nil
    local now = fingerprint(items)

    self:Put(identity.guid, identity.name, items, sure)

    -- NUR BEI ECHTER AENDERUNG SENDEN. Ein Beutel meldet sich auch, wenn
    -- sich Kupfer bewegt hat.
    if before == now then return end

    Debug:Print("comm", "Tauschbare Gegenstaende: %d (%s)", #items,
        sure and "sicher" or "Bindung unbekannt")

    if pending then return end
    pending = true
    Compat.After(SETTLE, function()
        pending = false
        Tradables:Publish()
    end)
end

--- Fragt den Besitzer nach einem Gegenstand.
---
--- EIN KNOPF, DER EINE NACHRICHT SCHICKT, MUSS SAGEN, WAS ER SCHICKT.
--- Deshalb steht die Zeile danach im eigenen Chat — wie jedes Fluestern,
--- das man selbst tippt. Wer nicht sieht, was in seinem Namen hinausging,
--- kann es auch nicht geradestellen.
---
--- MIT DEM ITEMLINK, nicht mit dem Namen: "Nomad Tunic" gibt es an einem
--- Abend dreimal mit verschiedenen Werten. Der Link sagt, welches gemeint
--- ist, und der Empfaenger kann ihn anklicken.
---
--- @return boolean gesendet, string|nil grund
function Tradables:Ask(itemID, owner, link)
    if not owner or owner == "" then return false, "noowner" end

    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(owner) then return false, "self" end

    -- NICHT ZWEIMAL DASSELBE. Ein Knopf, der bei jedem Druecken eine
    -- weitere Zeile schickt, macht aus Ungeduld eine Belaestigung — und
    -- der Empfaenger sieht nicht, dass es dieselbe Person war.
    self.asked = self.asked or {}
    local key = Util.ShortName(owner) .. "/" .. tostring(itemID)
    local zuletzt = self.asked[key]
    if zuletzt and Compat.Now() - zuletzt < ASK_COOLDOWN then
        return false, "recent"
    end

    local info = Compat.GetItemInfo(link or itemID)
    local was = link or (info and info.link) or (info and info.name)
        or string.format(GA.L.SLASH_ITEM_FALLBACK, tostring(itemID))

    local ok = Compat.SendChatMessage(string.format(GA.L.TRADE_ASK, was),
        "WHISPER", Util.ShortName(owner))
    if not ok then return false, "chat" end

    self.asked[key] = Compat.Now()
    Debug:Info(GA.L.TRADE_ASKED, tostring(was), Util.ShortName(owner))
    return true
end

--- Schreibt die eigenen Angebote in den Gildenchat.
---
--- IN DEN GILDENCHAT ZU SCHREIBEN IST EIN AUSDRUECKLICHER BEFEHL, kein
--- Nebeneffekt. Ein Addon, das ungefragt postet, fliegt zu Recht raus.
--- Diese Funktion wird deshalb NUR von zwei Stellen gerufen, die beide ein
--- Mensch ausloest: dem Knopf im Ueberblick und /ga trade post.
---
--- @return boolean gepostet, string|nil grund
function Tradables:Announce()
    local mine = self:Offered()
    if #mine == 0 then return false, "leer" end

    local namen = {}
    for _, item in ipairs(mine) do
        -- DER EIGENE LINK ZUERST: Er traegt den Zufallssuffix. Ein aus der
        -- ID nachgeschlagener Link postet "Nomad Tunic" in den Gildenchat,
        -- und wer darauf klickt, sieht andere Werte als die, die du
        -- anbietest.
        local info = Compat.GetItemInfo(item.link or item.itemID)
        local text = item.link or (info and info.link) or (info and info.name)
            or string.format(GA.L.SLASH_ITEM_FALLBACK, item.itemID)
        namen[#namen + 1] = text .. ((item.count or 1) > 1 and (" x" .. item.count) or "")
    end

    local ok = Compat.SendChatMessage(
        string.format(GA.L.TRADE_ANNOUNCE, table.concat(namen, ", ")), "GUILD")
    if not ok then return false, "chat" end

    self.lastAnnounce = Compat.Now()
    return true
end

function Tradables:Publish(channel)
    local Comm = GA.Core.Comm
    if not Comm or not GA.has.chatInfo then return false end
    if not Compat.IsInGuild() then return false end

    local identity = Compat.GetPlayerIdentity()
    local mine = identity.guid and store()[identity.guid]
    if not mine then return false end

    local list = encodeList(mine.items, MAX_ITEMS)
    local sure = mine.sure and 1 or 0

    -- Auch eine LEERE Liste geht hinaus: Sonst bliebe der letzte Stand
    -- stehen, nachdem jemand alles verkauft hat.
    --
    -- ZWEI WEGE, WEIL ITEMSTRINGS LANG SIND. Eine Nachricht fasst 240
    -- Zeichen; bei blossen IDs reichte das fuer alle vierzig Gegenstaende,
    -- bei vollen Itemstrings nicht mehr. Kuerzen waere falsch — dann fehlen
    -- Angebote, ohne dass es jemandem auffaellt. Passt es nicht, geht es
    -- als Blob in Stuecken raus.
    if Comm:Send("TRADE", { identity.guid, sure, list }, channel or "GUILD", nil, true) then
        return true
    end

    -- Semikolon als Trenner: In einer GUID, einer Ziffer und einem
    -- Itemstring kann es nicht vorkommen.
    return Comm:SendBlob("TRADE", table.concat({ identity.guid, sure, list }, ";"),
        channel or "GUILD", nil, true) and true or false
end

--- Nimmt die Liste eines anderen entgegen.
function Tradables:OnTrade(sender, fields)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end

    local guid, sure, list = fields[1], fields[2], fields[3] or ""
    if not guid or guid == "" then return end

    self:Put(guid, sender, decodeList(list), sure == "1")
end

--- Derselbe Inhalt, nur in Stuecken angekommen.
function Tradables:OnTradeBlob(sender, text)
    local guid, sure, list = string.match(text or "", "^([^;]*);([^;]*);(.*)$")
    if not guid then return end
    -- Ueber denselben Empfaenger: Zwei Wege in der Uebertragung duerfen
    -- nicht zwei Wege in der Auswertung werden.
    self:OnTrade(sender, { guid, sure, list })
end

-- ================================================================== Klicken --

--- Haengt sich an den Modifikator-Klick im Beutel.
---
--- IM TOOLTIP SELBST KANN MAN NICHTS ANKLICKEN. Ein WoW-Tooltip ist kein
--- Fenster mit Knoepfen — er zeigt Text und verschwindet. Was geht: Der
--- Tooltip SAGT, was ein Alt-Klick tut, und der Klick landet hier.
---
--- Geprueft wird, ob es die Blizzard-Funktion ueberhaupt gibt. Fehlt sie,
--- bleibt "/ga trade add" — der Weg, der immer funktioniert.
--- @return boolean ob der Haken sitzt
--- Verarbeitet einen Alt-Klick auf einen Gegenstand.
---
--- Nimmt den LINK, nicht Beutel und Platz: Der Link ist das, was alle
--- Klickwege gemeinsam haben, und er sagt die Item-ID direkt.
local function onAltClick(link)
    if type(_G.IsAltKeyDown) ~= "function" or not IsAltKeyDown() then return end

    local parsed = link and Compat.ParseItemLink(link)
    if not parsed or not parsed.itemID then return end

    -- Toggle prueft selbst, ob das Stueck ueberhaupt in Frage kommt, und
    -- gibt nil zurueck, wenn nicht. Ein Alt-Klick auf irgendetwas anderes
    -- bleibt damit folgenlos und still.
    local on = Tradables:Toggle(parsed.itemID)
    if on == nil then return end

    Debug:Info(on and GA.L.TRADE_NOW_OFFERED or GA.L.TRADE_NO_LONGER,
        tostring((Compat.GetItemInfo(parsed.itemID) or {}).name or parsed.itemID))
end

--- Holt Beutel und Platz aus einem Beutelknopf und daraus den Link.
local function linkFromButton(button)
    if type(button) ~= "table" then return nil end

    local ok, bag = pcall(function()
        return button.GetBagID and button:GetBagID()
            or (button:GetParent() and button:GetParent():GetID())
    end)
    local ok2, slot = pcall(function() return button.GetID and button:GetID() end)
    if not ok or not ok2 or bag == nil or slot == nil then return nil end

    return Compat.GetBagItemLink and Compat.GetBagItemLink(bag, slot)
end

--- Die Klickwege, in der Reihenfolge, in der sie versucht werden.
---
--- WARUM MEHRERE: Blizzard hat den Beutelklick zwischen den Versionen
--- dreimal umgebaut. Der erste Weg hier — HandleModifiedItemClick — ist
--- der stabilste, weil ihn ALLE anderen am Ende selbst aufrufen und er den
--- Link schon fertig in der Hand hat. Die beiden anderen sind Rueckfaelle
--- fuer Clients, auf denen es ihn nicht gibt.
---
--- Welcher Weg genommen wurde, steht danach in Tradables.hookPath. Ohne das
--- laesst sich ein nicht funktionierender Alt-Klick nicht unterscheiden von
--- einem, der zwar haengt, aber nie ausgeloest wird.
local CLICK_PATHS = {
    {
        name = "HandleModifiedItemClick",
        attach = function()
            if type(_G.HandleModifiedItemClick) ~= "function" then return false end
            return pcall(_G.hooksecurefunc, "HandleModifiedItemClick", function(link)
                onAltClick(link)
            end)
        end,
    },
    {
        name = "ContainerFrameItemButton_OnModifiedClick",
        attach = function()
            if type(_G.ContainerFrameItemButton_OnModifiedClick) ~= "function" then
                return false
            end
            return pcall(_G.hooksecurefunc, "ContainerFrameItemButton_OnModifiedClick",
                function(button) onAltClick(linkFromButton(button)) end)
        end,
    },
    {
        name = "ContainerFrameItemButtonMixin",
        attach = function()
            local mixin = _G.ContainerFrameItemButtonMixin
            if type(mixin) ~= "table" or type(mixin.OnModifiedClick) ~= "function" then
                return false
            end
            -- Kein hooksecurefunc: Das greift nur bei globalen FUNKTIONEN,
            -- nicht bei Methoden in einer Tabelle. Hier wird die Methode
            -- umschlossen — der alte Aufruf bleibt der erste.
            local original = mixin.OnModifiedClick
            return pcall(function()
                mixin.OnModifiedClick = function(self, ...)
                    original(self, ...)
                    onAltClick(linkFromButton(self))
                end
            end)
        end,
    },
}

--- Haengt den Alt-Klick ein und sagt, ob es geklappt hat.
function Tradables:HookClicks()
    if self.hooked then return true end
    if type(_G.hooksecurefunc) ~= "function" then return false end

    for _, path in ipairs(CLICK_PATHS) do
        if path.attach() == true then
            self.hooked = true
            self.hookPath = path.name
            return true
        end
    end

    self.hookPath = nil
    return false
end

-- ================================================================== Start ----

function Tradables:OnEnable()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:On("TRADE", function(sender, fields) Tradables:OnTrade(sender, fields) end,
            "Tradables")
        -- Lange Listen kommen als Blob. BEIDE Wege muessen angemeldet sein,
        -- sonst verschwinden ausgerechnet die Leute mit vielen Angeboten.
        Comm:OnBlob("TRADE", function(sender, text) Tradables:OnTradeBlob(sender, text) end,
            "Tradables")
    end

    -- Der Haken kann fehlschlagen; dann bleibt der Slash-Befehl. Gemeldet
    -- wird es nur im Debugkanal — wer ihn nicht braucht, soll nicht damit
    -- behelligt werden.
    -- SICHTBAR, NICHT IM DEBUGKANAL: Der Alt-Klick ist eine zugesagte
    -- Funktion. Faellt sie aus, muss das jemand erfahren, der den Debugkanal
    -- nie einschaltet — sonst klickt er und wundert sich.
    if self:HookClicks() then
        Debug:Print("ui", "Alt-Klick haengt an %s", tostring(self.hookPath))
    else
        Debug:Warn("%s", GA.L.TRADE_HOOK_OFF)
    end

    GA.Core.Events:Register("BAG_UPDATE_DELAYED", function()
        Tradables:Refresh()
    end, "Tradables")

    -- Einmal kurz nach dem Anmelden: Der Beutel kann sich seit der letzten
    -- Sitzung geaendert haben, und BAG_UPDATE feuert dafuer nicht.
    Compat.After(12, function() Tradables:Refresh() end)
end
