--[[----------------------------------------------------------------------------
    Compatibility — SAEMTLICHE versionsabhaengigen API-Aufrufe, und nur hier.

    ============================================================================
    GEMESSENE FAKTEN (WoW: Forever Beta, Build 1.60.1 / 69913, 18.09.2026,
    sechs Probe-Laeufe auf drei Charakteren) — keine Annahmen:

      Interface-Nummer         16001
      API-Grundlage            RETAIL-Client mit Vanilla-Inhalten
                               (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
      Combat Log fuer Addons   NICHT verfuegbar (37 Kaempfe, 0 Ereignisse;
                               CombatLogGetCurrentEventInfo fehlt)
      Combat Log als DATEI     VERFUEGBAR (gemessen 22.09.2026): /combatlog und
                               LoggingCombat funktionieren, die Datei ist
                               vollstaendig — Format 22, ADVANCED_LOG_ENABLED,
                               7994 Zeilen mit UNIT_DIED und ZONE_CHANGE.
                               Das Addon kann sie nicht lesen (Addons lesen
                               keine Dateien), das Begleitprogramm schon.
                               Die beiden Zeilen hier widersprechen sich also
                               NICHT: blind im Spiel, lesbar von aussen.
      Auren                    nur C_UnitAuras; UnitAura/UnitBuff fehlen
      Addon-Nachrichten        nur C_ChatInfo; globale Fassung fehlt
      Gruppe                   GetNumGroupMembers ja, GetNumRaidMembers nein
      Spezialisierungen        GetNumSpecializations() == 1 je Klasse
                               -> Spec traegt keine Information ueber die Klasse
                                  hinaus; Rolle NICHT daraus ableiten
      Talente                  modernes Trait-System, C_Traits.GenerateImportString
                               liefert den Loadout-String (ab ~Stufe 11)
      GetAverageItemLevel      FEHLERHAFT: teilt Summe durch konstant 16 statt
                               durch belegte Plaetze (13/16, 21/16, 68/16, 82/16)
                               -> Itemlevel wird hier selbst berechnet
      GetInventoryItemLink     funktioniert, liefert Item-Links
      C_Item.GetDetailedItemLevelInfo(link)   funktioniert
      Lokalisierung            Client wechselt Sprache; Namen nie fest verdrahten
      MAX_RAID_MEMBERS         40

    ============================================================================
    DIE REGEL, DIE AUS DIESEN MESSUNGEN FOLGT:

    Der Forever-Client traegt die komplette Retail-API mit sich — inklusive
    C_Garrison, C_ArtifactUI, C_DelvesUI, die es im Spiel nicht gibt. Die
    EXISTENZ einer Funktion beweist deshalb NICHTS. Jede Faehigkeit in `GA.has`,
    die ueber blosse Existenz hinausgeht, wird am RUECKGABEWERT geprueft
    (siehe Compat.Measure). Viermal hat diese Regel einen Fehler verhindert,
    einmal zu spaet gegriffen.

    ============================================================================
    NOCH NICHT GEMESSEN (RaidBrain_Probe misst sie beim naechsten Lauf):

      Pluendermeister          GetLootMethod / GiveMasterLoot / GetMasterLootCandidate
                               Retail hat Master Loot seit BfA entfernt, Vanilla
                               hatte ihn. Fuer das LootCouncil die entscheidende
                               Frage: Nur mit Master Loot kann ein Addon zuweisen.
      Handel                   GetTradeTargetItemLink & Co. fuer die manuelle
                               Uebergabe mit Bestaetigung
      Gilde                    GetGuildRosterInfo / C_GuildInfo
      Tooltip-Hooks            TooltipDataProcessor (modern) vs HookScript
      Inspect                  NotifyInspect + INSPECT_READY

    Fuer jeden dieser Bereiche gibt es hier bereits einen Wrapper mit
    Feature-Detection. Was fehlt, liefert nil und setzt das passende `GA.has`-
    Flag — das UI bietet die Funktion dann gar nicht erst an.
------------------------------------------------------------------------------]]

local _, GA = ...

local Compat = {}
GA.Core.Compat = Compat

local has = GA.has

local function isFunction(value) return type(value) == "function" end
local function isTable(value) return type(value) == "table" end

--- Einmal angelegt statt bei jedem Aufruf: Compat.IsReadable laeuft in
--- Tooltip-Rueckrufen, also bei jeder Mausbewegung.
local function concatProbe(value) return value .. "" end
local function compareProbe(a, b) return a == b end

--- Laesst sich dieser Wert ueberhaupt lesen?
---
--- EIN "SECRET VALUE" SIEHT AUS WIE EIN STRING UND IST KEINER.
---
--- Der Retail-Client gibt manche Angaben verschleiert heraus: type() sagt
--- "string", aber jede Umwandlung wirft
---
---   attempt to perform string conversion on a secret string value
---   (execution tainted by 'GuildArmory')
---
--- Gemessen am Unit-Token eines Tooltips (20.09.2026) und an der GUID aus
--- den Tooltipdaten (21.09.2026) — string.match darauf genuegt schon.
---
--- Es gibt keine Abfrage dafuer. Der einzige belastbare Test ist, die
--- Umwandlung zu versuchen und den Fehler aufzufangen. Ein nicht lesbarer
--- Wert ist KEIN Fehler im Addon: Er heisst nur, dass es fuer diese eine
--- Einheit nichts zu holen gibt.
---
--- GEPRUEFT WERDEN ZWEI OPERATIONEN, NICHT EINE. Am 21.09.2026 kam erst
--- "attempt to perform string conversion", eine Stunde spaeter "attempt to
--- compare a secret string value" aus LOOT_READY. Eine Probe, die nur das
--- Verketten versucht, haette den zweiten Fall durchgelassen und Sicherheit
--- vorgetaeuscht.
function Compat.IsReadable(value)
    if value == nil then return false end
    if type(value) ~= "string" then return true end
    if not pcall(concatProbe, value) then return false end
    return (pcall(compareProbe, value, ""))
end

--- Sind das dieselbe GUID?
---
--- EIN VERGLEICH IST KEINE HARMLOSE OPERATION.
---
--- Gemeldet 21.09.2026 aus LOOT_READY und LOOT_OPENED: "attempt to compare a
--- secret string value". Hier stand ein schlichtes `UnitGUID("target") ==
--- guid`, und der Rueckgabewert von UnitGUID ist auf diesem Client
--- verschleiert.
---
--- FALSCH IST DIE RICHTIGE ANTWORT, wenn der Vergleich nicht geht: Die eine
--- Stelle, die das braucht, fuellt dann den Namen des Gegners nicht aus —
--- genau das, was sie ohnehin tun soll, wenn sie sich nicht sicher ist.
--- Einen Namen zu raten waere schlechter als keiner.
function Compat.SameGUID(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local ok, equal = pcall(compareProbe, a, b)
    return (ok and equal) and true or false
end

-- ================================================================== Existenz --
-- Nur, was durch Existenz allein entscheidbar ist. Der Rest in Measure().

has.groupApi       = isFunction(_G.GetNumGroupMembers)                          -- true
has.auras          = isTable(_G.C_UnitAuras) and isFunction(_G.C_UnitAuras.GetAuraDataByIndex)
has.chatInfo       = isTable(_G.C_ChatInfo) and isFunction(_G.C_ChatInfo.SendAddonMessage)
has.timer          = isTable(_G.C_Timer) and isFunction(_G.C_Timer.After)
has.classColorApi  = isTable(_G.C_ClassColor)
has.itemApi        = isTable(_G.C_Item) and isFunction(_G.C_Item.GetItemInfo)
has.itemLevelApi   = isTable(_G.C_Item) and isFunction(_G.C_Item.GetDetailedItemLevelInfo)
has.inventoryLinks = isFunction(_G.GetInventoryItemLink)
has.inspect        = isFunction(_G.NotifyInspect) and isFunction(_G.CanInspect)
has.traits         = isTable(_G.C_Traits) and isTable(_G.C_ClassTalents)
has.tooltipProcessor = isTable(_G.TooltipDataProcessor)
    and isFunction(_G.TooltipDataProcessor.AddTooltipPostCall)
has.guildRoster    = isFunction(_G.GetNumGuildMembers) and isFunction(_G.GetGuildRosterInfo)
has.combatLockdown = isFunction(_G.InCombatLockdown)

--- Loot: Existenz der Funktionen. Ob Pluendermeister im Spiel WAEHLBAR ist,
--- entscheidet erst Measure() ueber GetLootMethod — siehe Dateikopf.
has.masterLootApi  = isFunction(_G.GiveMasterLoot) and isFunction(_G.GetMasterLootCandidate)
has.lootSlots      = isFunction(_G.GetNumLootItems) and isFunction(_G.GetLootSlotLink)
has.tradeApi       = isFunction(_G.GetTradeTargetItemLink) and isFunction(_G.GetTradePlayerItemLink)

-- Gemessen 18.09.2026: existieren, aber ohne verwertbare Information (s.o.)
has.specs          = isFunction(_G.GetInspectSpecialization)
has.multipleSpecs  = false   -- wird in Measure() gesetzt

-- ================================================================== Messung ---

--- Prueft die Faehigkeiten, die sich nur am Rueckgabewert erkennen lassen.
--- Wird von Core\Events nach PLAYER_LOGIN aufgerufen — vorher liefern viele
--- Funktionen noch nichts.
function Compat.Measure()
    -- Mehr als eine Spec je Klasse? Gemessen: nein. Bleibt trotzdem eine
    -- Messung, damit ein Patch das ohne Codeaenderung umdrehen kann.
    if isFunction(_G.GetNumSpecializations) then
        local ok, count = pcall(GetNumSpecializations)
        has.multipleSpecs = ok and tonumber(count) ~= nil and tonumber(count) > 1
    end

    -- Pluendermeister: Nicht "gibt es GiveMasterLoot", sondern "ist 'master'
    -- eine Lootmethode, die der Client kennt". GetLootMethod liefert ausserhalb
    -- einer Gruppe "freeforall"; ob "master" waehlbar ist, zeigt sich erst in
    -- einer Gruppe. Bis dahin gilt die Existenz der API als Vorbehalt.
    has.lootMethodApi = isFunction(_G.GetLootMethod)
        or (isTable(_G.C_PartyInfo) and isFunction(_G.C_PartyInfo.GetLootMethod))

    -- Tooltip-Hook: modern ueber TooltipDataProcessor und Enum.TooltipDataType.
    has.tooltipEnum = isTable(_G.Enum) and isTable(_G.Enum.TooltipDataType)
        and _G.Enum.TooltipDataType.Item ~= nil

    GA.Core.Callbacks:Fire("COMPAT_MEASURED")
end

--- Kurzfassung fuer Diagnose und Einstellungen.
function Compat.Describe()
    local lines = {}
    for _, key in ipairs({
        "groupApi", "auras", "chatInfo", "timer", "itemApi", "itemLevelApi",
        "inventoryLinks", "inspect", "traits", "tooltipProcessor", "guildRoster",
        "combatLockdown", "masterLootApi", "lootSlots", "tradeApi", "lootMethodApi",
        "multipleSpecs",
    }) do
        lines[#lines + 1] = string.format("  %-18s %s", key, tostring(has[key]))
    end
    return table.concat(lines, "\n")
end

-- ================================================================== Kampf -----

--- Waehrend des Combat-Lockdowns sind geschuetzte Frames tabu. Alles, was
--- Frames anlegt oder umhaengt, prueft hier und verschiebt sonst.
function Compat.InCombat()
    if has.combatLockdown then return InCombatLockdown() and true or false end
    return false
end

-- ================================================================== Gruppe ----

function Compat.GetNumGroupMembers()
    if has.groupApi then return GetNumGroupMembers() or 0 end
    return 0
end

function Compat.IsInRaid()
    if isFunction(_G.IsInRaid) then return IsInRaid() and true or false end
    return false
end

function Compat.IsInGroup()
    if isFunction(_G.IsInGroup) then return IsInGroup() and true or false end
    return Compat.GetNumGroupMembers() > 0
end

--- "raid3" bzw. "party2" / "player" fuer Index i.
function Compat.GetGroupUnit(index)
    if Compat.IsInRaid() then return "raid" .. index end
    if index == 1 then return "player" end
    return "party" .. (index - 1)
end

-- ================================================================== Gilde -----

--- Anzahl Gildenmitglieder (gesamt, online). Loest bei Bedarf eine
--- Aktualisierung aus; die Antwort kommt asynchron ueber GUILD_ROSTER_UPDATE.
function Compat.RequestGuildRoster()
    if isTable(_G.C_GuildInfo) and isFunction(_G.C_GuildInfo.GuildRoster) then
        pcall(_G.C_GuildInfo.GuildRoster)
    elseif isFunction(_G.GuildRoster) then
        pcall(GuildRoster)
    end
end

function Compat.IsInGuild()
    if isFunction(_G.IsInGuild) then return IsInGuild() and true or false end
    return false
end

--- @return number total, number online
function Compat.GetNumGuildMembers()
    if not has.guildRoster then return 0, 0 end
    local ok, total, online = pcall(GetNumGuildMembers)
    if not ok then return 0, 0 end
    return tonumber(total) or 0, tonumber(online) or 0
end

--- Ein Gildenmitglied nach Index. Feldreihenfolge von GetGuildRosterInfo:
--- name, rankName, rankIndex, level, classDisplayName, zone, publicNote,
--- officerNote, isOnline, status, classFile, achievementPoints, achievementRank,
--- isMobile, canSoR, repStanding, guid
--- @return table|nil
function Compat.GetGuildMember(index)
    if not has.guildRoster then return nil end

    local ok, name, rankName, rankIndex, level, classDisplay, zone, publicNote,
          officerNote, isOnline, _, classFile, _, _, _, _, _, guid =
        pcall(GetGuildRosterInfo, index)

    if not ok or not name then return nil end

    return {
        name = name,
        rankName = rankName,
        rankIndex = rankIndex,
        level = level,
        className = classDisplay,
        class = classFile,
        zone = zone,
        publicNote = publicNote,
        officerNote = officerNote,
        online = isOnline and true or false,
        guid = guid,
    }
end

--- Eigener Gildenname und -rang.
--- @return string|nil guildName, string|nil rankName, number|nil rankIndex
function Compat.GetOwnGuildInfo()
    if not isFunction(_G.GetGuildInfo) then return nil end
    local ok, guildName, rankName, rankIndex = pcall(GetGuildInfo, "player")
    if not ok then return nil end
    return guildName, rankName, rankIndex
end

-- ================================================================== Items -----

--- Iteminfo ueber die moderne oder die alte Schnittstelle.
--- Beide koennen nil liefern, wenn das Item noch nicht im Cache ist — dann
--- kommt spaeter GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT.
--- @return table|nil { name, link, quality, itemLevel, requiredLevel, type,
---                     subType, stackCount, equipLoc, icon, sellPrice, classID,
---                     subclassID }
function Compat.GetItemInfo(itemLinkOrID)
    if not itemLinkOrID then return nil end

    local fn = (has.itemApi and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if not isFunction(fn) then return nil end

    local ok, name, link, quality, itemLevel, requiredLevel, itemType, itemSubType,
          stackCount, equipLoc, icon, sellPrice, classID, subclassID, bindType =
        pcall(fn, itemLinkOrID)

    if not ok or not name then return nil end

    return {
        name = name, link = link, quality = quality, itemLevel = itemLevel,
        requiredLevel = requiredLevel, type = itemType, subType = itemSubType,
        stackCount = stackCount, equipLoc = equipLoc, icon = icon,
        sellPrice = sellPrice, classID = classID, subclassID = subclassID,
        -- 0 = bindet nie, 1 = beim Aufheben, 2 = beim Anlegen, 3 = bei
        -- Benutzung, 4 = Questgegenstand.
        bindType = tonumber(bindType),
    }
end

--- Bindet dieser Gegenstand erst beim Anlegen?
Compat.BIND_ON_EQUIP = 2

--- Der Link eines einzelnen Beutelplatzes.
function Compat.GetBagItemLink(bag, slot)
    local container = _G.C_Container
    local fn = (isTable(container) and container.GetContainerItemLink)
        or _G.GetContainerItemLink
    if not isFunction(fn) then return nil end

    local ok, link = pcall(fn, bag, slot)
    return (ok and link) or nil
end

--- Ist dieser Gegenstand im Beutel bereits seelengebunden?
---
--- DIE BINDUNGSART IST EINE EIGENSCHAFT DES GEGENSTANDS, NICHT DES STUECKS.
---
--- GetItemInfo sagt "bindet beim Anlegen" — auch dann, wenn genau dieses
--- Exemplar laengst angelegt WAR und damit gebunden ist. Wer nur bindType
--- liest, bietet der Gilde Gegenstaende an, die niemand mehr weitergeben
--- kann.
---
--- @return boolean|nil  nil = laesst sich auf diesem Client nicht feststellen
function Compat.IsItemBound(bag, slot)
    if not isTable(_G.C_Item) or not isFunction(_G.C_Item.IsBound) then return nil end
    if not isTable(_G.ItemLocation) or not isFunction(_G.ItemLocation.CreateFromBagAndSlot) then
        return nil
    end

    local okLoc, location = pcall(_G.ItemLocation.CreateFromBagAndSlot, bag, slot)
    if not okLoc or not location then return nil end

    local okBound, bound = pcall(_G.C_Item.IsBound, location)
    if not okBound then return nil end
    return bound and true or false
end

--- Tatsaechliches Itemlevel eines Items (beruecksichtigt Aufwertungen).
--- Gemessen 18.09.2026: C_Item.GetDetailedItemLevelInfo(link) funktioniert.
--- @return number|nil
function Compat.GetItemLevelOf(itemLink)
    if not itemLink then return nil end

    if has.itemLevelApi then
        local ok, level = pcall(_G.C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok and tonumber(level) and tonumber(level) > 0 then return tonumber(level) end
    end

    local info = Compat.GetItemInfo(itemLink)
    if info and tonumber(info.itemLevel) and info.itemLevel > 0 then
        return info.itemLevel
    end

    return nil
end

--- Zerlegt einen Item-Link in seine Bestandteile.
--- Format: item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:level:...
--- Das Format ist seit Jahren stabil und in allen Client-Linien gleich.
--- @return table|nil { itemID, enchantID, gems = {..}, suffixID, uniqueID, raw }
function Compat.ParseItemLink(link)
    if type(link) ~= "string" then return nil end

    local itemString = string.match(link, "item:([%-%d:]+)")
    if not itemString then return nil end

    local parts = {}
    for part in string.gmatch(itemString .. ":", "([^:]*):") do
        parts[#parts + 1] = part
    end

    local function num(index)
        local value = tonumber(parts[index])
        return (value and value ~= 0) and value or nil
    end

    local gems = {}
    for index = 3, 6 do
        local gem = num(index)
        if gem then gems[#gems + 1] = gem end
    end

    return {
        itemID = num(1),
        enchantID = num(2),
        gems = gems,
        suffixID = num(7),
        uniqueID = num(8),
        raw = itemString,
    }
end

--- Liest eine Item-ID aus dem, was ein Mensch in ein Eingabefeld tut.
---
--- WARUM DAS HIER NOETIG IST: Ein Addon kann keine HTTP-Anfragen stellen — der
--- WoW-Client stellt dafuer keine Schnittstelle bereit. Wowhead zur Laufzeit zu
--- befragen ist also unmoeglich, von keinem Addon. Was geht, ist das, was
--- Wowhead-Links ohnehin mitbringen: Die Item-ID steht in der URL.
---
---   https://www.wowhead.com/item=19019/thunderfury      -> 19019
---   https://www.wowhead.com/de/classic/item=19019       -> 19019
---   |cff...|Hitem:19019:0:...|h[Donnerzorn]|h|r         -> 19019
---   item:19019:0:0                                      -> 19019
---   19019                                               -> 19019
---
--- Ein NAME wird hier ausdruecklich NICHT aufgeloest: Dafuer gibt es keinen
--- verlaesslichen Weg im Client. Den uebernimmt Database/ItemIndex mit dem,
--- was dieser Client schon gesehen hat.
--- @return number|nil itemID, string|nil art ("link" | "wowhead" | "id")
function Compat.ParseItemInput(text)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then return nil end

    -- 1. Itemlink oder Item-String. Der Doppelpunkt unterscheidet ihn
    --    eindeutig von der Wowhead-Schreibweise mit Gleichheitszeichen.
    local fromLink = string.match(text, "item:(%d+)")
    if fromLink then return tonumber(fromLink), "link" end

    -- 2. Wowhead und alles, was "item=<zahl>" schreibt. Sprach- und
    --    Spielversionspfade (/de/, /classic/, /cata/) sind egal, gesucht wird
    --    nur das Stueck, auf das es ankommt.
    local fromUrl = string.match(text, "item=(%d+)")
    if fromUrl then return tonumber(fromUrl), "wowhead" end

    -- 3. Blanke Zahl.
    local fromNumber = string.match(text, "^(%d+)$")
    if fromNumber then return tonumber(fromNumber), "id" end

    return nil
end

--- Bittet den Client, die Daten einer Item-ID nachzuladen. Ohne das liefert
--- GetItemInfo fuer eine getippte ID beim ersten Mal nichts.
--- @return boolean angefordert
function Compat.RequestItemData(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    local item = _G.C_Item
    if isTable(item) and isFunction(item.RequestLoadItemDataByID) then
        local ok = pcall(item.RequestLoadItemDataByID, itemID)
        if ok then return true end
    end

    -- Rueckfall: Ein GetItemInfo-Aufruf stoesst das Nachladen ebenfalls an.
    -- Das Ergebnis kommt dann ueber GET_ITEM_INFO_RECEIVED.
    Compat.GetItemInfo(itemID)
    return false
end

--- Ist die Iteminfo schon im Client? Nur dann liefert GetItemInfo einen Namen.
function Compat.IsItemDataCached(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    local item = _G.C_Item
    if isTable(item) and isFunction(item.IsItemDataCachedByID) then
        local ok, cached = pcall(item.IsItemDataCachedByID, itemID)
        if ok then return cached and true or false end
    end

    local info = Compat.GetItemInfo(itemID)
    return info ~= nil and info.name ~= nil
end

-- ================================================================== Ausruestung

--- Ausruestungsplaetze mit Namen. Hemd (4) und Wappenrock (19) sind dabei,
--- zaehlen aber nicht ins Itemlevel (ITEM_LEVEL_SLOTS).
Compat.EQUIPMENT_SLOTS = {
    { id = 1,  key = "HEAD",     label = "Kopf" },
    { id = 2,  key = "NECK",     label = "Hals" },
    { id = 3,  key = "SHOULDER", label = "Schultern" },
    { id = 15, key = "BACK",     label = "Ruecken" },
    { id = 5,  key = "CHEST",    label = "Brust" },
    { id = 4,  key = "SHIRT",    label = "Hemd" },
    { id = 19, key = "TABARD",   label = "Wappenrock" },
    { id = 9,  key = "WRIST",    label = "Handgelenke" },
    { id = 10, key = "HANDS",    label = "Haende" },
    { id = 6,  key = "WAIST",    label = "Taille" },
    { id = 7,  key = "LEGS",     label = "Beine" },
    { id = 8,  key = "FEET",     label = "Fuesse" },
    { id = 11, key = "FINGER1",  label = "Ring 1" },
    { id = 12, key = "FINGER2",  label = "Ring 2" },
    { id = 13, key = "TRINKET1", label = "Schmuck 1" },
    { id = 14, key = "TRINKET2", label = "Schmuck 2" },
    { id = 16, key = "MAINHAND", label = "Waffenhand" },
    { id = 17, key = "OFFHAND",  label = "Schildhand" },
    { id = 18, key = "RANGED",   label = "Distanz" },
}

--- Plaetze, die ins Itemlevel eingehen: alle ausser Hemd und Wappenrock.
local ITEM_LEVEL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

--- Item-Link eines Ausruestungsplatzes, oder nil wenn leer.
--- Fuer "player" immer; fuer andere Einheiten nur nach abgeschlossenem Inspect.
function Compat.GetEquippedLink(unit, slotID)
    if not has.inventoryLinks then return nil end
    local ok, link = pcall(GetInventoryItemLink, unit or "player", slotID)
    if not ok then return nil end
    return link
end

--- Durchschnittliches Itemlevel, SELBST berechnet.
---
--- GetAverageItemLevel ist in Forever fehlerhaft (siehe Dateikopf): Es teilt
--- die Summe durch konstant 16. Auf Stufe 11 meldete es 4.25, waehrend drei
--- gemessene Plaetze im Schnitt 8.0 hatten. Deshalb: je Platz den Link holen,
--- Itemlevel bestimmen, summieren, durch die belegten Plaetze teilen.
--- @return number|nil average, number count
function Compat.ComputeItemLevel(unit)
    unit = unit or "player"
    local sum, count = 0, 0

    for _, slot in ipairs(ITEM_LEVEL_SLOTS) do
        local link = Compat.GetEquippedLink(unit, slot)
        if link then
            local level = Compat.GetItemLevelOf(link)
            if level then
                sum = sum + level
                count = count + 1
            end
        end
    end

    if count == 0 then return nil, 0 end
    return math.floor(sum / count + 0.5), count
end

-- ================================================================== Inspect ---

--- Fordert ein Inspect an. Antwort kommt asynchron ueber INSPECT_READY(guid).
--- Reichweite ~28 Yard, nur eine offene Anfrage, Drosselung durch den Server.
--- @return boolean angefordert
function Compat.RequestInspect(unit)
    if not has.inspect then return false end
    if Compat.InCombat() then return false end

    local okCan, can = pcall(CanInspect, unit)
    if not okCan or not can then return false end

    local ok = pcall(NotifyInspect, unit)
    return ok and true or false
end

function Compat.ClearInspect()
    if isFunction(_G.ClearInspectPlayer) then pcall(ClearInspectPlayer) end
end

-- ================================================================== Spec ------

--- Spezialisierungs-ID. Eigene ueber PlayerUtil, fremde nur nach Inspect.
--- Gemessen: GetNumSpecializations() == 1 — eine Spec je Klasse. Der Wert wird
--- gespeichert, aber NICHT zur Rollenableitung benutzt.
function Compat.GetSpecializationID(unit)
    unit = unit or "player"

    if unit == "player" then
        local playerUtil = _G.PlayerUtil
        if isTable(playerUtil) and isFunction(playerUtil.GetCurrentSpecID) then
            local ok, id = pcall(playerUtil.GetCurrentSpecID)
            if ok and tonumber(id) and tonumber(id) > 0 then return tonumber(id) end
        end
    end

    if has.specs then
        local ok, id = pcall(GetInspectSpecialization, unit)
        if ok and tonumber(id) and tonumber(id) > 0 then return tonumber(id) end
    end

    return nil
end

--- Loadout eines inspizierten Charakters. C_Traits.GenerateInspectImportString
--- ist gemessen vorhanden (19.09.2026); ob es fuer Forever-Charaktere einen
--- String liefert, zeigt erst der erste Inspect.
function Compat.GetInspectLoadoutString(unit)
    if not has.traits then return nil end
    local traits = _G.C_Traits
    if not isFunction(traits.GenerateInspectImportString) then return nil end
    local ok, value = pcall(traits.GenerateInspectImportString, unit)
    if not ok or type(value) ~= "string" or value == "" then return nil end
    return value
end

--- Talent-Loadout als kanonischer Import-String (gemessen: funktioniert).
function Compat.GetTalentLoadoutString()
    if not has.traits then return nil end
    local classTalents, traits = _G.C_ClassTalents, _G.C_Traits
    if not isFunction(classTalents.GetActiveConfigID) or not isFunction(traits.GenerateImportString) then
        return nil
    end

    local ok, configID = pcall(classTalents.GetActiveConfigID)
    if not ok or not configID then return nil end

    local okString, value = pcall(traits.GenerateImportString, configID)
    if not okString or type(value) ~= "string" or value == "" then return nil end
    return value
end

-- ================================================================== Loot ------

--- Namen aus Enum.LootMethod auf die klassischen Bezeichner abgebildet.
--- Abgebildet werden NAMEN, nicht Zahlen: Die Zahlen kommen aus der Enum-Tabelle
--- des Clients selbst, damit hier nichts geraten wird.
---
--- GEMESSEN 19.09.2026 — Forever schreibt die Namen anders, als die Retail-
--- Dokumentation vermuten laesst:
---   Freeforall=0  Roundrobin=1  Masterlooter=2  Group=3  Needbeforegreed=4  Personal=5
--- Ein erster Versuch mit "MasterLoot" und "FreeForAll" traf davon nichts.
--- Deshalb wird der Name normalisiert (klein, nur Buchstaben) und beide
--- Schreibweisen stehen in der Tabelle.
local ENUM_NAME_TO_METHOD = {
    freeforall      = "freeforall",
    roundrobin      = "roundrobin",
    masterlooter    = "master",       -- Forever
    masterloot      = "master",       -- Retail-Schreibweise
    master          = "master",
    group           = "group",        -- Forever
    grouploot       = "group",
    needbeforegreed = "needbeforegreed",
    personal        = "personalloot", -- Forever
    personalloot    = "personalloot",
}

--- "MasterLoot", "Masterlooter", "MASTER_LOOT" -> "masterloot"/"masterlooter"
local function normalizeEnumName(name)
    return string.lower(string.gsub(tostring(name), "[^%a]", ""))
end

--- Zahl -> Bezeichner, einmal aus Enum.LootMethod aufgebaut.
local lootMethodByValue

local function buildLootMethodMap()
    if lootMethodByValue ~= nil then return lootMethodByValue end

    local enum = isTable(_G.Enum) and _G.Enum.LootMethod
    if not isTable(enum) then
        -- Ohne Enum wird NICHT geraten: Eine falsch geratene Zahl wuerde eine
        -- Gruppenwurf-Runde als Pluendermeister ausweisen. Dann bleibt die
        -- Methode unbekannt, und IsMasterLooter() nimmt den direkten Weg.
        lootMethodByValue = false
        return false
    end

    lootMethodByValue = {}
    local mapped = 0
    for name, value in pairs(enum) do
        local method = ENUM_NAME_TO_METHOD[normalizeEnumName(name)]
        if method and type(value) == "number" then
            lootMethodByValue[value] = method
            mapped = mapped + 1
        end
    end

    -- Wenn die Enum da ist, aber kein einziger Name passt, stimmt die Annahme
    -- ueber die Schreibweise nicht mehr. Das laut sagen, statt es zu verschlucken:
    -- genau so ist am 19.09.2026 "Masterlooter" gegen "MasterLoot" aufgefallen.
    if mapped == 0 then
        local names = {}
        for name in pairs(enum) do names[#names + 1] = tostring(name) end
        table.sort(names)
        if GA.Core.Debug then
            GA.Core.Debug:Warn("Enum.LootMethod unbekannt benannt (%s) — bitte melden.",
                table.concat(names, ", "))
        end
    end

    return lootMethodByValue
end

--- Rohwert, so wie der Client ihn liefert — fuer Diagnose und Probe.
--- @return any method, number|nil masterLooterPartyID, number|nil masterLooterRaidID
function Compat.GetRawLootMethod()
    -- Gemessen 19.09.2026: Die globale GetLootMethod FEHLT in Forever, nur
    -- C_PartyInfo.GetLootMethod existiert. Der erste Wrapper lief ins Leere
    -- und meldete "unbekannt", obwohl die Information da war.
    local fn = (isTable(_G.C_PartyInfo) and _G.C_PartyInfo.GetLootMethod) or _G.GetLootMethod
    if not isFunction(fn) then return nil end
    local ok, method, partyID, raidID = pcall(fn)
    if not ok then return nil end
    return method, partyID, raidID
end

--- Aktuelle Lootmethode als Bezeichner: "freeforall" | "roundrobin" | "master" |
--- "group" | "needbeforegreed" | "personalloot" — oder nil, wenn unbekannt.
---
--- GEMESSEN 19.09.2026 (Schlachtzug, 2 Spieler):
---   C_PartyInfo.GetLootMethod() -> 2 | 0 | 1
--- Forever liefert eine ZAHL, nicht den klassischen Text. Der erste Wrapper
--- verglich gegen "master" und lag damit immer falsch — der Pluendermeister-Pfad
--- waere nie angelaufen. Deshalb wird hier ueber Enum.LootMethod uebersetzt.
--- @return string|nil method, number|nil masterLooterPartyID, number|nil masterLooterRaidID
function Compat.GetLootMethod()
    local raw, partyID, raidID = Compat.GetRawLootMethod()
    if raw == nil then return nil end

    if type(raw) == "string" then return raw, partyID, raidID end

    if type(raw) == "number" then
        local map = buildLootMethodMap()
        if map then return map[raw], partyID, raidID end
        return nil, partyID, raidID
    end

    return nil, partyID, raidID
end

--- Ist der Spieler gerade Pluendermeister? Nur dann darf das Addon zuweisen.
---
--- Zuerst die direkte Frage: IsMasterLooter() ist in Forever vorhanden und
--- beantwortet genau das — ohne Umweg ueber Enum-Werte und Index-Vergleiche.
--- Der zweite Weg greift nur, wenn es die Funktion nicht gibt.
function Compat.IsMasterLooter()
    if isFunction(_G.IsMasterLooter) then
        local ok, value = pcall(_G.IsMasterLooter)
        if ok and type(value) == "boolean" then return value end
        if ok and value ~= nil then return value and true or false end
    end

    local method, partyID, raidID = Compat.GetLootMethod()
    if method ~= "master" then return false end

    -- Im Schlachtzug zeigt raidID auf den Pluendermeister, in der Gruppe partyID;
    -- 0 im jeweils anderen Feld heisst "trifft hier nicht zu".
    if Compat.IsInRaid() then
        if not raidID or raidID == 0 then return false end
        local unit = "raid" .. raidID
        return UnitExists(unit) and UnitIsUnit(unit, "player") or false
    end

    -- partyID 0 bedeutet in der Gruppe: der Spieler selbst.
    return partyID == 0
end

--- Weist einen Loot-Slot einem Kandidaten zu. NUR als Pluendermeister und nur
--- solange das Loot-Fenster offen ist. Geschuetzte Funktion: Aufruf muss aus
--- einem Klick heraus erfolgen (Hardware-Event), nie automatisch.
--- @return boolean angestossen
function Compat.GiveMasterLoot(slot, candidateIndex)
    if not has.masterLootApi then return false end
    if not Compat.IsMasterLooter() then return false end
    local ok = pcall(GiveMasterLoot, slot, candidateIndex)
    return ok and true or false
end

--- Kandidatenname fuer Master Loot an Index i, oder nil.
function Compat.GetMasterLootCandidate(slot, index)
    if not has.masterLootApi then return nil end
    local ok, name = pcall(GetMasterLootCandidate, slot, index)
    if not ok then return nil end
    return name
end

--- Offene Loot-Slots als Liste { slot, link, quality, quantity, name }.
--- Nur gueltig zwischen LOOT_OPENED/LOOT_READY und LOOT_CLOSED.
function Compat.GetLootSlots()
    if not has.lootSlots then return {} end

    local ok, count = pcall(GetNumLootItems)
    if not ok or not count then return {} end

    local slots = {}
    for slot = 1, count do
        local okLink, link = pcall(GetLootSlotLink, slot)
        local okInfo, _, name, quantity, _, quality = pcall(GetLootSlotInfo, slot)
        if okLink and link then
            slots[#slots + 1] = {
                slot = slot, link = link,
                name = okInfo and name or nil,
                quantity = okInfo and quantity or 1,
                quality = okInfo and quality or nil,
            }
        end
    end
    return slots
end

--- Zerlegt eine Einheiten-GUID. Format (Retail):
---   Creature-0-<server>-<instanz>-<zone>-<npcID>-<spawn>
---   Player-<server>-<id>
--- @return string|nil art ("Creature", "Player", "Vehicle", "Pet", ...)
--- @return number|nil npcID  nur bei Kreaturen
function Compat.ParseGUID(guid)
    if type(guid) ~= "string" then return nil end

    -- Schon string.match wirft, wenn der Client die GUID verschleiert
    -- herausgibt. Hier abgefangen und nicht beim Aufrufer: Dann ist JEDER
    -- Weg zur GUID geschuetzt, nicht nur der, an dem es zuerst auffiel.

    if not Compat.IsReadable(guid) then return nil end

    local kind = string.match(guid, "^(%a+)%-")
    if not kind then return nil end
    if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then
        local npcID = string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        return kind, tonumber(npcID)
    end
    return kind, nil
end

--- Woher stammt ein Loot-Slot? Das ist die EINZIGE belastbare Quelle fuer die
--- Frage "welcher Gegner hat das fallen lassen" — das Combat Log ist fuer
--- Addons in Forever nicht lesbar (gemessen: 0 Ereignisse in 37 Kaempfen).
---
--- GetLootSourceInfo liefert Paare (GUID, Anzahl); bei zusammengefasstem Loot
--- koennen es mehrere Leichen sein. Genommen wird die erste — und der Name
--- kommt NUR dann mit, wenn das Ziel wirklich diese GUID ist. Sonst bleibt er
--- leer, statt den Namen des gerade anvisierten Gegners zu erfinden.
--- @return table|nil { guid, npcID, name }
function Compat.GetLootSource(slot)
    if not isFunction(_G.GetLootSourceInfo) then return nil end

    local ok, guid = pcall(GetLootSourceInfo, slot)
    if not ok or type(guid) ~= "string" then return nil end

    local kind, npcID = Compat.ParseGUID(guid)
    local name
    -- Compat.SameGUID statt "==": Der Rueckgabewert von UnitGUID ist auf
    -- diesem Client verschleiert, und schon der Vergleich wirft.
    if isFunction(_G.UnitGUID) then
        local ok, targetGuid = pcall(_G.UnitGUID, "target")
        if ok and Compat.SameGUID(targetGuid, guid) then
            name = UnitName("target")
        end
    end

    return { guid = guid, kind = kind, npcID = npcID, name = name }
end

--- Qualitaetsschwelle der Gruppe (ab der gewuerfelt bzw. zugewiesen wird).
function Compat.GetLootThreshold()
    if not isFunction(_G.GetLootThreshold) then return nil end
    local ok, value = pcall(GetLootThreshold)
    return ok and tonumber(value) or nil
end

--- Alle Master-Loot-Kandidaten eines Slots als { index, name }.
--- Blizzard laesst Luecken in der Liste (abgemeldete Spieler), deshalb wird
--- bis MAX_RAID_MEMBERS durchgezaehlt statt bis zum ersten nil.
function Compat.GetMasterLootCandidates(slot)
    if not has.masterLootApi then return {} end

    local limit = tonumber(_G.MAX_RAID_MEMBERS) or 40
    local candidates = {}
    for index = 1, limit do
        local ok, name = pcall(GetMasterLootCandidate, slot, index)
        if ok and name then
            candidates[#candidates + 1] = { index = index, name = name }
        end
    end
    return candidates
end

-- ================================================================== Handel ----

--- Items im Handelsfenster. `side` = "player" (was ich gebe) oder "target".
--- Nur gueltig zwischen TRADE_SHOW und TRADE_CLOSED.
function Compat.GetTradeItems(side)
    if not has.tradeApi then return {} end

    local getLink = (side == "target") and _G.GetTradeTargetItemLink or _G.GetTradePlayerItemLink
    local items = {}

    -- Sieben Handelsplaetze; der siebte ist "nicht handelbar / wird nicht gehandelt".
    for index = 1, 6 do
        local ok, link = pcall(getLink, index)
        if ok and link then items[#items + 1] = { index = index, link = link } end
    end
    return items
end

--- Alles, was in den Taschen liegt.
---
--- Zwei Wege, weil C_Container die moderne Fassung ist und die globalen
--- Funktionen die aeltere. Geprueft wird ueber den TYP des Ergebnisses, nicht
--- ueber die Existenz des Namens — auf Forever existiert vieles, was nichts
--- liefert.
---
--- @return table { { bag, slot, itemID, link, count } }
function Compat.GetBagItems()
    local container = _G.C_Container
    local getLink = (isTable(container) and container.GetContainerItemLink)
        or _G.GetContainerItemLink
    local getSlots = (isTable(container) and container.GetContainerNumSlots)
        or _G.GetContainerNumSlots
    if not isFunction(getLink) or not isFunction(getSlots) then return {} end

    local items = {}
    -- 0 = Rucksack, 1..4 angelegte Taschen. Bis 5 zaehlen schadet nicht: Ein
    -- nicht vorhandener Behaelter liefert 0 Plaetze.
    for bag = 0, 5 do
        local okSlots, slots = pcall(getSlots, bag)
        if okSlots and slots and slots > 0 then
            for slot = 1, slots do
                local okLink, link = pcall(getLink, bag, slot)
                if okLink and link then
                    local parsed = Compat.ParseItemLink(link)
                    if parsed and parsed.itemID then
                        items[#items + 1] = { bag = bag, slot = slot,
                                              itemID = parsed.itemID, link = link }
                    end
                end
            end
        end
    end
    return items
end

--- Wie viel Geld hat dieser Charakter, in Kupfer?
--- @return number|nil  nil = nicht messbar
function Compat.GetMoney()
    if not isFunction(_G.GetMoney) then return nil end
    local ok, copper = pcall(GetMoney)
    if not ok or type(copper) ~= "number" then return nil end
    return copper
end

--- Groesse der vier angelegten Taschen. Der Rucksack zaehlt NICHT mit: Er
--- laesst sich nicht tauschen, und ein Erfolg ueber etwas, das jeder von
--- Anfang an hat, waere keiner.
--- @return table|nil { [1..4] = Plaetze }
function Compat.GetBagSizes()
    local container = _G.C_Container
    local getSlots = (isTable(container) and container.GetContainerNumSlots)
        or _G.GetContainerNumSlots
    if not isFunction(getSlots) then return nil end

    local sizes = {}
    for bag = 1, 4 do
        local ok, slots = pcall(getSlots, bag)
        sizes[bag] = (ok and tonumber(slots)) or 0
    end
    return sizes
end

--- Die gelernten HAUPTberufe dieses Charakters.
---
--- LEER IST HIER NICHT NULL, SONDERN "WEISS NICHT".
---
--- GetProfessions liefert Indizes ins Zauberbuch. Gibt es beide nicht
--- zurueck, kann das zweierlei heissen: Der Charakter hat keinen Beruf
--- gelernt — oder der Client fuellt die Funktion auf einem Server mit
--- Vanilla-Inhalt gar nicht. Von aussen sind die beiden Faelle nicht zu
--- unterscheiden, und "0 von 1 Berufen" waere im zweiten Fall schlicht
--- falsch. Deshalb kommt dann nil zurueck, und die Oberflaeche schreibt
--- "noch nicht messbar", bis der erste Beruf auftaucht.
---
--- Sekundaerberufe (Kochen, Erste Hilfe, Angeln) bleiben draussen: Der
--- Katalog spricht von Hauptberufen.
---
--- @return table|nil { { name, rank, maxRank } }
function Compat.GetProfessions()
    if not isFunction(_G.GetProfessions) or not isFunction(_G.GetProfessionInfo) then
        return nil
    end

    local ok, first, second = pcall(GetProfessions)
    if not ok then return nil end
    if type(first) ~= "number" and type(second) ~= "number" then return nil end

    local out = {}
    for _, index in ipairs({ first, second }) do
        if type(index) == "number" then
            local okInfo, name, _, rank, maxRank = pcall(GetProfessionInfo, index)
            if okInfo and type(name) == "string" and type(rank) == "number" then
                out[#out + 1] = { name = name, rank = rank, maxRank = tonumber(maxRank) or 0 }
            end
        end
    end
    return out
end

--- Laeuft die Aufzeichnung ins Combat Log gerade?
--- @return boolean|nil  nil = der Client kennt die Funktion nicht
function Compat.IsCombatLogging()
    if not isFunction(_G.LoggingCombat) then return nil end
    local ok, running = pcall(_G.LoggingCombat)
    if not ok then return nil end
    return running and true or false
end

--- Schaltet die Aufzeichnung ein oder aus.
---
--- GEPRUEFT AM RUECKGABEWERT, nicht am Aufruf: LoggingCombat(true) kann
--- durchlaufen und nichts tun. Zurueck kommt der Zustand NACHHER — also wird
--- er noch einmal gelesen und verglichen.
---
--- @return boolean|nil zustand danach, nil wenn es nicht geht
function Compat.SetCombatLogging(on)
    if not isFunction(_G.LoggingCombat) then return nil end
    local ok = pcall(_G.LoggingCombat, on and true or false)
    if not ok then return nil end
    return Compat.IsCombatLogging()
end

--- Wo bin ich gerade?
---
--- GetInstanceInfo liefert (name, type, difficultyID, ...). `type` ist
--- "none" ausserhalb, sonst "party", "raid", "pvp", "arena", "scenario".
--- Geprueft wird der RUECKGABEWERT, nicht die Existenz: Die Funktion gibt es
--- auf Forever, aber ob sie fuer jede Zone etwas Sinnvolles liefert, ist eine
--- andere Frage.
---
--- @return table { inside, kind, name, difficultyID }
function Compat.GetInstance()
    if not isFunction(_G.GetInstanceInfo) then
        return { inside = false, kind = nil }
    end

    local ok, name, kind, difficultyID = pcall(GetInstanceInfo)
    if not ok or type(kind) ~= "string" or kind == "none" then
        return { inside = false, kind = nil }
    end

    return {
        inside = true,
        kind = kind,
        name = (type(name) == "string" and name ~= "") and name or nil,
        difficultyID = tonumber(difficultyID),
    }
end

--- Liest eine Wurfmeldung aus einer Systemzeile.
---
--- DER WURF KOMMT VOM SERVER. CHAT_MSG_SYSTEM traegt, was der Server
--- geschickt hat — Name, Ergebnis und Spanne. Ein Addon kann das nicht
--- faelschen, und genau deshalb ist Wuerfeln ueberhaupt als Verteilweg
--- brauchbar. Es ist dieselbe Eigenschaft wie beim Absendernamen einer
--- Addon-Nachricht (Communication/Sync).
---
--- Gelesen wird ueber RANDOM_ROLL_RESULT ("%s wuerfelt %d (%d-%d)"), nicht
--- ueber einen eingebauten deutschen oder englischen Satz: Sonst haengt die
--- Erkennung an der Clientsprache.
---
--- @return string|nil name, number|nil wurf, number|nil min, number|nil max
function Compat.ParseRoll(message)
    if type(message) ~= "string" then return nil end

    local format = _G.RANDOM_ROLL_RESULT
    if type(format) ~= "string" then return nil end

    local pattern = string.gsub(format, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    pattern = string.gsub(pattern, "%%%%s", "(.-)")
    pattern = string.gsub(pattern, "%%%%d", "(%%d+)")

    local name, roll, min, max = string.match(message, "^" .. pattern .. "$")
    if not name or not roll then return nil end

    return name, tonumber(roll), tonumber(min), tonumber(max)
end

--- Name des Handelspartners, oder nil.
function Compat.GetTradePartner()
    if isFunction(_G.UnitName) then
        local ok, name = pcall(UnitName, "NPC")
        if ok and name then return name end
    end
    return nil
end

-- ================================================================== Tooltip ---

--- Haengt eine Funktion an Item-Tooltips. Modern ueber TooltipDataProcessor,
--- sonst ueber HookScript. `handler(tooltip, itemLink)` wird aufgerufen,
--- sobald ein Item angezeigt wird.
--- @return boolean eingehaengt
function Compat.HookItemTooltip(handler)
    if has.tooltipProcessor and has.tooltipEnum then
        local ok = pcall(_G.TooltipDataProcessor.AddTooltipPostCall,
            _G.Enum.TooltipDataType.Item,
            function(tooltip, data)
                if tooltip ~= _G.GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
                local link = data and data.hyperlink
                if not link and tooltip.GetItem then
                    local _, itemLink = tooltip:GetItem()
                    link = itemLink
                end
                if link then handler(tooltip, link) end
            end)
        if ok then return true end
    end

    -- Aeltere Linie: direkt an den Frame haengen.
    if isTable(_G.GameTooltip) and isFunction(_G.GameTooltip.HookScript) then
        local ok = pcall(_G.GameTooltip.HookScript, _G.GameTooltip, "OnTooltipSetItem",
            function(tooltip)
                local _, link = tooltip:GetItem()
                if link then handler(tooltip, link) end
            end)
        return ok and true or false
    end

    return false
end

-- ================================================================== Auren -----

--- Einheitlicher Aurenzugriff. Gemessen: nur C_UnitAuras existiert.
function Compat.GetAura(unit, index, filter)
    if has.auras then
        local ok, data = pcall(_G.C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if not ok or not data then return nil end
        return data
    end
    return nil
end

-- ================================================================== Comm ------

function Compat.RegisterAddonPrefix(prefix)
    if has.chatInfo then
        local ok, result = pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, prefix)
        return ok and result
    end
    return false
end

--- Schreibt in einen Chatkanal. Anders als Addon-Nachrichten ist das fuer
--- Menschen sichtbar — und in Forever moeglicherweise auch nach Discord, wenn
--- die Gilde eine Bruecke eingerichtet hat. Das ist der einzige Weg, auf dem
--- ein Addon ueberhaupt etwas nach draussen bringt: Netzwerkzugriff hat es
--- keinen (siehe Core/Export.lua).
--- @return boolean gesendet
function Compat.SendChatMessage(text, channel, target)
    if not isFunction(_G.SendChatMessage) then return false end
    if type(text) ~= "string" or text == "" then return false end

    -- Chatnachrichten sind auf 255 Zeichen begrenzt; laengere schneidet der
    -- Client ab. Lieber selbst kuerzen und es kenntlich machen.
    if #text > 250 then text = string.sub(text, 1, 247) .. "..." end

    local ok = pcall(_G.SendChatMessage, text, channel or "GUILD", nil, target)
    return ok and true or false
end

--- @return boolean gesendet  (false auch bei Drosselung — der Aufrufer wiederholt)
function Compat.SendAddonMessage(prefix, message, channel, target)
    if not has.chatInfo then return false end
    local ok, result = pcall(_G.C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
    -- Neuere Clients geben einen Enum-Status zurueck (0 = Erfolg), aeltere true.
    if not ok then return false end
    if result == true or result == 0 or result == nil then return true end
    return false
end

-- ================================================================== Zeit ------

function Compat.After(seconds, callback)
    if has.timer then return _G.C_Timer.After(seconds, callback) end

    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= seconds then
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
    return frame
end

function Compat.Now()
    if isFunction(_G.GetServerTime) then return GetServerTime() end
    return time()
end

-- ================================================================== Player -----

--- GUID, Name, Realm, Klasse des eigenen Charakters — die Identitaet, an der
--- alles haengt. GUID ist der Schluessel (ueberlebt Umbenennung und Transfer).
function Compat.GetPlayerIdentity()
    return Compat.GetUnitIdentity("player")
end

--- Dieselbe Identitaet fuer eine beliebige Einheit (Ziel, Inspect). Realm ist
--- bei Fremden vom eigenen Server leer — dann gilt der eigene Realm.
function Compat.GetUnitIdentity(unit)
    unit = unit or "player"
    if not UnitExists(unit) then return {} end

    local name, realm = UnitName(unit)
    local className, classFile = UnitClass(unit)
    local raceName, raceFile = UnitRace(unit)

    if not realm or realm == "" then
        realm = (isFunction(_G.GetRealmName) and GetRealmName()) or ""
    end

    local guildName, guildRank, guildRankIndex
    if isFunction(_G.GetGuildInfo) then
        local ok, g, r, i = pcall(GetGuildInfo, unit)
        if ok then guildName, guildRank, guildRankIndex = g, r, i end
    end

    -- KEIN VERSCHLEIERTER WERT IN DIE DATENBANK.
    --
    -- Eine GUID, die sich nicht vergleichen laesst, ist als Schluessel
    -- wertlos — und sie wuerde dort liegen bleiben und bei jedem spaeteren
    -- Vergleich werfen, weit weg von der Stelle, an der sie hereinkam. An
    -- der Grenze abgefangen ist sie ein fehlendes Feld, und das kann der
    -- Aufrufer behandeln.
    local okGuid, unitGuid = pcall(_G.UnitGUID, unit)
    if not okGuid or not Compat.IsReadable(unitGuid) then unitGuid = nil end

    return {
        guid = unitGuid,
        name = name,
        realm = realm,
        class = classFile,
        className = className,
        race = raceFile,
        raceName = raceName,
        level = UnitLevel(unit),
        guildName = guildName,
        guildRank = guildRank,
        guildRankIndex = guildRankIndex,
    }
end

--- Kann diese Einheit inspiziert werden? Spieler, nicht man selbst, in
--- Reichweite (CanInspect prueft die ~28 Yard), nicht im Kampf.
function Compat.CanInspectUnit(unit)
    if not has.inspect then return false, "api" end
    if not UnitExists(unit) then return false, "notarget" end
    if not UnitIsPlayer(unit) then return false, "notplayer" end
    if UnitIsUnit(unit, "player") then return false, "self" end
    if Compat.InCombat() then return false, "combat" end
    local ok, can = pcall(CanInspect, unit)
    if not ok or not can then return false, "range" end
    return true
end
