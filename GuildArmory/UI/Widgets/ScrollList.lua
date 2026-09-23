--[[----------------------------------------------------------------------------
    Widgets/ScrollList — Tabelle mit wiederverwendeten Zeilen.

    Das ist die Stelle, an der die Leistungsvorgabe aus der Spezifikation haengt
    ("Tabellen wiederverwenden", "keine komplette UI bei jedem Event neu rendern").

    Prinzip: Es werden nur so viele Zeilen-Frames erzeugt, wie sichtbar sind
    (bei 620 Punkten Fensterhoehe etwa 20 Stueck) — unabhaengig davon, ob die Liste
    5 oder 40 Eintraege hat. Gescrollt wird nicht das Frame, sondern der Index:
    Jede Zeile bekommt einen anderen Datensatz zugewiesen.

    Der Unterschied ist nicht akademisch. Ein 40er-Roster, der bei jedem
    GROUP_ROSTER_UPDATE 40 Frames neu erzeugt, erzeugt in einem Raidabend
    zehntausende Frames, die nie wieder freigegeben werden — WoW gibt Frames nicht
    an das Betriebssystem zurueck.

    Bewusst ohne Blizzard-Vorlagen (FauxScrollFrame, UIPanelScrollFrameTemplate):
    Die Zielplattform steht noch nicht fest, und eine fehlende Vorlage wuerde beim
    Erzeugen werfen.
------------------------------------------------------------------------------]]

local _, GA = ...

local Widgets = GA.UI.Widgets or {}
GA.UI.Widgets = Widgets

local Theme = GA.UI.Theme

local SCROLLBAR_WIDTH = 6

