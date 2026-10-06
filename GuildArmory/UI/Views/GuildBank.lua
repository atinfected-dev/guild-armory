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

    local panel = Widgets.Panel(frame, L.NAV_GUILDBANK, "")
    panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -26)
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
end

function View:OnShow() self:Refresh() end

GA.UI.MainFrame:RegisterView("guildbank", View)
