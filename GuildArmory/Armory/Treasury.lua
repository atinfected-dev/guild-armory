--[[----------------------------------------------------------------------------
    Armory/Treasury — das Sparziel der Gilde.

    Kein Steuersystem: Ein Addon kann kein Gold bewegen, also gibt es keine
    Abgabe, keine Schuld, keinen Pranger. Es gibt ein ZIEL — "300 Gold fuer
    Flaeschchen bis zum 1. November" —, den Stand der Gildenbank dazu, und
    an der Bank einen Knopf fuer den, der etwas dazulegen will (08.10.2026,
    Entscheidung: "Sparziel waere am sinnvollsten").

    GEZAEHLT WIRD, WAS SEIT DEM SETZEN DAZUKAM. Die Bank hat beim Setzen
    einen Stand; der ist die Grundlinie. Fortschritt ist, was darueber
    liegt. Gibt die Gilde zwischendurch Gold aus, sinkt der Fortschritt —
    das ist kein Fehler, sondern die Wahrheit ueber die Kasse. Wer die
    Grundlinie neu ziehen will, setzt das Ziel neu.

    WER SETZT: wer im Spiel die Nachricht des Tages aendern darf. Das Ziel
    geht an die Gilde wie Gildenbank und Raidplaene (TGOAL), wer spaeter
    einloggt, fragt nach (TGREQ). Die hoechste Fassung gilt.

    DER STAND kommt aus Armory/GuildBank: Wer die Bank oeffnet, liest das
    Gold und teilt es. Ohne einen Stand gibt es keinen Fortschritt, nur den
    Hinweis, die Bank einmal zu oeffnen.
------------------------------------------------------------------------------]]

local _, GA = ...

local Treasury = {}
GA.Modules.Treasury = Treasury

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- So lange nach dem Einloggen wird nach einem neueren Ziel gefragt.
local REQUEST_DELAY = 50
local TITLE_LEN, NOTE_LEN = 60, 120

local function store()
    local account = GA.Core.Database.account
    account.treasury = account.treasury or {}
    return account.treasury
end

--- Trennzeichen des Protokolls raus, Laenge begrenzt.
local function clean(text, length)
    text = tostring(text or "")
    text = string.gsub(text, "[|~^:,;]", "")
    text = Util.Trim(text) or ""
    if #text > length then text = string.sub(text, 1, length) end
    return text
end

-- ================================================================ Lesen -----

--- Das Ziel, oder nil (keins gesetzt oder aufgehoben).
function Treasury:Goal()
    local goal = store().goal
    if not goal or goal.removed then return nil end
    return goal
end

--- Darf ich das Ziel setzen? Wer die Nachricht des Tages aendern darf —
--- dasselbe Recht wie bei den Gildennotizen; unbekannt heisst nicht nein.
function Treasury:CanEdit()
    return Compat.CanEditMOTD() ~= false
end

--- Kupfer als "12g 34s"; unter einem Gold "34s", nie Kupfer — die Kasse
--- rechnet nicht in Kupfer.
function Treasury.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    return string.format("%ds", s)
end

--- Eingabe "5", "2,5", "2.5", "120g" als Kupfer; nil, wenn unlesbar.
function Treasury.ParseGold(text)
    text = Util.Trim(tostring(text or "")) or ""
    text = string.gsub(text, "[gG]$", "")
    text = string.gsub(text, ",", ".")
    local gold = tonumber(text)
    if not gold or gold < 0 then return nil end
    return math.floor(gold * 10000 + 0.5)
end

--- Der Stand gegen das Ziel.
--- @return table|nil { raised, amount, ratio, money, ts, by, known, state, daysLeft }
---   state: "reached" | "ontrack" | "behind" | "overdue" | "unknown"
function Treasury:Progress()
    local goal = self:Goal()
    if not goal then return nil end
    local bank = GA.Modules.GuildBank and GA.Modules.GuildBank:Data() or {}
    local money = tonumber(bank.money)
    local out = { amount = goal.amount, money = money, ts = bank.ts, by = bank.by, known = money ~= nil }
    if not money then
        out.raised, out.ratio, out.state = 0, 0, "unknown"
        return out
    end
    out.raised = math.max(0, money - (goal.baseline or 0))
    out.ratio = math.min(1, goal.amount > 0 and out.raised / goal.amount or 0)
    local now = Util.Now()
    if out.raised >= goal.amount then
        out.state = "reached"
    elseif goal.deadline then
        out.daysLeft = math.ceil((goal.deadline - now) / 86400)
        if now > goal.deadline then
            out.state = "overdue"
        else
            -- Linear vom Setzen bis zur Frist: Wer darueber liegt, ist auf Kurs.
            local span = goal.deadline - (goal.start or now)
            -- Erst teilen, dann malnehmen: Kupfer mal Sekunden sprengt 32-Bit-Zahlen
            -- (die Test-VM rechnet so; das Spiel nicht, aber es kostet nichts).
            local expected = span > 0 and goal.amount * ((now - (goal.start or now)) / span) or 0
            out.state = out.raised >= expected and "ontrack" or "behind"
        end
    else
        out.state = "ontrack"
    end
    return out
