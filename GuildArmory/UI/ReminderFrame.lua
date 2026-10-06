--[[----------------------------------------------------------------------------
    UI/ReminderFrame — die Erinnerungen des Raidplans auf dem Bildschirm.
    Schritt 4, 06.10.2026. Die Logik steht in Raids/Reminders.

    Bis zu fuenf Zeilen uebereinander, die naechste oben: Symbol, Text,
    Countdown und ein Balken, der bis zum Zeitpunkt der Mechanik leerlaeuft.
    "warn" gelb, "alert" rot und gross, "info" weiss und klein.

    IM KAMPF FAENGT DIE ANZEIGE KEINE KLICKS: Sie liegt mitten im Bild, und
    ein Klick auf sie waere ein Klick, der in der Welt fehlt. Verschieben
    laesst sie sich im Probelauf und im Verschiebemodus (/ga reminder move,
    Einstellungen, 06.10.2026: "man muss sich die Reminder selbst an eine
    Stelle ziehen koennen") — dann haelt sie die Maus, zeigt Beispielzeilen
    und merkt sich die Lage. Beginnt ein Kampf, wird sie sofort gesperrt.
------------------------------------------------------------------------------]]

local _, GA = ...

local ReminderFrame = {}
GA.UI.ReminderFrame = ReminderFrame

local Theme = GA.UI.Theme
local L = GA.L

local LINES = 5
local LINE_H = 34
local WIDTH = 460
local TICK = 0.05

local STYLE = {
    info  = { size = 16, color = { 0.92, 0.92, 0.92 } },
    warn  = { size = 21, color = { 1.00, 0.82, 0.10 } },
    alert = { size = 26, color = { 1.00, 0.25, 0.20 } },
}

local fontCache = {}
local function font(level)
    if fontCache[level] then return fontCache[level] end
    local style = STYLE[level] or STYLE.warn
    local object = CreateFont("GuildArmoryReminderFont_" .. level)
    local path = _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
    if not pcall(object.SetFont, object, path, style.size, "OUTLINE") then
        object:SetFontObject(_G.GameFontNormalLarge)
    end
    fontCache[level] = object
    return object
end

function ReminderFrame:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "GuildArmoryReminders", UIParent)
    frame:SetSize(WIDTH, LINES * LINE_H)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        ReminderFrame:SavePlacement()
    end)
    frame:Hide()

    -- Im Probelauf sichtbar: wo die Anzeige sitzt, und dass man sie ziehen kann.
    -- KEIN HINTERGRUND (06.10.2026: "Geht das ohne background?"): Die Zeilen
    -- stehen frei im Bild. Nur im Verschiebemodus zeigt ein duenner Rahmen,
    -- wo die Anzeige liegt und wo man sie greift.
    frame.outline = Theme.Outline(frame, { 1, 0.82, 0.1, 0.45 })
    frame.hint = Theme.Label(frame, L.RP_REMINDER_DRAG, Theme.Fonts().small, Theme.color.textDim)
    frame.hint:SetPoint("BOTTOM", frame, "TOP", 0, 4)

    frame.lines = {}
    for i = 1, LINES do
        local line = CreateFrame("Frame", nil, frame)
        line:SetSize(WIDTH, LINE_H - 4)
        line:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * LINE_H)
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(26, 26)
        line.icon:SetPoint("LEFT", line, "LEFT", 0, 2)
        line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        line.text = line:CreateFontString(nil, "OVERLAY")
        line.text:SetFontObject(font("warn"))
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
        line.text:SetPoint("RIGHT", line, "RIGHT", -56, 0)
        line.text:SetJustifyH("LEFT")
        line.text:SetWordWrap(false)
        line.count = line:CreateFontString(nil, "OVERLAY")
        line.count:SetFontObject(font("warn"))
        line.count:SetPoint("RIGHT", line, "RIGHT", 0, 0)
        line.count:SetJustifyH("RIGHT")
        line.track = line:CreateTexture(nil, "BACKGROUND")
        line.track:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 34, -2)
        line.track:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 0, -2)
        line.track:SetHeight(3)
        Theme.Paint(line.track, { 0, 0, 0, 0.5 })
        line.bar = line:CreateTexture(nil, "ARTWORK")
        line.bar:SetPoint("TOPLEFT", line.track, "TOPLEFT", 0, 0)
        line.bar:SetHeight(3)
        line:Hide()
        frame.lines[i] = line
    end

    -- Verschiebemodus: "Fertig" unter der Anzeige.
    frame.done = GA.UI.Widgets.Button(frame, L.RP_REMINDER_LOCK, function() ReminderFrame:SetUnlocked(false) end, "primary")
    frame.done:SetPoint("TOP", frame, "BOTTOM", 0, -6)
    frame.done:Hide()

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < TICK then return end
        elapsed = 0
        local visible = GA.Modules.Reminders:Tick()
        if #visible == 0 and not GA.Modules.Reminders.run and ReminderFrame.unlocked then
            visible = ReminderFrame.Samples()
        end
        if ReminderFrame.frame:IsShown() then ReminderFrame:Render(visible) end
    end)

    self.frame = frame
    self:ApplyPlacement()
    return frame
