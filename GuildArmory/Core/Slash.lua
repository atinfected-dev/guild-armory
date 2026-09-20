--[[----------------------------------------------------------------------------
    Slash — /ga

        /ga                Fenster umschalten
        /ga armory         Direkt zu einer Ansicht
        /ga scale 0.9      Fensterskalierung
        /ga debug [kanal]  Debug umschalten
        /ga status         Diagnose
        /ga capture        Ausruestung jetzt erfassen
        /ga minimap        Minimap-Knopf ein-/ausblenden
        /ga sync           Abgleich anstossen und Gegenstellen zeigen
        /ga export         Exportstand aufbauen (/ga export show = Kopierfenster)
        /ga import         Sicherung einlesen (/ga import own = aus dieser Datei)
        /ga reset          Datenbank zuruecksetzen (zweistufig)
------------------------------------------------------------------------------]]

local _, GA = ...

local Debug = GA.Core.Debug

local VIEWS = {
    dashboard = "dashboard", armory = "armory", chars = "characters",
    characters = "characters", loot = "lootcouncil", council = "lootcouncil",
    history = "loothistory", wishlist = "wishlist", gear = "gear",
    analytics = "analytics", settings = "settings",
}

local pendingReset

--- Was dieser Client kann, in Worten statt in Wahrheitswerten.
---
--- Stand bis Phase 9 im Einstellungsfenster. Das Fenster ist weg, die
--- Erklaerungen sind es nicht: Compat.Describe() liefert nur `key true`, und
--- damit weiss niemand, was ein fehlendes `masterLootApi` praktisch bedeutet.
local CAPABILITIES = {
    { key = "masterLootApi",  label = "Pluendermeister-API",
      good = "GiveMasterLoot vorhanden — ob 'master' waehlbar ist, zeigt die Gruppe.",
      bad  = "Keine Zuweisung durch das Addon moeglich; Uebergabe per Handel." },
    { key = "tradeApi",       label = "Handels-API",
      good = "Uebergaben per Handel koennen bestaetigt werden.",
      bad  = "Handelsbestaetigung nicht verfuegbar — nur manuell." },
    { key = "guildRoster",    label = "Gildenroster",
      good = "Gildenmitglieder werden erfasst.",
      bad  = "Kein Zugriff auf das Gildenroster." },
    { key = "inspect",        label = "Inspect",
      good = "Fremde Ausruestung in Reichweite lesbar.",
      bad  = "Nur die eigene Ausruestung." },
    { key = "itemLevelApi",   label = "Itemlevel je Item",
      good = "C_Item.GetDetailedItemLevelInfo — Itemlevel wird selbst berechnet.",
      bad  = "Rueckfall auf GetItemInfo." },
    { key = "tooltipProcessor", label = "Tooltip-Erweiterung",
      good = "TooltipDataProcessor — Guild-Armory-Zeilen im Item-Tooltip moeglich.",
      bad  = "Rueckfall auf HookScript." },
    { key = "chatInfo",       label = "Addon-Nachrichten",
      good = "C_ChatInfo verfuegbar.",
      bad  = "Keine Synchronisation moeglich." },
    { key = "multipleSpecs",  label = "Mehrere Specs je Klasse",
      good = "Rolle aus der Spec ableitbar.",
      bad  = "Eine Spec je Klasse (gemessen) — Rolle nicht aus der Spec ableiten." },
}

local function handleReset(scope)
    scope = scope or "all"
    if pendingReset ~= scope then
        pendingReset = scope
        local stats = GA.Core.Database:Stats()
        Debug:Warn("Zuruecksetzen von \"%s\" — loescht %d Charaktere und %d Vergaben.",
            scope, stats.characters, stats.awards)
        Debug:Info("Zum Bestaetigen noch einmal: /ga reset %s", scope)
        GA.Core.Compat.After(15, function()
            if pendingReset == scope then pendingReset = nil Debug:Info("Abgelaufen, nichts geaendert.") end
        end)
        return
    end
    pendingReset = nil
    if GA.Core.Database:Reset(scope) then Debug:Info("Zurueckgesetzt: %s", scope)
    else Debug:Info("Unbekannter Bereich: %s (all, ui, characters)", scope) end
end

SLASH_GUILDARMORY1 = "/ga"
SLASH_GUILDARMORY2 = "/guildarmory"

