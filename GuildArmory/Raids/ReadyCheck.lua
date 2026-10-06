--[[----------------------------------------------------------------------------
    Raids/ReadyCheck — beim Ready Check: bin ICH bereit?
    Kein UI (die Anzeige ist UI/ReadyCheckFrame). Gebaut 06.10.2026.

    NUR DER EIGENE CHARAKTER:
      Haltbarkeit, Verzauberungen, Flaeschchen/Elixier — und die Vor-dem-
      Pull-Hinweise des naechsten Bosses aus dem aktiven Raidplan. Gelesen
      wird ausschliesslich der eigene Charakter; es geht keine Nachricht an
      andere. Damit bleibt es unter den Retail-Einschraenkungen moeglich
      (in der Instanz keine Addon-Nachrichten, fremde Daten verschleiert).

    STILL, WENN ALLES PASST:
      Das Fenster erscheint nur, wenn es etwas zu sagen gibt. Ein Fenster bei
      jedem Ready Check, das "alles gut" sagt, lernt man zu uebersehen — und
      dann auch das eine Mal, an dem etwas fehlt.

    DER NAECHSTE BOSS:
      Ein Ready Check sagt nicht, fuer welchen Boss er ist. Genommen wird der
      erste Boss des Plans, der heute noch nicht gelegt wurde — die Reihenfolge
      im Plan ist die Reihenfolge im Raid. Gelegt heisst: ENCOUNTER_END mit
      Erfolg in den letzten zwoelf Stunden.
------------------------------------------------------------------------------]]

local _, GA = ...

local ReadyCheck = {}
GA.Modules.ReadyCheck = ReadyCheck

local Compat = GA.Core.Compat
local Util = GA.Core.Util

--- Unter diesem Anteil wird an die Reparatur erinnert.
ReadyCheck.DURABILITY = 0.30
--- So lange gilt ein Boss als gelegt.
local KILL_WINDOW = 12 * 3600

--- Plaetze, die man fuer einen Raid ueblicherweise verzaubert. Kopf, Beine
--- und Schultern brauchen Ruf (Arkanum, Signet) — wer sie nicht hat, soll
--- nicht bei jedem Ready Check daran erinnert werden. Fernkampf nur fuer
--- Jaeger sinnvoll, darum auch nicht.
ReadyCheck.ENCHANT_SLOTS = {
    { slot = 15, key = "BACK" }, { slot = 5, key = "CHEST" }, { slot = 9, key = "WRIST" },
    { slot = 10, key = "HANDS" }, { slot = 8, key = "FEET" }, { slot = 16, key = "MAINHAND" },
    { slot = 17, key = "OFFHAND" },
}
--- Nebenhand: verzaubern lassen sich Schilde und Waffen, keine Haltegegenstaende.
local OFFHAND_ENCHANTABLE = {
    INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true,
}

--- Flaeschchen und Elixiere: bekannte Zauber-IDs, dazu Namensteile als
--- Rueckfall — die Liste der IDs ist nie vollstaendig, die Namen sind es eher.
ReadyCheck.CONSUMABLE_IDS = {
    [17626] = true, [17627] = true, [17628] = true, [17629] = true,   -- Flaeschchen
    [17538] = true, [11405] = true, [17539] = true, [11474] = true,   -- Mungo, Riesen, Gr. Arkan, Schattenmacht
    [26276] = true, [21920] = true, [11334] = true, [11348] = true,   -- Gr. Feuermacht, Frostmacht, Gr. Beweglichkeit, Oberste Verteidigung
    [3593] = true, [11396] = true, [24363] = true,                    -- Seelenstaerke, Gr. Intelligenz, Magiebluttrank
}
ReadyCheck.CONSUMABLE_WORDS = { "flask", "elixir", "fläschchen", "elixier", "zanza" }

-- ================================================================ Pruefen ---

--- Niedrigste Haltbarkeit als Anteil, oder nil, wenn nichts zu lesen ist.
--- @param list table { { cur, max } }
function ReadyCheck.LowestDurability(list)
    local lowest
    for _, d in ipairs(list or {}) do
        if d.max and d.max > 0 and d.cur then
            local share = d.cur / d.max
            if not lowest or share < lowest then lowest = share end
        end
    end
    return lowest
end

