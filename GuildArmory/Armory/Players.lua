--[[----------------------------------------------------------------------------
    Armory/Players — Spielerprofile: welcher Charakter gehoert zu welchem Spieler.

    Kein UI. Pflegt GA.Core.Database.account.players und die Rueckverknuepfung
    character.playerId.

    WORAUF DIESE ZUORDNUNG BERUHT — und worauf nicht:

    Ein Addon kann NICHT messen, wem ein fremder Charakter gehoert. Es gibt
    keine API, die "Aldrik-Ragnaros und Zephyra-Ragnaros sind dieselbe Person"
    beantwortet. Wer so tut, als wuesste er es, verteilt Loot nach einer
    Vermutung. Deshalb traegt jede Verknuepfung ihre Herkunft:

      "account"  BEWIESEN. Der Charakter hat sich auf DIESEM WoW-Account mit
                 diesem Addon eingeloggt (character.ownAccount, gesetzt von
                 Armory/Equipment beim Erfassen). Zwei Charaktere mit diesem
                 Merkmal teilen sich dieselbe SavedVariables-Datei — das ist
                 eine Tatsache, keine Annahme.

      "claim"    BEHAUPTET. Der Spieler selbst hat die Zuordnung per Sync
                 mitgeteilt (Phase 7). Plausibel, aber nicht pruefbar.

      "manual"   GESETZT. Ein Lootmeister oder Admin hat sie von Hand angelegt.
                 Nachvollziehbar ueber das Journal, aber ebenfalls kein Beweis.

    Die Oberflaeche zeigt diese Herkunft an. Loot-Statistiken, die "pro Spieler"
    rechnen, duerfen spaeter unterscheiden, ob sie auf Bewiesenem oder auf
    Behauptetem beruhen.

    EIN CHARAKTER GEHOERT ZU HOECHSTENS EINEM PROFIL. Ein Wechsel loest die
    alte Verknuepfung, statt zwei widerspruechliche Wahrheiten zu speichern.
------------------------------------------------------------------------------]]

local _, GA = ...

local Players = {}
GA.Modules.Players = Players

local Util = GA.Core.Util
local Debug = GA.Core.Debug

Players.ORIGIN_ACCOUNT = "account"
Players.ORIGIN_CLAIM   = "claim"
Players.ORIGIN_MANUAL  = "manual"

--- Wie stark ist eine Herkunft? Eine bewiesene Zuordnung wird nie von einer
--- behaupteten ueberschrieben — sonst koennte ein fremder Sync die eigene
--- Wahrheit kippen.
local ORIGIN_STRENGTH = { account = 3, manual = 2, claim = 1 }

-- ================================================================== Zugriff ---

local function profiles()
    return GA.Core.Database.account.players
end

local function characters()
    return GA.Core.Database.account.characters
end

function Players:Get(playerId)
    return playerId and profiles()[playerId] or nil
end

--- Profil eines Charakters, oder nil.
function Players:GetProfileFor(guid)
    local character = guid and characters()[guid]
    return character and self:Get(character.playerId) or nil
end

--- Anzeigename: gesetzter Name, sonst der Name des Mains, sonst irgendeiner.
function Players:DisplayName(profile)
    if not profile then return "?" end
    if profile.displayName and profile.displayName ~= "" then return profile.displayName end

    local main = profile.mainGuid and characters()[profile.mainGuid]
    if main and main.name then return Util.ShortName(main.name) end

    for guid in pairs(profile.characterGuids) do
        local character = characters()[guid]
        if character and character.name then return Util.ShortName(character.name) end
    end
    return "?"
end