end

function ReminderFrame:ApplyPlacement()
    local saved = GA.Core.Config:GetUI("reminder") or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(saved.point or "TOP", UIParent, saved.point or "TOP", saved.x or 0, saved.y or -160)
end

function ReminderFrame:SavePlacement()
    local point, _, _, x, y = self.frame:GetPoint(1)
    local ui = GA.Core.Database.account.ui
    ui.reminder = ui.reminder or {}
    ui.reminder.point, ui.reminder.x, ui.reminder.y = point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

--- Zeichnet die sichtbaren Erinnerungen (aus Reminders:Tick).
function ReminderFrame:Render(visible)
    local frame = self.frame
    for i = 1, LINES do
        local line, item = frame.lines[i], visible[i]
        if item then
            local r = item.reminder
            local style = STYLE[r.level] or STYLE.warn
            line.text:SetFontObject(font(r.level))
            line.count:SetFontObject(font(r.level))

            local text = r.text
            if not text and r.spell then text = GA.Core.Compat.GetSpellName(r.spell) end
            -- Im Probelauf steht bei fremden Erinnerungen, fuer wen sie sind.
            if not item.mine then
                text = "|cff9a9a9a[" .. GA.Modules.RaidPlan.TargetText(r) .. "]|r " .. (text or "")
            end
            line.text:SetText(text or "")
            local alpha = item.mine and 1 or 0.6
            line.text:SetTextColor(style.color[1], style.color[2], style.color[3], alpha)
            line.count:SetTextColor(style.color[1], style.color[2], style.color[3], alpha)

            local icon = r.spell and GA.Core.Compat.GetSpellIcon(r.spell)
            if icon and pcall(line.icon.SetTexture, line.icon, icon) then line.icon:Show() else line.icon:Hide() end

            -- Countdown bis zum Zeitpunkt; danach "jetzt", solange sie steht.
            if item.remaining > 0 then
                line.count:SetText(item.remaining < 3 and string.format("%.1f", item.remaining)
                    or tostring(math.ceil(item.remaining)))
                local share = r.lead > 0 and math.min(1, item.remaining / r.lead) or 0
                line.bar:SetWidth(math.max(1, (WIDTH - 34) * share))
                Theme.Paint(line.bar, { style.color[1], style.color[2], style.color[3], 0.9 * alpha })
                line.bar:Show()
            else
                line.count:SetText(L.RP_NOW)
                line.bar:Hide()
            end
            line:Show()
        else
            line:Hide()
        end
    end
end

--- Beispielzeilen fuer den Verschiebemodus: jede Stufe einmal.
function ReminderFrame.Samples()
    return {
        { mine = true, remaining = 3.4, reminder = { text = L.RP_DEMO_ALERT, level = "alert", lead = 5, dur = 4 } },
        { mine = true, remaining = 7, reminder = { text = L.RP_DEMO_WARN, level = "warn", lead = 10, dur = 4 } },
        { mine = true, remaining = -1, reminder = { text = L.RP_DEMO_INFO, level = "info", lead = 5, dur = 4 } },
    }
end

--- Maus und Hinweis: nur im Verschiebemodus oder Probelauf.
function ReminderFrame:UpdateMode()
    local run = GA.Modules.Reminders.run
    local movable = self.unlocked or (run and run.preview) or false
    self.frame:EnableMouse(movable and true or false)
    for _, edge in ipairs(self.frame.outline) do edge:SetShown(self.unlocked and true or false) end
    self.frame.hint:SetShown(movable and true or false)
    self.frame.done:SetShown(self.unlocked and true or false)
    if run or self.unlocked then
        self.frame:Show()
    else
        self:Render({})
        self.frame:Hide()
    end
end

--- Verschiebemodus an oder aus. Im Kampf nicht.
--- @return boolean an
function ReminderFrame:SetUnlocked(on)
    self:Create()
    if on and GA.Core.Compat.InCombat() then on = false end
    self.unlocked = on and true or false
    self:UpdateMode()
    return self.unlocked
end

function ReminderFrame:ToggleUnlocked() return self:SetUnlocked(not self.unlocked) end

--- Zurueck an die Ausgangsstelle (oben in der Mitte).
function ReminderFrame:ResetPlacement()
    GA.Core.Database.account.ui.reminder = { point = "TOP", x = 0, y = -160 }
    if self.frame then self:ApplyPlacement() end
end

function ReminderFrame:OnStart()
    self:Create()
    self:UpdateMode()
end

function ReminderFrame:OnStop()
    if not self.frame then return end
    self:UpdateMode()
end

GA.Core.Callbacks:On("REMINDERS_START", function(run) ReminderFrame:OnStart(run) end, "ReminderFrame")
GA.Core.Callbacks:On("REMINDERS_STOP", function() ReminderFrame:OnStop() end, "ReminderFrame")

-- Ein Kampf beginnt: Verschiebemodus aus, die Anzeige faengt keine Klicks mehr.
GA.Core.Events:Register("PLAYER_REGEN_DISABLED", function()
    if ReminderFrame.unlocked then ReminderFrame:SetUnlocked(false) end
end, "ReminderFrame")
