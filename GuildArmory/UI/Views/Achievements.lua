--[[----------------------------------------------------------------------------
    UI/Views/Achievements — der Trophaeensaal: Erfolge, Hall of Fame, Rangliste.

    Drei Blicke auf dieselben Daten, weil drei verschiedene Fragen gestellt
    werden:

      Erfolge       "Was habe ich, was fehlt mir noch?"
      Hall of Fame  "Wer war der Erste?"
      Rangliste     "Wo stehe ich in der Gilde?"

    ===========================================================================
    WAS DIESE ANSICHT ANDERS MACHT ALS EIN ERFOLGSFENSTER IM SPIEL
    ===========================================================================

    Sie zeigt nicht nur einen Haken, sondern WORAUF er beruht.

    Ein gemessener Erfolg und ein von Hand eingetragener sehen in einer Liste
    identisch aus, sobald man nur ein Symbol malt. In einer Gilde, in der
    Punkte in einer Rangliste landen, ist dieser Unterschied nicht
    nebensaechlich — er entscheidet, ob die Liste etwas wert ist.

    Und sie unterscheidet "noch nicht geschafft" von "wird noch gar nicht
    gemessen". Ein Fortschrittsbalken bei null, der sich nie bewegt, sieht wie
    ein kaputtes Addon aus. Steht dort "noch nicht messbar", weiss man woran
    man ist.

    ===========================================================================
    ENTWURF A1 — KARTEN STATT ZEILEN (27.09.2026)
    ===========================================================================

    Jeder Erfolg ist eine KARTE mit Seltenheitsrahmen: grau bis gold, wie
    Itemqualitaet, damit niemand zwei Farbsysteme lernen muss. Erreichte
    Karten haben Farbe, offene sind gedaempft, nicht messbare noch mehr. Auf
    jeder Karte: Symbol, Name, Kategorie und Punkte, die Beschreibung, der
    Balken mit "20 / 30" — und ein NACHWEISCHIP: gemessen, beobachtet,
    eingetragen, oder "noch nicht messbar". Das ist der Chip, der dieses
    Fenster von einem Blizzard-Fenster unterscheidet.

    Oben die Kategorien als Chips mit ihrem Stand: einer gedrueckt zeigt nur
    diese Kategorie, offen. "Alle" zeigt die dreizehn Gruppen mit Kopfzeile,
    ZUGEKLAPPT ALS GRUNDEINSTELLUNG — 272 Karten liest niemand, dreizehn
    Staende schon. Aufgeklappt wird, was gerade interessiert; das bleibt
    gespeichert (achievementsExpanded).

    DER KATEGORIESTAND WIRD IMMER UEBER ALLE ERFOLGE GERECHNET, nie ueber die
    gerade sichtbaren. Sonst stuende beim Suchen nach "Drache" ploetzlich
    "1 von 1 Erfolgen" da, und die Zahl waere eine Aussage ueber das Suchfeld
    statt ueber die Gilde. Beim Suchen sind deshalb auch alle Gruppen offen:
    Wer sucht, will finden, nicht erst aufklappen.

    Die Hall of Fame steht als Spalte rechts neben den eigenen Erfolgen (die
    letzten Gildenersten) und als eigener Blick mit allen — dort ebenfalls als
    Karten. Die Rangliste bleibt eine Tabelle: Eine Rangliste aus Karten ist
    keine Rangliste mehr. Sie hat eine Spalte HAND: die Punkte, die jemand
    eingetragen hat, stehen in der Summe — und sie stehen auch daneben.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local L = GA.L

View.titleKey = "ACH_TITLE"

--- Die drei Blicke.
local MODES = { "OWN", "HALL", "BOARD" }

--- Farbe je Seltenheit. Dieselbe Ordnung wie Itemqualitaet, damit niemand
--- zwei Farbsysteme lernen muss.
local RARITY_COLOR = {
    COMMON    = { 0.62, 0.62, 0.62 },
    UNCOMMON  = { 0.12, 1.00, 0.00 },
    RARE      = { 0.00, 0.44, 0.87 },
    EPIC      = { 0.64, 0.21, 0.93 },
    LEGENDARY = { 1.00, 0.50, 0.00 },
    MYTHIC    = { 0.90, 0.20, 0.30 },
}

--- Die ersten drei Plaetze der Rangliste. Bewusst nur drei: Ab Platz vier ist
--- eine Farbe keine Auszeichnung mehr, sondern Rauschen.
local RANK_COLOR = {
    [1] = { 1.00, 0.84, 0.30 },
    [2] = { 0.78, 0.80, 0.84 },
    [3] = { 0.80, 0.52, 0.30 },
}

--- Farbe je Nachweis: gemessen jade, beobachtet blau, eingetragen bernstein.
local EVIDENCE_COLOR = {
    measured = "jade",
    observed = "info",
    granted  = "warn",
}

--- Welches Symbol zu welchem Erfolg gehoert, steht in UI/AchievementIcons —
--- das ist eine eigene Frage mit eigener Begruendung und gehoert nicht in
--- eine Ansicht.
local Symbols = GA.UI.AchievementIcons

local CARD_MIN_W, CARD_H, CARD_GAP = 196, 112, 8
local HEADER_H = 30
local SIDE_W = 230
local ICON_SIZE = 28

--- Welche Kategorien sind AUFGEKLAPPT.
---
--- Liegt in der Datenbank, damit die Einstellung einen Reload ueberlebt — es
--- ist eine Ansichtssache, kein Messwert, und sie wird deshalb auch nicht ins
--- Journal geschrieben.
---
--- Gespeichert wird das Offene, nicht das Geschlossene — und darin steckt die
--- Grundeinstellung: Eine leere Tabelle heisst "alles zu".
local function expanded()
    local account = GA.Core.Database.account
    account.achievementsExpanded = account.achievementsExpanded or {}
    return account.achievementsExpanded
end

local function categoryName(category)
    if not category then return nil end
    return L["ACH_CAT_" .. category] or category
end

local function singleLine(label)
    if label.SetWordWrap then pcall(label.SetWordWrap, label, false) end
    if label.SetMaxLines then pcall(label.SetMaxLines, label, 1) end
    return label
end

local function paintLines(lines, color)
    for _, line in ipairs(lines) do Theme.Paint(line, color) end
end

local function setColor(label, color)
    label:SetTextColor(color[1], color[2], color[3])
end

--- Eine Kennzahlkachel: Zahl gross, Beschriftung klein, Einordnung darunter.
--- Jede Zeile hat ein linkes Ende — ein rechts verankerter Text ohne Breite
--- waechst nach links ueber die Kachel hinaus (Dashboard, 27.09.2026).
local KPI_W, KPI_H = 104, 58
local function kpi(parent)
    local fonts = Theme.Fonts()
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetWidth(KPI_W) tile:SetHeight(KPI_H)
    Theme.Fill(tile, { 0.031, 0.047, 0.043, 0.85 })
    Theme.Outline(tile, Theme.color.border)

    tile.value = Theme.Label(tile, "—", fonts.hero, Theme.color.goldBright)
    tile.value:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -6)
    singleLine(tile.value)

    tile.label = Theme.Label(tile, "", fonts.small, Theme.color.textDim)
    tile.label:SetPoint("TOPRIGHT", tile.value, "BOTTOMRIGHT", 0, -2)
    tile.label:SetWidth(KPI_W - 16)
    tile.label:SetJustifyH("RIGHT")
    singleLine(tile.label)

    tile.trend = Theme.Label(tile, "", fonts.small, Theme.color.textFaint)
    tile.trend:SetPoint("TOPRIGHT", tile.label, "BOTTOMRIGHT", 0, -1)
    tile.trend:SetWidth(KPI_W - 16)
    tile.trend:SetJustifyH("RIGHT")
    singleLine(tile.trend)

    function tile:Set(value, label, trend, valueColor, trendColor)
        self.value:SetText(value ~= nil and tostring(value) or "—")
        local farbe = valueColor or Theme.color.goldBright
        self.value:SetTextColor(farbe[1], farbe[2], farbe[3])
        self.label:SetText(string.upper(label or ""))
        self.trend:SetText(trend or "")
        local tf = trendColor or Theme.color.textFaint
        self.trend:SetTextColor(tf[1], tf[2], tf[3])
    end
    return tile
end

-- ================================================================== Aufbau ---

function View:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Kopf ------------
    local head = Widgets.Inset(frame)
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    head:SetHeight(KPI_H + 16)
    self.head = head

    self.tilePoints = kpi(head)
    self.tilePoints:SetPoint("LEFT", head, "LEFT", 10, 0)
    self.tileDone = kpi(head)
    self.tileDone:SetPoint("LEFT", self.tilePoints, "RIGHT", 6, 0)
    self.tileFirsts = kpi(head)
    self.tileFirsts:SetPoint("LEFT", self.tileDone, "RIGHT", 6, 0)

    -- Seit wann gezaehlt wird: die Zahlen sind eine Aussage ueber die Gilde
    -- seit diesem Tag, nicht ueber das Addon.
    self.since = Theme.Label(head, "", fonts.small, Theme.color.textFaint)
    self.since:SetPoint("BOTTOMLEFT", self.tileFirsts, "BOTTOMRIGHT", 12, 4)
    singleLine(self.since)

    -- Rechts: die drei Blicke als Gruppe, davor das Suchfeld.
    self.mode = "OWN"
    self.modeButtons = {}
    local previous
    for index = #MODES, 1, -1 do
        local mode = MODES[index]
        local button = Widgets.Button(head, L["ACH_MODE_" .. mode], function()
            self.mode = mode
            -- Die Auswahl gilt fuer die Liste, die sie getroffen hat: Eine
            -- Erfolgskennung aus "Meine Erfolge" bedeutet in der Rangliste
            -- nichts.
            self.selected = nil
            self:Refresh()
        end)
        button:SetHeight(22)
        button:SetWidth(104)
        if previous then button:SetPoint("RIGHT", previous, "LEFT", -3, 0)
        else button:SetPoint("TOPRIGHT", head, "TOPRIGHT", -10, -8) end
        button.mode = mode
        self.modeButtons[#self.modeButtons + 1] = button
        previous = button
    end

    self.search = Widgets.SearchBox(head, L.ACH_SEARCH, function() self:Refresh() end)
    self.search:SetPoint("RIGHT", previous, "LEFT", -10, 0)
    self.search:SetWidth(180)

    -- Eintragen und Zuruecknehmen. Nur fuer Administratoren sichtbar: Ein
    -- Knopf, der bei jedem dasteht und bei fast jedem "darfst du nicht" sagt,
    -- ist kein Hinweis, sondern eine Sackgasse.
    self.grantButton = Widgets.Button(head, L.GRANT_BUTTON, function()
        self:GrantSelected()
    end)
    self.grantButton:SetTooltip(L.TT_GRANT)
    self.grantButton:SetHeight(20)
    self.grantButton:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -10, 8)
    self.grantButton:Hide()

    self.revokeButton = Widgets.Button(head, L.GRANT_REVOKE, function()
        self:RevokeSelected()
    end)
    self.revokeButton:SetHeight(20)
    self.revokeButton:SetPoint("RIGHT", self.grantButton, "LEFT", -4, 0)
    self.revokeButton:SetConfirm(L.BTN_REALLY)
    self.revokeButton:Hide()

    -- Dreizehn Kopfzeilen einzeln anzuklicken ist keine Bedienung.
    self.toggleAll = Widgets.Button(head, L.ACH_COLLAPSE_ALL, function()
        self:ToggleAll()
    end)
    self.toggleAll:SetHeight(20)
    self.toggleAll:SetWidth(110)
    self.toggleAll:SetPoint("RIGHT", self.revokeButton, "LEFT", -4, 0)

    -- ------------------------------------------------------ Kategorien ------
    local chips = CreateFrame("Frame", nil, frame)
    chips:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    chips:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -6)
    chips:SetHeight(20)
    self.chipBar = chips
    -- Die Chips brechen um, sobald die Breite feststeht — und wieder, wenn
    -- sie sich aendert.
    chips:SetScript("OnSizeChanged", function() self:LayoutChips() end)

    self.category = nil
    self.categoryChips = {}
    local order = (GA.Data.Catalog and GA.Data.Catalog.CATEGORIES) or {}
    local keys = { "ALL" }
    for _, category in ipairs(order) do keys[#keys + 1] = category end
    local vorige
    for _, key in ipairs(keys) do
        local chip = Widgets.Chip(chips, key == "ALL" and L.ACH_FILTER_ALL or (categoryName(key) or key),
            function(pressed)
                self.category = (pressed and key ~= "ALL") and key or nil
                self:Refresh()
            end)
        chip.categoryKey = key
        self.categoryChips[#self.categoryChips + 1] = chip
        vorige = chip
    end

    -- ------------------------------------------------------ Karten ----------
    local panel = Widgets.Panel(frame, L.ACH_TITLE)
    panel:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -6)
    panel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    panel:SetPoint("RIGHT", frame, "RIGHT", -(pad + SIDE_W + gap), 0)
    self.panel = panel

    self.scroll = Widgets.ScrollArea(panel.content)
    self.scroll:SetAllPoints(panel.content)
    self.scroll:SetScript("OnSizeChanged", function(scroll)
        self:LayoutCards()
        scroll:Refresh()
    end)
    self.cards, self.headers = {}, {}

    self.empty = Theme.Label(panel.content, L.ACH_EMPTY, fonts.row, Theme.color.textFaint)
    self.empty:SetPoint("CENTER", panel.content, "CENTER", 0, 0)
    self.empty:Hide()

    -- Die Rangliste: eine Tabelle im selben Panel, nur im dritten Blick.
    self.board = Widgets.ScrollList(panel.content, {
        rowHeight = Theme.size.rowHeight + 4,
        columns = {
            { key = "rank", label = L.ACH_COL_RANK, width = 22 },
            { key = "name", label = L.ACH_COL_PLAYER, width = 150 },
            { key = "points", label = L.ACH_COL_POINTS, width = 90, justify = "RIGHT" },
            { key = "count", label = L.ACH_COL_COUNT, width = 40, justify = "RIGHT" },
            { key = "firsts", label = L.ACH_COL_FIRSTS, width = 44, justify = "RIGHT" },
            { key = "hand", label = L.ACH_COL_HAND, width = 44, justify = "RIGHT" },
        },
        createRow = function(row) self:BuildBoardRow(row) end,
        updateRow = function(row, entry) self:UpdateBoardRow(row, entry) end,
        onEnterRow = function(row, entry) self:ShowTooltip(row, entry) end,
    })
    self.board:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
    self.board:SetPoint("BOTTOMRIGHT", panel.content, "BOTTOMRIGHT", 0, 18)
    self.board:Hide()

    self.boardNote = Theme.Label(panel.content, L.ACH_HAND_NOTE, fonts.small, Theme.color.textFaint)
    self.boardNote:SetPoint("BOTTOMLEFT", panel.content, "BOTTOMLEFT", 2, 2)
    self.boardNote:SetPoint("RIGHT", panel.content, "RIGHT", -2, 0)
    self.boardNote:SetJustifyH("LEFT")
    singleLine(self.boardNote)
    self.boardNote:Hide()

    -- ------------------------------------------------------ Hall of Fame ----
    local side = Widgets.Panel(frame, L.ACH_HALL, L.ACH_HALL_LATEST)
    side:SetWidth(SIDE_W)
    side:SetPoint("TOPRIGHT", chips, "BOTTOMRIGHT", 0, -6)
    side:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.side = side

    self.hallNote = Theme.Label(side.content, L.ACH_HALL_NOTE, fonts.small, Theme.color.textFaint)
    self.hallNote:SetPoint("BOTTOMLEFT", side.content, "BOTTOMLEFT", 2, 0)
    self.hallNote:SetPoint("RIGHT", side.content, "RIGHT", -2, 0)
    self.hallNote:SetJustifyH("LEFT")
    self.hallNote:SetSpacing(2)
    self.hallNote:SetHeight(40)

    self.hall = Widgets.ScrollList(side.content, {
        rowHeight = 46,
        createRow = function(row) self:BuildHallRow(row) end,
        updateRow = function(row, entry) self:UpdateHallRow(row, entry) end,
        onEnterRow = function(row, entry) self:ShowTooltip(row, entry) end,
        onClickRow = function(entry) self:OnClickRow(entry) end,
    })
    self.hall:SetPoint("TOPLEFT", side.content, "TOPLEFT", 0, 0)
    self.hall:SetPoint("BOTTOMRIGHT", self.hallNote, "TOPRIGHT", 2, 4)

    self.frame = frame
    return frame
end

-- ================================================================== Karten ---

function View:BuildCard(index)
    if self.cards[index] then return self.cards[index] end
    local fonts = Theme.Fonts()

    local card = CreateFrame("Button", nil, self.scroll.content)
    card:SetHeight(CARD_H)
    card.fill = Theme.Fill(card, Theme.color.panelBg)
    card.lines = Theme.Outline(card, Theme.color.border)

    card.edge = card:CreateTexture(nil, "OVERLAY")
    card.edge:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.edge:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.edge:SetHeight(3)

    local holder = CreateFrame("Frame", nil, card)
    holder:SetWidth(ICON_SIZE) holder:SetHeight(ICON_SIZE)
    holder:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -12)
    Theme.Fill(holder, Theme.color.sidebarBg)
    card.iconLines = Theme.Outline(holder, Theme.color.border)
    card.icon = holder:CreateTexture(nil, "ARTWORK")
    card.icon:SetAllPoints(holder)
    card.iconHolder = holder

    card.name = Theme.Label(card, "", fonts.nav, Theme.color.text)
    card.name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 8, -1)
    card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.name:SetJustifyH("LEFT")
    singleLine(card.name)

    card.sub = Theme.Label(card, "", fonts.small, Theme.color.textFaint)
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.sub:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.sub:SetJustifyH("LEFT")
    singleLine(card.sub)

    card.desc = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.desc:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -46)
    card.desc:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.desc:SetHeight(26)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetJustifyV("TOP")
    if card.desc.SetMaxLines then pcall(card.desc.SetMaxLines, card.desc, 2) end

    card.state = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.state:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -76)
    singleLine(card.state)

    card.barTrack = card:CreateTexture(nil, "ARTWORK")
    Theme.Paint(card.barTrack, Theme.color.windowBg)
    card.barTrack:SetHeight(5)
    card.barTrack:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -79)
    card.barTrack:SetPoint("RIGHT", card.state, "LEFT", -6, 0)

    card.barFill = card:CreateTexture(nil, "OVERLAY")
    card.barFill:SetHeight(5)
    card.barFill:SetPoint("LEFT", card.barTrack, "LEFT", 0, 0)
    card.barFill:SetWidth(1)

    -- Der Nachweischip.
    card.chip = CreateFrame("Frame", nil, card)
    card.chip:SetHeight(15)
    card.chip:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
    card.chipLines = Theme.Outline(card.chip, Theme.color.border)
    card.chipText = Theme.Label(card.chip, "", fonts.small, Theme.color.textDim)
    card.chipText:SetPoint("CENTER", card.chip, "CENTER", 0, 0)

    card.selection = Theme.Outline(card, Theme.color.goldBright)
    for _, line in ipairs(card.selection) do line:Hide() end

    card:SetScript("OnClick", function(button) self:OnClickRow(button.entry) end)
    card:SetScript("OnEnter", function(button)
        Theme.Paint(button.fill, Theme.color.rowHover)
        self:ShowTooltip(button, button.entry)
    end)
    card:SetScript("OnLeave", function(button)
        Theme.Paint(button.fill, Theme.color.panelBg)
        GameTooltip:Hide()
    end)

    self.cards[index] = card
    return card
