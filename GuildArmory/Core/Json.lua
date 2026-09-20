--[[----------------------------------------------------------------------------
    Json — Kodierer und Parser.

    Warum JSON und nicht ein eigenes Lua-Format (docs/ARCHITECTURE.md, 6.2):
    Dasselbe Format traegt beide Wege aus dem Addon heraus — den Strategie-String
    zum Teilen unter Raidleadern und den Export fuer die Webapp. Eine Schnittstelle,
    eine Quelle der Wahrheit. Und die Webapp braucht keinen Lua-Parser, was die
    fehleranfaelligste Stelle solcher Werkzeuge ist.

    Warum selbstgeschrieben und keine Bibliothek: LibSerialize und LibDeflate waeren
    die uebliche Wahl und koennen spaeter dazukommen (sie wuerden die Strings
    deutlich kuerzen). Aber sie muessten mitgeliefert werden, und fuer eine
    Strategie von wenigen Kilobyte ist der Gewinn den zusaetzlichen Ballast nicht
    wert. Der Ausbau ist vorbereitet: Serializer kapselt die Kodierung, es haengt
    kein Aufrufer direkt an dieser Datei.

    Lua 5.1: keine Bit-Operatoren, kein goto. Alles hier kommt mit
    string.byte/char, Arithmetik und table.concat aus.
------------------------------------------------------------------------------]]

local _, GA = ...

local Json = {}
GA.Core.Json = Json

-- ---------------------------------------------------------------- Kodieren ---

local ESCAPES = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function escapeString(text)
    local out = string.gsub(text, '[%c"\\]', function(char)
        local escape = ESCAPES[char]
        if escape then return escape end
        -- Uebrige Steuerzeichen als \u00XX. WoW-Farbcodes enthalten keine,
        -- aber Spielernamen aus fremden Quellen koennen alles enthalten.
        return string.format('\\u%04x', string.byte(char))
    end)
    return '"' .. out .. '"'
end

