--[[----------------------------------------------------------------------------
    MainFrame — Huelle: Fensterrahmen, Reiter unten, Werkzeugzeile, Ansichten.

    Seit 19.09.2026 auf Blizzards PortraitFrameTemplate: Metallrahmen mit
    Portraitkreis oben links, Titelleiste, X-Knopf — derselbe Rahmen wie Karte,
    Questlog und Charakterfenster in Forever. Die Ansichten haengen als Reiter
    am unteren Rand (wie "Charakter | Ruf | Waehrung"). Fehlt die Vorlage,
    faellt alles auf den Backdrop-Rahmen mit eigener Kopfzeile zurueck; die
    Ansichten merken davon nichts.

    Ansichtsvertrag:
        view.Create(parent) -> Frame     einmalig
        view.OnShow()                    optional
        view.Refresh()                   optional, nur wenn sichtbar
------------------------------------------------------------------------------]]

local _, GA = ...

local MainFrame = {}
GA.UI.MainFrame = MainFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Config = GA.Core.Config
local L = GA.L

local FRAME_NAME = "GuildArmoryMainFrame"
-- Der Portraitkreis der Vorlage ragt oben links etwa 60px in den Rahmen; die
-- Werkzeugzeile liegt auf seiner Hoehe und beginnt deshalb rechts davon.
local TOOLBAR_HEIGHT = 32
local PORTRAIT_CLEARANCE = 56

--- Hoehe der Unterreiterzeile. 0, solange ein Bereich nur eine Ansicht hat.
local SUBBAR_HEIGHT = 22

--- ZWEI EBENEN STATT ELF REITER.
---
--- Bis 24.09.2026 hingen alle Ansichten als gleichrangige Reiter am unteren
--- Rand. Mit der elften war die Fensterbreite erreicht, und vor allem: Die
--- Reihe log. Sie stellte Dinge nebeneinander, die nicht nebeneinander
--- gehoeren.
---
---   * ZWEI WAREN EINSTELLUNGEN. Lootregeln und Einstellungen verstellt man
---     einmal im Quartal und suchte sie trotzdem jedes Mal in derselben
---     Reihe wie die laufende Sitzung.
---   * ZWEI STELLTEN DIESELBE FRAGE. Armory ("was traegt der") und
---     Charaktere ("wer ist das, welche Twinks, welche Rolle") fangen beide
---     damit an, dass man eine Person auswaehlt.
---   * VIER GEHOEREN ZUSAMMEN. Sitzung, Historie, Wunschliste und Regeln
---     sind ein Raidabend.
---
--- Unten stehen jetzt die BEREICHE, oben im Inhalt die Ansichten darin — wie
--- im Berufsfenster des Spiels. Wer ein Ziel sucht, liest fuenf Zeilen statt
--- elf.
---
--- WAS ES KOSTET, und das ist keine Kleinigkeit: ein Klick mehr zur Historie
--- und zur Wunschliste. Dafuer bleiben alle Slash-Kurzwege, wie sie waren —
--- `/ga history` springt weiterhin direkt dorthin, samt Bereichswechsel.
---
--- `settings` steht in KEINEM Bereich. Es haengt am Zahnrad in der
--- Werkzeugzeile, weil es keine Arbeitsansicht ist.
local SECTIONS = {
    { key = "overview", label = "NAV_OVERVIEW", views = {
        { key = "dashboard", label = "NAV_DASHBOARD" },
    } },

    { key = "guild", label = "NAV_GUILD", views = {
        { key = "armory",       label = "NAV_EQUIPMENT" },
        { key = "characters",   label = "NAV_CHARACTERS" },
        { key = "achievements", label = "NAV_ACHIEVEMENTS" },
    } },

    { key = "loot", label = "NAV_LOOT", views = {
        { key = "lootcouncil", label = "NAV_SESSION" },
        { key = "loothistory", label = "NAV_LOOTHISTORY" },
        { key = "wishlist",    label = "NAV_WISHLIST" },
        { key = "lootrules",   label = "NAV_RULES" },
    } },

    { key = "professions", label = "NAV_PROFESSIONS", views = {
        { key = "crafting", label = "NAV_CRAFTING" },
    } },

    { key = "analytics", label = "NAV_ANALYTICS", views = {
        { key = "analytics", label = "NAV_ANALYTICS" },
    } },
}

