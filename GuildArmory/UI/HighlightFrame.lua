--[[----------------------------------------------------------------------------
    UI/HighlightFrame — das eigene Zeichen am markierten Objekt (06.10.2026).
    Die Logik steht in Quests/Highlight.

    Gemessen: Fuer das markierte Objekt legt das Spiel ein Namensschild an.
    Daran haengt dieses Zeichen und wandert mit dem Objekt in der Welt mit —
    ueber dem Symbol des Spiels: Berufssymbol mit einem Rahmen in der Farbe
    der Stufe, darunter die Stufe, bei einem Questobjekt ein gelbes "!".
    Dahinter ein pulsierender Schein in derselben Farbe.

    EIN LEUCHTEN UM DAS OBJEKT SELBST GEHT NICHT: Die Umrandung, die das
    Spiel um anvisierte Einheiten und Objekte zeichnet (graphicsOutlineMode),
    loest nur das Spiel aus — fuer Ziel und Mauszeiger. Ein Addon kommt an
    die 3D-Welt nicht heran. Der Schein liegt deshalb um das Zeichen, das
    direkt ueber dem Objekt haengt.

    Den Texthinweis unter der Bildmitte gab es kurz (06.10.2026); er stand
    zu Fuessen der Figur und ist wieder weg ("der Text am Spieler muss weg").
    Was er sagte, sagt jetzt das Zeichen.
------------------------------------------------------------------------------]]

local _, GA = ...

local HighlightFrame = {}
GA.UI.HighlightFrame = HighlightFrame

local Theme = GA.UI.Theme

local COLORS = {
    red = { 1, 0.25, 0.2 }, orange = { 1, 0.5, 0.15 }, yellow = { 1, 0.85, 0.1 },
    green = { 0.3, 0.9, 0.3 }, gray = { 0.6, 0.6, 0.6 }, quest = { 1, 0.82, 0.1 },
}

