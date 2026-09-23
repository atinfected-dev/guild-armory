--[[----------------------------------------------------------------------------
    Widgets/Frame — Flaechen, Panels, Trennlinien.

    Diese Ebene existiert, damit acht Views nicht acht Mal dieselbe Panelkonstruktion
    neu erfinden (Architekturregel: UI-Widgets als eigene Schicht). Alles hier ist
    dumm: Es zeichnet, es weiss nichts ueber Roster, Zuweisungen oder Datenbank.

    Flaechen kommen aus Blizzards InsetFrameTemplate, wenn es traegt (Theme.CreateNative);
    sonst Backdrop und 1px-Linien — siehe Kopf von UI/Theme.lua.
------------------------------------------------------------------------------]]

local _, GA = ...

local Widgets = GA.UI.Widgets or {}
GA.UI.Widgets = Widgets

local Theme = GA.UI.Theme

-- ------------------------------------------------------------------ Inset ----

--- Eingelassene dunkle Flaeche mit Blizzards Innenrahmen (InsetFrameTemplate):
--- der Grund der Questliste im Screenshot, des Charakterfensters, des Rosters.
--- Rueckfall: Tooltip-Rahmen per Backdrop, danach 1px-Linien.
--- @return Frame inset  mit .native (true, wenn die Blizzard-Vorlage traegt)
function Widgets.Inset(parent, name)
    local inset = Theme.CreateNative("Frame", name, parent, "InsetFrameTemplate")
    if inset then
        inset.native = true
        return inset
    end

    inset = Theme.CreateBackdropFrame(name, parent)
    inset.native = false
    if not Theme.Backdrop(inset, "panel", Theme.color.panelBg, Theme.color.goldDeep) then
        Theme.Outline(inset, Theme.color.border)
    end
    return inset
end

-- ------------------------------------------------------------------ Panel ----

--- Ein Panel: Abschnittskopf wie im Questlog (goldener Balken, goldene
--- Kapitalis) und darunter eine eingelassene Flaeche fuer den Inhalt.
--- @param parent Frame
--- @param title string|nil   ohne Titel: nur die eingelassene Flaeche
--- @param tag string|nil     kleiner Hinweis rechts im Kopf ("live", "Phase 4")
--- @return Frame panel  mit .content (innerhalb der Flaeche, mit Rand),
---                      .inset, .heading, .tag
function Widgets.Panel(parent, title, tag)
    local panel = CreateFrame("Frame", nil, parent)
    local fonts = Theme.Fonts()
    local headerHeight = title and 24 or 0

    if title then
        local header = CreateFrame("Frame", nil, panel)
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
        header:SetHeight(headerHeight)
        Theme.HeaderBar(header)

        local heading = Theme.Label(header, title, fonts.nav, Theme.color.heading)
        heading:SetPoint("LEFT", header, "LEFT", 8, 0)
        if heading.SetShadowOffset then heading:SetShadowOffset(1, -1) end
        panel.heading = heading
        panel.header = header

        if tag then
            local tagLabel = Theme.Label(header, tag, fonts.small, Theme.color.textDim)
            tagLabel:SetPoint("RIGHT", header, "RIGHT", -8, 0)
            panel.tag = tagLabel
        end
    end

    local inset = Widgets.Inset(panel)
    inset:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -headerHeight)
    inset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.inset = inset

    local padding = 8
    local content = CreateFrame("Frame", nil, inset)
    content:SetPoint("TOPLEFT", inset, "TOPLEFT", padding, -padding)
    content:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -padding, padding)
    panel.content = content

    function panel:SetTitle(text)
        if self.heading then self.heading:SetText(text or "") end
    end

    return panel
end

-- ------------------------------------------------------------ Beschriftung ---

--- Zeile aus Beschriftung links und Wert rechts. Haeufigstes Muster im Dashboard.
function Widgets.KeyValue(parent, key, value)
    local fonts = Theme.Fonts()

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(16)

    row.key = Theme.Label(row, key, fonts.row, Theme.color.textDim)
    row.key:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.value = Theme.Label(row, value or "", fonts.row, Theme.color.text)
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    function row:SetValue(text, color)
        self.value:SetText(text or "")
        local c = color or Theme.color.text
        self.value:SetTextColor(c[1], c[2], c[3])
    end

    return row
end

