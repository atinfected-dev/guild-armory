--[[----------------------------------------------------------------------------
    Armory/Talents — die Talente der Mitglieder, gelesen, verteilt, entschluesselt.
    Kein UI. Gebaut 03.10.2026 auf Wunsch: "Talente der Spieler an der Puppe".

    ZWEI TEILE, ZWEI WEGE:

      1. DIE WAHL eines Spielers ist der Import-String des Spiels
         (character.loadout). Den erfasst Armory/Equipment fuer den eigenen
         Charakter und Armory/Inspect fuer Fremde; Communication/Sync schickt
         den eigenen mit dem Charakter an die Gilde.

      2. DER BAUM einer Klasse — welche Knoten es gibt, wo sie liegen, welche
         Zauber sie tragen. Den kennt nur ein Client dieser Klasse. Jeder
         Client liest seinen eigenen Baum (Compat.ReadOwnTalentTree), legt ihn
         unter seiner Spezialisierung ab und schickt ihn einmal je Sitzung als
         Blob TLAY. Wer ihn empfaengt, legt ihn ab — kontoweit, eine Fassung je
         Spezialisierung.

      Zusammen ergeben beide den nachgebauten Baum: Talents:BuildOf(character).

    DER STRING-AUFBAU (Blizzards Exportformat, Fassung 1 und 2):
      Base64, Bits von unten nach oben je Zeichen. Kopf: Fassung (8 Bit),
      Spezialisierung (16), Baum-Pruefsumme (128). Dann je Knoten in der
      Reihenfolge des Baums: gewaehlt (1); in Fassung 2 gekauft (1) — nicht
      gekauft heisst vom Spiel geschenkt; teilweise (1) und Raenge (6);
      Auswahlknoten (1) und Wahl (2, ab 0).

      Ob das auf diesem Client stimmt, misst der eigene Client: Er kennt
      seinen String UND seine echten Raenge. Talents:CaptureOwn vergleicht
      beides und legt das Ergebnis unter measured.talentDecoder ab.

    WARUM NICHT BLIZZARDS TALENTFENSTER:
      Ein Addon, das das Talentfenster des Spiels oeffnet, hinterlaesst dort
      fremden Code im Ablauf. Dann kann spaeter das Speichern eigener Talente
      mit "Interface action failed because of an AddOn" scheitern. Das
      nachgebaute Fenster liest nur und beruehrt das Spiel nicht.
------------------------------------------------------------------------------]]

local _, GA = ...

local Talents = {}
GA.Modules.Talents = Talents

local Util = GA.Core.Util
local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

Talents.LAYOUT_VERSION = 1

local function account() return GA.Core.Database.account end
local function layouts()
    local db = account()
    db.talentLayouts = db.talentLayouts or {}
    return db.talentLayouts
end
local function comm() return GA.Core.Comm end

-- ================================================================ String ----

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR_VALUE = {}
for i = 1, #ALPHABET do CHAR_VALUE[string.sub(ALPHABET, i, i)] = i - 1 end

