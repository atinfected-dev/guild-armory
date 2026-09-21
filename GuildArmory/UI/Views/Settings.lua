--[[----------------------------------------------------------------------------
    Views/Settings — Fenster, Freigabe, Daten, Client-Faehigkeiten.

    Die Freigabe eigener Charakterdaten ist die wichtigste Einstellung hier
    (Vorgabe, Abschnitt 4 und 14): Standard AUS. Solange sie aus ist, verlaesst
    nichts ueber die eigenen Charaktere diesen Client.
------------------------------------------------------------------------------]]

local _, GA = ...

local Settings = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local L = GA.L

Settings.titleKey = "NAV_SETTINGS"


--- Abstand zwischen zwei Bloecken und Hoehe des Loot-Blocks. Beides fest,
--- weil der Inhalt fest ist; was trotzdem nicht hineinpasst, faengt der
--- Bildlauf auf.
local PANEL_GAP = 8
local LOOT_PANEL_HEIGHT = 300
local LANGUAGE_PANEL_HEIGHT = 116

--- Die Auswahl, in der Reihenfolge der Knoepfe. "auto" steht hinten: Es ist
--- die Ausnahme, nicht der Normalfall (siehe Localization/Locale.lua).
local LANGUAGES = { "enUS", "deDE", "auto" }