--- Grosse Zahl mit kleinem Zusatz, z.B. "38 / 40".
function Widgets.BigNumber(parent)
    local fonts = Theme.Fonts()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(26)

    local main = Theme.Label(frame, "", fonts.number, Theme.color.goldBright)
    main:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    local suffix = Theme.Label(frame, "", fonts.row, Theme.color.textDim)
    suffix:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", 3, 2)

    function frame:Set(value, extra)
        main:SetText(tostring(value))
        suffix:SetText(extra or "")
    end

    return frame
end

--- Waagerechter Balken mit Beschriftung und Zahl — Rollenverteilung.
function Widgets.BarRow(parent, label, color)
    local fonts = Theme.Fonts()

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(14)

    local name = Theme.Label(row, label, fonts.row, Theme.color.textDim)
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetWidth(54)
    name:SetJustifyH("LEFT")

    local count = Theme.Label(row, "0", fonts.row, Theme.color.text)
    count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    count:SetWidth(26)
    count:SetJustifyH("RIGHT")

    local track = CreateFrame("Frame", nil, row)
    track:SetPoint("LEFT", name, "RIGHT", 6, 0)
    track:SetPoint("RIGHT", count, "LEFT", -6, 0)
    track:SetHeight(5)
    Theme.Fill(track, Theme.color.rowAltBg)

    local fill = track:CreateTexture(nil, "ARTWORK")
    Theme.Paint(fill, color or Theme.color.gold)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)

    --- @param value number
    --- @param total number
    function row:Set(value, total)
        count:SetText(tostring(value))
        local width = track:GetWidth()
        if not width or width <= 0 then width = 100 end
        local ratio = (total and total > 0) and (value / total) or 0
        fill:SetWidth(math.max(1, width * ratio))
    end

    return row
end

-- --------------------------------------------------------------- Abzeichen ---

--- Kleines Zustandsabzeichen: umrandeter Text in Zustandsfarbe.
--- @param state string "good" | "warn" | "bad" | "unknown"
function Widgets.Badge(parent, text, state)
    local fonts = Theme.Fonts()

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(14)

    local label = Theme.Label(badge, text or "", fonts.small, Theme.StateColor(state))
    label:SetPoint("CENTER", badge, "CENTER", 0, 0)

    badge.background = Theme.Fill(badge, Theme.color.rowAltBg)
    badge.lines = Theme.Outline(badge, Theme.StateColor(state))
    badge.label = label

    function badge:Set(newText, newState)
        label:SetText(newText or "")
        local color = Theme.StateColor(newState)
        label:SetTextColor(color[1], color[2], color[3])
        for _, line in ipairs(self.lines) do
            Theme.Paint(line, color)
        end
        self:SetWidth(label:GetStringWidth() + 12)
    end

    badge:Set(text, state)
    return badge
end

-- ------------------------------------------------------------ Leerzustand ----

--- Mittig gesetzter Hinweis fuer Ansichten, die es noch nicht gibt oder die
--- gerade keine Daten haben. Bewusst ausformuliert statt "keine Daten".
function Widgets.Placeholder(parent, phase, title, body)
    local fonts = Theme.Fonts()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    local phaseLabel = Theme.Label(frame, string.upper(phase or ""), fonts.small, Theme.color.goldDim)
    phaseLabel:SetPoint("CENTER", frame, "CENTER", 0, 46)

    local titleLabel = Theme.Label(frame, string.upper(title or ""), fonts.title, Theme.color.goldBright)
    titleLabel:SetPoint("CENTER", frame, "CENTER", 0, 22)

    local bodyLabel = Theme.Label(frame, body or "", fonts.row, Theme.color.textDim)
    bodyLabel:SetPoint("TOP", titleLabel, "BOTTOM", 0, -12)
    bodyLabel:SetWidth(math.min(420, parent:GetWidth() > 0 and parent:GetWidth() - 60 or 420))
    bodyLabel:SetJustifyH("CENTER")
    bodyLabel:SetSpacing(3)

    frame.title = titleLabel
    frame.body = bodyLabel
    return frame
end

-- --------------------------------------------------------- Itemlevel-Verlauf

