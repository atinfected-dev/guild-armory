--[[----------------------------------------------------------------------------
    UI/HighlightFrame — der Hinweis zum markierten Objekt (06.10.2026).
    Die Logik steht in Quests/Highlight.

    Unter der Bildmitte, ohne Hintergrund: oben der Name des Objekts, darunter
    je eine Zeile fuer Beruf und Quest. Er steht, solange das Objekt markiert
    ist, und geht, sobald es das nicht mehr ist. Er faengt keine Klicks.
------------------------------------------------------------------------------]]

local _, GA = ...

local HighlightFrame = {}
GA.UI.HighlightFrame = HighlightFrame

local LINES = 3
local COLORS = {
    red = { 1, 0.25, 0.2 }, orange = { 1, 0.5, 0.15 }, yellow = { 1, 0.85, 0.1 },
    green = { 0.3, 0.9, 0.3 }, gray = { 0.6, 0.6, 0.6 }, quest = { 1, 0.82, 0.1 },
}

local function font(name, size)
    local object = CreateFont(name)
    if not pcall(object.SetFont, object, _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, "OUTLINE") then
        object:SetFontObject(_G.GameFontNormal)
    end
    return object
end

function HighlightFrame:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "GuildArmoryObjectHint", UIParent)
    frame:SetSize(420, 20 + LINES * 18)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)
    frame:Hide()
    frame.name = frame:CreateFontString(nil, "OVERLAY")
    frame.name:SetFontObject(font("GuildArmoryObjectHintName", 16))
    frame.name:SetPoint("TOP", frame, "TOP", 0, 0)
    frame.lines = {}
    for i = 1, LINES do
        local line = frame:CreateFontString(nil, "OVERLAY")
        line:SetFontObject(font("GuildArmoryObjectHintLine" .. i, 13))
        line:SetPoint("TOP", i == 1 and frame.name or frame.lines[i - 1], "BOTTOM", 0, -3)
        line:SetWidth(420)
        line:SetWordWrap(false)
        frame.lines[i] = line
    end
    self.frame = frame
    return frame
end

function HighlightFrame:Show(result)
    if not result then
        if self.frame then self.frame:Hide() end
        return
    end
    local frame = self:Create()
    frame.name:SetText(result.name or "")
    frame.name:SetTextColor(1, 1, 1)
    for i = 1, LINES do
        local item = result.lines[i]
        if item then
            local c = COLORS[item.color] or COLORS.gray
            frame.lines[i]:SetText(item.text)
            frame.lines[i]:SetTextColor(c[1], c[2], c[3])
            frame.lines[i]:Show()
        else
            frame.lines[i]:Hide()
        end
    end
    frame:Show()
end

GA.Core.Callbacks:On("HIGHLIGHT_HINT", function(result) HighlightFrame:Show(result) end, "HighlightFrame")
