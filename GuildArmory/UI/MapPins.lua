--[[----------------------------------------------------------------------------
    UI/MapPins — Gildenmitglieder als Nadeln auf Blizzards Weltkarte.

    KEINE AUSWERTUNG HIER. Wer wo steht, entscheidet Map/Positions.lua; diese
    Datei rechnet Kartenanteile in Pixel um und setzt Nadeln.

    ===========================================================================
    DIE ANGEZEIGTE KARTE, NICHT DIE EIGENE
    ===========================================================================

    Wer die Weltkarte aufzieht und nach Kalimdor blaettert, steht immer noch in
    Sturmwind. Gezeichnet wird deshalb nach WorldMapFrame:GetMapID(), nie nach
    der eigenen Position — sonst klebten die Nadeln des eigenen Tals auf jeder
    Karte, durch die man blaettert.

    ===========================================================================
    EIN TAKT STATT EINES HAKENS
    ===========================================================================

    Es gibt auf jeder Spiellinie einen anderen Weg, den Kartenwechsel zu
    erfahren — OnMapChanged, WORLD_MAP_UPDATE, ein Datenanbieter. Keiner davon
    ist auf Forever gemessen.

    Solange die Karte offen ist, sieht deshalb ein Takt alle TICK Sekunden
    nach, welche Karte darin steht. Das ist zwei Aufrufe je Sekunde, aber NUR
    bei offener Karte — und es funktioniert auf jeder Linie gleich, statt auf
    einer zu funktionieren und auf den anderen still nichts zu tun.

    ===========================================================================
    DIE EIGENE NADEL FEHLT MIT ABSICHT
    ===========================================================================

    Blizzard zeichnet den eigenen Pfeil schon. Eine zweite Markierung an
    derselben Stelle waere nur im Weg.

    Sie war einmal kurz drin, mit dem Argument, ohne sich selbst fehle der
    Massstab. Das Argument traegt nicht: Wer wissen will, wie weit jemand
    weg ist, sieht den Pfeil des Spiels ohnehin.
------------------------------------------------------------------------------]]

local _, GA = ...

local MapPins = {}
GA.UI.MapPins = MapPins

local Theme = GA.UI.Theme
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

local PIN_SIZE = 12
local TICK = 0.5

-- ================================================================== Nadeln ---