--- Balkendiagramm fuer eine Reihe von Messpunkten.
---
--- BEWUSST BALKEN, KEINE LINIE. Ein Ausruestungsstand ist ein Ereignis, kein
--- Messwert einer laufenden Reihe: Zwischen zwei Staenden ist nichts passiert,
--- was das Addon wuesste. Eine Linie wuerde dazwischen interpolieren und damit
--- etwas behaupten, das niemand gemessen hat.
---
--- Gezeichnet wird mit Texturen — CreateLine gibt es in dieser Client-Linie
--- vielleicht, aber Texturen funktionieren nachweislich.
---
--- @param maxBars number  Wie viele Balken hoechstens (aelteste fallen weg)
function Widgets.LevelChart(parent, maxBars)
    local fonts = Theme.Fonts()
    maxBars = maxBars or 24

    local chart = CreateFrame("Frame", nil, parent)
    chart.bars = {}
    chart.maxBars = maxBars

    local plot = CreateFrame("Frame", nil, chart)
    plot:SetPoint("TOPLEFT", chart, "TOPLEFT", 34, -2)
    plot:SetPoint("BOTTOMRIGHT", chart, "BOTTOMRIGHT", -2, 14)
    chart.plot = plot

    -- Grundlinie und Deckel: zwei duenne Linien, damit die Balken einen Bezug
    -- haben und nicht im Nichts stehen.
    local base = plot:CreateTexture(nil, "BORDER")
    Theme.Paint(base, Theme.color.border)
    base:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 0)
    base:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, 0)
    base:SetHeight(1)

    local top = plot:CreateTexture(nil, "BORDER")
    Theme.Paint(top, Theme.color.divider)
    top:SetPoint("TOPLEFT", plot, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", plot, "TOPRIGHT", 0, 0)
    top:SetHeight(1)

    chart.maxLabel = Theme.Label(chart, "", fonts.small, Theme.color.textFaint)
    chart.maxLabel:SetPoint("TOPLEFT", chart, "TOPLEFT", 0, -2)
    chart.maxLabel:SetWidth(30)
    chart.maxLabel:SetJustifyH("RIGHT")

    chart.minLabel = Theme.Label(chart, "", fonts.small, Theme.color.textFaint)
    chart.minLabel:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 0, 14)
    chart.minLabel:SetWidth(30)
    chart.minLabel:SetJustifyH("RIGHT")

    chart.fromLabel = Theme.Label(chart, "", fonts.small, Theme.color.textFaint)
    chart.fromLabel:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, -13)

    chart.toLabel = Theme.Label(chart, "", fonts.small, Theme.color.textFaint)
    chart.toLabel:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, -13)

    chart.empty = Theme.Label(chart, "", fonts.small, Theme.color.textFaint)
    chart.empty:SetPoint("CENTER", plot, "CENTER", 0, 0)
    chart.empty:Hide()

    --- @param points table Liste von { ts, value }, aelteste zuerst
    --- @param emptyText string|nil
    function chart:SetPoints(points, emptyText)
        points = points or {}

        -- Nur die letzten maxBars zeigen.
        local first = math.max(1, #points - self.maxBars + 1)

        local min, max
        for index = first, #points do
            local value = tonumber(points[index].value)
            if value then
                if not min or value < min then min = value end
                if not max or value > max then max = value end
            end
        end

        local count = #points - first + 1
        if count <= 0 or not min then
            for _, bar in ipairs(self.bars) do bar:Hide() end
            self.empty:SetText(emptyText or "")
            self.empty:Show()
            self.minLabel:SetText("")
            self.maxLabel:SetText("")
            self.fromLabel:SetText("")
            self.toLabel:SetText("")
            return
        end
        self.empty:Hide()

        -- Spanne nie null: Sonst haetten gleiche Werte keine Hoehe.
        local span = max - min
        if span <= 0 then span = math.max(1, max * 0.1) min = max - span end

        local width = self.plot:GetWidth()
        if not width or width <= 0 then width = 200 end
        local height = self.plot:GetHeight()
        if not height or height <= 0 then height = 60 end

        local slot = width / count
        local barWidth = math.max(2, math.floor(slot) - 2)

        for index = 1, count do
            local point = points[first + index - 1]
            local bar = self.bars[index]
            if not bar then
                bar = self.plot:CreateTexture(nil, "ARTWORK")
                bar:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", 0, 1)
                self.bars[index] = bar
            end

            local value = tonumber(point.value) or min
            local ratio = (value - min) / span
            -- Mindesthoehe, damit der kleinste Wert nicht unsichtbar ist.
            local barHeight = math.max(2, (height - 2) * (0.12 + ratio * 0.88))

            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT",
                (index - 1) * slot + 1, 1)
            bar:SetWidth(barWidth)
            bar:SetHeight(barHeight)
            -- Der letzte Stand ist der aktuelle: hell. Alles davor gedaempft.
            Theme.Paint(bar, index == count and Theme.color.gold or Theme.color.goldDeep)
            bar:Show()
        end

        for index = count + 1, #self.bars do self.bars[index]:Hide() end

        local function short(value)
            if math.floor(value) == value then return tostring(value) end
            return string.format("%.1f", value)
        end
        self.maxLabel:SetText(short(max))
        self.minLabel:SetText(short(min))
        self.fromLabel:SetText(GA.Core.Util.TimeAgo(points[first].ts))
        self.toLabel:SetText(GA.Core.Util.TimeAgo(points[#points].ts))
    end

    return chart
end

--- Ein Bereich, der bildlaeuft, wenn sein Inhalt hoeher ist als der Platz.
---
--- WOZU:
---
---   Die Einstellungen sind eine Kette fester Bloecke in einer Spalte mit
---   fester Hoehe. Solange beides zusammenpasst, sieht man das Problem nicht —
---   und dann kommt eine Einstellung dazu, und der letzte Block laeuft unten
---   aus dem Fenster (gemessen 20.09.2026, Screenshot). Das ist kein Fehler
---   einer bestimmten Zeile, sondern eine Eigenschaft des Aufbaus.
---
---   Ein Bildlaufbereich macht die Frage gegenstandslos: Der Inhalt darf
---   beliebig hoch werden.
---
--- Bewusst ohne Blizzard-Vorlage (UIPanelScrollFrameTemplate): ScrollFrame,
--- ein Kind und ein Mausrad sind Grundfunktionen und brauchen keine Vorlage,
--- die auf Forever erst gemessen werden muesste.
---
--- @return table scroll  mit `.content` (Hoehe selbst setzen) und `:Refresh()`
function Widgets.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetHeight(1)
    -- Breite sofort setzen: Bloecke, die ihre Breite vom Inhalt ableiten,
    -- waeren sonst bis zum ersten Refresh null Pixel breit.
    content:SetWidth(parent:GetWidth() or 300)
    scroll:SetScrollChild(content)
    scroll.content = content

    -- Schmale Anzeige am rechten Rand, nur sichtbar, wenn es etwas zu rollen
    -- gibt. Kein Ziehen: Das Mausrad genuegt fuer eine Spalte Einstellungen,
    -- und ein Balken, den man treffen muss, kostet mehr als er bringt.
    -- OVERLAY, nicht BACKGROUND: Der Inhalt ist ein eigenes Kindfenster und
    -- liegt ueber allem, was auf dem ScrollFrame selbst gezeichnet wird.
    local track = Theme.Fill(scroll, Theme.color.border, "OVERLAY")
    track:ClearAllPoints()
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    track:SetWidth(2)
    track:Hide()

    local thumb = Theme.Fill(scroll, Theme.color.goldDeep, "OVERLAY")
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    thumb:SetWidth(2)
    thumb:Hide()

    --- Nach einer Aenderung an Inhalt oder Groesse aufrufen.
    function scroll:Refresh()
        local visible = self:GetHeight() or 0
        local total = content:GetHeight() or 0
        content:SetWidth(self:GetWidth() or 0)

        local overflow = math.max(0, total - visible)
        if overflow <= 0 then
            self:SetVerticalScroll(0)
            track:Hide() thumb:Hide()
            return
        end

        -- Ein Fenster, das kleiner gezogen wird, darf nicht mit einer
        -- Bildlaufposition zurueckbleiben, die es nicht mehr gibt.
        local current = math.min(self:GetVerticalScroll() or 0, overflow)
        self:SetVerticalScroll(current)

        track:Show()
        local height = math.max(20, visible * (visible / total))
        thumb:SetHeight(height)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0,
            -((visible - height) * (current / overflow)))
        thumb:Show()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local overflow = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        if overflow <= 0 then return end
        self:SetVerticalScroll(
            math.max(0, math.min(overflow, (self:GetVerticalScroll() or 0) - delta * 24)))
        self:Refresh()
    end)

    scroll:SetScript("OnSizeChanged", function(self) self:Refresh() end)

    return scroll
end

-- ------------------------------------------------------- Gegenstands-Tooltip -

--- Zeigt den Tooltip eines Gegenstands an einem Rahmen.
---
--- DIE ID GENUEGT, DER LINK IST DIE KUER.
---
--- Dasselbe stand vorher an fuenf Stellen, und alle fuenf haengten am
--- LINK: "if award.itemLink then ...". Den gibt es aber nur, wenn dieser
--- Client den Gegenstand schon einmal gesehen hat. Bei einem fremden
--- Angebot, einer alten Vergabe aus dem Abgleich oder einem Probelauf ist
--- er nicht da — und dann erschien gar kein Tooltip, was wie ein defektes
--- Fenster aussieht.
---
--- Drei Wege, in dieser Reihenfolge:
---
---   1. Der LINK, wenn es ihn gibt. Nur er traegt Zufallssuffix und
---      Verzauberung, also das, was dieses eine Stueck ausmacht.
---   2. SetItemByID. Braucht nur die Zahl und stoesst beim Server die
---      Abfrage an; solange die laeuft, steht "Retrieving item
---      information" da. Das ist richtig so und besser als nichts.
---   3. "item:<id>" als Kurzform, falls es SetItemByID nicht gibt.
---
--- @return boolean ob etwas angezeigt wird
function Widgets.ShowItemTooltip(owner, itemID, link)
    if not owner or not _G.GameTooltip then return false end
    if not itemID and not link then return false end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

    if link and pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
        GameTooltip:Show()
        return true
    end

    if itemID and type(GameTooltip.SetItemByID) == "function"
        and pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    then
        GameTooltip:Show()
        return true
    end

    if itemID and pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. itemID) then
        GameTooltip:Show()
        return true
    end

    -- Nichts anzuzeigen heisst: nichts stehen lassen. Ein Tooltip, der vom
    -- vorigen Eintrag uebrig ist, gehoert zum falschen Gegenstand.
    GameTooltip:Hide()
    return false
