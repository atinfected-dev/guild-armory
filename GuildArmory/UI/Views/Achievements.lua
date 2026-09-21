--[[----------------------------------------------------------------------------
    UI/Views/Achievements — Erfolge, Hall of Fame und Rangliste.

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
    WARUM DIE ZEILE SO GEBAUT IST (21.09.2026)
    ===========================================================================

    272 Eintraege sind zu viele, um sie zu LESEN. Man ueberfliegt sie. Also
    muss jede Zeile drei Fragen ohne Lesen beantworten:

      Was ist das?       Das Symbol (die Kategorie) und die Farbe (Seltenheit)
      Habe ich es?       Der goldene Streifen an der Kante
      Wie weit bin ich?  Der Balken — und zwar NUR dort, wo wirklich gezaehlt
                         wird

    DER BALKEN IST DESHALB KEINE DEKORATION, SONDERN EINE AUSSAGE. Wo keiner
    steht, wird nicht gemessen, und daneben steht warum. Ein Balken bei null
    ueber zweihundert Zeilen waere hier die bequeme, aber falsche Loesung.

    Alles, was in einer Zeile nicht mehr Platz hat — Kategorie, Beleg,
    Charakter, Datum, der ganze Beschreibungstext — steht im Tooltip. Die
    Zeile kuerzt mit Auslassungspunkten statt ueber den Rand zu laufen.

    ===========================================================================
    KATEGORIEN ZUM AUFKLAPPEN (21.09.2026)
    ===========================================================================

    Die eigenen Erfolge stehen in dreizehn Gruppen mit eigener Kopfzeile, und
    ZUGEKLAPPT IST DIE GRUNDEINSTELLUNG. Wer die Ansicht oeffnet, sieht
    dreizehn Zeilen mit je einem Stand — nicht 272 Zeilen, durch die er sich
    erst scrollen muss, um zu erkennen, wo er steht. Aufgeklappt wird, was
    gerade interessiert. Das loest zwei Dinge auf einmal:

      Man kann WEGRAEUMEN, was gerade nicht interessiert. Von 272 Zeilen sind
      an einem Abend vielleicht zwanzig wichtig.

      Und jede Gruppe traegt ihren eigenen Stand: Punkte, Anzahl und einen
      Balken. Der Gesamtpunktestand oben sagt, wie weit man ist — die Kopfzeilen
      sagen, WORIN.

    DER KATEGORIESTAND WIRD IMMER UEBER ALLE ERFOLGE GERECHNET, nie ueber die
    gerade sichtbaren. Sonst stuende beim Suchen nach "Drache" plotzlich
    "1 von 1 Erfolgen" da, und die Zahl waere eine Aussage ueber das Suchfeld
    statt ueber die Gilde. Beim Suchen sind deshalb auch alle Gruppen offen:
    Wer sucht, will finden, nicht erst aufklappen.

    Hall of Fame und Rangliste bleiben ungruppiert. In der Hall of Fame sind
    alle Eintraege Gilden-Firsts — eine einzige Gruppe ist keine — und eine
    Rangliste, die man aufklappen muss, ist keine Rangliste mehr.
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

--- Welches Symbol zu welchem Erfolg gehoert, steht in UI/AchievementIcons —
--- das ist eine eigene Frage mit eigener Begruendung und gehoert nicht in
--- eine Ansicht.
local Symbols = GA.UI.AchievementIcons

local ROW_HEIGHT   = 42
local ICON_SIZE    = 30
local TEXT_LEFT    = 46   -- 7 Rand + 30 Symbol + 9 Luft
local HEADER_LEFT  = 32   -- Kopfzeilen tragen kein Symbol, nur das Zeichen
local RIGHT_COLUMN = 150  -- Punkte und Zustand

--- Welche Kategorien sind AUFGEKLAPPT.
---
--- Liegt in der Datenbank, damit die Einstellung einen Reload ueberlebt — es
--- ist eine Ansichtssache, kein Messwert, und sie wird deshalb auch nicht ins
--- Journal geschrieben.
---
--- Gespeichert wird das Offene, nicht das Geschlossene — und darin steckt die
--- Grundeinstellung: Eine leere Tabelle heisst "alles zu". Beim ersten
--- Oeffnen stehen deshalb dreizehn Kopfzeilen da und sonst nichts, und man
--- sieht mit einem Blick, wo man in jeder Gruppe steht, statt durch 272
--- Zeilen zu scrollen.
---
--- Andersherum gespeichert braeuchte es eine Anfangsbefuellung mit allen
--- Kategorien — und danach waere nicht mehr zu unterscheiden, ob jemand alles
--- aufgeklappt hat oder ob die Befuellung nie lief.
local function expanded()
    local account = GA.Core.Database.account
    account.achievementsExpanded = account.achievementsExpanded or {}
    return account.achievementsExpanded
end

local function categoryName(category)
    if not category then return nil end
    return L["ACH_CAT_" .. category] or category
end

--- Eine Zeile laeuft nicht ueber den Rand, sie kuerzt. Ohne das schiebt ein
--- langer Erfolgsname die Punkte aus dem Fenster.
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

--- Setzt die Balkenbreite aus dem gemerkten Verhaeltnis.
---
--- Die Breite der Zeile steht erst fest, wenn das Fenster gemessen ist.
--- Deshalb wird das VERHAELTNIS aufbewahrt und bei jeder Groessenaenderung
--- neu gerechnet — statt einmal auf eine Breite gesetzt, die noch null war.
local function applyBar(row)
    local ratio = row.barRatio
    if not ratio then return end
    local width = row.barTrack:GetWidth()
    if not width or width <= 0 then return end
    row.barFill:SetWidth(math.max(1, width * math.min(1, math.max(0, ratio))))
end

-- ================================================================== Aufbau ---

--- Eine Kennzahl im Kopf: grosse Zahl, kleine Beschriftung darunter.
local function statTile(parent, caption, width)
    local fonts = Theme.Fonts()

    local tile = CreateFrame("Frame", nil, parent)
    tile:SetWidth(width)

    local value = Theme.Label(tile, "—", fonts.number, Theme.color.goldBright)
    value:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 2)
    singleLine(value)

    local label = Theme.Label(tile, string.upper(caption or ""), fonts.heading,
        Theme.color.goldDim)
    label:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 1)
    singleLine(label)

    function tile:Set(text)
        value:SetText(tostring(text))
    end

    return tile