function MapPins:Pin(index)
    self.pins = self.pins or {}
    if self.pins[index] then return self.pins[index] end

    local pin = CreateFrame("Button", nil, self.canvas)
    pin:SetWidth(PIN_SIZE)
    pin:SetHeight(PIN_SIZE)
    pin:SetFrameStrata("HIGH")

    -- Erst die Flaeche, dann der Rand: Die Flaeche traegt die Klassenfarbe,
    -- der Rand haelt sie von jedem Kartenuntergrund ab. Ohne ihn verschwindet
    -- ein dunkelblauer Schamane im Meer.
    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
    pin.fill:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)

    pin.ring = {}
    for _, seite in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = pin:CreateTexture(nil, "BACKGROUND")
        Theme.Paint(line, { 0, 0, 0, 0.9 })
        if seite == "TOP" or seite == "BOTTOM" then
            line:SetHeight(2)
            line:SetPoint(seite .. "LEFT", pin, seite .. "LEFT", 0, 0)
            line:SetPoint(seite .. "RIGHT", pin, seite .. "RIGHT", 0, 0)
        else
            line:SetWidth(2)
            line:SetPoint("TOP" .. seite, pin, "TOP" .. seite, 0, 0)
            line:SetPoint("BOTTOM" .. seite, pin, "BOTTOM" .. seite, 0, 0)
        end
        pin.ring[#pin.ring + 1] = line
    end

    pin:SetScript("OnEnter", function(self)
        if not self.entry or not _G.GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = Util.ClassColor(self.entry.class)
        GameTooltip:SetText(self.entry.name, r, g, b)
        if self.entry.rank then
            GameTooltip:AddLine(self.entry.rank, 0.66, 0.61, 0.52)
        end
        -- DAS ALTER GEHOERT DAZU. Eine Nadel sieht immer gleich frisch aus;
        -- ob sie zehn Sekunden oder vier Minuten alt ist, entscheidet, ob
        -- man hinlaeuft.
        GameTooltip:AddLine(Util.TimeAgo(self.entry.ts), 0.44, 0.40, 0.33)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function()
        if _G.GameTooltip then GameTooltip:Hide() end
    end)

    self.pins[index] = pin
    return pin
end

-- ================================================================ Zeichnen ---

function MapPins:Refresh()
    local Positions = GA.Modules.Positions
    if not Positions then return end

    -- DIE FLAECHE BEI JEDEM ZEICHNEN NEU HOLEN, nicht einmal gemerkt.
    --
    -- Blizzard baut die Karte um, wenn das Questlog auf- oder zugeht, und
    -- eine beim Anhaengen gemerkte Flaeche ist danach die falsche. Der
    -- Aufruf kostet nichts; ein Nadelfeld, das sich auf einen alten Rahmen
    -- bezieht, kostet Vertrauen.
    local canvas = Compat.GetMapCanvas()
    self.canvas = canvas
    if not canvas then self:HideAll() return end

    local mapID = Compat.GetDisplayedMapID()
    local breite = canvas:GetWidth() or 0
    local hoehe = canvas:GetHeight() or 0

    -- OHNE BEKANNTE GROESSE WIRD NICHTS GESETZT. Ein auf Breite 0 gerechneter
    -- Punkt landet in der Ecke, und dort saehe er aus wie eine Aussage.
    if not mapID or breite <= 1 or hoehe <= 1 then
        self:HideAll()
        return
    end

    local sichtbar = 0
    for _, entry in ipairs(Positions:All()) do
      -- DIE EIGENE NADEL BLEIBT DRAUSSEN. Siehe Dateikopf: Blizzard zeichnet
      -- den Pfeil, und zwei Markierungen an derselben Stelle sind eine zu
      -- viel.
      if not entry.own then
        -- AUF DIE ANGEZEIGTE KARTE UMRECHNEN. Gespeichert ist die Position
        -- auf der Zonenkarte; wer die Kontinentkarte aufzieht, saehe sonst
        -- gar nichts, obwohl alle Daten da sind.
        local x, y = entry.x, entry.y
        if entry.mapID ~= mapID then
            x, y = Compat.TranslateMapPosition(entry.mapID, entry.x, entry.y, mapID)
        end

        if x then
            sichtbar = sichtbar + 1
            local pin = self:Pin(sichtbar)
            pin.entry = entry

            local r, g, b = Util.ClassColor(entry.class)
            Theme.Paint(pin.fill, { r, g, b, 1 })

            -- ERST UMHAENGEN, DANN SETZEN. Ein Anker auf einen Rahmen,
            -- der gleich ausgetauscht wird, ist einer zu viel.
            pin:SetParent(canvas)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", x * breite, -(y * hoehe))
            pin:Show()
        end
      end
    end

    for index = sichtbar + 1, #(self.pins or {}) do
        self.pins[index]:Hide()
    end
    self.shown = sichtbar
end

function MapPins:HideAll()
    for _, pin in ipairs(self.pins or {}) do pin:Hide() end
    self.shown = 0
end

-- ================================================================== Anhaken --

--- Haengt den Takt an die Weltkarte.
---
--- NICHT BEIM ANHAENGEN NACH DER FLAECHE SUCHEN.
---
--- Blizzard_MapCanvas wird bei Bedarf nachgeladen — vor dem ersten Oeffnen
--- der Weltkarte gibt es die Flaeche gar nicht. Die erste Fassung suchte
--- einmal, meldete "keine Kartenflaeche" und sah nie wieder nach: Wer die
--- Karte erst nach dem Anmelden aufzog, bekam nie Nadeln.
---
--- Angehaengt wird deshalb nur der Takt. Die Flaeche holt sich jedes
--- Zeichnen selbst, und gemeldet wird erst, wenn die Karte OFFEN ist und
--- trotzdem keine da war — dann ist es wirklich eine Auskunft.
function MapPins:Attach()
    if self.ticker then return true end

    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, delta)
        if not Compat.IsWorldMapShown() then
            if MapPins.wasShown then
                MapPins.wasShown = false
                MapPins:HideAll()
            end
            return
        end

        if not MapPins.wasShown then
            MapPins.wasShown = true
            -- Beim Aufziehen einmal fragen: frische Daten genau dann, wenn
            -- jemand hinsieht.
            if GA.Modules.Positions then GA.Modules.Positions:Request() end

            -- ERST JETZT MELDEN, WENN ES NICHTS GIBT. Die Karte ist offen,
            -- die Flaeche muesste also da sein — vorher waere dieselbe
            -- Meldung nur die Auskunft, dass noch niemand die Karte
            -- aufgezogen hat. EINMAL je Sitzung, nicht bei jedem Oeffnen.
            if not Compat.GetMapCanvas() and not MapPins.warned then
                MapPins.warned = true
                GA.Core.Debug:Warn("%s", L.MAP_NO_CANVAS)
            end
        end

        MapPins.since = (MapPins.since or 0) + delta
        if MapPins.since < TICK then return end
        MapPins.since = 0
        MapPins:Refresh()
    end)
    self.ticker = ticker

    GA.Core.Callbacks:On("POSITIONS_CHANGED", function()
        if Compat.IsWorldMapShown() then MapPins:Refresh() end
    end, "MapPins")

    return true
end

GA.Core.Callbacks:On("ADDON_READY", function()
    -- Der Takt kann sofort laufen: Er tut nichts, solange die Karte zu ist,
    -- und holt sich die Flaeche beim Zeichnen selbst. Auf Blizzard_MapCanvas
    -- zu warten hiesse zu raten, wann es nachgeladen wird.
    MapPins:Attach()
end, "MapPins")