--- Welche der ueblichen Plaetze tragen etwas ohne Verzauberung?
--- @param equipped table [slot] = { link, equipLoc }
--- @return table Liste der Schluessel ("HANDS", …)
function ReadyCheck.MissingEnchants(equipped)
    local out = {}
    for _, entry in ipairs(ReadyCheck.ENCHANT_SLOTS) do
        local item = equipped[entry.slot]
        if item and item.link then
            local applies = entry.slot ~= 17 or OFFHAND_ENCHANTABLE[item.equipLoc or ""]
            local parsed = Compat.ParseItemLink(item.link)
            if applies and parsed and not parsed.enchantID then out[#out + 1] = entry.key end
        end
    end
    return out
end

--- Laeuft ein Flaeschchen oder Elixier? nil = nicht feststellbar.
--- @param auras table|nil { { spellId, name } }
function ReadyCheck.HasConsumable(auras)
    if not auras then return nil end
    for _, aura in ipairs(auras) do
        if aura.spellId and ReadyCheck.CONSUMABLE_IDS[aura.spellId] then return true end
        local name = type(aura.name) == "string" and string.lower(aura.name) or ""
        for _, word in ipairs(ReadyCheck.CONSUMABLE_WORDS) do
            if string.find(name, word, 1, true) then return true end
        end
    end
    return false
end

-- ================================================================ Lesen -----

local function readDurability()
    local list = {}
    for slot = 1, 18 do
        local cur, max = Compat.GetDurability(slot)
        if cur then list[#list + 1] = { cur = cur, max = max } end
    end
    return list
end

local function readEquipped()
    local out = {}
    for _, entry in ipairs(ReadyCheck.ENCHANT_SLOTS) do
        local link = Compat.GetEquippedLink("player", entry.slot)
        if link then
            local info = Compat.GetItemInfo(link)
            out[entry.slot] = { link = link, equipLoc = info and info.equipLoc }
        end
    end
    return out
end

--- Eigene Buffs — nil, wenn der Client sie verschleiert.
local function readAuras()
    local secrets = _G.C_Secrets
    if type(secrets) == "table" and type(secrets.ShouldAurasBeSecret) == "function" then
        local ok, secret = pcall(secrets.ShouldAurasBeSecret)
        if ok and secret then return nil end
    end
    local out = {}
    for index = 1, 40 do
        local data = Compat.GetAura("player", index, "HELPFUL")
        if not data then break end
        local id = Compat.IsReadableNumber(data.spellId) and data.spellId or nil
        local name = Compat.IsReadable(data.name) and data.name or nil
        out[#out + 1] = { spellId = id, name = name }
    end
    return out
end

-- ================================================================ Bosse -----

local function kills()
    local account = GA.Core.Database.account
    account.raidKills = account.raidKills or {}
    return account.raidKills
end

function ReadyCheck:OnEncounterEnd(encounterID, encounterName, success)
    if success ~= 1 and success ~= true then return end
    local now, list = Util.Now(), kills()
    if Compat.IsReadableNumber(encounterID) then list["id:" .. encounterID] = now end
    if type(encounterName) == "string" and Compat.IsReadable(encounterName) then
        list["name:" .. string.lower(encounterName)] = now
    end
    -- Alte Eintraege fallen weg.
    for key, ts in pairs(list) do
        if ts < now - KILL_WINDOW then list[key] = nil end
    end
end

function ReadyCheck.IsKilled(boss, list, now)
    local function fresh(ts) return ts and ts >= now - KILL_WINDOW end
    if boss.encounterID and fresh(list["id:" .. boss.encounterID]) then return true end
    if boss.name and fresh(list["name:" .. string.lower(boss.name)]) then return true end
    return false
end

--- Der erste Boss des Plans, der heute noch steht.
function ReadyCheck.NextBoss(plan, list, now)
    for _, boss in ipairs(plan.bosses or {}) do
        if not ReadyCheck.IsKilled(boss, list or {}, now or Util.Now()) then return boss end
    end
    return nil
end

-- ================================================================ Ergebnis --

--- Was beim Ready Check zu sagen ist.
--- @param opts table|nil { boss = gewaehlter Boss, force = auch ohne Befund }
--- @return table { boss, prepull = { text… }, issues = { { key, value } } }
function ReadyCheck:Evaluate(opts)
    opts = opts or {}
    local Config = GA.Core.Config
    local result = { prepull = {}, issues = {} }

    local RaidPlan = GA.Modules.RaidPlan
    local entry = RaidPlan and RaidPlan:Active()
    if entry then
        local boss = opts.boss or ReadyCheck.NextBoss(entry.plan, kills(), Util.Now())
        if boss then
            result.boss = boss
            local who = RaidPlan.WhoAmI(entry.plan)
            for _, item in ipairs(boss.prepull or {}) do
                if RaidPlan.Matches(item, who) then result.prepull[#result.prepull + 1] = item.text end
            end
        end
    end

    local lowest = ReadyCheck.LowestDurability(readDurability())
    if lowest and lowest < ReadyCheck.DURABILITY then
        result.issues[#result.issues + 1] = { key = "DURABILITY", value = math.floor(lowest * 100 + 0.5) }
    end
    if Config:Get("readyEnchants") ~= false then
        local missing = ReadyCheck.MissingEnchants(readEquipped())
        if #missing > 0 then result.issues[#result.issues + 1] = { key = "ENCHANTS", value = missing } end
    end
    if Config:Get("readyConsumables") ~= false and ReadyCheck.HasConsumable(readAuras()) == false then
        result.issues[#result.issues + 1] = { key = "CONSUMABLE" }
    end
    return result
end

--- Zeigt das Ergebnis — nur, wenn es etwas zu sagen gibt (oder erzwungen).
function ReadyCheck:Run(opts)
    opts = opts or {}
    if not opts.force and GA.Core.Config:Get("readyCheck") == false then return nil end
    local result = self:Evaluate(opts)
    local anything = #result.prepull > 0 or #result.issues > 0
    if anything or opts.force then GA.Core.Callbacks:Fire("READYCHECK_RESULT", result, opts.force) end
    return result
end

function ReadyCheck:OnEnable()
    local Events = GA.Core.Events
    Events:Register("READY_CHECK", function() ReadyCheck:Run() end, "ReadyCheck")
    Events:Register("READY_CHECK_FINISHED", function() GA.Core.Callbacks:Fire("READYCHECK_FINISHED") end, "ReadyCheck")
    Events:Register("ENCOUNTER_END", function(_, id, name, _, _, success)
        ReadyCheck:OnEncounterEnd(id, name, success)
    end, "ReadyCheck")
end
