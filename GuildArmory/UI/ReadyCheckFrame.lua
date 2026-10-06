--[[----------------------------------------------------------------------------
    UI/ReadyCheckFrame — das kleine Fenster beim Ready Check (06.10.2026).
    Die Logik steht in Raids/ReadyCheck.

    Oben, gelb: die Vor-dem-Pull-Hinweise des naechsten Bosses aus dem Plan.
    Darunter, rot: was am eigenen Charakter fehlt. Es sitzt unter der
    Erinnerungsanzeige — wer die verschoben hat, findet beides beieinander.

    Es geht von selbst: 15 Sekunden nach dem Ende des Ready Checks, sofort
    bei Kampfbeginn, oder mit dem X.
------------------------------------------------------------------------------]]

local _, GA = ...

local ReadyCheckFrame = {}
GA.UI.ReadyCheckFrame = ReadyCheckFrame

local Theme = GA.UI.Theme
local L = GA.L

local WIDTH, PAD, LINE = 360, 12, 18
local MAX_LINES = 12
local LINGER = 15

function ReadyCheckFrame:Create()
    if self.frame then return self.frame end
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", "GuildArmoryReadyCheck", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetWidth(WIDTH)
    frame:SetClampedToScreen(true)
    Theme.Fill(frame, { 0.04, 0.04, 0.05, 0.82 })
    Theme.Outline(frame, { 1, 0.82, 0.1, 0.5 })
    frame:Hide()

    frame.title = Theme.Label(frame, "", fonts.title, Theme.color.heading)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -28, 0)
    frame.title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() ReadyCheckFrame:Hide() end)

    frame.lines = {}
    for i = 1, MAX_LINES do
        local line = Theme.Label(frame, "", fonts.row, Theme.color.text)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -34 - (i - 1) * LINE)
        line:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        frame.lines[i] = line
    end
    self.frame = frame
    return frame
end

--- Unter der Erinnerungsanzeige, sonst oben in der Mitte.
function ReadyCheckFrame:Place()
    local frame = self.frame
    frame:ClearAllPoints()
    local reminders = GA.UI.ReminderFrame and GA.UI.ReminderFrame.frame
    if not reminders then GA.UI.ReminderFrame:Create() reminders = GA.UI.ReminderFrame.frame end
    if reminders then
        frame:SetPoint("TOP", reminders, "BOTTOM", 0, -12)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -330)
    end
end

--- Die Zeilen aus einem Ergebnis von ReadyCheck:Evaluate.
function ReadyCheckFrame.Lines(result)
    local out = {}
    for _, text in ipairs(result.prepull or {}) do
        out[#out + 1] = { text = GA.Modules.RaidPlan.RenderText(text), color = { 1, 0.82, 0.1 } }
    end
    for _, issue in ipairs(result.issues or {}) do
        local text
        if issue.key == "DURABILITY" then
            text = string.format(L.RC_DURABILITY, issue.value)
        elseif issue.key == "ENCHANTS" then
            local names = {}
            for _, key in ipairs(issue.value) do names[#names + 1] = L["RC_SLOT_" .. key] or key end
            text = string.format(L.RC_ENCHANTS, table.concat(names, ", "))
        elseif issue.key == "CONSUMABLE" then
            text = L.RC_CONSUMABLE
        end
        if text then out[#out + 1] = { text = text, color = { 1, 0.4, 0.35 } } end
    end
    return out
end

function ReadyCheckFrame:Show(result, forced)
    self:Create()
    local frame = self.frame
    local lines = ReadyCheckFrame.Lines(result)
    if #lines == 0 then
        if not forced then return end
        lines[1] = { text = L.RC_ALL_GOOD, color = { 0.4, 0.9, 0.4 } }
    end
    local boss = result.boss and (result.boss.name or ("#" .. tostring(result.boss.encounterID)))
    frame.title:SetText(boss and string.format(L.RC_TITLE_BOSS, boss) or L.RC_TITLE)
    for i = 1, MAX_LINES do
        local line, item = frame.lines[i], lines[i]
        if item then
            line:SetText(item.text)
            line:SetTextColor(item.color[1], item.color[2], item.color[3])
            line:Show()
        else
            line:Hide()
        end
    end
    frame:SetHeight(34 + math.min(#lines, MAX_LINES) * LINE + PAD)
    self:Place()
    self.token = (self.token or 0) + 1
    frame:Show()
end

function ReadyCheckFrame:Hide()
    if self.frame then self.frame:Hide() end
end

--- Nach dem Ready Check noch ein wenig stehen lassen.
function ReadyCheckFrame:Linger()
    if not self.frame or not self.frame:IsShown() then return end
    self.token = (self.token or 0) + 1
    local token = self.token
    GA.Core.Compat.After(LINGER, function()
        if ReadyCheckFrame.token == token then ReadyCheckFrame:Hide() end
    end)
end

GA.Core.Callbacks:On("READYCHECK_RESULT", function(result, forced) ReadyCheckFrame:Show(result, forced) end, "ReadyCheckFrame")
GA.Core.Callbacks:On("READYCHECK_FINISHED", function() ReadyCheckFrame:Linger() end, "ReadyCheckFrame")
GA.Core.Events:Register("PLAYER_REGEN_DISABLED", function() ReadyCheckFrame:Hide() end, "ReadyCheckFrame")
