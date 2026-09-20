--[[----------------------------------------------------------------------------
    Armory/Notes — Spitznamen und freie Notizen je Charakter.

    Kein UI. Kleines Modul, aber es loest ein echtes Problem: Im Council steht
    "Thrallmarwyn" auf dem Zettel, und niemand weiss, dass das der Tank ist,
    der seit zwei Jahren dabei ist.

    ZWEI GETRENNTE FELDER, UND DER UNTERSCHIED IST WICHTIG:

      nickname  — wie die Gilde die Person nennt. Ersetzt in der Anzeige den
                  Charakternamen NICHT, sondern steht daneben. Ein Addon, das
                  Namen austauscht, macht Logs und Chat unlesbar.

      note      — freier Text. Alles, was jemand fuer erwaehnenswert haelt.

    BEIDES IST LOKAL, bis jemand es ausdruecklich teilt. Eine Notiz ueber einen
    Mitspieler ist nichts, was ungefragt durch die Gilde wandert — schon gar
    nicht, wenn sie unfreundlich ist.
------------------------------------------------------------------------------]]

local _, GA = ...

local Notes = {}
GA.Modules.Notes = Notes

local Util = GA.Core.Util

local MAX_NICKNAME = 24
local MAX_NOTE = 200

local function store()
    local db = GA.Core.Database.account
    db.notes = db.notes or {}
    return db.notes
end

--- Schneidet zu und entfernt Steuerzeichen. Farbcodes und Links haetten in
--- einer Liste nichts zu suchen — sie wuerden die Zeile sprengen.
local function clean(text, limit)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "|", "")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s*(.-)%s*$", "%1")
    if text == "" then return nil end
    return string.sub(text, 1, limit)
end

-- ================================================================== Zugriff ---

function Notes:Get(guid)
    return guid and store()[guid] or nil
end

function Notes:GetNickname(guid)
    local entry = self:Get(guid)
    return entry and entry.nickname or nil
end

function Notes:GetNote(guid)
    local entry = self:Get(guid)
    return entry and entry.note or nil
end

--- Name fuer die Anzeige: "Thrallmarwyn (Kevin)".
--- Der Charaktername bleibt vorn — man muss ihn im Chat wiederfinden.
function Notes:DisplayName(guid, fallback)
    local name = Util.ShortName(fallback or "?")
    local nickname = self:GetNickname(guid)
    if not nickname or nickname == name then return name end
    return string.format("%s (%s)", name, nickname)
end

-- ================================================================== Setzen ---

function Notes:SetNickname(guid, nickname)
    if not guid then return false end
    local entry = store()[guid] or {}

    local before = entry.nickname
    entry.nickname = clean(nickname, MAX_NICKNAME)
    entry.ts = Util.Now()
    store()[guid] = entry

    if before ~= entry.nickname then
        GA.Core.Database:Journal("NICKNAME", guid, before, entry.nickname)
        GA.Core.Callbacks:Fire("NOTES_CHANGED", guid)
    end
    return true
end

function Notes:SetNote(guid, note)
    if not guid then return false end
    local entry = store()[guid] or {}

    local before = entry.note
    entry.note = clean(note, MAX_NOTE)
    entry.ts = Util.Now()
    store()[guid] = entry

    if before ~= entry.note then
        GA.Core.Database:Journal("NOTE", guid, before, entry.note)
        GA.Core.Callbacks:Fire("NOTES_CHANGED", guid)
    end
    return true
end

function Notes:Clear(guid)
    if not guid or not store()[guid] then return false end
    store()[guid] = nil
    GA.Core.Database:Journal("NOTE_CLEAR", guid, nil, nil)
    GA.Core.Callbacks:Fire("NOTES_CHANGED", guid)
    return true
end

function Notes:Count()
    local count = 0
    for _ in pairs(store()) do count = count + 1 end
    return count
end