end

-- ================================================================ Setzen ----

--- Setzt oder aendert das Ziel. Die Grundlinie bleibt, wenn es dasselbe
--- Ziel ist (nur Frist oder Betrag geaendert); neu ist sie bei einem neuen.
--- @param fields table { title, amount (Kupfer), deadline (ts|nil), note, restart }
--- @return table|nil goal, string|nil grund
function Treasury:SetGoal(fields)
    if not self:CanEdit() then return nil, "notallowed" end
    fields = fields or {}
    local amount = math.floor(tonumber(fields.amount) or 0)
    if amount <= 0 then return nil, "amount" end
    local title = clean(fields.title, TITLE_LEN)
    if title == "" then return nil, "title" end
    local deadline = tonumber(fields.deadline) or nil
    if deadline and deadline < Util.Now() then return nil, "deadline" end

    local old = self:Goal()
    local bank = GA.Modules.GuildBank and GA.Modules.GuildBank:Data() or {}
    local identity = Compat.GetPlayerIdentity()
    local fresh = not old or fields.restart
    local goal = {
        id = (old and not fields.restart) and old.id or Util.NewId("t"),
        rev = ((store().goal and store().goal.rev) or 0) + 1,
        title = title, amount = amount, deadline = deadline,
        note = clean(fields.note, NOTE_LEN),
        by = identity.name and Util.ShortName(identity.name) or "?",
        ts = Util.Now(),
        start = fresh and Util.Now() or old.start,
        baseline = fresh and (tonumber(bank.money) or 0) or (old.baseline or 0),
    }
    store().goal = goal
    GA.Core.Database:Journal("TREASURY_GOAL", goal.id, old and old.amount or nil, amount)
    GA.Core.Callbacks:Fire("TREASURY_CHANGED")
    self:Publish()
    return goal
end

--- Hebt das Ziel auf. Der Datensatz bleibt als "aufgehoben" mit seiner
--- Fassung stehen, damit eine aeltere Fassung von anderswo es nicht
--- wiederbelebt.
function Treasury:RemoveGoal()
    if not self:CanEdit() then return false, "notallowed" end
    local goal = store().goal
    if not goal then return true end
    goal.removed = true
    goal.rev = (goal.rev or 0) + 1
    goal.ts = Util.Now()
    GA.Core.Database:Journal("TREASURY_GOAL", goal.id, goal.amount, nil)
    GA.Core.Callbacks:Fire("TREASURY_CHANGED")
    self:Publish()
    return true
end

-- ============================================================ Einzahlen ----

--- Das Kleingeld unter dem naechsten vollen Gold — oder nil, wenn keins.
function Treasury:SmallChange()
    local money = Compat.GetMoney()
    if not money then return nil end
    local rest = money % 10000
    return rest > 0 and rest or nil
end