--- [Ansichtsschluessel] = Bereichsindex. Aus SECTIONS gerechnet, nicht
--- daneben gepflegt: Eine zweite Liste waere genau bis zur naechsten
--- Ansicht richtig.
local SECTION_OF = {}
--- [Ansichtsschluessel] = Beschriftung des Unterreiters.
local LABEL_OF = {}
for index, section in ipairs(SECTIONS) do
    for _, view in ipairs(section.views) do
        SECTION_OF[view.key] = index
        LABEL_OF[view.key] = view.label
    end
end

local PLACEHOLDER = {
    gear        = "TODO_GEAR",
}

MainFrame.views = {}
MainFrame.tabs = {}
MainFrame.subTabs = {}
MainFrame.current = nil

--- Wo man in einem Bereich zuletzt war. Nur im Arbeitsspeicher: Nach einem
--- /reload beim ersten Unterreiter anzufangen ist kein Verlust, und eine
--- weitere Zeile in den SavedVariables dafuer waere es nicht wert.
MainFrame.lastInSection = {}

function MainFrame:RegisterView(key, view)
    self.views[key] = view
end

-- ================================================================== Aufbau ----

function MainFrame:Create()
    if self.frame then return self.frame end

    local saved = Config:GetUI("main")

    -- Rahmen: Blizzards Portraitfenster, sonst Backdrop.
    local frame = Theme.CreateNative("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
    self.native = frame ~= nil
    if not frame then
        frame = Theme.CreateBackdropFrame(FRAME_NAME, UIParent)
        if not Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid) then
            Theme.DoubleFrame(frame)
        end
    end
    self.frame = frame

    frame:SetWidth(saved.width)
    frame:SetHeight(saved.height)
    frame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
    frame:SetScale(saved.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:Hide()

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        MainFrame:SavePosition()
    end)

    frame:SetResizable(true)
    if not pcall(frame.SetResizeBounds, frame, 860, 540) then
        pcall(frame.SetMinResize, frame, 860, 540)
    end

    local insets
    if self.native then
        self:BuildNativeChrome()
        insets = Theme.PanelInsets()
    else
        self:BuildFallbackHeader()
        insets = { left = 12, right = -12, top = -(Theme.size.headerHeight + 12), bottom = 12 }
    end

    -- Inhalt: Werkzeugzeile oben, darunter die Ansicht.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", insets.left + 4, insets.top - 4)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", insets.right - 4, insets.bottom + 4)
    if not self.native then
        Theme.TexturedFill(content, "Interface\\FrameGeneral\\UI-Background-Rock",
            { 0.42, 0.50, 0.46, 1 })
    end
    self.content = content

    self:BuildToolbar()

    -- Zeile fuer die Unterreiter. Liegt zwischen Werkzeugzeile und Inhalt und
    -- bleibt leer, solange ein Bereich nur eine Ansicht hat.
    local subBar = CreateFrame("Frame", nil, content)
    subBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -TOOLBAR_HEIGHT)
    subBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -TOOLBAR_HEIGHT)
    subBar:SetHeight(SUBBAR_HEIGHT)
    subBar:Hide()
    self.subBar = subBar

    local body = CreateFrame("Frame", nil, content)
    self.body = body
    self.bodyBottom = 0
    self:LayoutBody(false)

    self:BuildTabs()
    self:BuildSubTabs()
    self:BuildResizeGrip()

    if type(_G.UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, FRAME_NAME)
    end

    frame:SetScript("OnSizeChanged", function()
        local view = MainFrame.current and MainFrame.views[MainFrame.current]
        if view and view.Refresh and MainFrame:IsVisible() then view:Refresh() end
    end)
    frame:SetScript("OnShow", function() MainFrame:UpdatePortrait() end)

    self:HookEvents()
    return frame
end

--- Titel, Portrait und X-Knopf der Blizzard-Vorlage.
function MainFrame:BuildNativeChrome()
    local frame = self.frame

    if frame.SetTitle then
        pcall(frame.SetTitle, frame, "Guild Armory")
    else
        local title = Theme.NativeText(frame)
        if title then title:SetText("Guild Armory") end
    end

    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() MainFrame:Hide() end)
    end

    self:UpdatePortrait()
end

--- Portrait des eigenen Charakters im Kreis oben links. Beim Login ist das
--- Modell manchmal noch nicht geladen — deshalb bei jedem Anzeigen erneut.
function MainFrame:UpdatePortrait()
    local frame = self.frame
    if not frame or not self.native then return end

    if frame.SetPortraitToUnit then
        if pcall(frame.SetPortraitToUnit, frame, "player") then return end
    end
    local texture = (frame.PortraitContainer and frame.PortraitContainer.portrait)
        or frame.portrait or frame.Portrait
    if texture then Theme.SetPortrait(texture, "player") end
