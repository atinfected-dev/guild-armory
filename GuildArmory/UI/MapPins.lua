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

-- 14 statt 12, seit die Nadel rund ist: Rand, Flaeche und Glanz sind drei
-- Lagen, und bei zwoelf Pixeln bleiben fuer den Glanz drei uebrig. Das ist
-- kein Lichtpunkt mehr, sondern ein Fleck.
local PIN_SIZE = 14
local TICK = 0.5

-- ================================================================== Nadeln ---

function MapPins:Pin(index)
    self.pins = self.pins or {}
    if self.pins[index] then return self.pins[index] end

    local pin = CreateFrame("Button", nil, self.canvas)
    pin:SetWidth(PIN_SIZE)
    pin:SetHeight(PIN_SIZE)
    pin:SetFrameStrata("HIGH")

    -- RUND, MIT SCHATTIERUNG — UND EINEM WEG ZURUECK.
    --
    -- Drei Lagen: ein dunkler Kreis als Rand, darauf die Klassenfarbe,
    -- darauf ein heller Bogen oben. Der Rand haelt den Punkt von jedem
    -- Kartenuntergrund ab — ohne ihn verschwindet ein dunkelblauer Schamane
    -- im Meer. Der helle Bogen macht aus der Scheibe eine Kugel; ohne ihn
    -- ist "rund" nur die Silhouette.
    --
    -- EINE RUNDE TEXTUR, KEINE MASKE AUF EINER FARBFLAECHE.
    --
    -- Der erste Versuch tat genau das — und die Nadeln blieben eckig,
    -- gemeldet mit Bild am 26.09.2026. Der Aufruf lief durch, pcall meldete
    -- Erfolg, der Rueckfall griff nicht. Ein pcall, der nicht wirft, ist
    -- eben kein Beweis, dass etwas passiert ist.
    pin.rand = pin:CreateTexture(nil, "BACKGROUND")
    pin.rand:SetAllPoints(pin)

    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
    pin.fill:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)

    -- Der Glanz sitzt in der oberen Haelfte und ist schmaler als die
    -- Flaeche: Licht kommt von oben, und ein Glanz ueber die ganze Scheibe
    -- waere Nebel statt Woelbung.
    pin.glanz = pin:CreateTexture(nil, "OVERLAY")
    pin.glanz:SetPoint("TOPLEFT", pin, "TOPLEFT", 3, -3)
    pin.glanz:SetPoint("BOTTOMRIGHT", pin, "CENTER", -3, 0)

    local rund = Theme.RoundTexture(pin.rand, { 0, 0, 0, 0.9 })
        and Theme.RoundTexture(pin.fill)
    pin.rund = rund
    if rund then
        Theme.RoundTexture(pin.glanz, { 1, 1, 1, 0.35 })
    else
        -- Der alte eckige Rand, Linie fuer Linie: Ein viereckiger Punkt ist
        -- haesslich, eine Karte ohne Punkte ist kaputt.
        pin.glanz:Hide()
        pin.rand:Hide()
        Theme.Paint(pin.fill, { 1, 1, 1, 1 })
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
    end

    -- DIE BESCHRIFTUNG STEHT IMMER DA, ohne Hover.
    --
    -- Eine Nadel ohne Namen beantwortet die Frage nicht, die man sich auf
    -- der Karte stellt: nicht "ist da jemand", sondern "wer, und lohnt sich
    -- der Weg". Dafuer muesste man jede einzeln anfahren.
    --
    -- Sie haengt RECHTS an der Nadel und ist nach links verankert: So
    -- wandert der Text nach aussen, waehrend der Punkt auf seiner Stelle
    -- bleibt. Umgekehrt verschoebe ein langer Name die Nadel optisch.
    pin.label = pin:CreateFontString(nil, "OVERLAY")
    pin.label:SetFontObject(Theme.Fonts().pin)
    pin.label:SetPoint("LEFT", pin, "RIGHT", 2, 0)
    pin.label:SetJustifyH("LEFT")

    pin:SetScript("OnEnter", function(self)
        if not self.entry or not _G.GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = Util.ClassColor(self.entry.class)
        -- DER VOLLE NAME, ohne Realm. An der Nadel steht nur der Vorname;
        -- hier gehoert der ganze hin, sonst waere das Zeigen umsonst.
        GameTooltip:SetText(Util.ShortName(self.entry.name), r, g, b)
        -- Stufe und Rang in einer Zeile.
        local zweite = self.entry.level
            and string.format(L.LEVEL_FMT, tostring(self.entry.level)) or nil
        if self.entry.rank then
            zweite = zweite and (zweite .. "  ·  " .. self.entry.rank) or self.entry.rank
        end
        if zweite then
            GameTooltip:AddLine(zweite, 0.66, 0.61, 0.52)
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

    -- EINMAL JE ZEICHNEN GEFRAGT, nicht je Nadel. Der Zugriff ist billig,
    -- aber er laeuft bei zwanzig Nadeln zwanzigmal fuer eine Antwort, die
    -- sich waehrend eines Durchlaufs nicht aendert.
    local beschriften = GA.Core.Config:Get("mapPinLabels") ~= false

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
            -- BEI EINER RUNDEN NADEL WIRD EINGEFAERBT, NICHT UEBERMALT.
            -- Theme.Paint setzt eine Farbflaeche — es wuerde die runde
            -- Textur bei jedem Zeichnen wieder durch ein Quadrat ersetzen,
            -- und zwar erst nach dem ersten Auffrischen. Genau die Sorte
            -- Fehler, die man am Bild sucht und im Aufbau nicht findet.
            if pin.rund then
                pin.fill:SetVertexColor(r, g, b, 1)
            else
                Theme.Paint(pin.fill, { r, g, b, 1 })
            end

            -- NUR DER VORNAME, IN KLASSENFARBE.
            --
            -- Auf Ansage (26.09.2026): "kannst du auf der map nur die
            -- vornamen machen, beim hovern dann den vollen namen und das
            -- level."
            --
            -- Namen haben hier zwei Teile, und auf einer Karte ist der
            -- zweite vor allem Breite: Bei mehreren Nadeln nebeneinander
            -- laufen die Beschriftungen ineinander, und darunter liegt eine
            -- Karte, die jemand lesen will.
            --
            -- Die Karte beantwortet damit "wer ist da", das Zeigen
            -- beantwortet "wer genau, und wie weit" — voller Name, Stufe und
            -- Rang stehen im Tooltip.
            if beschriften then
                pin.label:SetText(
                    Util.ColorByClass(Util.FirstName(entry.name), entry.class))
                pin.label:Show()
            else
                -- LEEREN UND VERSTECKEN. Nur verstecken liesse den alten Text
                -- stehen, und er kaeme beim naechsten Einschalten fuer einen
                -- Augenblick mit dem falschen Namen zurueck.
                pin.label:SetText("")
                pin.label:Hide()
            end

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
        -- ZUERST DIE UHR, DANN ALLES ANDERE.
        --
        -- Hier stand die Abfrage "ist die Karte offen" VOR der Drosselung —
        -- also sechzigmal je Sekunde, jedes Mal mit einem pcall. Das laeuft
        -- den ganzen Abend, auch wenn die Karte nie aufgeht.
        --
        -- WoWs Speicheranzeige je Addon zaehlt ALLES ANGEFORDERTE, nicht das
        -- Belegte. Eine Schleife, die je Bild ein paar Bytes anfordert, steht
        -- nach einer Stunde mit zweistelligen Megabyte da, ohne dass ein
        -- einziges Byte haengengeblieben waere. Gemeldet wurden 18 MB bei
        -- zwei Spielern — daher kam der groesste Teil.
        MapPins.since = (MapPins.since or 0) + delta
        if MapPins.since < TICK then return end
        MapPins.since = 0

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
