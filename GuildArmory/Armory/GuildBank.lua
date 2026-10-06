--[[----------------------------------------------------------------------------
    Armory/GuildBank — was in der Gildenbank liegt. Kein UI.
    Gebaut 06.10.2026 auf Wunsch: "ein Guild-Bank-Tab, wo man sieht, was in
    der Gildenbank vorraetig ist".

    DIE BANK IST NUR OFFEN LESBAR:
      Das Spiel gibt den Inhalt der Gildenbank nur heraus, solange jemand sie
      an einem Gildentresor geoeffnet hat — und dann nur die Faecher, die sein
      Rang sehen darf. Wer sie oeffnet, liest deshalb jedes sichtbare Fach,
      legt den Stand ab und schickt ihn an die Gilde (Blob GBANK). So sieht
      jeder den Vorrat, auch ohne selbst am Tresor zu stehen — mit Zeit und
      Namen, wer gelesen hat.

    EIN FACH, DAS NOCH NICHT GELADEN IST, SIEHT LEER AUS. Wie beim Berufs-
    fenster: Gelesen wird ein Fach erst, nachdem es angefragt wurde
    (QueryGuildBankTab) und die Antwort zur Ruhe gekommen ist.

    WAS GETEILT WIRD, ENTSCHEIDET DER LESER: Die Einstellung "Gildenbank mit
    der Gilde teilen" (Standard an) kann er abschalten — dann bleibt sein
    Stand bei ihm. Geteilt werden die Faecher, die er sehen darf.
------------------------------------------------------------------------------]]

local _, GA = ...

local GuildBank = {}
GA.Modules.GuildBank = GuildBank

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Ruhezeit nach dem letzten Bank-Ereignis, bevor gelesen wird.
local SETTLE = 1.2
--- Abstand zwischen den Anfragen der Faecher — das Spiel drosselt sonst.
local QUERY_GAP = 0.4
--- So lange nach dem Einloggen wird nach einem neueren Stand gefragt.
local REQUEST_DELAY = 40

local function store()
    local account = GA.Core.Database.account
    account.guildBank = account.guildBank or {}
    return account.guildBank
end

function GuildBank:Data() return store() end

-- ================================================================ Kodierung --

local function clean(text) return (string.gsub(tostring(text or ""), "[|%^~:,;]", "")) end