--- Ein Lesestrom ueber den Import-String: Bits von unten nach oben.
local function stream(text)
    local values = {}
    for i = 1, #text do
        local v = CHAR_VALUE[string.sub(text, i, i)]
        if v == nil then
            if string.sub(text, i, i) == "=" then break end
            return nil
        end
        values[#values + 1] = v
    end
    local index, used = 1, 0
    local self = {}
    function self.read(width)
        local value, factor = 0, 1
        for _ = 1, width do
            local current = values[index]
            if current == nil then return nil end
            local bit = math.floor(current / 2 ^ used) % 2
            value = value + bit * factor
            factor = factor * 2
            used = used + 1
            if used == 6 then index, used = index + 1, 0 end
        end
        return value
    end
    return self
end

--- Fassung und Spezialisierung aus dem Kopf.
--- @return number|nil version, number|nil specID
function Talents.Header(text)
    if type(text) ~= "string" or text == "" then return nil end
    local s = stream(text)
    if not s then return nil end
    return s.read(8), s.read(16)
end

--- Liest die Wahl aus einem String mit dem Baum der Klasse.
--- @return table|nil { [nodeID] = { rank, chosen, granted } }, string|nil grund
function Talents.Decode(text, layout)
    if type(text) ~= "string" or text == "" then return nil, "nostring" end
    if not layout or not layout.nodes then return nil, "nolayout" end
    local s = stream(text)
    if not s then return nil, "badchars" end
    local version, specID = s.read(8), s.read(16)
    if version ~= 1 and version ~= 2 then return nil, "version" end
    if layout.specID and specID and specID ~= layout.specID then return nil, "spec" end
    for _ = 1, 16 do if s.read(8) == nil then return nil, "short" end end

    local out = {}
    for _, node in ipairs(layout.nodes) do
        local selected = s.read(1)
        if selected == nil then return nil, "short" end
        if selected == 1 then
            local purchased = 1
            if version >= 2 then purchased = s.read(1) end
            local rank, chosen, granted = node.max or 1, nil, nil
            if purchased == 1 then
                if s.read(1) == 1 then rank = s.read(6) end
                if s.read(1) == 1 then chosen = (s.read(2) or 0) + 1 end
            else
                granted = true
            end
            if rank == nil then return nil, "short" end
            out[node.id] = { rank = rank, chosen = chosen, granted = granted }
        end
    end
    return out
end

-- ================================================================ Baum -------

--- Ein Baum als kurzer Text: Kopf "v|spec|tree", dann je Knoten
--- "id,x,y,max,c,zauber/zauber,ziel/ziel" — unsichtbare nur "id,,,max".
function Talents.EncodeLayout(layout)
    local teile = {}
    for _, node in ipairs(layout.nodes) do
        if node.visible and node.x and node.y then
            teile[#teile + 1] = table.concat({
                node.id, math.floor(node.x + 0.5), math.floor(node.y + 0.5), node.max or 1,
                node.choice and 1 or 0, table.concat(node.spells or {}, "/"), table.concat(node.edges or {}, "/"),
            }, ",")
        else
            teile[#teile + 1] = table.concat({ node.id, "", "", node.max or 1 }, ",")
        end
    end
    return table.concat({ Talents.LAYOUT_VERSION, layout.specID or 0, layout.treeID or 0 }, "|")
        .. "|" .. table.concat(teile, ";")
end

local function split(text, sep)
    local out = {}
    for part in string.gmatch(text .. sep, "([^" .. sep .. "]*)" .. sep) do out[#out + 1] = part end
    return out
end

--- @return table|nil layout
function Talents.DecodeLayout(text)
    if type(text) ~= "string" then return nil end
    local v, spec, tree, body = string.match(text, "^(%d+)|(%d+)|(%d+)|(.*)$")
    if tonumber(v) ~= Talents.LAYOUT_VERSION or not body or body == "" then return nil end
    local layout = { specID = tonumber(spec), treeID = tonumber(tree), nodes = {} }
    for _, rec in ipairs(split(body, ";")) do
        local f = split(rec, ",")
        local id = tonumber(f[1])
        if not id then return nil end
        local node = { id = id, max = tonumber(f[4]) or 1, spells = {}, edges = {} }
        node.x, node.y = tonumber(f[2]), tonumber(f[3])
        node.visible = node.x ~= nil and node.y ~= nil
        node.choice = f[5] == "1"
        for sp in string.gmatch(f[6] or "", "[^/]+") do node.spells[#node.spells + 1] = tonumber(sp) or 0 end
        for e in string.gmatch(f[7] or "", "[^/]+") do node.edges[#node.edges + 1] = tonumber(e) end
        layout.nodes[#layout.nodes + 1] = node
    end
    if layout.specID == 0 then layout.specID = nil end
    return layout
end

--- Der Baum einer Spezialisierung, entschluesselt und zwischengespeichert.
function Talents:Layout(specID)
    specID = tonumber(specID)
    if not specID then return nil end
    local entry = layouts()[specID]
    if not entry or not entry.text then return nil end
    self.cache = self.cache or {}
    local hit = self.cache[specID]
    if hit and hit.text == entry.text then return hit.layout end
    local layout = Talents.DecodeLayout(entry.text)
    self.cache[specID] = { text = entry.text, layout = layout }
    return layout
end

--- Legt einen Baum ab, wenn er neu oder anders ist.
--- @return boolean geaendert
function Talents:StoreLayout(text, from)
    local layout = Talents.DecodeLayout(text)
    if not layout or not layout.specID then return false end
    local alt = layouts()[layout.specID]
    if alt and alt.text == text then return false end
    layouts()[layout.specID] = { text = text, ts = Util.Now(), from = from }
    GA.Core.Callbacks:Fire("TALENTS_CHANGED", layout.specID)
    return true
end

-- ================================================================ Eigenes ----

--- Liest den eigenen Baum und Stand, legt den Baum ab, prueft den Decoder.
--- @return table|nil tree, string|nil grund
function Talents:CaptureOwn()
    local tree, grund = Compat.ReadOwnTalentTree()
    if not tree then return nil, grund end
    if not tree.specID then
        local loadout = Compat.GetTalentLoadoutString()
        local _, specID = Talents.Header(loadout)
        tree.specID = specID
    end
    if not tree.specID then return nil, "nospec" end

    local text = Talents.EncodeLayout(tree)
    self:StoreLayout(text, "self")
    self.ownTree = tree
    self.ownLayoutText = text

    -- Den Decoder am eigenen Stand messen.
    local loadout = Compat.GetTalentLoadoutString()
    if loadout then
        local decoded = Talents.Decode(loadout, Talents.DecodeLayout(text))
        local stimmt = decoded ~= nil
        if decoded then
            -- Jeder gekaufte Rang muss stimmen; was der String nicht nennt,
            -- darf das Spiel nicht als gekauft fuehren. Geschenkte Knoten
            -- (Fassung 2) haben keinen gekauften Rang und zaehlen nicht.
            for _, node in ipairs(tree.nodes) do
                local d = decoded[node.id]
                local live = node.rank or 0
                if d then
                    if not d.granted and d.rank ~= live then stimmt = false break end
                elseif live > 0 then
                    stimmt = false break
                end
            end
        end
        local db = account()
        db.measured = db.measured or {}
        db.measured.talentDecoder = { ok = stimmt, ts = Util.Now() }
        Debug:Print("armory", "Talent-Decoder am eigenen Stand: %s", stimmt and "stimmt" or "WEICHT AB")

        -- Den eigenen String frisch halten; Sync schickt ihn mit dem Charakter.
        local identity = Compat.GetPlayerIdentity()
        local character = identity.guid and db.characters[identity.guid]
        if character then
            character.specID = tree.specID
            if not character.loadout or character.loadout.value ~= loadout then
                character.loadout = { value = loadout, ts = Util.Now() }
            end
        end
    end
    return tree
end

--- Schickt den eigenen Baum an die Gilde, einmal je Sitzung und Aenderung.
function Talents:PublishLayout()
    if not self.ownLayoutText or not comm() or not Compat.IsInGuild() then return false end
    if self.sentLayout == self.ownLayoutText then return false end
    if type(comm().SendBlob) ~= "function" then return false end
    local ok = comm():SendBlob("TLAY", self.ownLayoutText, "GUILD", nil, true)
    if ok then self.sentLayout = self.ownLayoutText end
    return ok and true or false
end

function Talents:OnLayout(sender, text)
    if comm() and comm():IsSelf(sender) then return false end
    return self:StoreLayout(text, Util.ShortName(sender))
end

-- ================================================================ Lesen ------

--- Der nachgebaute Baum eines Charakters.
--- @return table|nil { layout, picks, own, specID, ts, source }, string|nil grund
function Talents:BuildOf(character)
    if not character then return nil, "nocharacter" end
    local identity = Compat.GetPlayerIdentity()
    local own = identity.guid and character.guid == identity.guid

    -- Der eigene: lebendig aus dem Spiel, wenn moeglich.
    if own then
        local tree = self.ownTree or self:CaptureOwn()
        if tree then
            local picks = {}
            for _, node in ipairs(tree.nodes) do
                if (node.rank or 0) > 0 then picks[node.id] = { rank = node.rank, chosen = node.chosen } end
            end
            return { layout = Talents.DecodeLayout(Talents.EncodeLayout(tree)), picks = picks, own = true,
                     specID = tree.specID, ts = Util.Now(), source = "self" }
        end
    end

    local loadout = character.loadout and character.loadout.value
    if not loadout then return nil, "noloadout" end
    local _, specID = Talents.Header(loadout)
    specID = specID or character.specID
    local layout = self:Layout(specID)
    if not layout then return nil, "nolayout", specID end
    local picks, grund = Talents.Decode(loadout, layout)
    if not picks then return nil, grund, specID end
    return { layout = layout, picks = picks, own = false, specID = specID,
             ts = character.loadout.ts, source = character.loadout.source or character.source }
end

-- ================================================================ Start ------

function Talents:OnEnable()
    local Comm = comm()
    if Comm and type(Comm.OnBlob) == "function" then
        Comm:OnBlob("TLAY", function(sender, text) Talents:OnLayout(sender, text) end, "Talents")
    end

    local function spaeter()
        Talents:CaptureOwn()
        Talents:PublishLayout()
    end
    Compat.After(12, spaeter)

    -- Talente geaendert: neu lesen, und den Baum neu schicken, falls er sich
    -- geaendert hat (eine neue Stufe schaltet Knoten frei).
    if GA.Core.Events then
        for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
            pcall(GA.Core.Events.Register, GA.Core.Events, event, function()
                Talents.ownTree = nil
                Compat.After(2, spaeter)
            end, "Talents")
        end
    end
end
