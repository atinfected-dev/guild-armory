--[[----------------------------------------------------------------------------
    Views/Dungeonhub — Heute und Morgen als Karten, rechts das Formular
    (Entwurf H2, 29.09.2026).

    Links zwei Spalten: die Laeufe von heute, die von morgen. Jede Karte
    traegt Uhrzeit, Dungeon, Leiter, die Notiz, die fuenf Plaetze als
    Kaestchen — belegt mit Name in Klassenfarbe, offen gestrichelt in der
    Rollenfarbe — und darunter "Beitreten als" mit den freien Rollen, oder
    "Du bist drin als …" mit Verlassen, oder fuer den Leiter Zuruecknehmen
    und Gruppe einladen. Rechts steht immer das Formular: Dungeon, Tag,
    Uhrzeit, Notiz, eigene Rolle, ein Knopf.

    Was ein Lauf IST und wie er durch die Gilde geht, steht in
    Quests/Dungeonhub.lua. Hier wird nur gezeichnet.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

View.titleKey = "NAV_DUNGEONHUB"

local FORM_W = 290
local CARD_H = 158
local CARD_GAP = 10

--- Die Rollenfarben: Tank blau, Heiler gruen, Schaden rot — verschieden in
--- Helligkeit, nicht nur im Ton.
local ROLE_COLOR = {
    TANK = { 0.36, 0.55, 0.84 },
    HEAL = { 0.30, 0.69, 0.31 },
    DPS  = { 0.78, 0.25, 0.18 },
}
local ROLE_LETTER = { TANK = "T", HEAL = "H", DPS = "D" }

local function editBox(parent, width, onEnter)
    local box = Theme.CreateNative("EditBox", nil, parent, "InputBoxTemplate")
    if not box then
        box = CreateFrame("EditBox", nil, parent)
        Theme.Fill(box, Theme.color.windowBg)
        Theme.Outline(box, Theme.color.border)
        box:SetFontObject(Theme.Fonts().row)
        box:SetTextInsets(6, 6, 0, 0)
    end
    box:SetWidth(width or 100)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() if onEnter then onEnter() end end)
    return box
end

local function roleName(role)
    return L["DH_ROLE_" .. role] or role
end

-- ================================================================== Aufbau ----

function View:Create(parent)
    local fonts = Theme.Fonts()
    local pad = 4
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame
    self.cards = {}

    -- ------------------------------------------------------- Formular -------
    local form = Widgets.Inset(frame)
    form:SetWidth(FORM_W)
    form:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    form:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.form = form

    local y = -14
    local function caption(text)
        local label = Theme.Label(form, text, fonts.small, Theme.color.textDim)
        label:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y)
        y = y - 16
        return label
    end

    local head = Theme.Label(form, L.DH_POST_HEAD, fonts.title, Theme.color.heading)
    head:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y)
    y = y - 26

    caption(L.DH_DUNGEON)
    -- FREI EINTIPPBAR, die Liste ist ein Vorschlag: Forever hat Instanzen,
    -- die keine feste Liste kennt (29.09.2026). Die Liste kommt aus dem
    -- Kompendium des Clients, dahinter die klassische.
    self.dungeonBox = editBox(form, FORM_W - 28 - 74, nil)
    self.dungeonBox:SetPoint("TOPLEFT", form, "TOPLEFT", 18, y)
    self.dungeonBox:SetMaxLetters(GA.Modules.Dungeonhub.DUNGEON_LEN)
    self.dungeonPick = Widgets.Dropdown(form, {
        width = 70, placeholder = L.DH_DUNGEON_LIST,
        popupWidth = FORM_W - 28, popupAnchor = "RIGHT",
        getOptions = function()
            local out = {}
            local levels = GA.Modules.Dungeonhub.LEVELS
            for _, name in ipairs((GA.Modules.Dungeonhub:Dungeons())) do
                out[#out + 1] = { text = levels[name] and (name .. "  " .. levels[name]) or name, value = name }
            end
            return out
        end,
        onSelect = function(value)
            View.dungeonBox:SetText(value)
            View.dungeonPick:SetDisplay(L.DH_DUNGEON_LIST, Theme.color.textFaint)
        end,
    })
    self.dungeonPick:SetPoint("LEFT", self.dungeonBox, "RIGHT", 6, 0)
    y = y - 30

    caption(L.DH_DAY)
    self.dayChips = {}
    local previous
    for offset = 0, 1 do
        local chip = Widgets.Chip(form, offset == 0 and L.DH_TODAY or L.DH_TOMORROW, function()
            View.dayOffset = offset
            View:RefreshForm()
        end)
        chip:SetHeight(20)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else chip:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y) end
        chip.offset = offset
        self.dayChips[#self.dayChips + 1] = chip
        previous = chip
    end
    local timeCaption = Theme.Label(form, L.DH_TIME, fonts.small, Theme.color.textDim)
    timeCaption:SetPoint("LEFT", previous, "RIGHT", 16, 0)
    self.timeBox = editBox(form, 60, function() View:RefreshForm() end)
    self.timeBox:SetPoint("LEFT", timeCaption, "RIGHT", 8, 0)
    self.timeBox:SetText("20:00")
    y = y - 30

    caption(L.DH_NOTE)
    self.noteBox = editBox(form, FORM_W - 34, nil)
    self.noteBox:SetPoint("TOPLEFT", form, "TOPLEFT", 18, y)
    self.noteBox:SetMaxLetters(GA.Modules.Dungeonhub.NOTE_LEN)
    y = y - 30

    caption(L.DH_YOUR_ROLE)
    self.roleChips = {}
    previous = nil
    for _, role in ipairs(GA.Modules.Dungeonhub.ROLES) do
        local chip = Widgets.Chip(form, roleName(role), function()
            View.role = role
            View:RefreshForm()
        end)
        chip:SetHeight(20)
        chip:SetWidth(math.floor((FORM_W - 28 - 8) / 3))
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else chip:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y) end
        chip.role = role
        self.roleChips[#self.roleChips + 1] = chip
        previous = chip
    end
    y = y - 32

    self.postButton = Widgets.Button(form, L.DH_POST_BTN, function() View:Post() end, "primary")
    self.postButton:SetHeight(24)
    self.postButton:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y)
    self.postButton:SetPoint("RIGHT", form, "RIGHT", -14, 0)
    y = y - 32

    self.formHint = Theme.Label(form, L.DH_POST_HINT, fonts.small, Theme.color.textDim)
    self.formHint:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y)
    self.formHint:SetPoint("RIGHT", form, "RIGHT", -14, 0)
    self.formHint:SetJustifyH("LEFT")
    self.formHint:SetSpacing(2)

    self.formError = Theme.Label(form, "", fonts.small, Theme.color.warn)
    self.formError:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 36)
    self.formError:SetPoint("RIGHT", form, "RIGHT", -14, 0)
    self.formError:SetJustifyH("LEFT")

    self.notifyState = Theme.Label(form, "", fonts.small, Theme.color.textFaint)
    self.notifyState:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 14)
    self.notifyState:SetPoint("RIGHT", form, "RIGHT", -14, 0)
    self.notifyState:SetJustifyH("LEFT")

    -- ------------------------------------------------------- Karten ---------
    self.scroll = Widgets.ScrollArea(frame)
    self.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    self.scroll:SetPoint("BOTTOMRIGHT", form, "BOTTOMLEFT", -8, 0)
    local content = self.scroll.content

    self.todayHead = Theme.Label(content, string.upper(L.DH_TODAY), fonts.heading, Theme.color.goldDim)
    self.todayHead:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
    self.tomorrowHead = Theme.Label(content, string.upper(L.DH_TOMORROW), fonts.heading, Theme.color.goldDim)
    self.tomorrowHead:SetPoint("TOP", content, "TOP", 0, -8)
    self.tomorrowHead:SetPoint("LEFT", content, "CENTER", 10, 0)

    self.todayNone = Theme.Label(content, L.DH_NONE_TODAY, fonts.small, Theme.color.textFaint)
    self.todayNone:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -30)
    self.tomorrowNone = Theme.Label(content, L.DH_NONE_TOMORROW, fonts.small, Theme.color.textFaint)
    self.tomorrowNone:SetPoint("TOPLEFT", content, "TOP", 10, -30)

    self.dayOffset = 0
    self.role = GA.Modules.Dungeonhub:LastRole()
    return frame