--- @param parent Frame
--- @param options table
---   rowHeight  number
---   columns    table|nil   { { label = "Name", width = 120, justify = "LEFT" }, ... }
---   createRow  function(row, columns)  einmalig je Zeilen-Frame
---   updateRow  function(row, item, index)  bei jeder Zuweisung
---   onClickRow function(item, index, button)|nil
function Widgets.ScrollList(parent, options)
    local fonts = Theme.Fonts()

    local list = CreateFrame("Frame", nil, parent)
    Theme.Outline(list, Theme.color.border)

    list.rowHeight = options.rowHeight or Theme.size.rowHeight
    list.columns = options.columns
    list.createRow = options.createRow
    list.updateRow = options.updateRow
    list.onClickRow = options.onClickRow
    list.data = {}
    list.offset = 0
    list.rows = {}

    -- ------------------------------------------------------------ Kopfzeile --

    local headerHeight = 0
    if list.columns then
        headerHeight = 19
        local header = CreateFrame("Frame", nil, list)
        header:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
        header:SetHeight(headerHeight)
        Theme.Fill(header, Theme.color.panelBg)
        Theme.Edge(header, "BOTTOM", Theme.color.border)

        local x = 8
        for _, column in ipairs(list.columns) do
            local label = Theme.Label(header, string.upper(column.label or ""),
                fonts.heading, Theme.color.heading)
            label:SetPoint("LEFT", header, "LEFT", x, 0)
            if column.width then
                label:SetWidth(column.width)
                label:SetJustifyH(column.justify or "LEFT")
                x = x + column.width + 6
            end
        end
        list.header = header
    end

    -- --------------------------------------------------------- Zeilenbereich -

    local body = CreateFrame("Frame", nil, list)
    body:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -headerHeight)
    body:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -SCROLLBAR_WIDTH, 0)
    list.body = body

    -- ------------------------------------------------------------ Bildlauf ---

    local track = CreateFrame("Frame", nil, list)
    track:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -headerHeight)
    track:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    track:SetWidth(SCROLLBAR_WIDTH)
    Theme.Fill(track, Theme.color.rowAltBg)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)

    -- Der Rueckgabewert wird GEBRAUCHT: Theme.Fill legt eine Textur AUF den
    -- Knopf und gibt sie zurueck. Wer ihn wegwirft und spaeter den Knopf
    -- selbst bemalt, ruft SetColorTexture auf einem Frame auf — und das gibt
    -- es dort nicht. Gemessen 21.09.2026, als jemand zum ersten Mal am
    -- Bildlaufbalken zog.
    local thumbFill = Theme.Fill(thumb, Theme.color.goldDeep)
    thumb:Hide()

    list.track = track
    list.thumb = thumb

    -- ---------------------------------------------------------------- Logik --

    --- Wie viele Zeilen passen aktuell in den Bereich?
    local function visibleCount()
        local height = body:GetHeight()
        if not height or height <= 0 then return 0 end
        return math.floor(height / list.rowHeight)
    end

    --- Erzeugt fehlende Zeilen-Frames. Wird nur groesser, nie kleiner:
    --- ueberzaehlige Zeilen werden versteckt statt zerstoert.
    ---
    --- DIESE FELDNAMEN GEHOEREN ScrollList UND KEINER ANSICHT:
    ---
    ---     row.item        der Datensatz der Zeile
    ---     row.dataIndex   seine Stelle in den Daten
    ---     row.background  die Hintergrundflaeche
    ---     row.index       die Nummer der Zeile im Fenster
    ---     row.cells       die Spalten einer Tabellenzeile
    ---
    --- row.item und row.dataIndex werden VOR JEDEM updateRow neu gesetzt.
    --- Wer in createRow eine Anzeige darunter ablegt, verliert sie beim
    --- ersten Datensatz — und der Fehler erscheint dann in der Ansicht,
    --- nicht hier. Genau so ist die Tradables-Liste gestolpert.
    ---
    --- Bewacht von tools/test/rowfields.test.js, das diese Liste aus dem
    --- Quelltext hier liest statt sie nachzupflegen.
    local function ensureRows(count)
        for index = #list.rows + 1, count do
            local row = CreateFrame("Button", nil, body)
            row:SetHeight(list.rowHeight)
            row:SetPoint("LEFT", body, "LEFT", 0, 0)
            row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            row:SetPoint("TOP", body, "TOP", 0, -(index - 1) * list.rowHeight)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            row.background = Theme.Fill(row, Theme.color.rowBg)
            row.index = index

            row:SetScript("OnEnter", function(self)
                Theme.Paint(self.background, Theme.color.rowHover)
                if self.item and options.onEnterRow then options.onEnterRow(self, self.item) end
            end)
            row:SetScript("OnLeave", function(self)
                Theme.Paint(self.background,
                    (self.dataIndex or 0) % 2 == 1 and Theme.color.rowAltBg or Theme.color.rowBg)
                if options.onLeaveRow then options.onLeaveRow(self) end
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(self, button)
                if list.onClickRow and self.item then
                    list.onClickRow(self.item, self.dataIndex, button)
                end
            end)

            if list.createRow then
                list.createRow(row, list.columns)
            end

            list.rows[index] = row
        end
    end

    --- Weist den sichtbaren Zeilen ihre Datensaetze zu.
    function list:Update()
        local count = visibleCount()
        if count <= 0 then return end

        ensureRows(count)

        local total = #self.data
        local maxOffset = math.max(0, total - count)
        if self.offset > maxOffset then self.offset = maxOffset end
        if self.offset < 0 then self.offset = 0 end

        for index = 1, #self.rows do
            local row = self.rows[index]

            if index > count then
                row:Hide()
            else
                local dataIndex = index + self.offset
                local item = self.data[dataIndex]

                if item then
                    row.item = item
                    row.dataIndex = dataIndex
                    Theme.Paint(row.background,
                        dataIndex % 2 == 1 and Theme.color.rowAltBg or Theme.color.rowBg)
                    if self.updateRow then self.updateRow(row, item, dataIndex) end
                    row:Show()
                else
                    row.item = nil
                    row.dataIndex = nil
                    row:Hide()
                end
            end
        end

        -- Bildlaufanzeige
        if total > count then
            local trackHeight = track:GetHeight()
            local ratio = count / total
            local thumbHeight = math.max(16, trackHeight * ratio)
            local travel = trackHeight - thumbHeight
            local progress = maxOffset > 0 and (self.offset / maxOffset) or 0

            thumb:SetHeight(thumbHeight)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -travel * progress)
            thumb:Show()
        else
            thumb:Hide()
        end
    end

    function list:SetData(data)
        self.data = data or {}
        self.offset = 0
        self:Update()
    end

    function list:Scroll(delta)
        local count = visibleCount()
        local maxOffset = math.max(0, #self.data - count)
        self.offset = math.max(0, math.min(maxOffset, self.offset - delta))
        self:Update()
    end

    -- -------------------------------------------------------- Eingabe -------

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self:Scroll(delta * 3)
    end)

    list:SetScript("OnSizeChanged", function(self)
        self:Update()
    end)

    -- Ziehen der Bildlaufanzeige. Bewusst ueber OnUpdate statt OnDragStart:
    -- Der Balken ist schmal, und das Ziehen soll auch dann weiterlaufen, wenn
    -- der Mauszeiger ihn seitlich verlaesst.
    local dragging, dragStartY, dragStartOffset = false, 0, 0

    thumb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    thumb:SetScript("OnMouseDown", function()
        dragging = true
        local _, y = GetCursorPosition()
        dragStartY = y
        dragStartOffset = list.offset
        Theme.Paint(thumbFill, Theme.color.goldDim)
    end)
    thumb:SetScript("OnMouseUp", function()
        dragging = false
        Theme.Paint(thumbFill, Theme.color.goldDeep)
    end)

    thumb:SetScript("OnUpdate", function()
        if not dragging then return end
        if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") then
            dragging = false
            Theme.Paint(thumbFill, Theme.color.goldDeep)
            return
        end

        local count = visibleCount()
        local maxOffset = math.max(0, #list.data - count)
        if maxOffset == 0 then return end

        local _, y = GetCursorPosition()
        local scale = list:GetEffectiveScale()
        local moved = (dragStartY - y) / (scale > 0 and scale or 1)

        local trackHeight = track:GetHeight()
        local perRow = trackHeight / math.max(1, #list.data)
        local steps = perRow > 0 and math.floor(moved / perRow + 0.5) or 0

        local target = math.max(0, math.min(maxOffset, dragStartOffset + steps))
        if target ~= list.offset then
            list.offset = target
            list:Update()
        end
    end)

    return list
end

--- Hilfsmittel fuer createRow: legt Textfelder gemaess Spaltendefinition an.
--- Die Felder landen in row.cells und werden in updateRow nur noch beschriftet.
function Widgets.BuildCells(row, columns, fontObject)
    local fonts = Theme.Fonts()
    row.cells = {}

    local x = 8
    for index, column in ipairs(columns) do
        local cell = Theme.Label(row, "", fontObject or fonts.row, Theme.color.text)
        cell:SetPoint("LEFT", row, "LEFT", x, 0)

        -- WO DIESE ZELLE ANFAENGT, ZUM NACHSCHLAGEN.
        --
        -- Eine Ansicht, die vor den Text noch ein Symbol setzen will,
        -- braucht diesen Abstand. Ohne ihn haengt sie das Symbol an die
        -- Zelle und die Zelle an das Symbol — ein Ring, den WoW mit
        -- "Cannot anchor to a region dependent on it" ablehnt. Genau so
        -- ist die Loot-Historie gestolpert.
        cell.leftInset = x
        cell.fills = not column.width

        if column.width then
            cell:SetWidth(column.width)
            cell:SetJustifyH(column.justify or "LEFT")
            x = x + column.width + 6
        else
            -- Spalte ohne Breite fuellt den Rest bis zur naechsten festen Spalte.
            cell:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            cell:SetJustifyH(column.justify or "LEFT")
        end

        row.cells[index] = cell
        row.cells[column.key or index] = cell
    end

    return row.cells
end