end

local function setChip(card, text, color)
    card.chipText:SetText(string.upper(text or ""))
    setColor(card.chipText, color)
    paintLines(card.chipLines, color)
    card.chip:SetWidth(card.chipText:GetStringWidth() + 12)
end

local function setBar(card, ratio, color)
    if ratio == nil then
        card.barTrack:Hide() card.barFill:Hide()
        return
    end
    local breite = card.barTrack:GetWidth()
    if not breite or breite <= 0 then breite = 120 end
    Theme.BarFill(card.barFill, color)
    card.barFill:SetWidth(math.max(1, breite * math.min(1, math.max(0, ratio))))
    card.barTrack:Show() card.barFill:Show()
end

function View:UpdateCard(card, entry)
    card.entry = entry
    local rarity = RARITY_COLOR[entry.rarity] or Theme.color.text
    Theme.Paint(card.edge, rarity)
    Symbols:Apply(card.icon, entry)
    if card.icon.SetDesaturated then pcall(card.icon.SetDesaturated, card.icon, false) end

    card.name:SetText(entry.name or entry.id)
    card.sub:SetText(string.format("%s · %s", categoryName(entry.category) or "?",
        string.format(L.ACH_TT_POINTS, entry.points or 0)))

    local chosen = entry.id ~= nil and entry.id == self.selected
    for _, line in ipairs(card.selection) do
        if chosen then line:Show() else line:Hide() end
    end

    if entry.mode == "HALL" then
        setColor(card.name, rarity)
        paintLines(card.iconLines, rarity)
        card.desc:SetText(entry.description or "")
        setColor(card.desc, Theme.color.textDim)
        card.state:SetText(string.format(L.ACH_HALL_DETAIL,
            tostring(entry.holder), Util.TimeAgo(entry.ts)))
        setColor(card.state, Theme.color.text)
        setBar(card, nil)
        local state = L["ACH_STATE_" .. tostring(entry.state)] or tostring(entry.state)
        if entry.claims and entry.claims > 1 then
            state = state .. string.format(L.ACH_CLAIMS, entry.claims)
        end
        setChip(card, state, entry.contested and Theme.color.warn
            or (entry.state == "verified" and Theme.color.jade or Theme.color.textDim))
        return
    end

    card.desc:SetText(entry.description or "")

    if entry.unlocked then
        setColor(card.name, rarity)
        paintLines(card.iconLines, rarity)
        setColor(card.desc, Theme.color.textDim)
        card.state:SetText(L.ACH_REACHED .. " · " .. Util.TimeAgo(entry.ts))
        setColor(card.state, Theme.color.jade)
        setBar(card, 1, rarity)
        local color = Theme.color[EVIDENCE_COLOR[entry.evidence] or "textDim"]
        setChip(card, L["ACH_EV_" .. tostring(entry.evidence)] or tostring(entry.evidence), color)
        return
    end

    -- Offen: gedaempft. Nicht messbar: noch mehr, und ohne Balken.
    if card.icon.SetDesaturated then pcall(card.icon.SetDesaturated, card.icon, true) end
    setColor(card.name, Theme.color.textDim)
    paintLines(card.iconLines, Theme.color.border)
    setColor(card.desc, Theme.color.textFaint)

    local progress = entry.progress
    if not progress or not progress.measurable then
        card.state:SetText("")
        setBar(card, nil)
        setChip(card, L.ACH_NOT_MEASURABLE, Theme.color.textFaint)
        return
    end
    if progress.unreachable then
        card.state:SetText(string.format(L.ACH_UNREACHABLE, progress.ceiling))
        setColor(card.state, Theme.color.warn)
        setBar(card, nil)
        setChip(card, L.ACH_EV_measured, Theme.color.textFaint)
        return
    end

    card.state:SetText(string.format("%d / %d", progress.current, progress.target))
    setColor(card.state, Theme.color.textDim)
    setBar(card, progress.target > 0 and (progress.current / progress.target) or 0, Theme.color.goldDim)
    setChip(card, L.ACH_EV_measured, Theme.color.textFaint)
