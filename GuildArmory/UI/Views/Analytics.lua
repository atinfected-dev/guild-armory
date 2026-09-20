--[[----------------------------------------------------------------------------
    Views/Analytics — wer hat was bekommen, woher kam es, wie gut ist es belegt.

    Oben der Zeitraum und die Eckdaten, links die Gruppierung (Spieler,
    Charakter, Herkunft, Antwort, Qualitaet), rechts die Zeitreihe.

    DIE KOPFZEILE IST DER WICHTIGSTE TEIL DIESER ANSICHT. Sie sagt, worauf die
    Zahlen darunter beruhen: wie viele Uebergaben bestaetigt sind, wie viele nur
    auf dem Wort des Lootmeisters stehen, und wie viel Beute ohne belegte
    Herkunft dabei ist. Eine Statistik ohne diese Angaben sieht genauso aus,
    ob sie auf Messungen beruht oder auf Vermutungen.
------------------------------------------------------------------------------]]

local _, GA = ...

local AnalyticsView = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local L = GA.L

AnalyticsView.title = L.NAV_ANALYTICS

local GROUPINGS = {
    { key = "player",    label = "ANA_BY_PLAYER",    fn = "ByPlayer" },
    { key = "character", label = "ANA_BY_CHARACTER", fn = "ByCharacter" },
    { key = "source",    label = "ANA_BY_SOURCE",    fn = "BySource" },
    { key = "response",  label = "ANA_BY_RESPONSE",  fn = "ByResponse" },
    { key = "quality",   label = "ANA_BY_QUALITY",   fn = "ByQuality" },
}

local RANGES = {
    { key = "all", label = "ANA_RANGE_ALL" },
    { key = "d7",  label = "ANA_RANGE_7" },
    { key = "d30", label = "ANA_RANGE_30" },
    { key = "d90", label = "ANA_RANGE_90" },
}

-- ================================================================== Aufbau ----

function AnalyticsView:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    self.grouping = "player"
    self.range = "all"

    -- ------------------------------------------------------ Werkzeugzeile ---
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(24)

    self.groupButtons = {}
    local previous
    for _, grouping in ipairs(GROUPINGS) do
        local button = Widgets.Button(bar, L[grouping.label], function()
            self.grouping = grouping.key
            self:Refresh()
        end)
        button:SetHeight(20)
        button:SetWidth(86)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 3, 0)
        else
            button:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
        button.groupKey = grouping.key
        self.groupButtons[#self.groupButtons + 1] = button
        previous = button
    end

    self.rangeButtons = {}
    local previousRange
    for index = #RANGES, 1, -1 do
        local range = RANGES[index]
        local button = Widgets.Button(bar, L[range.label], function()
            self.range = range.key
            self:Refresh()
        end)
        button:SetHeight(20)
        button:SetWidth(58)
        if previousRange then
            button:SetPoint("RIGHT", previousRange, "LEFT", -3, 0)
        else
            button:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
        button.rangeKey = range.key
        self.rangeButtons[#self.rangeButtons + 1] = button
        previousRange = button
    end

    -- ------------------------------------------------------ Eckdaten --------
    local head = Widgets.Inset(frame)
    head:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    head:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    head:SetHeight(62)

    self.headline = Theme.Label(head, "", fonts.hero, Theme.color.goldBright)
    self.headline:SetPoint("TOPLEFT", head, "TOPLEFT", 14, -8)
    if self.headline.SetShadowOffset then self.headline:SetShadowOffset(1, -1) end

    self.headlineLabel = Theme.Label(head, "", fonts.body, Theme.color.textDim)
    self.headlineLabel:SetPoint("LEFT", self.headline, "RIGHT", 8, -3)

    -- Beleglage: die Zeile, die diese Ansicht ehrlich macht.
    self.evidence = Theme.Label(head, "", fonts.small, Theme.color.textFaint)
    self.evidence:SetPoint("TOPLEFT", self.headline, "BOTTOMLEFT", 1, -4)
    self.evidence:SetPoint("RIGHT", head, "RIGHT", -14, 0)
    self.evidence:SetJustifyH("LEFT")
    self.evidence:SetSpacing(2)

    -- ------------------------------------------------------ Tabelle ---------
    local table_ = Widgets.Panel(frame, L.ANA_TABLE)
    table_:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -gap)
    table_:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    table_:SetWidth(460)
    self.tablePanel = table_

    self.rows = Widgets.ScrollList(table_.content, {
        rowHeight = 24,
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, entry) self:UpdateRow(row, entry) end,
    })
    self.rows:SetAllPoints(table_.content)

    -- ------------------------------------------------------ Zeitreihe -------
    local chart = Widgets.Panel(frame, L.ANA_TIMELINE)
    chart:SetPoint("TOPLEFT", table_, "TOPRIGHT", gap, 0)
    chart:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)

    self.chart = Widgets.LevelChart(chart.content, 30)
    self.chart:SetPoint("TOPLEFT", chart.content, "TOPLEFT", 0, 0)
    self.chart:SetPoint("TOPRIGHT", chart.content, "TOPRIGHT", 0, 0)
    self.chart:SetHeight(150)

    self.chartHint = Theme.Label(chart.content, L.ANA_TIMELINE_HINT, fonts.small, Theme.color.textFaint)
    self.chartHint:SetPoint("TOPLEFT", self.chart, "BOTTOMLEFT", 0, -6)
    self.chartHint:SetPoint("RIGHT", chart.content, "RIGHT", 0, 0)
    self.chartHint:SetJustifyH("LEFT")
    self.chartHint:SetSpacing(2)

    self.frame = frame
    return frame