end

--- Blendet den Gegenstands-Tooltip wieder aus.
function Widgets.HideItemTooltip()
    if _G.GameTooltip then GameTooltip:Hide() end
end

-- ------------------------------------------------------------ Messende Spalte -

--- Stapelt Elemente untereinander und MISST dabei jede Hoehe.
---
--- WARUM GEMESSEN UND NICHT GESETZT.
---
--- Eine feste Hoehe fuer umbrechenden Text ist immer eine Wette auf
--- Sprache, Schriftgroesse und Fensterbreite. In den Einstellungen ist
--- diese Wette verloren gegangen: Die englische Combat-Log-Erklaerung
--- brauchte fuenf Zeilen statt der eingeplanten drei, und der Rest landete
--- im Kaestchen darunter.
---
--- Jede Erklaerung sagt ueber GetStringHeight selbst, wie hoch sie ist.
--- Was nicht hineinpasst, schiebt den Rest nach unten, statt ihn zu
--- ueberdecken.
---
--- OHNE BEKANNTE BREITE WIRD NICHTS GESETZT: Ein auf Breite 0 gerechneter
--- Umbruch ergibt eine sinnlose Hoehe, und die stuende dann fest.
--- @return table|nil stapel
function Widgets.Stack(content, options)
    options = options or {}
    local breite = content and content:GetWidth() or 0
    if breite <= 1 then return nil end

    local stapel = { y = 0, breite = breite, content = content }

    --- Ein Element mit eigener Hoehe: Kaestchen, Knopf, Zeile.
    function stapel:Add(frame, einzug, abstand)
        self.y = self.y - (abstand or 0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", einzug or 0, self.y)
        self.y = self.y - (frame:GetHeight() or 0)
        return frame
    end

    --- Eine Beschriftung, die umbrechen darf.
    function stapel:Text(label, einzug, abstand)
        einzug = einzug or 0
        self.y = self.y - (abstand or 0)
        label:SetWidth(self.breite - einzug)
        label:SetJustifyH("LEFT")
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", self.content, "TOPLEFT", einzug, self.y)

        -- GetStringHeight ist die Hoehe des UMGEBROCHENEN Textes. GetHeight
        -- waere die gesetzte — und die zu lesen, nachdem man sie selbst
        -- gesetzt hat, beweist nichts.
        local hoehe = label:GetStringHeight() or 0
        if hoehe <= 0 then hoehe = 12 end
        label:SetHeight(hoehe)
        self.y = self.y - hoehe
        return label
    end

    --- Mehrere Elemente nebeneinander, gleichmaessig verteilt.
    function stapel:Row(frames, einzug, abstand)
        einzug = einzug or 0
        self.y = self.y - (abstand or 0)
        local luecke = 4
        local anzahl = #frames
        if anzahl == 0 then return end

        local je = math.floor((self.breite - einzug - (anzahl - 1) * luecke) / anzahl)
        local hoehe = 0
        for index, frame in ipairs(frames) do
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", self.content, "TOPLEFT",
                einzug + (index - 1) * (je + luecke), self.y)
            if frame.SetWidth then frame:SetWidth(je) end
            hoehe = math.max(hoehe, frame:GetHeight() or 0)
        end
        self.y = self.y - hoehe
    end

    --- Wie hoch der Inhalt geworden ist.
    function stapel:Height()
        return -self.y
    end

    return stapel
end
