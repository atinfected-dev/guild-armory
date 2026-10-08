--[[----------------------------------------------------------------------------
    Assist/Merchant — beim Haendler: Schrott verkaufen, reparieren.

    Zwei Schalter in den Einstellungen (08.10.2026), beide aus, bis jemand
    sie will: Ein Addon, das ungefragt verkauft, ist eines, dem man nicht
    traut. Ein dritter Schalter laesst die Reparatur zuerst aus der
    Gildenbank bezahlen, wo der Rang das erlaubt.

    SCHROTT heisst grau (Qualitaet 0) mit Verkaufswert, nicht gesperrt.
    Verkauft wird mit UseContainerItem bei OFFENEM Haendler — dieselbe
    Funktion legt sonst an oder verbraucht, deshalb prueft diese Datei den
    Zustand selbst (MERCHANT_SHOW / MERCHANT_CLOSED) und ruft nie ausserhalb.

    REPARATUR wie Blizzards Haendlerfenster: Kosten und Moeglichkeit von
    GetRepairAllCost, dann RepairAllItems. Ob die Gilde zahlen darf, weiss
    der Client vorher nicht verlaesslich; also erst ueber die Gilde
    versuchen und an den Restkosten sehen, was uebrig blieb.
------------------------------------------------------------------------------]]

local _, GA = ...

local Merchant = {}
GA.Modules.Merchant = Merchant

local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

local GUILD_SETTLE = 1      -- Sekunden, bis der Server die Gildenreparatur verbucht hat

local function config(key)
    return GA.Core.Config:Get(key) and true or false
end

local function notice(kind, format, ...)
    if GA.UI.MainFrame and GA.UI.MainFrame.Notice then GA.UI.MainFrame:Notice(kind, format, ...)
    else Debug:Info(format, ...) end
end

local function money(copper)
    local T = GA.Modules.Treasury
    if T and T.Money then return T.Money(copper) end
    return string.format("%dg", math.floor((copper or 0) / 10000))
end

-- ================================================================ Schrott ---

--- Grau, mit Wert, nicht gesperrt.
function Merchant.IsJunk(info)
    return info ~= nil and info.quality == 0 and not info.hasNoValue and not info.isLocked
end

--- Was der Schrott in den Taschen bringt.
--- @return number kupfer, number stuecke
function Merchant:JunkValue()
    local total, count = 0, 0
    Compat.ForEachBagItem(function(_, _, info)
        if Merchant.IsJunk(info) then
            local item = Compat.GetItemInfo(info.itemID)
            total = total + (item and item.sellPrice or 0) * (info.stackCount or 1)
            count = count + 1
        end
    end)
    return total, count
end

--- Verkauft allen Schrott. Nur bei offenem Haendler.
--- @return number stuecke, number kupfer
function Merchant:SellJunk()
    if not self.open then return 0, 0 end
    local total, count = 0, 0
    Compat.ForEachBagItem(function(bag, slot, info)
        if Merchant.IsJunk(info) then
            local item = Compat.GetItemInfo(info.itemID)
            if Compat.SellContainerItem(bag, slot) then
                total = total + (item and item.sellPrice or 0) * (info.stackCount or 1)
                count = count + 1
            end
        end
    end)
    if count > 0 then notice("info", GA.L.MERCHANT_SOLD, count, money(total)) end
    return count, total
end

-- ================================================================ Reparatur -

local function repairPersonally(cost)
    local own = Compat.GetMoney() or 0
    if own < cost then
        notice("warn", GA.L.MERCHANT_REPAIR_POOR, money(cost))
        return false
    end
    if Compat.RepairAllItems(false) then
        notice("info", GA.L.MERCHANT_REPAIRED, money(cost))
        return true
    end
    return false
end

--- Repariert alles — zuerst aus der Gildenbank, wenn gewuenscht und erlaubt.
--- @return boolean angestossen
function Merchant:Repair()
    if not self.open or not Compat.CanMerchantRepair() then return false end
    local cost, can = Compat.GetRepairAllCost()
    if not can or not cost or cost <= 0 then return false end

    if config("autoRepairGuild") and Compat.CanGuildBankRepair() then
        if not Compat.RepairAllItems(true) then return repairPersonally(cost) end
        Compat.After(GUILD_SETTLE, function()
            if not Merchant.open or not Compat.CanMerchantRepair() then return end
            local left = Compat.GetRepairAllCost() or 0
            if left < cost then notice("info", GA.L.MERCHANT_REPAIRED_GUILD, money(cost - left)) end
            if left > 0 then repairPersonally(left) end
        end)
        return true
    end
    return repairPersonally(cost)
end

-- ================================================================ Start -----

function Merchant:OnShow()
    self.open = true
    if config("autoRepair") then self:Repair() end
    if config("autoSellJunk") then self:SellJunk() end
end

function Merchant:OnClose()
    self.open = false
end

function Merchant:OnEnable()
    local Events = GA.Core.Events
    Events:Register("MERCHANT_SHOW", function() Merchant:OnShow() end, "Merchant")
    Events:Register("MERCHANT_CLOSED", function() Merchant:OnClose() end, "Merchant")
end
