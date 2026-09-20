--[[----------------------------------------------------------------------------
    Config — Zugriff auf Einstellungen.

    Duenne Schicht ueber der Datenbank, damit der Rest des Addons nicht ueberall
    `GA.Core.Database.account.config.xyz` schreiben muss. Der eigentliche Nutzen ist
    aber ein anderer: Jede Aenderung feuert ein Callback, sodass Views reagieren
    koennen, ohne dass die Einstellungsansicht sie kennen muss.
------------------------------------------------------------------------------]]

local _, GA = ...

local Config = {}
GA.Core.Config = Config

function Config:Get(key)
    return GA.Core.Database.account.config[key]
end

function Config:Set(key, value)
    local config = GA.Core.Database.account.config
    if config[key] == value then return end

    config[key] = value
    GA.Core.Callbacks:Fire("CONFIG_CHANGED", key, value)
end

function Config:Toggle(key)
    self:Set(key, not self:Get(key))
    return self:Get(key)
end

--- Fensterzustand. Getrennt gehalten, weil er haeufig und ungefragt geschrieben wird.
function Config:GetUI(window)
    return GA.Core.Database.account.ui[window]
end
