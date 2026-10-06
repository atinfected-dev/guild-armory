--[[----------------------------------------------------------------------------
    UI/Views/RaidPlan — der Raidplan aus der Webapp (06.10.2026).

    Oben die Wahl des Plans und der Import, darunter links die Gruppen 1–8,
    rechts die Bosse und je Boss Notiz und Erinnerungen. Was fuer einen
    selbst gilt (eigener Name, eigene Gruppe, eigene Rolle), steht hervor-
    gehoben — das ist die Frage, mit der jemand diese Seite oeffnet.

    Die Daten kommen aus Raids/RaidPlan. Bearbeitet wird hier nichts: Der
    Plan entsteht in der Webapp und kommt per Import.
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
function View.Clock(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

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

    self.picker = Widgets.Dropdown(bar, {
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
    self.picker:SetPoint("LEFT", bar, "LEFT", 0, 0)

    self.importButton = Widgets.Button(bar, L.RP_IMPORT, function() View:OpenImport() end, "primary")
    self.importButton:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    self.deleteButton = Widgets.Button(bar, L.RP_DELETE, function() View:DeleteActive() end)
    self.deleteButton:SetPoint("RIGHT", self.importButton, "LEFT", -6, 0)
    self.shareButton = Widgets.Button(bar, L.RP_SHARE, function() View:ShareActive() end)
    self.shareButton:SetPoint("RIGHT", self.deleteButton, "LEFT", -6, 0)
    self.arrangeButton = Widgets.Button(bar, L.RP_ARRANGE, function() View:Arrange() end, "primary")
    self.arrangeButton:SetPoint("RIGHT", self.shareButton, "LEFT", -12, 0)

    self.status = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.status:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -6)
    self.status:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    self.status:SetJustifyH("LEFT")

    -- Links: die Gruppen.
    local groups = Widgets.Panel(frame, L.RP_GROUPS, "")
    groups:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -26)
    groups:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    groups:SetWidth(GROUP_W * 2 + 30)
    self.groupsPanel = groups
    self.groupBoxes = {}
    for g = 1, 8 do
        local box = CreateFrame("Frame", nil, groups.content)
        box:SetSize(GROUP_W, 18 + GROUP_ROW * 5)
        local col, row = (g - 1) % 2, math.floor((g - 1) / 2)
        box:SetPoint("TOPLEFT", groups.content, "TOPLEFT", col * (GROUP_W + 12), -row * (18 + GROUP_ROW * 5 + 10))
        box.title = Theme.Label(box, string.format(L.RP_GROUP, g), fonts.small, Theme.color.heading)
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        box.lines = {}
        for i = 1, 5 do
            local line = Theme.Label(box, "", fonts.row, Theme.color.text)
            line:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -16 - (i - 1) * GROUP_ROW)
            line:SetWidth(GROUP_W - 8)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            box.lines[i] = line
        end
        self.groupBoxes[g] = box
    end
    self.bench = Theme.Label(groups.content, "", fonts.small, Theme.color.textDim)
    self.bench:SetPoint("TOPLEFT", groups.content, "TOPLEFT", 0, -4 * (18 + GROUP_ROW * 5 + 10))
    self.bench:SetPoint("RIGHT", groups.content, "RIGHT", 0, 0)
    self.bench:SetJustifyH("LEFT")
    self.bench:SetSpacing(2)

    -- Rechts: Bosse, Notiz, Erinnerungen.
    local bosses = Widgets.Panel(frame, L.RP_BOSSES, "")
    bosses:SetPoint("TOPLEFT", groups, "TOPRIGHT", 8, 0)
    bosses:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    self.bossPanel = bosses

    -- Probelauf (Schritt 4): die Erinnerungen des gewaehlten Bosses so, wie
    -- sie im Kampf erscheinen — alle, nicht nur die eigenen. Dabei laesst
    -- sich die Anzeige verschieben.
    self.previewButton = Widgets.Button(bosses.header or bosses, L.RP_PREVIEW, function() View:TogglePreview() end)
    self.previewButton:SetHeight(18)
    self.previewButton:SetPoint("RIGHT", bosses.header or bosses, "RIGHT", -4, 0)

    self.bossList = Widgets.ScrollList(bosses.content, {
        rowHeight = ROW_H,
        createRow = function(row) View:BuildBossRow(row) end,
        updateRow = function(row, entry) View:UpdateBossRow(row, entry) end,
        onClickRow = function(entry) View.bossIndex = entry.index View:Refresh() end,
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
    })
    self.reminders:SetPoint("TOPLEFT", self.note, "BOTTOMLEFT", -2, -8)
    self.reminders:SetPoint("BOTTOMRIGHT", bosses.content, "BOTTOMRIGHT", 0, 0)

    self.empty = Theme.Label(frame, L.RP_EMPTY, fonts.body, Theme.color.textDim)
    self.empty:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 40, -90)
    self.empty:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetSpacing(3)
    self.empty:Hide()

    for _, name in ipairs({ "RAIDPLAN_CHANGED", "RAIDPLAN_ROSTER", "RAIDPLAN_ARRANGE", "REMINDERS_START", "REMINDERS_STOP" }) do
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
    row.text:SetText(text)
    local c = Theme.color[LEVEL_COLOR[r.level] or "text"] or Theme.color.text
    if not entry.mine then c = Theme.color.textDim end
    row.text:SetTextColor(c[1], c[2], c[3])
    local tc = entry.mine and Theme.color.heading or Theme.color.textDim
    row.to:SetTextColor(tc[1], tc[2], tc[3])
end

-- ================================================================== Inhalt ----

function View:Refresh()
    if not self.frame then return end
    local Plans = plans()
    local entry = Plans:Active()
    local has = entry ~= nil
    self.empty:SetShown(not has)
    self.groupsPanel:SetShown(has)
    self.bossPanel:SetShown(has)
    self.deleteButton:SetEnabledState(has)
    self.shareButton:SetEnabledState(has and entry.wire ~= nil)
    local problem = Plans.arranging and "running" or Plans:ArrangeProblem()
    self.arrangeButton:SetEnabledState(problem == nil, problem and L["RP_ARRANGE_" .. string.upper(problem)] or nil)
    if not has then
        self.picker:SetDisplay(nil)
        self.status:SetText("")
        GA.UI.MainFrame:SetContext("")
        return
    end

    local plan = entry.plan
    if self.planId ~= plan.id then self.planId, self.bossIndex = plan.id, nil end
    self.picker:SetDisplay(View.PlanLabel(plan))
    local me = Plans.WhoAmI(plan)
    local myKey = Plans.NameKey(me.name)
    local sum = Plans.Summary(plan)

    local parts = { string.format(L.RP_REV, plan.rev) }
    if plan.author then parts[#parts + 1] = string.format(L.RP_AUTHOR, plan.author) end
    if entry.from then parts[#parts + 1] = string.format(L.RP_FROM, entry.from, Util.TimeAgo(entry.at)) end
    parts[#parts + 1] = string.format(L.RP_COUNTS, sum.players, sum.bosses, sum.reminders)
    if me.group then parts[#parts + 1] = "|cffffd100" .. string.format(L.RP_YOU, me.group) .. "|r"
    else parts[#parts + 1] = L.RP_YOU_NOT end
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
            if name then
                local role = plan.roles[Plans.NameKey(name)]
                local roleText = role and (" |cff8a8a8a" .. (L["RP_ROLE_" .. string.upper(role)] or role) .. "|r") or ""
                -- Im Raid: wer fehlt, wer woanders steht.
                local where = ""
                local member = cmp and cmp.byKey[Plans.NameKey(name)]
                if cmp and not member then where = " |cffff5050" .. L.RP_MISSING_TAG .. "|r"
                elseif member and member.group ~= g then where = " |cffffd100" .. string.format(L.RP_NOW_IN, member.group) .. "|r" end
                line:SetText((Plans.NameKey(name) == myKey and "> " or "") .. name .. roleText .. where)
                local class = classOf(name)
                if class and not (cmp and not member) then line:SetTextColor(Theme.ClassColor(class))
                else line:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3]) end
            else
                line:SetText("")
            end
        end
        local title = string.format(L.RP_GROUP, g)
        box.title:SetText(g == me.group and ("|cffffd100" .. title .. "|r") or title)
    end
    local benchLines = {}
    if #plan.bench > 0 then benchLines[#benchLines + 1] = string.format(L.RP_BENCH, table.concat(plan.bench, ", ")) end
    if cmp and #cmp.extras > 0 then
        benchLines[#benchLines + 1] = "|cffffd100" .. string.format(L.RP_EXTRAS, table.concat(cmp.extras, ", ")) .. "|r"
    end
    self.bench:SetText(table.concat(benchLines, "\n"))

    -- Bosse
    local list = {}
    for index, boss in ipairs(plan.bosses) do
        local mine = 0
        for _, r in ipairs(boss.reminders) do if Plans.Matches(r, me) then mine = mine + 1 end end
        list[#list + 1] = { index = index, boss = boss, mine = mine }
    end
    if not self.bossIndex or not plan.bosses[self.bossIndex] then self.bossIndex = #list > 0 and 1 or nil end
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
        self.note:SetText(note)
        for _, r in ipairs(boss.reminders) do rows[#rows + 1] = { reminder = r, mine = Plans.Matches(r, me) } end
        self.bossPanel:SetTitle(boss.name or L.RP_BOSSES)
        self.previewButton:SetEnabledState(#boss.reminders > 0)
    else
        self.note:SetText(L.RP_NO_BOSSES)
        self.previewButton:SetEnabledState(false)
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

function View:TogglePreview()
    local Reminders = GA.Modules.Reminders
    if Reminders:IsPreview() then Reminders:Stop("preview") return end
    local entry = plans():Active()
    local boss = entry and self.bossIndex and entry.plan.bosses[self.bossIndex]
    if boss then Reminders:Start(entry.plan, boss, { preview = true }) end
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

function View:OnShow() self:Refresh() end

GA.UI.MainFrame:RegisterView("raidplan", View)
