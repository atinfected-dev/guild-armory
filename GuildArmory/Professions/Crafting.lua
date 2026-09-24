--[[----------------------------------------------------------------------------
    Professions/Crafting — wer in der Gilde kann das herstellen?

    Kein UI. Liest die eigenen Rezepte, verteilt sie an die Gilde, nimmt die der
    anderen entgegen und beantwortet die eine Frage, um die es geht: Wer kann
    diesen Gegenstand machen?

    ===========================================================================
    DAS BERUFSFENSTER IST DIE EINZIGE QUELLE — UND SIE IST LAUNISCH
    ===========================================================================

    C_TradeSkillUI beschreibt nicht "meine Berufe", sondern "das Fenster, das
    gerade offen ist". Ist keines offen, liefert GetAllRecipeIDs eine LEERE
    Liste, und die sieht genauso aus wie "dieser Beruf kann nichts".

    Wer den Unterschied verschluckt, loescht beim naechsten Einloggen die
    Rezepte jedes Charakters, den er je gesehen hat. Deshalb liefert die
    Kompatibilitaetsschicht hier nil statt einer leeren Liste, und dieses
    Modul SCHREIBT NIE eine leere Rezeptliste ueber eine gefuellte.

    Es folgt daraus eine Zumutung, die man nicht wegbauen kann: Einmal je
    Beruf das Fenster oeffnen, sonst gibt es nichts zu lesen. `/ga craft`
    sagt genau das, statt so zu tun, als haette man nichts gelernt.

    ===========================================================================
    EINE DARSTELLUNG FUER SPEICHER UND LEITUNG
    ===========================================================================

    Rezepte sind Listen mit mehreren hundert Zahlen. Als Lua-Tabelle in den
    SavedVariables sind das fuer eine Gilde schnell Zehntausende Eintraege; als
    Klartext ueber eine Leitung, die 240 Zeichen je Nachricht vertraegt, sind
    es Dutzende Stuecke.

    Beides loest dieselbe Kodierung: aufsteigend sortieren, DIFFERENZEN bilden,
    zur Basis 36 schreiben. Aus 200 Rezept-IDs mit je sechs Stellen werden so
    etwa 500 Zeichen.

    Dass Speicher und Leitung dasselbe Format benutzen, ist der eigentliche
    Gewinn: Es gibt EINEN Kodierer, EINEN Dekodierer, und was ankommt, kann
    ohne Umbau abgelegt werden.

    ===========================================================================
    ZWEI ARTEN VON REZEPT
    ===========================================================================

    Die meisten ergeben einen GEGENSTAND — danach wird gesucht. Verzauberungen
    ergeben keinen; dort ist das Rezept selbst das Ergebnis. Beide Listen
    werden getrennt gefuehrt, weil sie verschieden abgefragt werden. Wer nur
    Gegenstaende sammelt, verliert die Verzauberkunst vollstaendig.
------------------------------------------------------------------------------]]

local _, GA = ...

local Crafting = {}
GA.Modules.Crafting = Crafting

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Obergrenze je Beruf. Ein Hoechstberuf hat gut 300 Rezepte; 800 laesst
--- Luft und verhindert, dass ein kaputter Client die Datenbank flutet.
local MAX_RECIPES = 800

--- Nach so vielen Tagen ohne neue Meldung fliegt ein Charakter heraus.
local STALE_DAYS = 60

--- Sammelfenster nach einem Scan, bevor gesendet wird.
local SETTLE = 8

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local pending = false

local function store()
    local account = GA.Core.Database.account
    account.crafting = account.crafting or {}
    return account.crafting
end

-- ================================================================ Kodierung --

local function toBase36(value)
    if value == 0 then return "0" end
    local out = {}
    while value > 0 do
        local rest = value % 36
        table.insert(out, 1, string.sub(DIGITS, rest + 1, rest + 1))
        value = math.floor(value / 36)
    end
    return table.concat(out)
end

local function fromBase36(text)
    if text == "" then return nil end
    local value = 0
    for index = 1, #text do
        local digit = string.find(DIGITS, string.sub(text, index, index), 1, true)
        if not digit then return nil end
        value = value * 36 + (digit - 1)
    end
    return value
end