SlashCmdList["GUILDARMORY"] = function(input)
    input = string.lower(string.gsub(input or "", "^%s+", ""))
    local command, rest = string.match(input, "^(%S*)%s*(.*)$")
    local MainFrame = GA.UI.MainFrame

    if command == "" then MainFrame:Toggle()
    elseif command == "show" then MainFrame:Show()
    elseif command == "hide" then MainFrame:Hide()
    elseif VIEWS[command] then MainFrame:Show() MainFrame:ShowView(VIEWS[command])
    elseif command == "scale" then
        local value = tonumber(rest)
        if value then Debug:Info("Skalierung: %.2f", MainFrame:SetScale(value))
        else Debug:Info("Aktuelle Skalierung: %.2f", GA.Core.Config:GetUI("main").scale or 1) end
    elseif command == "debug" then
        if rest ~= "" then Debug:ToggleChannel(rest) else Debug:Toggle() end
    elseif command == "status" then
        local stats = GA.Core.Database:Stats()
        Debug:Info("Version %s, Schema %s, Sprache %s", GA.version,
            tostring(stats.schemaVersion), tostring(GA.Core.Locale.active))
        local storage = GA.Core.Database.storage or {}
        Debug:Info("Speicherquelle: %s%s", tostring(storage.source),
            storage.accountLoaded and "" or
            "  (die kontoweite Datei kam nicht an — Spiegel in der Charakterdatei)")
        Debug:Info("%d Charaktere, %d Vergaben, %d Sessions, %d Journaleintraege",
            stats.characters, stats.awards, stats.sessions, stats.journal)
        for _, capability in ipairs(CAPABILITIES) do
            local value = GA.has[capability.key]
            Debug:Info("  %s %-22s %s", value and "+" or "-", capability.label,
                value and capability.good or capability.bad)
        end
        Debug:Info("Fenstervorlagen: %s", GA.UI.Theme.DescribeNative())
    elseif command == "capture" then
        GA.Modules.Equipment:Capture("Befehl")
        Debug:Info("Ausruestung erfasst.")
    elseif command == "minimap" then
        local shown = GA.UI.MinimapButton:SetShown(nil)
        Debug:Info("Minimap-Knopf: %s", shown and "an" or "aus")
    elseif command == "sync" then
        local Sync = GA.Modules.Sync
        Sync:Hello()
        local ok, reason = Sync:PublishAll()
        Debug:Info("Abgleich: %d Clients bekannt, %d Widersprueche%s",
            Sync:PeerCount(), Sync.conflicts or 0,
            ok and "" or (" — nichts gesendet (" .. tostring(reason or "Freigabe aus") .. ")"))
        for name, peer in pairs(Sync.peers) do
            Debug:Info("  %s  Addon %s, Protokoll %s", name,
                tostring(peer.addon), tostring(peer.version))
        end
    elseif command == "export" then
        if rest == "show" then GA.Core.Export:ShowDialog()
        else GA.Core.Export:Refresh(true) end
    elseif command == "import" then
        GA.UI.ImportDialog:Open(rest)
    elseif command == "rotate" then
        local Rotation = GA.Modules.Rotation
        if rest == "clear" then
            Debug:Info("%d Sitze beendet.", Rotation:ClearAll(
                GA.Core.Compat.GetPlayerIdentity().guid))
        elseif rest == "status" then
            local active = Rotation:Active()
            local done, total = Rotation:CycleProgress()
            Debug:Info("Sitze auf Zeit: %d · Zyklus %d von %d", #active, done, total)
            for _, seat in ipairs(active) do
                Debug:Info("  %s  noch %d min", tostring(seat.name),
                    math.max(0, math.floor((seat.expires - GA.Core.Util.Now()) / 60)))
            end
        else
            local ok, result = Rotation:Rotate({ seats = tonumber(rest) })
            if not ok then
                Debug:Info("%s", GA.L["ROTATION_ERR_" .. string.upper(tostring(result))]
                    or tostring(result))
            else
                local names = {}
                for _, entry in ipairs(result) do names[#names + 1] = entry.name end
                Debug:Info(GA.L.ROTATION_DONE, table.concat(names, ", "))
            end
        end
    elseif command == "roll" then
        local Rolls = GA.Modules.Rolls
        if rest == "close" or rest == "ende" then
            local ok = Rolls:Close("von Hand")
            Debug:Info("%s", ok and "Wurfrunde beendet." or GA.L.ROLL_IDLE)
        elseif rest == "" and Rolls.current then
            local list = Rolls:Results()
            local winner, tied = Rolls:Winner()
            Debug:Info(GA.L.ROLL_COUNT, #list, #Rolls:Missing())
            for _, entry in ipairs(list) do
                Debug:Info("  %-16s %d", tostring(entry.name), entry.roll)
            end
            if winner then
                Debug:Info(GA.L.ROLL_WINNER, winner.name, winner.roll)
            elseif #tied > 1 then
                local namen = {}
                for _, entry in ipairs(tied) do namen[#namen + 1] = entry.name end
                Debug:Info(GA.L.ROLL_TIE, tied[1].roll, table.concat(namen, ", "))
                Debug:Info("%s", GA.L.ROLL_TIE_HINT)
            end
        else
            -- "/ga roll <item> [sekunden]" — der Gegenstand darf ein Link,
            -- eine Wowhead-Adresse, eine ID oder ein Name sein. Dieselbe
            -- Eingabe wie bei der Wunschliste, damit niemand zwei Formate
            -- lernen muss.
            local text, seconds = string.match(rest, "^(.-)%s+(%d+)$")
            text = text or rest
            local parsed = text ~= "" and GA.Core.Compat.ParseItemInput(text) or nil

            local ok, result = Rolls:Open({
                itemID = parsed and parsed.itemID,
                itemName = parsed and parsed.name or (text ~= "" and text or nil),
                itemLink = parsed and parsed.link,
                seconds = tonumber(seconds),
            })
            if not ok then
                Debug:Info("%s", GA.L["ROLL_ERR_" .. string.upper(tostring(result))]
                    or tostring(result))
            else
                Rolls:Announce()
                Debug:Info(GA.L.ROLL_RUNNING,
                    tostring(result.itemName or result.itemID or "?"), result.min, result.max)
            end
        end
    elseif command == "sr" or command == "reserve" then
        local SoftRes = GA.Modules.SoftRes
        local identity = GA.Core.Compat.GetPlayerIdentity()
        if rest == "open" then
            local ok, result = SoftRes:Open({})
            Debug:Info("%s", ok and GA.L.SOFTRES_TITLE
                or (GA.L["SOFTRES_ERR_" .. string.upper(tostring(result))] or tostring(result)))
        elseif rest == "close" then
            Debug:Info("%s", SoftRes:Close(identity.guid) and "Runde beendet."
                or GA.L.SOFTRES_NONE)
        elseif string.sub(rest, 1, 3) == "add" then
            -- Der Weg fuer SPIELER: anmelden, nicht eintragen. Die Runde
            -- liegt beim Lootmeister, also geht das ueber eine Nachricht und
            -- kommt als Antwort zurueck.
            local text = string.match(rest, "^add%s+(.+)$")
            local parsed = text and GA.Core.Compat.ParseItemInput(text)
            if not parsed or not parsed.itemID then
                Debug:Info("Gegenstand nicht erkannt: %s", tostring(text))
            else
                local ok, grund = SoftRes:Claim(parsed.itemID)
                if not ok then
                    Debug:Info("%s", GA.L["SOFTRES_ERR_" .. string.upper(tostring(grund)) .. "2"]
                        or tostring(grund))
                end
            end
        elseif string.sub(rest, 1, 3) == "del" then
            local text = string.match(rest, "^del%s+(.+)$")
            local parsed = text and GA.Core.Compat.ParseItemInput(text)
            SoftRes:Unclaim(parsed and parsed.itemID)
        elseif rest == "mine" then
            local mine = SoftRes:Of(identity.name)
            if #mine == 0 then
                Debug:Info("%s", GA.L.SOFTRES_NONE)
            end
            for _, entry in ipairs(mine) do
                Debug:Info("  %s (%s)", tostring(entry.itemName or entry.itemID),
                    entry.origin == "claim" and GA.L.SOFTRES_ORIGIN_CLAIM
                        or GA.L.SOFTRES_ORIGIN_LIST)
            end
        elseif string.sub(rest, 1, 6) == "import" then
            -- Eigenes Eingabefenster, nicht der Export-Import: Das eine liest
            -- eine Sicherung, das andere eine Namensliste. Beides in einen
            -- Dialog zu legen waere eine Falle.
            GA.UI.Widgets.InputDialog(GA.L.SOFTRES_TITLE,
                "Anna: Thunderfury, 18348\nBert = 19019",
                function(text)
                    local report = SoftRes:Import(text)
                    Debug:Info(GA.L.SOFTRES_IMPORTED, report.added, #report.skipped)
                    for _, entry in ipairs(report.skipped) do
                        Debug:Info("  ? %s (%s)", tostring(entry.line), tostring(entry.reason))
                    end
                end)
        else
            local stats = SoftRes:Stats()
            if not SoftRes:Current() then
                Debug:Info("%s", GA.L.SOFTRES_NONE)
            else
                Debug:Info(GA.L.SOFTRES_STATS, stats.entries, stats.players, stats.contested)
                for _, entry in ipairs(SoftRes:Contested()) do
                    Debug:Info("  %s  %s: %s", GA.L.SOFTRES_CONTESTED,
                        tostring(entry.itemName or entry.itemID),
                        table.concat(entry.names, ", "))
                end
                for _, entry in ipairs(SoftRes:OverLimit()) do
                    Debug:Info("  %s  %s (%d)", GA.L.SOFTRES_OVERLIMIT, entry.name, entry.count)
                end
                Debug:Info("%s", GA.L.SOFTRES_HINT)
            end
        end
    elseif command == "plusone" or command == "p1" then
        local PlusOne = GA.Modules.PlusOne
        local list = PlusOne:List()
        if #list == 0 then
            Debug:Info("Keine Spielerprofile.")
        end
        for _, entry in ipairs(list) do
            Debug:Info(GA.L.PLUSONE_ROW, entry.name, entry.total, entry.counted, entry.offset)
            if entry.manual > 0 then
                Debug:Info("    " .. GA.L.PLUSONE_MANUAL_HINT, entry.manual)
            end
        end
        Debug:Info("%s", GA.L.PLUSONE_HINT)
    elseif command == "atlas" then
        local Atlas = GA.Modules.AtlasBridge
        local stats = Atlas:Stats()
        if not stats.available then
            Debug:Info("%s", GA.L.ATLAS_MISSING)
        elseif rest == "" and stats.harvested then
            Debug:Info(GA.L.ATLAS_STATS, stats.sources, stats.known)
        else
            local ok, grund = Atlas:Harvest()
            if not ok then Debug:Info("AtlasLoot: %s", tostring(grund)) end
        end
    elseif command == "version" then
        local V = GA.Modules.VersionCheck
        V:Start(rest ~= "" and string.upper(rest) or nil)
        Debug:Info("%s", GA.L.VERSION_RUNNING)
        GA.Core.Compat.After(11, function()
            local list, counts = V:Result()
            Debug:Info(GA.L.VERSION_SUMMARY, counts.current, counts.outdated, counts.silent)
            for _, entry in ipairs(list) do
                Debug:Info("  %-16s %-14s %s", tostring(entry.name),
                    tostring(GA.L["VERSION_" .. string.upper(entry.status)] or entry.status),
                    tostring(entry.version or ""))
            end
            if counts.silent > 0 then Debug:Info("%s", GA.L.VERSION_SILENT_HINT) end
        end)
    elseif command == "handover" then
        local carrying, missing = GA.Modules.Handover:Pending()
        if #carrying == 0 and #missing == 0 then
            Debug:Info("%s", GA.L.HANDOVER_NONE)
        end
        for _, entry in ipairs(carrying) do
            Debug:Info("  %s  %s  → %s (Tasche %d, Platz %d)", GA.L.HANDOVER_CARRYING,
                tostring(entry.link or entry.itemID), tostring(entry.to),
                entry.bag, entry.slot)
        end
        for _, entry in ipairs(missing) do
            Debug:Info("  %s  %s  → %s", GA.L.HANDOVER_MISSING,
                tostring(entry.itemID), tostring(entry.to))
        end
        if #missing > 0 then Debug:Info("%s", GA.L.HANDOVER_MISSING_HINT) end
    elseif command == "reset" then handleReset(rest ~= "" and rest or "all")
    else
        Debug:Info("Befehle: /ga · armory · scale · debug · status · capture · minimap · sync · export · import · rotate · roll · sr · plusone · atlas · version · handover · reset")
    end
end