end

--- Rueckfall ohne Vorlage: eigene Kopfzeile mit Titel und X.
function MainFrame:BuildFallbackHeader()
    local fonts = Theme.Fonts()
    local frame = self.frame

    local inset = 12
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    header:SetHeight(Theme.size.headerHeight)
    Theme.Fill(header, Theme.color.panelBg)
    Theme.Edge(header, "BOTTOM", Theme.color.border)

    local brand = Theme.Label(header, "Guild Armory", fonts.big, Theme.color.gold)
    brand:SetPoint("LEFT", header, "LEFT", 14, 0)
    local tagline = Theme.Label(header, "Forever Edition", fonts.small, Theme.color.textFaint)
    tagline:SetPoint("LEFT", brand, "RIGHT", 8, -1)

    local close = Widgets.Button(header, "X", function() MainFrame:Hide() end)
    close:SetWidth(22)
    close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
end

--- Werkzeugzeile: Ansichtstitel, Kontext, Aktualisieren.
function MainFrame:BuildToolbar()
    local fonts = Theme.Fonts()
    local content = self.content

    local bar = CreateFrame("Frame", nil, content)
    bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    bar:SetHeight(TOOLBAR_HEIGHT)

    self.titleLabel = Theme.Label(bar, "", fonts.big, Theme.color.heading)
    self.titleLabel:SetPoint("LEFT", bar, "LEFT", self.native and PORTRAIT_CLEARANCE or 4, 2)
    if self.titleLabel.SetShadowOffset then self.titleLabel:SetShadowOffset(1, -1) end

    self.contextLabel = Theme.Label(bar, "", fonts.body, Theme.color.textDim)
    self.contextLabel:SetPoint("LEFT", self.titleLabel, "RIGHT", 12, -1)

    local refresh = Widgets.Button(bar, L.BTN_REFRESH, function()
        GA.Modules.Equipment:Capture("manuell")
        GA.Core.Compat.RequestGuildRoster()
    end, "primary")
    refresh:SetPoint("RIGHT", bar, "RIGHT", -2, 2)
    self.refreshButton = refresh

    self.settingsButton = self:BuildSettingsButton(bar)
    self.settingsButton:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
end

--- Das Zahnrad. Einstellungen sind keine Arbeitsansicht — sie standen nur
--- deshalb in der Reiterreihe, weil es dort Platz gab.
---
--- ZUERST DAS SYMBOL, DANN DAS WORT. Ein Zahnrad ist ohne Uebersetzung
--- verstaendlich und kostet 22 Pixel statt der Breite von
--- "Einstellungen"/"Settings". Laedt die Textur nicht, steht das Wort da —
--- ein leerer Knopf waere schlimmer als ein breiter.
function MainFrame:BuildSettingsButton(bar)
    local PATH = "Interface\\Buttons\\UI-OptionsButton"

    if Theme.TextureExists(PATH) then
        local button = CreateFrame("Button", nil, bar)
        button:SetWidth(22) button:SetHeight(22)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexture(PATH)
        icon:SetVertexColor(Theme.color.goldMid[1], Theme.color.goldMid[2],
            Theme.color.goldMid[3])

        button:SetScript("OnEnter", function(self)
            icon:SetVertexColor(Theme.color.goldBright[1], Theme.color.goldBright[2],
                Theme.color.goldBright[3])
            if _G.GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L.NAV_SETTINGS, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            icon:SetVertexColor(Theme.color.goldMid[1], Theme.color.goldMid[2],
                Theme.color.goldMid[3])
            if _G.GameTooltip then GameTooltip:Hide() end
        end)
        button:SetScript("OnClick", function() MainFrame:ShowView("settings") end)
        return button
    end

    return Widgets.Button(bar, L.NAV_SETTINGS, function()
        MainFrame:ShowView("settings")
    end)
end

--- Setzt den Inhaltsbereich unter Werkzeugzeile und (falls sichtbar)
--- Unterreiterzeile.
---
--- ClearAllPoints ZUERST. SetPoint fuegt einen Anker HINZU, es ersetzt
--- keinen — wer das vergisst, sammelt bei jedem Ansichtswechsel einen
--- weiteren an, und irgendwann widersprechen sie sich. Genau daran ist die
--- Loot-Historie einmal gescheitert.
function MainFrame:LayoutBody(withSubBar)
    if not self.body then return end
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0,
        -(TOOLBAR_HEIGHT + (withSubBar and SUBBAR_HEIGHT or 0)))
    self.body:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", 0, self.bodyBottom or 0)