end

-- ================================================================== Zeilen ----

function AnalyticsView:BuildRow(row)
    local fonts = Theme.Fonts()

    row.label = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.label:SetWidth(150)
    row.label:SetJustifyH("LEFT")

    row.count = Theme.Label(row, "", fonts.body, Theme.color.goldBright)
    row.count:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
    row.count:SetWidth(34)
    row.count:SetJustifyH("RIGHT")

    -- Balken statt Prozentzahl: Der Vergleich zwischen den Zeilen ist das
    -- Interessante, nicht der Absolutwert auf zwei Stellen.
    --
    -- Bewusst NICHT Widgets.BarRow: Das Widget bringt eine eigene Beschriftung
    -- und eine eigene Zahl mit, die hier neben row.count ein zweites Mal
    -- daestuende. Hier genuegen Schiene und Fuellung.
    local track = CreateFrame("Frame", nil, row)
    track:SetPoint("LEFT", row.count, "RIGHT", 8, 0)
    track:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    track:SetHeight(6)
    Theme.Fill(track, Theme.color.rowAltBg)

    local fill = track:CreateTexture(nil, "ARTWORK")
    Theme.Paint(fill, Theme.color.gold)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)

    row.track = track
    row.fill = fill

    --- @param value number
    --- @param maximum number  der groesste Wert der Tabelle
    function row:SetBar(value, maximum)
        local width = self.track:GetWidth()
        if not width or width <= 0 then width = 120 end
        local ratio = (maximum and maximum > 0) and (value / maximum) or 0
        self.fill:SetWidth(math.max(1, width * ratio))
    end

    row.note = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.note:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.note:SetWidth(100)
    row.note:SetJustifyH("RIGHT")
end