--- "ts|geld|fach^fach" — je Fach "index~name~symbol~id:anzahl,id:anzahl".
function GuildBank.Encode(data)
    local tabs = {}
    for _, tab in ipairs(data.tabs or {}) do
        local items = {}
        local ids = {}
        for id in pairs(tab.items or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do items[#items + 1] = id .. ":" .. tab.items[id] end
        tabs[#tabs + 1] = table.concat({ tab.index or #tabs + 1, clean(tab.name), clean(tab.icon), table.concat(items, ",") }, "~")
    end
    return table.concat({ math.floor(tonumber(data.ts) or 0), math.floor(tonumber(data.money) or 0), table.concat(tabs, "^") }, "|")
end

--- @return table|nil { ts, money, tabs }
function GuildBank.Decode(text)
    if type(text) ~= "string" then return nil end
    local ts, money, rest = string.match(text, "^(%d+)|(%d+)|(.*)$")
    ts, money = tonumber(ts), tonumber(money)
    if not ts or not rest then return nil end
    local out = { ts = ts, money = money, tabs = {} }
    for rec in string.gmatch(rest, "[^%^]+") do
        local index, name, icon, items = string.match(rec, "^(%d+)~([^~]*)~([^~]*)~(.*)$")
        if not index then return nil end
        local tab = { index = tonumber(index), name = name ~= "" and name or nil,
            icon = tonumber(icon) or (icon ~= "" and icon or nil), items = {} }
        for id, count in string.gmatch(items, "(%d+):(%d+)") do
            tab.items[tonumber(id)] = tonumber(count)
        end
        out.tabs[#out.tabs + 1] = tab
    end
    return out
end

-- ================================================================ Lesen -----

--- Die Bank ist offen: jedes sichtbare Fach anfragen.
function GuildBank:OnOpen()
    self.open = true
    self.queried = {}
    local tabs = Compat.GetGuildBankTabs()
    if not tabs then return end
    for n, tab in ipairs(tabs) do
        if tab.viewable then
            Compat.After((n - 1) * QUERY_GAP, function()
                if not GuildBank.open then return end
                Compat.QueryGuildBankTab(tab.index)
                GuildBank.queried[tab.index] = true
                GuildBank:ScheduleRead()
            end)
        end
    end
    self:ScheduleRead()
end

function GuildBank:OnClose()
    if self.open then self:Read(true) end
    self.open = false
end

function GuildBank:ScheduleRead()
    self.readToken = (self.readToken or 0) + 1
    local token = self.readToken
    Compat.After(SETTLE, function()
        if GuildBank.readToken ~= token then return end
        GuildBank:Read(false)
    end)
end

--- Liest die angefragten Faecher. Ein Fach, das noch nicht angefragt wurde,
--- behaelt seinen alten Stand — leer heisst dort "noch nicht geladen".
--- @param final boolean beim Schliessen: das Ergebnis geht an die Gilde
function GuildBank:Read(final)
    local tabs = Compat.GetGuildBankTabs()
    if not tabs or #tabs == 0 then return false end
    local db = store()
    local old = {}
    for _, tab in ipairs(db.tabs or {}) do old[tab.index] = tab end

    local fresh, read = {}, 0
    for _, info in ipairs(tabs) do
        if info.viewable then
            local items = self.queried and self.queried[info.index] and Compat.ReadGuildBankTab(info.index) or nil
            if items then read = read + 1 end
            fresh[#fresh + 1] = { index = info.index, name = info.name, icon = info.icon,
                items = items or (old[info.index] and old[info.index].items) or {} }
        end
    end
    if read == 0 then return false end

    local identity = Compat.GetPlayerIdentity()
    db.tabs = fresh
    db.ts = Util.Now()
    db.by = identity and identity.name and Util.ShortName(identity.name) or db.by
    db.money = Compat.GetGuildBankMoney() or db.money
    GA.Core.Callbacks:Fire("GUILD_BANK_CHANGED")
    if final then
        local count = 0
        for _, tab in ipairs(fresh) do for _, n in pairs(tab.items) do count = count + n end end
        Debug:Info(GA.L.GB_SCANNED, #fresh, count)
        self:Publish()
    end
    return true
end

-- ================================================================ Teilen ----

--- Der eigene Stand an die Gilde — nur, wenn der Leser teilen will.
function GuildBank:Publish()
    if GA.Core.Config:Get("guildBankShare") == false then return false end
    local db = store()
    if not db.ts or not db.tabs or #db.tabs == 0 then return false end
    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end
    return Comm:SendBlob("GBANK", GuildBank.Encode(db), "GUILD", nil, true) and true or false
end

--- Ein Stand von jemand anderem: genommen, wenn er neuer ist.
function GuildBank:OnBank(sender, text)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local data = GuildBank.Decode(text)
    if not data then return end
    if data.ts > Util.Now() + 300 then return end      -- aus der Zukunft: Uhr falsch, nicht uebernehmen
    self.heard = math.max(self.heard or 0, data.ts)
    local db = store()
    if (db.ts or 0) >= data.ts then return end
    db.ts, db.money, db.tabs, db.by = data.ts, data.money, data.tabs, Util.ShortName(sender)
    GA.Core.Callbacks:Fire("GUILD_BANK_CHANGED")
end

--- Jemand fragt nach dem neuesten Stand. Nur wer Neueres hat, antwortet —
--- gestreut, und nicht, wenn inzwischen ein anderer schon geantwortet hat.
function GuildBank:OnRequest(sender, fields)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local theirs = tonumber(fields and fields[1]) or 0
    local db = store()
    if not db.ts or db.ts <= theirs then return end
    Compat.After(2 + math.random() * 8, function()
        if (GuildBank.heard or 0) >= (store().ts or 0) then return end
        GuildBank:Publish()
    end)
end

function GuildBank:Request()
    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end
    return Comm:Send("GBREQ", { store().ts or 0 }, "GUILD", nil, true) and true or false
end

-- ================================================================ Start ----

function GuildBank:OnEnable()
    local Events = GA.Core.Events
    Events:Register("GUILDBANKFRAME_OPENED", function() GuildBank:OnOpen() end, "GuildBank")
    Events:Register("GUILDBANKFRAME_CLOSED", function() GuildBank:OnClose() end, "GuildBank")
    -- Neuere Clients melden den Tresor ueber den Interaktionsmanager.
    local banker = _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.GuildBanker or 10
    Events:Register("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) if kind == banker then GuildBank:OnOpen() end end, "GuildBank")
    Events:Register("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind) if kind == banker then GuildBank:OnClose() end end, "GuildBank")
    Events:Register("GUILDBANKBAGSLOTS_CHANGED", function() if GuildBank.open then GuildBank:ScheduleRead() end end, "GuildBank")
    Events:Register("GUILDBANK_UPDATE_MONEY", function() if GuildBank.open then GuildBank:ScheduleRead() end end, "GuildBank")

    local Comm = GA.Core.Comm
    if Comm then
        Comm:OnBlob("GBANK", function(sender, text) GuildBank:OnBank(sender, text) end, "GuildBank")
        Comm:On("GBREQ", function(sender, fields) GuildBank:OnRequest(sender, fields) end, "GuildBank")
    end
    Compat.After(REQUEST_DELAY, function() GuildBank:Request() end)
end
