--[[----------------------------------------------------------------------------
    UI/Views/Together — "Was koennen wir zusammen machen?" (07.10.2026).

    Links Dungeon-Gruppen aus den Online-Mitgliedern, als Karten: Dungeon
    mit Stufenspanne, fuenf Zeilen mit Haken oder Kreis, Rolle, Name, Stufe —
    eine geratene Rolle traegt ein Fragezeichen —, darunter "Lauf eintragen"
    und "Alle einladen". Rechts die Dungeon-, Elite- und Gruppenquests, die
    mehrere Online-Mitglieder gerade offen haben. Oben die eigene Rolle zum
    Setzen: Sie wird gesynct, und die Vorschlaege aller werden damit besser.

    Die Logik steht in Quests/Together.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local L = GA.L

View.titleKey = "NAV_TOGETHER"

local CARDS = 5
local CARD_H = 24 + 5 * 16 + 34
local ROW_H = 22

local function together() return GA.Modules.Together end

-- ================================================================== Aufbau ----

function View:Create(parent)
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    bar:SetHeight(24)

    -- Die eigene Rolle: drei Chips, einer gedrueckt oder keiner.
    local roleLabel = Theme.Label(bar, L.TG_MY_ROLE, fonts.small, Theme.color.textDim)
    roleLabel:SetPoint("LEFT", bar, "LEFT", 2, 0)
    self.roleChips = {}
    local previous = roleLabel
    for _, role in ipairs(together().ROLES) do
        local chip = Widgets.Chip(bar, L["DH_ROLE_" .. role])
        chip:SetHeight(18)
        chip:SetPoint("LEFT", previous, "RIGHT", previous == roleLabel and 8 or 4, 0)
        chip.role = role
        chip:SetScript("OnClick", function(c)
            local current = View.MyRole()
            together():SetMyRole(current == c.role and nil or c.role)
            View:Refresh()
        end)
        self.roleChips[role] = chip
        previous = chip
    end
    self.roleHint = Theme.Label(bar, L.TG_ROLE_HINT, fonts.small, Theme.color.textFaint)
    self.roleHint:SetPoint("LEFT", previous, "RIGHT", 10, 0)

    self.refreshButton = Widgets.Button(bar, L.TG_REFRESH, function() View:Refresh() end, "primary")
    self.refreshButton:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

    self.status = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.status:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -6)
    self.status:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    self.status:SetJustifyH("LEFT")

    -- Links: Gruppen.
    local groups = Widgets.Panel(frame, L.TG_GROUPS, "")
    groups:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -26)
    groups:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    groups:SetPoint("RIGHT", frame, "CENTER", 40, 0)
    self.groupsPanel = groups
    self.groupScroll = Widgets.ScrollArea(groups.content)
    self.groupScroll:SetAllPoints(groups.content)
    self.cards = {}
    for i = 1, CARDS do
        local card = CreateFrame("Frame", nil, self.groupScroll.content)
        card:SetHeight(CARD_H)
        card:SetPoint("TOPLEFT", self.groupScroll.content, "TOPLEFT", 0, -(i - 1) * (CARD_H + 8))
        card:SetPoint("RIGHT", self.groupScroll.content, "RIGHT", -4, 0)
        Theme.Fill(card, Theme.color.rowAltBg)
        Theme.Outline(card, Theme.color.border)
        card.title = Theme.Label(card, "", fonts.rowBold or fonts.row, Theme.color.heading)
        card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        card.count = Theme.Label(card, "", fonts.small, Theme.color.textDim)
        card.count:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)
        -- Je Platz: Rollenwappen, Klassenwappen, Text (07.10.2026: "kannst du
        -- hier Rollenwappen einfuegen" — die Haken und Kreise davor hatte die
        -- Schrift nicht, sie kamen als Kaestchen). Ein leerer Platz zeigt
        -- sein Rollenwappen blass, ohne Klasse.
        card.lines = {}
        for n = 1, 5 do
            local y = -26 - (n - 1) * 16
            local roleIcon = card:CreateTexture(nil, "ARTWORK")
            roleIcon:SetSize(14, 14)
            roleIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, y)
            local classIcon = card:CreateTexture(nil, "ARTWORK")
            classIcon:SetSize(14, 14)
            classIcon:SetPoint("LEFT", roleIcon, "RIGHT", 4, 0)
            local line = Theme.Label(card, "", fonts.row, Theme.color.text)
            line:SetPoint("LEFT", classIcon, "RIGHT", 6, 0)
            line:SetPoint("RIGHT", card, "RIGHT", -8, 0)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            line.roleIcon, line.classIcon = roleIcon, classIcon
            card.lines[n] = line
        end
        card.post = Widgets.Button(card, L.TG_POST_RUN, function() View:PostRun(card.suggestion) end, "primary")
        card.post:SetTooltip(L.TT_TG_POST)
        card.post:SetHeight(20)
        card.post:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 7)
        card.invite = Widgets.Button(card, L.TG_INVITE_ALL, function() View:InviteAll(card.suggestion) end)
        card.invite:SetHeight(20)
        card.invite:SetPoint("LEFT", card.post, "RIGHT", 6, 0)
        card:Hide()
        self.cards[i] = card
    end
    self.groupsEmpty = Theme.Label(groups.content, L.TG_NO_GROUPS, fonts.body, Theme.color.textDim)
    self.groupsEmpty:SetPoint("TOPLEFT", groups.content, "TOPLEFT", 16, -30)
    self.groupsEmpty:SetPoint("RIGHT", groups.content, "RIGHT", -16, 0)
    self.groupsEmpty:SetJustifyH("CENTER")
    self.groupsEmpty:SetSpacing(3)

    -- Rechts: Gruppenquests.
    local quests = Widgets.Panel(frame, L.TG_QUESTS, "")
    quests:SetPoint("TOPLEFT", groups, "TOPRIGHT", 8, 0)
    quests:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    self.questPanel = quests
    self.questList = Widgets.ScrollList(quests.content, {
        rowHeight = ROW_H,
        columns = {
            { key = "tag",   label = L.TG_COL_TAG,   width = 70 },
            { key = "title", label = L.TG_COL_QUEST, width = 220 },
            { key = "who",   label = L.TG_COL_WHO },
        },
        createRow = function(row) View:BuildQuestRow(row) end,
        updateRow = function(row, entry) View:UpdateQuestRow(row, entry) end,
        -- Klick: Menue mit "Im Questhub posten" und "Einladen" (09.10.2026).
        onClickRow = function(entry) View:QuestMenu(entry) end,
        onEnterRow = function(row)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.TT_TG_QUEST_ROW, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end,
        onLeaveRow = function() GameTooltip:Hide() end,
    })
    self.questList:SetAllPoints(quests.content)
    self.questsEmpty = Theme.Label(quests.content, L.TG_NO_QUESTS, fonts.body, Theme.color.textDim)
    self.questsEmpty:SetPoint("TOPLEFT", quests.content, "TOPLEFT", 16, -40)
    self.questsEmpty:SetPoint("RIGHT", quests.content, "RIGHT", -16, 0)
    self.questsEmpty:SetJustifyH("CENTER")
    self.questsEmpty:SetSpacing(3)

    for _, name in ipairs({ "TOGETHER_CHANGED", "GUILD_UPDATED", "EQUIPMENT_UPDATED", "QUESTHUB_CHANGED" }) do
        GA.Core.Callbacks:On(name, function()
            if View.frame and View.frame:IsVisible() then View:Refresh() end
        end, "TogetherView")
    end

    self.frame = frame
    return frame
