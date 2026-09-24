--[[----------------------------------------------------------------------------
    UI/Tooltips — Guild-Armory-Daten dort zeigen, wo man hinschaut.

    Zwei Stellen:

      GEGENSTAND  Wer aus der Gilde hat ihn auf der Wunschliste, und wurde er
                  schon einmal vergeben?
      SPIELER     Itemlevel, letzte Vergabe, Spitzname, seit wann bekannt.

    JEDE ZEILE SAGT, WIE ALT IHRE DATEN SIND. Ein Tooltip sieht aus wie eine
    Live-Auskunft; ohne Zeitangabe wuerde ein drei Wochen alter Inspect-Stand
    wie der aktuelle wirken. Deshalb steht bei fremden Daten immer dabei, woher
    sie kommen und wann sie erfasst wurden.

    ANGEBUNDEN WIRD UEBER TooltipDataProcessor (gemessen vorhanden, 19.09.2026)
    mit Rueckfall auf HookScript. Schlaegt beides fehl, bleiben die Tooltips
    einfach so, wie sie waren — das Addon funktioniert weiter.
------------------------------------------------------------------------------]]

local _, GA = ...

local Tooltips = {}
GA.UI.Tooltips = Tooltips

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local L = GA.L

local PREFIX = "|cffe5cc80GA|r "

-- ================================================================== Gegenstand

