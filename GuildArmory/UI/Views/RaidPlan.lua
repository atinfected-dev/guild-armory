--[[----------------------------------------------------------------------------
    UI/Views/RaidPlan — der Raidplan (06.10.2026).

    Oben die Wahl des Plans, Import und das Plan-Menue, darunter links die
    Gruppen 1–8, rechts die Bosse und je Boss Notiz und Erinnerungen. Was
    fuer einen selbst gilt (eigener Name, eigene Gruppe, eigene Rolle), steht
    hervorgehoben — das ist die Frage, mit der jemand diese Seite oeffnet.

    VON HAND BEARBEITEN (06.10.2026: "Man muss das alles auch im Addon von
    Hand eintragen koennen"): Plan › Neu oder Bearbeiten schaltet die Seite
    in den Bearbeitungsmodus. Dann
      * ist jeder Platz in den Gruppen anklickbar (Name, Rolle, Bank,
        entfernen), und "Aus dem Raid" uebernimmt die aktuelle Aufstellung,
      * haengt unter Bossen und Erinnerungen je eine Zeile "+ hinzufuegen",
      * oeffnet Klick auf eine Erinnerung ihr Formular, Rechtsklick auf Boss
        oder Erinnerung ein Menue (bearbeiten, verschieben, entfernen).
    Bearbeitet wird ein ENTWURF in der Rohform (Raids/RaidPlan, "Entwurf").
    Erst "Speichern" legt ihn ab — mit neuer Revision, und er geht an die
    Gilde wie ein importierter Plan. "Verwerfen" laesst alles, wie es war.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local L = GA.L

View.titleKey = "NAV_RAIDPLAN"

local GROUP_W, GROUP_ROW = 150, 15
local BOSS_W = 170
local ROW_H = 20

local function plans() return GA.Modules.RaidPlan end

--- "1:05" aus Sekunden.
function View.Clock(seconds) return plans().FormatClock(seconds) end

--- Lesbare Ziele einer Erinnerung (die Funktion steht im Modul).
function View.Targets(reminder) return plans().TargetText(reminder) end

--- Klasse eines Namens aus dem Gildenroster, falls bekannt.
local function classOf(name)
    local key = plans().NameKey(name)
    local members = GA.Core.Database.account.guild and GA.Core.Database.account.guild.members or {}
    for _, member in pairs(members) do
        if member.name and plans().NameKey(member.name) == key then return member.class end
    end
    return nil
end

-- ================================================================== Aufbau ----

function View:Create(parent)
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    bar:SetHeight(24)

    -- Leiste im Ansichtsmodus.
    local normal = CreateFrame("Frame", nil, bar)
    normal:SetAllPoints(bar)
    self.normalBar = normal
    self.picker = Widgets.Dropdown(normal, {
        width = 280,
        placeholder = L.RP_NONE_SHORT,
        getOptions = function()
            local out = {}
            for _, entry in ipairs(plans():All()) do
                out[#out + 1] = { text = View.PlanLabel(entry.plan), value = entry.plan.id }
            end
            return out
        end,
        onSelect = function(id) plans():SetActive(id) end,
    })
    self.picker:SetPoint("LEFT", normal, "LEFT", 0, 0)
    self.importButton = Widgets.Button(normal, L.RP_IMPORT, function() View:OpenImport() end)
    self.importButton:SetTooltip(L.TT_RP_IMPORT)
    self.importButton:SetPoint("RIGHT", normal, "RIGHT", 0, 0)
    self.menuButton = Widgets.Button(normal, L.RP_MENU, function() View:PlanMenu() end)
    self.menuButton:SetPoint("RIGHT", self.importButton, "LEFT", -6, 0)
    self.arrangeButton = Widgets.Button(normal, L.RP_ARRANGE, function() View:Arrange() end, "primary")
    self.arrangeButton:SetTooltip(L.TT_RP_ARRANGE)
    self.arrangeButton:SetPoint("RIGHT", self.menuButton, "LEFT", -12, 0)

    -- Leiste im Bearbeitungsmodus.
    local edit = CreateFrame("Frame", nil, bar)
    edit:SetAllPoints(bar)
    edit:Hide()
    self.editBar = edit
    self.editTitle = Theme.Label(edit, "", fonts.nav or fonts.row, Theme.color.heading)
    self.editTitle:SetPoint("LEFT", edit, "LEFT", 4, 0)
    self.saveButton = Widgets.Button(edit, L.RP_SAVE, function() View:SaveEdit() end, "primary")
    self.saveButton:SetTooltip(L.TT_RP_SAVE)
    self.saveButton:SetPoint("RIGHT", edit, "RIGHT", 0, 0)
    self.discardButton = Widgets.Button(edit, L.RP_DISCARD, function() View:DiscardEdit() end)
    self.discardButton:SetPoint("RIGHT", self.saveButton, "LEFT", -6, 0)
    self.propsButton = Widgets.Button(edit, L.RP_PROPS, function() View:EditProps() end)
    self.propsButton:SetPoint("RIGHT", self.discardButton, "LEFT", -12, 0)

    self.status = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.status:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -6)
    self.status:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    self.status:SetJustifyH("LEFT")

    -- Anmeldung (06.10.2026): die eigene Zu-/Absage und wer sonst kommt.
    local sign = CreateFrame("Frame", nil, frame)
    sign:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -24)
    sign:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    sign:SetHeight(20)
    self.signRow = sign
    local signLabel = Theme.Label(sign, L.RP_SIGN_YOU, fonts.small, Theme.color.textDim)
    signLabel:SetPoint("LEFT", sign, "LEFT", 2, 0)
    self.signChips = {}
    local previous = signLabel
    for _, status in ipairs({ "yes", "maybe", "no" }) do
        local chip = Widgets.Chip(sign, L["RP_SIGN_" .. string.upper(status)])
        chip:SetHeight(18)
        chip:SetPoint("LEFT", previous, "RIGHT", previous == signLabel and 8 or 4, 0)
        chip:SetScript("OnClick", function() View:SetSignup(status) end)
        self.signChips[status] = chip
        previous = chip
    end
    -- Die Zahlen; darueber zeigt der Tooltip die Namen.
    local counts = CreateFrame("Button", nil, sign)
    counts:SetPoint("LEFT", previous, "RIGHT", 14, 0)
    counts:SetSize(260, 18)
    counts.label = Theme.Label(counts, "", fonts.small, Theme.color.text)
    counts.label:SetPoint("LEFT", counts, "LEFT", 0, 0)
    counts:SetScript("OnEnter", function(btn) View:ShowSignupTooltip(btn) end)
    counts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.signCounts = counts

    -- Links: die Gruppen.
    local groups = Widgets.Panel(frame, L.RP_GROUPS, "")
    groups:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -50)
    groups:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    groups:SetWidth(GROUP_W * 2 + 30)
    self.groupsPanel = groups
    self.fromRaidButton = Widgets.Button(groups.header or groups, L.RP_FROM_RAID, function() View:TakeFromRaid() end)
    self.fromRaidButton:SetTooltip(L.TT_RP_FROM_RAID)
    self.fromRaidButton:SetHeight(18)
    self.fromRaidButton:SetPoint("RIGHT", groups.header or groups, "RIGHT", -4, 0)
    self.groupBoxes = {}
    for g = 1, 8 do
        local box = CreateFrame("Frame", nil, groups.content)
        box:SetSize(GROUP_W, 18 + GROUP_ROW * 5)
        local col, row = (g - 1) % 2, math.floor((g - 1) / 2)
        box:SetPoint("TOPLEFT", groups.content, "TOPLEFT", col * (GROUP_W + 12), -row * (18 + GROUP_ROW * 5 + 10))
        box.title = Theme.Label(box, string.format(L.RP_GROUP, g), fonts.small, Theme.color.heading)
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        box.lines, box.slots = {}, {}
        for i = 1, 5 do
            local line = Theme.Label(box, "", fonts.row, Theme.color.text)
            line:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -16 - (i - 1) * GROUP_ROW)
            line:SetWidth(GROUP_W - 8)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            box.lines[i] = line
            -- Im Bearbeitungsmodus: der Platz als Knopf.
            local slot = CreateFrame("Button", nil, box)
            slot:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -15 - (i - 1) * GROUP_ROW)
            slot:SetSize(GROUP_W - 2, GROUP_ROW)
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local hl = Theme.Fill(slot, Theme.color.rowHover, "HIGHLIGHT")
            hl:SetAlpha(0.6)
            slot:SetScript("OnClick", function() View:SlotMenu(g, i) end)
            slot:Hide()
            box.slots[i] = slot
        end
        self.groupBoxes[g] = box
    end
    self.bench = Theme.Label(groups.content, "", fonts.small, Theme.color.textDim)
    self.bench:SetPoint("TOPLEFT", groups.content, "TOPLEFT", 0, -4 * (18 + GROUP_ROW * 5 + 10))
    self.bench:SetPoint("RIGHT", groups.content, "RIGHT", 0, 0)
    self.bench:SetJustifyH("LEFT")
    self.bench:SetSpacing(2)
    self.benchButton = CreateFrame("Button", nil, groups.content)
    self.benchButton:SetPoint("TOPLEFT", self.bench, "TOPLEFT", -2, 2)
    self.benchButton:SetPoint("RIGHT", groups.content, "RIGHT", 0, 0)
    self.benchButton:SetHeight(32)
    Theme.Fill(self.benchButton, Theme.color.rowHover, "HIGHLIGHT"):SetAlpha(0.6)
    self.benchButton:SetScript("OnClick", function() View:EditBench() end)
    self.benchButton:Hide()

    -- Rechts: Bosse, Notiz, Erinnerungen.
    local bosses = Widgets.Panel(frame, L.RP_BOSSES, "")
    bosses:SetPoint("TOPLEFT", groups, "TOPRIGHT", 8, 0)
    bosses:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    self.bossPanel = bosses

    -- Probelauf (Schritt 4): die Erinnerungen des gewaehlten Bosses so, wie
    -- sie im Kampf erscheinen — alle, nicht nur die eigenen.
    self.previewButton = Widgets.Button(bosses.header or bosses, L.RP_PREVIEW, function() View:TogglePreview() end)
    self.previewButton:SetTooltip(L.TT_RP_PREVIEW)
    self.previewButton:SetHeight(18)
    self.previewButton:SetPoint("RIGHT", bosses.header or bosses, "RIGHT", -4, 0)
    self.bossEditButton = Widgets.Button(bosses.header or bosses, L.RP_BOSS_EDIT, function() View:EditBoss(View.bossIndex) end)
    self.bossEditButton:SetHeight(18)
    self.bossEditButton:SetPoint("RIGHT", self.previewButton, "LEFT", -6, 0)
    self.bossEditButton:Hide()

    self.bossList = Widgets.ScrollList(bosses.content, {
        rowHeight = ROW_H,
        createRow = function(row) View:BuildBossRow(row) end,
        updateRow = function(row, entry) View:UpdateBossRow(row, entry) end,
        onClickRow = function(entry, _, button) View:OnBossClick(entry, button) end,
    })
    self.bossList:SetPoint("TOPLEFT", bosses.content, "TOPLEFT", 0, 0)
    self.bossList:SetPoint("BOTTOMLEFT", bosses.content, "BOTTOMLEFT", 0, 0)
    self.bossList:SetWidth(BOSS_W)

    self.note = Theme.Label(bosses.content, "", fonts.small, Theme.color.text)
    self.note:SetPoint("TOPLEFT", bosses.content, "TOPLEFT", BOSS_W + 12, -2)
    self.note:SetPoint("RIGHT", bosses.content, "RIGHT", -4, 0)
    self.note:SetJustifyH("LEFT")
    self.note:SetSpacing(2)

    self.reminders = Widgets.ScrollList(bosses.content, {
        rowHeight = ROW_H,
        columns = {
            { key = "time",  label = L.RP_COL_TIME, width = 56 },
            { key = "to",    label = L.RP_COL_TO,   width = 130 },
            { key = "text",  label = L.RP_COL_TEXT },
        },
        createRow = function(row) View:BuildReminderRow(row) end,
        updateRow = function(row, entry) View:UpdateReminderRow(row, entry) end,
        onClickRow = function(entry, _, button) View:OnReminderClick(entry, button) end,
    })
    self.reminders:SetPoint("TOPLEFT", self.note, "BOTTOMLEFT", -2, -8)
    self.reminders:SetPoint("BOTTOMRIGHT", bosses.content, "BOTTOMRIGHT", 0, 0)

    self.empty = Theme.Label(frame, L.RP_EMPTY, fonts.body, Theme.color.textDim)
    self.empty:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 40, -90)
    self.empty:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetSpacing(3)
    self.empty:Hide()
    self.newButton = Widgets.Button(frame, L.RP_NEW, function() View:NewPlan() end, "primary")
    self.newButton:SetPoint("TOP", self.empty, "BOTTOM", 0, -14)
    self.newButton:Hide()

    for _, name in ipairs({ "RAIDPLAN_CHANGED", "RAIDPLAN_ROSTER", "RAIDPLAN_ARRANGE", "REMINDERS_START", "REMINDERS_STOP",
                            "RAIDPLAN_SIGNUPS", "RAIDPLAN_ENCOUNTERS" }) do
        GA.Core.Callbacks:On(name, function()
            if View.frame and View.frame:IsVisible() then View:Refresh() end
        end, "RaidPlanView")
    end

    self.frame = frame
    return frame