--- Einzahlen aus dem Addon heraus. Ob der Client das aus Addon-Code
--- zulaesst, ist auf Forever UNGEMESSEN (Sonde "guildBankDeposit"): Geht
--- es nicht, sagt die Rueckgabe das, und der Betrag steht zum Abtippen da.
--- @return boolean ok, string|nil grund ("closed" | "noapi" | "blocked" | "amount" | "poor")
function Treasury:Deposit(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return false, "amount" end
    if not (GA.Modules.GuildBank and GA.Modules.GuildBank.open) then return false, "closed" end
    local own = Compat.GetMoney()
    if own and own < copper then return false, "poor" end
    local ok, why = Compat.DepositGuildBankMoney(copper)
    if ok then
        GA.Core.Database:Journal("TREASURY_DEPOSIT", nil, nil, copper)
        Debug:Print("bank", "Einzahlung angestossen: %d Kupfer", copper)
    end
    return ok, why
end

-- ============================================================== Teilen -----

local function goalFields(goal)
    return { goal.id, goal.rev, goal.amount, goal.deadline or 0, goal.baseline or 0, goal.start or 0,
             goal.by or "", goal.removed and 1 or 0, goal.title or "", goal.note or "" }
end

function Treasury:Publish()
    local Comm = GA.Core.Comm
    local goal = store().goal
    if not Comm or not goal or not Compat.IsInGuild() then return false end
    return Comm:Send("TGOAL", goalFields(goal), "GUILD", nil, true) and true or false
end

--- Ein Ziel von jemand anderem: genommen, wenn es eine hoehere Fassung ist.
function Treasury:OnGoal(sender, fields)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local id, rev, amount = fields[1], tonumber(fields[2]), tonumber(fields[3])
    if not id or id == "" or not rev or not amount then return end
    local mine = store().goal
    if mine and mine.id == id and (mine.rev or 0) >= rev then return end
    -- Ein anderes Ziel mit niedrigerer Fassung als meines: das aeltere
    -- Geraet hat die Aufhebung oder das neue Ziel noch nicht. Meins gilt.
    if mine and mine.id ~= id and (mine.ts or 0) > Util.Now() - 60 then return end
    local wasReached = self:Progress() and self:Progress().state == "reached"
    store().goal = {
        id = id, rev = rev, amount = amount,
        deadline = tonumber(fields[4]) ~= 0 and tonumber(fields[4]) or nil,
        baseline = tonumber(fields[5]) or 0, start = tonumber(fields[6]) or Util.Now(),
        by = fields[7] ~= "" and fields[7] or Util.ShortName(sender),
        removed = fields[8] == "1" or nil,
        title = clean(fields[9], TITLE_LEN), note = clean(fields[10], NOTE_LEN),
        ts = Util.Now(),
    }
    self.heard = rev
    GA.Core.Callbacks:Fire("TREASURY_CHANGED")
    self:CheckReached(wasReached)
end

--- Jemand fragt nach dem Ziel. Nur wer Neueres hat, antwortet — gestreut.
function Treasury:OnRequest(sender, fields)
    local Comm = GA.Core.Comm
    if Comm and Comm:IsSelf(sender) then return end
    local goal = store().goal
    if not goal then return end
    local theirId, theirRev = fields[1] or "", tonumber(fields[2]) or 0
    if theirId == goal.id and theirRev >= (goal.rev or 0) then return end
    Compat.After(2 + math.random() * 8, function()
        local now = store().goal
        if not now or (Treasury.heard or 0) >= (now.rev or 0) and theirId == now.id then return end
        Treasury:Publish()
    end)
end

function Treasury:Request()
    local Comm = GA.Core.Comm
    if not Comm or not Compat.IsInGuild() then return false end
    local goal = store().goal
    return Comm:Send("TGREQ", { goal and goal.id or "", goal and goal.rev or 0 }, "GUILD", nil, true) and true or false
end

--- Einmal je Ziel sagen, dass es erreicht ist.
function Treasury:CheckReached(wasReached)
    local goal = self:Goal()
    local progress = self:Progress()
    if not goal or not progress or progress.state ~= "reached" then return end
    if wasReached or goal.announced then return end
    goal.announced = true
    if GA.UI.MainFrame and GA.UI.MainFrame.Notice then
        GA.UI.MainFrame:Notice("info", GA.L.TR_REACHED_NOTICE, goal.title)
    end
end

-- ================================================================ Start -----

function Treasury:OnEnable()
    local Comm = GA.Core.Comm
    if Comm then
        Comm:On("TGOAL", function(sender, fields) Treasury:OnGoal(sender, fields) end, "Treasury")
        Comm:On("TGREQ", function(sender, fields) Treasury:OnRequest(sender, fields) end, "Treasury")
    end
    GA.Core.Callbacks:On("GUILD_BANK_CHANGED", function()
        Treasury:CheckReached(false)
        GA.Core.Callbacks:Fire("TREASURY_CHANGED")
    end, "Treasury")
    Compat.After(REQUEST_DELAY, function() Treasury:Request() end)
end