end

--- Eine Kopfzeile fuer eine Kategorie im Raster.
function View:BuildHeader(index)
    if self.headers[index] then return self.headers[index] end
    local fonts = Theme.Fonts()

    local header = CreateFrame("Button", nil, self.scroll.content)
    header:SetHeight(HEADER_H)
    header.fill = Theme.Fill(header, Theme.color.windowBg)
    Theme.Edge(header, "BOTTOM", Theme.color.border)

    header.bar = header:CreateTexture(nil, "ARTWORK")
    Theme.Paint(header.bar, Theme.color.gold)
    header.bar:SetWidth(3) header.bar:SetHeight(14)
    header.bar:SetPoint("LEFT", header, "LEFT", 8, 0)

    header.toggle = Theme.Label(header, "", fonts.big, Theme.color.gold)
    header.toggle:SetPoint("LEFT", header, "LEFT", 17, 0)
    header.toggle:SetWidth(14)

    header.name = Theme.Label(header, "", fonts.heading, Theme.color.heading)
    header.name:SetPoint("LEFT", header, "LEFT", 34, 0)

    header.detail = Theme.Label(header, "", fonts.small, Theme.color.textDim)
    header.detail:SetPoint("LEFT", header.name, "RIGHT", 8, 0)

    header.points = Theme.Label(header, "", fonts.rowBold, Theme.color.goldBright)
    header.points:SetPoint("RIGHT", header, "RIGHT", -8, 0)

    header.barTrack = header:CreateTexture(nil, "ARTWORK")
    Theme.Paint(header.barTrack, Theme.color.panelBg)
    header.barTrack:SetWidth(80) header.barTrack:SetHeight(5)
    header.barTrack:SetPoint("RIGHT", header.points, "LEFT", -8, 0)

    header.barFill = header:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(header.barFill, Theme.color.goldDim)
    header.barFill:SetHeight(5)
    header.barFill:SetPoint("LEFT", header.barTrack, "LEFT", 0, 0)

    header:SetScript("OnClick", function(button) self:OnClickRow(button.entry) end)

    self.headers[index] = header
    return header
