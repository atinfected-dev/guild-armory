--[[----------------------------------------------------------------------------
    UI/Views/GuildBank — was in der Gildenbank liegt (06.10.2026).

    Oben die Faecher als Reiter (Alle + jedes Fach) und eine Suche, darunter
    die Gegenstaende mit Anzahl und Fach. Darueber steht immer, wann und von
    wem gelesen wurde — ein Stand von gestern ist eine andere Auskunft als
    einer von eben. Die Daten kommen aus Armory/GuildBank.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

View.titleKey = "NAV_GUILDBANK"

local ROW_H = 22
local function columns()
    return {
        { key = "icon",  label = "",            width = 16 },
        { key = "name",  label = L.COL_ITEM,     width = 300 },
        { key = "count", label = L.GB_COL_COUNT, width = 64, justify = "RIGHT" },
        { key = "tab",   label = L.GB_COL_TAB },
    }
end
local X = { icon = 8, name = 30, count = 336, tab = 406 }

local function money(copper)
    copper = tonumber(copper)
    if not copper then return nil end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", g, s, c)
end

-- ================================================================== Aufbau ----

function View:Create(parent)
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.tab = 0          -- 0 = alle Faecher
    self.query = ""

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    bar:SetHeight(24)
    self.bar = bar
    self.tabChips = {}

    self.search = Widgets.SearchBox(bar, L.GB_SEARCH, function(text)
        View.query = string.lower(text or "")
        View:Refresh()
    end)
    self.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    self.search:SetWidth(220)

    self.status = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.status:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -6)
    self.status:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    self.status:SetJustifyH("LEFT")

    -- Sparziel (08.10.2026): ein Streifen ueber dem Vorrat. Was, wie viel,
    -- bis wann, der Balken dazu; rechts Setzen (wer darf) und Einzahlen
    -- (wer an der Bank steht).
    local goal = Widgets.Inset(frame)
    goal:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -26)
    goal:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -26)
    goal:SetHeight(58)
    self.goal = goal

    self.goalTitle = Theme.Label(goal, "", fonts.heading, Theme.color.goldBright)
    self.goalTitle:SetPoint("TOPLEFT", goal, "TOPLEFT", 12, -8)
    self.goalTitle:SetWordWrap(false)
    self.goalText = Theme.Label(goal, "", fonts.small, Theme.color.textDim)
    self.goalText:SetPoint("LEFT", self.goalTitle, "RIGHT", 10, 0)
    self.goalText:SetWordWrap(false)

    local track = CreateFrame("Frame", nil, goal)
    track:SetPoint("BOTTOMLEFT", goal, "BOTTOMLEFT", 12, 10)
    track:SetPoint("RIGHT", goal, "RIGHT", -230, 0)
    track:SetHeight(8)
    Theme.Fill(track, Theme.color.rowAltBg)
    Theme.Outline(track, Theme.color.border)
    self.goalTrack = track
    self.goalFill = track:CreateTexture(nil, "ARTWORK")
    Theme.BarFill(self.goalFill, Theme.color.gold)
    self.goalFill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
    self.goalFill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
    self.goalFill:SetWidth(1)
    self.goalState = Theme.Label(goal, "", fonts.small, Theme.color.textFaint)
    self.goalState:SetPoint("BOTTOMLEFT", track, "TOPLEFT", 0, 3)
    self.goalState:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    self.goalState:SetJustifyH("LEFT")
    self.goalState:SetWordWrap(false)

    self.goalSet = Widgets.Button(goal, L.TR_SET, function() View:EditGoal() end)
    self.goalSet:SetTooltip(L.TT_TR_SET)
    self.goalSet:SetHeight(20)
    self.goalSet:SetPoint("RIGHT", goal, "RIGHT", -10, 0)
    self.goalDeposit = Widgets.Button(goal, L.TR_DEPOSIT, function() View:DepositMenu() end, "primary")
    self.goalDeposit:SetTooltip(L.TT_TR_DEPOSIT)
    self.goalDeposit:SetHeight(20)
    self.goalDeposit:SetPoint("RIGHT", self.goalSet, "LEFT", -6, 0)

    local panel = Widgets.Panel(frame, L.NAV_GUILDBANK, "")
    panel:SetPoint("TOPLEFT", goal, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    self.panel = panel

    self.list = Widgets.ScrollList(panel.content, {
        rowHeight = ROW_H,
        columns = columns(),
        createRow = function(row) View:BuildRow(row) end,
        updateRow = function(row, entry) View:UpdateRow(row, entry) end,
        onEnterRow = function(row, entry) if entry.itemID then Widgets.ShowItemTooltip(row, entry.itemID) end end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.list:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
    self.list:SetPoint("BOTTOMRIGHT", panel.content, "BOTTOMRIGHT", 0, 0)

    self.empty = Theme.Label(panel.content, L.GB_EMPTY, fonts.body, Theme.color.textDim)
    self.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 24, -60)
    self.empty:SetPoint("RIGHT", panel.content, "RIGHT", -24, 0)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetSpacing(3)
    self.empty:Hide()

    GA.Core.Callbacks:On("GUILD_BANK_CHANGED", function()
        if View.frame and View.frame:IsVisible() then View:Refresh() end
    end, "GuildBankView")
    GA.Core.Callbacks:On("TREASURY_CHANGED", function()
        if View.frame and View.frame:IsVisible() then View:RefreshGoal() end
    end, "GuildBankView")

    self.frame = frame
    return frame
end

function View:BuildRow(row)
    local fonts = Theme.Fonts()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(16) row.icon:SetHeight(16)
    row.icon:SetPoint("LEFT", row, "LEFT", X.icon, 0)
    row.nameText = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.nameText:SetPoint("LEFT", row, "LEFT", X.name, 0)
    row.nameText:SetWidth(300)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)
    row.countText = Theme.Label(row, "", fonts.rowBold or fonts.row, Theme.color.heading)
    row.countText:SetPoint("LEFT", row, "LEFT", X.count, 0)
    row.countText:SetWidth(64)
    row.countText:SetJustifyH("RIGHT")
    row.tabText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.tabText:SetPoint("LEFT", row, "LEFT", X.tab, 0)
    row.tabText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.tabText:SetJustifyH("LEFT")
    row.tabText:SetWordWrap(false)
end

function View:UpdateRow(row, entry)
    local icon = Compat.GetItemIcon(entry.itemID)
    if icon and pcall(row.icon.SetTexture, row.icon, icon) then
        pcall(row.icon.SetTexCoord, row.icon, 0.08, 0.92, 0.08, 0.92)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    if entry.name then
        row.nameText:SetText(entry.name)
        local c = entry.quality and Theme.QualityColor(entry.quality) or Theme.color.text
        row.nameText:SetTextColor(c[1], c[2], c[3])
    else
        -- Noch nicht geladen ist nicht unbekannt: die Kennung, bis der Name da ist.
        row.nameText:SetText(string.format(L.SLASH_ITEM_FALLBACK, tostring(entry.itemID)))
        row.nameText:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end
    row.countText:SetText(tostring(entry.count))
    row.tabText:SetText(entry.tabs or "")
end

-- ================================================================== Inhalt ----

--- Reiter fuer die Faecher — neu gebaut, wenn sich die Faecher aendern.
function View:BuildTabChips(tabs)
    local sig = {}
    for _, tab in ipairs(tabs) do sig[#sig + 1] = tostring(tab.index) .. (tab.name or "") end
    sig = table.concat(sig, "|")
    if sig == self.tabSig then return end
    self.tabSig = sig
    for _, chip in ipairs(self.tabChips) do chip:Hide() end
    self.tabChips = {}
    local previous
    local entries = { { index = 0, name = L.GB_ALL } }
    for _, tab in ipairs(tabs) do entries[#entries + 1] = tab end
    for _, tab in ipairs(entries) do
        local chip = Widgets.Chip(self.bar, tab.name or ("#" .. tostring(tab.index)))
        chip:SetHeight(20)
        chip.tabIndex = tab.index
        chip:SetScript("OnClick", function(c) View.tab = c.tabIndex View:Refresh() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", self.bar, "LEFT", 0, 0) end
        self.tabChips[#self.tabChips + 1] = chip
        previous = chip
    end
end

function View:Refresh()
    if not self.frame then return end
    local data = GA.Modules.GuildBank and GA.Modules.GuildBank:Data() or {}
    local tabs = data.tabs or {}
    self:BuildTabChips(tabs)
    local known = false
    for _, chip in ipairs(self.tabChips) do
        chip:SetPressed(chip.tabIndex == self.tab)
        if chip.tabIndex == self.tab then known = true end
    end
    if not known then self.tab = 0 if self.tabChips[1] then self.tabChips[1]:SetPressed(true) end end

    -- Zusammenzaehlen: je Gegenstand die Anzahl, und in welchen Faechern er liegt.
    local byId, order = {}, {}
    for _, tab in ipairs(tabs) do
        if self.tab == 0 or self.tab == tab.index then
            for id, count in pairs(tab.items or {}) do
                local e = byId[id]
                if not e then
                    local info = Compat.GetItemInfo(id)
                    e = { itemID = id, count = 0, tabList = {}, name = info and info.name, quality = info and info.quality }
                    byId[id] = e
                    order[#order + 1] = e
                end
                e.count = e.count + count
                e.tabList[#e.tabList + 1] = tab.name or ("#" .. tostring(tab.index))
            end
        end
    end
    local list, total = {}, 0
    for _, e in ipairs(order) do
        e.tabs = table.concat(e.tabList, ", ")
        local name = string.lower(e.name or "")
        if self.query == "" or string.find(name, self.query, 1, true) then
            list[#list + 1] = e
            total = total + e.count
        end
    end
    table.sort(list, function(a, b)
        if (a.name ~= nil) ~= (b.name ~= nil) then return a.name ~= nil end
        if a.name and b.name and a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    self.list:SetData(list)

    local hasData = #tabs > 0
    self.empty:SetShown(not hasData or #list == 0)
    self.empty:SetText(hasData and L.GB_NONE or L.GB_EMPTY)
    local parts = {}
    if data.ts then parts[#parts + 1] = string.format(L.GB_READ, Util.TimeAgo(data.ts), data.by or "?") end
    local m = money(data.money)
    if m then parts[#parts + 1] = string.format(L.GB_MONEY, m) end
    self.status:SetText(table.concat(parts, "  ·  "))
    self.panel:SetTitle(L.NAV_GUILDBANK)
    GA.UI.MainFrame:SetContext(hasData and string.format(L.GB_CONTEXT, #list, #tabs) or "")
    self:RefreshGoal()
end

-- ================================================================ Sparziel --

local GOAL_FIELDS = {
    { key = "title", label = L.TR_F_TITLE },
    { key = "amount", label = L.TR_F_AMOUNT, hint = L.TR_F_AMOUNT_HINT },
    { key = "deadline", label = L.TR_F_DEADLINE, hint = L.TR_F_DEADLINE_HINT },
    { key = "note", label = L.TR_F_NOTE },
}

function View:EditGoal()
    local T = GA.Modules.Treasury
    local goal = T:Goal()
    local values = goal and {
        title = goal.title, amount = string.format("%d", math.floor(goal.amount / 10000)),
        deadline = goal.deadline and date("%d.%m.%Y", goal.deadline) or "", note = goal.note,
    } or { amount = "", deadline = "", note = "" }
    Widgets.FormDialog("treasuryGoal", L.TR_TITLE, GOAL_FIELDS, values, function(v)
        local amount = T.ParseGold(v.amount)
        if not amount or amount <= 0 then return false, L.TR_ERR_amount end
        local deadline, ok = GA.Modules.RaidPlan.ParseStart(v.deadline, "23:59")
        if not ok then return false, L.TR_ERR_deadline end
        -- Ein anderer Titel ist ein neues Ziel: Grundlinie neu ab jetzt.
        local restart = goal ~= nil and (v.title or "") ~= (goal.title or "")
        local saved, why = T:SetGoal({ title = v.title, amount = amount, deadline = deadline, note = v.note, restart = restart })
        if not saved then return false, L["TR_ERR_" .. tostring(why)] or tostring(why) end
        View:RefreshGoal()
        return true
    end, goal and function() T:RemoveGoal() View:RefreshGoal() end or nil)
end

function View:DepositMenu()
    local T = GA.Modules.Treasury
    local items = {}
    local change = T:SmallChange()
    if change then
        items[#items + 1] = { text = string.format(L.TR_DEPOSIT_CHANGE, T.Money(change)),
            func = function() View:Deposit(change) end }
    end
    items[#items + 1] = { text = L.TR_DEPOSIT_AMOUNT, func = function()
        Widgets.InputDialog(L.TR_DEPOSIT, L.TR_DEPOSIT_PROMPT, function(text)
            local copper = T.ParseGold(text)
            if not copper or copper <= 0 then return false, L.TR_ERR_amount end
            View:Deposit(copper)
            return true
        end)
    end }
    Widgets.ContextMenu(L.TR_DEPOSIT, items)
end

function View:Deposit(copper)
    local T = GA.Modules.Treasury
    local ok, why = T:Deposit(copper)
    if ok then
        GA.UI.MainFrame:Notice("info", L.TR_DEPOSIT_DONE, T.Money(copper))
    else
        GA.UI.MainFrame:Notice("warn", L["TR_DEPOSIT_ERR_" .. tostring(why)] or tostring(why), T.Money(copper))
    end
end

--- Der Streifen: Ziel, Stand, Balken, Knoepfe.
function View:RefreshGoal()
    if not self.frame then return end
    local T = GA.Modules.Treasury
    local goal = T:Goal()
    local canEdit = T:CanEdit()
    self.goalSet:SetShown(canEdit)
    self.goalSet:SetLabel(goal and L.TR_EDIT or L.TR_SET)
    local bankOpen = GA.Modules.GuildBank and GA.Modules.GuildBank.open or false
    self.goalDeposit:SetEnabledState(bankOpen, L.TR_DEPOSIT_CLOSED)

    if not goal then
        self.goalTitle:SetText(L.TR_TITLE)
        self.goalText:SetText(canEdit and L.TR_NONE_EDIT or L.TR_NONE)
        self.goalState:SetText("")
        self.goalFill:SetWidth(1)
        return
    end
    local p = T:Progress()
    self.goalTitle:SetText(goal.title)
    local parts = { string.format(L.TR_PROGRESS, T.Money(p.raised), T.Money(goal.amount)) }
    if goal.deadline then parts[#parts + 1] = string.format(L.TR_DEADLINE, date("%d.%m.%Y", goal.deadline)) end
    if goal.note and goal.note ~= "" then parts[#parts + 1] = goal.note end
    self.goalText:SetText(table.concat(parts, "  ·  "))

    local width = self.goalTrack:GetWidth() or 200
    self.goalFill:SetWidth(math.max(1, (width - 2) * (p.ratio or 0)))
    local state, color
    if not p.known then
        state, color = L.TR_STAND_UNKNOWN, Theme.color.warn
    else
        local stand = string.format(L.TR_STAND_FROM, Util.TimeAgo(p.ts), p.by or "?")
        local word = L["TR_STATE_" .. string.upper(p.state)] or p.state
        if p.daysLeft and p.state ~= "reached" and p.state ~= "overdue" then
            word = word .. "  ·  " .. string.format(L.TR_DAYS_LEFT, p.daysLeft)
        end
        state = word .. "  ·  " .. stand
        color = (p.state == "reached" and Theme.color.jade) or (p.state == "behind" and Theme.color.warn)
            or (p.state == "overdue" and Theme.color.bad) or Theme.color.textDim
    end
    self.goalState:SetText(state)
    self.goalState:SetTextColor(color[1], color[2], color[3])
end

function View:OnShow() self:Refresh() self:RefreshGoal() end

GA.UI.MainFrame:RegisterView("guildbank", View)