end

--- Eine Karte aus dem Vorrat.
function View:Card(index)
    if self.cards[index] then return self.cards[index] end
    local fonts = Theme.Fonts()
    local card = Widgets.Inset(self.scroll.content)
    card:SetHeight(CARD_H)

    card.time = Theme.Label(card, "", fonts.big, Theme.color.goldBright)
    card.time:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card.dungeon = Theme.Label(card, "", fonts.body, Theme.color.text)
    card.dungeon:SetPoint("LEFT", card.time, "RIGHT", 10, -1)
    card.leader = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.leader:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -14)
    card.leader:SetJustifyH("RIGHT")
    card.line = Theme.Fill(card, Theme.color.border)
    card.line:ClearAllPoints()
    card.line:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -36)
    card.line:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -36)
    card.line:SetHeight(1)
    card.note = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -44)
    card.note:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.note:SetJustifyH("LEFT")
    card.note:SetWordWrap(false)

    -- Die fuenf Plaetze: Kaestchen mit Rollenbuchstabe im Kreis und Name.
    card.slots = {}
    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, card)
        slot:SetHeight(44)
        slot.fill = Theme.Fill(slot, Theme.color.rowAltBg)
        slot.lines = Theme.Outline(slot, Theme.color.border)
        slot.disc = slot:CreateTexture(nil, "ARTWORK")
        slot.disc:SetSize(18, 18)
        slot.disc:SetPoint("TOP", slot, "TOP", 0, -5)
        if Theme.TextureExists("Interface\\AddOns\\GuildArmory\\Media\\Circle.tga") then
            slot.disc:SetTexture("Interface\\AddOns\\GuildArmory\\Media\\Circle.tga")
        end
        slot.letter = Theme.Label(slot, "", fonts.small, Theme.color.windowBg)
        slot.letter:SetPoint("CENTER", slot.disc, "CENTER", 0, 0)
        slot.name = Theme.Label(slot, "", fonts.small, Theme.color.text)
        slot.name:SetPoint("TOP", slot.disc, "BOTTOM", 0, -3)
        slot.name:SetPoint("LEFT", slot, "LEFT", 2, 0)
        slot.name:SetPoint("RIGHT", slot, "RIGHT", -2, 0)
        slot.name:SetJustifyH("CENTER")
        slot.name:SetWordWrap(false)
        card.slots[i] = slot
    end

    card.action = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.action:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 12)
    card.buttons = {}
    for i = 1, 3 do
        local button = Widgets.FlatButton(card, "", nil)
        button:SetHeight(20)
        button:Hide()
        card.buttons[i] = button
    end
    card.whisper = Widgets.FlatButton(card, L.DH_WHISPER, function()
        if card.run then Compat.OpenWhisper(card.run.leader) end
    end)
    card.whisper:SetHeight(18)
    card.whisper:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 12)

    self.cards[index] = card
    return card