end

function View:Create(parent)
    local fonts = Theme.Fonts()
    local pad = 4

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Werkzeugzeile ---
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(22)

    self.mode = "OWN"
    self.modeButtons = {}
    local previous
    for _, mode in ipairs(MODES) do
        local button = Widgets.Button(bar, L["ACH_MODE_" .. mode], function()
            self.mode = mode
            -- Die Auswahl gilt fuer die Liste, die sie getroffen hat: Eine
            -- Erfolgskennung aus "Meine Erfolge" bedeutet in der Rangliste
            -- nichts.
            self.selected = nil
            self:Refresh()
        end)
        button:SetHeight(20)
        button:SetWidth(120)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else button:SetPoint("LEFT", bar, "LEFT", 0, 0) end
        button.mode = mode
        self.modeButtons[#self.modeButtons + 1] = button
        previous = button
    end

    -- Das Suchfeld steht rechts, damit die drei Knoepfe als eine Gruppe
    -- zusammenbleiben und nicht mit dem Feld zu einer Reihe verschwimmen.
    self.search = Widgets.SearchBox(bar, L.ACH_SEARCH, function() self:Refresh() end)
    self.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    self.search:SetWidth(200)

    -- Dreizehn Kopfzeilen einzeln anzuklicken ist keine Bedienung.
    self.toggleAll = Widgets.Button(bar, L.ACH_COLLAPSE_ALL, function()
        self:ToggleAll()
    end)
    self.toggleAll:SetHeight(20)
    self.toggleAll:SetWidth(130)
    self.toggleAll:SetPoint("RIGHT", self.search, "LEFT", -8, 0)

    -- Eintragen und Zuruecknehmen. Nur fuer Administratoren sichtbar: Ein
    -- Knopf, der bei jedem dasteht und bei fast jedem "darfst du nicht" sagt,
    -- ist kein Hinweis, sondern eine Sackgasse.
    self.grantButton = Widgets.Button(bar, L.GRANT_BUTTON, function()
        self:GrantSelected()
    end)
    self.grantButton:SetHeight(20)
    self.grantButton:SetPoint("RIGHT", self.toggleAll, "LEFT", -6, 0)
    self.grantButton:Hide()

    self.revokeButton = Widgets.Button(bar, L.GRANT_REVOKE, function()
        self:RevokeSelected()
    end)
    self.revokeButton:SetHeight(20)
    self.revokeButton:SetPoint("RIGHT", self.grantButton, "LEFT", -4, 0)
    self.revokeButton:Hide()

    -- ------------------------------------------------------ Kopfzahlen ------
    --
    -- Punktestand und Abdeckung standen vorher als eine lange Zeile neben dem
    -- Suchfeld und liefen dort aus dem Fenster. Sie gehoeren nicht in die
    -- Werkzeugleiste: Es sind die Zahlen, wegen derer man die Ansicht
    -- ueberhaupt oeffnet.
    local strip = Widgets.Inset(frame)
    strip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    strip:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    strip:SetHeight(46)
    self.strip = strip

    self.tilePoints = statTile(strip, L.ACH_STAT_POINTS, 96)
    self.tilePoints:SetPoint("TOPLEFT", strip, "TOPLEFT", 12, -5)
    self.tilePoints:SetPoint("BOTTOM", strip, "BOTTOM", 0, 5)

    self.tileDone = statTile(strip, L.ACH_STAT_DONE, 110)
    self.tileDone:SetPoint("TOPLEFT", self.tilePoints, "TOPRIGHT", 16, 0)
    self.tileDone:SetPoint("BOTTOM", strip, "BOTTOM", 0, 5)

    self.tileFirsts = statTile(strip, L.ACH_STAT_FIRSTS, 110)
    self.tileFirsts:SetPoint("TOPLEFT", self.tileDone, "TOPRIGHT", 16, 0)
    self.tileFirsts:SetPoint("BOTTOM", strip, "BOTTOM", 0, 5)

    -- Rechts daneben, klein und rechtsbuendig: worueber die Zahlen ueberhaupt
    -- eine Aussage machen. Ohne diese zwei Zeilen waeren sie eine Aussage
    -- ueber das Addon und nicht ueber die Gilde.
    self.since = Theme.Label(strip, "", fonts.small, Theme.color.textFaint)
    self.since:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -12, -9)
    self.since:SetPoint("LEFT", self.tileFirsts, "RIGHT", 12, 0)
    self.since:SetJustifyH("RIGHT")
    singleLine(self.since)

    self.coverage = Theme.Label(strip, "", fonts.small, Theme.color.textFaint)
    self.coverage:SetPoint("TOPRIGHT", self.since, "BOTTOMRIGHT", 0, -3)
    self.coverage:SetPoint("LEFT", self.tileFirsts, "RIGHT", 12, 0)
    self.coverage:SetJustifyH("RIGHT")
    singleLine(self.coverage)

    -- ------------------------------------------------------ Liste -----------
    local panel = Widgets.Panel(frame, L.ACH_TITLE)
    panel:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.panel = panel

    self.rows = Widgets.ScrollList(panel.content, {
        rowHeight = ROW_HEIGHT,
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, entry) self:UpdateRow(row, entry) end,
        onEnterRow = function(row, entry) self:ShowTooltip(row, entry) end,
        onClickRow = function(entry) self:OnClickRow(entry) end,
    })
    self.rows:SetAllPoints(panel.content)

    self.empty = Theme.Label(panel.content, L.ACH_EMPTY, fonts.row, Theme.color.textFaint)
    self.empty:SetPoint("CENTER", panel.content, "CENTER", 0, 0)
    self.empty:Hide()

    self.frame = frame
    return frame