end

function View.PlanLabel(plan)
    local when = plan.start and date("%d.%m. %H:%M", plan.start)
    return when and (when .. "  " .. (plan.title or "")) or (plan.title or plan.id)
end

function View:BuildBossRow(row)
    local fonts = Theme.Fonts()
    row.label = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.count = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
end

function View:UpdateBossRow(row, entry)
    if entry.add then
        row.label:SetText(L.RP_ADD_BOSS)
        row.label:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
        row.count:SetText("")
        return
    end
    row.label:SetText(entry.boss.name or ("#" .. tostring(entry.boss.encounterID)))
    local c = entry.index == self.bossIndex and Theme.color.heading or Theme.color.text
    row.label:SetTextColor(c[1], c[2], c[3])
    row.count:SetText(entry.mine > 0 and string.format("|cffffd100%d|r/%d", entry.mine, #entry.boss.reminders)
        or tostring(#entry.boss.reminders))
end

function View:BuildReminderRow(row)
    local fonts = Theme.Fonts()
    row.time = Theme.Label(row, "", fonts.row, Theme.color.textDim)
    row.time:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.time:SetWidth(50)
    row.time:SetJustifyH("LEFT")
    row.to = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.to:SetPoint("LEFT", row, "LEFT", 62, 0)
    row.to:SetWidth(124)
    row.to:SetJustifyH("LEFT")
    row.to:SetWordWrap(false)
    row.text = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.text:SetPoint("LEFT", row, "LEFT", 192, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
end

local LEVEL_COLOR = { info = "text", warn = "heading", alert = "bad" }

function View:UpdateReminderRow(row, entry)
    if entry.add then
        row.time:SetText("")
        row.to:SetText("")
        row.text:SetText(L.RP_ADD_REMINDER)
        row.text:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
        return
    end
    local r = entry.reminder
    local clock = View.Clock(r.time)
    if r.phase > 1 then clock = clock .. " P" .. r.phase end
    row.time:SetText(clock)
    row.to:SetText(View.Targets(r))
    local text = r.text or ""
    if r.spell then
        local name = GA.Core.Compat.GetSpellName and GA.Core.Compat.GetSpellName(r.spell)
        if name and text == "" then text = name end
    end
    if r.marker then text = "|T" .. plans().MarkerTexture(r.marker) .. ":0|t " .. text end
    row.text:SetText(plans().RenderText(text))
    local c = Theme.color[LEVEL_COLOR[r.level] or "text"] or Theme.color.text
    if not entry.mine and not self.draft then c = Theme.color.textDim end
    row.text:SetTextColor(c[1], c[2], c[3])
    local tc = entry.mine and Theme.color.heading or Theme.color.textDim
    row.to:SetTextColor(tc[1], tc[2], tc[3])
end

-- ================================================================== Inhalt ----

--- Der Plan, der gerade gezeigt wird: im Bearbeitungsmodus der Entwurf,
--- sonst der aktive. @return plan|nil, entry|nil
function View:CurrentPlan()
    if self.draft then return plans().Normalize(self.draft), nil end
    local entry = plans():Active()
    return entry and entry.plan, entry
end

function View:Refresh()
    if not self.frame then return end
    local Plans = plans()
    local editing = self.draft ~= nil
    local plan, entry = self:CurrentPlan()
    local has = plan ~= nil

    self.normalBar:SetShown(not editing)
    self.editBar:SetShown(editing)
    self.discardButton:SetConfirm(editing and self.dirty and L.BTN_REALLY or nil)
    self.empty:SetShown(not has)
    self.newButton:SetShown(not has)
    self.groupsPanel:SetShown(has)
    self.bossPanel:SetShown(has)
    self.fromRaidButton:SetShown(editing)
    self.fromRaidButton:SetEnabledState(GA.Core.Compat.IsInRaid(), L.RP_ARRANGE_NORAID)
    self.bossEditButton:SetShown(editing)
    self.benchButton:SetShown(editing)
    local problem = Plans.arranging and "running" or Plans:ArrangeProblem()
    self.arrangeButton:SetEnabledState(problem == nil, problem and L["RP_ARRANGE_" .. string.upper(problem)] or nil)
    if not has then
        self.signRow:Hide()
        self.picker:SetDisplay(nil)
        self.status:SetText(editing and L.RP_ERR_DRAFT or "")
        GA.UI.MainFrame:SetContext("")
        return
    end

    -- Anmeldung: eigene Wahl und Zahlen (nicht im Bearbeitungsmodus).
    self.signRow:SetShown(not editing)
    local signups = Plans:Signups(plan.id)
    if not editing then
        local mine = Plans:SignupOf(plan.id, (GA.Core.Compat.GetPlayerIdentity() or {}).name)
        for status, chip in pairs(self.signChips) do chip:SetPressed(mine ~= nil and mine.status == status) end
        local c = Plans:SignupCounts(plan.id)
        self.signCounts.label:SetText(string.format(L.RP_SIGN_COUNTS, c.yes, c.maybe, c.no))
    end

    local planKey = editing and ("draft:" .. plan.id) or plan.id
    if self.planId ~= planKey then self.planId, self.bossIndex = planKey, nil end
    self.picker:SetDisplay(View.PlanLabel(plan))
    self.editTitle:SetText(string.format(L.RP_EDITING, View.PlanLabel(plan)))
    local me = Plans.WhoAmI(plan)
    local myKey = Plans.NameKey(me.name)
    local sum = Plans.Summary(plan)

    local parts = {}
    if editing then
        parts[#parts + 1] = "|cffffd100" .. (self.dirty and L.RP_UNSAVED or L.RP_EDIT_HINT) .. "|r"
    else
        parts[#parts + 1] = string.format(L.RP_REV, plan.rev)
        if plan.author then parts[#parts + 1] = string.format(L.RP_AUTHOR, plan.author) end
        if entry and entry.from then parts[#parts + 1] = string.format(L.RP_FROM, entry.from, Util.TimeAgo(entry.at)) end
    end
    parts[#parts + 1] = string.format(L.RP_COUNTS, sum.players, sum.bosses, sum.reminders)
    if me.group then parts[#parts + 1] = "|cffffd100" .. string.format(L.RP_YOU, me.group) .. "|r"
    elseif not editing then parts[#parts + 1] = L.RP_YOU_NOT end
    -- Im Raid: Plan gegen Aufstellung.
    local roster = GA.Core.Compat.GetRaidRoster()
    local cmp = #roster > 0 and Plans.Compare(plan, roster) or nil
    if cmp then
        parts[#parts + 1] = string.format(L.RP_INRAID, cmp.placed, cmp.placed + cmp.wrong + #cmp.missing)
    end
    self.status:SetText(table.concat(parts, "  ·  "))

    -- Gruppen
    for g = 1, 8 do
        local box = self.groupBoxes[g]
        local names = plan.groups[g] or {}
        for i = 1, 5 do
            local line, name = box.lines[i], names[i]
            -- Im Bearbeitungsmodus: belegte Plaetze und der erste freie sind anklickbar.
            box.slots[i]:SetShown(editing and i <= #names + 1)
            if name then
                local role = plan.roles[Plans.NameKey(name)]
                local roleText = role and (" |cff8a8a8a" .. (L["RP_ROLE_" .. string.upper(role)] or role) .. "|r") or ""
                -- Im Raid: wer fehlt, wer woanders steht.
                local where = ""
                local member = cmp and cmp.byKey[Plans.NameKey(name)]
                if cmp and not member then where = " |cffff5050" .. L.RP_MISSING_TAG .. "|r"
                elseif member and member.group ~= g then where = " |cffffd100" .. string.format(L.RP_NOW_IN, member.group) .. "|r" end
                -- Anmeldung: wer abgesagt hat oder noch unsicher ist.
                local signed = signups[Plans.NameKey(name)]
                if signed and signed.status == "no" then where = where .. " |cffff5050" .. L.RP_SIGN_TAG_NO .. "|r"
                elseif signed and signed.status == "maybe" then where = where .. " |cffffd100" .. L.RP_SIGN_TAG_MAYBE .. "|r" end
                line:SetText((Plans.NameKey(name) == myKey and "> " or "") .. name .. roleText .. where)
                local class = classOf(name)
                if class and not (cmp and not member) then line:SetTextColor(Theme.ClassColor(class))
                else line:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3]) end
            elseif editing and i == #names + 1 then
                line:SetText(L.RP_SLOT_FREE)
                line:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
            else
                line:SetText("")
            end
        end
        local title = string.format(L.RP_GROUP, g)
        box.title:SetText(g == me.group and ("|cffffd100" .. title .. "|r") or title)
    end
    local benchLines = {}
    if #plan.bench > 0 then benchLines[#benchLines + 1] = string.format(L.RP_BENCH, table.concat(plan.bench, ", "))
    elseif editing then benchLines[#benchLines + 1] = L.RP_BENCH_EDIT end
    if cmp and #cmp.extras > 0 then
        benchLines[#benchLines + 1] = "|cffffd100" .. string.format(L.RP_EXTRAS, table.concat(cmp.extras, ", ")) .. "|r"
    end
    -- Zusagen gegen Anwesenheit (07.10.2026): sobald dieser Client im Raid
    -- mitgeschrieben hat.
    local report = not editing and Plans:AttendanceReport(plan.id)
    if report then
        benchLines[#benchLines + 1] = string.format(L.RP_ATT_CAME, report.came)
            .. (#report.noShow > 0 and ("  |cffff5050" .. string.format(L.RP_ATT_NOSHOW, table.concat(report.noShow, ", ")) .. "|r") or "")
            .. (#report.unannounced > 0 and ("  |cff8a8a8a" .. string.format(L.RP_ATT_UNANNOUNCED, table.concat(report.unannounced, ", ")) .. "|r") or "")
    end
    self.bench:SetText(table.concat(benchLines, "\n"))

    -- Bosse
    local list = {}
    for index, boss in ipairs(plan.bosses) do
        local mine = 0
        for _, r in ipairs(boss.reminders) do if Plans.Matches(r, me) then mine = mine + 1 end end
        list[#list + 1] = { index = index, boss = boss, mine = mine }
    end
    if not self.bossIndex or not plan.bosses[self.bossIndex] then self.bossIndex = #plan.bosses > 0 and 1 or nil end
    if editing then list[#list + 1] = { add = true } end
    self.bossList:SetData(list)

    local boss = self.bossIndex and plan.bosses[self.bossIndex]
    local rows = {}
    if boss then
        local note = boss.note or plan.note or ""
        if #boss.phases > 0 then
            local ph = {}
            for _, p in ipairs(boss.phases) do
                ph[#ph + 1] = string.format(L.RP_PHASE_AT, p.phase, View.Clock(p.at)) .. (p.name and (" " .. p.name) or "")
            end
            note = (note ~= "" and (note .. "\n") or "") .. "|cff8a8a8a" .. table.concat(ph, "  ·  ") .. "|r"
        end
        -- Vor dem Pull: was beim Ready Check erscheint.
        if #(boss.prepull or {}) > 0 then
            local pre = {}
            for _, item in ipairs(boss.prepull) do
                local to = (#item.to == 1 and item.to[1] == "all") and "" or (" (" .. Plans.TargetText(item) .. ")")
                pre[#pre + 1] = Plans.RenderText(item.text) .. to
            end
            note = (note ~= "" and (note .. "\n") or "") .. "|cffffd100" .. L.RP_PREPULL .. ":|r " .. table.concat(pre, "  ·  ")
        end
        self.note:SetText(note)
        for _, r in ipairs(boss.reminders) do rows[#rows + 1] = { reminder = r, mine = Plans.Matches(r, me) } end
        if editing then rows[#rows + 1] = { add = true } end
        self.bossPanel:SetTitle(boss.name or L.RP_BOSSES)
        self.previewButton:SetEnabledState(#boss.reminders > 0)
        self.bossEditButton:SetEnabledState(true)
    else
        self.note:SetText(editing and L.RP_NO_BOSSES_EDIT or L.RP_NO_BOSSES)
        self.previewButton:SetEnabledState(false)
        self.bossEditButton:SetEnabledState(false)
        self.bossPanel:SetTitle(L.RP_BOSSES)
    end
    self.reminders:SetData(rows)
    local Reminders = GA.Modules.Reminders
    self.previewButton:SetLabel(Reminders and Reminders:IsPreview() and L.RP_PREVIEW_STOP or L.RP_PREVIEW)
    GA.UI.MainFrame:SetContext(plan.title or "")
end

-- ================================================================== Aktionen --

function View:OpenImport()
    Widgets.InputDialog(L.RP_IMPORT_TITLE, L.RP_IMPORT_HINT, function(text)
        local plan, reason = plans():Import(text)
        if not plan then return false, L["RP_ERR_" .. tostring(reason)] or tostring(reason) end
        local sum = plans().Summary(plan)
        GA.Core.Debug:Info(L.RP_IMPORTED, plan.title or plan.id, sum.players, sum.bosses, sum.reminders)
        if sum.skipped > 0 then GA.Core.Debug:Warn(L.RP_SKIPPED, sum.skipped) end
        View:Refresh()
        return true
    end)
end

--- Das Plan-Menue: neu, bearbeiten, als Text, an die Gilde, entfernen.
function View:PlanMenu()
    local entry = plans():Active()
    Widgets.ContextMenu(L.RP_MENU, {
        { text = L.RP_NEW, func = function() View:NewPlan() end },
        { text = L.RP_EDIT, disabled = not entry, func = function() View:EditPlan() end },
        { text = L.RP_COPY, disabled = not entry, func = function() View:CopyText() end },
        { text = L.RP_SHARE, disabled = not (entry and entry.wire), func = function() View:ShareActive() end },
        { text = L.RP_DELETE, disabled = not entry, confirm = L.BTN_REALLY, func = function() View:DeleteActive() end },
    })
end

function View:SetSignup(status)
    local entry = plans():Active()
    if not entry then return end
    local ok, why = plans():SetSignup(entry.plan.id, status)
    if why == "later" then GA.Core.Debug:Info(L.RP_SHARE_LATER) end
    self:Refresh()
end

--- Wer zugesagt, vielleicht oder abgesagt hat — in Klassenfarbe.
function View:ShowSignupTooltip(owner)
    local entry = plans():Active()
    if not entry then return end
    local byStatus = { yes = {}, maybe = {}, no = {} }
    for _, s in pairs(plans():Signups(entry.plan.id)) do
        if byStatus[s.status] then table.insert(byStatus[s.status], s) end
    end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(L.RP_SIGN_TITLE)
    for _, status in ipairs({ "yes", "maybe", "no" }) do
        local list = byStatus[status]
        table.sort(list, function(a, b) return a.name < b.name end)
        if #list > 0 then
            local names = {}
            for _, s in ipairs(list) do
                names[#names + 1] = s.class and Theme.ColorByClass(s.name, s.class) or s.name
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["RP_SIGN_" .. string.upper(status)] .. " (" .. #list .. ")", 1, 0.82, 0.1)
            GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

function View:TogglePreview()
    local Reminders = GA.Modules.Reminders
    if Reminders:IsPreview() then Reminders:Stop("preview") return end
    local plan = self:CurrentPlan()
    local boss = plan and self.bossIndex and plan.bosses[self.bossIndex]
    if boss then Reminders:Start(plan, boss, { preview = true }) end
end

function View:Arrange()
    local ok, why = plans():Arrange()
    if not ok then GA.Core.Debug:Warn(L["RP_ARRANGE_" .. string.upper(tostring(why))] or tostring(why)) end
    View:Refresh()
end

function View:ShareActive()
    local entry = plans():Active()
    if not entry then return end
    local ok, why = plans():Publish(entry.plan.id)
    if ok then GA.Core.Debug:Info(L.RP_SHARED, entry.plan.title or entry.plan.id)
    elseif why == "later" then GA.Core.Debug:Info(L.RP_SHARE_LATER)
    end
end

function View:DeleteActive()
    local entry = plans():Active()
    if not entry then return end
    plans():Delete(entry.plan.id)
end

--- Der Plan als Text zum Weitergeben — derselbe Text wie aus der Webapp.
function View:CopyText()
    local entry = plans():Active()
    if not entry then return end
    Widgets.CopyDialog(L.RP_COPY_TITLE, entry.wire or plans().EncodeRaw(plans().ToRaw(entry.plan)))
end

-- ================================================================ Bearbeiten -

function View:StartEdit(raw)
    self.draft = raw
    self.dirty = false
    self.planId = nil
    self:Refresh()
end

--- Nach jeder Aenderung am Entwurf.
function View:Changed()
    self.dirty = true
    self:Refresh()
end

function View:NewPlan()
    self:StartEdit(plans().NewDraft())
    self:EditProps()
end

function View:EditPlan()
    local entry = plans():Active()
    if entry then self:StartEdit(plans().ToRaw(entry.plan)) end
end

function View:SaveEdit()
    if not self.draft then return end
    local plan, why = plans():SaveDraft(self.draft)
    if not plan then
        GA.Core.Debug:Warn(L["RP_ERR_" .. tostring(why)] or tostring(why))
        return
    end
    self.draft, self.dirty = nil, false
    GA.Core.Debug:Info(L.RP_SAVED, plan.title or plan.id, plan.rev)
    self:Refresh()
end

--- Verwerfen. Mit ungespeicherten Aenderungen erst beim zweiten Klick.
--- Verwerfen. Mit ungespeicherten Aenderungen bestaetigt der Knopf selbst
--- (rot, "Wirklich?") — gesetzt in Refresh, je nachdem, ob etwas offen ist.
function View:DiscardEdit()
    self.draft, self.dirty = nil, false
    self:Refresh()
end

-- ---------------------------------------------------------- Eigenschaften --

local PROPS_FIELDS = {
    { key = "title", label = L.RP_F_TITLE },
    { key = "raid",  label = L.RP_F_RAID },
    { key = "date",  label = L.RP_F_DATE, hint = L.RP_F_DATE_HINT },
    { key = "clock", label = L.RP_F_CLOCK, hint = L.RP_F_CLOCK_HINT },
    { key = "note",  label = L.RP_F_NOTE, kind = "multiline", height = 70 },
}

function View:EditProps()
    local raw = self.draft
    if not raw then return end
    Widgets.FormDialog("rpProps", L.RP_PROPS, PROPS_FIELDS, {
        title = raw.title, raid = raw.raid and raw.raid.name,
        date = raw.start and date("%d.%m.%Y", raw.start), clock = raw.start and date("%H:%M", raw.start),
        note = raw.note,
    }, function(v)
        local start, ok = plans().ParseStart(v.date, v.clock)
        if not ok then return false, L.RP_ERR_DATE end
        local title = Util.Trim(v.title or "") or ""
        if title == "" then return false, L.RP_ERR_TITLE end
        raw.title, raw.start = title, start
        raw.raid = raw.raid or {}
        raw.raid.name = Util.Trim(v.raid or "") ~= "" and Util.Trim(v.raid) or nil
        raw.note = Util.Trim(v.note or "") ~= "" and v.note or nil
        View:Changed()
        return true
    end)
end

-- ------------------------------------------------------------------ Plaetze --

--- Wen man auf einen Platz setzen kann: wer im Raid ist, sonst wer aus der
--- Gilde online ist — jeweils ohne die, die schon einen Platz haben.
function View:Candidates()
    local Plans, raw = plans(), self.draft
    local out, seen = {}, {}
    local function add(name)
        name = Util.ShortName(name)
        local key = Plans.NameKey(name)
        if key and not seen[key] and not Plans.FindInGroups(raw, name) then
            seen[key] = true
            out[#out + 1] = name
        end
    end
    -- Wer abgesagt hat, wird nicht angeboten; wer zugesagt hat, zuerst.
    local signups = Plans:Signups(raw.id)
    for key, s in pairs(signups) do
        if s.status == "no" then seen[key] = true end
    end
    for _, s in pairs(signups) do
        if s.status ~= "no" then add(s.name) end
    end
    for _, m in ipairs(GA.Core.Compat.GetRaidRoster()) do add(m.name) end
    for _, name in ipairs(raw.bench or {}) do add(name) end
    if #out == 0 and GA.Modules.Guild then
        for _, member in ipairs(GA.Modules.Guild:List(true)) do add(member.name) end
    end
    return Plans.SortCandidates(out, signups)
end

local ROLE_ORDER = { "tank", "healer", "melee", "ranged" }

function View:SlotMenu(g, i)
    local raw = self.draft
    if not raw then return end
    local Plans = plans()
    local name = raw.groups[g][i]
    local items = {}
    if name then
        local current = Plans.RoleOf(raw, name)
        for _, role in ipairs(ROLE_ORDER) do
            items[#items + 1] = { text = (current == role and "> " or "   ") .. L["RP_ROLE_" .. string.upper(role)],
                func = function() Plans.SetRole(raw, name, role) View:Changed() end }
        end
        items[#items + 1] = { text = (current and "   " or "> ") .. L.RP_ROLE_NONE,
            func = function() Plans.SetRole(raw, name, nil) View:Changed() end }
        items[#items + 1] = { text = L.RP_TO_BENCH, func = function()
            table.remove(raw.groups[g], i)
            raw.bench[#raw.bench + 1] = name
            View:Changed()
        end }
        items[#items + 1] = { text = L.RP_REMOVE, func = function() table.remove(raw.groups[g], i) View:Changed() end }
    end
    items[#items + 1] = { text = L.RP_ENTER_NAME, func = function() View:EnterName(g, i) end }
    local candidates = self:Candidates()
    local signups = Plans:Signups(raw.id)
    for n = 1, math.min(#candidates, 15) do
        local cand = candidates[n]
        local signed = signups[Plans.NameKey(cand)]
        local tag = signed and signed.status == "yes" and (" |cff40c040" .. L.RP_SIGN_TAG_YES .. "|r")
            or (signed and signed.status == "maybe" and (" |cffffd100" .. L.RP_SIGN_TAG_MAYBE .. "|r")) or ""
        items[#items + 1] = { text = "+ " .. cand .. tag, func = function()
            if Plans.PlaceName(raw, g, i, cand) then View:Changed() end
        end }
    end
    Widgets.ContextMenu(name or string.format(L.RP_SLOT_TITLE, g), items)
end

local NAME_FIELDS = { { key = "name", label = L.RP_F_NAME } }

function View:EnterName(g, i)
    local raw = self.draft
    Widgets.FormDialog("rpName", string.format(L.RP_SLOT_TITLE, g), NAME_FIELDS, { name = raw.groups[g][i] }, function(v)
        local name = Util.Trim(v.name or "") or ""
        if name == "" then return false, L.RP_ERR_NAME end
        if not plans().PlaceName(raw, g, i, name) then return false, L.RP_ERR_FULL end
        View:Changed()
        return true
    end)
end

local BENCH_FIELDS = { { key = "bench", label = L.RP_F_BENCH, kind = "multiline", height = 90, hint = L.RP_F_BENCH_HINT } }

function View:EditBench()
    local raw = self.draft
    if not raw then return end
    Widgets.FormDialog("rpBench", L.RP_F_BENCH, BENCH_FIELDS, { bench = table.concat(raw.bench or {}, "\n") }, function(v)
        local list = {}
        for part in string.gmatch(v.bench or "", "[^,\n]+") do
            local name = Util.Trim(part) or ""
            -- Wer einen Platz hat, steht nicht auch auf der Bank.
            if name ~= "" and not plans().FindInGroups(raw, name) then list[#list + 1] = name end
        end
        raw.bench = list
        View:Changed()
        return true
    end)
end

function View:TakeFromRaid()
    local raw = self.draft
    if not raw then return end
    raw.groups = plans().GroupsFromRoster(GA.Core.Compat.GetRaidRoster())
    View:Changed()
end

-- -------------------------------------------------------------------- Bosse --

function View:OnBossClick(entry, button)
    if entry.add then self:EditBoss(nil) return end
    self.bossIndex = entry.index
    if self.draft and button == "RightButton" then self:BossMenu(entry.boss.src or entry.index) return end
    self:Refresh()
end

local BOSS_FIELDS = {
    { key = "known", label = L.RP_F_KNOWN, kind = "select",
      options = function()
          local out = {}
          for id, name in pairs(GA.Core.Database.account.seenEncounters or {}) do
              out[#out + 1] = { text = name .. "  (" .. id .. ")", value = id }
          end
          table.sort(out, function(a, b) return a.text < b.text end)
          if #out == 0 then out[1] = { text = L.RP_F_KNOWN_NONE, value = nil, disabled = true } end
          return out
      end,
      onSelect = function(id, dlg)
          local name = (GA.Core.Database.account.seenEncounters or {})[id]
          if name then dlg:SetValue("name", name) dlg:SetValue("id", id) end
      end },
    { key = "name",   label = L.RP_F_BOSS },
    { key = "id",     label = L.RP_F_ENCOUNTER, hint = L.RP_F_ENCOUNTER_HINT },
    { key = "phases", label = L.RP_F_PHASES, kind = "multiline", height = 50, hint = L.RP_F_PHASES_HINT },
    { key = "prepull", label = L.RP_F_PREPULL, kind = "multiline", height = 50, hint = L.RP_F_PREPULL_HINT },
    { key = "note",   label = L.RP_F_NOTE, kind = "multiline", height = 80 },
}

--- @param src number|nil  Stelle in draft.bosses; nil = neuer Boss
function View:EditBoss(src)
    local raw = self.draft
    if not raw then return end
    local boss = src and raw.bosses[src]
    Widgets.FormDialog("rpBoss", boss and (boss.name or L.RP_BOSSES) or L.RP_ADD_BOSS, BOSS_FIELDS, {
        name = boss and boss.name, id = boss and boss.encounterID,
        phases = boss and plans().PhasesToText(boss.phases), note = boss and boss.note,
        prepull = boss and plans().PrepullToText(boss.prepull),
    }, function(v)
        local name = Util.Trim(v.name or "") or ""
        local idText = Util.Trim(tostring(v.id or "")) or ""
        local id = tonumber(idText)
        if idText ~= "" and not id then return false, L.RP_ERR_ENCOUNTER end
        if name == "" and not id then return false, L.RP_ERR_BOSS end
        local phases, badLine = plans().ParsePhases(v.phases)
        if not phases then return false, string.format(L.RP_ERR_PHASES, badLine) end
        local prepull, badPrepull = plans().ParsePrepull(v.prepull)
        if not prepull then return false, string.format(L.RP_ERR_PREPULL, tostring(badPrepull)) end
        local target = boss or { reminders = {} }
        target.name = name ~= "" and name or nil
        target.encounterID = id
        target.phases = phases
        target.prepull = prepull
        target.note = Util.Trim(v.note or "") ~= "" and v.note or nil
        if not boss then
            raw.bosses[#raw.bosses + 1] = target
            View.bossIndex = #raw.bosses
        end
        View:Changed()
        return true
    end, boss and function() View:RemoveBoss(src) end or nil)
end

function View:RemoveBoss(src)
    table.remove(self.draft.bosses, src)
    self.bossIndex = math.max(1, src - 1)
    self:Changed()
end

function View:MoveBoss(src, delta)
    local list = self.draft.bosses
    local to = src + delta
    if not list[to] then return end
    list[src], list[to] = list[to], list[src]
    self.bossIndex = to
    self:Changed()
end

function View:BossMenu(src)
    local boss = self.draft.bosses[src]
    if not boss then return end
    Widgets.ContextMenu(boss.name or L.RP_BOSSES, {
        { text = L.RP_EDIT, func = function() View:EditBoss(src) end },
        { text = L.RP_UP, disabled = src <= 1, func = function() View:MoveBoss(src, -1) end },
        { text = L.RP_DOWN, disabled = src >= #self.draft.bosses, func = function() View:MoveBoss(src, 1) end },
        { text = L.RP_REMOVE, func = function() View:RemoveBoss(src) end },
    })
end

-- ------------------------------------------------------------- Erinnerungen --

local function targetOptions()
    local out = { { text = L.RP_TO_ALL, value = "all" } }
    for _, role in ipairs({ "tank", "healer", "melee", "ranged", "dps" }) do
        out[#out + 1] = { text = L["RP_ROLE_" .. string.upper(role)], value = "role:" .. role }
    end
    for g = 1, 8 do out[#out + 1] = { text = string.format(L.RP_GROUP, g), value = "group:" .. g } end
    for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[class] or class
        out[#out + 1] = { text = name, value = "class:" .. class }
    end
    local raw = View.draft
    for g = 1, 8 do
        for _, name in ipairs(raw and raw.groups[g] or {}) do out[#out + 1] = { text = name, value = name } end
    end
    return out
end

--- Die acht Markierungen zur Auswahl — mit Symbol und dem Namen des Spiels.
--- @param asToken boolean  Wert ist "{square}" (zum Einfuegen in den Text)
function View.MarkerOptions(asToken)
    local out = {}
    if not asToken then out[1] = { text = L.RP_MARKER_NONE, value = "none" } end
    for index, name in ipairs(plans().MARKER_NAMES) do
        local label = _G["RAID_TARGET_" .. index] or L["RP_MARK_" .. index]
        out[#out + 1] = { text = "|T" .. plans().MarkerTexture(index) .. ":14|t " .. label,
                          value = asToken and ("{" .. name .. "}") or name }
    end
    return out
end

local REMINDER_FIELDS = {
    { key = "clock", label = L.RP_F_TIME, hint = L.RP_F_TIME_HINT },
    { key = "phase", label = L.RP_F_PHASE },
    { key = "to",    label = L.RP_F_TO, append = targetOptions, hint = L.RP_F_TO_HINT },
    { key = "text",  label = L.RP_F_TEXT, append = function() return View.MarkerOptions(true) end, appendSep = " ",
      hint = L.RP_F_TEXT_HINT },
    { key = "marker", label = L.RP_F_MARKER, kind = "select", options = function() return View.MarkerOptions(false) end },
    { key = "spell", label = L.RP_F_SPELL },
    { key = "level", label = L.RP_F_LEVEL, kind = "select", options = function()
        return { { text = L.RP_LEVEL_INFO, value = "info" }, { text = L.RP_LEVEL_WARN, value = "warn" },
                 { text = L.RP_LEVEL_ALERT, value = "alert" } }
    end },
    { key = "sound", label = L.RP_F_SOUND, kind = "select", options = function()
        return { { text = L.RP_SOUND_AUTO, value = "auto" }, { text = L.RP_SOUND_NONE, value = "none" },
                 { text = L.RP_LEVEL_INFO, value = "info" }, { text = L.RP_LEVEL_WARN, value = "warn" },
                 { text = L.RP_LEVEL_ALERT, value = "alert" } }
    end },
    { key = "lead",  label = L.RP_F_LEAD },
    { key = "dur",   label = L.RP_F_DUR },
}

--- @param bossSrc number  Stelle in draft.bosses
--- @param src number|nil  Stelle in boss.reminders; nil = neue Erinnerung
function View:EditReminder(bossSrc, src)
    local raw = self.draft
    local boss = raw and raw.bosses[bossSrc]
    if not boss then return end
    local r = src and boss.reminders[src]
    Widgets.FormDialog("rpReminder", r and L.RP_EDIT_REMINDER or L.RP_ADD_REMINDER, REMINDER_FIELDS, {
        clock = plans().FormatClock(r and r.at or 0), phase = r and r.phase or 1,
        to = table.concat(r and r.to or { "all" }, ", "), text = r and r.text, spell = r and r.spell,
        level = r and r.level or "warn", sound = r and r.sound or "auto",
        lead = r and r.lead or 5, dur = r and r.dur or 4,
        marker = r and r.marker and plans().MARKER_NAMES[plans().MarkerIndex(r.marker)] or "none",
    }, function(v)
        local at = plans().ParseClock(v.clock)
        if not at or at > 3600 then return false, L.RP_ERR_TIME end
        local phase = tonumber(v.phase)
        if not phase or phase < 1 or phase > 20 then return false, L.RP_ERR_PHASE end
        local to, bad = plans().ParseTargets(v.to)
        if not to then return false, string.format(L.RP_ERR_TO, bad) end
        local text = Util.Trim(v.text or "") or ""
        local spellText = Util.Trim(tostring(v.spell or "")) or ""
        local spell = tonumber(spellText)
        if spellText ~= "" and not spell then return false, L.RP_ERR_SPELL end
        local marker = v.marker ~= "none" and v.marker or nil
        if text == "" and not spell and not marker then return false, L.RP_ERR_TEXT end
        local lead, dur = tonumber(v.lead) or 5, tonumber(v.dur) or 4
        if lead < 0 or lead > 30 or dur < 1 or dur > 60 then return false, L.RP_ERR_LEADDUR end
        local target = r or {}
        target.at, target.phase, target.to = at, math.floor(phase), to
        target.text = text ~= "" and text or nil
        target.spell = spell and math.floor(spell) or nil
        target.level = v.level or "warn"
        target.sound = (v.sound and v.sound ~= "auto") and v.sound or nil
        target.lead, target.dur = lead, dur
        target.marker = marker
        if not r then boss.reminders[#boss.reminders + 1] = target end
        View:Changed()
        return true
    end, r and function() table.remove(boss.reminders, src) View:Changed() end or nil)
end

function View:OnReminderClick(entry, button)
    if not self.draft then return end
    local plan = self:CurrentPlan()
    local boss = plan and plan.bosses[self.bossIndex]
    if not boss then return end
    local bossSrc = boss.src or self.bossIndex
    if entry.add then self:EditReminder(bossSrc, nil) return end
    local src = entry.reminder.src
    if button ~= "RightButton" then self:EditReminder(bossSrc, src) return end
    local list = self.draft.bosses[bossSrc].reminders
    Widgets.ContextMenu(entry.reminder.text or L.RP_EDIT_REMINDER, {
        { text = L.RP_EDIT, func = function() View:EditReminder(bossSrc, src) end },
        { text = L.RP_DUPLICATE, func = function()
            local copy = {}
            for k, value in pairs(list[src]) do copy[k] = value end
            copy.to = {}
            for i, sel in ipairs(list[src].to or {}) do copy.to[i] = sel end
            list[#list + 1] = copy
            View:Changed()
            View:EditReminder(bossSrc, #list)
        end },
        { text = L.RP_REMOVE, func = function() table.remove(list, src) View:Changed() end },
    })
end

function View:OnShow() self:Refresh() end

GA.UI.MainFrame:RegisterView("raidplan", View)
