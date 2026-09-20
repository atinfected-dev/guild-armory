--[[----------------------------------------------------------------------------
    Callbacks — internes Pub/Sub.

    Der Grund, warum es das gibt: Module duerfen kein UI kennen (Architekturregel 1),
    und Views duerfen keine Auswertungslogik enthalten (Regel 2). Ohne eine
    Vermittlungsschicht bleibt nur, dass Module die Views direkt aufrufen — und genau
    das erzeugt den Knoten, den man spaeter nicht mehr aufloest.

    Ablauf:
        Modul:  GA.Core.Callbacks:Fire("ROSTER_UPDATED")
        View:   GA.Core.Callbacks:On("ROSTER_UPDATED", function() self:Refresh() end)

    Die Views entscheiden selbst, ob sie ueberhaupt neu zeichnen (sichtbar? gedrosselt?).
    Das Modul weiss davon nichts.
------------------------------------------------------------------------------]]

local _, GA = ...

local Callbacks = {}
GA.Core.Callbacks = Callbacks

local listeners = {}

--- Registriert einen Empfaenger.
--- @param event string
--- @param handler function
--- @param owner any Optionale Kennung, um spaeter gezielt abzumelden.
function Callbacks:On(event, handler, owner)
    if type(handler) ~= "function" then
        error("Callbacks:On erwartet eine Funktion fuer " .. tostring(event), 2)
    end

    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
    end

    list[#list + 1] = { handler = handler, owner = owner }
end

--- Meldet alle Empfaenger eines Besitzers ab.
function Callbacks:Off(event, owner)
    local list = listeners[event]
    if not list then return end

    for index = #list, 1, -1 do
        if list[index].owner == owner then
            table.remove(list, index)
        end
    end
end

--- Loest ein Ereignis aus.
---
--- Jeder Empfaenger laeuft in pcall: Ein Fehler in einer View darf niemals
--- verhindern, dass die uebrigen Views ihre Benachrichtigung bekommen — und schon
--- gar nicht, dass das ausloesende Modul weiterarbeitet.
function Callbacks:Fire(event, ...)
    local list = listeners[event]
    if not list then return end

    for index = 1, #list do
        local entry = list[index]
        local ok, err = pcall(entry.handler, ...)
        if not ok then
            local Debug = GA.Core.Debug
            if Debug then
                Debug:Print("callbacks", "Fehler in Empfaenger fuer %s: %s", event, tostring(err))
            else
                print("|cffff5555GuildArmory|r Fehler in " .. tostring(event) .. ": " .. tostring(err))
            end
        end
    end
end

--- Nur fuer den Debug-Modus: Wer haengt an welchem Ereignis?
function Callbacks:Describe()
    local lines = {}
    for event, list in pairs(listeners) do
        lines[#lines + 1] = string.format("  %-26s %d Empfaenger", event, #list)
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end