function AnalyticsView:UpdateRow(row, entry)
    local label = entry.label

    -- Ohne Beschriftung ist es die Zeile fuer Unbelegtes — sie bekommt einen
    -- Namen, damit sie nicht wie ein Fehler aussieht.
    if label == nil then label = L.ANA_UNKNOWN end
    if self.grouping == "quality" then
        label = L["QUALITY_" .. tostring(entry.key)] or ("Q" .. tostring(entry.key))
    elseif self.grouping == "response" then
        local response = GA.Modules.Session:ResponseByKey(entry.extra and entry.extra.responseKey)
        label = response and response.label or label
    end

    row.label:SetText(label)
    local class = entry.extra and entry.extra.class
    if class then
        local r, g, b = Util.ClassColor(class)
        row.label:SetTextColor(r, g, b)
    elseif entry.label == nil then
        row.label:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
    else
        row.label:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    end

    row.count:SetText(tostring(entry.delivered))
    row:SetBar(entry.delivered, self.maxDelivered or 1)

    -- Was an dieser Zeile unsicher ist, steht rechts.
    local notes = {}
    if entry.pending > 0 then notes[#notes + 1] = string.format(L.ANA_PENDING, entry.pending) end
    if entry.manual > 0 then notes[#notes + 1] = string.format(L.ANA_MANUAL, entry.manual) end
    if entry.hasClaimed then notes[#notes + 1] = L.ANA_CLAIMED end
    if entry.extra and entry.extra.unlinked then notes[#notes + 1] = L.ANA_UNLINKED end

    row.note:SetText(table.concat(notes, "  "))
    local warn = entry.hasClaimed or entry.manual > 0
    local color = warn and Theme.color.warn or Theme.color.textFaint
    row.note:SetTextColor(color[1], color[2], color[3])
end

-- ================================================================== Refresh ---

function AnalyticsView:Filter()
    if self.range == "all" then return nil end
    for _, range in ipairs(GA.Modules.Analytics:Ranges()) do
        if range.key == self.range then return { since = range.since } end
    end
    return nil
end

function AnalyticsView:OnShow() self:Refresh() end

function AnalyticsView:Refresh()
    local Analytics = GA.Modules.Analytics
    local filter = self:Filter()

    for _, button in ipairs(self.groupButtons) do
        button:SetEnabledState(button.groupKey ~= self.grouping, L.ANA_ACTIVE)
    end
    for _, button in ipairs(self.rangeButtons) do
        button:SetEnabledState(button.rangeKey ~= self.range, L.ANA_ACTIVE)
    end

    -- Eckdaten
    local summary = Analytics:Summary(filter)
    self.headline:SetText(tostring(summary.delivered))
    self.headlineLabel:SetText(L.ANA_DELIVERED)

    local parts = {}
    if summary.pending > 0 then parts[#parts + 1] = string.format(L.ANA_SUM_PENDING, summary.pending) end
    parts[#parts + 1] = string.format(L.ANA_SUM_STRONG, summary.strong)
    if summary.chat > 0 then parts[#parts + 1] = string.format(L.ANA_SUM_CHAT, summary.chat) end
    if summary.manual > 0 then parts[#parts + 1] = string.format(L.ANA_SUM_MANUAL, summary.manual) end
    if summary.unknownSource > 0 then
        parts[#parts + 1] = string.format(L.ANA_SUM_UNKNOWN, summary.unknownSource)
    end
    if summary.firstTs then
        parts[#parts + 1] = string.format(L.ANA_SUM_SINCE, Util.TimeAgo(summary.firstTs))
    end
    self.evidence:SetText(table.concat(parts, "  ·  "))

    -- Tabelle
    local grouping
    for _, entry in ipairs(GROUPINGS) do
        if entry.key == self.grouping then grouping = entry break end
    end

    local rows = Analytics[grouping.fn](Analytics, filter)
    self.maxDelivered = 1
    for _, entry in ipairs(rows) do
        if entry.delivered > self.maxDelivered then self.maxDelivered = entry.delivered end
    end

    self.tablePanel:SetTitle(string.format("%s  (%d)", L[grouping.label], #rows))
    self.rows:SetData(rows)

    -- Zeitreihe
    local points = Analytics:Timeline(filter)
    self.chart:SetPoints(points, L.ANA_NO_DATA)
    if #points > 0 then self.chartHint:Show() else self.chartHint:Hide() end

    GA.UI.MainFrame:SetContext(string.format(L.ANA_CONTEXT, summary.delivered, summary.pending))
end

GA.UI.MainFrame:RegisterView("analytics", AnalyticsView)
