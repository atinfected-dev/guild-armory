--[[----------------------------------------------------------------------------
    Database/AtlasBridge — Gegenstaende aus AtlasLoot, wenn es installiert ist.

    Kein UI. Laeuft ueber die Tabellen, die AtlasLootClassic beim Laden in den
    Speicher gelegt hat, und fuettert daraus das eigene Itemverzeichnis.

    ===========================================================================
    WARUM GELESEN UND NICHT KOPIERT
    ===========================================================================

    AtlasLootClassic steht unter der GPL v2. Seine Datenbanken in dieses Addon
    zu kopieren waere erlaubt — aber dann stuende GuildArmory selbst unter der
    GPL, mit allem, was daran haengt: Quelltext offenlegen, Lizenz mitgeben,
    abgeleitete Arbeiten wieder unter GPL.

    Das ist eine Entscheidung ueber das ganze Addon, und sie soll nicht als
    Nebenwirkung einer Suchfunktion passieren.

    Deshalb wird nichts kopiert. Ist AtlasLoot installiert, liegen seine
    Tabellen ohnehin im selben Lua-Zustand; dieses Modul liest sie dort. Das
    ist Zusammenspiel zweier Addons, kein Weiterverbreiten. Ist es nicht
    installiert, faellt die Erweiterung weg und die Suche arbeitet wie vorher.

    UND: DIE NAMEN KOMMEN NICHT VON ATLASLOOT.

      Uebernommen werden nur Item-IDs und die Fundstelle (Instanz, Boss). Den
      NAMEN loest der Client selbst auf, wie ueberall sonst im Addon auch. Was
      hier entsteht, ist also kein Abzug fremder Daten, sondern eine Liste von
      Zahlen, die das Spiel selbst beantwortet.

    ===========================================================================
    WAS DABEI ZU MESSEN IST, STATT ES ANZUNEHMEN
    ===========================================================================

    Die Struktur ist die von AtlasLoot, nicht die eigene:

        ItemDB.Storage[addon][inhalt].items[boss][schwierigkeit] = {
            { platz, itemID },     -- itemID ist eine ZAHL
            { platz, "f730rep8" }, -- oder ein TEXT (Zauber, Symbol, Ueberschrift)
        }

    Texte statt Zahlen sind hier der Normalfall, nicht die Ausnahme —
    Ueberschriften und Symbole stehen in denselben Listen. Wer alles nimmt,
    was an zweiter Stelle steht, legt "INV_Box_01" als Gegenstand ab.

    Deshalb: Jede Ebene wird auf ihren TYP geprueft, bevor sie betreten wird,
    und nur Zahlen gelten als Item-ID. Die Struktur eines fremden Addons darf
    sich jederzeit aendern; dann findet dieses Modul nichts und meldet das,
    statt Unsinn einzutragen.
------------------------------------------------------------------------------]]

local _, GA = ...

local AtlasBridge = {}
GA.Modules.AtlasBridge = AtlasBridge

local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

--- Wie viele Gegenstaende je Durchgang eingelesen werden. Das Auflösen eines
--- Namens kostet den Client Arbeit; tausende auf einmal lassen das Spiel
--- haengen. Lieber ueber ein paar Sekunden verteilt.
local CHUNK = 200

--- Fundstellen: [itemID] = { content, boss }
AtlasBridge.sources = {}

AtlasBridge.harvested = false
AtlasBridge.count = 0

-- ================================================================== Pruefung --

--- Ist AtlasLoot da, und sieht es so aus, wie dieses Modul erwartet?
---
--- Geprueft wird ueber den INHALT, nicht ueber den Namen: Dass eine globale
--- Tabelle "AtlasLoot" heisst, sagt nichts darueber, ob sie eine ItemDB mit
--- Storage hat. Dieselbe Regel wie bei den Blizzard-Vorlagen.
--- @return table|nil storage, string|nil grund
function AtlasBridge:Storage()
    local atlas = _G.AtlasLoot
    if type(atlas) ~= "table" then return nil, "notinstalled" end

    local itemDB = atlas.ItemDB
    if type(itemDB) ~= "table" then return nil, "noitemdb" end

    local storage = itemDB.Storage
    if type(storage) ~= "table" then return nil, "nostorage" end
    if next(storage) == nil then return nil, "empty" end

    return storage
end

function AtlasBridge:IsAvailable()
    return self:Storage() ~= nil
end

-- ================================================================== Ernten ---

