--[[----------------------------------------------------------------------------
    Views/Analytics — wer hat was bekommen, woher kam es, wie gut ist es belegt.

    Oben die Gruppierung als Chips (Spieler, Charakter, Herkunft, Schlachtzug,
    Boss, Antwort, Qualitaet, Anwesenheit, DKP), darunter der Zeitraum und
    "Kopieren"; dann die Eckdaten, links die Tabelle, rechts die Zeitreihe.

    EIN WERKZEUG, KEINE TAFEL (08.10.2026): Jede Zeile der Loot-Gruppierungen
    fuehrt per Klick in die Loothistorie, gefiltert auf genau diese Zeile —
    "alles von Harry" ist die Frage, die hier gestellt wird. Eine DKP-Zeile
    oeffnet das Kontobuch. Die Tabelle laesst sich als Text kopieren.

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

AnalyticsView.titleKey = "NAV_ANALYTICS"

--- loot = Zeile fuehrt in die Loothistorie; dkp = ins Kontobuch; sonst nichts.
local GROUPINGS = {
    { key = "player",     label = "ANA_BY_PLAYER",     fn = "ByPlayer",    kind = "loot" },
    { key = "character",  label = "ANA_BY_CHARACTER",  fn = "ByCharacter", kind = "loot" },
    { key = "source",     label = "ANA_BY_SOURCE",     fn = "BySource",    kind = "loot" },
    { key = "raid",       label = "ANA_BY_RAID",       fn = "ByRaid",      kind = "loot" },
    { key = "boss",       label = "ANA_BY_BOSS",       fn = "ByBoss",      kind = "loot" },
    { key = "response",   label = "ANA_BY_RESPONSE",   fn = "ByResponse",  kind = "loot" },
    { key = "quality",    label = "ANA_BY_QUALITY",    fn = "ByQuality",   kind = "loot" },
    { key = "attendance", label = "ANA_BY_ATTENDANCE", fn = "Attendance",  kind = "attendance" },
    { key = "dkp",        label = "ANA_BY_DKP",        fn = "Dkp",         kind = "dkp" },
}

local RANGES = {
    { key = "all", label = "ANA_RANGE_ALL" },
    { key = "d7",  label = "ANA_RANGE_7" },
    { key = "d30", label = "ANA_RANGE_30" },
    { key = "d90", label = "ANA_RANGE_90" },
}

local function groupingByKey(key)
    for _, entry in ipairs(GROUPINGS) do
        if entry.key == key then return entry end
    end
    return GROUPINGS[1]
end

-- ================================================================== Aufbau ----

function AnalyticsView:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    self.grouping = "player"
    self.range = "all"

    -- ------------------------------------------------------ Gruppierung -----
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(20)

    self.groupChips = {}
    local previous
    for _, grouping in ipairs(GROUPINGS) do
        local chip = Widgets.Chip(bar, L[grouping.label], function()
            self.grouping = grouping.key
            self:Refresh()
        end)
        chip:SetHeight(20)
        if previous then
            chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            chip:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
        chip.groupKey = grouping.key
        self.groupChips[#self.groupChips + 1] = chip
        previous = chip
    end

    -- ------------------------------------------------------ Zeitraum --------
    local bar2 = CreateFrame("Frame", nil, frame)
    bar2:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
    bar2:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -4)
    bar2:SetHeight(20)

    self.rangeChips = {}
    previous = nil
    for _, range in ipairs(RANGES) do
        local chip = Widgets.Chip(bar2, L[range.label], function()
            self.range = range.key
            self:Refresh()
        end)
        chip:SetHeight(20)
        if previous then
            chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            chip:SetPoint("LEFT", bar2, "LEFT", 0, 0)
        end
        chip.rangeKey = range.key
        self.rangeChips[#self.rangeChips + 1] = chip
        previous = chip
    end

    self.copyButton = Widgets.Button(bar2, L.ANA_COPY, function() self:CopyTable() end)
    self.copyButton:SetTooltip(L.TT_ANA_COPY)
    self.copyButton:SetHeight(20)
    self.copyButton:SetPoint("RIGHT", bar2, "RIGHT", 0, 0)

    -- ------------------------------------------------------ Eckdaten --------
    local head = Widgets.Inset(frame)
    head:SetPoint("TOPLEFT", bar2, "BOTTOMLEFT", 0, -6)
    head:SetPoint("TOPRIGHT", bar2, "BOTTOMRIGHT", 0, -6)
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
        emptyText = L.ANA_TABLE_EMPTY,
        rowHeight = 24,
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, entry) self:UpdateRow(row, entry) end,
        onClickRow = function(entry) self:OpenRow(entry) end,
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

    -- Was ein Klick auf eine Zeile tut — je Gruppierung anders.
    self.rowHint = Theme.Label(chart.content, "", fonts.small, Theme.color.textFaint)
    self.rowHint:SetPoint("BOTTOMLEFT", chart.content, "BOTTOMLEFT", 0, 0)
    self.rowHint:SetPoint("RIGHT", chart.content, "RIGHT", 0, 0)
    self.rowHint:SetJustifyH("LEFT")
    self.rowHint:SetSpacing(2)

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
    Theme.BarFill(fill, Theme.color.gold)
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

--- Die Beschriftung einer Zeile, wie sie in Tabelle und Kopie steht.
function AnalyticsView:RowLabel(entry)
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
    return label
end

--- Was rechts an der Zeile steht: bei Loot das Unsichere, bei Anwesenheit
--- Zusagen und Abende, bei DKP Zugang und Abgang.
--- @return string text, boolean warn
function AnalyticsView:RowNote(entry)
    if entry.kind == "attendance" then
        return string.format(L.ANA_ATT_NOTE, entry.signed or 0, entry.evenings or 0), false
    end
    if entry.kind == "dkp" then
        return string.format(L.ANA_DKP_NOTE, entry.earned or 0, entry.spent or 0), false
    end
    local notes = {}
    if entry.pending > 0 then notes[#notes + 1] = string.format(L.ANA_PENDING, entry.pending) end
    if entry.manual > 0 then notes[#notes + 1] = string.format(L.ANA_MANUAL, entry.manual) end
    if entry.hasClaimed then notes[#notes + 1] = L.ANA_CLAIMED end
    if entry.extra and entry.extra.unlinked then notes[#notes + 1] = L.ANA_UNLINKED end
    return table.concat(notes, "  "), (entry.hasClaimed or entry.manual > 0) and true or false
end

function AnalyticsView:UpdateRow(row, entry)
    row.label:SetText(self:RowLabel(entry))
    local class = entry.extra and entry.extra.class
    if class then
        local r, g, b = Theme.ClassColor(class)
        row.label:SetTextColor(r, g, b)
    elseif entry.label == nil then
        row.label:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
    else
        row.label:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    end

    row.count:SetText(tostring(entry.delivered))
    row:SetBar(entry.delivered, self.maxDelivered or 1)

    local text, warn = self:RowNote(entry)
    row.note:SetText(text)
    local color = warn and Theme.color.warn or Theme.color.textFaint
    row.note:SetTextColor(color[1], color[2], color[3])
end

-- ================================================================== Klick -----

--- Der Filter fuer die Loothistorie zu einer Zeile — nil, wo es keinen gibt.
--- @return table|nil filter, string|nil beschreibung
function AnalyticsView:FilterForRow(entry)
    local grouping = groupingByKey(self.grouping)
    if grouping.kind ~= "loot" then return nil end
    local filter = {}
    local range = self:Filter()
    if range then filter.since = range.since end
    local extra = entry.extra or {}

    if self.grouping == "player" then
        local names = entry.characters or { entry.label }
        local set = {}
        for _, name in ipairs(names) do set[string.lower(Util.ShortName(name or ""))] = true end
        filter.recipients = set
    elseif self.grouping == "character" then
        if not entry.label then return nil end
        filter.recipients = { [string.lower(Util.ShortName(entry.label))] = true }
    elseif self.grouping == "source" or self.grouping == "boss" then
        if extra.kind == "encounter" then filter.encounterName = entry.label
        elseif extra.kind == "creature" then filter.sourceName = entry.label
        elseif extra.kind == "npcid" then filter.sourceNpcID = tonumber(string.match(entry.key, "^i:(%d+)$"))
        else filter.unknownSource = true end
    elseif self.grouping == "raid" then
        if extra.kind == "raid" then filter.instanceName = entry.label else filter.unknownRaid = true end
    elseif self.grouping == "response" then
        filter.response = extra.responseKey
    elseif self.grouping == "quality" then
        filter.quality = extra.quality
    end
    return filter, self:RowLabel(entry)
end

function AnalyticsView:OpenRow(entry)
    if not entry then return end
    local grouping = groupingByKey(self.grouping)
    if grouping.kind == "dkp" then
        if GA.UI.DkpFrame then GA.UI.DkpFrame:Open() end
        return
    end
    local filter, description = self:FilterForRow(entry)
    if not filter then return end
    local history = GA.UI.MainFrame.views and GA.UI.MainFrame.views.loothistory
    if not history or not history.ApplyFilter then return end
    history:ApplyFilter(filter, description)
    GA.UI.MainFrame:ShowView("loothistory")
end

--- Die Tabelle als Text: eine Zeile je Eintrag, Tabulator-getrennt — fuer
--- Tabellenkalkulation und Discord gleichermassen.
function AnalyticsView:CopyTable()
    local grouping = groupingByKey(self.grouping)
    local lines = { L[grouping.label] }
    for _, range in ipairs(RANGES) do
        if range.key == self.range then lines[1] = lines[1] .. "  ·  " .. L[range.label] end
    end
    for _, entry in ipairs(self.currentRows or {}) do
        local note = self:RowNote(entry)
        lines[#lines + 1] = self:RowLabel(entry) .. "\t" .. tostring(entry.delivered)
            .. (note ~= "" and ("\t" .. note) or "")
    end
    Widgets.CopyDialog(L.ANA_TABLE, table.concat(lines, "\n"))
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

    for _, chip in ipairs(self.groupChips) do chip:SetPressed(chip.groupKey == self.grouping) end
    for _, chip in ipairs(self.rangeChips) do chip:SetPressed(chip.rangeKey == self.range) end

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
    local grouping = groupingByKey(self.grouping)
    local rows = Analytics[grouping.fn](Analytics, filter)
    self.maxDelivered = 1
    for _, entry in ipairs(rows) do
        if entry.delivered > self.maxDelivered then self.maxDelivered = entry.delivered end
    end
    self.currentRows = rows

    self.tablePanel:SetTitle(string.format("%s  (%d)", L[grouping.label], #rows))
    self.rows:SetData(rows)
    self.rows:SetEmptyText(grouping.kind == "attendance" and L.ANA_ATT_EMPTY
        or grouping.kind == "dkp" and L.ANA_DKP_EMPTY or L.ANA_TABLE_EMPTY)
    self.copyButton:SetEnabledState(#rows > 0, L.ANA_TABLE_EMPTY)

    self.rowHint:SetText(grouping.kind == "loot" and L.ANA_ROW_HINT
        or grouping.kind == "dkp" and L.ANA_DKP_HINT or L.ANA_ATT_HINT)

    -- Zeitreihe
    local points = Analytics:Timeline(filter)
    self.chart:SetPoints(points, L.ANA_NO_DATA)
    if #points > 0 then self.chartHint:Show() else self.chartHint:Hide() end

    GA.UI.MainFrame:SetContext(string.format(L.ANA_CONTEXT, summary.delivered, summary.pending))
end

GA.UI.MainFrame:RegisterView("analytics", AnalyticsView)