end

function View:BuildRow(row)
    local fonts = Theme.Fonts()

    -- Der goldene Streifen an der Kante. Eine Farbe am Rand liest sich beim
    -- Ueberfliegen schneller als das Wort "gemessen" am anderen Ende.
    row.accent = row:CreateTexture(nil, "BORDER")
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.accent:SetWidth(2)
    Theme.Paint(row.accent, Theme.color.gold)
    row.accent:Hide()

    -- Der goldene Balken der Kopfzeilen: dasselbe Motiv wie ueber einem
    -- Questlog-Abschnitt. Eine eigene Textur statt row.background, weil die
    -- Liste den Hintergrund beim Ueberfahren selbst umfaerbt.
    row.headerBg = Theme.HeaderBar(row)
    row.headerBg:Hide()

    -- Plus und Minus statt eines Pfeils: Diese beiden Zeichen gibt es in
    -- jeder Schrift. Ein Dreieck waere eine Wette auf den Zeichensatz.
    row.toggle = Theme.Label(row, "", fonts.big, Theme.color.gold)
    row.toggle:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.toggle:Hide()

    -- Auswahlrahmen. Eigene Texturen statt einer Hintergrundfarbe: Die Liste
    -- faerbt den Hintergrund beim Ueberfahren selbst um, ein Rahmen bleibt.
    row.selection = Theme.Outline(row, Theme.color.goldBright)
    for _, line in ipairs(row.selection) do line:Hide() end

    -- Symbol im Rahmen, wie ein Ausruestungsplatz im Charakterfenster.
    local holder = CreateFrame("Frame", nil, row)
    holder:SetWidth(ICON_SIZE)
    holder:SetHeight(ICON_SIZE)
    holder:SetPoint("LEFT", row, "LEFT", 7, 0)
    Theme.Fill(holder, Theme.color.sidebarBg)

    row.icon = holder:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints(holder)

    row.iconLines = Theme.Outline(holder, Theme.color.border)
    row.iconHolder = holder

    -- In der Rangliste steht hier der Platz statt eines Symbols.
    row.rank = Theme.Label(holder, "", fonts.body, Theme.color.text)
    row.rank:SetPoint("CENTER", holder, "CENTER", 0, 0)

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_COLUMN + 14), 0)
    row.name:SetJustifyH("LEFT")
    singleLine(row.name)

    row.detail = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -21)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_COLUMN + 14), 0)
    row.detail:SetJustifyH("LEFT")
    singleLine(row.detail)

    -- Der Fortschrittsbalken. Er erscheint NUR, wo wirklich gezaehlt wird —
    -- das ist seine eigentliche Aussage, nicht die Breite.
    row.barTrack = CreateFrame("Frame", nil, row)
    row.barTrack:SetHeight(4)
    row.barTrack:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -34)
    row.barTrack:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_COLUMN + 14), 0)
    Theme.Fill(row.barTrack, Theme.color.sidebarBg)

    row.barFill = row.barTrack:CreateTexture(nil, "ARTWORK")
    Theme.Paint(row.barFill, Theme.color.jadeDim)
    row.barFill:SetPoint("TOPLEFT", row.barTrack, "TOPLEFT", 0, 0)
    row.barFill:SetPoint("BOTTOMLEFT", row.barTrack, "BOTTOMLEFT", 0, 0)
    row.barFill:SetWidth(1)
    row.barTrack:Hide()
    row.barTrack:SetScript("OnSizeChanged", function() applyBar(row) end)

    row.points = Theme.Label(row, "", fonts.big, Theme.color.goldBright)
    row.points:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -4)
    row.points:SetWidth(RIGHT_COLUMN)
    row.points:SetJustifyH("RIGHT")
    singleLine(row.points)

    -- Der Beleg steht in einer EIGENEN Spalte, nicht im Kleingedruckten:
    -- Er ist der Unterschied zwischen einer Messung und einer Behauptung.
    row.evidence = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.evidence:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -24)
    row.evidence:SetWidth(RIGHT_COLUMN)
    row.evidence:SetJustifyH("RIGHT")
    singleLine(row.evidence)

    row.layout = "ENTRY"