end

function View:BuildQuestRow(row)
    local fonts = Theme.Fonts()
    row.tag = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.tag:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.tag:SetWidth(64)
    row.tag:SetJustifyH("LEFT")
    row.title = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.title:SetPoint("LEFT", row, "LEFT", 76, 0)
    row.title:SetWidth(214)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.who = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.who:SetPoint("LEFT", row, "LEFT", 296, 0)
    row.who:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)
end

function View:UpdateQuestRow(row, entry)
    row.tag:SetText(L["TG_TAG_" .. entry.tag] or entry.tag)
    -- Schon im Questhub? Dann steht es hinter dem Titel.
    local posted = GA.Modules.Questhub and GA.Modules.Questhub:OwnFor(entry.id)
    row.title:SetText((entry.title or ("#" .. tostring(entry.id)))
        .. (posted and ("  |cffd9a441" .. L.TG_QH_MARK .. "|r") or ""))
    row.who:SetText(#entry.holders .. "  ·  " .. table.concat(entry.holders, ", "))
end

-- ================================================================== Inhalt ----

function View.MyRole()
    local identity = GA.Core.Compat.GetPlayerIdentity()
    local character = identity.guid and GA.Core.Database.account.characters[identity.guid]
    return character and character.combatRole or nil
end

local function colored(name, class)
    return class and Theme.ColorByClass(name, class) or name
end

function View:Refresh()
    if not self.frame then return end
    local T = together()
    local mine = View.MyRole()
    for role, chip in pairs(self.roleChips) do chip:SetPressed(mine == role) end

    local candidates = T:Candidates()
    local suggestions = T:Suggestions()
    local shared = T:Shared()

    self.status:SetText(string.format(L.TG_STATUS, #candidates, #suggestions, #shared))

    for i, card in ipairs(self.cards) do
        local s = suggestions[i]
        card.suggestion = s
        if s then
            card.title:SetText(string.format("%s  (%d–%d)", s.dungeon, s.min, s.max))
            card.count:SetText(string.format(L.TG_FILLED, s.filled))
            local c = s.filled == 5 and Theme.color.jade or Theme.color.textDim
            card.count:SetTextColor(c[1], c[2], c[3])
            local rows = {
                { role = "TANK", entry = s.slots.TANK },
                { role = "HEAL", entry = s.slots.HEAL },
                { role = "DPS", entry = s.slots.DPS[1] },
                { role = "DPS", entry = s.slots.DPS[2] },
                { role = "DPS", entry = s.slots.DPS[3] },
            }
            for n, r in ipairs(rows) do
                local line = card.lines[n]
                local label = L["DH_ROLE_" .. r.role]
                -- Fehlt das Wappen auf diesem Client, steht die Rolle als Wort.
                local hasRole = Theme.SetRoleIcon(line.roleIcon, r.role)
                line.roleIcon:SetShown(hasRole)
                local prefix = hasRole and "" or (label .. "  ")
                if r.entry then
                    line.roleIcon:SetAlpha(1)
                    pcall(line.roleIcon.SetDesaturated, line.roleIcon, false)
                    line.classIcon:SetShown(Theme.SetClassIcon(line.classIcon, r.entry.class))
                    local who = colored(r.entry.name, r.entry.class) .. (r.entry.me and (" " .. L.TG_YOU) or "")
                    local level = r.entry.level and (" |cff8a8a8a" .. r.entry.level .. "|r") or ""
                    local guess = r.entry.guessed and (" |cff8a8a8a" .. L.TG_GUESSED .. "|r") or ""
                    line:SetText(prefix .. who .. level .. guess)
                else
                    line.roleIcon:SetAlpha(0.35)
                    pcall(line.roleIcon.SetDesaturated, line.roleIcon, true)
                    line.classIcon:Hide()
                    line:SetText("|cff8a8a8a" .. prefix .. L.TG_MISSING .. "|r")
                end
            end
            local others = 0
            for _, r in ipairs(rows) do if r.entry and not r.entry.me then others = others + 1 end end
            card.invite:SetEnabledState(others > 0)
            card:Show()
        else
            card:Hide()
        end
    end
    self.groupScroll.content:SetHeight(math.max(1, #suggestions * (CARD_H + 8)))
    if self.groupScroll.Refresh then self.groupScroll:Refresh() end
    self.groupsEmpty:SetShown(#suggestions == 0)

    self.questList:SetData(shared)
    self.questsEmpty:SetShown(#shared == 0)
    GA.UI.MainFrame:SetContext(string.format(L.TG_CONTEXT, #candidates))
end

-- ================================================================== Aktionen --

--- Dungeonhub oeffnen, Dungeon vorbelegt.
function View:PostRun(s)
    if not s then return end
    local hub = GA.UI.MainFrame.views and GA.UI.MainFrame.views.dungeonhub
    if hub and hub.Prefill then hub:Prefill(s.dungeon) end
    GA.UI.MainFrame:ShowView("dungeonhub")
end

function View:InviteAll(s)
    if not s then return end
    local names = {}
    local function add(e) if e and not e.me then names[#names + 1] = e.name end end
    add(s.slots.TANK) add(s.slots.HEAL)
    for _, e in ipairs(s.slots.DPS) do add(e) end
    GA.Modules.Guild:Invite(names)
end

--- Das Menue einer gemeinsamen Quest (09.10.2026): im Questhub posten
--- (oder wieder herausnehmen) und die anderen einladen. Posten geht nur
--- mit einer Quest aus dem EIGENEN Log — ein Gesuch sagt "ich habe sie
--- und suche Leute", und Ziele und Stand kommen aus diesem Log.
function View:QuestMenu(entry)
    local Questhub = GA.Modules.Questhub
    local items = {}

    local posted = Questhub and Questhub:OwnFor(entry.id)
    local mine = Questhub and Questhub:MatchOwn(entry.id)
    if posted then
        items[#items + 1] = { text = L.TG_QH_WITHDRAW, func = function()
            Questhub:Withdraw(posted.id)
            GA.UI.MainFrame:Notice("info", L.QH_WITHDRAWN, tostring(posted.title or entry.title))
            View:Refresh()
        end }
    elseif mine then
        items[#items + 1] = { text = L.TG_QH_POST, func = function()
            local request, reason = Questhub:Post(mine.entry)
            if request then
                GA.UI.MainFrame:Notice("info", L.QH_POSTED, tostring(request.title))
            else
                GA.UI.MainFrame:Notice("warn", "%s", L["QH_ERR_" .. tostring(reason)] or tostring(reason))
            end
            View:Refresh()
        end }
    else
        items[#items + 1] = { text = L.TG_QH_NOT_MINE, disabled = true }
    end

    local me = GA.Core.Util.ShortName(GA.Core.Compat.GetPlayerIdentity().name or "")
    local names = {}
    for _, name in ipairs(entry.holders or {}) do
        if name ~= me then names[#names + 1] = name end
    end
    if #names > 0 then
        items[#items + 1] = { text = string.format(L.TG_INVITE_HOLDERS, #names), func = function() GA.Modules.Guild:Invite(names) end }
    end
    Widgets.ContextMenu(entry.title or L.TG_QUESTS, items)
end

function View:OnShow() self:Refresh() end

GA.UI.MainFrame:RegisterView("together", View)