--- Ist die Tabelle ein Array (Schluessel 1..n, lueckenlos, sonst nichts)?
local function isArray(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then return false end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then return false end
    end
    return true, count
end

local encodeValue

local function encodeTable(value, out, depth)
    if depth > 64 then
        error("JSON: Verschachtelung zu tief (Zyklus?)")
    end

    local array, count = isArray(value)

    if array then
        if count == 0 then
            out[#out + 1] = "[]"
            return
        end
        out[#out + 1] = "["
        for index = 1, count do
            if index > 1 then out[#out + 1] = "," end
            encodeValue(value[index], out, depth + 1)
        end
        out[#out + 1] = "]"
        return
    end

    -- Objekt. Schluessel werden sortiert ausgegeben, damit zwei Exporte
    -- derselben Daten denselben String ergeben — sonst sieht jeder Export nach
    -- einer Aenderung aus.
    --
    -- Der Originalschluessel wird mitgefuehrt, nicht nur seine Textfassung:
    -- Die Datenbank benutzt Zahlen als Schluessel (encounterID), und ein
    -- Zugriff ueber die Zeichenkette liefe ins Leere.
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = { raw = key, text = tostring(key) }
    end
    table.sort(keys, function(a, b) return a.text < b.text end)

    out[#out + 1] = "{"
    for index, entry in ipairs(keys) do
        if index > 1 then out[#out + 1] = "," end
        out[#out + 1] = escapeString(entry.text)
        out[#out + 1] = ":"
        encodeValue(value[entry.raw], out, depth + 1)
    end
    out[#out + 1] = "}"
end

encodeValue = function(value, out, depth)
    local kind = type(value)

    if value == nil then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = value and "true" or "false"
    elseif kind == "number" then
        -- Ganze Zahlen ohne Nachkommastellen; %.14g vermeidet 1e+15-Notation
        -- fuer Zeitstempel.
        if value ~= value or value == math.huge or value == -math.huge then
            error("JSON: Zahl nicht darstellbar (nan/inf)")
        end
        if math.floor(value) == value and math.abs(value) < 1e15 then
            out[#out + 1] = string.format("%d", value)
        else
            out[#out + 1] = string.format("%.14g", value)
        end
    elseif kind == "string" then
        out[#out + 1] = escapeString(value)
    elseif kind == "table" then
        encodeTable(value, out, depth)
    else
        error("JSON: Typ nicht kodierbar: " .. kind)
    end
end

--- @return string|nil ergebnis, string|nil fehler
function Json.Encode(value)
    local out = {}
    local ok, err = pcall(encodeValue, value, out, 0)
    if not ok then return nil, tostring(err) end
    return table.concat(out)
end

-- ------------------------------------------------------------------ Parsen ---

local Parser = {}
Parser.__index = Parser

local function newParser(text)
    return setmetatable({ text = text, pos = 1, len = #text }, Parser)
end

function Parser:error(message)
    error(string.format("JSON: %s (Position %d)", message, self.pos), 0)
end

function Parser:skipWhitespace()
    local _, stop = string.find(self.text, "^[ \t\r\n]*", self.pos)
    self.pos = stop + 1
end

function Parser:peek()
    return string.sub(self.text, self.pos, self.pos)
end

function Parser:expect(char)
    if self:peek() ~= char then
        self:error("erwartet '" .. char .. "', gefunden '" .. self:peek() .. "'")
    end
    self.pos = self.pos + 1
end

local UNESCAPES = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

function Parser:parseString()
    self:expect('"')
    local parts = {}

    while true do
        if self.pos > self.len then self:error("Zeichenkette nicht beendet") end

        local char = string.sub(self.text, self.pos, self.pos)

        if char == '"' then
            self.pos = self.pos + 1
            return table.concat(parts)
        end

        if char == "\\" then
            local escape = string.sub(self.text, self.pos + 1, self.pos + 1)
            local simple = UNESCAPES[escape]

            if simple then
                parts[#parts + 1] = simple
                self.pos = self.pos + 2
            elseif escape == "u" then
                local hex = string.sub(self.text, self.pos + 2, self.pos + 5)
                local code = tonumber(hex, 16)
                if not code then self:error("ungueltige \\u-Sequenz") end
                -- Nur die BMP-Grundebene; fuer Namen und Notizen ausreichend.
                if code < 128 then
                    parts[#parts + 1] = string.char(code)
                else
                    -- UTF-8 von Hand, weil Lua 5.1 kein utf8.char kennt.
                    if code < 2048 then
                        parts[#parts + 1] = string.char(192 + math.floor(code / 64),
                                                        128 + (code % 64))
                    else
                        parts[#parts + 1] = string.char(
                            224 + math.floor(code / 4096),
                            128 + (math.floor(code / 64) % 64),
                            128 + (code % 64))
                    end
                end
                self.pos = self.pos + 6
            else
                self:error("unbekannte Escape-Sequenz")
            end
        else
            -- Bis zum naechsten Sonderzeichen in einem Rutsch nehmen.
            local stop = string.find(self.text, '["\\]', self.pos)
            if not stop then self:error("Zeichenkette nicht beendet") end
            parts[#parts + 1] = string.sub(self.text, self.pos, stop - 1)
            self.pos = stop
        end
    end
end

function Parser:parseNumber()
    local start, stop = string.find(self.text, "^-?%d+%.?%d*[eE]?[-+]?%d*", self.pos)
    if not start then self:error("Zahl erwartet") end

    local value = tonumber(string.sub(self.text, start, stop))
    if not value then self:error("ungueltige Zahl") end

    self.pos = stop + 1
    return value
end

function Parser:parseValue(depth)
    if depth > 64 then self:error("Verschachtelung zu tief") end
    self:skipWhitespace()

    local char = self:peek()

    if char == "{" then
        self.pos = self.pos + 1
        local object = {}
        self:skipWhitespace()

        if self:peek() == "}" then self.pos = self.pos + 1 return object end

        while true do
            self:skipWhitespace()
            local key = self:parseString()
            self:skipWhitespace()
            self:expect(":")
            object[key] = self:parseValue(depth + 1)
            self:skipWhitespace()

            local next = self:peek()
            if next == "," then
                self.pos = self.pos + 1
            elseif next == "}" then
                self.pos = self.pos + 1
                return object
            else
                self:error("',' oder '}' erwartet")
            end
        end
    end

    if char == "[" then
        self.pos = self.pos + 1
        local array = {}
        self:skipWhitespace()

        if self:peek() == "]" then self.pos = self.pos + 1 return array end

        while true do
            array[#array + 1] = self:parseValue(depth + 1)
            self:skipWhitespace()

            local next = self:peek()
            if next == "," then
                self.pos = self.pos + 1
            elseif next == "]" then
                self.pos = self.pos + 1
                return array
            else
                self:error("',' oder ']' erwartet")
            end
        end
    end

    if char == '"' then return self:parseString() end

    if string.sub(self.text, self.pos, self.pos + 3) == "true" then
        self.pos = self.pos + 4
        return true
    end
    if string.sub(self.text, self.pos, self.pos + 4) == "false" then
        self.pos = self.pos + 5
        return false
    end
    if string.sub(self.text, self.pos, self.pos + 3) == "null" then
        self.pos = self.pos + 4
        return nil
    end

    return self:parseNumber()
end

--- @return table|nil ergebnis, string|nil fehler
function Json.Decode(text)
    if type(text) ~= "string" or text == "" then
        return nil, "Leere Eingabe"
    end

    local parser = newParser(text)
    local ok, result = pcall(parser.parseValue, parser, 0)
    if not ok then return nil, tostring(result) end

    parser:skipWhitespace()
    if parser.pos <= parser.len then
        return nil, "Unerwartete Zeichen nach dem Ende (Position " .. parser.pos .. ")"
    end

    return result
end