end

--- Fuellt eine Karte mit einem Lauf.
function View:FillCard(card, run)
    local Hub = GA.Modules.Dungeonhub
    card.run = run
    card.time:SetText(date("%H:%M", run.at or 0))
    card.dungeon:SetText(run.dungeon or "?")
    card.leader:SetText(Util.ColorByClass(run.leader or "?", run.class))

    local teile = {}
    if run.note and run.note ~= "" then teile[#teile + 1] = run.note end
    teile[#teile + 1] = string.format(L.DH_POSTED_AGO, Util.TimeAgo(run.ts or 0))
    card.note:SetText(table.concat(teile, " · "))

    local width = (card:GetWidth() or 300) - 24
    local slotW = math.floor((width - 4 * 4) / 5)
    for i, slot in ipairs(Hub:Slots(run)) do
        local box = card.slots[i]
        box:ClearAllPoints()
        box:SetWidth(slotW)
        box:SetPoint("TOPLEFT", card, "TOPLEFT", 12 + (i - 1) * (slotW + 4), -62)
        local color = ROLE_COLOR[slot.role]
        box.letter:SetText(ROLE_LETTER[slot.role])
        if slot.name then
            Theme.Paint(box.disc, color)
            box.letter:SetTextColor(Theme.color.windowBg[1], Theme.color.windowBg[2], Theme.color.windowBg[3])
            local me = Compat.GetPlayerIdentity().name
            local mine = me and Util.ShortName(me) == slot.name
            box.name:SetText(mine and L.DH_YOU or slot.name)
            local r, g, b = Util.ClassColor(slot.class)
            if mine then r, g, b = Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3] end
            box.name:SetTextColor(r, g, b)
            for _, line in ipairs(box.lines) do Theme.Paint(line, mine and Theme.color.goldDim or Theme.color.border) end
            Theme.Paint(box.fill, mine and Theme.color.goldDeep or Theme.color.rowAltBg)
        else
            Theme.Paint(box.disc, { color[1] * 0.45, color[2] * 0.45, color[3] * 0.45 })
            box.letter:SetTextColor(color[1], color[2], color[3])
            box.name:SetText(L.DH_OPEN)
            box.name:SetTextColor(color[1], color[2], color[3])
            for _, line in ipairs(box.lines) do Theme.Paint(line, { color[1] * 0.6, color[2] * 0.6, color[3] * 0.6 }) end
            Theme.Paint(box.fill, Theme.color.rowAltBg)
        end
    end

    -- Die Handlungszeile: je nach dem, wer ich in diesem Lauf bin.
    for _, button in ipairs(card.buttons) do button:Hide() end
    local me = Compat.GetPlayerIdentity().name
    me = me and Util.ShortName(me)
    local mine = Hub:MyRole(run)
    local function place(index, text, onClick, anchorTo)
        local button = card.buttons[index]
        button:SetLabel(text)
        button:SetScript("OnClick", onClick)
        button:ClearAllPoints()
        if anchorTo then button:SetPoint("LEFT", anchorTo, "RIGHT", 4, 0)
        else button:SetPoint("LEFT", card.action, "RIGHT", 8, 0) end
        button:Show()
        return button
    end
    if run.own then
        card.action:SetText(string.format(L.DH_IN_AS, roleName(mine or "DPS")) .. " · " .. L.DH_LEADER)
        local b = place(1, L.DH_WITHDRAW, function() Hub:Withdraw(run.id) end)
        place(2, L.DH_INVITE, function() Hub:InviteAll(run) end, b)
    elseif mine then
        card.action:SetText(string.format(L.DH_IN_AS, roleName(mine)))
        place(1, L.DH_LEAVE, function()
            local ok, grund = Hub:Leave(run.id)
            if not ok then GA.Core.Debug:Info("%s", L["DH_ERR_" .. tostring(grund)] or tostring(grund)) end
        end)
    else
        card.action:SetText(Hub:IsFull(run) and L.DH_FULL or L.DH_JOIN_AS)
        local previous
        local index = 0
        for _, role in ipairs(Hub.ROLES) do
            if Hub:CanJoin(run, role) then
                index = index + 1
                if index <= 3 then
                    previous = place(index, roleName(role), function()
                        local ok, grund = Hub:Join(run.id, role)
                        if not ok then GA.Core.Debug:Info("%s", L["DH_ERR_" .. tostring(grund)] or tostring(grund)) end
                    end, previous)
                end
            end
        end
    end
    card.whisper:SetShown(not run.own)
end

-- ================================================================== Inhalt ----

--- Traegt den Lauf aus dem Formular ein.
function View:Post()
    local Hub = GA.Modules.Dungeonhub
    self.formError:SetText("")
    local dungeon = (self.dungeonBox:GetText() or ""):gsub("^%s*(.-)%s*$", "%1")
    if dungeon == "" then
        self.formError:SetText(L.DH_ERR_nodungeon)
        return
    end
    local hh, mm = Hub.ParseClock(self.timeBox:GetText())
    if not hh then self.formError:SetText(L.DH_ERR_time) return end
    local at, grund = Hub.StartTime(self.dayOffset or 0, hh, mm)
    if not at then self.formError:SetText(L["DH_ERR_" .. tostring(grund)] or tostring(grund)) return end
    local run, reason = Hub:Post(dungeon, at, self.noteBox:GetText(), self.role or "DPS")
    if not run then
        self.formError:SetText(L["DH_ERR_" .. tostring(reason)] or tostring(reason))
        return
    end
    GA.Core.Debug:Info(L.DH_POSTED, run.dungeon, date("%H:%M", run.at))
    self.noteBox:SetText("")
    self:Refresh()
end

function View:RefreshForm()
    for _, chip in ipairs(self.dayChips) do chip:SetPressed(chip.offset == (self.dayOffset or 0)) end
    for _, chip in ipairs(self.roleChips) do chip:SetPressed(chip.role == self.role) end
    self.dungeonPick:SetDisplay(L.DH_DUNGEON_LIST, Theme.color.textFaint)
    local on = GA.Core.Config:Get("notifyEnabled") ~= false and GA.Core.Config:Get("notifyDungeon") ~= false
    self.notifyState:SetText(string.format(L.DH_NOTIFY_STATE, on and L.SET_ON or L.SET_OFF))
end

function View:OnShow() self:Refresh() end

function View:Refresh()
    if not self.frame then return end
    local Hub = GA.Modules.Dungeonhub
    self:RefreshForm()

    -- Heute und morgen nach dem Kalendertag der Startzeit, nicht nach
    -- "in weniger als 24 Stunden": Ein Lauf um 01:00 ist morgen.
    local today = date("%Y-%m-%d", Util.Now())
    local columns = { {}, {} }
    for _, run in ipairs(Hub:List()) do
        local tag = date("%Y-%m-%d", run.at or 0)
        if tag == today then columns[1][#columns[1] + 1] = run
        else columns[2][#columns[2] + 1] = run end
    end

    local content = self.scroll.content
    local width = (content:GetWidth() or 600)
    local columnW = math.floor((width - 6 - 10 - 12) / 2)
    local used = 0
    local tallest = 0
    for c, list in ipairs(columns) do
        local x = c == 1 and 6 or (6 + columnW + 12)
        for i, run in ipairs(list) do
            used = used + 1
            local card = self:Card(used)
            card:ClearAllPoints()
            card:SetWidth(columnW)
            card:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(30 + (i - 1) * (CARD_H + CARD_GAP)))
            card:Show()
            self:FillCard(card, run)
        end
        tallest = math.max(tallest, #list)
    end
    for i = used + 1, #self.cards do self.cards[i]:Hide() end
    self.todayNone:SetShown(#columns[1] == 0)
    self.tomorrowNone:SetShown(#columns[2] == 0)
    content:SetHeight(math.max(1, 30 + tallest * (CARD_H + CARD_GAP) + 10))
    self.scroll:Refresh()

    GA.UI.MainFrame:SetContext(string.format(L.DH_CONTEXT, #columns[1] + #columns[2]))
end

GA.UI.MainFrame:RegisterView("dungeonhub", View)

GA.Core.Callbacks:On("DUNGEONHUB_CHANGED", function()
    if View.frame and View.frame:IsVisible() then View:Refresh() end
end, "DungeonhubView")