--- Charaktere eines Profils als Liste: Main zuerst, dann nach Itemlevel.
function Players:CharactersOf(profile)
    local list = {}
    if not profile then return list end

    for guid in pairs(profile.characterGuids) do
        local character = characters()[guid]
        if character then list[#list + 1] = character end
    end

    table.sort(list, function(a, b)
        local aMain = (a.guid == profile.mainGuid) and 1 or 0
        local bMain = (b.guid == profile.mainGuid) and 1 or 0
        if aMain ~= bMain then return aMain > bMain end
        local aLevel = (a.itemLevel and a.itemLevel.value) or -1
        local bLevel = (b.itemLevel and b.itemLevel.value) or -1
        if aLevel ~= bLevel then return aLevel > bLevel end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

--- Alle Profile, nach Anzeigename.
function Players:List()
    local list = {}
    for _, profile in pairs(profiles()) do list[#list + 1] = profile end
    table.sort(list, function(a, b)
        return string.lower(Players:DisplayName(a)) < string.lower(Players:DisplayName(b))
    end)
    return list
end

--- Charaktere ohne Profil.
--- Charaktere ohne Profil — die Liste, aus der man Spieler zusammensetzt.
---
--- FREMDE BLEIBEN DRAUSSEN. Ein einmal inspizierter Spieler aus einer anderen
--- Gilde stand hier zwischen den eigenen Leuten und sah aus wie jemand, dem
--- man noch ein Profil anlegen muss (gemeldet 25.09.2026). Was "fremd" heisst
--- und warum ein fehlender Gildenname dafuer NICHT genuegt, steht an
--- DB:IsForeignCharacter.
function Players:Unassigned()
    local db = GA.Core.Database
    local list = {}
    for _, character in pairs(characters()) do
        if (not character.playerId or not self:Get(character.playerId))
            and not db:IsForeignCharacter(character) then
            list[#list + 1] = character
        end
    end
    Util.SortBy(list, { { field = "name" } })
    return list
end

-- ================================================================== Aendern ---

--- Legt ein Profil an. `seedGuid` wird gleich zugeordnet und Main.
function Players:Create(seedGuid, origin, displayName)
    local profile = {
        id = Util.NewId("p"),
        displayName = displayName,
        mainGuid = nil,
        characterGuids = {},
        origin = {},
        createdTs = Util.Now(),
    }
    profiles()[profile.id] = profile

    if seedGuid then
        self:Link(seedGuid, profile.id, origin or self.ORIGIN_MANUAL)
        self:SetMain(profile.id, seedGuid)
    end

    GA.Core.Database:Journal("PLAYER_CREATE", profile.id, nil, seedGuid)
    return profile
end

--- Ordnet einen Charakter einem Profil zu.
--- @return boolean geaendert, string|nil grund
function Players:Link(guid, playerId, origin)
    local character = guid and characters()[guid]
    local profile = self:Get(playerId)
    if not character or not profile then return false, "unknown" end

    origin = origin or self.ORIGIN_MANUAL

    if character.playerId == playerId then
        -- Schon zugeordnet: nur die Herkunft darf staerker werden.
        local before = profile.origin[guid]
        if (ORIGIN_STRENGTH[origin] or 0) > (ORIGIN_STRENGTH[before] or 0) then
            profile.origin[guid] = origin
            return true
        end
        return false, "already"
    end

    -- Eine bewiesene Zuordnung wird nicht von einer schwaecheren verdraengt.
    local current = self:GetProfileFor(guid)
    if current then
        local currentOrigin = current.origin[guid]
        if (ORIGIN_STRENGTH[currentOrigin] or 0) > (ORIGIN_STRENGTH[origin] or 0) then
            return false, "stronger"
        end
        self:Unlink(guid, true)
    end

    profile.characterGuids[guid] = true
    profile.origin[guid] = origin
    character.playerId = playerId
    if not profile.mainGuid then profile.mainGuid = guid end

    GA.Core.Database:Journal("PLAYER_LINK", guid, current and current.id or nil,
        { playerId = playerId, origin = origin })
    GA.Core.Callbacks:Fire("PLAYERS_CHANGED")
    return true
end

--- Loest die Zuordnung. Leere Profile werden entfernt — ein Profil ohne
--- Charaktere ist kein Spieler, sondern Muell.
function Players:Unlink(guid, quiet)
    local character = guid and characters()[guid]
    if not character then return false end

    local profile = self:Get(character.playerId)
    character.playerId = nil
    if not profile then return false end

    profile.characterGuids[guid] = nil
    profile.origin[guid] = nil

    if profile.mainGuid == guid then
        profile.mainGuid = nil
        for otherGuid in pairs(profile.characterGuids) do
            profile.mainGuid = otherGuid
            break
        end
    end

    local empty = next(profile.characterGuids) == nil
    if empty then profiles()[profile.id] = nil end

    if not quiet then
        GA.Core.Database:Journal("PLAYER_UNLINK", guid, profile.id, nil)
        GA.Core.Callbacks:Fire("PLAYERS_CHANGED")
    end
    return true
end

--- @param byUser boolean  true, wenn ein Mensch das entschieden hat. Dann wird
---        der Main nie wieder automatisch nach Itemlevel umgesetzt.
function Players:SetMain(playerId, guid, byUser)
    local profile = self:Get(playerId)
    if not profile or not profile.characterGuids[guid] then return false end
    if byUser then profile.mainSetByUser = true end
    if profile.mainGuid == guid then return false end

    local before = profile.mainGuid
    profile.mainGuid = guid
    GA.Core.Database:Journal("PLAYER_MAIN", playerId, before, guid)
    GA.Core.Callbacks:Fire("PLAYERS_CHANGED")
    return true
end

function Players:SetDisplayName(playerId, name)
    local profile = self:Get(playerId)
    if not profile then return false end
    local before = profile.displayName
    profile.displayName = (name and name ~= "") and name or nil
    GA.Core.Database:Journal("PLAYER_RENAME", playerId, before, profile.displayName)
    GA.Core.Callbacks:Fire("PLAYERS_CHANGED")
    return true
end

-- ================================================================== Eigene ----

--- Alle Charaktere dieses WoW-Accounts in ein Profil. Das ist der einzige Ort,
--- an dem eine Zuordnung BEWIESEN ist: Diese Charaktere haben sich mit diesem
--- Addon auf diesem Account eingeloggt und teilen sich die SavedVariables.
---
--- Laeuft bei jedem Start. Ein neu erstellter Twink taucht beim ersten Login
--- automatisch beim richtigen Spieler auf, ohne dass jemand etwas eintraegt.
function Players:RebuildOwnProfile()
    local own = {}
    for guid, character in pairs(characters()) do
        if character.ownAccount then own[#own + 1] = guid end
    end
    if #own == 0 then return end

    -- Gibt es schon ein Profil mit einem dieser Charaktere? Dann dort hinein.
    local target
    for _, guid in ipairs(own) do
        local profile = self:GetProfileFor(guid)
        if profile then target = profile break end
    end

    if not target then
        target = self:Create(nil, nil, nil)
    end

    local linked = 0
    for _, guid in ipairs(own) do
        if self:Link(guid, target.id, self.ORIGIN_ACCOUNT) then linked = linked + 1 end
    end

    -- Main: der Charakter mit dem hoechsten Itemlevel, solange keiner gesetzt
    -- wurde. Eine Vermutung — aber eine, die der Spieler jederzeit umstellt,
    -- und sie wird nie als Tatsache beschriftet.
    if not target.mainSetByUser then
        local best, bestLevel
        for _, guid in ipairs(own) do
            local character = characters()[guid]
            local level = (character and character.itemLevel and character.itemLevel.value) or -1
            if not bestLevel or level > bestLevel then best, bestLevel = guid, level end
        end
        if best and target.mainGuid ~= best then
            target.mainGuid = best
        end
    end

    if linked > 0 then
        Debug:Print("players", "Eigenes Profil: %d Charaktere zugeordnet (bewiesen)", linked)
        GA.Core.Callbacks:Fire("PLAYERS_CHANGED")
    end
    return target
end

--- Herkunft einer Zuordnung als Schluessel fuer die Oberflaeche.
function Players:OriginOf(guid)
    local profile = self:GetProfileFor(guid)
    return profile and profile.origin[guid] or nil
end

-- ================================================================== Start ------

function Players:OnEnable()
    GA.Core.Callbacks:On("EQUIPMENT_UPDATED", function()
        Players:RebuildOwnProfile()
    end, "Players")

    GA.Core.Compat.After(2, function() Players:RebuildOwnProfile() end)
end
