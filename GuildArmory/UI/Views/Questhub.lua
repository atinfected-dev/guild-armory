--[[----------------------------------------------------------------------------
    Views/Questhub — die Tafel: Gesuche links, die gewaehlte Quest rechts.

    Entwurf Q1 (28.09.2026). Die Frage auf dieser Seite ist "lohnt sich der
    Weg?", und eine Tabellenzeile beantwortet sie ohne Klick: Art, Quest mit
    dem Zielstand des Suchers, Zone, Stufe (gruen, wenn nah an der eigenen),
    wer sucht und wie viele mitwollen, seit wann. Rechts die Einzelheiten:
    die Ziele des Suchers, wer sie noch sucht, was DU damit zu tun hast (aus
    dem eigenen Log), und der eine Knopf, der die Gruppeneinladung des
    Spiels schickt.

    "Quest aus dem Log" tauscht die rechte Seite gegen das eigene Questlog
    mit einem Knopf je Quest — der Weg ohne Alt-Klick, fuer den Fall, dass
    der Klick auf dieser Linie nirgends ankommt (siehe /ga probe).

    KEINE AUSWERTUNG HIER. Was ein Gesuch ist, wann es verfaellt und was
    mitgeht, entscheidet Quests/Questhub.lua.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

View.titleKey = "NAV_QUESTHUB"

local DETAIL_W = 320
local FILTERS = { "ALL", "ZONE", "LEVEL", "GROUP", "DUNGEON" }

--- Farbe je Questart.
local TAG_COLOR = {
    GROUP = "warn", DUNGEON = "epic", RAID = "epic", ELITE = "info", HEROIC = "epic", PVP = "bad",
}
local EPIC = { 0.64, 0.21, 0.93 }

local function tagColor(tag)
    local key = TAG_COLOR[tag or ""]
    if key == "epic" then return EPIC end
    return Theme.color[key or "textDim"]
end

local function tagLetter(tag)
    if not tag then return "" end
    return string.sub(L["QH_TAG_" .. tag] or tag, 1, 1)
end

local COLUMN_GAP, COLUMN_X0 = 6, 8
local function columns()
    return {
        { key = "kind",   label = "",            width = 18 },
        { key = "quest",  label = L.QH_COL_QUEST, width = 200 },
        { key = "zone",   label = L.QH_COL_ZONE,  width = 110 },
        { key = "level",  label = L.COL_LEVEL,    width = 30, justify = "RIGHT" },
        { key = "seeker", label = L.QH_COL_SEEKER, width = 104 },
        { key = "age",    label = L.QH_COL_SINCE,  width = 64, justify = "RIGHT" },
    }
end

local function offsets()
    local x, out, w = COLUMN_X0, {}, {}
    for _, column in ipairs(columns()) do
        out[column.key] = x
        w[column.key] = column.width
        x = x + column.width + COLUMN_GAP
    end
    return out, w
end

-- ================================================================== Aufbau ----

function View:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Werkzeugzeile ---
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(24)

    self.state = Theme.Label(bar, "", fonts.body, Theme.color.textDim)
    self.state:SetPoint("LEFT", bar, "LEFT", 2, 0)

    self.filter = "ALL"
    self.filterChips = {}
    local vorige
    for _, key in ipairs(FILTERS) do
        local chip = Widgets.Chip(bar, L["QH_FILTER_" .. key], function(pressed)
            self.filter = pressed and key or "ALL"
            self:Refresh()
        end)
        if vorige then chip:SetPoint("LEFT", vorige, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", self.state, "RIGHT", 14, 0) end
        chip.filterKey = key
        self.filterChips[#self.filterChips + 1] = chip
        vorige = chip
    end

    self.pickButton = Widgets.Button(bar, L.QH_FROM_LOG, function()
        self.picking = not self.picking
        self:Refresh()
    end, "primary")
    self.pickButton:SetTooltip(L.TT_QH_FROM_LOG)
    self.pickButton:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    self.search = Widgets.SearchBox(bar, L.QH_SEARCH, function() self:Refresh() end)
    self.search:SetPoint("RIGHT", self.pickButton, "LEFT", -8, 0)
    self.search:SetWidth(180)

    -- ------------------------------------------------------ Tafel -----------
    local table_ = Widgets.Panel(frame, L.QH_TITLE)
    table_:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    table_:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    table_:SetPoint("RIGHT", frame, "RIGHT", -(pad + DETAIL_W + gap), 0)
    self.tablePanel = table_

    self.rows = Widgets.ScrollList(table_.content, {
        rowHeight = 40,
        columns = columns(),
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, request) self:UpdateRow(row, request) end,
        onClickRow = function(request)
            self.selectedId = request.id
            self.picking = false
            self:Refresh()
        end,
    })
    self.rows:SetPoint("TOPLEFT", table_.content, "TOPLEFT", 0, 0)
    self.rows:SetPoint("BOTTOMRIGHT", table_.content, "BOTTOMRIGHT", 0, 18)

    self.footer = Theme.Label(table_.content, L.QH_FOOTER, fonts.small, Theme.color.textFaint)
    self.footer:SetPoint("BOTTOMLEFT", table_.content, "BOTTOMLEFT", 2, 2)
    self.footer:SetPoint("RIGHT", table_.content, "RIGHT", -2, 0)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetWordWrap(false)

    self.empty = Theme.Label(table_.content, L.QH_EMPTY, fonts.small, Theme.color.textFaint)
    self.empty:SetPoint("TOPLEFT", table_.content, "TOPLEFT", 8, -28)
    self.empty:SetPoint("RIGHT", table_.content, "RIGHT", -8, 0)
    self.empty:SetJustifyH("LEFT")
    self.empty:SetSpacing(2)
    self.empty:Hide()

    -- ------------------------------------------------------ Rechts ----------
    local detail = Widgets.Inset(frame)
    detail:SetWidth(DETAIL_W)
    detail:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.detail = detail
    self:BuildDetail(detail, fonts)
    self:BuildPicker(detail, fonts)

    self.frame = frame
    return frame
end

-- ================================================================== Zeilen ----

function View:BuildRow(row)
    local fonts = Theme.Fonts()
    local x, w = offsets()

    row.edge = Theme.Fill(row, Theme.color.gold)
    row.edge:ClearAllPoints()
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(2)
    row.edge:Hide()

    row.kind = CreateFrame("Frame", nil, row)
    row.kind:SetWidth(14) row.kind:SetHeight(14)
    row.kind:SetPoint("LEFT", row, "LEFT", x.kind, 0)
    row.kindLines = Theme.Outline(row.kind, Theme.color.border)
    row.kindText = Theme.Label(row.kind, "", fonts.small, Theme.color.textDim)
    row.kindText:SetPoint("CENTER", row.kind, "CENTER", 0, 0)

    row.quest = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.quest:SetPoint("TOPLEFT", row, "TOPLEFT", x.quest, -6)
    row.quest:SetWidth(w.quest)
    row.quest:SetJustifyH("LEFT")
    row.quest:SetWordWrap(false)

    row.objectives = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.objectives:SetPoint("TOPLEFT", row, "TOPLEFT", x.quest, -21)
    row.objectives:SetWidth(w.quest)
    row.objectives:SetJustifyH("LEFT")
    row.objectives:SetWordWrap(false)

    row.zone = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.zone:SetPoint("LEFT", row, "LEFT", x.zone, 0)
    row.zone:SetWidth(w.zone)
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)

    row.level = Theme.Label(row, "", fonts.rowBold, Theme.color.textDim)
    row.level:SetPoint("LEFT", row, "LEFT", x.level, 0)
    row.level:SetWidth(w.level)
    row.level:SetJustifyH("RIGHT")

    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(12) row.crest:SetHeight(12)
    row.crest:SetPoint("LEFT", row, "LEFT", x.seeker, 0)

    row.seeker = Theme.Label(row, "", fonts.small, Theme.color.text)
    row.seeker:SetPoint("LEFT", row, "LEFT", x.seeker + 16, 0)
    row.seeker:SetWidth(w.seeker - 16)
    row.seeker:SetJustifyH("LEFT")
    row.seeker:SetWordWrap(false)

    row.age = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.age:SetPoint("LEFT", row, "LEFT", x.age, 0)
    row.age:SetWidth(w.age)
    row.age:SetJustifyH("RIGHT")
end

function View:UpdateRow(row, request)
    local selected = request.id == self.selectedId
    if selected then
        row.edge:Show()
        Theme.Paint(row.background, Theme.color.rowHover)
    else
        row.edge:Hide()
    end

    local farbe = tagColor(request.tag)
    row.kindText:SetText(tagLetter(request.tag))
    row.kindText:SetTextColor(farbe[1], farbe[2], farbe[3])
    for _, line in ipairs(row.kindLines) do Theme.Paint(line, request.tag and farbe or Theme.color.border) end

    row.quest:SetText(request.title or "?")
    local tc = request.own and Theme.color.goldBright or Theme.color.text
    row.quest:SetTextColor(tc[1], tc[2], tc[3])

    -- Der Zielstand des Suchers, "+" erledigt, "-" offen, in einer Zeile.
    local teile = {}
    for _, ziel in ipairs(request.objectives or {}) do
        teile[#teile + 1] = string.sub(ziel, 2)
    end
    row.objectives:SetText(table.concat(teile, " · "))

    row.zone:SetText(request.zone or "")

    -- Die Stufe: gruen, wenn nah an der eigenen — die Frage "lohnt sich der
    -- Weg" hat hier ihre erste Antwort.
    local eigene = Compat.GetPlayerIdentity().level
    row.level:SetText(request.level and tostring(request.level) or "")
    local nah = eigene and request.level and math.abs(eigene - request.level) <= 5
    local lc = nah and Theme.color.jade or Theme.color.textDim
    row.level:SetTextColor(lc[1], lc[2], lc[3])

    if request.class and Theme.SetClassPortrait(row.crest, request.class) then
        row.crest:Show()
    else
        row.crest:Hide()
    end
    local r, g, b = Theme.ClassColor(request.class)
    local mit = GA.Modules.Questhub:JoinerCount(request)
    row.seeker:SetText(Util.FirstName(request.seeker or "?") .. (mit > 0 and (" |cff6f6753+" .. mit .. "|r") or ""))
    row.seeker:SetTextColor(r, g, b)

    row.age:SetText(Util.TimeAgo(request.ts))
end

-- ================================================================== Rechts ----

function View:BuildDetail(parent, fonts)
    local d = CreateFrame("Frame", nil, parent)
    d:SetAllPoints(parent)
    self.detailFrame = d

    d.kicker = Theme.Label(d, "", fonts.small, Theme.color.warn)
    d.kicker:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -12)

    d.title = Theme.Label(d, "", fonts.big, Theme.color.goldBright)
    d.title:SetPoint("TOPLEFT", d.kicker, "BOTTOMLEFT", 0, -4)
    d.title:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.title:SetJustifyH("LEFT")
    d.title:SetSpacing(2)

    d.zone = Theme.Label(d, "", fonts.small, Theme.color.textDim)
    d.zone:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.zone:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.zone:SetJustifyH("LEFT")

    local sep1 = d:CreateTexture(nil, "ARTWORK")
    Theme.Paint(sep1, Theme.color.border)
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT", d.zone, "BOTTOMLEFT", -14, -10)
    sep1:SetPoint("RIGHT", d, "RIGHT", 0, 0)

    d.goalsHead = Theme.Label(d, string.upper(L.QH_GOALS), fonts.heading, Theme.color.goldDim)
    d.goalsHead:SetPoint("TOPLEFT", sep1, "BOTTOMLEFT", 14, -8)

    d.goals = {}
    for index = 1, 3 do
        local line = CreateFrame("Frame", nil, d)
        line:SetHeight(14)
        line:SetPoint("TOPLEFT", d.goalsHead, "BOTTOMLEFT", 0, -(4 + (index - 1) * 16))
        line:SetPoint("RIGHT", d, "RIGHT", -14, 0)
        line.text = Theme.Label(line, "", fonts.small, Theme.color.text)
        line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
        line.text:SetPoint("RIGHT", line, "RIGHT", -16, 0)
        line.text:SetJustifyH("LEFT")
        line.text:SetWordWrap(false)
        line.mark = Theme.Label(line, "", fonts.small, Theme.color.jade)
        line.mark:SetPoint("RIGHT", line, "RIGHT", 0, 0)
        d.goals[index] = line
    end
    d.goalsHint = Theme.Label(d, L.QH_GOALS_HINT, fonts.small, Theme.color.textFaint)
    d.goalsHint:SetPoint("TOPLEFT", d.goalsHead, "BOTTOMLEFT", 0, -54)
    d.goalsHint:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.goalsHint:SetJustifyH("LEFT")

    d.seekersHead = Theme.Label(d, "", fonts.heading, Theme.color.goldDim)
    d.seekersHead:SetPoint("TOPLEFT", d.goalsHint, "BOTTOMLEFT", 0, -12)

    d.seekers = Widgets.ScrollList(d, {
        rowHeight = 26,
        createRow = function(row)
            row.crest = row:CreateTexture(nil, "ARTWORK")
            row.crest:SetWidth(12) row.crest:SetHeight(12)
            row.crest:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.whisper = Widgets.Button(row, L.QH_WHISPER, function()
                if row.item then Compat.OpenWhisper(row.item.name) end
            end)
            row.whisper:SetTooltip(L.TT_WHISPER)
            row.whisper:SetHeight(18)
            row.whisper:SetWidth(64)
            row.whisper:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.name = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.name:SetPoint("LEFT", row, "LEFT", 20, 0)
            row.name:SetPoint("RIGHT", row.whisper, "LEFT", -6, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
        end,
        updateRow = function(row, entry)
            local r, g, b = Theme.ClassColor(entry.class)
            if entry.class and Theme.SetClassPortrait(row.crest, entry.class) then row.crest:Show() else row.crest:Hide() end
            row.name:SetText(entry.name .. (entry.poster and ("  |cff6f6753" .. L.QH_POSTER .. "|r") or ""))
            row.name:SetTextColor(r, g, b)
            row.whisper:SetShown(not entry.me)
        end,
    })
    d.seekers:SetPoint("TOPLEFT", d.seekersHead, "BOTTOMLEFT", -4, -4)
    d.seekers:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.seekers:SetHeight(80)

    d.mine = Theme.Label(d, "", fonts.small, Theme.color.textDim)
    d.mine:SetPoint("TOPLEFT", d.seekers, "BOTTOMLEFT", 4, -10)
    d.mine:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.mine:SetJustifyH("LEFT")

    -- Knoepfe unten.
    d.invite = Widgets.Button(d, L.QH_INVITE, function()
        local request = GA.Modules.Questhub:Get(self.selectedId)
        if not request then return end
        local ok, weg = GA.Modules.Questhub:Invite(request)
        GA.Core.Debug:Info(ok and L.QH_INVITED or L.QH_INVITE_FAILED, tostring(request.seeker), tostring(weg))
    end, "primary")
    d.invite:SetTooltip(L.TT_INVITE)
    d.invite:SetHeight(28)
    d.invite:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 48)
    d.invite:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -14, 48)

    d.join = Widgets.Button(d, L.QH_JOIN, function()
        local Questhub = GA.Modules.Questhub
        local request = Questhub:Get(self.selectedId)
        if not request then return end
        if request.own then Questhub:Withdraw(request.id)
        else Questhub:Join(request.id, not Questhub:HasJoined(request)) end
        self:Refresh()
    end)
    d.join:SetTooltip(L.TT_QH_JOIN)
    d.join:SetHeight(22)
    d.join:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 22)
    d.join:SetWidth(140)

    d.announce = Widgets.Button(d, L.QH_ANNOUNCE, function()
        local request = GA.Modules.Questhub:Get(self.selectedId)
        if request then GA.Modules.Questhub:Announce(request) end
    end)
    d.announce:SetTooltip(L.TT_QH_ANNOUNCE)
    d.announce:SetHeight(22)
    d.announce:SetPoint("LEFT", d.join, "RIGHT", 6, 0)
    d.announce:SetPoint("RIGHT", d, "RIGHT", -14, 0)

    d.note = Theme.Label(d, L.QH_INVITE_NOTE, fonts.small, Theme.color.textFaint)
    d.note:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 6)
    d.note:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.note:SetJustifyH("LEFT")
    d.note:SetWordWrap(false)

    d.none = Theme.Label(d, L.QH_PICK, fonts.small, Theme.color.textFaint)
    d.none:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -14)
    d.none:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.none:SetJustifyH("LEFT")
    d.none:SetSpacing(2)