end

--- Setzt die Textspalte auf Kopfzeile oder Eintrag um.
---
--- Nur beim Wechsel, nicht bei jeder Zuweisung: Beim Bildlauf laufen zwanzig
--- Zeilen durch, und Anker neu zu setzen ist teurer als sie zu vergleichen.
local function setLayout(row, layout)
    if row.layout == layout then return end
    row.layout = layout

    local header = layout == "HEADER"
    local left = header and HEADER_LEFT or TEXT_LEFT
    local fonts = Theme.Fonts()

    row.name:ClearAllPoints()
    row.detail:ClearAllPoints()
    row.barTrack:ClearAllPoints()

    if header then
        -- Die Kopfzeile hat nur eine Textzeile, dafuer eine groessere.
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", left, -6)
        row.name:SetFontObject(fonts.big)
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", left, -24)
    else
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", left, -5)
        row.name:SetFontObject(fonts.body)
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", left, -21)
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_COLUMN + 14), 0)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_COLUMN + 14), 0)
    row.barTrack:SetPoint("TOPLEFT", row, "TOPLEFT", left, -34)
    row.barTrack:SetPoint("RIGHT", row, "RIGHT", -(RIGHT_COLUMN + 14), 0)
end

-- ================================================================== Zeilen ---

function View:UpdateRow(row, entry)
    -- Zeilen werden ueber alle drei Blicke hinweg wiederverwendet. Was eine
    -- Betriebsart setzt, muss die naechste zuruecknehmen, sonst steht ein
    -- Rest der vorigen Ansicht in der Zeile.
    row.accent:Hide()
    row.barTrack:Hide()
    row.barRatio = nil
    row.rank:SetText("")
    row.icon:Show()
    row.iconHolder:Show()
    row.headerBg:Hide()
    row.toggle:Hide()
    if row.icon.SetDesaturated then pcall(row.icon.SetDesaturated, row.icon, false) end

    local chosen = entry.id ~= nil and entry.id == self.selected and not entry.isHeader
    for _, line in ipairs(row.selection) do
        if chosen then line:Show() else line:Hide() end
    end

    if entry.isHeader then
        self:UpdateHeaderRow(row, entry)
        return
    end
    setLayout(row, "ENTRY")

    if entry.mode == "BOARD" then
        self:UpdateBoardRow(row, entry)
        return
    end

    Symbols:Apply(row.icon, entry)

    local rarity = RARITY_COLOR[entry.rarity] or Theme.color.text
    row.name:SetText(entry.name or entry.id)
    row.points:SetText(tostring(entry.points or ""))

    if entry.mode == "HALL" then
        self:UpdateHallRow(row, entry, rarity)
        return
    end

    self:UpdateOwnRow(row, entry, rarity)
