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

-- ================================================================ Zeichen ---
--
-- Das eigene Zeichen am Namensschild des Objekts (Quests/Highlight). Ueber
-- dem Symbol des Spiels: Berufssymbol mit einem Rahmen in der Farbe der
-- Stufe, darunter die Stufe — bei einem Questobjekt ein gelbes Ausrufe-
-- zeichen. Die Bilder sind die des Spiels, ueber ihren Pfad.

local MARKER_ICON = {
    [182] = [[Interface\Icons\Spell_Nature_NatureTouchGrow]],   -- Kraeuterkunde
    [186] = [[Interface\Icons\Trade_Mining]],                   -- Bergbau
    quest = [[Interface\GossipFrame\AvailableQuestIcon]],
}

function HighlightFrame:CreateMarker()
    if self.marker then return self.marker end
    local marker = CreateFrame("Frame", "GuildArmoryObjectMarker", UIParent)
    marker:SetSize(34, 34)
    marker:SetFrameStrata("LOW")
    marker:EnableMouse(false)
    marker:Hide()
    marker.border = marker:CreateTexture(nil, "BACKGROUND")
    marker.border:SetPoint("TOPLEFT", marker, "TOPLEFT", -2, 2)
    marker.border:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", 2, -2)
    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetAllPoints(marker)
    marker.text = marker:CreateFontString(nil, "OVERLAY")
    marker.text:SetFontObject(font("GuildArmoryObjectMarkerText", 12))
    marker.text:SetPoint("TOP", marker, "BOTTOM", 0, -2)
    -- Ein sanftes Pulsieren: Es soll ins Auge fallen, nicht blinken.
    if marker.CreateAnimationGroup then
        local group = marker:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1) fade:SetToAlpha(0.55) fade:SetDuration(0.8)
        marker.pulse = group
    end
    self.marker = marker
    return marker
end

--- Haengt das Zeichen an das Namensschild. Ein geschuetztes Schild (in
--- Instanzen) bleibt unberuehrt.
function HighlightFrame:AttachMarker(unit, result)
    local api = _G.C_NamePlate
    if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then return end
    local ok, plate = pcall(api.GetNamePlateForUnit, unit)
    if not ok or not plate then return end
    if plate.IsForbidden and plate:IsForbidden() then return end
    local marker = self:CreateMarker()
    marker:ClearAllPoints()
    if not pcall(marker.SetPoint, marker, "BOTTOM", plate, "TOP", 0, 26) then return end

    local first = result.lines[1] or {}
    local node = result.node
    local icon = (node and MARKER_ICON[node]) or (first.color == "quest" and MARKER_ICON.quest) or MARKER_ICON[182]
    marker.icon:SetTexture(icon)
    if first.color == "quest" then
        marker.icon:SetTexCoord(0, 1, 0, 1)
    else
        marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local c = COLORS[first.color] or COLORS.gray
    marker.border:SetColorTexture(c[1], c[2], c[3], 0.95)
    marker.text:SetText(node and string.match(first.text or "", "%d+") or "")
    marker.text:SetTextColor(c[1], c[2], c[3])
    marker.unit = unit
    marker:Show()
    if marker.pulse then marker.pulse:Play() end
end

function HighlightFrame:DetachMarker(unit)
    local marker = self.marker
    if not marker or (unit and marker.unit ~= unit) then return end
    if marker.pulse then marker.pulse:Stop() end
    marker:Hide()
    marker:ClearAllPoints()
    marker.unit = nil
end

GA.Core.Callbacks:On("HIGHLIGHT_HINT", function(result) HighlightFrame:Show(result) end, "HighlightFrame")
GA.Core.Callbacks:On("HIGHLIGHT_PLATE", function(unit, result) HighlightFrame:AttachMarker(unit, result) end, "HighlightFrame")
GA.Core.Callbacks:On("HIGHLIGHT_PLATE_GONE", function(unit) HighlightFrame:DetachMarker(unit) end, "HighlightFrame")
