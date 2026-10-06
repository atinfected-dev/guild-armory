--[[----------------------------------------------------------------------------
    Views/Settings — Register links, eine Seite rechts (Entwurf S1, 29.09.2026).

    Sechs Abschnitte: Sprache, Fenster, Am Bildschirm, Meldungen, Loot, Daten.
    Links die Leiste mit den Abschnitten, darunter das, was dieser Client
    gemessen hat. Rechts die Seite des gewaehlten Abschnitts: Titel,
    Untertitel, und darunter die Zeilen — je Einstellung Titel, Hinweis und
    rechts ein Schalter. Grau ist aus, gold ist an.

    JEDE ZEILE MISST SICH SELBST. Ein umbrechender Hinweis hat keine feste
    Hoehe; LayoutPage fragt jede Zeile, wie hoch sie bei der aktuellen Breite
    ist, und setzt die naechste darunter (tools/test/settingslayout.test.js
    stellt Texte verschiedener Laenge und prueft, dass nichts ineinander
    laeuft — die Wette auf eine geratene Hoehe ging in dieser Datei schon
    zweimal verloren).

    Die Freigabe eigener Charakterdaten ist keine Einstellung mehr, sondern
    eine Feststellung (Abschnitt Daten): Die Gilde hat entschieden, dass
    Ausruestung geteilt wird; hier steht, was hinausgeht und was nicht.
------------------------------------------------------------------------------]]

local _, GA = ...

local Settings = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local L = GA.L

Settings.titleKey = "NAV_SETTINGS"

local NAV_W = 190
local ROW_PAD = 12          -- Innenabstand einer Zeile oben/unten
local ROW_MIN = 44          -- eine Zeile ist nie flacher als ihr Schalter + Luft
local CONTROL_GAP = 16      -- zwischen Text und Schalter

--- Die Auswahl, in der Reihenfolge der Knoepfe. "auto" steht hinten: Es ist
--- die Ausnahme, nicht der Normalfall (siehe Localization/Locale.lua).
local LANGUAGES = { "enUS", "deDE", "auto" }

--- Die Abschnitte, in der Reihenfolge der Leiste.
local SECTIONS = {
    { key = "language", title = "SET_UI_LANGUAGE", sub = "SET_SUB_UI_LANGUAGE" },
    { key = "window",   title = "SET_WINDOW",   sub = "SET_SUB_WINDOW" },
    { key = "onscreen", title = "SET_ONSCREEN", sub = "SET_SUB_ONSCREEN" },
    -- Raid (06.10.2026): Erinnerungen, Ready Check, Kampflog — vorher auf
    -- "Am Bildschirm" verstreut, wo man sie schwer fand.
    { key = "raid",     title = "SET_RAID",     sub = "SET_SUB_RAID" },
    { key = "notify",   title = "SET_NOTIFY",   sub = "SET_SUB_NOTIFY" },
    { key = "loot",     title = "SET_LOOT",     sub = "SET_SUB_LOOT" },
    { key = "data",     title = "SET_DATA",     sub = "SET_SUB_DATA" },
    { key = "about",    title = "SET_ABOUT",    sub = "SET_SUB_ABOUT" },
}

-- ================================================================== Zeilen ----