end

--- Die Kopfzeile einer Kategorie: Zeichen, Name, Anzahl, Punkte, Balken.
function View:UpdateHeaderRow(row, entry)
    setLayout(row, "HEADER")

    row.iconHolder:Hide()
    row.headerBg:Show()
    row.toggle:SetText(entry.collapsed and "+" or "-")
    row.toggle:Show()

    Theme.Paint(row.accent, Theme.color.gold)
    row.accent:Show()

    row.name:SetText(categoryName(entry.category) or entry.category)
    setColor(row.name, Theme.color.heading)

    if entry.unlocked == 0 then
        -- "0 von 20" liest sich wie ein Fehler. Es ist aber ein Anfang.
        row.detail:SetText(string.format(L.ACH_CAT_UNTOUCHED, entry.total))
    else
        row.detail:SetText(string.format(L.ACH_CAT_PROGRESS, entry.unlocked, entry.total))
    end
    setColor(row.detail, Theme.color.textDim)

    row.points:SetText(string.format("%d / %d", entry.points, entry.available))
    row.evidence:SetText("")

    -- Der Balken zaehlt PUNKTE, nicht Erfolge: Ein legendaerer First und ein
    -- gewoehnlicher Erfolg sind nicht dasselbe, und die Kopfzeile soll das
    -- nicht einebnen.
    if entry.available > 0 then
        row.barRatio = entry.points / entry.available
        Theme.Paint(row.barFill, Theme.color.goldDim)
        row.barTrack:Show()
        applyBar(row)
    end
end

function View:UpdateBoardRow(row, entry)
    local color = RANK_COLOR[entry.rank] or Theme.color.textDim

    row.icon:Hide()
    row.rank:SetText(tostring(entry.rank or "?"))
    setColor(row.rank, color)
    paintLines(row.iconLines, RANK_COLOR[entry.rank] and color or Theme.color.border)

    if RANK_COLOR[entry.rank] then
        Theme.Paint(row.accent, color)
        row.accent:Show()
    end

    row.name:SetText(entry.name or "?")
    setColor(row.name, Theme.color.text)
    row.detail:SetText(string.format(L.ACH_BOARD_DETAIL, entry.count, entry.firsts))
    setColor(row.detail, Theme.color.textFaint)

    row.points:SetText(tostring(entry.points))
    row.evidence:SetText(entry.granted > 0
        and string.format(L.ACH_GRANTED_HINT, entry.granted) or "")
    setColor(row.evidence, Theme.color.warn)