end

function View:UpdateHeader(header, entry)
    header.entry = entry
    header.toggle:SetText(entry.collapsed and "+" or "-")
    header.name:SetText(string.upper(categoryName(entry.category) or entry.category))
    if entry.unlocked == 0 then
        header.detail:SetText(string.format(L.ACH_CAT_UNTOUCHED, entry.total))
    else
        header.detail:SetText(string.format(L.ACH_CAT_PROGRESS, entry.unlocked, entry.total))
    end
    header.points:SetText(string.format("%d / %d", entry.points, entry.available))
    local anteil = entry.available > 0 and (entry.points / entry.available) or 0
    header.barFill:SetWidth(math.max(1, 80 * math.min(1, anteil)))
end

--- Legt Kopfzeilen und Karten ins Raster. Eine Kopfzeile nimmt eine ganze
--- Zeile; Karten stehen zu so vielen nebeneinander, wie der Platz hergibt.
function View:LayoutCards()
    local entries = self.entries or {}
    local content = self.scroll.content
    local breite = self.scroll:GetWidth()
    if not breite or breite <= 0 then return end
    content:SetWidth(breite)

    local spalten = math.max(1, math.floor((breite + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
    local cardW = math.floor((breite - (spalten - 1) * CARD_GAP) / spalten)

    local y, spalte = 0, 0
    local cardIndex, headerIndex = 0, 0
    for _, entry in ipairs(entries) do
        if entry.isHeader then
            if spalte > 0 then y = y + CARD_H + CARD_GAP spalte = 0 end
            headerIndex = headerIndex + 1
            local header = self:BuildHeader(headerIndex)
            self:UpdateHeader(header, entry)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            header:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            header:Show()
            y = y + HEADER_H + 4
        else
            cardIndex = cardIndex + 1
            local card = self:BuildCard(cardIndex)
            card:ClearAllPoints()
            card:SetWidth(cardW)
            card:SetPoint("TOPLEFT", content, "TOPLEFT", spalte * (cardW + CARD_GAP), -y)
            card:Show()
            self:UpdateCard(card, entry)
            spalte = spalte + 1
            if spalte >= spalten then
                spalte = 0
                y = y + CARD_H + CARD_GAP
            end
        end
    end
    if spalte > 0 then y = y + CARD_H end
    for index = cardIndex + 1, #self.cards do self.cards[index]:Hide() end
    for index = headerIndex + 1, #self.headers do self.headers[index]:Hide() end

    content:SetHeight(math.max(1, y))
    self.scroll:Refresh()
end

-- ================================================================== Tabellen -

function View:BuildBoardRow(row)
    local fonts = Theme.Fonts()
    local x, w = 8, {}
    for _, column in ipairs(self.board.columns) do w[column.key] = { x = x, width = column.width } x = x + column.width + 6 end

    row.rank = Theme.Label(row, "", fonts.nav, Theme.color.textDim)
    row.rank:SetPoint("LEFT", row, "LEFT", w.rank.x, 0)

    row.name = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", w.name.x, 0)
    row.name:SetWidth(w.name.width)
    row.name:SetJustifyH("LEFT")
    singleLine(row.name)

    row.barTrack = row:CreateTexture(nil, "ARTWORK")
    Theme.Paint(row.barTrack, Theme.color.windowBg)
    row.barTrack:SetWidth(34) row.barTrack:SetHeight(5)
    row.barTrack:SetPoint("LEFT", row, "LEFT", w.points.x, 0)
    row.barFill = row:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(row.barFill, Theme.color.goldDim)
    row.barFill:SetHeight(5)
    row.barFill:SetPoint("LEFT", row.barTrack, "LEFT", 0, 0)

    row.points = Theme.Label(row, "", fonts.rowBold, Theme.color.goldBright)
    row.points:SetPoint("LEFT", row, "LEFT", w.points.x + 40, 0)
    row.points:SetWidth(w.points.width - 40)
    row.points:SetJustifyH("RIGHT")

    row.count = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.count:SetPoint("LEFT", row, "LEFT", w.count.x, 0)
    row.count:SetWidth(w.count.width)
    row.count:SetJustifyH("RIGHT")

    row.firsts = Theme.Label(row, "", fonts.small, RARITY_COLOR.EPIC)
    row.firsts:SetPoint("LEFT", row, "LEFT", w.firsts.x, 0)
    row.firsts:SetWidth(w.firsts.width)
    row.firsts:SetJustifyH("RIGHT")

    row.hand = Theme.Label(row, "", fonts.small, Theme.color.warn)
    row.hand:SetPoint("LEFT", row, "LEFT", w.hand.x, 0)
    row.hand:SetWidth(w.hand.width)
    row.hand:SetJustifyH("RIGHT")
end

function View:UpdateBoardRow(row, entry)
    local color = RANK_COLOR[entry.rank] or Theme.color.textFaint
    row.rank:SetText(tostring(entry.rank or "?"))
    setColor(row.rank, color)
    row.name:SetText(entry.name or "?")
    row.points:SetText(tostring(entry.points))
    local best = self.bestPoints or 0
    row.barFill:SetWidth(math.max(1, 34 * (best > 0 and entry.points / best or 0)))
    row.count:SetText(tostring(entry.count))
    row.firsts:SetText(entry.firsts > 0 and tostring(entry.firsts) or "")
    row.hand:SetText(entry.granted > 0 and tostring(entry.granted) or "")
end

function View:BuildHallRow(row)
    local fonts = Theme.Fonts()
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.accent:SetWidth(3)

    row.name = Theme.Label(row, "", fonts.nav, Theme.color.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.name:SetJustifyH("LEFT")
    singleLine(row.name)

    row.holder = Theme.Label(row, "", fonts.small, Theme.color.text)
    row.holder:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -20)
    row.holder:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.holder:SetJustifyH("LEFT")
    singleLine(row.holder)

    row.state = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.state:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -32)
    row.state:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.state:SetJustifyH("LEFT")
    singleLine(row.state)

    row.selection = Theme.Outline(row, Theme.color.goldBright)
    for _, line in ipairs(row.selection) do line:Hide() end
end

function View:UpdateHallRow(row, entry)
    local rarity = RARITY_COLOR[entry.rarity] or Theme.color.text
    Theme.Paint(row.accent, rarity)
    row.name:SetText(entry.name or entry.id)
    setColor(row.name, rarity)
    row.holder:SetText(string.format(L.ACH_HALL_DETAIL, tostring(entry.holder), Util.TimeAgo(entry.ts)))
    local state = L["ACH_STATE_" .. tostring(entry.state)] or tostring(entry.state)
    if entry.claims and entry.claims > 1 then
        state = state .. string.format(L.ACH_CLAIMS, entry.claims)
    end
    row.state:SetText(state)
    setColor(row.state, entry.contested and Theme.color.warn
        or (entry.state == "verified" and Theme.color.jade or Theme.color.textDim))
    local chosen = entry.id ~= nil and entry.id == self.selected
    for _, line in ipairs(row.selection) do
        if chosen then line:Show() else line:Hide() end
    end
end

-- ================================================================== Tooltip --

function View:ShowTooltip(owner, entry)
    if not GameTooltip or not entry or entry.isHeader then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    if entry.mode == "BOARD" then
        GameTooltip:SetText(entry.name or "?", 1, 1, 1)
        GameTooltip:AddLine(string.format(L.ACH_BOARD_DETAIL, entry.count, entry.firsts),
            0.7, 0.7, 0.7)
        GameTooltip:AddLine(string.format(L.ACH_TT_POINTS, entry.points), 0.9, 0.8, 0.5)
        if entry.granted > 0 then
            GameTooltip:AddLine(string.format(L.ACH_GRANTED_HINT, entry.granted),
                0.85, 0.64, 0.25)
        end
        GameTooltip:Show()
        return
    end

    local rarity = RARITY_COLOR[entry.rarity] or Theme.color.text
    GameTooltip:SetText(entry.name or entry.id, rarity[1], rarity[2], rarity[3])

    if entry.description then
        GameTooltip:AddLine(entry.description, 0.82, 0.78, 0.70, true)
    end

    local category = categoryName(entry.category)
    if category then
        GameTooltip:AddLine(string.format(L.ACH_TT_CATEGORY, category), 0.55, 0.52, 0.45)
    end
    GameTooltip:AddLine(string.format(L.ACH_TT_POINTS, entry.points or 0), 0.9, 0.8, 0.5)

    if entry.mode == "HALL" then
        GameTooltip:AddLine(string.format(L.ACH_TT_HOLDER, tostring(entry.holder)), 1, 1, 1)
        GameTooltip:AddLine(string.format(L.ACH_TT_UNLOCKED, Util.TimeAgo(entry.ts)),
            0.6, 0.6, 0.6)
        local state = L["ACH_STATE_" .. tostring(entry.state)] or entry.state
        GameTooltip:AddLine(state, entry.contested and 0.85 or 0.37,
            entry.contested and 0.64 or 0.79, entry.contested and 0.25 or 0.63)
        GameTooltip:Show()
        return
    end

    if entry.unlocked then
        GameTooltip:AddLine(string.format(L.ACH_TT_UNLOCKED, Util.TimeAgo(entry.ts)),
            0.6, 0.6, 0.6)
        if entry.character then
            GameTooltip:AddLine(string.format(L.ACH_TT_CHARACTER, entry.character),
                0.6, 0.6, 0.6)
        end
        local evidence = L["ACH_EV_" .. tostring(entry.evidence)]
        if evidence then
            local granted = entry.evidence == "granted"
            GameTooltip:AddLine(evidence, granted and 0.85 or 0.37,
                granted and 0.64 or 0.79, granted and 0.25 or 0.63)
        end
        if entry.reason and entry.reason ~= "" then
            GameTooltip:AddLine(entry.reason, 0.66, 0.61, 0.52, true)
        end
        GameTooltip:Show()
        return
    end

    local progress = entry.progress
    if not progress or not progress.measurable then
        GameTooltip:AddLine(L.ACH_NOT_MEASURABLE, 0.55, 0.52, 0.45)
    elseif progress.unreachable then
        GameTooltip:AddLine(string.format(L.ACH_UNREACHABLE, progress.ceiling),
            0.85, 0.64, 0.25)
    else
        GameTooltip:AddLine(string.format(L.ACH_TT_PROGRESS,
            progress.current, progress.target), 0.37, 0.79, 0.63)
    end
    GameTooltip:Show()
end

-- GRUPPIERUNG ANFANG (wird so getestet, Marke nicht entfernen)

--- Baut aus einer flachen Erfolgsliste die Zeilen mit Kopfzeilen.
---
--- Ohne Oberflaeche und ohne GA: Hier steckt die ganze Regel, und sie laesst
--- sich damit pruefen, ohne einen Spielclient zu brauchen.
---
--- DER STAND EINER KATEGORIE WIRD UEBER ALLE IHRE ERFOLGE GERECHNET, nie ueber
--- die gerade sichtbaren. Sonst stuende beim Suchen nach "Drache" ploetzlich
--- "1 von 1 Erfolgen" da — eine Aussage ueber das Suchfeld statt ueber die
--- Gilde. Deshalb zaehlt die Schleife ZUERST und filtert DANACH.
---
--- @param list table            alle Erfolge, flach
--- @param order table           Reihenfolge der Kategorien
--- @param shut table            [category] = true fuer zugeklappt
--- @param keep function(row)    Filter, z.B. aus dem Suchfeld
--- @return table zeilen
function View.Group(list, order, shut, keep)
    shut = shut or {}

    local groups, stats = {}, {}
    for _, row in ipairs(list) do
        local category = row.category or "?"
        local stat = stats[category]
        if not stat then
            stat = { points = 0, available = 0, unlocked = 0, total = 0 }
            stats[category] = stat
            groups[category] = {}
        end

        stat.total = stat.total + 1
        stat.available = stat.available + (row.points or 0)
        if row.unlocked then
            stat.unlocked = stat.unlocked + 1
            stat.points = stat.points + (row.points or 0)
        end

        row.mode = "OWN"
        if not keep or keep(row) then
            local visible = groups[category]
            visible[#visible + 1] = row
        end
    end

    local out = {}
    for _, category in ipairs(order) do
        local visible, stat = groups[category], stats[category]
        if stat and visible and #visible > 0 then
            out[#out + 1] = {
                isHeader = true,
                mode = "OWN",
                category = category,
                points = stat.points,
                available = stat.available,
                unlocked = stat.unlocked,
                total = stat.total,
                collapsed = shut[category] and true or false,
            }

            if not shut[category] then
                -- Innerhalb der Gruppe: Freigeschaltetes zuerst, danach das
                -- Messbare, ganz unten das noch nicht Messbare. Wer nach dem
                -- naechsten Ziel sucht, soll nicht an Zeilen vorbei, die gar
                -- nicht gezaehlt werden.
                table.sort(visible, function(a, b)
                    if a.unlocked ~= b.unlocked then return a.unlocked end
                    local am = a.progress and a.progress.measurable
                    local bm = b.progress and b.progress.measurable
                    if am ~= bm then return am and true or false end
                    if a.unlocked and b.unlocked then return (a.ts or 0) > (b.ts or 0) end
                    return (a.id or "") < (b.id or "")
                end)
                for _, row in ipairs(visible) do out[#out + 1] = row end
            end
        end
    end

    return out
end

-- GRUPPIERUNG ENDE

-- ================================================================== Daten -----

function View:Rows()
    local Achievements = GA.Modules.Achievements
    local Rules = GA.Modules.Rules
    local search = string.lower(self.search and self.search:GetValue() or "")

    local function matches(text)
        return search == "" or string.find(string.lower(tostring(text or "")), search, 1, true)
    end

    if self.mode == "BOARD" then
        local out = {}
        for rank, row in ipairs(Achievements:Leaderboard()) do
            row.rank = rank
            if matches(row.name) then
                row.mode = "BOARD"
                out[#out + 1] = row
            end
        end
        return out
    end

    if self.mode == "HALL" then
        local catalog = GA.Data.Catalog
        local out = {}
        for _, row in ipairs(Achievements:HallOfFame()) do
            local entry = catalog and catalog.ENTRIES[row.id]
            row.category = entry and entry.category
            row.description = entry and entry.description
            if matches(row.name) or matches(row.holder)
                or matches(categoryName(row.category))
            then
                row.mode = "HALL"
                out[#out + 1] = row
            end
        end
        return out
    end

    local list = Achievements:List()
    if Rules then
        for _, row in ipairs(list) do
            if not row.unlocked then row.progress = Rules:Progress(row.id) end
        end
    end

    local order = (GA.Data.Catalog and GA.Data.Catalog.CATEGORIES) or {}

    -- Zugeklappt, was nicht offen ist — ausser beim Suchen, und ausser der
    -- einen gewaehlten Kategorie: Die ist immer offen, sonst waere der Chip
    -- ein Umweg zu einer Kopfzeile.
    local shut = {}
    if search == "" then
        local open = expanded()
        for _, category in ipairs(order) do
            if not open[category] and category ~= self.category then shut[category] = true end
        end
    end

    local category = self.category
    return View.Group(list, order, shut,
        function(row)
            if category and row.category ~= category then return false end
            return matches(row.name) or matches(row.description)
                or matches(categoryName(row.category))
        end)
end

-- ================================================================== Aktionen -

function View:OnClickRow(entry)
    if not entry then return end

    if entry.isHeader then
        local open = expanded()
        open[entry.category] = (not open[entry.category]) or nil
        self:Refresh()
        return
    end

    self.selected = (self.selected ~= entry.id) and entry.id or nil
    self:Refresh()
end

function View:GrantSelected()
    if not self.selected then
        GA.UI.MainFrame:Notice("info", "%s", L.GRANT_NEED_ROW)
        return
    end
    local ok, reason = GA.UI.GrantDialog:Open(self.selected)
    if not ok then
        GA.UI.MainFrame:Notice("info", "%s",
            L["GRANT_ERR_" .. string.upper(tostring(reason))] or tostring(reason))
    end
end

function View:RevokeSelected()
    if not self.selected then
        GA.UI.MainFrame:Notice("info", "%s", L.GRANT_NEED_ROW)
        return
    end

    local Achievements = GA.Modules.Achievements
    local ok, reason = Achievements:Revoke(self.selected, self:PlayerId())
    if ok then
        GA.UI.MainFrame:Notice("info", L.GRANT_REVOKED,
            tostring((Achievements:Entry(self.selected) or {}).name))
        self:Refresh()
    else
        GA.UI.MainFrame:Notice("info", "%s",
            L["GRANT_ERR_" .. string.upper(tostring(reason))] or tostring(reason))
    end
end

function View:PlayerId()
    local guid = GA.Core.Compat.GetPlayerIdentity().guid
    local profile = guid and GA.Modules.Players:GetProfileFor(guid)
    return profile and profile.id or nil
end

function View:ToggleAll()
    local open = expanded()
    local order = (GA.Data.Catalog and GA.Data.Catalog.CATEGORIES) or {}

    local anyOpen = false
    for _, category in ipairs(order) do
        if open[category] then anyOpen = true break end
    end

    for _, category in ipairs(order) do
        open[category] = (not anyOpen) or nil
    end
    self:Refresh()
end

-- ================================================================== Refresh --

function View:OnShow() self:Refresh() end

--- Der Stand je Kategorie, ueber ALLE Erfolge — fuer die Chips.
function View:CategoryStats()
    local stats = {}
    for _, entry in ipairs(GA.Modules.Achievements:List()) do
        local stat = stats[entry.category] or { unlocked = 0, total = 0 }
        stats[entry.category] = stat
        stat.total = stat.total + 1
        if entry.unlocked then stat.unlocked = stat.unlocked + 1 end
    end
    return stats
end

--- Legt die Chips zeilenweise: so viele je Zeile, wie die Breite hergibt,
--- die Leiste waechst mit, und was darunter haengt, rueckt nach.
---
--- GEMESSEN 28.09.2026 mit Bild: Vierzehn Chips in einer Kette liefen
--- rechts aus dem Fenster — "ECONOMY 0/18" war halb zu sehen, der Rest gar
--- nicht. Eine Kette hat kein Ende; eine Zeile hat eines.
local CHIP_GAP, CHIP_ROW = 3, 22
function View:LayoutChips()
    local bar = self.chipBar
    if not bar then return end
    local breite = bar:GetWidth()
    if not breite or breite <= 1 then return end

    local x, reihe = 0, 0
    for _, chip in ipairs(self.categoryChips) do
        if chip:IsShown() then
            local w = chip:GetWidth() or 60
            if x > 0 and x + w > breite then
                x, reihe = 0, reihe + 1
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -(reihe * CHIP_ROW))
            x = x + w + CHIP_GAP
        end
    end
    local hoehe = self.mode == "OWN" and ((reihe + 1) * CHIP_ROW - 2) or 0
    if math.abs((bar:GetHeight() or 0) - hoehe) > 0.5 then bar:SetHeight(math.max(1, hoehe)) end
end

function View:Refresh()
    if not self.frame then return end
    for _, button in ipairs(self.modeButtons) do
        button:SetEnabledState(button.mode ~= self.mode)
    end

    local Achievements = GA.Modules.Achievements
    local points = Achievements:Points()

    -- Chips: Beschriftung mit Stand, einer gedrueckt.
    local stats = self:CategoryStats()
    for _, chip in ipairs(self.categoryChips) do
        local key = chip.categoryKey
        local text
        if key == "ALL" then
            text = string.format("%s %d/%d", L.ACH_FILTER_ALL, points.count, points.available)
        else
            local stat = stats[key] or { unlocked = 0, total = 0 }
            text = string.format("%s %d/%d", categoryName(key) or key, stat.unlocked, stat.total)
        end
        chip.label:SetText(string.upper(text))
        chip:SetWidth(chip.label:GetStringWidth() + 18)
        chip:SetPressed((key == "ALL" and self.category == nil) or key == self.category)
        chip:SetShown(self.mode == "OWN")
    end
    self:LayoutChips()

    local rows = self:Rows()
    local own = self.mode ~= "BOARD"

    if own then
        self.entries = rows
        self.board:Hide()
        self.boardNote:Hide()
        self.scroll:Show()
        self:LayoutCards()
    else
        self.entries = {}
        self:LayoutCards()
        self.scroll:Hide()
        self.bestPoints = rows[1] and rows[1].points or 0
        self.board:SetData(rows)
        self.board:Show()
        self.boardNote:Show()
    end
    if #rows == 0 then self.empty:Show() else self.empty:Hide() end

    -- Die Seitenspalte nur bei den eigenen Erfolgen: In der Hall of Fame
    -- stuende sie neben sich selbst.
    if self.mode == "OWN" then
        self.side:Show()
        self.panel:SetPoint("RIGHT", self.frame, "RIGHT", -(4 + SIDE_W + 8), 0)
        local hall = Achievements:HallOfFame()
        local neueste = {}
        for index = #hall, math.max(1, #hall - 7), -1 do
            local entry = hall[index]
            entry.mode = "HALL"
            neueste[#neueste + 1] = entry
        end
        self.hall:SetData(neueste)
    else
        self.side:Hide()
        self.panel:SetPoint("RIGHT", self.frame, "RIGHT", -4, 0)
    end

    if self.mode == "OWN" then
        local open = expanded()
        local order = (GA.Data.Catalog and GA.Data.Catalog.CATEGORIES) or {}
        local anyOpen = false
        for _, category in ipairs(order) do
            if open[category] then anyOpen = true break end
        end
        self.toggleAll:SetLabel(anyOpen and L.ACH_COLLAPSE_ALL or L.ACH_EXPAND_ALL)
        self.toggleAll:SetWidth(110)
        self.toggleAll:Show()
    else
        self.toggleAll:Hide()
    end

    local mayGrant = GA.Modules.Achievements:MayGrant() and self.mode ~= "BOARD"
    if mayGrant then
        self.grantButton:Show()
        self.grantButton:SetEnabledState(self.selected ~= nil, L.GRANT_NEED_ROW)
        self.revokeButton:Show()
        self.revokeButton:SetEnabledState(self.selected ~= nil, L.GRANT_NEED_ROW)
    else
        self.grantButton:Hide()
        self.revokeButton:Hide()
    end
    -- Der Klappknopf haengt rechts am Zuruecknehmen — ohne dieses am Rand.
    self.toggleAll:ClearAllPoints()
    if mayGrant then
        self.toggleAll:SetPoint("RIGHT", self.revokeButton, "LEFT", -4, 0)
    else
        self.toggleAll:SetPoint("BOTTOMRIGHT", self.head, "BOTTOMRIGHT", -10, 8)
    end

    if self.mode == "BOARD" then
        self.panel:SetTitle(L.ACH_MODE_BOARD)
    elseif self.mode == "HALL" then
        self.panel:SetTitle(L.ACH_HALL)
    else
        self.panel:SetTitle(L.ACH_TITLE)
    end

    -- Die Kacheln: Zahl, Beschriftung, Einordnung.
    self.tilePoints:Set(points.total, L.ACH_STAT_POINTS,
        points.granted > 0 and string.format(L.ACH_STAT_BYHAND, points.granted) or "",
        nil, Theme.color.warn)
    local coverage = GA.Modules.Rules and GA.Modules.Rules:Coverage()
    self.tileDone:Set(string.format("%d / %d", points.count, points.available), L.ACH_STAT_DONE,
        coverage and string.format(L.ACH_COVERAGE_SHORT, coverage.measurable) or "")
    local strittig = 0
    for _, entry in ipairs(Achievements:HallOfFame()) do
        if entry.contested then strittig = strittig + 1 end
    end
    self.tileFirsts:Set(points.firsts, L.ACH_STAT_FIRSTS,
        strittig > 0 and string.format(L.ACH_CONTESTED_COUNT, strittig) or "",
        RARITY_COLOR.EPIC, Theme.color.warn)

    local since = GA.Core.Database.account.achievementsSince
    self.since:SetText(since and string.format(L.ACH_SINCE, Util.TimeAgo(since)) or "")

    GA.UI.MainFrame:SetContext(string.format("%d", points.total))
end

for _, event in ipairs({ "ACHIEVEMENT_UNLOCKED", "ACHIEVEMENT_CHANGED",
                         "ACHIEVEMENT_CONTESTED" }) do
    GA.Core.Callbacks:On(event, function()
        if View.frame and View.frame:IsVisible() then View:Refresh() end
    end, "AchievementsView")
end

GA.UI.MainFrame:RegisterView("achievements", View)
