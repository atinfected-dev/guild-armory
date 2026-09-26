--[[----------------------------------------------------------------------------
    Util — Kleinkram, der an mehreren Stellen gebraucht wird.

    Enthaelt bewusst keine Fachlogik. Alles hier ist testbar, ohne dass irgendein
    Modul geladen sein muesste.
------------------------------------------------------------------------------]]

local _, GA = ...

local Util = {}
GA.Core.Util = Util

-- ------------------------------------------------------------ Tabellenpool ---

--- Wiederverwendete Tabellen. Verhindert, dass haeufige Operationen (Roster-Aufbau,
--- Ereignisverarbeitung) bei jedem Durchlauf den Garbage Collector beschaeftigen.
local pool = {}

function Util.NewTable()
    local count = #pool
    if count > 0 then
        local t = pool[count]
        pool[count] = nil
        return t
    end
    return {}
end

function Util.ReleaseTable(t)
    if type(t) ~= "table" then return end
    for key in pairs(t) do
        t[key] = nil
    end
    pool[#pool + 1] = t
end

--- Leert eine Tabelle, ohne sie neu anzulegen.
function Util.Wipe(t)
    if type(t) ~= "table" then return t end
    for key in pairs(t) do
        t[key] = nil
    end
    return t
end

--- Tiefe Kopie. Fuer Strategien, die dupliziert werden.
function Util.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = Util.DeepCopy(inner)
    end
    return copy
end

--- Ergaenzt fehlende Schluessel aus `defaults`, ohne vorhandene zu ueberschreiben.
--- Grundlage der Datenbank-Defaults (Core\Database).
function Util.ApplyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = Util.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

-- ------------------------------------------------------------------ Namen ----

--- Normalisiert einen Spielernamen auf "Name-Realm".
--- Der eigene Realm wird angehaengt, wenn er fehlt — sonst passen Schluessel aus
--- verschiedenen Quellen (Roster, Import, Logs) nicht zusammen.
function Util.NormalizeName(name, realm)
    if not name or name == "" then return nil end

    local baseName, baseRealm = string.match(name, "^([^%-]+)%-(.+)$")
    if baseName then
        name, realm = baseName, baseRealm
    end

    if not realm or realm == "" then
        realm = GetRealmName and GetRealmName() or ""
    end
    realm = string.gsub(realm, "%s+", "")

    if realm == "" then return name end
    return name .. "-" .. realm
end

--- Nur der Name, ohne Realm — fuer die Anzeige.
function Util.ShortName(fullName)
    if not fullName then return "" end
    return (string.match(fullName, "^([^%-]+)") or fullName)
end

--- Nur der erste Namensteil — fuer enge Stellen wie die Kartennadeln.
---
--- Namen auf diesem Realm haben zwei Teile ("Horst Hodenhagen"), und auf
--- einer Karte mit zwanzig Nadeln ist der zweite vor allem Breite: Die
--- Beschriftungen laufen ineinander, und darunter liegt eine Karte, die
--- jemand lesen will. Der volle Name steht im Tooltip.
---
--- NICHT AM BINDESTRICH, DER IST DER REALM. Erst den abschneiden, dann das
--- erste Wort nehmen — sonst liefert "Total-ClassicBetaPvE2" den ganzen
--- Namen und "Total Tumult-Realm" das Richtige, also je nach Quelle etwas
--- anderes.
function Util.FirstName(fullName)
    local kurz = Util.ShortName(fullName)
    if not kurz or kurz == "" then return kurz end
    return (string.match(kurz, "^(%S+)") or kurz)
end

--- Ist `kurz` der Anfang von `lang`, an einer Wortgrenze?
---
--- AUF DATEIEBENE, NICHT IN DER FUNKTION. Als lokale Funktion in
--- SameCharacter waere das eine neue Closure BEI JEDEM AUFRUF — und
--- SameCharacter laeuft bei jeder eingehenden Addon-Nachricht. Genau diese
--- Form, ein paar Bytes je Durchgang, hat in 0.1.9 die 18 MB gemacht.
local function faengtAnMit(lang, kurz)
    if kurz == "" or #kurz >= #lang then return false end
    return string.lower(string.sub(lang, 1, #kurz)) == string.lower(kurz)
        and string.sub(lang, #kurz + 1, #kurz + 1) == " "
end

--- Von zwei Schreibweisen DESSELBEN Charakters die vollstaendigere.
---
--- WOZU: UnitName("player") gibt auf diesem Realm nur den ersten Teil eines
--- zweiteiligen Namens her ("Total" statt "Total Tumult"). Im
--- Charakterdatensatz steht dank des Gildenrosters die ganze Schreibweise.
--- Wo beides vorliegt, soll die vollstaendige angezeigt werden — gemeldet
--- am 25.09.2026 fuer Ausruestung, Charaktere und das Dashboard.
---
--- Es wird NUR ergaenzt, nie ersetzt: Sind es zwei verschiedene Charaktere,
--- gewinnt der erste. Sonst wuerde ein fremder Name schon dadurch gewinnen,
--- dass er laenger ist.
function Util.FullestName(name, andere)
    if not name or name == "" then return andere end
    if not andere or andere == "" then return name end
    if #andere > #name and Util.SameCharacter(name, andere) then return andere end
    return name
end

--- Beschreiben zwei Namen denselben Charakter?
---
--- WARUM NICHT EINFACH ==
---
--- Auf Forever duerfen Charakternamen LEERZEICHEN enthalten ("Larrin
--- Lasereule", "Horst Hodenhagen") — gemessen am 20.09.2026, siehe
--- Communication/Comm.lua. Und die Quellen sind sich ueber den vollen Namen
--- nicht einig: Der Absendername einer Addon-Nachricht kommt vom Server und
--- traegt beide Teile, waehrend UnitName("player") auch nur den ersten
--- liefern kann.
---
--- GEMELDET 25.09.2026, nach einem Namenswechsel:
---
---     Verworfen: Total Tumult-ClassicBetaPvE2 wollte den Charakter Total
---     veroeffentlichen.
---
--- Das war der Spieler selbst. Beide Namen sind seine, und die Pruefung, die
--- Fremde abhalten soll, hat ihn abgehalten — sein Charakter kam bei
--- niemandem mehr an.
---
--- DIE REGEL: Der Realm muss gleich sein, und der kuerzere Name muss der
--- ANFANG des laengeren sein, an einer Wortgrenze. "Total" passt zu "Total
--- Tumult", "Tot" nicht.
---
--- WAS DAS KOSTET: Wer "Total Tumult" heisst, koennte sich als "Total"
--- ausgeben. Das ist der Preis dafuer, dass zwei Namensquellen desselben
--- Servers verschieden lang sind, und er ist klein gegen den Fehler, den er
--- ersetzt — eine Pruefung, die jeden zweiten Namen dieses Realms
--- faelschlich fuer eine Faelschung haelt. Wer es enger will, muss vorher
--- messen, WELCHE Quelle kuerzt; dafuer gibt es /ga probe (Sonde "names").
function Util.SameCharacter(links, rechts)
    local a = Util.NormalizeName(links)
    local b = Util.NormalizeName(rechts)
    if not a or not b then return false end
    if string.lower(a) == string.lower(b) then return true end

    -- Getrennt wird am BINDESTRICH, nie am Leerzeichen: Am Leerzeichen
    -- zerlegt man hier Personen.
    local aName, aRealm = string.match(a, "^([^%-]+)%-(.*)$")
    local bName, bRealm = string.match(b, "^([^%-]+)%-(.*)$")
    aName, aRealm = aName or a, aRealm or ""
    bName, bRealm = bName or b, bRealm or ""
    if string.lower(aRealm) ~= string.lower(bRealm) then return false end

    return faengtAnMit(aName, bName) or faengtAnMit(bName, aName)
end

-- ----------------------------------------------------------------- Farben ----

--- Rueckfall, falls RAID_CLASS_COLORS fehlt oder eine Klasse nicht kennt.
--- Die Werte sind mit den Klassenfarben der Gildenseite (isnotalone.de)
--- abgeglichen, damit Roster im Addon und Aufstellung auf der Seite gleich aussehen.
--- Kein Todesritter: WoW: Forever hat Stufengrenze 60 und neun Klassen.
local FALLBACK_CLASS_COLORS = {
    WARRIOR = { r = 0.776, g = 0.608, b = 0.427 },  -- #c69b6d
    PALADIN = { r = 0.957, g = 0.549, b = 0.729 },  -- #f48cba
    HUNTER  = { r = 0.667, g = 0.827, b = 0.447 },  -- #aad372
    ROGUE   = { r = 1.000, g = 0.957, b = 0.408 },  -- #fff468
    PRIEST  = { r = 1.000, g = 1.000, b = 1.000 },  -- #ffffff
    SHAMAN  = { r = 0.000, g = 0.439, b = 0.867 },  -- #0070dd
    MAGE    = { r = 0.247, g = 0.780, b = 0.922 },  -- #3fc7eb
    WARLOCK = { r = 0.529, g = 0.533, b = 0.933 },  -- #8788ee
    DRUID   = { r = 1.000, g = 0.486, b = 0.039 },  -- #ff7c0a
}

--- @param classFile string Klassentoken in Grossbuchstaben, z.B. "SHAMAN"
--- @return number r, number g, number b
function Util.ClassColor(classFile)
    if not classFile then return 0.7, 0.7, 0.7 end

    if GA.has.classColorApi then
        local color = C_ClassColor.GetClassColor(classFile)
        if color then return color.r, color.g, color.b end
    end

    local colors = _G.RAID_CLASS_COLORS
    local color = (colors and colors[classFile]) or FALLBACK_CLASS_COLORS[classFile]
    if color then return color.r, color.g, color.b end

    return 0.7, 0.7, 0.7
end

--- Faerbt einen Text in Klassenfarbe ein.
function Util.ColorByClass(text, classFile)
    local r, g, b = Util.ClassColor(classFile)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text or "")
end

function Util.Colorize(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text or "")
end

-- ------------------------------------------------------------------ Zeit -----

--- Sekunden als "4:37" bzw. "1:04:37".
function Util.FormatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local rest = seconds % 60

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, rest)
    end
    return string.format("%d:%02d", minutes, rest)
end

--- Serverzeit als Zahl. Rueckfall auf time(), wenn GetServerTime fehlt.
function Util.Now()
    if type(_G.GetServerTime) == "function" then return GetServerTime() end
    return time()
end

--- "vor 4 min" / "vor 2 Std." / "gerade eben"
function Util.TimeAgo(timestamp)
    if not timestamp then return "nie" end
    local delta = Util.Now() - timestamp
    if delta < 60 then return "gerade eben" end
    if delta < 3600 then return string.format("vor %d min", math.floor(delta / 60)) end
    if delta < 86400 then return string.format("vor %d Std.", math.floor(delta / 3600)) end
    return string.format("vor %d Tagen", math.floor(delta / 86400))
end

-- ------------------------------------------------------------------- IDs -----

local idCounter = 0

--- Kennung fuer Strategien, Assignment-Bloecke und Pulls.
--- Muss nur innerhalb dieser Datenbank eindeutig sein, nicht global.
function Util.NewId(prefix)
    idCounter = idCounter + 1
    return string.format("%s%d%04d", prefix or "id", Util.Now(), idCounter)
end

-- --------------------------------------------------------------- Sortieren --

--- Sortiert stabil nach mehreren Schluesseln.
--- @param keys table Liste von { field = "name", desc = false }
function Util.SortBy(list, keys)
    table.sort(list, function(a, b)
        for _, key in ipairs(keys) do
            local left, right = a[key.field], b[key.field]
            if left ~= right then
                if left == nil then return false end
                if right == nil then return true end
                if key.desc then return left > right end
                return left < right
            end
        end
        return false
    end)
    return list
end

--- Schneidet Leerraum an beiden Enden ab.
---
--- Fuer Eingabefelder: Ein Grund, der nur aus Leerzeichen besteht, ist
--- keiner — aber er ist nicht leer, und ohne diese Funktion kaeme er
--- durch jede Pruefung auf "" hindurch.
function Util.Trim(text)
    if type(text) ~= "string" then return "" end
    return (string.match(text, "^%s*(.-)%s*$")) or ""
end