end

function View:UpdateHallRow(row, entry, rarity)
    setColor(row.name, rarity)
    paintLines(row.iconLines, rarity)
    Theme.Paint(row.accent, rarity)
    row.accent:Show()

    row.detail:SetText(string.format(L.ACH_HALL_DETAIL,
        tostring(entry.holder), Util.TimeAgo(entry.ts)))
    setColor(row.detail, Theme.color.textDim)

    -- Der Zustand ist hier die wichtigste Angabe: Ein gemeldeter First ist
    -- kein bestaetigter, und ein strittiger schon gar nicht.
    local state = L["ACH_STATE_" .. tostring(entry.state)] or entry.state
    if entry.claims and entry.claims > 1 then
        state = state .. string.format(L.ACH_CLAIMS, entry.claims)
    end
    row.evidence:SetText(state)
    setColor(row.evidence, entry.contested and Theme.color.warn
        or (entry.state == "verified" and Theme.color.jade or Theme.color.textDim))
end

function View:UpdateOwnRow(row, entry, rarity)
    if entry.unlocked then
        setColor(row.name, rarity)
        paintLines(row.iconLines, rarity)
        Theme.Paint(row.accent, Theme.color.gold)
        row.accent:Show()

        row.detail:SetText(entry.description .. "  ·  " .. Util.TimeAgo(entry.ts))
        setColor(row.detail, Theme.color.textDim)

        row.evidence:SetText(L["ACH_EV_" .. tostring(entry.evidence)] or "")
        setColor(row.evidence, entry.evidence == "granted"
            and Theme.color.warn or Theme.color.jade)
        return
    end

    -- Noch nicht geschafft: Symbol entfaerbt, Name gedaempft, Rahmen neutral.
    if row.icon.SetDesaturated then pcall(row.icon.SetDesaturated, row.icon, true) end
    setColor(row.name, Theme.color.textDim)
    paintLines(row.iconLines, Theme.color.border)

    row.detail:SetText(entry.description)
    setColor(row.detail, Theme.color.textFaint)

    -- "Noch nicht messbar" ist etwas anderes als "0 von 50". Ein Balken bei
    -- null, der sich nie bewegt, sieht wie ein kaputtes Addon aus — deshalb
    -- steht hier dann gar keiner.
    local progress = entry.progress
    if not progress or not progress.measurable then
        row.evidence:SetText(L.ACH_NOT_MEASURABLE)
        setColor(row.evidence, Theme.color.textFaint)
        return
    end

    if progress.unreachable then
        -- "15 von 18" sieht aus wie drei fehlende Gegenstaende. In Wahrheit
        -- gibt es die Plaetze nicht, und das muss dastehen.
        row.evidence:SetText(string.format(L.ACH_UNREACHABLE, progress.ceiling))
        setColor(row.evidence, Theme.color.warn)
        return
    end

    row.evidence:SetText(string.format("%d / %d", progress.current, progress.target))
    setColor(row.evidence, Theme.color.textDim)

    row.barRatio = progress.target > 0 and (progress.current / progress.target) or 0
    Theme.Paint(row.barFill, Theme.color.jadeDim)
    row.barTrack:Show()
    applyBar(row)
end

-- ================================================================= Tooltip ---

--- Alles, was in der Zeile nicht mehr Platz hat. Der Tooltip ist kein Extra:
--- Die Beschreibung wird in der Zeile gekuerzt, hier steht sie ganz.
function View:ShowTooltip(row, entry)
    -- Eine Kopfzeile sagt schon alles, was sie zu sagen hat.
    if not GameTooltip or not entry or entry.isHeader then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

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
        -- Woher der Erfolg kommt, ist hier keine Fussnote: gemessen und von
        -- Hand eingetragen sind zwei verschiedene Dinge.
        local evidence = L["ACH_EV_" .. tostring(entry.evidence)]
        if evidence then
            local granted = entry.evidence == "granted"
            GameTooltip:AddLine(evidence, granted and 0.85 or 0.37,
                granted and 0.64 or 0.79, granted and 0.25 or 0.63)
        end
        -- EIN EINTRAG OHNE GRUND IST EINE BEHAUPTUNG. Deshalb steht er hier,
        -- und nicht nur in der Datenbank.
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