end

--- Das eigene Questlog mit "Einstellen" je Quest — der Weg ohne Alt-Klick.
function View:BuildPicker(parent, fonts)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints(parent)
    p:Hide()
    self.picker = p

    p.head = Theme.Label(p, L.QH_LOG_TITLE, fonts.big, Theme.color.goldBright)
    p.head:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)

    p.hint = Theme.Label(p, "", fonts.small, Theme.color.textFaint)
    p.hint:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -4)
    p.hint:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    p.hint:SetJustifyH("LEFT")
    p.hint:SetSpacing(2)

    p.list = Widgets.ScrollList(p, {
        rowHeight = 30,
        createRow = function(row)
            row.button = Widgets.Button(row, "", function()
                if not row.item then return end
                local Questhub = GA.Modules.Questhub
                if row.item.posted then Questhub:Withdraw(row.item.posted.id)
                else Questhub:Post(row.item.entry) end
                self:Refresh()
            end)
            row.button:SetHeight(18)
            row.button:SetWidth(84)
            row.button:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.title = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
            row.title:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
            row.title:SetJustifyH("LEFT")
            row.title:SetWordWrap(false)
            row.meta = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.meta:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -16)
            row.meta:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
            row.meta:SetJustifyH("LEFT")
            row.meta:SetWordWrap(false)
        end,
        updateRow = function(row, item)
            row.title:SetText(item.entry.title or "?")
            local farbe = item.posted and Theme.color.goldBright or Theme.color.text
            row.title:SetTextColor(farbe[1], farbe[2], farbe[3])
            local teile = {}
            if item.entry.level then teile[#teile + 1] = string.format(L.LEVEL_FMT, tostring(item.entry.level)) end
            if item.entry.tag then teile[#teile + 1] = L["QH_TAG_" .. item.entry.tag] or item.entry.tag end
            if item.entry.header then teile[#teile + 1] = item.entry.header end
            row.meta:SetText(table.concat(teile, " · "))
            row.button:SetLabel(item.posted and L.QH_WITHDRAW or L.QH_POST)
            row.button:SetWidth(84)
        end,
    })
    p.list:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", -4, -8)
    p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -10, 34)

    p.close = Widgets.Button(p, L.QH_BACK, function()
        self.picking = false
        self:Refresh()
    end)
    p.close:SetTooltip(L.TT_BACK)
    p.close:SetHeight(22)
    p.close:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 8)