--- Zahlenliste zu Text. Sortiert, als Differenzen, zur Basis 36.
---
--- Doppelte fallen heraus: Eine Differenz von 0 waere nicht von einem
--- Trennzeichen zu unterscheiden, und zweimal dasselbe Rezept gibt es nicht.
--- @return string
function Crafting.Encode(ids)
    local sauber = {}
    for _, id in ipairs(ids or {}) do
        id = tonumber(id)
        if id and id > 0 and id == math.floor(id) then sauber[#sauber + 1] = id end
    end
    table.sort(sauber)

    local parts, vorher = {}, 0
    for _, id in ipairs(sauber) do
        if id ~= vorher then
            parts[#parts + 1] = toBase36(id - vorher)
            vorher = id
        end
    end
    return table.concat(parts, "-")
end

--- Text zurueck zu Zahlen.
--- @return table|nil  nil = unbrauchbar; {} = ausdruecklich leer
function Crafting.Decode(text)
    if type(text) ~= "string" then return nil end
    if text == "" then return {} end

    local out, laufend = {}, 0
    for part in string.gmatch(text, "[^%-]+") do
        local delta = fromBase36(part)
        if not delta or delta == 0 then return nil end
        laufend = laufend + delta
        if laufend > 10000000 then return nil end
        out[#out + 1] = laufend
        if #out > MAX_RECIPES then return nil end
    end

    -- Ein Text, der nur aus Trennzeichen bestand, ist kein leerer Text.
    if #out == 0 then return nil end
    return out
end

-- ================================================================== Messen ---

--- Liest das offene Berufsfenster und legt das Ergebnis ab.
---
--- SAGT ES, ABER NUR WENN ES ETWAS ZU SAGEN GIBT.
---
--- Ein Scan, der nichts geaendert hat, ist keine Nachricht. Das Berufsfenster
--- meldet sich beim Oeffnen mehrfach (TRADE_SKILL_SHOW, dann die Liste),
--- also liefe sonst bei jedem Blick in die Alchimie dieselbe Zeile zweimal
--- durch den Chat — und beim naechsten Blick wieder.
---
--- Wer ausdruecklich `/ga craft scan` tippt, bekommt dagegen IMMER eine
--- Antwort: Er hat gefragt, und Schweigen waere dort keine.
---
--- @param laut boolean  auch melden, wenn sich nichts geaendert hat
--- @return number|nil lineID, string|nil grund
function Crafting:ScanOpen(laut)
    local beruf = Compat.GetOpenTradeSkill()
    if not beruf then return nil, "nowindow" end

    local rezepte = Compat.GetLearnedRecipes()
    if not rezepte then return nil, "notready" end

    local items, spells = {}, {}
    for _, entry in ipairs(rezepte) do
        if entry.item then items[#items + 1] = entry.item
        else spells[#spells + 1] = entry.recipe end
    end

    local identity = Compat.GetPlayerIdentity()
    if not identity or not identity.name then return nil, "noname" end

    local _, geaendert = self:Remember(identity.name, beruf.line, {
        name = beruf.name,
        rank = beruf.rank,
        maxRank = beruf.maxRank,
        items = Crafting.Encode(items),
        spells = Crafting.Encode(spells),
    })

    local wie = tostring(beruf.name or beruf.line)
    if geaendert then
        Debug:Info(GA.L.CRAFT_SCAN_LINE, wie, #items + #spells, beruf.rank or 0)
        self:ScheduleSend()
    elseif laut then
        Debug:Info(GA.L.CRAFT_SCAN_SAME, wie, #items + #spells)
    end

    Debug:Print("craft", "%s: %d Gegenstaende, %d ohne Gegenstand, geaendert %s",
        wie, #items, #spells, tostring(geaendert))

    return beruf.line
end

--- Legt einen Beruf ab — den eigenen oder einen fremden.
---
--- DER SCHLUESSEL IST DER NAME, NICHT DIE GUID.
---
--- Eine GUID aus einer Nachricht ist eine Behauptung: Der Absendername
--- kommt vom Server und ist nicht faelschbar, alles andere im Text hat der
--- Absender selbst geschrieben. Wer nach mitgeschickter GUID ablegt, laesst
--- jedes Gildenmitglied Rezepte unter fremdem Namen eintragen — und
--- widerspricht damit der Zusage, dass ein Client nur den Charakter
--- veroeffentlicht, als der er eingeloggt ist.
---
--- Der Preis ist eine Umbenennung oder ein Transfer: Dann steht der alte
--- Name noch da, bis er nach STALE_DAYS herausfaellt. Das ist der guenstigere
--- der beiden Fehler.
function Crafting:Remember(name, lineID, data)
    if not name or name == "" or not lineID then return false end
    name = Util.ShortName(name)

    local db = store()
    db[name] = db[name] or { lines = {} }
    local eintrag = db[name]
    eintrag.name = name
    eintrag.ts = Util.Now()
    eintrag.lines = eintrag.lines or {}

    -- NIE EINE LEERE LISTE UEBER EINE GEFUELLTE. Ein Fenster, das noch nicht
    -- geantwortet hat, sieht genauso aus wie ein Beruf ohne Rezepte.
    local alt = eintrag.lines[lineID]
    if alt and (data.items or "") == "" and (data.spells or "") == ""
        and ((alt.items or "") ~= "" or (alt.spells or "") ~= "") then
        Debug:Print("craft", "Leerer Scan fuer %s verworfen — alter Stand bleibt.",
            tostring(lineID))
        return false
    end

    -- WAS SICH GEAENDERT HAT, ENTSCHEIDET SICH AM INHALT, nicht am
    -- Zeitstempel. Sonst gaelte jeder Blick ins Berufsfenster als Aenderung,
    -- und die Meldung darueber waere so wertlos wie ein "no changes".
    local neu = {
        name = data.name,
        rank = tonumber(data.rank) or 0,
        maxRank = tonumber(data.maxRank) or 0,
        items = data.items or "",
        spells = data.spells or "",
        ts = Util.Now(),
    }

    local geaendert = not alt
        or alt.items ~= neu.items
        or alt.spells ~= neu.spells
        or alt.rank ~= neu.rank

    eintrag.lines[lineID] = neu

    -- Nur bei echter Aenderung neu rechnen und die Oberflaeche wecken. Ein
    -- Verzeichnis, das bei jedem Fensteroeffnen neu faellt, kostet bei
    -- vierzig Charakteren spuerbar Zeit fuer nichts.
    if geaendert then
        self.dirty = true
        GA.Core.Callbacks:Fire("CRAFTING_CHANGED", name)
    end
    return true, geaendert
end

-- ============================================================== Nachschlagen -

--- Baut das Verzeichnis Gegenstand -> wer kann es.
---
--- GERECHNET, NICHT GESPEICHERT. Das Verzeichnis ist immer genau so aktuell
--- wie die Rezeptlisten, aus denen es faellt — es kann ihnen nicht
--- widersprechen, weil es nichts als sie ist.
function Crafting:Index()
    if self.byItem and not self.dirty then return self.byItem end

    local byItem, bySpell = {}, {}
    for name, eintrag in pairs(store()) do
        for lineID, line in pairs(eintrag.lines or {}) do
            local items = Crafting.Decode(line.items)
            for _, itemID in ipairs(items or {}) do
                byItem[itemID] = byItem[itemID] or {}
                byItem[itemID][#byItem[itemID] + 1] = { who = name, line = lineID }
            end
            local spells = Crafting.Decode(line.spells)
            for _, spellID in ipairs(spells or {}) do
                bySpell[spellID] = bySpell[spellID] or {}
                bySpell[spellID][#bySpell[spellID] + 1] = { who = name, line = lineID }
            end
        end
    end

    self.byItem, self.bySpell, self.dirty = byItem, bySpell, false
    return byItem
end

--- Wer kann diesen Gegenstand herstellen?
--- @return table { { name, line, lineName, rank, ts } }
function Crafting:Crafters(itemID)
    itemID = tonumber(itemID)
    if not itemID then return {} end

    local treffer = self:Index()[itemID]
    if not treffer then return {} end

    local db, out = store(), {}
    for _, hit in ipairs(treffer) do
        local eintrag = db[hit.who]
        local line = eintrag and eintrag.lines and eintrag.lines[hit.line]
        if eintrag and line then
            out[#out + 1] = {
                name = eintrag.name or hit.who or GA.L.UNKNOWN,
                line = hit.line,
                lineName = line.name,
                rank = line.rank,
                ts = line.ts,
            }
        end
    end

    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

--- Alle bekannten Berufe, mit ihren Traegern.
--- @return table { { line, name, crafters = { { name, rank, recipes } } } }
function Crafting:Professions()
    local db, nachLinie = store(), {}

    for who, eintrag in pairs(db) do
        for lineID, line in pairs(eintrag.lines or {}) do
            nachLinie[lineID] = nachLinie[lineID] or { line = lineID, name = line.name, crafters = {} }
            -- Der zuletzt gesehene Name gewinnt: Er ist in der Sprache
            -- dessen, der zuletzt gescannt hat, aber immer ein echter.
            nachLinie[lineID].name = nachLinie[lineID].name or line.name

            local items = Crafting.Decode(line.items) or {}
            local spells = Crafting.Decode(line.spells) or {}
            table.insert(nachLinie[lineID].crafters, {
                name = eintrag.name or who or GA.L.UNKNOWN,
                rank = line.rank,
                maxRank = line.maxRank,
                recipes = #items + #spells,
                ts = line.ts,
            })
        end
    end

    local out = {}
    for _, eintrag in pairs(nachLinie) do
        table.sort(eintrag.crafters, function(a, b)
            if a.rank ~= b.rank then return a.rank > b.rank end
            return (a.name or "") < (b.name or "")
        end)
        out[#out + 1] = eintrag
    end
    table.sort(out, function(a, b)
        return tostring(a.name or a.line) < tostring(b.name or b.line)
    end)
    return out
end

--- Was dieser Charakter kann.
function Crafting:LinesOf(name)
    local eintrag = name and store()[Util.ShortName(name)]
    if not eintrag then return {} end

    local out = {}
    for lineID, line in pairs(eintrag.lines or {}) do
        local items = Crafting.Decode(line.items) or {}
        local spells = Crafting.Decode(line.spells) or {}
        out[#out + 1] = {
            line = lineID, name = line.name, rank = line.rank, maxRank = line.maxRank,
            items = items, spells = spells, ts = line.ts,
        }
    end
    table.sort(out, function(a, b) return tostring(a.name or a.line) < tostring(b.name or b.line) end)
    return out
end

--- Zahlen fuer `/ga craft` und die Einstellungen.
function Crafting:Stats()
    local charaktere, berufe, rezepte = 0, 0, 0
    for _, eintrag in pairs(store()) do
        charaktere = charaktere + 1
        for _, line in pairs(eintrag.lines or {}) do
            berufe = berufe + 1
            rezepte = rezepte + #(Crafting.Decode(line.items) or {})
                + #(Crafting.Decode(line.spells) or {})
        end
    end
    return charaktere, berufe, rezepte
end

--- Vergisst, was zu lange her ist.
function Crafting:Prune()
    local grenze = Util.Now() - (STALE_DAYS * 86400)
    local weg = 0
    for name, eintrag in pairs(store()) do
        if (eintrag.ts or 0) < grenze then
            store()[name] = nil
            weg = weg + 1
        end
    end
    if weg > 0 then self.dirty = true end
    return weg
end

-- ================================================================= Fragen ----

--- Wie lange nach einer Anfrage dieselbe nicht noch einmal geht.
--- Eine Minute, wie bei den tauschbaren Gegenstaenden: lang genug, dass
--- Ungeduld nicht zur Belaestigung wird.
local ASK_COOLDOWN = 60

--- Fluestert jemandem die Bitte, etwas herzustellen.
---
--- MIT DEM ITEMLINK, nicht mit dem Namen: Der Empfaenger kann ihn anklicken
--- und sieht sofort, was gemeint ist — und welche Materialien fehlen.
--- @return boolean, string|nil grund
function Crafting:Ask(itemID, name)
    itemID = tonumber(itemID)
    if not itemID then return false, "noitem" end
    if not name or name == "" then return false, "noname" end

    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(name) then return false, "self" end

    self.asked = self.asked or {}
    local key = Util.ShortName(name) .. "/" .. itemID
    local zuletzt = self.asked[key]
    if zuletzt and Compat.Now() - zuletzt < ASK_COOLDOWN then
        return false, "recent"
    end

    local info = Compat.GetItemInfo(itemID)
    local was = (info and info.link) or (info and info.name)
        or string.format(GA.L.SLASH_ITEM_FALLBACK, tostring(itemID))

    if not Compat.SendChatMessage(string.format(GA.L.CRAFT_ASK, was),
        "WHISPER", Util.ShortName(name)) then
        return false, "chat"
    end

    self.asked[key] = Compat.Now()
    Debug:Info(GA.L.CRAFT_ASKED, tostring(was), Util.ShortName(name))
    return true
end

-- ============================================================== Uebertragung -

--- Trennzeichen duerfen in einem Namen nicht vorkommen.
local function safeName(text)
    if type(text) ~= "string" then return "" end
    return (string.gsub(text, "[:;~]", " "))
end

--- Der eigene Stand als Text.
--- @return string|nil
--- WEDER NAME NOCH KENNUNG STEHEN DARIN.
---
--- Wer geredet hat, sagt der Server — Comm reicht den Absender durch, und
--- der ist nicht faelschbar. Ein mitgeschickter Name waere eine zweite,
--- schwaechere Quelle fuer dieselbe Angabe, und bei Widerspruch muesste man
--- sich entscheiden. Also gar nicht erst mitschicken.
function Crafting:Payload()
    local identity = Compat.GetPlayerIdentity()
    if not identity or not identity.name then return nil end

    local eintrag = store()[Util.ShortName(identity.name)]
    if not eintrag or not eintrag.lines then return nil end

    local teile = {}
    for lineID, line in pairs(eintrag.lines) do
        teile[#teile + 1] = table.concat({
            lineID, line.rank or 0, line.maxRank or 0,
            safeName(line.name), line.items or "", line.spells or "",
        }, ":")
    end
    if #teile == 0 then return nil end

    return table.concat(teile, "~")
end

function Crafting:Publish(channel)
    local Comm = GA.Core.Comm
    if not Comm or not GA.has.chatInfo then return false, "noapi" end
    if not Compat.IsInGuild() then return false, "noguild" end

    local payload = self:Payload()
    if not payload then return false, "nothing" end

    -- Immer als Blob: Ein einziger Beruf sprengt die 240 Zeichen schon.
    return Comm:SendBlob("CRAFT", payload, channel or "GUILD", nil, true) and true or false
end

function Crafting:ScheduleSend()
    if pending then return end
    pending = true
    Compat.After(SETTLE, function()
        pending = false
        Crafting:Publish()
    end)
end

--- Der Stand eines anderen.
function Crafting:OnCraft(sender, text)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    if type(text) ~= "string" then return end

    -- DER ABSENDER DARF NUR UEBER SICH SELBST REDEN.
    --
    -- Unter welchem Namen abgelegt wird, entscheidet allein der Absender aus
    -- der Nachrichtenschicht — der kommt vom Server. Frueher stand am Anfang
    -- des Textes eine GUID, und danach wurde abgelegt: Damit konnte jedes
    -- Gildenmitglied Rezepte unter fremdem Namen eintragen.
    local kurz = Util.ShortName(sender)
    if not kurz or kurz == "" then return end

    local gelesen = 0
    for teil in string.gmatch(text, "[^~]+") do
        local lineID, rank, maxRank, lineName, items, spells =
            string.match(teil, "^(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*)$")
        lineID, rank, maxRank = tonumber(lineID), tonumber(rank), tonumber(maxRank)

        if lineID and rank and maxRank and rank <= 1000 and maxRank <= 1000 then
            -- Beide Listen muessen lesbar sein. Eine kaputte Haelfte
            -- stillschweigend als leer abzulegen waere schlimmer als sie
            -- zu verwerfen: Der Beruf saehe dann aus wie einer ohne Rezepte.
            local itemsOk = items == "" or Crafting.Decode(items) ~= nil
            local spellsOk = spells == "" or Crafting.Decode(spells) ~= nil
            if itemsOk and spellsOk then
                self:Remember(kurz, lineID, {
                    name = lineName ~= "" and lineName or nil,
                    rank = rank, maxRank = maxRank,
                    items = items, spells = spells,
                })
                gelesen = gelesen + 1
            end
        end
    end

    Debug:Print("craft", "%s: %d Beruf(e) uebernommen", tostring(kurz), gelesen)
end

--- Jemand fragt nach dem Stand der Gilde.
function Crafting:OnRequest(sender)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    -- Gestreut, damit nicht die halbe Gilde im selben Augenblick sendet.
    Compat.After(2 + math.random() * 8, function() Crafting:Publish() end)
end

function Crafting:Request()
    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end
    return Comm:Send("CREQC", {}, "GUILD", nil, true) and true or false
end

-- ================================================================== Start ----

function Crafting:OnEnable()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:OnBlob("CRAFT", function(sender, text) Crafting:OnCraft(sender, text) end,
            "Crafting")
        Comm:On("CREQC", function(sender) Crafting:OnRequest(sender) end, "Crafting")
    end

    self:Prune()

    -- Das Berufsfenster meldet sich selbst, wenn es bereit ist. Beide
    -- Ereignisse: Das erste kommt beim Oeffnen, das zweite, wenn der Server
    -- die Liste nachgeliefert hat — und erst dann steht etwas darin.
    local function scan()
        local line, grund = Crafting:ScanOpen()
        if not line and grund ~= "notready" and grund ~= "nowindow" then
            Debug:Print("craft", "Scan fehlgeschlagen: %s", tostring(grund))
        end
    end
    GA.Core.Events:Register("TRADE_SKILL_SHOW", scan, "Crafting")
    GA.Core.Events:Register("TRADE_SKILL_LIST_UPDATE", scan, "Crafting")
    GA.Core.Events:Register("TRADE_SKILL_DATA_SOURCE_CHANGED", scan, "Crafting")

    -- Einmal nach dem Anmelden fragen, was die anderen koennen.
    Compat.After(25, function() Crafting:Request() end)
end
