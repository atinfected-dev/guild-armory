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


--- Abstand zwischen zwei Bloecken.
local PANEL_GAP = 8

--- Startwert fuer den Loot-Block, bis er sich selbst gemessen hat.
---
--- Er stand frueher fest auf 450 und war damit rund 90 Pixel zu klein —
--- was nicht hineinpasste, lief in das naechste Kaestchen. Jetzt rechnet
--- RelayoutLoot die Hoehe aus dem Inhalt aus; diese Zahl gilt nur fuer die
--- Augenblicke davor, in denen die Breite noch nicht feststeht.
local LOOT_PANEL_HEIGHT = 450
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
    -- Keine feste Hoehe: siehe tools/test/fixedheights.test.js. Der Text
    -- ist auf Deutsch laenger als auf Englisch, und die Wette darauf, dass
    -- zwei Zeilen reichen, ist genau die, die hier schon einmal verloren
    -- ging.

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

    -- Lager
    --
    -- EIGENES PANEL STATT EINER ZEILE WEITER OBEN. Die Erklaerung ist lang,
    -- weil sie sagen muss, was dieser Client ueber einen verschickt — und die
    -- Bloecke darueber haben feste Hoehen. Ein umbrechender Text in einem
    -- Block fester Hoehe ist genau die Wette, die in dieser Datei schon
    -- zweimal verloren gegangen ist. Hier misst er sich selbst.
    local camp = Widgets.Panel(columnA, L.SET_ONSCREEN)
    camp:SetPoint("TOPLEFT", publish, "BOTTOMLEFT", 0, -gap)
    camp:SetPoint("RIGHT", columnA, "RIGHT", 0, 0)
    camp:SetHeight(72)
    self.campPanel = camp

    self.campBox = Widgets.CheckBox(camp.content, L.SET_CAMP, function(checked)
        GA.Core.Config:Set("campEnabled", checked)
        if checked then GA.UI.CampFrame:Show() else GA.UI.CampFrame:Hide() end
    end)
    self.campHint = Theme.Label(camp.content, L.SET_CAMP_HINT, fonts.small, Theme.color.textDim)

    self.mapBox = Widgets.CheckBox(camp.content, L.SET_MAP, function(checked)
        GA.Core.Config:Set("mapShare", checked)
        local Positions = GA.Modules.Positions
        if not Positions then return end
        if checked then
            Positions:Publish(true)
        else
            -- Aus heisst aus: auch das, was schon hereingekommen ist,
            -- verschwindet. Sonst blieben die Nadeln stehen, bis jemand
            -- neu einloggt.
            wipe(Positions.states)
            if GA.UI.MapPins then GA.UI.MapPins:HideAll() end
        end
    end)
    self.mapHint = Theme.Label(camp.content, L.SET_MAP_HINT, fonts.small, Theme.color.textDim)

    -- HIER STAND EIN LEBENSBALKEN. Er ist wieder heraus, weil dieser Client
    -- keine lesbaren Lebenswerte herausgibt — gemessen am 24.09.2026 ueber
    -- beide Wege, UnitHealth und Blizzards eigene Leiste, und beide Male
    -- werfen Rechnen UND Vergleichen. Ein Schalter, der nachweislich nie
    -- etwas tun kann, macht die Liste laenger und wirft bei jedem, der ihn
    -- findet, dieselbe Frage auf. `/ga probe` zeigt die beiden Zeilen.

    camp.content:SetScript("OnSizeChanged", function() Settings:RelayoutCamp() end)

    -- Die linke Spalte ist eine Kette fester Bloecke; das Lagerpanel und die
    -- rechte Spalte tragen ihre Hoehe selbst ein, sobald sie gemessen haben.
    self.columnAFixed = language:GetHeight() + gap + left:GetHeight()
        + gap + publish:GetHeight() + gap
    self.columnHeights = {
        self.columnAFixed + camp:GetHeight(),
        LOOT_PANEL_HEIGHT,
    }
    self:RelayoutCamp()

    -- Loot-Erfassung
    --
    -- DIE HOEHEN WERDEN GEMESSEN, NICHT GESETZT.
    --
    -- Vorher hing hier eine Kette: jedes Kaestchen unter der Erklaerung des
    -- vorigen, und zwei dieser Erklaerungen hatten eine feste Hoehe
    -- (SetHeight(44) und SetHeight(28)). Das haelt genau so lange, wie der
    -- Text in die geratene Hoehe passt. Er passte nicht: Auf Englisch
    -- braucht die Combat-Log-Erklaerung fuenf Zeilen statt der
    -- eingeplanten drei, und die restlichen 16 Pixel landeten im naechsten
    -- Kaestchen.
    --
    -- Eine feste Hoehe fuer umbrechenden Text ist immer eine Wette auf
    -- Sprache, Schriftgroesse und Fensterbreite — drei Dinge, die sich alle
    -- aendern koennen. Deshalb sagt jetzt jede Erklaerung selbst, wie hoch
    -- sie ist (GetStringHeight), und der naechste Eintrag setzt darunter
    -- auf. Die Panelhoehe faellt hinten heraus, statt vorne geraten zu
    -- werden.
    local loot = Widgets.Panel(columnB, L.SET_LOOT)
    loot:SetPoint("TOPLEFT", columnB, "TOPLEFT", 0, 0)
    loot:SetPoint("RIGHT", columnB, "RIGHT", 0, 0)
    loot:SetHeight(LOOT_PANEL_HEIGHT)
    self.lootPanel = loot

    self.thresholdLabel = Theme.Label(loot.content, "", fonts.row, Theme.color.text)

    self.thresholdButtons = {}
    for _, quality in ipairs({ 2, 3, 4 }) do
        local button = Widgets.Button(loot.content, L["QUALITY_" .. quality], function()
            GA.Core.Config:Set("lootThresholdQuality", quality)
            Settings:Refresh()
        end)
        button:SetHeight(20)
        button.quality = quality
        self.thresholdButtons[#self.thresholdButtons + 1] = button
    end

    self.soloBox = Widgets.CheckBox(loot.content, L.SET_LOOT_SOLO, function(checked)
        GA.Core.Config:Set("trackOutsideGroup", checked)
    end)
    self.soloHint = Theme.Label(loot.content, L.SET_LOOT_SOLO_HINT, fonts.small,
        Theme.color.textDim)

    -- Ankuendigung im Gildenchat. Der einzige Weg, auf dem ein Addon etwas
    -- nach draussen bringt — und damit auch nach Discord, wenn die Gilde eine
    -- Bruecke am Gildenchat hat.
    self.announceBox = Widgets.CheckBox(loot.content, L.SET_ANNOUNCE, function(checked)
        GA.Core.Config:Set("announceLoot", checked)
    end)
    self.announceHint = Theme.Label(loot.content, L.SET_ANNOUNCE_HINT, fonts.small,
        Theme.color.textDim)

    -- Sammlerbetrieb. Steht bewusst hier unten und nicht prominent: Es ist
    -- eine Einstellung fuer genau einen Client, nicht fuer jeden Spieler.
    self.collectorBox = Widgets.CheckBox(loot.content, L.SET_COLLECTOR, function(checked)
        GA.Core.Config:Set("collectorMode", checked)
    end)
    self.collectorHint = Theme.Label(loot.content, "", fonts.small, Theme.color.textDim)

    -- Combat Log. Steht hier unten bei den Dingen, die etwas AUSSERHALB des
    -- Spiels anlegen — und wie der Sammlerbetrieb ist es aus, bis jemand es
    -- einschaltet.
    self.combatLogBox = Widgets.CheckBox(loot.content, L.SET_COMBATLOG, function(checked)
        GA.Core.Config:Set("autoCombatLog", checked)
        Settings:Refresh()
    end)
    self.combatLogHint = Theme.Label(loot.content, L.SET_COMBATLOG_HINT,
        fonts.small, Theme.color.textDim)

    self.offerBox = Widgets.CheckBox(loot.content, L.SET_OFFER_NEW, function(checked)
        GA.Core.Config:Set("offerNewFinds", checked)
        if GA.Modules.Tradables then GA.Modules.Tradables:Refresh() end
    end)
    self.offerHint = Theme.Label(loot.content, L.SET_OFFER_NEW_HINT,
        fonts.small, Theme.color.textDim)

    -- Was dieser Client wirklich gesehen hat — nicht, was die API verspricht.
    self.measured = Theme.Label(loot.content, "", fonts.small, Theme.color.textFaint)

    -- Neu messen, sobald die Breite steht: Vorher ist GetStringHeight
    -- wertlos, weil der Umbruch noch gar nicht feststeht.
    loot.content:SetScript("OnSizeChanged", function() Settings:RelayoutLoot() end)
    self:RelayoutLoot()



    -- Kein eigenes layout() mehr: Die Breiten kamen frueher aus einer
    -- Rechnung auf frame:GetWidth(). Seit die Bloecke links UND rechts
    -- verankert sind, ist das ein Widerspruch — eine gesetzte Breite und zwei
    -- Anker koennen nicht beide gelten. Die Anker gewinnen, die Rechnung war
    -- ab da wirkungslos und stand nur noch im Weg.

    self.frame = frame
    return frame
end

--- Setzt die rechte Spalte neu und misst dabei jede Erklaerung.
---
--- LAEUFT MEHRMALS UND MUSS DAS AUSHALTEN. Aufgerufen wird sie beim Bauen
--- (da ist die Breite oft noch 0), sobald die Breite steht, und nach jedem
--- Refresh — denn zwei der Texte aendern sich zur Laufzeit.
---
--- Ohne bekannte Breite wird NICHTS gesetzt: Ein Umbruch, der auf Breite 0
--- gerechnet wurde, ergibt eine sinnlose Hoehe, und die stuende dann fest,
--- bis jemand das Fenster in der Groesse aendert.
-- LAYOUT ANFANG (herausgeschnitten von tools/test/settingslayout.test.js)
function Settings:RelayoutLoot()
    local panel = self.lootPanel
    if not panel then return false end

    local content = panel.content
    local width = content:GetWidth() or 0
    if width <= 1 then return false end

    local y = 0

    --- Setzt eine Erklaerung auf volle Breite und gibt ihre Hoehe zurueck.
    local function hint(label, indent)
        label:SetWidth(width - indent)
        label:SetJustifyH("LEFT")
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", content, "TOPLEFT", indent, y)
        -- GetStringHeight ist die Hoehe des UMGEBROCHENEN Textes, also das,
        -- was wirklich Platz braucht. GetHeight waere die gesetzte Hoehe —
        -- und die zu lesen, nachdem man sie selbst gesetzt hat, beweist
        -- nichts.
        local height = label:GetStringHeight() or 0
        if height <= 0 then height = 12 end
        label:SetHeight(height)
        y = y - height
    end

    --- Setzt ein Kaestchen und rueckt um SEINE Hoehe weiter, nicht um eine
    --- angenommene. Ein Kaestchen ist heute 26 Pixel hoch; das ist eine
    --- Zahl aus Widgets.CheckBox und keine, die hier noch einmal geraten
    --- werden sollte.
    local function box(check, gapAbove)
        y = y - (gapAbove or 8)
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT", content, "TOPLEFT", -4, y)
        y = y - (check:GetHeight() or 26)
    end

    -- Schwelle: Beschriftung, darunter die drei Knoepfe nebeneinander.
    self.thresholdLabel:ClearAllPoints()
    self.thresholdLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - (self.thresholdLabel:GetStringHeight() or 14) - 6

    local previous
    for _, button in ipairs(self.thresholdButtons) do
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        end
        previous = button
    end
    y = y - (self.thresholdButtons[1] and self.thresholdButtons[1]:GetHeight() or 20)

    box(self.soloBox, 10)
    hint(self.soloHint, 4)

    box(self.announceBox)
    hint(self.announceHint, 4)

    box(self.collectorBox)
    hint(self.collectorHint, 4)

    box(self.combatLogBox)
    hint(self.combatLogHint, 4)

    box(self.offerBox)
    hint(self.offerHint, 4)

    y = y - 10
    hint(self.measured, 0)

    -- Die Panelhoehe faellt aus dem Inhalt heraus. Der Kopf und die
    -- Innenraender des Panels kommen dazu: content ist um 8 Pixel je Seite
    -- eingerueckt und sitzt unter einer 24 Pixel hohen Kopfleiste.
    local needed = -y + 24 + 16
    if math.abs((panel:GetHeight() or 0) - needed) > 0.5 then
        panel:SetHeight(needed)
    end

    self.columnHeights = self.columnHeights or {}
    self.columnHeights[2] = needed
    self:UpdateColumnHeight()
    return true
end

--- Dasselbe fuer das Lagerpanel: Kaestchen, darunter die gemessene
--- Erklaerung, und die Panelhoehe faellt hinten heraus.
---
--- Die Erklaerung ist die laengste im ganzen Fenster — sie muss sagen, was
--- dieser Client ueber einen verschickt. Genau deshalb darf ihre Hoehe
--- nirgends geraten werden.
function Settings:RelayoutCamp()
    local panel = self.campPanel
    if not panel then return false end

    local content = panel.content
    local width = content:GetWidth() or 0
    if width <= 1 then return false end

    local y = 0

    -- DREI PAARE, EINE SCHLEIFE. Jede Erklaerung misst sich selbst und
    -- schiebt das naechste Kaestchen nach unten. Die Alternative waere
    -- dreimal derselbe Block mit drei geratenen Abstaenden — und genau so
    -- ist diese Spalte schon einmal ineinandergelaufen.
    local paare = {
        { self.campBox, self.campHint },
        { self.mapBox, self.mapHint },
    }

    for index, paar in ipairs(paare) do
        local box, hint = paar[1], paar[2]
        if index > 1 then y = y - 8 end

        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", content, "TOPLEFT", -4, y)
        y = y - (box:GetHeight() or 26)

        hint:SetWidth(width - 4)
        hint:SetJustifyH("LEFT")
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
        local height = hint:GetStringHeight() or 0
        if height <= 0 then height = 12 end
        hint:SetHeight(height)
        y = y - height
    end

    local needed = -y + 24 + 16
    if math.abs((panel:GetHeight() or 0) - needed) > 0.5 then
        panel:SetHeight(needed)
    end

    self.columnHeights = self.columnHeights or {}
    self.columnHeights[1] = (self.columnAFixed or 0) + needed
    self:UpdateColumnHeight()
    return true
end
-- LAYOUT ENDE

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

    -- DER HINWEIS SAGT DIE WAHRHEIT UEBER DIESEN CLIENT, nicht ueber die
    -- Absicht: Ist die Einstellung an und der Client kann es nicht, steht
    -- das da — statt ein Haekchen zu zeigen, hinter dem nichts passiert.
    local an = GA.Core.Config:Get("autoCombatLog") and true or false
    self.combatLogBox:SetChecked(an)
    self.offerBox:SetChecked(GA.Core.Config:Get("offerNewFinds") and true or false)
    if an and GA.Modules.CombatLog and GA.Modules.CombatLog:Available() == false then
        self.combatLogHint:SetText(L.COMBATLOG_UNAVAILABLE)
        self.combatLogHint:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
    else
        self.combatLogHint:SetText(L.SET_COMBATLOG_HINT)
        self.combatLogHint:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
    end
    self.collectorHint:SetText(string.format(L.SET_COLLECTOR_HINT,
        tonumber(GA.Core.Config:Get("collectorMinutes")) or 60))

    -- ~= false, nicht "and true or false": Die Voreinstellung ist AN, und ein
    -- noch nie gesetzter Wert ist nil. Wer hier auf Wahrheit prueft, zeigt
    -- beim ersten Oeffnen ein leeres Kaestchen fuer etwas, das laeuft.
    self.campBox:SetChecked(GA.Core.Config:Get("campEnabled") ~= false)
    self.campHint:SetText(L.SET_CAMP_HINT)
    self.mapBox:SetChecked(GA.Core.Config:Get("mapShare") ~= false)
    self.mapHint:SetText(L.SET_MAP_HINT)

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

    -- ERST NACH DEM SETZEN ALLER TEXTE NEU MESSEN.
    --
    -- Zwei Erklaerungen aendern sich hier oben: die des Combat Logs (sie
    -- wird zur Warnung, wenn das Mitschreiben nicht geht) und die des
    -- Sammlerbetriebs (sie traegt die eingestellten Minuten). Beide koennen
    -- dabei laenger oder kuerzer werden — wer vorher misst, misst den alten
    -- Text.
    self:RelayoutLoot()
    self:RelayoutCamp()
    self:UpdateColumnHeight()

    GA.UI.MainFrame:SetContext("v" .. GA.version)
end

GA.UI.MainFrame:RegisterView("settings", Settings)