end

--- Reiter am unteren Rand — ein BEREICH je Reiter.
function MainFrame:BuildTabs()
    local frame = self.frame
    local previous

    for index, entry in ipairs(SECTIONS) do
        local tab = Widgets.Tab(frame, index, L[entry.label], function()
            MainFrame:ShowSection(index)
        end)
        tab.sectionKey = entry.key

        if tab.native then
            -- Wie CharacterFrame.xml: erster Reiter unter der linken Ecke,
            -- die weiteren daneben. Die alte Vorlage ueberlappt, die neue nicht.
            local gap = Theme.native.PanelTabButtonTemplate and 3 or -15
            if previous then
                tab:SetPoint("LEFT", previous, "RIGHT", gap, 0)
            else
                tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
            end
        else
            -- Gezeichnete Reiter liegen innen am unteren Rand.
            if previous then
                tab:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else
                tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
                -- Der Inhalt endet oberhalb der gezeichneten Reiter. Gemerkt
                -- statt gesetzt: LayoutBody setzt beide Anker gemeinsam neu,
                -- sooft die Unterreiterzeile kommt oder geht.
                self.bodyBottom = 30
                self:LayoutBody(false)
            end
        end

        self.tabs[index] = tab
        previous = tab
    end
end

--- Unterreiter je Bereich. ALLE EINMAL GEBAUT, danach nur ein- und
--- ausgeblendet.
---
--- Bei jedem Ansichtswechsel neue Frames zu erzeugen waere dieselbe Falle wie
--- in ScrollList: WoW gibt Frames nie wieder frei, und ein Abend mit viel
--- Hin und Her legt hunderte an, die nie wieder jemand anfasst.
function MainFrame:BuildSubTabs()
    for index, section in ipairs(SECTIONS) do
        self.subTabs[index] = {}

        -- EIN EINZELNER UNTERREITER IST KEINER. Wo ein Bereich nur eine
        -- Ansicht hat, bleibt die Zeile weg und der Inhalt rueckt hoch —
        -- ein Reiter, der nichts zur Wahl stellt, kostet nur Platz.
        if #section.views > 1 then
            local previous
            for _, view in ipairs(section.views) do
                local chip = Widgets.Chip(self.subBar, L[view.label])
                chip.viewKey = view.key
                -- Chip schaltet sich von Haus aus selbst um. Hier ist die
                -- Wahl aber eine unter mehreren, keine an/aus — deshalb
                -- entscheidet ShowView, wer gedrueckt aussieht.
                chip:SetScript("OnClick", function(self)
                    MainFrame:ShowView(self.viewKey)
                end)
                if previous then
                    chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
                else
                    chip:SetPoint("LEFT", self.subBar, "LEFT",
                        self.native and PORTRAIT_CLEARANCE or 4, 0)
                end
                chip:Hide()
                self.subTabs[index][#self.subTabs[index] + 1] = chip
                previous = chip
            end
        end
    end
end

--- Zeigt die Unterreiterzeile des Bereichs und hebt die laufende Ansicht hervor.
function MainFrame:UpdateSubTabs(sectionIndex, viewKey)
    local any = false
    for index, chips in pairs(self.subTabs) do
        for _, chip in ipairs(chips) do
            if index == sectionIndex then
                chip:SetPressed(chip.viewKey == viewKey)
                chip:Show()
                any = true
            else
                chip:Hide()
            end
        end
    end

    if any then self.subBar:Show() else self.subBar:Hide() end
    self:LayoutBody(any)
end

--- Oeffnet einen Bereich — dort, wo man zuletzt war.
function MainFrame:ShowSection(index)
    local section = SECTIONS[index]
    if not section then return end
    self:ShowView(self.lastInSection[section.key] or section.views[1].key)
end

function MainFrame:BuildResizeGrip()
    local frame = self.frame
    local grip = CreateFrame("Button", nil, frame)
    grip:SetWidth(16) grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    for index = 1, 3 do
        local line = grip:CreateTexture(nil, "OVERLAY")
        Theme.Paint(line, Theme.color.goldDim)
        line:SetWidth(12 - index * 3) line:SetHeight(1)
        line:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, index * 3)
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        MainFrame:SavePosition()
    end)
end

-- ================================================================== Ansichten -