function Settings:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- Der ganze Bereich laeuft im Bildlauf: Die Bloecke haben feste Hoehen,
    -- und die passten nur so lange in ein festes Fenster, bis eine Einstellung
    -- dazukam. Mit dem Bildlauf ist die Frage gegenstandslos — auch dann, wenn
    -- jemand das Fenster klein zieht.
    local column = Widgets.ScrollArea(frame)
    column:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    column:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.column = column

    -- Zwei Spalten ueber die volle Breite. Die Trennung laeuft ueber die
    -- Mitte des Inhalts ("TOP"/"BOTTOM" als Ankerpunkt) statt ueber eine
    -- gerechnete Breite: So folgt der Umbruch der Fensterbreite von selbst,
    -- auch wenn der Spieler das Fenster zieht.
    local columnA = CreateFrame("Frame", nil, column.content)
    columnA:SetPoint("TOPLEFT", column.content, "TOPLEFT", 0, 0)
    columnA:SetPoint("BOTTOMRIGHT", column.content, "BOTTOM", -gap, 0)

    local columnB = CreateFrame("Frame", nil, column.content)
    columnB:SetPoint("TOPLEFT", column.content, "TOP", gap, 0)
    columnB:SetPoint("BOTTOMRIGHT", column.content, "BOTTOMRIGHT", -8, 0)

    -- ------------------------------------------------------------ Sprache ---
    --
    -- Ganz oben und als eigener Block: Wer die Sprache sucht, sucht sie nicht
    -- unter "Fenster". Drei Knoepfe statt einer Auswahlliste — bei drei
    -- Moeglichkeiten ist eine Liste ein Klick zu viel, und man sieht sofort,
    -- was gerade gilt.
    local language = Widgets.Panel(columnA, L.SET_LANGUAGE)
    language:SetPoint("TOPLEFT", columnA, "TOPLEFT", 0, 0)
    language:SetPoint("RIGHT", columnA, "RIGHT", 0, 0)
    language:SetHeight(LANGUAGE_PANEL_HEIGHT)

    self.languageButtons = {}
    local previousLanguage
    for _, choice in ipairs(LANGUAGES) do
        local button = Widgets.Button(language.content, L["SET_LANGUAGE_" .. string.upper(choice)],
            function() Settings:ChooseLanguage(choice) end)
        button:SetHeight(20)
        if previousLanguage then button:SetPoint("LEFT", previousLanguage, "RIGHT", 4, 0)
        else button:SetPoint("TOPLEFT", language.content, "TOPLEFT", 0, -2) end
        button.choice = choice
        self.languageButtons[#self.languageButtons + 1] = button
        previousLanguage = button
    end

    local languageHint = Theme.Label(language.content, L.SET_LANGUAGE_HINT,
        fonts.small, Theme.color.textDim)
    languageHint:SetPoint("TOPLEFT", language.content, "TOPLEFT", 0, -28)
    languageHint:SetPoint("RIGHT", language.content, "RIGHT", 0, 0)
    languageHint:SetJustifyH("LEFT")
    languageHint:SetHeight(28)

    -- DER HINWEIS STEHT ERST DA, WENN ER STIMMT.
    --
    -- Was schon im Fenster steht, wurde beim Bauen in der alten Sprache
    -- geschrieben und aendert sich nicht mehr. Ein Hinweis, der immer
    -- dastuende, waere aber Rauschen — er erscheint deshalb erst nach einer
    -- Umstellung, zusammen mit dem Knopf, der sie abschliesst.
    self.languageReload = Theme.Label(language.content, L.SET_LANGUAGE_RELOAD,
        fonts.small, Theme.color.warn)
    self.languageReload:SetPoint("TOPLEFT", language.content, "TOPLEFT", 0, -60)
    self.languageReload:SetPoint("RIGHT", language.content, "RIGHT", -110, 0)
    self.languageReload:SetJustifyH("LEFT")
    self.languageReload:SetHeight(28)
    self.languageReload:Hide()

    self.reloadButton = Widgets.Button(language.content, L.BTN_RELOAD, function()
        if type(_G.ReloadUI) == "function" then ReloadUI() end
    end, "primary")
    self.reloadButton:SetHeight(20)
    self.reloadButton:SetPoint("TOPRIGHT", language.content, "TOPRIGHT", 0, -62)
    self.reloadButton:Hide()

    local left = Widgets.Panel(columnA, L.SET_WINDOW)
    left:SetPoint("TOPLEFT", language, "BOTTOMLEFT", 0, -gap)
    left:SetPoint("RIGHT", columnA, "RIGHT", 0, 0)
    left:SetHeight(232)

    self.scaleLabel = Theme.Label(left.content, "", fonts.row, Theme.color.text)
    self.scaleLabel:SetPoint("TOPLEFT", left.content, "TOPLEFT", 0, -2)

    local function setScale(delta)
        GA.UI.MainFrame:SetScale((GA.Core.Config:GetUI("main").scale or 1) + delta)
        Settings:Refresh()
    end
    local smaller = Widgets.Button(left.content, "-", function() setScale(-0.05) end)
    smaller:SetWidth(24) smaller:SetPoint("TOPLEFT", left.content, "TOPLEFT", 0, -22)
    local bigger = Widgets.Button(left.content, "+", function() setScale(0.05) end)
    bigger:SetWidth(24) bigger:SetPoint("LEFT", smaller, "RIGHT", 4, 0)
    local debug = Widgets.Button(left.content, L.SET_DEBUG, function()
        GA.Core.Debug:Toggle() Settings:Refresh()
    end)
    debug:SetPoint("LEFT", bigger, "RIGHT", 10, 0)
    self.debugState = Theme.Label(left.content, "", fonts.small, Theme.color.textFaint)
    self.debugState:SetPoint("LEFT", debug, "RIGHT", 8, 0)

    self.minimapBox = Widgets.CheckBox(left.content, L.SET_MINIMAP, function(checked)
        GA.UI.MinimapButton:SetShown(checked)
    end)
    self.minimapBox:SetPoint("TOPLEFT", left.content, "TOPLEFT", -4, -46)

    self.tooltipBox = Widgets.CheckBox(left.content, L.SET_TOOLTIPS, function(checked)
        GA.Core.Config:Set("tooltipItems", checked)
        GA.Core.Config:Set("tooltipPlayers", checked)
    end)
    self.tooltipBox:SetPoint("TOPLEFT", self.minimapBox, "BOTTOMLEFT", 0, -2)

    local tooltipHint = Theme.Label(left.content, L.SET_TOOLTIPS_HINT, fonts.small, Theme.color.textDim)
    tooltipHint:SetPoint("TOPLEFT", self.tooltipBox, "BOTTOMLEFT", 4, -2)
    tooltipHint:SetPoint("RIGHT", left.content, "RIGHT", 0, 0)
    tooltipHint:SetJustifyH("LEFT")

    self.rotationBox = Widgets.CheckBox(left.content, L.ROTATION_ENABLED, function(checked)
        GA.Core.Config:Set("rotationEnabled", checked)
    end)
    self.rotationBox:SetPoint("TOPLEFT", tooltipHint, "BOTTOMLEFT", -4, -6)

    self.rotationAnnounceBox = Widgets.CheckBox(left.content, L.ROTATION_ANNOUNCE_OPT,
        function(checked) GA.Core.Config:Set("rotationAnnounce", checked) end)
    self.rotationAnnounceBox:SetPoint("TOPLEFT", self.rotationBox, "BOTTOMLEFT", 0, -2)

    -- Freigabe
    local publish = Widgets.Panel(columnA, L.SET_DATA)
    publish:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -gap)
    publish:SetPoint("RIGHT", columnA, "RIGHT", 0, 0)
    publish:SetHeight(140)

    -- KEIN SCHALTER, SONDERN EINE FESTSTELLUNG.
    --
    -- Bis 20.09.2026 stand hier ein Kaestchen mit dem Versprechen "nichts
    -- verlaesst diesen Client, bis du es einschaltest". Die Gilde hat
    -- entschieden, dass Ausruestungsdaten geteilt werden. Ein Kaestchen, das
    -- man nicht mehr abwaehlen kann, waere eine Luege — also steht hier jetzt,
    -- was tatsaechlich hinausgeht und was nicht.
    local state = Theme.Label(publish.content, L.SET_PUBLISH_ON, fonts.body, Theme.color.jade)
    state:SetPoint("TOPLEFT", publish.content, "TOPLEFT", 0, 0)

    local hint = Theme.Label(publish.content, L.SET_PUBLISH_HINT, fonts.small, Theme.color.textDim)
    hint:SetPoint("TOPLEFT", state, "BOTTOMLEFT", 0, -6)
    hint:SetPoint("RIGHT", publish.content, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")

    -- Abgleich: wer laeuft noch mit dem Addon, und gab es Widersprueche?
    self.syncLine = Theme.Label(publish.content, "", fonts.small, Theme.color.textFaint)
    self.syncLine:SetPoint("BOTTOMLEFT", publish.content, "BOTTOMLEFT", 0, 14)
    self.syncLine:SetPoint("RIGHT", publish.content, "RIGHT", 0, 0)
    self.syncLine:SetJustifyH("LEFT")

    self.stats = Theme.Label(publish.content, "", fonts.small, Theme.color.textFaint)
    self.stats:SetPoint("BOTTOMLEFT", publish.content, "BOTTOMLEFT", 0, 0)

    -- Loot-Erfassung
    -- Feste Hoehe statt "bis zum Fensterboden": Der Inhalt ist eine Kette von
    -- acht Elementen mit bekannter Hoehe. Sie an den Boden zu heften hiesse,
    -- sie auf so viel Platz zu zwingen, wie zufaellig uebrig ist — und genau
    -- daran ist sie herausgelaufen.
    local loot = Widgets.Panel(columnB, L.SET_LOOT)
    loot:SetPoint("TOPLEFT", columnB, "TOPLEFT", 0, 0)
    loot:SetPoint("RIGHT", columnB, "RIGHT", 0, 0)
    loot:SetHeight(LOOT_PANEL_HEIGHT)

    -- Die hoehere der beiden Spalten bestimmt, wie weit der Bildlauf geht.
    self.columnHeights = {
        language:GetHeight() + gap + left:GetHeight() + gap + publish:GetHeight(),
        loot:GetHeight(),
    }

    self.thresholdLabel = Theme.Label(loot.content, "", fonts.row, Theme.color.text)
    self.thresholdLabel:SetPoint("TOPLEFT", loot.content, "TOPLEFT", 0, -2)

    self.thresholdButtons = {}
    local previousQuality
    for _, quality in ipairs({ 2, 3, 4 }) do
        local button = Widgets.Button(loot.content, L["QUALITY_" .. quality], function()
            GA.Core.Config:Set("lootThresholdQuality", quality)
            Settings:Refresh()
        end)
        button:SetHeight(20)
        if previousQuality then
            button:SetPoint("LEFT", previousQuality, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", loot.content, "TOPLEFT", 0, -22)
        end
        button.quality = quality
        self.thresholdButtons[#self.thresholdButtons + 1] = button
        previousQuality = button
    end

    self.soloBox = Widgets.CheckBox(loot.content, L.SET_LOOT_SOLO, function(checked)
        GA.Core.Config:Set("trackOutsideGroup", checked)
    end)
    self.soloBox:SetPoint("TOPLEFT", loot.content, "TOPLEFT", -4, -46)

    local soloHint = Theme.Label(loot.content, L.SET_LOOT_SOLO_HINT, fonts.small, Theme.color.textDim)
    soloHint:SetPoint("TOPLEFT", self.soloBox, "BOTTOMLEFT", 4, -4)
    soloHint:SetPoint("RIGHT", loot.content, "RIGHT", 0, 0)
    soloHint:SetJustifyH("LEFT")

    -- Ankuendigung im Gildenchat. Der einzige Weg, auf dem ein Addon etwas
    -- nach draussen bringt — und damit auch nach Discord, wenn die Gilde eine
    -- Bruecke am Gildenchat hat.
    self.announceBox = Widgets.CheckBox(loot.content, L.SET_ANNOUNCE, function(checked)
        GA.Core.Config:Set("announceLoot", checked)
    end)
    self.announceBox:SetPoint("TOPLEFT", soloHint, "BOTTOMLEFT", -8, -8)

    local announceHint = Theme.Label(loot.content, L.SET_ANNOUNCE_HINT, fonts.small, Theme.color.textDim)
    announceHint:SetPoint("TOPLEFT", self.announceBox, "BOTTOMLEFT", 4, -4)
    announceHint:SetPoint("RIGHT", loot.content, "RIGHT", 0, 0)
    announceHint:SetJustifyH("LEFT")

    -- Sammlerbetrieb. Steht bewusst hier unten und nicht prominent: Es ist
    -- eine Einstellung fuer genau einen Client, nicht fuer jeden Spieler.
    self.collectorBox = Widgets.CheckBox(loot.content, L.SET_COLLECTOR, function(checked)
        GA.Core.Config:Set("collectorMode", checked)
    end)
    self.collectorBox:SetPoint("TOPLEFT", announceHint, "BOTTOMLEFT", -8, -8)

    self.collectorHint = Theme.Label(loot.content, "", fonts.small, Theme.color.textDim)
    self.collectorHint:SetPoint("TOPLEFT", self.collectorBox, "BOTTOMLEFT", 4, -4)
    self.collectorHint:SetPoint("RIGHT", loot.content, "RIGHT", 0, 0)
    self.collectorHint:SetJustifyH("LEFT")

    -- Was dieser Client wirklich gesehen hat — nicht, was die API verspricht.
    self.measured = Theme.Label(loot.content, "", fonts.small, Theme.color.textFaint)
    self.measured:SetPoint("BOTTOMLEFT", loot.content, "BOTTOMLEFT", 0, 0)
    self.measured:SetPoint("RIGHT", loot.content, "RIGHT", 0, 0)
    self.measured:SetJustifyH("LEFT")


    -- Kein eigenes layout() mehr: Die Breiten kamen frueher aus einer
    -- Rechnung auf frame:GetWidth(). Seit die Bloecke links UND rechts
    -- verankert sind, ist das ein Widerspruch — eine gesetzte Breite und zwei
    -- Anker koennen nicht beide gelten. Die Anker gewinnen, die Rechnung war
    -- ab da wirkungslos und stand nur noch im Weg.

    self.frame = frame
    return frame
end

--- Hoehe des Bildlaufinhalts nachfuehren.
---
--- Gerechnet, nicht gemessen: GetTop und GetBottom liefern nil, solange das
--- Fenster nicht sichtbar ist — und Refresh laeuft auch dann. Die Hoehen der
--- Bloecke stehen fest, also ist die Rechnung die zuverlaessigere Quelle.
function Settings:UpdateColumnHeight()
    if not self.column then return end

    local tallest = 0
    for _, height in ipairs(self.columnHeights or {}) do
        if height > tallest then tallest = height end
    end
    self.column.content:SetHeight(math.max(1, tallest + PANEL_GAP))
    self.column:Refresh()
end

--- Stellt die Sprache um.
---
--- GA.L ist danach sofort neu gefuellt, aber das Fenster nicht: Jede
--- Beschriftung, die schon dasteht, wurde beim Bauen kopiert. Deshalb wird
--- hier nichts neu gezeichnet, sondern der Hinweis auf /reload gezeigt.
function Settings:ChooseLanguage(choice)
    if GA.Core.Locale:Choose(choice) then
        self.languageChanged = true
    end
    self:Refresh()
end

function Settings:Refresh()
    local chosen = GA.Core.Database.account.language or GA.Core.Locale.DEFAULT
    for _, button in ipairs(self.languageButtons) do
        button:SetEnabledState(button.choice ~= chosen)
    end
    if self.languageChanged then
        self.languageReload:Show()
        self.reloadButton:Show()
    end

    self.scaleLabel:SetText(string.format(L.SET_SCALE, GA.Core.Config:GetUI("main").scale or 1))
    local debugOn = GA.Core.Database.char.debug
    self.debugState:SetText(debugOn and L.SET_ON or L.SET_OFF)


    self.minimapBox:SetChecked(not GA.Core.Config:GetUI("minimap").hidden)
    self.tooltipBox:SetChecked(GA.Core.Config:Get("tooltipItems") and true or false)
    self.rotationBox:SetChecked(GA.Core.Config:Get("rotationEnabled") and true or false)
    self.rotationAnnounceBox:SetChecked(GA.Core.Config:Get("rotationAnnounce") and true or false)

    -- Abgleich. Konflikte stehen in Warnfarbe: Sie bedeuten, dass zwei Clients
    -- derselben Gilde etwas Widersprechendes gemeldet haben.
    local Sync = GA.Modules.Sync
    local conflicts = Sync.conflicts or 0
    self.syncLine:SetText(string.format(L.SET_SYNC, Sync:PeerCount(), conflicts))
    local syncColor = conflicts > 0 and Theme.color.warn or Theme.color.textFaint
    self.syncLine:SetTextColor(syncColor[1], syncColor[2], syncColor[3])

    local stats = GA.Core.Database:Stats()
    local storage = GA.Core.Database.storage or {}
    self.stats:SetText(string.format(L.SET_STATS,
        stats.characters, stats.awards, stats.journal, tostring(stats.schemaVersion))
        .. "  ·  " .. string.format(L.SET_STORAGE, tostring(storage.source)))
    local storageColor = storage.accountLoaded and Theme.color.textFaint or Theme.color.warn
    self.stats:SetTextColor(storageColor[1], storageColor[2], storageColor[3])

    -- Loot-Erfassung
    local threshold = GA.Core.Config:Get("lootThresholdQuality") or 3
    self.thresholdLabel:SetText(string.format(L.SET_LOOT_THRESHOLD,
        L["QUALITY_" .. threshold] or tostring(threshold)))
    for _, button in ipairs(self.thresholdButtons) do
        button:SetEnabledState(button.quality ~= threshold)
    end
    self.soloBox:SetChecked(GA.Core.Config:Get("trackOutsideGroup") and true or false)
    self.announceBox:SetChecked(GA.Core.Config:Get("announceLoot") and true or false)
    self.collectorBox:SetChecked(GA.Core.Config:Get("collectorMode") and true or false)
    self.collectorHint:SetText(string.format(L.SET_COLLECTOR_HINT,
        tonumber(GA.Core.Config:Get("collectorMinutes")) or 60))

    local seen = {}
    local measured = GA.Core.Database.account.measured
    for method in pairs((measured and measured.lootMethods) or {}) do
        seen[#seen + 1] = L["LOOT_" .. string.upper(method)] or method
    end
    table.sort(seen)
    -- Beobachtete Lootmethoden und die Groesse des Itemverzeichnisses: beides
    -- sagt, worauf dieser Client gerade tatsaechlich zurueckgreifen kann.
    self.measured:SetText(string.format(L.SET_MEASURED,
            #seen > 0 and table.concat(seen, ", ") or L.SET_MEASURED_NONE)
        .. "\n"
        .. string.format(L.SET_ITEMINDEX, GA.Modules.ItemIndex:Count()))

    -- Erst nach dem Setzen aller Texte: Die Hoehe der Hinweiszeilen steht
    -- vorher nicht fest, und der Bildlauf soll nicht raten.
    self:UpdateColumnHeight()

    GA.UI.MainFrame:SetContext("v" .. GA.version)
end

GA.UI.MainFrame:RegisterView("settings", Settings)