local MARKER_ICON = {
    [182] = [[Interface\Icons\Spell_Nature_NatureTouchGrow]],   -- Kraeuterkunde
    [186] = [[Interface\Icons\Trade_Mining]],                   -- Bergbau
    -- Questobjekt: eigenes goldenes "!" (Media/QuestMark, 06.10.2026: "kannst
    -- du das Ausrufezeichen schoener machen … mehr HD"). Faellt die Textur
    -- aus, bleibt Blizzards kleines Questsymbol.
    quest = [[Interface\GossipFrame\AvailableQuestIcon]],
}

local function font(name, size)
    local object = CreateFont(name)
    if not pcall(object.SetFont, object, _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, "OUTLINE") then
        object:SetFontObject(_G.GameFontNormal)
    end
    return object
end

function HighlightFrame:CreateMarker()
    if self.marker then return self.marker end
    local marker = CreateFrame("Frame", "GuildArmoryObjectMarker", UIParent)
    marker:SetSize(34, 34)
    marker:SetFrameStrata("LOW")
    marker:EnableMouse(false)
    marker:Hide()

    -- Der Schein: eigene weiche Textur (Media/Glow), additiv, hinter dem
    -- Symbol. Ein eigener Rahmen, damit nur er pulsiert und das Symbol ruhig
    -- bleibt.
    local halo = CreateFrame("Frame", nil, marker)
    halo:SetPoint("CENTER", marker, "CENTER", 0, 0)
    halo:SetSize(160, 160)
    halo:SetFrameLevel(math.max(0, marker:GetFrameLevel() - 1))
    -- KRAEFTIGER (06.10.2026: "der Glow muss noch staerker werden"): drei
    -- Schichten uebereinander, additiv — ein weiter Schein, ein mittlerer
    -- und ein heller Kern direkt hinter dem Symbol.
    local glow = Theme.Media("glow")
    halo.layers = {}
    for i, size in ipairs({ 160, 110, 70 }) do
        local tex = halo:CreateTexture(nil, "BACKGROUND", nil, i)
        tex:SetPoint("CENTER", halo, "CENTER", 0, 0)
        tex:SetSize(size, size)
        if glow and pcall(tex.SetTexture, tex, glow) then
            pcall(tex.SetBlendMode, tex, "ADD")
        else
            tex:Hide()
        end
        halo.layers[i] = tex
    end
    halo.tex = halo.layers[1]
    if halo.CreateAnimationGroup then
        local group = halo:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local fade = group:CreateAnimation("Alpha")
        -- NUR HELLIGKEIT, KEIN WACHSEN (06.10.2026: "pulsiert zu stark, sieht
        -- aus, als wuerde es ruckeln"). Beim Skalieren wird der Schein jedes
        -- Bild neu auf Pixel gerundet und zittert. Langsam und flach atmen.
        fade:SetFromAlpha(1) fade:SetToAlpha(0.8) fade:SetDuration(1.6)
        if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
        halo.pulse = group
    end
    marker.halo = halo

    marker.border = marker:CreateTexture(nil, "BORDER")
    marker.border:SetPoint("TOPLEFT", marker, "TOPLEFT", -2, 2)
    marker.border:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", 2, -2)
    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetAllPoints(marker)
    marker.text = marker:CreateFontString(nil, "OVERLAY")
    marker.text:SetFontObject(font("GuildArmoryObjectMarkerText", 12))
    marker.text:SetPoint("TOP", marker, "BOTTOM", 0, -2)
    self.marker = marker
    return marker
end

-- ========================================================== Spielsymbol ---
--
-- BLIZZARDS SYMBOL AUSBLENDEN (06.10.2026: "kannst du das Softinteract-
-- Symbol komplett ausblenden?"). Nicht ueber die Spieleinstellung: Das
-- Namensschild entsteht vermutlich gerade WEGEN des Symbols (gemessen: es
-- kommt auch mit SoftTargetNameplateInteract=0) — ohne Symbol kein Schild,
-- ohne Schild kein eigenes Zeichen. Stattdessen wird das Symbol auf DIESEM
-- Schild unsichtbar, solange unser Zeichen daran haengt, und beim Abhaengen
-- wieder sichtbar: Schilder werden vom Spiel wiederverwendet.
--
-- WO ES SITZT, IST AUF FOREVER NICHT GEMESSEN. Versucht werden die Stellen,
-- an denen Retail es fuehrt; /ga probe softinteract schreibt den Aufbau des
-- Schilds mit, falls keine passt.

--- Das Symbol des Spiels am Schild — oder nil.
function HighlightFrame.GameIcon(plate)
    local uf = plate and plate.UnitFrame
    for _, frame in ipairs({ uf and uf.SoftTargetFrame, plate and plate.SoftTargetFrame,
                             uf and uf.softTargetFrame }) do
        if type(frame) == "table" and type(frame.SetAlpha) == "function" then return frame end
    end
    return nil
end

--- [unit] = das versteckte Symbol, damit es beim Abhaengen zurueckkommt.
local hidden = {}

--- DAS SPIEL SETZT DIE DECKKRAFT SELBST (gemessen 06.10.2026: Symbol am
--- richtigen Ort gefunden — UnitFrame.SoftTargetFrame —, und trotzdem zu
--- sehen). Es blendet das Symbol nach Reichweite ab und auf, grau und
--- farbig, und ueberschreibt dabei ein einmaliges SetAlpha(0). Deshalb
--- haengt sich das Addon NACH jedes SetAlpha und Show des Spiels und setzt
--- die Deckkraft wieder auf 0, solange das Symbol versteckt sein soll.
--- hooksecurefunc ruft hinterher auf und veraendert den Aufruf des Spiels
--- nicht. Einmal je Rahmen — das Spiel verwendet Schilder wieder.
local function keepHidden(frame)
    if frame.gaHideHooked or type(_G.hooksecurefunc) ~= "function" then return end
    frame.gaHideHooked = true
    local function reapply(self)
        if self.gaHidden and not self.gaHiding then
            self.gaHiding = true
            pcall(self.SetAlpha, self, 0)
            self.gaHiding = nil
        end
    end
    pcall(hooksecurefunc, frame, "SetAlpha", reapply)
    pcall(hooksecurefunc, frame, "Show", reapply)
    pcall(hooksecurefunc, frame, "SetShown", reapply)
end

function HighlightFrame:HideGameIcon(unit)
    if GA.Core.Config:Get("highlightHideGameIcon") == false then return end
    local api = _G.C_NamePlate
    if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then return end
    local ok, plate = pcall(api.GetNamePlateForUnit, unit)
    if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local icon = HighlightFrame.GameIcon(plate)
    if not icon then return end
    -- Der Rahmen UND das Bild darin: Fuehrt das Bild seine Deckkraft
    -- unabhaengig vom Rahmen, haelt es sonst sichtbar.
    local parts = { icon }
    if type(icon.Icon) == "table" and type(icon.Icon.SetAlpha) == "function" then parts[2] = icon.Icon end
    for _, part in ipairs(parts) do
        keepHidden(part)
        part.gaHidden = true
        pcall(part.SetAlpha, part, 0)
    end
    hidden[unit] = parts
end

function HighlightFrame:RestoreGameIcon(unit)
    for _, part in ipairs(hidden[unit] or {}) do
        part.gaHidden = nil
        pcall(part.SetAlpha, part, 1)
    end
    hidden[unit] = nil
end

--- Alle wieder sichtbar (Schalter aus).
function HighlightFrame:RestoreAllGameIcons()
    for unit in pairs(hidden) do self:RestoreGameIcon(unit) end
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
    local c = COLORS[first.color] or COLORS.gray
    local questMark = not node and first.color == "quest" and Theme.Media("questmark")
    if questMark then
        -- Das "!" steht frei, ohne Rahmen: hoch statt quadratisch.
        marker:SetSize(20, 40)   -- etwas kleiner (06.10.2026), vorher 28x56
        marker.icon:SetTexture(questMark)
        marker.icon:SetTexCoord(0, 1, 0, 1)
        marker.border:Hide()
    else
        marker:SetSize(34, 34)
        local icon = (node and MARKER_ICON[node]) or (first.color == "quest" and MARKER_ICON.quest) or MARKER_ICON[182]
        marker.icon:SetTexture(icon)
        if first.color == "quest" then
            marker.icon:SetTexCoord(0, 1, 0, 1)
            marker.border:Hide()
        else
            marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            Theme.Paint(marker.border, { c[1], c[2], c[3], 0.95 })
            marker.border:Show()
        end
    end
    for _, tex in ipairs(marker.halo.layers) do tex:SetVertexColor(c[1], c[2], c[3], 1) end
    marker.text:SetText(node and string.match(first.text or "", "%d+") or "")
    marker.text:SetTextColor(c[1], c[2], c[3])
    marker.unit = unit
    marker:Show()
    if marker.halo.pulse then marker.halo.pulse:Play() end
end

function HighlightFrame:DetachMarker(unit)
    local marker = self.marker
    if not marker or (unit and marker.unit ~= unit) then return end
    if marker.halo.pulse then marker.halo.pulse:Stop() end
    marker:Hide()
    marker:ClearAllPoints()
    marker.unit = nil
end

GA.Core.Callbacks:On("HIGHLIGHT_OBJECT_PLATE", function(unit) HighlightFrame:HideGameIcon(unit) end, "HighlightFrame")
GA.Core.Callbacks:On("HIGHLIGHT_OBJECT_PLATE_GONE", function(unit) HighlightFrame:RestoreGameIcon(unit) end, "HighlightFrame")
GA.Core.Callbacks:On("HIGHLIGHT_PLATE", function(unit, result) HighlightFrame:AttachMarker(unit, result) end, "HighlightFrame")
GA.Core.Callbacks:On("HIGHLIGHT_PLATE_GONE", function(unit) HighlightFrame:DetachMarker(unit) end, "HighlightFrame")