-- ============================================================== Gruppierung --
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
-- ================================================================== Inhalt ---

function View:Rows()
    local Achievements = GA.Modules.Achievements
    local Rules = GA.Modules.Rules
    -- GetValue, nicht GetText: Ohne Blizzards SearchBoxTemplate liefert
    -- Widgets.SearchBox einen Rahmen um das Eingabefeld, und ein Rahmen hat
    -- kein GetText. Beide Wege koennen GetValue.
    local search = string.lower(self.search and self.search:GetValue() or "")

    local function matches(text)
        return search == "" or string.find(string.lower(tostring(text or "")), search, 1, true)
    end

    if self.mode == "BOARD" then
        local out = {}
        -- Der Platz wird VOR dem Filtern vergeben: Wer nach einem Namen
        -- sucht, will dessen Platz in der Gilde sehen, nicht Platz 1 von 1.
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
            -- Die Kategorie kommt aus dem Katalog: Sie traegt das Symbol.
            local entry = catalog and catalog.ENTRIES[row.id]
            row.category = entry and entry.category
            if matches(row.name) or matches(row.holder)
                or matches(categoryName(row.category))
            then
                row.mode = "HALL"
                out[#out + 1] = row
            end
        end
        return out
    end

    -- Eigene Erfolge: gruppiert. Die Regel dahinter steht in View.Group.
    local list = Achievements:List()
    if Rules then
        for _, row in ipairs(list) do
            if not row.unlocked then row.progress = Rules:Progress(row.id) end
        end
    end

    local order = (GA.Data.Catalog and GA.Data.Catalog.CATEGORIES) or {}

    -- View.Group bekommt die GESCHLOSSENEN: Sie rendert nur, sie entscheidet
    -- nicht. Was voreingestellt zu ist, entscheidet diese Ansicht — hier.
    local shut = {}
    if search == "" then
        -- Wer sucht, will finden, nicht erst aufklappen. Deshalb ist beim
        -- Suchen alles offen, egal was gespeichert ist.
        local open = expanded()
        for _, category in ipairs(order) do
            if not open[category] then shut[category] = true end
        end
    end

    return View.Group(list, order, shut,
        function(row)
            -- Die Kategorie ist durchsuchbar, obwohl sie als Wort nur in der
            -- Kopfzeile steht: "raid" ist der kuerzeste Weg zu einer Gruppe.
            return matches(row.name) or matches(row.description)
                or matches(categoryName(row.category))
        end)
end

-- ================================================================ Bedienung --

function View:OnClickRow(entry)
    if not entry then return end

    if entry.isHeader then
        local open = expanded()
        open[entry.category] = (not open[entry.category]) or nil
        self:Refresh()
        return
    end

    -- Auswahl. Ein zweiter Klick auf dieselbe Zeile hebt sie wieder auf —
    -- sonst bleibt ein Erfolg ausgewaehlt, ohne dass man ihn loswird.
    self.selected = (self.selected ~= entry.id) and entry.id or nil
    self:Refresh()
end

--- Traegt den ausgewaehlten Erfolg fuer jemanden ein.
function View:GrantSelected()
    if not self.selected then
        GA.Core.Debug:Info("%s", L.GRANT_NEED_ROW)
        return
    end
    local ok, reason = GA.UI.GrantDialog:Open(self.selected)
    if not ok then
        GA.Core.Debug:Info("%s",
            L["GRANT_ERR_" .. string.upper(tostring(reason))] or tostring(reason))
    end
end

--- Nimmt einen eingetragenen Erfolg zurueck — beim eigenen Profil.
---
--- Bewusst nur das eigene: Der Dialog waehlt einen Spieler aus, dieser Knopf
--- nicht. Einen fremden Eintrag ueber einen Knopf ohne Namen zu loeschen waere
--- genau die Art Bedienung, bei der man hinterher raet, wen es getroffen hat.
function View:RevokeSelected()
    if not self.selected then
        GA.Core.Debug:Info("%s", L.GRANT_NEED_ROW)
        return
    end

    local Achievements = GA.Modules.Achievements
    local ok, reason = Achievements:Revoke(self.selected, self:PlayerId())
    if ok then
        GA.Core.Debug:Info(L.GRANT_REVOKED,
            tostring((Achievements:Entry(self.selected) or {}).name))
        self:Refresh()
    else
        GA.Core.Debug:Info("%s",
            L["GRANT_ERR_" .. string.upper(tostring(reason))] or tostring(reason))
    end
end

function View:PlayerId()
    local guid = GA.Core.Compat.GetPlayerIdentity().guid
    local profile = guid and GA.Modules.Players:GetProfileFor(guid)
    return profile and profile.id or nil
end

--- Alles auf oder alles zu. Welches von beidem, entscheidet der Bestand:
--- Ist irgendetwas offen, wird zugeklappt — sonst aufgeklappt.
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

function View:OnShow() self:Refresh() end

function View:Refresh()
    for _, button in ipairs(self.modeButtons) do
        button:SetEnabledState(button.mode ~= self.mode)
    end

    local Achievements = GA.Modules.Achievements
    local points = Achievements:Points()

    local rows = self:Rows()
    self.rows:SetData(rows)
    if #rows == 0 then self.empty:Show() else self.empty:Hide() end

    -- Gruppen gibt es nur bei den eigenen Erfolgen (siehe Dateikopf), also
    -- auch den Knopf nur dort.
    if self.mode == "OWN" then
        local open = expanded()
        local order = (GA.Data.Catalog and GA.Data.Catalog.CATEGORIES) or {}
        local anyOpen = false
        for _, category in ipairs(order) do
            if open[category] then anyOpen = true break end
        end
        -- SetLabel, nicht SetText: Der Rueckfallknopf traegt seine Beschriftung
        -- als eigene Fontstring, und SetText gibt es dort gar nicht.
        self.toggleAll:SetLabel(anyOpen and L.ACH_COLLAPSE_ALL or L.ACH_EXPAND_ALL)
        self.toggleAll:Show()
    else
        self.toggleAll:Hide()
    end

    -- Eintragen gibt es nur, wo Zeilen Erfolge sind. In der Rangliste stehen
    -- Spieler, und einen Spieler kann man nicht eintragen.
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

    if self.mode == "BOARD" then
        self.panel:SetTitle(L.ACH_MODE_BOARD)
    elseif self.mode == "HALL" then
        self.panel:SetTitle(L.ACH_HALL)
    else
        self.panel:SetTitle(L.ACH_TITLE)
    end

    self.tilePoints:Set(points.total)
    self.tileDone:Set(string.format("%d / %d", points.count, points.available))
    self.tileFirsts:Set(points.firsts)

    -- Abdeckung und Startzeitpunkt: Beide sagen, worueber die Zahlen links
    -- ueberhaupt eine Aussage machen. Von Hand eingetragene Punkte stehen
    -- dabei, weil sie den Punktestand tragen, ohne gemessen zu sein.
    local since = GA.Core.Database.account.achievementsSince
    local head = since and string.format(L.ACH_SINCE, Util.TimeAgo(since)) or ""
    if points.granted > 0 then
        head = head .. "  " .. string.format(L.ACH_GRANTED_HINT, points.granted)
    end
    self.since:SetText(head)

    local coverage = GA.Modules.Rules and GA.Modules.Rules:Coverage()
    self.coverage:SetText(coverage
        and string.format(L.ACH_COVERAGE, coverage.measurable, coverage.catalog) or "")

    GA.UI.MainFrame:SetContext(string.format("%d", points.total))
end

-- Ein Eintrag geschieht in einem Dialog DAVOR. Ohne diese Zeilen bliebe die
-- Liste darunter stehen, wie sie war — und der Eintrag saehe aus, als waere
-- er nicht angekommen.
for _, event in ipairs({ "ACHIEVEMENT_UNLOCKED", "ACHIEVEMENT_CHANGED",
                         "ACHIEVEMENT_CONTESTED" }) do
    GA.Core.Callbacks:On(event, function()
        if View.frame and View.frame:IsVisible() then View:Refresh() end
    end, "AchievementsView")
end

GA.UI.MainFrame:RegisterView("achievements", View)