--- Zeigt eine Ansicht — und zwar ueber JEDEN Blattschluessel.
---
--- Die Slash-Kurzwege nennen weiterhin Ansichten, keine Bereiche: `/ga
--- history` muss den Loot-Bereich waehlen UND die Historie darin. Wer hier
--- nur Bereiche annaehme, haette mit dem Umbau die halbe Bedienung
--- weggeraeumt.
function MainFrame:ShowView(key)
    local view = self.views[key]
    local sectionIndex = SECTION_OF[key]

    -- 0 statt nil: Es waehlt nachweislich KEINEN Reiter aus. nil laesst bei
    -- Blizzards Reitern den alten stehen, und dann leuchtet "Loot", waehrend
    -- die Einstellungen offen sind.
    Widgets.SelectTab(self.frame, self.tabs, sectionIndex or 0)

    if sectionIndex then
        self.lastInSection[SECTIONS[sectionIndex].key] = key
    end
    self:UpdateSubTabs(sectionIndex, key)

    if self.current and self.views[self.current] and self.views[self.current].frame then
        self.views[self.current].frame:Hide()
    end
    if self.placeholder then self.placeholder:Hide() end

    self.current = key
    Config:GetUI("main").lastView = key

    if not view then
        local label = L[LABEL_OF[key] or ("NAV_" .. string.upper(key))] or key
        local phase = ""
        self.placeholder = Widgets.Placeholder(self.body, phase, label, L[PLACEHOLDER[key] or "TODO_TITLE"])
        self.placeholder:Show()
        self:SetTitle(label, nil)
        return
    end

    if not view.frame then view.frame = view:Create(self.body) end
    view.frame:Show()
    if view.OnShow then view:OnShow() end
    if view.Refresh then view:Refresh() end
    -- Der SCHLUESSEL wird erst hier aufgeloest, nicht beim Laden der Ansicht:
    -- Eine beim Laden kopierte Beschriftung wuesste von der gewaehlten Sprache
    -- nichts (siehe Localization/Locale.lua).
    self:SetTitle(view.titleKey and L[view.titleKey] or view.title or key, view.context)
end

function MainFrame:SetTitle(title, context)
    self.titleLabel:SetText(title or "")
    self.contextLabel:SetText(context or "")
end

function MainFrame:SetContext(text)
    if self.contextLabel then self.contextLabel:SetText(text or "") end
end

-- ================================================================== Sichtbarkeit

function MainFrame:IsVisible() return self.frame and self.frame:IsShown() end

function MainFrame:Show()
    self:Create()
    self.frame:Show()
    self:ShowView(self.current or Config:GetUI("main").lastView or "dashboard")
end

function MainFrame:Hide()
    if self.frame then self:SavePosition() self.frame:Hide() end
end

function MainFrame:Toggle()
    if self:IsVisible() then self:Hide() else self:Show() end
end

function MainFrame:SavePosition()
    if not self.frame then return end
    local saved = Config:GetUI("main")
    local point, _, _, x, y = self.frame:GetPoint()
    saved.point = point or "CENTER"
    saved.x = math.floor((x or 0) + 0.5)
    saved.y = math.floor((y or 0) + 0.5)
    saved.width = math.floor(self.frame:GetWidth() + 0.5)
    saved.height = math.floor(self.frame:GetHeight() + 0.5)
end

function MainFrame:SetScale(scale)
    scale = math.max(0.6, math.min(1.4, tonumber(scale) or 1))
    Config:GetUI("main").scale = scale
    if self.frame then self.frame:SetScale(scale) end
    return scale
end

-- ================================================================== Ereignisse -

function MainFrame:HookEvents()
    local Callbacks = GA.Core.Callbacks
    local function refreshCurrent()
        if not MainFrame:IsVisible() then return end
        local view = MainFrame.views[MainFrame.current]
        if view and view.Refresh then view:Refresh() end
    end
    -- TARGET_CHANGED steht bewusst NICHT in dieser Liste: Zielwechsel kommen im
    -- Raid im Sekundentakt, und ein kompletter Neuaufbau aller Listen dafuer
    -- waere Verschwendung. Die Armory haengt sich selbst daran und aktualisiert
    -- nur ihren Inspect-Knopf.
    for _, event in ipairs({ "EQUIPMENT_UPDATED", "GUILD_UPDATED", "CONFIG_CHANGED",
                             "DATABASE_RESET", "ROLES_CHANGED", "COMPAT_MEASURED",
                             "PLAYERS_CHANGED", "INSPECT_DONE", "INSPECT_FAILED",
                             "AWARD_CREATED", "AWARD_CHANGED", "SESSION_CHANGED",
                             "WISHLIST_CHANGED" }) do
        Callbacks:On(event, refreshCurrent, "MainFrame")
    end
end
