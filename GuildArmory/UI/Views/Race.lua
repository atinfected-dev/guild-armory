--[[----------------------------------------------------------------------------
    Views/Race — Rennen zur Hoechststufe: die Rangliste der Gilde.

    Oben die Ersten (gesamt und je Klasse, nur live gesehene), darunter die
    Liste: Platz, Wappen, Name, Stufe mit XP-Balken, Spielzeit, letzter
    Aufstieg, und bei den Fertigen, seit wann. Chips: alle, meine Klasse,
    nur online. Daten aus Armory/Race.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

View.titleKey = "NAV_RACE"

local ROW_H = 26
local BAR_W = 60
local X = { pos = 8, crest = 36, name = 62, level = 240, bar = 272, played = 350, ding = 450, finish = 560 }

function View:Create(parent)
    local fonts = Theme.Fonts()
    local pad = 4
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.filter = {}

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(20)
    self.chips = {}
    local previous
    for _, spec in ipairs({ { key = "all", label = L.RACE_ALL }, { key = "class", label = L.RACE_MY_CLASS }, { key = "online", label = L.RACE_ONLINE } }) do
        local chip = Widgets.Chip(bar, spec.label, function()
            View.mode = spec.key
            View:Refresh()
        end)
        chip:SetHeight(20)
        chip.key = spec.key
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 4, 0) else chip:SetPoint("LEFT", bar, "LEFT", 0, 0) end
        self.chips[#self.chips + 1] = chip
        previous = chip
    end
    self.mode = "all"

    self.myPlace = Theme.Label(bar, "", fonts.body, Theme.color.goldBright)
    self.myPlace:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    -- Die Ersten
    local head = Widgets.Inset(frame)
    head:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    head:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    head:SetHeight(58)
    self.first = Theme.Label(head, "", fonts.heading, Theme.color.goldBright)
    self.first:SetPoint("TOPLEFT", head, "TOPLEFT", 12, -8)
    self.first:SetPoint("RIGHT", head, "RIGHT", -12, 0)
    self.first:SetJustifyH("LEFT")
    self.first:SetWordWrap(false)
    self.classFirst = Theme.Label(head, "", fonts.small, Theme.color.textDim)
    self.classFirst:SetPoint("TOPLEFT", self.first, "BOTTOMLEFT", 0, -4)
    self.classFirst:SetPoint("RIGHT", head, "RIGHT", -12, 0)
    self.classFirst:SetJustifyH("LEFT")
    self.classFirst:SetSpacing(2)

    local panel = Widgets.Panel(frame, L.NAV_RACE)
    panel:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.panel = panel

    self.list = Widgets.ScrollList(panel.content, {
        emptyText = L.RACE_EMPTY,
        rowHeight = ROW_H,
        createRow = function(row) View:BuildRow(row) end,
        updateRow = function(row, entry) View:UpdateRow(row, entry) end,
    })
    self.list:SetAllPoints(panel.content)

    GA.Core.Callbacks:On("RACE_CHANGED", function() if View.frame and View.frame:IsVisible() then View:Refresh() end end, "RaceView")
    GA.Core.Callbacks:On("GUILD_UPDATED", function() if View.frame and View.frame:IsVisible() then View:Refresh() end end, "RaceView")

    self.frame = frame
    return frame
end

function View:BuildRow(row)
    local fonts = Theme.Fonts()
    row.pos = Theme.Label(row, "", fonts.rowBold, Theme.color.goldDim)
    row.pos:SetPoint("LEFT", row, "LEFT", X.pos, 0)
    row.pos:SetWidth(24)
    row.pos:SetJustifyH("RIGHT")
    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(20) row.crest:SetHeight(20)
    row.crest:SetPoint("LEFT", row, "LEFT", X.crest, 0)
    row.name = Theme.Label(row, "", fonts.rowBold, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", X.name, 0)
    row.name:SetWidth(X.level - X.name - 6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.level = Theme.Label(row, "", fonts.rowBold, Theme.color.heading)
    row.level:SetPoint("LEFT", row, "LEFT", X.level, 0)
    row.level:SetWidth(26)
    row.level:SetJustifyH("RIGHT")
    row.trough = row:CreateTexture(nil, "ARTWORK")
    Theme.BarTrough(row.trough)
    row.trough:SetWidth(BAR_W) row.trough:SetHeight(5)
    row.trough:SetPoint("LEFT", row, "LEFT", X.bar, 0)
    row.fill = row:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(row.fill, Theme.color.gold)
    row.fill:SetHeight(5)
    row.fill:SetPoint("LEFT", row.trough, "LEFT", 0, 0)
    row.fill:SetWidth(1)
    row.played = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.played:SetPoint("LEFT", row, "LEFT", X.played, 0)
    row.played:SetWidth(X.ding - X.played - 6)
    row.played:SetJustifyH("LEFT")
    row.ding = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.ding:SetPoint("LEFT", row, "LEFT", X.ding, 0)
    row.ding:SetWidth(X.finish - X.ding - 6)
    row.ding:SetJustifyH("LEFT")
    row.finish = Theme.Label(row, "", fonts.small, Theme.color.jade)
    row.finish:SetPoint("LEFT", row, "LEFT", X.finish, 0)
    row.finish:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.finish:SetJustifyH("LEFT")
    row.finish:SetWordWrap(false)
end

function View:UpdateRow(row, e)
    row.pos:SetText(tostring(e.position))
    if e.class and Theme.SetClassPortrait(row.crest, e.class) then row.crest:Show() else row.crest:Hide() end
    local r, g, b = Theme.ClassColor(e.class)
    row.name:SetText(Util.ShortName(e.name) .. (e.me and ("  " .. L.RACE_ME) or ""))
    row.name:SetTextColor(r, g, b)
    row:SetAlpha(e.online and 1 or 0.6)
    row.level:SetText(tostring(e.level))
    if e.finish then
        row.trough:Hide() row.fill:Hide()
    else
        row.trough:Show() row.fill:Show()
        row.fill:SetWidth(math.max(1, BAR_W * math.min(1, (e.pct or 0) / 100)))
    end
    local F = GA.Modules.Leveling and GA.Modules.Leveling.FormatDuration
    row.played:SetText(e.played and F and F(e.played) or "")
    row.ding:SetText(e.lastDing and string.format(L.RACE_LAST_DING, e.lastDing.level, Util.TimeAgo(e.lastDing.ts)) or "")
    if e.finish then
        if e.how == "before" then row.finish:SetText(L.RACE_BEFORE)
        elseif e.how == "live" then row.finish:SetText(string.format(L.RACE_LIVE, Util.TimeAgo(e.finish.at)))
        else row.finish:SetText(string.format(L.RACE_BY, Util.TimeAgo(e.finish.at))) end
    else
        row.finish:SetText("")
    end
end

function View:Refresh()
    if not self.frame then return end
    local Race = GA.Modules.Race
    for _, chip in ipairs(self.chips) do chip:SetPressed(chip.key == self.mode) end
    local filter = {}
    local identity = Compat.GetPlayerIdentity()
    if self.mode == "class" then filter.class = identity.class end
    if self.mode == "online" then filter.online = true end
    local rows = Race:Board(filter)
    self.list:SetData(rows)

    local pos, total = Race:MyPosition()
    self.myPlace:SetText(pos and string.format(L.RACE_MY_PLACE, pos, total) or "")

    local first, classFirst, since = Race:Firsts()
    local max = Race:MaxLevel()
    if first then
        self.first:SetText(string.format(L.RACE_FIRST, max, Theme.ColorByClass(first.name, first.class), Util.TimeAgo(first.at)))
    else
        self.first:SetText(string.format(L.RACE_NO_FIRST, max, since and Util.TimeAgo(since) or "?"))
    end
    local parts = {}
    for class, e in pairs(classFirst or {}) do
        local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[class] or class
        parts[#parts + 1] = name .. ": " .. Theme.ColorByClass(e.name, e.class)
    end
    table.sort(parts)
    self.classFirst:SetText(#parts > 0 and (L.RACE_CLASS_FIRSTS .. "  " .. table.concat(parts, "  ·  ")) or L.RACE_CLASS_NONE)

    local done = 0
    for _, r in ipairs(rows) do if r.finish then done = done + 1 end end
    self.panel:SetTitle(string.format(L.RACE_TITLE, done, #rows, max))
    GA.UI.MainFrame:SetContext(pos and string.format(L.RACE_MY_PLACE, pos, total) or "")
end

function View:OnShow() self:Refresh() end

GA.UI.MainFrame:RegisterView("race", View)
