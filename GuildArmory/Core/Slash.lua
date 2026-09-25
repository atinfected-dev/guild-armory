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
    session = "lootcouncil", sitzung = "lootcouncil",
    analytics = "analytics", settings = "settings",
    lootrules = "lootrules", rules = "lootrules", regeln = "lootrules",
    crafting = "crafting", berufe = "crafting", professions = "crafting",
    -- Bereichswoerter zeigen auf die ERSTE Ansicht des Bereichs. Der Reiter
    -- wird dabei mitgewaehlt, und wer dort zuletzt woanders war, landet
    -- ueber den Reiter selbst wieder dort — hier zaehlt der geradeste Weg.
    overview = "dashboard", uebersicht = "dashboard",
    guild = "armory", gilde = "armory",
    equipment = "armory", ausruestung = "armory",
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

--- Ein Bericht, der im Chat steht UND sich herausholen laesst.
---
--- "ich kann nicht aus dem chat kopieren" — gemeldet 25.09.2026, und es
--- stimmt: WoWs Chatfenster gibt seinen Text nicht her. Ein Diagnosebericht,
--- den niemand verschicken kann, ist als Diagnose wertlos; genau deshalb
--- hat /ga probe schon immer ein Fenster zum Kopieren.
---
--- Die Zeilen gehen trotzdem AUCH in den Chat: Wer nur kurz nachsieht, will
--- kein Fenster wegklicken.
local function bericht()
    local zeilen = {}
    return {
        sag = function(format, ...)
            local ok, text = pcall(string.format, format, ...)
            if not ok then text = tostring(format) end
            zeilen[#zeilen + 1] = text
            Debug:Info("%s", text)
        end,
        zeigen = function(titel)
            if GA.UI and GA.UI.Widgets and GA.UI.Widgets.CopyDialog then
                GA.UI.Widgets.CopyDialog(titel, table.concat(zeilen, "\n"))
            end
        end,
    }
end

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
    elseif command == "mem" then
        -- WARUM DIESER BEFEHL EXISTIERT
        --
        -- Gemeldet wurde eine steigende Zahl — 18, 19, 20 MB — und dann fiel
        -- sie von selbst auf 5 zurueck. Das ist der Sammler. Belegtes faellt
        -- nicht, Muell schon, und ohne diese Unterscheidung sieht beides
        -- gleich aus: Man baut dann Dinge um, die nie das Problem waren.
        --
        -- Der Befehl misst beides nacheinander und sagt, was davon zu halten
        -- ist. Er sammelt dabei ABSICHTLICH — das kostet einen kurzen
        -- Ruckler und ist genau das Ereignis, das gemessen werden soll.
        local Compat = GA.Core.Compat
        local vorherAddon = Compat.GetAddonMemoryKB("GuildArmory")
        local vorherLua = Compat.GetLuaMemoryKB()

        Compat.CollectGarbage()

        local nachherAddon = Compat.GetAddonMemoryKB("GuildArmory")
        local nachherLua = Compat.GetLuaMemoryKB()

        local function mb(kb)
            if not kb then return "?" end
            return string.format("%.2f MB", kb / 1024)
        end

        local b = bericht()
        b.sag("%s", L.SLASH_MEM_TITLE)
        if not vorherAddon and not vorherLua then
            b.sag("%s", L.SLASH_MEM_NOAPI)
        else
            b.sag(L.SLASH_MEM_BEFORE, mb(vorherAddon), mb(vorherLua))
            b.sag(L.SLASH_MEM_AFTER, mb(nachherAddon), mb(nachherLua))

            -- DIE AUSSAGE STEHT AUF DER LUA-ZAHL, nicht auf der je Addon.
            -- Die Addon-Zahl ist eine Zuschreibung; collectgarbage("count")
            -- ist gemessen. Wer nur die erste ansieht, deutet eine
            -- Schaetzung.
            local basis = vorherLua or vorherAddon
            local rest = nachherLua or nachherAddon
            if basis and rest then
                local weg = basis - rest
                if weg > basis * 0.2 then
                    b.sag(L.SLASH_MEM_GARBAGE, mb(weg))
                else
                    b.sag("%s", L.SLASH_MEM_HELD)
                end
            end
        end

        -- WOVON, FALLS ES WIRKLICH BELEGT IST. Zahlen statt Vermutungen:
        -- Eine Tabelle, die staendig waechst, faellt hier sofort auf, und
        -- eine, die klein bleibt, ist entlastet.
        local account = GA.Core.Database.account
        b.sag("%s", L.SLASH_MEM_TABLES)
        for _, eintrag in ipairs({
            { "characters", account.characters },
            { "awards", account.awards },
            { "journal", account.journal },
            { "sessions", account.sessions },
            { "wishlists", account.wishlists },
            { "items", account.items },
            { "players", account.players },
            { "guild.members", account.guild and account.guild.members },
        }) do
            local zahl = 0
            for _ in pairs(eintrag[2] or {}) do zahl = zahl + 1 end
            b.sag(L.SLASH_MEM_ROW, eintrag[1], zahl)
        end
        b.zeigen(L.SLASH_MEM_TITLE)

    elseif command == "status" then
        -- AUCH ZUM KOPIEREN. Das ist der Bericht, um den ich am haeufigsten
        -- bitte, und aus dem Chatfenster ist er nicht herauszubekommen.
        local b = bericht()
        local stats = GA.Core.Database:Stats()
        b.sag(L.SLASH_STATUS_VERSION, GA.version, tostring(stats.schemaVersion),
            tostring(GA.Core.Locale.active), tostring(GA.Core.Locale.reason))
        local storage = GA.Core.Database.storage or {}
        b.sag(L.SLASH_STATUS_STORAGE, tostring(storage.source),
            storage.accountLoaded and "" or ("  " .. L.SLASH_STATUS_MIRROR))
        b.sag(L.SLASH_STATUS_COUNTS,
            stats.characters, stats.awards, stats.sessions, stats.journal)
        for _, key in ipairs(CAPABILITIES) do
            local value = GA.has[key]
            b.sag("  %s %-22s %s", value and "+" or "-",
                tostring(L["CAP_" .. key]),
                tostring(value and L["CAP_" .. key .. "_GOOD"] or L["CAP_" .. key .. "_BAD"]))
        end
        -- WER BIN ICH HIER, UND WAS DARF ICH?
        --
        -- "Ich kann keine Sitzung oeffnen" ist sonst nicht aufzuklaeren:
        -- Die Rolle haengt an der eigenen GUID, und die kann auf diesem
        -- Client ein verschleierter Wert sein. Dann steht hier "GUID nicht
        -- lesbar", und das ist die Antwort.
        local eigen = GA.Core.Compat.GetPlayerIdentity()
        local Database = GA.Core.Database
        if not eigen.guid then
            Debug:Warn("%s", L.ROLE_NO_GUID)
            b.sag("%s", L.ROLE_NO_GUID)
        else
            local rolle = Database:GetRole(eigen.guid)
            b.sag(L.SLASH_STATUS_ROLE, tostring(rolle),
                tostring(Database:HasAtLeast(eigen.guid, GA.const.ROLE_LOOTMASTER)),
                tostring(Database:HasAtLeast(eigen.guid, GA.const.ROLE_COUNCIL)))
        end

        b.sag(L.SLASH_STATUS_TEMPLATES, GA.UI.Theme.DescribeNative())
        b.zeigen(L.SLASH_STATUS_TITLE)
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

        if string.sub(rest, 1, 3) == "why" then
            -- "Geht nicht" laesst sich nicht reparieren. Diese Ausgabe macht
            -- daraus eine Liste von Werten, von denen einer "nein" sagt.
            local text = string.match(rest, "^%a+%s+(.+)$")
            local itemID = text and GA.Core.Compat.ParseItemInput(text)
            if not itemID then
                Debug:Info(L.SLASH_NO_ITEM, tostring(text))
            else
                for _, zeile in ipairs(Tradables:Explain(itemID)) do
                    Debug:Info("%s", zeile)
                end
            end
        elseif rest == "test" then
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
            -- Dieselbe Funktion, die der Knopf im Ueberblick ruft. Zwei
            -- Wege in der Bedienung duerfen nicht zwei Fassungen im Code
            -- werden — sonst postet der eine bald etwas anderes als der
            -- andere.
            local ok, grund = Tradables:Announce()
            if not ok then
                Debug:Info("%s", grund == "leer" and L.TRADE_NONE_OWN or L.TRADE_POST_FAILED)
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
    elseif command == "camp" or command == "lager" then
        local Camp = GA.Modules.Camp
        local CampFrame = GA.UI.CampFrame

        if rest == "why" or rest == "warum" then
            -- Der Katalog ist abgeschriebene Beobachtung, kein gemessener
            -- Befund. Diese Ausgabe sagt, was dieser Client daraus macht —
            -- statt "geht nicht" zu sein.
            for _, zeile in ipairs(Camp:Explain()) do Debug:Info("%s", zeile) end
        elseif rest == "on" or rest == "an" then
            GA.Core.Config:Set("campEnabled", true)
            CampFrame:Show()
            Debug:Info(L.SLASH_CAMP, L.SLASH_ON)
        elseif rest == "off" or rest == "aus" then
            -- AUS HEISST AUS: Das Fenster verschwindet, und Camp:Enabled
            -- schliesst ab jetzt jeden Versand und jeden Empfang aus.
            GA.Core.Config:Set("campEnabled", false)
            CampFrame:Hide()
            Debug:Info(L.SLASH_CAMP, L.SLASH_OFF)
        else
            local sichtbar = CampFrame:Toggle()
            Debug:Info(L.SLASH_CAMP, sichtbar and L.SLASH_ON or L.SLASH_OFF)
        end
    elseif command == "craft" or command == "beruf" then
        local Crafting = GA.Modules.Crafting

        if rest == "scan" then
            -- DER EINE BEFEHL, DER DIE ZUMUTUNG ABKUERZT: Wer sein
            -- Berufsfenster offen hat und trotzdem nichts sieht, braucht
            -- einen Weg, es von Hand auszuloesen — und eine Begruendung,
            -- wenn es wieder nichts wird.
            -- LAUT: Wer tippt, hat gefragt. ScanOpen meldet sonst nur echte
            -- Aenderungen, damit das Berufsfenster nicht bei jedem Oeffnen
            -- zweimal dasselbe in den Chat schreibt.
            local line, grund = Crafting:ScanOpen(true)
            if not line then
                Debug:Info("%s", L["CRAFT_ERR_" .. tostring(grund)])
            end
        elseif rest == "sync" then
            Crafting:Request()
            Crafting:Publish()
            Debug:Info("%s", L.CRAFT_SYNCED)
        elseif rest ~= "" then
            local itemID = GA.Core.Compat.ParseItemInput(rest)
            if not itemID then
                Debug:Info(L.SLASH_NO_ITEM, tostring(rest))
            else
                local crafters = Crafting:Crafters(itemID)
                local info = GA.Core.Compat.GetItemInfo(itemID)
                local was = (info and info.name)
                    or string.format(L.SLASH_ITEM_FALLBACK, tostring(itemID))
                if #crafters == 0 then
                    Debug:Info(L.CRAFT_NOBODY, was)
                else
                    Debug:Info(L.CRAFT_FOUND, #crafters, was)
                    for _, crafter in ipairs(crafters) do
                        Debug:Info("  %-16s %s %d  (%s)", tostring(crafter.name),
                            tostring(crafter.lineName or crafter.line), crafter.rank or 0,
                            GA.Core.Util.TimeAgo(crafter.ts))
                    end
                end
            end
        else
            local charaktere, berufe, rezepte = Crafting:Stats()
            Debug:Info(L.CRAFT_STATS, charaktere, berufe, rezepte)
            -- OHNE DIESEN SATZ SIEHT EIN LEERES VERZEICHNIS AUS WIE EIN
            -- FEHLER. Es ist keiner: Rezepte gibt es nur bei geoeffnetem
            -- Berufsfenster zu lesen, und das hat noch niemand getan.
            Debug:Info("%s", L.CRAFT_HOWTO)
        end
    elseif command == "map" or command == "karte" then
        local Positions = GA.Modules.Positions

        if rest == "why" or rest == "warum" then
            for _, zeile in ipairs(Positions:Explain()) do Debug:Info("%s", zeile) end
        elseif rest == "on" or rest == "an" then
            GA.Core.Config:Set("mapShare", true)
            Positions:Publish(true)
            Debug:Info(L.MAP_SHARING, L.SLASH_ON)
        elseif rest == "off" or rest == "aus" then
            -- AUS HEISST AUS, in beide Richtungen: Positions:Enabled
            -- schliesst ab jetzt jeden Versand UND jeden Empfang aus, und
            -- OnMap gibt nichts mehr heraus.
            GA.Core.Config:Set("mapShare", false)
            wipe(Positions.states)
            if GA.UI.MapPins then GA.UI.MapPins:HideAll() end
            Debug:Info(L.MAP_SHARING, L.SLASH_OFF)
        else
            local anzahl, karten = Positions:Stats()
            Debug:Info(L.MAP_STATS, anzahl, karten)
            Debug:Info(L.MAP_SHARING,
                Positions:Enabled() and L.SLASH_ON or L.SLASH_OFF)
        end
    -- NUR "sim". Hier stand einmal `command == "sim" or command == "probe"`,
    -- und damit war der API-Bericht weiter unten unerreichbar: Die erste
    -- passende Bedingung gewinnt, und der Zweig darunter sah aus, als gaebe
    -- es ihn. Ein zweiter Name fuer den Probebetrieb ist es nicht wert.
    elseif command == "sim" then
        -- PROBEBETRIEB. Ein ganzer Raidabend ohne Raid: Gegenstaende, die
        -- fallen, Leute, die bieten, ein Council, das abstimmt.
        --
        -- Solange er laeuft, verlaesst nichts diesen Client — weder eine
        -- Chatzeile noch eine Addon-Nachricht. Und jeder erfundene
        -- Datensatz traegt ein Merkmal, an dem "sim clear" ihn wieder
        -- findet und der Abgleich sich weigert, ihn weiterzugeben.
        local Sandbox = GA.Modules.Sandbox
        local wort, zahl = string.match(rest, "^(%a*)%s*(%d*)$")
        zahl = tonumber(zahl)

        if wort == "on" or wort == "an" then
            Sandbox:SetActive(true)
            Debug:Warn("%s", L.SIM_ON)
        elseif wort == "off" or wort == "aus" then
            Sandbox:SetActive(false)
            Debug:Info(L.SIM_OFF, Sandbox.blocked.chat, Sandbox.blocked.comm)
        elseif wort == "clear" or wort == "weg" then
            local weg = Sandbox:Clear()
            Sandbox:SetActive(false)
            Debug:Info(L.SIM_CLEARED, weg.awards, weg.characters, weg.profile,
                weg.sessions, weg.reserves)
        elseif wort == "raid" then
            Sandbox:SetActive(true)
            Debug:Info(L.SIM_ROSTER, Sandbox:Roster(zahl))
        elseif wort == "drop" then
            Sandbox:SetActive(true)
            Debug:Info(L.SIM_DROPPED, #Sandbox:Drop(zahl))
        elseif wort == "sr" or wort == "reserve" then
            Sandbox:SetActive(true)
            Sandbox:Roster()
            Debug:Info(L.SIM_RESERVED, Sandbox:Reserves())
        elseif wort == "award" or wort == "vergeben" then
            -- Der Durchlauf vergibt NICHT mehr selbst; das ist der Schritt,
            -- den man pruefen will. Wer ihn trotzdem automatisch braucht —
            -- etwa um die Historie zu fuellen — sagt es hier.
            local session = GA.Modules.Session:Current()
            if not session then
                Debug:Info("%s", L.COUNCIL_REOPEN_NONE)
            else
                local vergeben, leer = Sandbox:Award(session.id)
                Debug:Info(L.SIM_AWARDED, vergeben, leer)
            end
        elseif wort == "bid" or wort == "gebot" then
            -- Das Gebotsfenster noch einmal zeigen.
            local session = GA.Modules.Session:Current()
            if session then Sandbox:ShowBidFrame(session)
            else Debug:Info("%s", L.COUNCIL_REOPEN_NONE) end
        elseif wort == "seed" then
            Debug:Info(L.SIM_SEED, Sandbox:Seed(zahl))
        elseif wort == "run" or wort == "" then
            local bericht = Sandbox:Run(zahl)
            if bericht.fehler then
                Debug:Warn(L.SIM_FAILED, tostring(bericht.fehler))
            else
                Debug:Info(L.SIM_RAN, bericht.spieler, #bericht.gefallen,
                    bericht.gebote, bericht.stimmen)
                Debug:Info("%s", L.SIM_LOOK)
            end
        else
            Debug:Info("%s", L.SIM_USAGE)
        end

        local zahlen = Sandbox:Count()
        Debug:Info(L.SIM_STATE, tostring(Sandbox.active),
            zahlen.awards, zahlen.characters, zahlen.sessions)
    elseif command == "dkp" then
        -- PUNKTE VON HAND BUCHEN UND NACHSEHEN.
        --
        -- Das Addon bucht nichts von allein: Es kann einen verpassten Boss
        -- nicht von einem nicht stattgefundenen unterscheiden, und eine
        -- erfundene Buchung waere schlimmer als gar keine.
        local Dkp = GA.Modules.Dkp
        local wort, rest2 = string.match(rest, "^(%a*)%s*(.*)$")

        if wort == "add" or wort == "give" then
            local punkte, name = string.match(rest2, "^(-?%d+)%s+(.+)$")
            local character = name and GA.Core.Database:FindCharacterByName(name)

            -- JEDER FEHLSCHLAG SAGT SEINEN EIGENEN GRUND.
            --
            -- Hier stand fuer beide Faelle die Hilfe. Wer einen Namen
            -- eintippt, den das Addon nicht kennt, bekam damit eine Liste
            -- von Befehlen zurueck — und liest daraus, der Befehl sei
            -- falsch gewesen. Er war richtig; der Name war unbekannt.
            if not punkte then
                Debug:Info("%s", L.DKP_USAGE)
            elseif not character then
                -- NICHT NUR "KENNE ICH NICHT", SONDERN WARUM.
                --
                -- Es gibt drei verschiedene Lagen, und sie brauchen
                -- verschiedene Antworten: Die Datenbank ist leer, der
                -- eigene Charakter fehlt (dann ist die GUID nicht lesbar),
                -- oder der Name ist wirklich unbekannt. "Kenne ich nicht"
                -- fuer alle drei schickt den Fragenden in die falsche
                -- Richtung.
                local namen, anzahl = {}, 0
                for _, eintrag in pairs(GA.Core.Database.account.characters or {}) do
                    anzahl = anzahl + 1
                    if #namen < 6 and eintrag.name then
                        namen[#namen + 1] = eintrag.name
                    end
                end

                local eigen = GA.Core.Compat.GetPlayerIdentity()
                Debug:Warn(L.DKP_NO_CHARACTER, tostring(name))
                Debug:Info(L.DKP_NO_CHARACTER_WHY, anzahl,
                    tostring(eigen.name), tostring(eigen.guid ~= nil))

                -- DIE NAMEN SELBST. Genau hier liegt der Unterschied, wenn
                -- es einen gibt: Was das Spiel als Namen herausgibt, muss
                -- nicht sein, was ein Mensch eintippt.
                if anzahl > 0 then
                    Debug:Info(L.DKP_KNOWN_NAMES, table.concat(namen, ", "))
                end
            else
                local eintrag, grund = Dkp:Post(character.guid, character.name,
                    tonumber(punkte), Dkp.KIND.ADJUST, L.DKP_BY_HAND)
                if eintrag then
                    Debug:Info(L.DKP_POSTED, tonumber(punkte), character.name,
                        Dkp:Balance(character.guid))
                else
                    Debug:Info("%s", tostring(grund))
                end
            end
        elseif wort == "log" then
            local name = rest2 ~= "" and rest2 or nil
            local character = name and GA.Core.Database:FindCharacterByName(name)

            if name and not character then
                Debug:Warn(L.DKP_NO_CHARACTER, tostring(name))
            else
                local guid = character and character.guid
                    or GA.Core.Compat.GetPlayerIdentity().guid
                local eintraege = Dkp:History(guid, 15)

                -- EIN LEERES KONTOBUCH IST EINE ANTWORT, KEIN SCHWEIGEN.
                if #eintraege == 0 then
                    Debug:Info(L.DKP_NO_ENTRIES, tostring(character and character.name
                        or GA.Core.Compat.GetPlayerIdentity().name))
                else
                    Debug:Info(L.DKP_LOG_HEAD,
                        tostring(character and character.name
                            or GA.Core.Compat.GetPlayerIdentity().name),
                        Dkp:Balance(guid))
                    for _, eintrag in ipairs(eintraege) do
                        Debug:Info("  %s  %+d  %s", GA.Core.Util.TimeAgo(eintrag.ts),
                            eintrag.points, tostring(eintrag.reason))
                    end
                end
            end
        else
            -- Die Rangliste. Sie steht hier und nicht in einem eigenen
            -- Fenster, weil sie meistens nur kurz gebraucht wird.
            local liste = Dkp:List()

            -- AUCH HIER: LEER IST EINE ANTWORT. Vorher kam nur die Hilfe,
            -- und das sieht aus, als haette der Befehl nicht funktioniert.
            if #liste == 0 then
                Debug:Info("%s", L.DKP_EMPTY)
            else
                Debug:Info(L.DKP_LIST_HEAD, #liste)
                for index, stand in ipairs(liste) do
                    if index > 20 then break end
                    Debug:Info("  %-22s %5d   (%d %s, %d %s)", tostring(stand.name),
                        stand.total, stand.earned, L.DKP_WORD_EARNED,
                        stand.spent, L.DKP_WORD_SPENT)
                end
            end
            Debug:Info("%s", L.DKP_USAGE)
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