--- Eine Zeile: Titel, Hinweis (umbrechend), rechts ein Bedienelement.
---
--- @param page table  die Seite (page.box ist der Rahmen der Zeilen)
--- @param spec table  { label, hint, control = "switch"|"none", get, set, build }
---   build(row) darf eigene Elemente anlegen und MUSS dann eine Funktion
---   measure(width) -> hoehe zurueckgeben, die sie setzt.
local function makeRow(page, spec)
    local fonts = Theme.Fonts()
    local row = CreateFrame("Frame", nil, page.box)
    row.spec = spec

    row.title = Theme.Label(row, spec.label or "", fonts.body, Theme.color.text)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 18, -ROW_PAD)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.hint = Theme.Label(row, spec.hint or "", fonts.small, Theme.color.textDim)
    row.hint:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.hint:SetJustifyH("LEFT")
    -- Keine feste Hoehe: siehe Dateikopf und tools/test/fixedheights.test.js.

    row.chip = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.chip:SetJustifyH("RIGHT")
    row.chip:Hide()

    if spec.control == "switch" then
        row.switch = Widgets.Switch(row, function(checked)
            if spec.set then spec.set(checked) end
            Settings:Refresh()
        end)
        row.switch:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        row.chip:SetPoint("RIGHT", row.switch, "LEFT", -10, 0)
    else
        row.chip:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    end

    if spec.build then row.measureCustom = spec.build(row) end

    page.rows[#page.rows + 1] = row
    return row
end

--- Eine Zwischenueberschrift in einer Seite (06.10.2026: "ordne die
--- Einstellungen in Unterkategorien, man tut sich schwer, was zu finden").
--- Eine Zeile wie die anderen — misst sich, bekommt ihre Trennlinie —, nur
--- niedriger, in der Ueberschriftschrift und mit einem leichten Band.
local function makeHeading(page, text)
    local row = makeRow(page, { label = string.upper(text or "") })
    row.isHeading = true
    row.minHeight = 30
    local fonts = Theme.Fonts()
    row.title:SetFontObject(fonts.heading or fonts.body)
    row.title:SetTextColor(Theme.color.heading[1], Theme.color.heading[2], Theme.color.heading[3])
    row.band = Theme.Fill(row, { 1, 1, 1, 0.035 })
    return row
end

-- LAYOUT ANFANG (herausgeschnitten von tools/test/settingslayout.test.js)

--- Wie breit der Text einer Zeile sein darf: Breite minus Raender und Bedienelement.
local function textWidth(row, width)
    local reserved = 36
    if row.switch then reserved = reserved + 46 + CONTROL_GAP end
    if row.chip:IsShown() then reserved = reserved + (row.chip:GetStringWidth() or 0) + 10 end
    return math.max(60, width - reserved)
end

--- Misst eine Zeile bei gegebener Breite und setzt ihre Hoehe.
--- @return number hoehe
function Settings.MeasureRow(row, width)
    local tw = textWidth(row, width)
    row.title:SetWidth(tw)
    local height = ROW_PAD + (row.title:GetStringHeight() or 14)
    local hintText = row.hint:GetText()
    if hintText and hintText ~= "" then
        row.hint:SetWidth(tw)
        row.hint:Show()
        local h = row.hint:GetStringHeight() or 0
        if h <= 0 then h = 12 end
        -- GetStringHeight ist die Hoehe des UMGEBROCHENEN Textes; GetHeight
        -- waere die gesetzte, und die zu lesen, nachdem man sie selbst
        -- gesetzt hat, beweist nichts.
        row.hint:SetHeight(h)
        height = height + 3 + h
    else
        row.hint:Hide()
    end
    if row.measureCustom then
        height = height + (row.measureCustom(tw) or 0)
    end
    height = height + ROW_PAD
    local minimum = row.minHeight or ROW_MIN
    if height < minimum then height = minimum end
    row:SetHeight(height)
    return height
end

--- Setzt die Zeilen einer Seite untereinander, mit Trennlinien, und traegt
--- die Hoehe des Rahmens und des Bildlaufinhalts ein.
---
--- LAEUFT MEHRMALS UND MUSS DAS AUSHALTEN: beim Bauen (Breite oft noch 0),
--- sobald die Breite steht, und nach jedem Refresh, denn Texte aendern
--- sich zur Laufzeit. Ohne bekannte Breite wird NICHTS gesetzt.
function Settings.LayoutPage(page)
    local width = page.box:GetWidth() or 0
    if width <= 1 then return false end
    local y = 0
    local shown = 0
    for _, row in ipairs(page.rows) do
        -- Eine versteckte Zeile (der Reload-Hinweis vor der Umstellung)
        -- nimmt keinen Platz und zieht keine Trennlinie.
        if row:IsShown() then
            shown = shown + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", page.box, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", page.box, "RIGHT", 0, 0)
            local height = Settings.MeasureRow(row, width)
            y = y - height
        end
    end
    -- Trennlinien zwischen sichtbaren Zeilen, nicht unter der letzten.
    local seen = 0
    for _, row in ipairs(page.rows) do
        if row:IsShown() then
            seen = seen + 1
            if row.separator then row.separator:SetShown(seen < shown) end
        end
    end
    local boxHeight = math.max(1, -y)
    page.box:SetHeight(boxHeight)
    page.content:SetHeight((page.headHeight or 0) + boxHeight + 16)
    if page.scroll and page.scroll.Refresh then page.scroll:Refresh() end
    return true
end
-- LAYOUT ENDE

-- ================================================================== Aufbau ----

--- Eine Seite: Bildlauf, Kopf (Titel + Untertitel), darunter der Rahmen
--- mit den Zeilen.
function Settings:Page(parent, section)
    local fonts = Theme.Fonts()
    local scroll = Widgets.ScrollArea(parent)
    scroll:SetPoint("TOPLEFT", self.nav, "TOPRIGHT", 8, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
    scroll:Hide()

    local page = { key = section.key, scroll = scroll, content = scroll.content, rows = {} }

    page.title = Theme.Label(scroll.content, L[section.title] or section.key, fonts.big, Theme.color.heading)
    page.title:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 6, -10)
    page.subtitle = Theme.Label(scroll.content, L[section.sub] or "", fonts.small, Theme.color.textDim)
    page.subtitle:SetPoint("LEFT", page.title, "RIGHT", 12, -1)
    page.subtitle:SetWordWrap(false)
    page.headHeight = 44

    page.box = Widgets.Inset(scroll.content)
    page.box:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -page.headHeight)
    page.box:SetPoint("RIGHT", scroll.content, "RIGHT", -4, 0)
    page.box:SetHeight(1)
    page.box:SetScript("OnSizeChanged", function() Settings.LayoutPage(page) end)

    self.pages[section.key] = page
    return page
end