--- Sammelt alle Item-IDs mit ihrer Fundstelle ein.
---
--- Nur Lesen und Zaehlen — die Namen werden danach getaktet aufgeloest
--- (siehe Resolve). Das Einsammeln selbst ist billig: Es sind Tabellen, die
--- ohnehin im Speicher liegen.
---
--- @return number gefunden, table|nil ids
function AtlasBridge:Collect()
    local storage, reason = self:Storage()
    if not storage then return 0, nil, reason end

    local ids, found = {}, 0

    for addonName, addon in pairs(storage) do
        if type(addon) == "table" then
            for contentKey, content in pairs(addon) do
                -- __atlaslootdata und andere Verwaltungsfelder sind keine Inhalte.
                if contentKey ~= "__atlaslootdata" and type(content) == "table"
                    and type(content.items) == "table"
                then
                    local contentName = content.name or tostring(contentKey)

                    for _, boss in pairs(content.items) do
                        if type(boss) == "table" then
                            local bossName = type(boss.name) == "string" and boss.name or nil

                            for _, list in pairs(boss) do
                                -- boss.name ist ein Text, keine Liste.
                                if type(list) == "table" then
                                    for _, entry in ipairs(list) do
                                        local itemID = type(entry) == "table" and entry[2] or nil

                                        -- NUR ZAHLEN. Texte sind Ueberschriften,
                                        -- Symbole oder Zauber — siehe Dateikopf.
                                        if type(itemID) == "number" and itemID > 0
                                            and not ids[itemID]
                                        then
                                            ids[itemID] = true
                                            found = found + 1
                                            self.sources[itemID] = {
                                                content = contentName,
                                                boss = bossName,
                                                addon = addonName,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return found, ids
end

--- Traegt die eingesammelten IDs ins eigene Verzeichnis ein — getaktet.
---
--- @param onDone function|nil
--- @return boolean gestartet, string|nil grund
function AtlasBridge:Harvest(onDone)
    if self.running then return false, "running" end

    local found, ids, reason = self:Collect()
    if found == 0 then
        Debug:Print("items", "AtlasLoot: nichts gefunden (%s)", tostring(reason))
        return false, reason or "empty"
    end

    local queue = {}
    for itemID in pairs(ids) do queue[#queue + 1] = itemID end

    self.running = true
    self.count = 0
    local index = 1

    local function step()
        local last = math.min(index + CHUNK - 1, #queue)
        for position = index, last do
            local itemID = queue[position]
            -- Learn holt den Namen vom Client. Kennt er ihn noch nicht,
            -- bleibt die ID stehen und wird spaeter nachgereicht — genau wie
            -- bei Gegenstaenden aus dem eigenen Beutel.
            if GA.Modules.ItemIndex:Learn(itemID) then
                self.count = self.count + 1
            end
        end
        index = last + 1

        if index <= #queue then
            Compat.After(0.5, step)
        else
            self.running = false
            self.harvested = true
            Debug:Info(GA.L.ATLAS_DONE, #queue, self.count)
            GA.Core.Callbacks:Fire("ITEMINDEX_CHANGED")
            if onDone then onDone(#queue, self.count) end
        end
    end

    Debug:Info(GA.L.ATLAS_START, found)
    step()
    return true
end

-- ================================================================== Abfrage --

--- Wo faellt dieser Gegenstand? nil, wenn AtlasLoot ihn nicht kennt.
--- @return string|nil beschreibung
function AtlasBridge:SourceOf(itemID)
    local entry = itemID and self.sources[tonumber(itemID)]
    if not entry then return nil end

    if entry.boss and entry.boss ~= "" then
        return entry.content .. " — " .. entry.boss
    end
    return entry.content
end

function AtlasBridge:Stats()
    return {
        available = self:IsAvailable(),
        harvested = self.harvested,
        known = self.count,
        sources = (function()
            local n = 0
            for _ in pairs(self.sources) do n = n + 1 end
            return n
        end)(),
    }
end

-- ================================================================== Start ------

function AtlasBridge:OnEnable()
    -- NICHT beim Anmelden ernten. Das Aufloesen tausender Namen ist Arbeit
    -- fuer den Client, und niemand hat darum gebeten, nur weil er sich
    -- einloggt. Geerntet wird, wenn jemand sucht (Wishlist-Ansicht) oder es
    -- verlangt (/ga atlas).
    local storage, reason = self:Storage()
    Debug:Print("items", "AtlasLoot: %s",
        storage and "verfuegbar" or ("nicht verfuegbar (" .. tostring(reason) .. ")"))
end
