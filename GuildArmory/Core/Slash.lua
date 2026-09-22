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
        /ga icons          Symbolpfade pruefen
        /ga reset          Datenbank zuruecksetzen (zweistufig)

    DIE BEFEHLSWOERTER SELBST BLEIBEN ENGLISCH. Sie sind Eingabe, keine
    Ausgabe: Wer "/ga sync" in einer Anleitung liest, muss es tippen koennen,
    egal welche Sprache im Fenster steht. Uebersetzt wird, was zurueckkommt.
------------------------------------------------------------------------------]]

local _, GA = ...

local Debug = GA.Core.Debug
local L = GA.L

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
---
--- Hier stehen nur die SCHLUESSEL. Die Texte kommen erst beim Ausgeben aus
--- GA.L — eine beim Laden gebaute Liste traegt sonst die Sprache, die beim
--- Laden galt (siehe Localization/Locale.lua).
local CAPABILITIES = {
    "masterLootApi", "tradeApi", "guildRoster", "inspect",
    "itemLevelApi", "tooltipProcessor", "chatInfo", "multipleSpecs",
}

local function handleReset(scope)
    scope = scope or "all"
    if pendingReset ~= scope then
        pendingReset = scope
        local stats = GA.Core.Database:Stats()
        Debug:Warn(L.SLASH_RESET_WARN, scope, stats.characters, stats.awards)
        Debug:Info(L.SLASH_RESET_CONFIRM, scope)
        GA.Core.Compat.After(15, function()
            if pendingReset == scope then
                pendingReset = nil
                Debug:Info("%s", L.SLASH_RESET_EXPIRED)
            end
        end)
        return
    end
    pendingReset = nil
    if GA.Core.Database:Reset(scope) then Debug:Info(L.SLASH_RESET_DONE, scope)
    else Debug:Info(L.SLASH_RESET_UNKNOWN, scope) end
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
        if value then Debug:Info(L.SLASH_SCALE_SET, MainFrame:SetScale(value))
        else Debug:Info(L.SLASH_SCALE_CURRENT, GA.Core.Config:GetUI("main").scale or 1) end
    elseif command == "debug" then
        if rest ~= "" then Debug:ToggleChannel(rest) else Debug:Toggle() end
    elseif command == "language" or command == "sprache" then
        -- Auch ohne Einstellungsfenster erreichbar: Wer die Sprache falsch
        -- gestellt hat, findet den Knopf sonst schlecht wieder.
        local Locale = GA.Core.Locale
        if rest ~= "" then
            local code = rest == "auto" and "auto"
                or (rest == "de" or rest == "dede") and "deDE"
                or (rest == "en" or rest == "enus") and "enUS"
                or nil
            if not code then
                Debug:Info(L.SLASH_LANGUAGE_UNKNOWN, rest)
            elseif Locale:Choose(code) then
                Debug:Info(L.SLASH_LANGUAGE_SET, code)
                Debug:Info("%s", L.SET_LANGUAGE_RELOAD)
            end
        end
        Debug:Info(L.SLASH_LANGUAGE_NOW, tostring(Locale.active),
            tostring(Locale.reason))
    elseif command == "status" then
        local stats = GA.Core.Database:Stats()
        Debug:Info(L.SLASH_STATUS_VERSION, GA.version, tostring(stats.schemaVersion),
            tostring(GA.Core.Locale.active), tostring(GA.Core.Locale.reason))
        local storage = GA.Core.Database.storage or {}
        Debug:Info(L.SLASH_STATUS_STORAGE, tostring(storage.source),
            storage.accountLoaded and "" or ("  " .. L.SLASH_STATUS_MIRROR))
        Debug:Info(L.SLASH_STATUS_COUNTS,
            stats.characters, stats.awards, stats.sessions, stats.journal)
        for _, key in ipairs(CAPABILITIES) do
            local value = GA.has[key]
            Debug:Info("  %s %-22s %s", value and "+" or "-",
                tostring(L["CAP_" .. key]),
                tostring(value and L["CAP_" .. key .. "_GOOD"] or L["CAP_" .. key .. "_BAD"]))
        end
        Debug:Info(L.SLASH_STATUS_TEMPLATES, GA.UI.Theme.DescribeNative())
    elseif command == "capture" then
        GA.Modules.Equipment:Capture(L.SLASH_SOURCE_COMMAND)
        Debug:Info("%s", L.SLASH_CAPTURED)
    elseif command == "minimap" then
        local shown = GA.UI.MinimapButton:SetShown(nil)
        Debug:Info(L.SLASH_MINIMAP, shown and L.SLASH_ON or L.SLASH_OFF)
    elseif command == "sync" then
        local Sync = GA.Modules.Sync
        Sync:Hello()
        local ok, reason = Sync:PublishAll()
        Debug:Info(L.SLASH_SYNC, Sync:PeerCount(), Sync.conflicts or 0,
            ok and "" or string.format(L.SLASH_SYNC_NOTSENT,
                tostring(reason or L.SLASH_SYNC_SHARING_OFF)))
        for name, peer in pairs(Sync.peers) do
            Debug:Info(L.SLASH_SYNC_PEER, name,
                tostring(peer.addon), tostring(peer.version))
        end

        -- Abgewiesene Nachrichten gehoeren hierher und nicht ins Schweigen:
        -- Wer sich wundert, warum ein Mitspieler nicht auftaucht, sieht hier
        -- den Grund.
        local rejected = GA.Core.Comm.rejected or {}
        if (rejected.stranger or 0) > 0 or (rejected.unknown or 0) > 0 then
            Debug:Info(L.SLASH_SYNC_REJECTED,
                rejected.stranger or 0, rejected.unknown or 0)
        end
    elseif command == "export" then
        if rest == "show" then GA.Core.Export:ShowDialog()
        else GA.Core.Export:Refresh(true) end
    elseif command == "import" then
        GA.UI.ImportDialog:Open(rest)
    elseif command == "rotate" then
        local Rotation = GA.Modules.Rotation
        if rest == "clear" then
            Debug:Info(L.SLASH_ROTATE_CLEARED, Rotation:ClearAll(
                GA.Core.Compat.GetPlayerIdentity().guid))
        elseif rest == "status" then
            local active = Rotation:Active()
            local done, total = Rotation:CycleProgress()
            Debug:Info(L.SLASH_ROTATE_STATUS, #active, done, total)
            for _, seat in ipairs(active) do
                Debug:Info(L.SLASH_ROTATE_SEAT, tostring(seat.name),
                    math.max(0, math.floor((seat.expires - GA.Core.Util.Now()) / 60)))
            end
        else
            local ok, result = Rotation:Rotate({ seats = tonumber(rest) })
            if not ok then
                Debug:Info("%s", L["ROTATION_ERR_" .. string.upper(tostring(result))]
                    or tostring(result))
            else
                local names = {}
                for _, entry in ipairs(result) do names[#names + 1] = entry.name end
                Debug:Info(L.ROTATION_DONE, table.concat(names, ", "))
            end
        end
    elseif command == "roll" then
        local Rolls = GA.Modules.Rolls
        if rest == "close" or rest == "ende" then
            local ok = Rolls:Close(L.SLASH_BY_HAND)
            Debug:Info("%s", ok and L.SLASH_ROLL_CLOSED or L.ROLL_IDLE)
        elseif rest == "" and Rolls.current then
            local list = Rolls:Results()
            local winner, tied = Rolls:Winner()
            Debug:Info(L.ROLL_COUNT, #list, #Rolls:Missing())
            for _, entry in ipairs(list) do
                Debug:Info("  %-16s %d", tostring(entry.name), entry.roll)
            end
            if winner then
                Debug:Info(L.ROLL_WINNER, winner.name, winner.roll)
            elseif #tied > 1 then
                local namen = {}
                for _, entry in ipairs(tied) do namen[#namen + 1] = entry.name end
                Debug:Info(L.ROLL_TIE, tied[1].roll, table.concat(namen, ", "))
                Debug:Info("%s", L.ROLL_TIE_HINT)
            end
        else
            -- "/ga roll <item> [sekunden]" — der Gegenstand darf ein Link,
            -- eine Wowhead-Adresse, eine ID oder ein Name sein. Dieselbe
            -- Eingabe wie bei der Wunschliste, damit niemand zwei Formate
            -- lernen muss.
            local text, seconds = string.match(rest, "^(.-)%s+(%d+)$")
            text = text or rest
            -- ParseItemInput liefert ZWEI WERTE (ID und Art), keine Tabelle.
            -- Name und Link kommen aus dem Itemverzeichnis, nicht vom Parser
            -- — der sieht nur die Eingabe.
            local itemID = text ~= "" and GA.Core.Compat.ParseItemInput(text) or nil
            local info = itemID and GA.Core.Compat.GetItemInfo(itemID)

            local ok, result = Rolls:Open({
                itemID = itemID,
                itemName = (info and info.name) or (text ~= "" and text or nil),
                itemLink = info and info.link,
                seconds = tonumber(seconds),
            })
            if not ok then
                Debug:Info("%s", L["ROLL_ERR_" .. string.upper(tostring(result))]
                    or tostring(result))
            else
                Rolls:Announce()
                Debug:Info(L.ROLL_RUNNING,
                    tostring(result.itemName or result.itemID or "?"), result.min, result.max)
            end
        end
    elseif command == "sr" or command == "reserve" then
        local SoftRes = GA.Modules.SoftRes
        local identity = GA.Core.Compat.GetPlayerIdentity()
        if rest == "open" then
            local ok, result = SoftRes:Open({})
            Debug:Info("%s", ok and L.SOFTRES_TITLE
                or (L["SOFTRES_ERR_" .. string.upper(tostring(result))] or tostring(result)))
        elseif rest == "close" then
            Debug:Info("%s", SoftRes:Close(identity.guid) and L.SLASH_SR_CLOSED
                or L.SOFTRES_NONE)
        elseif string.sub(rest, 1, 3) == "add" then
            -- Der Weg fuer SPIELER: anmelden, nicht eintragen. Die Runde
            -- liegt beim Lootmeister, also geht das ueber eine Nachricht und
            -- kommt als Antwort zurueck.
            local text = string.match(rest, "^add%s+(.+)$")
            local itemID = text and GA.Core.Compat.ParseItemInput(text)
            if not itemID then
                Debug:Info(L.SLASH_NO_ITEM, tostring(text))
            else
                local ok, grund = SoftRes:Claim(itemID)
                if not ok then
                    Debug:Info("%s", L["SOFTRES_ERR_" .. string.upper(tostring(grund)) .. "2"]
                        or tostring(grund))
                end
            end
        elseif string.sub(rest, 1, 3) == "del" then
            local text = string.match(rest, "^del%s+(.+)$")
            SoftRes:Unclaim(text and GA.Core.Compat.ParseItemInput(text))
        elseif rest == "mine" then
            local mine = SoftRes:Of(identity.name)
            if #mine == 0 then
                Debug:Info("%s", L.SOFTRES_NONE)
            end
            for _, entry in ipairs(mine) do
                Debug:Info("  %s (%s)", tostring(entry.itemName or entry.itemID),
                    entry.origin == "claim" and L.SOFTRES_ORIGIN_CLAIM
                        or L.SOFTRES_ORIGIN_LIST)
            end
        elseif string.sub(rest, 1, 6) == "import" then
            -- Eigenes Eingabefenster, nicht der Export-Import: Das eine liest
            -- eine Sicherung, das andere eine Namensliste. Beides in einen
            -- Dialog zu legen waere eine Falle.
            GA.UI.Widgets.InputDialog(L.SOFTRES_TITLE,
                L.SLASH_SR_IMPORT_EXAMPLE,
                function(text)
                    local report = SoftRes:Import(text)
                    Debug:Info(L.SOFTRES_IMPORTED, report.added, #report.skipped)
                    for _, entry in ipairs(report.skipped) do
                        Debug:Info("  ? %s (%s)", tostring(entry.line), tostring(entry.reason))
                    end
                end)
        else
            local stats = SoftRes:Stats()
            if not SoftRes:Current() then
                Debug:Info("%s", L.SOFTRES_NONE)
            else
                Debug:Info(L.SOFTRES_STATS, stats.entries, stats.players, stats.contested)
                for _, entry in ipairs(SoftRes:Contested()) do
                    Debug:Info("  %s  %s: %s", L.SOFTRES_CONTESTED,
                        tostring(entry.itemName or entry.itemID),
                        table.concat(entry.names, ", "))
                end
                for _, entry in ipairs(SoftRes:OverLimit()) do
                    Debug:Info("  %s  %s (%d)", L.SOFTRES_OVERLIMIT, entry.name, entry.count)
                end
                Debug:Info("%s", L.SOFTRES_HINT)
            end
        end
    elseif command == "plusone" or command == "p1" then
        local PlusOne = GA.Modules.PlusOne
        local list = PlusOne:List()
        if #list == 0 then
            Debug:Info("%s", L.SLASH_NO_PROFILES)
        end
        for _, entry in ipairs(list) do
            Debug:Info(L.PLUSONE_ROW, entry.name, entry.total, entry.counted, entry.offset)
            if entry.manual > 0 then
                Debug:Info("    " .. L.PLUSONE_MANUAL_HINT, entry.manual)
            end
        end
        Debug:Info("%s", L.PLUSONE_HINT)
    elseif command == "test" then
        -- PROBELAUF FUERS COUNCIL.
        --
        -- Eine Session braucht erkannte Vergaben, und die entstehen nur aus
        -- echtem Loot. Ohne diesen Befehl muesste man zum Ueben etwas
        -- aufheben und danach die Historie aufraeumen.
        --
        -- Die Probevergabe ist als solche gekennzeichnet (test = true) und
        -- bleibt aus Statistik, Plus Eins und Export heraus. Eine Probe, die
        -- Spuren hinterlaesst, ist keine.
        local Awards = GA.Modules.Awards
        if rest == "clear" then
            local removed = 0
            for id, award in pairs(GA.Core.Database.account.awards) do
                if award.test then
                    GA.Core.Database.account.awards[id] = nil
                    removed = removed + 1
                end
            end
            GA.Core.Callbacks:Fire("AWARD_CHANGED")
            Debug:Info(L.TEST_CLEARED, removed)
        elseif rest == "" then
            Debug:Info("%s", L.TEST_USAGE)
        else
            local itemID = GA.Core.Compat.ParseItemInput(rest)
            if not itemID then
                Debug:Info("%s", L.WISH_NO_ITEM)
            else
                local info = GA.Core.Compat.GetItemInfo(itemID)
                local award = Awards:Create({
                    itemID = itemID,
                    name = (info and info.name)
                        or string.format(L.SLASH_ITEM_FALLBACK, itemID),
                    link = info and info.link,
                    quality = info and info.quality or 4,
                }, { reason = L.TEST_REASON, sourceName = L.TEST_SOURCE })
                award.test = true
                Debug:Info(L.TEST_CREATED,
                    tostring(award.itemLink or award.itemName), tostring(award.id))
            end
        end
    elseif command == "atlas" then
        local Atlas = GA.Modules.AtlasBridge
        local stats = Atlas:Stats()
        if not stats.available then
            Debug:Info("%s", L.ATLAS_MISSING)
        elseif rest == "" and stats.harvested then
            Debug:Info(L.ATLAS_STATS, stats.sources, stats.known)
        else
            local ok, grund = Atlas:Harvest()
            if not ok then Debug:Info(L.SLASH_ATLAS_ERROR, tostring(grund)) end
        end
    elseif command == "trade" or command == "tausch" then
        local Tradables = GA.Modules.Tradables

        if rest == "test" then
            Tradables.testMode = not Tradables.testMode
            Tradables:Refresh()
            Debug:Info(L.TRADE_TEST, Tradables.testMode and L.SLASH_ON or L.SLASH_OFF)
        elseif string.sub(rest, 1, 3) == "add" or string.sub(rest, 1, 6) == "remove" then
            -- DER WEG, DER IMMER FUNKTIONIERT. Der Alt-Klick im Beutel haengt
            -- an einer Blizzard-Funktion, die es geben kann oder nicht.
            local wantOn = string.sub(rest, 1, 3) == "add"
            local text = string.match(rest, "^%a+%s+(.+)$")
            local itemID = text and GA.Core.Compat.ParseItemInput(text)

            if not itemID then
                Debug:Info(L.SLASH_NO_ITEM, tostring(text))
            elseif not Tradables:IsCandidate(itemID) then
                Debug:Info("%s", L.TRADE_NOT_CANDIDATE)
            else
                Tradables:SetOffered(itemID, wantOn)
                local info = GA.Core.Compat.GetItemInfo(itemID)
                Debug:Info(wantOn and L.TRADE_NOW_OFFERED or L.TRADE_NO_LONGER,
                    tostring((info and info.name) or itemID))
            end
        end

        local candidates, sure = Tradables:Scan()
        local mine = Tradables:Offered()

        if rest == "post" or rest == "chat" then
            -- IN DEN GILDENCHAT SCHREIBEN IST EIN AUSDRUECKLICHER BEFEHL,
            -- kein Nebeneffekt. Ein Addon, das ungefragt postet, fliegt zu
            -- Recht raus — dieselbe Regel wie bei Announce.
            if #mine == 0 then
                Debug:Info("%s", L.TRADE_NONE_OWN)
            else
                local names = {}
                for _, item in ipairs(mine) do
                    -- DER EIGENE LINK ZUERST: Er traegt den Zufallssuffix.
                    -- Ein aus der ID nachgeschlagener Link postet
                    -- "Nomad Tunic" in den Gildenchat, und wer darauf klickt,
                    -- sieht andere Werte als die, die du anbietest.
                    local info = GA.Core.Compat.GetItemInfo(item.link or item.itemID)
                    local text = item.link or (info and info.link) or (info and info.name)
                        or string.format(L.SLASH_ITEM_FALLBACK, item.itemID)
                    names[#names + 1] = text .. (item.count > 1 and (" x" .. item.count) or "")
                end
                GA.Core.Compat.SendChatMessage(
                    string.format(L.TRADE_ANNOUNCE, table.concat(names, ", ")), "GUILD")
            end
        end

        -- Beide Zahlen: Was in Frage kaeme, und was du tatsaechlich
        -- anbietest. Nur die zweite zu zeigen liesse offen, ob nichts da ist
        -- oder nur nichts gewaehlt wurde.
        Debug:Info(L.TRADE_OWN, #mine, #candidates,
            sure and "" or (" — " .. L.TRADE_UNSURE))
        if Tradables.testMode then Debug:Warn("%s", L.TRADE_TEST_ON) end

        -- OB DER ALT-KLICK HAENGT, GEHOERT SICHTBAR HIERHER. Er haengt an
        -- einer Blizzard-Funktion, die es je nach Client gibt oder nicht;
        -- ohne diese Zeile sieht ein nicht eingehaengter Klick genauso aus
        -- wie einer, der einfach nichts getroffen hat.
        if Tradables.hookPath then
            Debug:Info(L.TRADE_HOOK_ON, tostring(Tradables.hookPath))
        else
            Debug:Warn("%s", L.TRADE_HOOK_OFF)
        end
        for _, entry in ipairs(Tradables:All()) do
            Debug:Info("  %-16s %d", tostring(entry.name), #entry.items)
        end
    elseif command == "combatlog" then
        -- EIN KURZER WEG ZU EINER EINSTELLUNG, DIE JEDE SITZUNG NEU GESETZT
        -- WERDEN MUSS.
        --
        -- Gemessen 20.09.2026: Dieser Client SCHREIBT die SavedVariables
        -- korrekt, liest sie beim Start aber nie ein. Jede Sitzung faengt
        -- damit bei den Voreinstellungen an — und autoCombatLog ist aus.
        --
        -- Das Haekchen in den Einstellungen tut dasselbe. Es ist nur drei
        -- Klicks weit weg, und das hier ist eine Zeile.
        local on
        if rest == "on" or rest == "an" then on = true
        elseif rest == "off" or rest == "aus" then on = false end

        if on ~= nil then
            GA.Core.Config:Set("autoCombatLog", on)
            -- Sofort anwenden statt bis zum naechsten Takt zu warten: Wer
            -- das im Raid tippt, meint jetzt.
            if GA.Modules.CombatLog and GA.Modules.Attendance then
                GA.Modules.CombatLog:Apply((GA.Modules.Attendance:InRaid()))
            end
        end

        local running = GA.Core.Compat.IsCombatLogging()
        Debug:Info(L.SLASH_COMBATLOG,
            GA.Core.Config:Get("autoCombatLog") and L.SLASH_ON or L.SLASH_OFF,
            running == nil and L.UNKNOWN or (running and L.SLASH_ON or L.SLASH_OFF))
    elseif command == "probe" then
        -- WAS GIBT DIESER CLIENT FUER DIE OFFENEN ERFOLGE HER?
        --
        -- Von aussen nicht zu beantworten: Forever traegt die komplette
        -- Retail-API mit sich, auch fuer Dinge, die es im Spiel nicht gibt.
        -- Gemessen wird deshalb der Rueckgabewert, nicht die Existenz.
        local text, counts = GA.Core.Probe:Report()
        Debug:Info(L.PROBE_RESULT, counts.ja or 0, counts.leer or 0, counts.nein or 0)
        GA.UI.Widgets.CopyDialog(L.PROBE_TITLE, text)
    elseif command == "icons" then
        -- WELCHE SYMBOLE KENNT DIESER CLIENT NICHT?
        --
        -- Die Pfade in AchievementIcons sind gewaehlt, nicht gemessen — von
        -- aussen ist nicht zu pruefen, welche Symboldateien mitgeliefert
        -- werden. Hier laeuft die Probe, und das Ergebnis steht in einem
        -- Fenster zum Kopieren: aus dem Chat ist es nicht herauszubekommen.
        local Icons = GA.UI.AchievementIcons
        local result = Icons:Probe()
        Debug:Info(L.ICONS_RESULT, result.checked, #result.missing)
        if #result.missing > 0 then
            GA.UI.Widgets.CopyDialog(L.ICONS_TITLE, table.concat(result.missing, "\n"))
        end
    elseif command == "version" then
        local V = GA.Modules.VersionCheck
        V:Start(rest ~= "" and string.upper(rest) or nil)
        Debug:Info("%s", L.VERSION_RUNNING)
        GA.Core.Compat.After(11, function()
            local list, counts = V:Result()
            Debug:Info(L.VERSION_SUMMARY, counts.current, counts.outdated, counts.silent)
            for _, entry in ipairs(list) do
                Debug:Info("  %-16s %-14s %s", tostring(entry.name),
                    tostring(L["VERSION_" .. string.upper(entry.status)] or entry.status),
                    tostring(entry.version or ""))
            end
            if counts.silent > 0 then Debug:Info("%s", L.VERSION_SILENT_HINT) end
        end)
    elseif command == "handover" then
        local carrying, missing = GA.Modules.Handover:Pending()
        if #carrying == 0 and #missing == 0 then
            Debug:Info("%s", L.HANDOVER_NONE)
        end
        for _, entry in ipairs(carrying) do
            Debug:Info(L.SLASH_HANDOVER_CARRYING, L.HANDOVER_CARRYING,
                tostring(entry.link or entry.itemID), tostring(entry.to),
                entry.bag, entry.slot)
        end
        for _, entry in ipairs(missing) do
            Debug:Info("  %s  %s  → %s", L.HANDOVER_MISSING,
                tostring(entry.itemID), tostring(entry.to))
        end
        if #missing > 0 then Debug:Info("%s", L.HANDOVER_MISSING_HINT) end
    elseif command == "reset" then handleReset(rest ~= "" and rest or "all")
    else
        Debug:Info("%s", L.SLASH_HELP)
    end
end