--- Ein Eintrag der Leiste links.
function Settings:NavEntry(section, index)
    local fonts = Theme.Fonts()
    local button = CreateFrame("Button", nil, self.nav)
    button:SetHeight(34)
    button:SetPoint("TOPLEFT", self.nav, "TOPLEFT", 6, -10 - (index - 1) * 36)
    button:SetPoint("RIGHT", self.nav, "RIGHT", -6, 0)
    button.fill = Theme.Fill(button, { 0, 0, 0, 0 })
    button.edge = Theme.Fill(button, Theme.color.goldMid)
    button.edge:ClearAllPoints()
    button.edge:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.edge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.edge:SetWidth(2)
    button.label = Theme.Label(button, L[section.title] or section.key, fonts.body, Theme.color.textDim)
    button.label:SetPoint("LEFT", button, "LEFT", 14, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    button.key = section.key
    button:SetScript("OnClick", function() Settings:ShowSection(section.key) end)
    button:SetScript("OnEnter", function(self)
        if Settings.current ~= self.key then Theme.Paint(self.fill, { 1, 1, 1, 0.04 }) end
    end)
    button:SetScript("OnLeave", function(self)
        if Settings.current ~= self.key then Theme.Paint(self.fill, { 0, 0, 0, 0 }) end
    end)
    self.navButtons[#self.navButtons + 1] = button
    return button
end

--- Sammeln-Taste: der naechste Tastendruck wird die Taste (ESC bricht ab).
function Settings:CaptureGatherKey()
    if GA.Core.Compat.InCombat() then GA.Core.Debug:Warn(L.SET_GATHER_KEY_COMBAT) return end
    self.capturingKey = true
    self.gatherKeyButton:SetLabel(L.SET_GATHER_KEY_PRESS)
    if self.gatherKeyButton.EnableKeyboard then self.gatherKeyButton:EnableKeyboard(true) end
    if self.gatherKeyButton.SetPropagateKeyboardInput then pcall(self.gatherKeyButton.SetPropagateKeyboardInput, self.gatherKeyButton, false) end
end

local MODIFIER_ONLY = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

function Settings:OnGatherKey(key)
    if not self.capturingKey or MODIFIER_ONLY[key] then return end
    self.capturingKey = false
    if self.gatherKeyButton.EnableKeyboard then self.gatherKeyButton:EnableKeyboard(false) end
    if key ~= "ESCAPE" then
        local full = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local ok, why = GA.Modules.Highlight:SetInteractKey(full)
        if ok then GA.Core.Debug:Info(L.SET_GATHER_KEY_SET, full)
        else GA.Core.Debug:Warn(L["SET_GATHER_KEY_" .. string.upper(tostring(why))] or tostring(why)) end
    end
    self:Refresh()
end

--- Wechselt den Abschnitt: Leiste und Seiten folgen.
function Settings:ShowSection(key)
    self.current = key
    for _, button in ipairs(self.navButtons) do
        local active = button.key == key
        Theme.Paint(button.fill, active and { 1, 1, 1, 0.06 } or { 0, 0, 0, 0 })
        button.edge:SetShown(active)
        local color = active and Theme.color.goldBright or Theme.color.textDim
        button.label:SetTextColor(color[1], color[2], color[3])
    end
    for pageKey, page in pairs(self.pages) do
        page.scroll:SetShown(pageKey == key)
    end
    local page = self.pages[key]
    if page then Settings.LayoutPage(page) end
    GA.Core.Config:GetUI("settings").section = key
end

function Settings:Create(parent)
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame
    self.pages = {}
    self.navButtons = {}
    self.switches = {}

    -- ------------------------------------------------------------ Leiste ----
    local nav = Widgets.Inset(frame)
    nav:SetWidth(NAV_W)
    nav:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    nav:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    self.nav = nav
    for index, section in ipairs(SECTIONS) do self:NavEntry(section, index) end

    -- Was dieser Client gemessen hat — unten in der Leiste, klein.
    self.factsHead = Theme.Label(nav, string.upper(L.SET_NAV_FACTS), fonts.heading, Theme.color.goldDim)
    self.factsHead:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 14, 70)
    self.facts = Theme.Label(nav, "", fonts.small, Theme.color.textFaint)
    self.facts:SetPoint("TOPLEFT", self.factsHead, "BOTTOMLEFT", 0, -4)
    self.facts:SetPoint("RIGHT", nav, "RIGHT", -10, 0)
    self.facts:SetJustifyH("LEFT")
    self.facts:SetSpacing(2)

    for _, section in ipairs(SECTIONS) do self:Page(frame, section) end

    -- ------------------------------------------------------------ Sprache ---
    --
    -- Drei Knoepfe statt einer Auswahlliste — bei drei Moeglichkeiten ist
    -- eine Liste ein Klick zu viel, und man sieht sofort, was gerade gilt.
    -- Der Hinweis auf /reload steht erst da, wenn er stimmt: nach einer
    -- Umstellung, zusammen mit dem Knopf, der sie abschliesst.
    local language = self.pages.language
    self.languageButtons = {}

    -- Look (05.10.2026): die drei Entwuerfe und Blizzards Fenster, zur Wahl
    -- neben der Sprache. Wirkt nach /reload — die Fenster sind schon gebaut.
    self.lookButtons = {}
    makeRow(language, { label = L.SET_LOOK, hint = L.SET_LOOK_HINT, build = function(row)
        local previous
        for _, choice in ipairs(Theme.LOOK_ORDER) do
            local button = Widgets.Button(row, L["SET_LOOK_" .. string.upper(choice)],
                function() Settings:ChooseLook(choice) end)
            button:SetHeight(20)
            button.choice = choice
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8) end
            -- Farbprobe unter dem Knopf: Grund, Akzent, Hinweis des Looks —
            -- man sieht vor dem Neuladen, was man waehlt.
            local def = Theme.LOOKS[choice]
            if def then
                local probe = { def.palette.panelBg, def.palette.gold, def.palette.attn or def.palette.goldMid }
                local part = math.floor((button:GetWidth() or 60) / 3)
                for i, color in ipairs(probe) do
                    local strip = row:CreateTexture(nil, "ARTWORK")
                    strip:SetHeight(3)
                    strip:SetWidth(part)
                    strip:SetPoint("TOPLEFT", button, "BOTTOMLEFT", (i - 1) * part, -2)
                    Theme.Paint(strip, { color[1], color[2], color[3], 1 })
                end
            end
            Settings.lookButtons[#Settings.lookButtons + 1] = button
            previous = button
        end
        return function() return 34 end
    end })
    makeRow(language, { label = L.SET_LANGUAGE, hint = L.SET_LANGUAGE_HINT, build = function(row)
        local previous
        for _, choice in ipairs(LANGUAGES) do
            local button = Widgets.Button(row, L["SET_LANGUAGE_" .. string.upper(choice)],
                function() Settings:ChooseLanguage(choice) end)
            button:SetHeight(20)
            button.choice = choice
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8) end
            Settings.languageButtons[#Settings.languageButtons + 1] = button
            previous = button
        end
        return function() return 28 end
    end })
    self.reloadRow = makeRow(language, { label = "", hint = L.SET_LANGUAGE_RELOAD, build = function(row)
        row.hint:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
        Settings.reloadButton = Widgets.Button(row, L.BTN_RELOAD, function()
            if type(_G.ReloadUI) == "function" then ReloadUI() end
        end, "primary")
        Settings.reloadButton:SetHeight(20)
        Settings.reloadButton:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8)
        return function() return 28 end
    end })

    -- ------------------------------------------------------------ Fenster ---
    local window = self.pages.window
    makeHeading(window, L.SET_H_WINDOW)
    makeRow(window, { label = L.SET_SCALE_ROW, hint = L.SET_SCALE_HINT, build = function(row)
        local function setScale(delta)
            GA.UI.MainFrame:SetScale((GA.Core.Config:GetUI("main").scale or 1) + delta)
            Settings:Refresh()
        end
        Settings.scaleValue = Theme.Label(row, "", fonts.body, Theme.color.goldMid)
        Settings.scaleValue:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        local bigger = Widgets.Button(row, "+", function() setScale(0.05) end)
        bigger:SetWidth(24) bigger:SetHeight(20)
        bigger:SetPoint("RIGHT", Settings.scaleValue, "LEFT", -10, 0)
        local smaller = Widgets.Button(row, "-", function() setScale(-0.05) end)
        smaller:SetWidth(24) smaller:SetHeight(20)
        smaller:SetPoint("RIGHT", bigger, "LEFT", -4, 0)
        return function() return 0 end
    end })
    self.rowMinimap = makeRow(window, { label = L.SET_MINIMAP, hint = L.SET_MINIMAP_HINT, control = "switch",
        set = function(on) GA.UI.MinimapButton:SetShown(on) end })
    makeHeading(window, L.SET_H_CONTROLS)
    self.rowTooltips = makeRow(window, { label = L.SET_TOOLTIPS, hint = L.SET_TOOLTIPS_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("tooltipItems", on) GA.Core.Config:Set("tooltipPlayers", on) end })
    -- DIE J-TASTE (28.09.2026): Blizzards Gildenfenster fuehrt zum
    -- Verzeichnis. Aus, bis jemand es will — es biegt eine Erwartung von
    -- zehn Jahren um.
    self.rowGuildKey = makeRow(window, { label = L.SET_GUILDKEY, hint = L.SET_GUILDKEY_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("guildKeyOpensAddon", on) end })

    -- Bereiche ausblenden (06.10.2026): ein Schalter je Reiter.
    makeHeading(window, L.SET_H_TABS)
    self.sectionRows = {}
    for _, section in ipairs(GA.UI.MainFrame.HideableSections()) do
        local key = section.key
        local row = makeRow(window, {
            label = string.format(L.SET_SECTION, L[section.label] or key),
            hint = self.sectionRows[1] and "" or L.SET_SECTION_HINT,
            control = "switch",
            set = function(on) GA.UI.MainFrame:SetSectionHidden(key, not on) end })
        row.sectionKey = key
        self.sectionRows[#self.sectionRows + 1] = row
    end

    -- ------------------------------------------------------ Am Bildschirm ---
    local onscreen = self.pages.onscreen
    local raid = self.pages.raid
    makeHeading(onscreen, L.SET_H_CAMP)
    self.rowCamp = makeRow(onscreen, { label = L.SET_CAMP, hint = L.SET_CAMP_HINT, control = "switch",
        set = function(on)
            GA.Core.Config:Set("campEnabled", on)
            if on then GA.UI.CampFrame:Show() else GA.UI.CampFrame:Hide() end
        end })
    makeHeading(onscreen, L.SET_H_MAP)
    self.rowMap = makeRow(onscreen, { label = L.SET_MAP, hint = L.SET_MAP_HINT, control = "switch",
        set = function(on)
            GA.Core.Config:Set("mapShare", on)
            local Positions = GA.Modules.Positions
            if not Positions then return end
            if on then
                Positions:Publish(true)
            else
                -- Aus heisst aus: auch das, was schon hereingekommen ist,
                -- verschwindet. Sonst blieben die Nadeln stehen, bis jemand
                -- neu einloggt.
                wipe(Positions.states)
                if GA.UI.MapPins then GA.UI.MapPins:HideAll() end
            end
        end })
    -- Die Beschriftung ist eine ANZEIGEFRAGE, kein Datenschalter: Sie
    -- aendert nichts daran, was gesendet oder empfangen wird.
    self.rowMapLabels = makeRow(onscreen, { label = L.SET_MAP_LABELS, hint = L.SET_MAP_LABELS_HINT, control = "switch",
        set = function(on)
            GA.Core.Config:Set("mapPinLabels", on)
            if GA.UI.MapPins then GA.UI.MapPins:Refresh() end
        end })
    -- Die Nadel selbst: Wappen oder Punkt, und wie gross. Beides wirkt
    -- sofort auf der offenen Karte.
    self.pinStyleChips = {}
    makeRow(onscreen, { label = L.SET_PIN_STYLE, hint = L.SET_PIN_STYLE_HINT, build = function(row)
        local previous
        for _, style in ipairs({ "crest", "dot" }) do
            local chip = Widgets.Chip(row, L["SET_PIN_STYLE_" .. string.upper(style)], function()
                GA.Core.Config:Set("mapPinStyle", style)
                if GA.UI.MapPins then GA.UI.MapPins:Refresh() end
                Settings:Refresh()
            end)
            chip:SetHeight(20)
            chip.style = style
            if previous then chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else chip:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8) end
            Settings.pinStyleChips[#Settings.pinStyleChips + 1] = chip
            previous = chip
        end
        return function() return 28 end
    end })
    makeRow(onscreen, { label = L.SET_PIN_SIZE, hint = L.SET_PIN_SIZE_HINT, build = function(row)
        Settings.pinSize = Widgets.Slider(row, 12, 40, 2, function(value)
            GA.Core.Config:Set("mapPinSize", value)
            if GA.UI.MapPins then GA.UI.MapPins:Refresh() end
        end)
        Settings.pinSize.format = "%d px"
        Settings.pinSize:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 4, -10)
        Settings.pinSize:SetWidth(180)
        return function() return 30 end
    end })

    -- Sammeln & Quests (06.10.2026): das naechste benutzbare Objekt markieren.
    makeHeading(onscreen, L.SET_H_GATHER)
    self.rowHighlight = makeRow(onscreen, { label = L.SET_HIGHLIGHT, hint = L.SET_HIGHLIGHT_HINT, control = "switch",
        set = function(on) GA.Modules.Highlight:SetEnabled(on) end })
    -- Reichweite: einstellbar, weil nicht gemessen ist, ob Forever mehr als 20 annimmt.
    makeRow(onscreen, { label = L.SET_HIGHLIGHT_RANGE, hint = L.SET_HIGHLIGHT_RANGE_HINT, build = function(row)
        local function step(delta)
            local H = GA.Modules.Highlight
            local range, accepted, now = H:SetRange(H.Range() + delta)
            if accepted == false then GA.Core.Debug:Warn(L.HL_RANGE_REFUSED, range, tostring(now)) end
            Settings:Refresh()
        end
        Settings.rangeValue = Theme.Label(row, "", fonts.body, Theme.color.goldMid)
        Settings.rangeValue:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        local more = Widgets.Button(row, "+", function() step(GA.Modules.Highlight.RANGE_STEP) end)
        more:SetWidth(24) more:SetHeight(20)
        more:SetPoint("RIGHT", Settings.rangeValue, "LEFT", -10, 0)
        local less = Widgets.Button(row, "-", function() step(-GA.Modules.Highlight.RANGE_STEP) end)
        less:SetWidth(24) less:SetHeight(20)
        less:SetPoint("RIGHT", more, "LEFT", -4, 0)
        return function() return 0 end
    end })
    -- Sammeln per Taste (06.10.2026): Blizzards eigene Aktion "Mit Ziel
    -- interagieren" — bei eingeschalteter Markierung sammelt sie das
    -- markierte Objekt. Selbst sammeln darf ein Addon nicht (geschuetzt);
    -- eine Taste auf die Spielaktion legen darf es, ausser im Kampf.
    makeRow(onscreen, { label = L.SET_GATHER_KEY, hint = L.SET_GATHER_KEY_HINT, build = function(row)
        local button = Widgets.Button(row, "", function() Settings:CaptureGatherKey() end)
        button:SetHeight(20)
        button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8)
        button:SetScript("OnKeyDown", function(_, key) Settings:OnGatherKey(key) end)
        if button.EnableKeyboard then button:EnableKeyboard(false) end
        Settings.gatherKeyButton = button
        return function() return 28 end
    end })
    self.rowHighlightMarker = makeRow(onscreen, { label = L.SET_HIGHLIGHT_MARKER, hint = L.SET_HIGHLIGHT_MARKER_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("highlightMarker", on) if not on then GA.UI.HighlightFrame:DetachMarker() end end })
    self.rowHighlightSound = makeRow(onscreen, { label = L.SET_HIGHLIGHT_SOUND, hint = L.SET_HIGHLIGHT_SOUND_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("highlightSound", on) end })

    makeHeading(onscreen, L.SET_H_GUILDCHAT)
    -- DIESER SCHALTER SCHREIBT IN DEN GILDENCHAT: Wer ihn anstellt, soll
    -- vorher wissen, dass die Gilde es liest.
    self.rowLevelUp = makeRow(onscreen, { label = L.SET_LEVELUP, hint = L.SET_LEVELUP_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("levelUpAnnounce", on) end })

    -- ---------------------------------------------------------------- Raid --
    -- Raidplan-Erinnerungen (06.10.2026).
    makeHeading(raid, L.SET_H_REMINDERS)
    self.rowReminders = makeRow(raid, { label = L.SET_REMINDERS, hint = L.SET_REMINDERS_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("raidReminders", on) end })
    self.rowReminderSound = makeRow(raid, { label = L.SET_REMINDER_SOUND, hint = L.SET_REMINDER_SOUND_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("raidReminderSound", on) end })
    -- Verschieben und Testen ohne Boss (06.10.2026).
    makeRow(raid, { label = L.SET_REMINDER_PLACE, hint = L.SET_REMINDER_PLACE_HINT, build = function(row)
        local move = Widgets.Button(row, L.SET_REMINDER_MOVE_BTN, function() GA.UI.ReminderFrame:ToggleUnlocked() end)
        move:SetHeight(20)
        move:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8)
        local test = Widgets.Button(row, L.SET_REMINDER_TEST_BTN, function() GA.Modules.Reminders:Demo() end)
        test:SetHeight(20)
        test:SetPoint("LEFT", move, "RIGHT", 6, 0)
        return function() return 28 end
    end })

    -- Ready Check fuer sich selbst (06.10.2026).
    makeHeading(raid, L.SET_H_READY)
    self.rowReady = makeRow(raid, { label = L.SET_READY, hint = L.SET_READY_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("readyCheck", on) end })
    self.rowReadyEnchants = makeRow(raid, { label = L.SET_READY_ENCHANTS, hint = L.SET_READY_ENCHANTS_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("readyEnchants", on) end })
    self.rowReadyConsumables = makeRow(raid, { label = L.SET_READY_CONSUMABLES, hint = L.SET_READY_CONSUMABLES_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("readyConsumables", on) end })

    -- Discord-Bot (03.10.2026): haengt Maschinenmarken an die Discord-Zeilen
    -- des Dungeonhubs. Aus, bis die Gilde den Bot laufen hat.
    self.rowDiscordBot = makeRow(onscreen, { label = L.SET_DISCORD_BOT, hint = L.SET_DISCORD_BOT_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("discordBot", on) end })

    -- ------------------------------------------------------------ Meldungen -
    --
    -- Je Art ein Schalter (28.09.2026). Aus heisst: weder Streifen noch
    -- Ablage. Erfolge sind aus, bis jemand sie will — ein Gildenerster ist
    -- eine Behauptung, keine Nachricht.
    local notify = self.pages.notify
    self.rowNotifyAll = makeRow(notify, { label = L.SET_NOTIFY_ALL, hint = L.SET_NOTIFY_ALL_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("notifyEnabled", on) end })
    self.notifyRows = {}
    for _, key in ipairs({ "Tradables", "Questhub", "Dungeon", "Camp", "Achievements" }) do
        local row = makeRow(notify, { label = L["SET_NOTIFY_" .. string.upper(key)],
            hint = L["SET_NOTIFY_" .. string.upper(key) .. "_HINT"], control = "switch",
            set = function(on) GA.Core.Config:Set("notify" .. key, on) end })
        row.notifyKey = key
        self.notifyRows[#self.notifyRows + 1] = row
    end

    -- ------------------------------------------------------------ Loot ------
    local loot = self.pages.loot
    makeHeading(loot, L.SET_H_SESSION)
    self.thresholdButtons = {}
    self.rowThreshold = makeRow(loot, { label = "", hint = L.SET_LOOT_THRESHOLD_HINT, build = function(row)
        local previous
        for _, quality in ipairs({ 2, 3, 4 }) do
            local button = Widgets.Button(row, L["QUALITY_" .. quality], function()
                GA.Core.Config:Set("lootThresholdQuality", quality)
                Settings:Refresh()
            end)
            button:SetHeight(20)
            button.quality = quality
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8) end
            Settings.thresholdButtons[#Settings.thresholdButtons + 1] = button
            previous = button
        end
        return function() return 28 end
    end })
    self.rowOffer = makeRow(loot, { label = L.SET_OFFER_NEW, hint = L.SET_OFFER_NEW_HINT, control = "switch",
        set = function(on)
            GA.Core.Config:Set("offerNewFinds", on)
            if GA.Modules.Tradables then GA.Modules.Tradables:Refresh() end
        end })
    -- Ankuendigung im Gildenchat: der einzige Weg, auf dem ein Addon etwas
    -- nach draussen bringt — und damit auch nach Discord, wenn die Gilde
    -- eine Bruecke am Gildenchat hat.
    self.rowAnnounce = makeRow(loot, { label = L.SET_ANNOUNCE, hint = L.SET_ANNOUNCE_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("announceLoot", on) end })
    makeHeading(loot, L.SET_H_ROTATION)
    self.rowRotation = makeRow(loot, { label = L.ROTATION_ENABLED, hint = L.SET_ROTATION_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("rotationEnabled", on) end })
    self.rowRotationAnnounce = makeRow(loot, { label = L.ROTATION_ANNOUNCE_OPT, hint = "", control = "switch",
        set = function(on) GA.Core.Config:Set("rotationAnnounce", on) end })
    makeHeading(loot, L.SET_H_TRACKING)
    self.rowSolo = makeRow(loot, { label = L.SET_LOOT_SOLO, hint = L.SET_LOOT_SOLO_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("trackOutsideGroup", on) end })
    -- Combat Log: legt etwas AUSSERHALB des Spiels an — aus, bis jemand
    -- es einschaltet. Der Hinweis sagt die Wahrheit ueber diesen Client:
    -- Kann er es nicht, steht das da statt eines Schalters, hinter dem
    -- nichts passiert.
    makeHeading(raid, L.SET_H_COMBATLOG)
    self.rowCombatLog = makeRow(raid, { label = L.SET_COMBATLOG, hint = L.SET_COMBATLOG_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("autoCombatLog", on) end })
    self.rowMeasured = makeRow(loot, { label = L.SET_MEASURED_ROW, hint = "" })

    -- ------------------------------------------------------------ Daten -----
    --
    -- KEIN SCHALTER, SONDERN EINE FESTSTELLUNG. Bis 20.09.2026 stand hier
    -- ein Kaestchen mit dem Versprechen "nichts verlaesst diesen Client,
    -- bis du es einschaltest". Die Gilde hat entschieden, dass
    -- Ausruestungsdaten geteilt werden. Ein Kaestchen, das man nicht mehr
    -- abwaehlen kann, waere eine Luege — also steht hier, was hinausgeht.
    local data = self.pages.data
    makeHeading(data, L.SET_H_SHARE)
    self.rowPublish = makeRow(data, { label = L.SET_PUBLISH, hint = L.SET_PUBLISH_HINT, build = function(row)
        row.chip:SetText(L.SET_PUBLISH_ON)
        row.chip:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
        row.chip:Show()
        return function() return 0 end
    end })
    -- Gildenbank (06.10.2026): teilen, was man am Tresor liest.
    self.rowGbankShare = makeRow(data, { label = L.SET_GBANK_SHARE, hint = L.SET_GBANK_SHARE_HINT, control = "switch",
        set = function(on) GA.Core.Config:Set("guildBankShare", on) end })
    makeHeading(data, L.SET_H_SYNC)
    self.rowSync = makeRow(data, { label = L.SET_SYNC_ROW, hint = "" })
    self.rowStats = makeRow(data, { label = L.SET_CLIENT, hint = "" })
    -- ------------------------------------------------------------ Ueber ---
    -- Kontakt und Hilfe (06.10.2026: "baut eine Kontaktart ein" — ein Spieler
    -- wollte einen Fehler melden und fand keinen Weg).
    local about = self.pages.about
    makeRow(about, { label = L.SET_FEEDBACK, hint = L.SET_FEEDBACK_HINT, build = function(row)
        local button = Widgets.Button(row, L.SET_FEEDBACK_BTN, function()
            Widgets.CopyDialog(L.SET_FEEDBACK, GA.const.FEEDBACK_URL)
        end, "primary")
        button:SetHeight(20)
        button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8)
        return function() return 28 end
    end })
    makeRow(about, { label = L.SET_BOT_REQUEST, hint = L.SET_BOT_REQUEST_HINT, build = function(row)
        local button = Widgets.Button(row, L.SET_FEEDBACK_BTN, function()
            Widgets.CopyDialog(L.SET_BOT_REQUEST, GA.const.FEEDBACK_URL)
        end)
        button:SetHeight(20)
        button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8)
        return function() return 28 end
    end })
    makeRow(about, { label = L.SET_WINDOW_RESET, hint = L.SET_WINDOW_RESET_HINT, build = function(row)
        local button = Widgets.Button(row, L.SET_WINDOW_RESET_BTN, function()
            GA.UI.MainFrame:ResetWindow()
        end)
        button:SetHeight(20)
        button:SetPoint("TOPLEFT", row.hint, "BOTTOMLEFT", 0, -8)
        return function() return 28 end
    end })
    makeRow(about, { label = L.SET_ABOUT_VERSION, hint = string.format(L.SET_ABOUT_VERSION_HINT, tostring(GA.version)) })

    -- Sammlerbetrieb: eine Einstellung fuer genau einen Client, nicht fuer
    -- jeden Spieler — deshalb hier unten.
    makeHeading(data, L.SET_H_ADVANCED)
    self.rowCollector = makeRow(data, { label = L.SET_COLLECTOR, hint = "", control = "switch",
        set = function(on) GA.Core.Config:Set("collectorMode", on) end })
    self.rowDebug = makeRow(data, { label = L.SET_DEBUG_ROW, hint = L.SET_DEBUG_HINT, control = "switch",
        set = function(on)
            local debugOn = GA.Core.Database.char.debug and true or false
            if debugOn ~= on then GA.Core.Debug:Toggle() end
        end })

    -- Trennlinien zwischen den Zeilen, und Seiten, die sich selbst messen.
    for _, page in pairs(self.pages) do
        for _, row in ipairs(page.rows) do
            row.separator = Theme.Fill(row, Theme.color.border)
            row.separator:ClearAllPoints()
            row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.separator:SetHeight(1)
        end
    end

    local last = GA.Core.Config:GetUI("settings").section
    self:ShowSection(self.pages[last] and last or SECTIONS[1].key)
    return frame