end

-- ================================================================== Refresh ---

function View:Filtered(list)
    local search = string.lower(self.search and self.search:GetValue() or "")
    local identity = Compat.GetPlayerIdentity()
    local zone = Compat.GetZone()
    local out = {}
    for _, request in ipairs(list) do
        local keep = true
        if self.filter == "ZONE" then keep = zone ~= nil and request.zone == zone
        elseif self.filter == "LEVEL" then
            keep = identity.level ~= nil and request.level ~= nil and math.abs(identity.level - request.level) <= 5
        elseif self.filter == "GROUP" then keep = request.tag == "GROUP" or request.tag == "ELITE"
        elseif self.filter == "DUNGEON" then keep = request.tag == "DUNGEON" or request.tag == "RAID" or request.tag == "HEROIC"
        end
        if keep and search ~= "" then
            local heu = string.lower((request.title or "") .. " " .. (request.zone or "") .. " " .. (request.seeker or ""))
            keep = string.find(heu, search, 1, true) ~= nil
        end
        if keep then out[#out + 1] = request end
    end
    return out
end

function View:RefreshDetail(request)
    local d = self.detailFrame
    local Questhub = GA.Modules.Questhub
    local widgets = { d.kicker, d.title, d.zone, d.goalsHead, d.goalsHint, d.seekersHead,
        d.seekers, d.mine, d.invite, d.join, d.announce, d.note }
    for _, line in ipairs(d.goals) do widgets[#widgets + 1] = line end

    if not request then
        for _, w in ipairs(widgets) do w:Hide() end
        d.none:Show()
        return
    end
    d.none:Hide()
    for _, w in ipairs(widgets) do w:Show() end

    local farbe = tagColor(request.tag)
    local kicker = {}
    if request.tag then kicker[#kicker + 1] = string.upper(L["QH_TAG_" .. request.tag] or request.tag) end
    if request.level then kicker[#kicker + 1] = string.upper(string.format(L.LEVEL_FMT, tostring(request.level))) end
    d.kicker:SetText(table.concat(kicker, " · "))
    d.kicker:SetTextColor(farbe[1], farbe[2], farbe[3])
    d.title:SetText(request.title or "?")
    d.zone:SetText(request.zone or "")

    for index, line in ipairs(d.goals) do
        local ziel = request.objectives and request.objectives[index]
        if ziel then
            local erledigt = string.sub(ziel, 1, 1) == "+"
            line.text:SetText(string.sub(ziel, 2))
            line.mark:SetText(erledigt and "✓" or "")
            line:Show()
        else
            line:Hide()
        end
    end
    d.goalsHint:SetText(#(request.objectives or {}) > 0 and L.QH_GOALS_HINT or L.QH_GOALS_NONE)

    -- Wer sucht: der Sucher zuerst, dann die, die mitwollen.
    local me = Util.ShortName(Compat.GetPlayerIdentity().name or "")
    local liste = { { name = request.seeker, class = request.class, poster = true, me = request.own } }
    local joiners = {}
    for name in pairs(request.joiners or {}) do joiners[#joiners + 1] = name end
    table.sort(joiners)
    for _, name in ipairs(joiners) do
        liste[#liste + 1] = { name = name, class = nil, me = name == me }
    end
    d.seekersHead:SetText(string.upper(string.format(L.QH_SEEKERS, #liste)))
    d.seekers:SetData(liste)

    -- Was DU damit zu tun hast — aus deinem Log, nicht aus dem Gesuch.
    local eigene = Questhub:MatchOwn(request.questID)
    if eigene then
        local offen, gesamt = 0, #eigene.objectives
        for _, objective in ipairs(eigene.objectives) do if not objective.finished then offen = offen + 1 end end
        d.mine:SetText(string.format(L.QH_MINE_HAVE, gesamt - offen, gesamt))
        d.mine:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
    else
        d.mine:SetText(L.QH_MINE_NOT)
        d.mine:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    if request.own then
        d.invite:SetLabel(L.QH_OWN)
        d.invite:SetEnabledState(false, L.QH_OWN_HINT)
        d.join:SetLabel(L.QH_WITHDRAW)
    else
        d.invite:SetLabel(string.format(L.QH_INVITE_NAME, Util.FirstName(request.seeker or "?")))
        d.invite:SetEnabledState(true)
        d.join:SetLabel(Questhub:HasJoined(request) and L.QH_UNJOIN or L.QH_JOIN)
    end
    d.join:SetWidth(140)
end

function View:RefreshPicker()
    local p = self.picker
    local Questhub = GA.Modules.Questhub
    local log, weg = Compat.GetQuestLog()
    local items = {}
    local db = GA.Core.Database.account.questhub
    for _, entry in ipairs(log or {}) do
        local posted
        for _, request in pairs(db and db.own or {}) do
            if request.questID == entry.questID then posted = request break end
        end
        items[#items + 1] = { entry = entry, posted = posted }
    end
    p.hint:SetText(log and string.format(L.QH_LOG_HINT, #items, tostring(Questhub.hookPath or L.QH_NO_HOOK))
        or L.QH_NO_LOG)
    p.list:SetData(items)
end

function View:OnShow() self:Refresh() end

function View:Refresh()
    if not self.frame then return end
    local Questhub = GA.Modules.Questhub
    local alle = Questhub:List()

    for _, chip in ipairs(self.filterChips) do chip:SetPressed(chip.filterKey == self.filter) end

    local zonen, eigene = {}, 0
    for _, request in ipairs(alle) do
        zonen[request.zone or "?"] = true
        if request.own then eigene = eigene + 1 end
    end
    local zonenzahl = 0
    for _ in pairs(zonen) do zonenzahl = zonenzahl + 1 end
    self.state:SetText(string.format(L.QH_STATE, #alle, zonenzahl, eigene))

    local list = self:Filtered(alle)
    self.rows:SetData(list)
    self.empty:SetShown(#list == 0)

    local request = Questhub:Get(self.selectedId)
    if not request and list[1] then
        self.selectedId = list[1].id
        request = list[1]
    end

    if self.picking then
        self.detailFrame:Hide()
        self.picker:Show()
        self:RefreshPicker()
    else
        self.picker:Hide()
        self.detailFrame:Show()
        self:RefreshDetail(request)
    end

    GA.UI.MainFrame:SetContext(#alle > 0 and string.format(L.QH_CONTEXT, #alle) or "")
end

GA.UI.MainFrame:RegisterView("questhub", View)

GA.Core.Callbacks:On("QUESTHUB_CHANGED", function()
    if View.frame and View.frame:IsVisible() then View:Refresh() end
end, "QuesthubView")