--- Ergaenzt einen Item-Tooltip.
function Tooltips:OnItem(tooltip, itemID)
    if not itemID or not GA.Core.Config:Get("tooltipItems") then return end

    -- Wunschliste: wer haette ihn gern?
    local wanted = GA.Modules.Wishlist:ForItem(itemID)
    local open = {}
    for _, entry in ipairs(wanted) do
        if not entry.fulfilled then open[#open + 1] = entry end
    end

    if #open > 0 then
        tooltip:AddLine(" ")
        -- Hoechstens fuenf Namen: Ein Tooltip, der den halben Bildschirm
        -- fuellt, wird nicht gelesen.
        local names = {}
        for index = 1, math.min(#open, 5) do
            local entry = open[index]
            local priority = GA.Modules.Wishlist:PriorityByKey(entry.priority)
            names[#names + 1] = string.format("%s (%s)",
                Util.ColorByClass(entry.name, entry.class),
                priority and priority.label or entry.priority)
        end
        tooltip:AddLine(PREFIX .. L.TIP_WISHED, 0.90, 0.80, 0.50)
        for _, line in ipairs(names) do tooltip:AddLine("  " .. line, 1, 1, 1) end
        if #open > 5 then
            tooltip:AddLine(string.format("  " .. L.TIP_AND_MORE, #open - 5), 0.5, 0.5, 0.5)
        end
    end

    -- Tauschbar? Die Zeile steht NUR bei eigenen Beutelstuecken, die in
    -- Frage kommen — bei jedem Gegenstand im Spiel waere sie Rauschen.
    --
    -- SIE IST KEIN KNOPF. Ein WoW-Tooltip zeigt Text und verschwindet; man
    -- kann darin nichts anklicken. Deshalb sagt die Zeile, was ein Alt-Klick
    -- im Beutel tut, und der Klick landet in Armory/Tradables.
    local Tradables = GA.Modules.Tradables
    if Tradables and Tradables:IsCandidate(itemID) then
        local offered = Tradables:IsOffered(itemID)
        tooltip:AddLine(PREFIX .. (offered and L.TIP_TRADE_ON or L.TIP_TRADE_OFF),
            offered and 0.37 or 0.66, offered and 0.79 or 0.61, offered and 0.63 or 0.52)
        tooltip:AddLine("  " .. (offered and L.TIP_TRADE_HINT_OFF or L.TIP_TRADE_HINT_ON),
            0.5, 0.5, 0.5)
    end

    -- Wer kann das herstellen?
    --
    -- Die Zeile steht nur, wenn es wirklich jemanden gibt. "Niemand kann
    -- das herstellen" waere eine Behauptung ueber alle, die noch nie ihr
    -- Berufsfenster geoeffnet haben — und das sind am Anfang alle.
    local Crafting = GA.Modules.Crafting
    if Crafting then
        local crafters = Crafting:Crafters(itemID)
        if #crafters > 0 then
            tooltip:AddLine(PREFIX .. L.TIP_CRAFTED_BY, 0.37, 0.79, 0.63)
            for index = 1, math.min(#crafters, 5) do
                local crafter = crafters[index]
                tooltip:AddLine(string.format("  %s (%s %d)", crafter.name,
                    crafter.lineName or tostring(crafter.line), crafter.rank or 0),
                    1, 1, 1)
            end
            if #crafters > 5 then
                tooltip:AddLine(string.format("  " .. L.TIP_AND_MORE, #crafters - 5),
                    0.5, 0.5, 0.5)
            end
        end
    end

    -- Wurde er schon einmal vergeben?
    local awards = GA.Modules.Awards:List({ itemID = itemID })
    local last
    for _, award in ipairs(awards) do
        if award.recipientName then last = award break end
    end
    if last then
        tooltip:AddLine(string.format(PREFIX .. L.TIP_LAST_AWARD,
            Util.ShortName(last.recipientName), Util.TimeAgo(last.ts)), 0.66, 0.61, 0.52)
    end
end

--- Ruft einen Tooltip-Ergaenzer auf und schaltet ihn nach dem ersten Fehler ab.
---
--- Kein Verstecken von Fehlern: Der Fehler wird gemeldet, EINMAL, mit der
--- betroffenen Stelle. Nur die Wiederholung wird unterbunden — und die ist
--- hier das eigentliche Problem, weil der Rueckruf an der Maus haengt.
function Tooltips:Guarded(method, tooltip, value)
    if self.disabled then return end

    local ok, err = pcall(self[method], self, tooltip, value)
    if not ok then
        self.disabled = true
        GA.Core.Debug:Warn("Tooltip-Ergaenzung abgeschaltet nach Fehler in %s: %s",
            method, tostring(err))
    end
end

-- ================================================================== Spieler ---

--- Ergaenzt einen Einheiten-Tooltip, wenn die Einheit ein bekannter Charakter ist.
---
--- NIMMT EINE GUID, KEINEN UNIT-TOKEN — und das ist keine Geschmacksfrage.
---
--- Gemessen 20.09.2026 im Spiel: Der Client gibt den Unit-Token eines
--- Tooltips als "secret value" heraus. Ihn an UnitIsPlayer oder UnitGUID
--- weiterzureichen bricht mit
---
---   "Secret values are only allowed during untainted execution"
---
--- und zwar bei jedem Tooltip unter dem Mauszeiger, also im Sekundentakt.
---
--- Die GUID braucht diese Aufrufe gar nicht: Sie traegt die Art der Einheit
--- in sich ("Player-...", "Creature-..."), und Compat.ParseGUID liest sie
--- heraus. Damit faellt die eingeschraenkte Funktion weg, statt umgangen zu
--- werden — der Fehler kann nicht wiederkommen, weil der Aufruf nicht mehr
--- existiert.
function Tooltips:OnUnit(tooltip, guid)
    -- Ein Tooltip-Rueckruf laeuft bei jeder Mausbewegung. Ein Fehler darin
    -- ist deshalb kein einzelner Fehler, sondern eine Flut — der gemeldete
    -- kam im Sekundentakt. Nach dem ersten Fehler schaltet sich die
    -- Anreicherung ab und sagt einmal Bescheid, statt das Chatfenster
    -- zuzuschuetten.
    if self.disabled then return end

    if type(guid) ~= "string" or not GA.Core.Config:Get("tooltipPlayers") then return end

    -- Kein UnitIsPlayer: Die GUID sagt es selbst.
    local kind = GA.Core.Compat.ParseGUID(guid)
    if kind ~= "Player" then return end

    local character = GA.Core.Database.account.characters[guid]

    -- Auch ohne Charakterdatensatz kann ein Spitzname da sein.
    local nickname = GA.Modules.Notes:GetNickname(guid)
    local note = GA.Modules.Notes:GetNote(guid)

    if not character and not nickname and not note then return end

    tooltip:AddLine(" ")

    if nickname then
        tooltip:AddLine(PREFIX .. nickname, 0.90, 0.80, 0.50)
    end

    if character then
        local level = character.itemLevel and character.itemLevel.value
        if level then
            -- Die Quelle steht DANEBEN, nicht im Kleingedruckten: Ein
            -- Inspect-Stand von letzter Woche ist keine Live-Auskunft.
            local age = character.equipmentTs and Util.TimeAgo(character.equipmentTs) or "?"
            local source = character.source and L["SOURCE_" .. character.source] or L.UNKNOWN
            tooltip:AddLine(string.format(PREFIX .. L.TIP_ILVL, level, source, age),
                0.66, 0.61, 0.52)
        end

        local awards = GA.Modules.Awards:List({ recipientGuid = guid })
        if #awards > 0 then
            local item = GA.Modules.ItemIndex:Get(awards[1].itemID)
            tooltip:AddLine(string.format(PREFIX .. L.TIP_LAST_LOOT,
                (item and item.name) or awards[1].itemName or "?",
                Util.TimeAgo(awards[1].ts)), 0.66, 0.61, 0.52)
        end
    end

    if note then
        tooltip:AddLine("  " .. note, 0.44, 0.40, 0.33, true)
    end
end

-- ================================================================== Anbindung

function Tooltips:Hook()
    local processor = _G.TooltipDataProcessor
    local enum = _G.Enum and _G.Enum.TooltipDataType

    if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function"
        and type(enum) == "table"
    then
        if enum.Item then
            pcall(processor.AddTooltipPostCall, enum.Item, function(tooltip)
                local info = tooltip.GetTooltipData and tooltip:GetTooltipData()
                local itemID = info and (info.id or (info.lines and info.lines[1]
                    and info.lines[1].tooltipID))
                if itemID then Tooltips:Guarded("OnItem", tooltip, itemID) end
            end)
            self.itemHooked = true
        end

        if enum.Unit then
            pcall(processor.AddTooltipPostCall, enum.Unit, function(tooltip, data)
                -- Die GUID kommt aus den Tooltipdaten, nicht aus GetUnit():
                -- Der Unit-Token ist ein secret value (siehe OnUnit).
                local guid = data and data.guid
                if not guid then
                    local info = tooltip.GetTooltipData and tooltip:GetTooltipData()
                    guid = info and info.guid
                end
                if guid then Tooltips:Guarded("OnUnit", tooltip, guid) end
            end)
            self.unitHooked = true
        end
    end

    -- Rueckfall fuer Einheiten, falls der moderne Weg nicht greift.
    if not self.unitHooked and _G.GameTooltip and GameTooltip.HookScript then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            local info = tooltip.GetTooltipData and tooltip:GetTooltipData()
            local guid = info and info.guid
            if guid then Tooltips:Guarded("OnUnit", tooltip, guid) end
        end)
        self.unitHooked = ok
    end

    GA.Core.Debug:Print("ui", "Tooltips: Gegenstand=%s, Spieler=%s",
        tostring(self.itemHooked), tostring(self.unitHooked))
end

GA.Core.Callbacks:On("ADDON_READY", function()
    Tooltips:Hook()
end, "Tooltips")