end

-- ================================================================== Inhalt ----

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

--- Stellt den Look um. Gebaut ist das Fenster schon im alten — der Hinweis
--- auf /reload erscheint, sobald die Wahl vom laufenden Look abweicht.
function Settings:ChooseLook(choice)
    GA.Core.Config:Set("uiLook", choice)
    self.lookChanged = choice ~= (Theme.look or Theme.DEFAULT_LOOK)
    self:Refresh()
end

function Settings:Refresh()
    local Config = GA.Core.Config

    local look = Theme.LookKey()
    for _, button in ipairs(self.lookButtons or {}) do
        button:SetEnabledState(button.choice ~= look)
    end

    local chosen = GA.Core.Database.account.language or GA.Core.Locale.DEFAULT
    for _, button in ipairs(self.languageButtons) do
        button:SetEnabledState(button.choice ~= chosen)
    end
    local pending = self.languageChanged or self.lookChanged
    self.reloadRow:SetShown(pending and true or false)
    if not pending then
        -- Eine versteckte Zeile nimmt keinen Platz: Hoehe null, kein Hinweis.
        self.reloadRow.hint:SetText("")
    else
        self.reloadRow.hint:SetText(self.languageChanged and L.SET_LANGUAGE_RELOAD or L.SET_LOOK_RELOAD)
    end

    self.scaleValue:SetText(string.format("%.2f", Config:GetUI("main").scale or 1))
    self.rowMinimap.switch:SetChecked(not Config:GetUI("minimap").hidden)
    self.rowTooltips.switch:SetChecked(Config:Get("tooltipItems") and true or false)
    self.rowGuildKey.switch:SetChecked(Config:Get("guildKeyOpensAddon") and true or false)
    for _, row in ipairs(self.sectionRows or {}) do
        row.switch:SetChecked(not GA.UI.MainFrame:IsSectionHidden(row.sectionKey))
    end

    -- ~= false, nicht "and true or false": Die Voreinstellung ist AN, und ein
    -- noch nie gesetzter Wert ist nil. Wer hier auf Wahrheit prueft, zeigt
    -- beim ersten Oeffnen einen leeren Schalter fuer etwas, das laeuft.
    self.rowCamp.switch:SetChecked(Config:Get("campEnabled") ~= false)
    self.rowMap.switch:SetChecked(Config:Get("mapShare") ~= false)
    self.rowMapLabels.switch:SetChecked(Config:Get("mapPinLabels") ~= false)
    self.rowLevelUp.switch:SetChecked(Config:Get("levelUpAnnounce") and true or false)
    self.rowReminders.switch:SetChecked(Config:Get("raidReminders") ~= false)
    self.rowReminderSound.switch:SetChecked(Config:Get("raidReminderSound") ~= false)
    self.rowReady.switch:SetChecked(Config:Get("readyCheck") ~= false)
    self.rowHighlight.switch:SetChecked(Config:Get("objectHighlight") == true)
    self.rowHighlightMarker.switch:SetChecked(Config:Get("highlightMarker") ~= false)
    if self.gatherKeyButton and not self.capturingKey then
        local key = GA.Core.Compat.GetBindingKey(GA.Modules.Highlight.INTERACT_ACTION)
        self.gatherKeyButton:SetLabel(string.format(L.SET_GATHER_KEY_BTN, key or L.SET_GATHER_KEY_NONE))
    end
    self.rowHighlightSound.switch:SetChecked(Config:Get("highlightSound") == true)
    if self.rangeValue then self.rangeValue:SetText(string.format(L.HL_RANGE_VALUE, GA.Modules.Highlight.Range())) end
    self.rowReadyEnchants.switch:SetChecked(Config:Get("readyEnchants") ~= false)
    self.rowReadyConsumables.switch:SetChecked(Config:Get("readyConsumables") ~= false)
    self.rowDiscordBot.switch:SetChecked(Config:Get("discordBot") and true or false)
    local style = Config:Get("mapPinStyle") == "dot" and "dot" or "crest"
    for _, chip in ipairs(self.pinStyleChips) do chip:SetPressed(chip.style == style) end
    self.pinSize:SetQuiet(tonumber(Config:Get("mapPinSize")) or 22)
    local notifyAll = Config:Get("notifyEnabled") ~= false
    self.rowNotifyAll.switch:SetChecked(notifyAll)
    for _, row in ipairs(self.notifyRows) do
        local wert = Config:Get("notify" .. row.notifyKey)
        if wert == nil then wert = row.notifyKey ~= "Achievements" end
        row.switch:SetChecked(wert and true or false)
        row.switch:SetEnabledState(notifyAll, L.SET_NOTIFY_ALL_OFF)
    end

    local threshold = Config:Get("lootThresholdQuality") or 3
    self.rowThreshold.title:SetText(string.format(L.SET_LOOT_THRESHOLD, L["QUALITY_" .. threshold] or tostring(threshold)))
    for _, button in ipairs(self.thresholdButtons) do
        button:SetEnabledState(button.quality ~= threshold)
    end
    self.rowOffer.switch:SetChecked(Config:Get("offerNewFinds") and true or false)
    self.rowAnnounce.switch:SetChecked(Config:Get("announceLoot") and true or false)
    self.rowRotation.switch:SetChecked(Config:Get("rotationEnabled") and true or false)
    self.rowRotationAnnounce.switch:SetChecked(Config:Get("rotationAnnounce") and true or false)
    self.rowSolo.switch:SetChecked(Config:Get("trackOutsideGroup") and true or false)
    local logOn = Config:Get("autoCombatLog") and true or false
    self.rowCombatLog.switch:SetChecked(logOn)
    if logOn and GA.Modules.CombatLog and GA.Modules.CombatLog:Available() == false then
        self.rowCombatLog.hint:SetText(L.COMBATLOG_UNAVAILABLE)
        self.rowCombatLog.hint:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
    else
        self.rowCombatLog.hint:SetText(L.SET_COMBATLOG_HINT)
        self.rowCombatLog.hint:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
    end

    -- Was dieser Client wirklich gesehen hat — nicht, was die API verspricht.
    local seen = {}
    local measured = GA.Core.Database.account.measured
    for method in pairs((measured and measured.lootMethods) or {}) do
        seen[#seen + 1] = L["LOOT_" .. string.upper(method)] or method
    end
    table.sort(seen)
    local seenText = #seen > 0 and table.concat(seen, ", ") or L.SET_MEASURED_NONE
    self.rowMeasured.hint:SetText(string.format(L.SET_MEASURED, seenText)
        .. "\n" .. string.format(L.SET_ITEMINDEX, GA.Modules.ItemIndex:Count()))

    -- Abgleich. Konflikte stehen in Warnfarbe: Zwei Clients derselben Gilde
    -- haben etwas Widersprechendes gemeldet.
    local Sync = GA.Modules.Sync
    local conflicts = Sync.conflicts or 0
    self.rowSync.hint:SetText(string.format(L.SET_SYNC, Sync:PeerCount(), conflicts))
    local syncColor = conflicts > 0 and Theme.color.warn or Theme.color.textDim
    self.rowSync.hint:SetTextColor(syncColor[1], syncColor[2], syncColor[3])

    local stats = GA.Core.Database:Stats()
    local storage = GA.Core.Database.storage or {}
    self.rowStats.hint:SetText(string.format(L.SET_STATS,
        stats.characters, stats.awards, stats.journal, tostring(stats.schemaVersion))
        .. "\n" .. string.format(L.SET_STORAGE, tostring(storage.source)))
    local storageColor = storage.accountLoaded and Theme.color.textDim or Theme.color.warn
    self.rowStats.hint:SetTextColor(storageColor[1], storageColor[2], storageColor[3])

    self.rowGbankShare.switch:SetChecked(Config:Get("guildBankShare") ~= false)
    self.rowCollector.switch:SetChecked(Config:Get("collectorMode") and true or false)
    self.rowCollector.hint:SetText(string.format(L.SET_COLLECTOR_HINT, tonumber(Config:Get("collectorMinutes")) or 60))
    self.rowDebug.switch:SetChecked(GA.Core.Database.char.debug and true or false)

    -- Die Leiste: drei Messwerte, die man sonst suchen muesste.
    local logState = L.SET_OFF
    if GA.Modules.CombatLog and GA.Modules.CombatLog:Available() == false then logState = L.SET_NAV_NOLOG
    elseif logOn then logState = L.SET_ON end
    self.facts:SetText(string.format(L.SET_NAV_FACTS_LINE, logState, #seen, Sync:PeerCount()))

    -- ERST NACH DEM SETZEN ALLER TEXTE NEU MESSEN: Mehrere Hinweise aendern
    -- sich hier oben, und wer vorher misst, misst den alten Text.
    for _, page in pairs(self.pages) do Settings.LayoutPage(page) end

    -- ShowView schreibt nach diesem Refresh den Titel samt view.context:
    -- Die Version muss dort stehen, sonst steht sie nur nach einer
    -- Aenderung (gesehen 01.10.2026).
    self.context = "v" .. GA.version
    GA.UI.MainFrame:SetContext(self.context)
end

GA.UI.MainFrame:RegisterView("settings", Settings)
