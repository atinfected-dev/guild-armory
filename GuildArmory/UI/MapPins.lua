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

-- 22, am Bildschirm gefunden. Der Weg war 12 (farbiger Punkt), 14, 16
-- (Klassenwappen), 20, 24 — und 24 war eine Stufe zu viel.
--
-- Ein Wappen braucht Platz, um eines zu sein; nach oben ist die Grenze die
-- Karte selbst. Was die Nadel verdeckt, kann niemand mehr lesen, und bei
-- zwanzig Gildenmitgliedern in einer Zone wird daraus eine
-- Wappensammlung.
--
-- Die Zahl gilt seit dem Massstabsausgleich weiter unten fuer JEDE
-- Aufloesung und jede Zoomstufe gleich. Vorher waere sie nur fuer einen
-- Bildschirm richtig gewesen.
local PIN_SIZE = 22

--- Die Farbe des Rands um die Nadel.
---
--- WEISS, NICHT SCHWARZ (26.09.2026 auf Ansage: "so sieht man es denke ich
--- besser"). Der Rand hat eine Aufgabe — die Nadel von der Karte
--- abzusetzen —, und welche Farbe sie erfuellt, haengt am Untergrund: Auf
--- einem hellen Pergament trennt Schwarz besser, auf dunklem Wasser und
--- Wald Weiss.
---
--- Das Wappen selbst ist dunkel (tiefes Blau, Schwarz, Gold). Ein dunkler
--- Rand darum vergroessert also nur den dunklen Fleck; ein heller macht
--- daraus eine Marke mit Kante. Am Bildschirm entschieden, nicht
--- ausgerechnet.
local RAND_FARBE = { 1, 1, 1, 0.9 }
local TICK = 0.5

--- AB VIER WIRD GEBUENDELT (27.09.2026 auf Ansage: "wenn mehr als 3 in
--- einem Umkreis sind"). Stehen so viele Nadeln uebereinander, ist keine
--- mehr zu lesen — weder Wappen noch Name. Dann steht dort EINE Nadel mit
--- der Zahl, und wer zeigt, sieht, wer alles dort ist.
---
--- Der Umkreis ist die Nadel selbst: Zwei Nadeln, deren Mitten naeher
--- beieinander liegen als eine Nadel breit ist, ueberschneiden sich.
local CLUSTER_MIN = 4

-- ================================================================== Nadeln ---

function MapPins:Pin(index)
    self.pins = self.pins or {}
    if self.pins[index] then return self.pins[index] end

    local pin = CreateFrame("Button", nil, self.canvas)
    pin:SetWidth(PIN_SIZE)
    pin:SetHeight(PIN_SIZE)
    pin:SetFrameStrata("HIGH")

    -- RUND: DAS KLASSENWAPPEN, NICHT EINE EINGEFAERBTE SCHEIBE.
    --
    -- ZWEIMAL GERATEN, ZWEIMAL DANEBEN (26.09.2026, beide Male mit Bild
    -- gemeldet). Erst eine Maske ueber einer Farbflaeche, dann die Maske
    -- als Bild: Beide Male lief der Aufruf durch, beide Male blieb die
    -- Nadel eckig. Diese Linie nimmt Maskenaufrufe entgegen und tut nichts
    -- damit.
    --
    -- UI-Classes-Circles rendert hier NACHWEISLICH rund — daran haengt das
    -- Portrait im Dashboard, und das ist gesehen worden. Also wird diese
    -- Kunst genommen statt einer dritten Vermutung.
    --
    -- Es ist dabei die bessere Nadel: Ein farbiger Punkt sagt die Klasse
    -- ueber einen Farbton, den man gelernt haben muss; das Wappen sagt sie
    -- direkt.
    --
    -- DER RAND IST DASSELBE WAPPEN IN SCHWARZ, etwas groesser. Er hat
    -- damit genau dieselbe Silhouette — ein Kreis dahinter waere an den
    -- Raendern zu sehen — und haelt den Punkt von jedem Kartenuntergrund
    -- ab. Ohne ihn verschwindet ein dunkler Schamane im Meer.
    pin.rand = pin:CreateTexture(nil, "BACKGROUND")
    pin.rand:SetAllPoints(pin)

    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
    pin.fill:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)

    -- Der eckige Rueckfall wird IMMER gebaut und nur versteckt: Ob das
    -- Wappen sitzt, entscheidet sich erst beim Zeichnen, wenn die Klasse
    -- bekannt ist — und ein Spieler ohne gemeldete Klasse braucht ihn dann
    -- sofort.
    pin.ring = {}
    for _, seite in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = pin:CreateTexture(nil, "BORDER")
        Theme.Paint(line, RAND_FARBE)
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

    -- DIE BESCHRIFTUNG STEHT IMMER DA, ohne Hover.
    --
    -- Eine Nadel ohne Namen beantwortet die Frage nicht, die man sich auf
    -- der Karte stellt: nicht "ist da jemand", sondern "wer, und lohnt sich
    -- der Weg". Dafuer muesste man jede einzeln anfahren.
    --
    -- SIE STEHT MITTIG UEBER DER NADEL (26.09.2026 auf Ansage).
    --
    -- Vorher hing sie rechts daneben. Das hatte einen Grund — ein langer
    -- Name sollte nach aussen wachsen, statt die Nadel optisch zu
    -- verschieben —, und mittig loest dasselbe besser: Der Text waechst nach
    -- BEIDEN Seiten, der Punkt bleibt also in seiner Mitte stehen, und
    -- zwischen zwei Nadeln nebeneinander schiebt sich kein Name mehr auf die
    -- andere.
    --
    -- UEBER der Nadel, nicht darunter: Was auf einer Karte wichtig ist, liegt
    -- meist unter dem Punkt — Wege, Zonengrenzen, der eigene Pfeil. Ein Name
    -- darueber verdeckt weniger.
    pin.label = pin:CreateFontString(nil, "OVERLAY")
    pin.label:SetFontObject(Theme.Fonts().pin)
    pin.label:SetPoint("BOTTOM", pin, "TOP", 0, 1)
    pin.label:SetJustifyH("CENTER")

    -- Die Zahl auf einer gebuendelten Nadel. Dunkel auf Gold, mit Umriss —
    -- der Untergrund ist hier die Nadel selbst, nicht die Karte.
    pin.count = pin:CreateFontString(nil, "OVERLAY")
    pin.count:SetFontObject(Theme.Fonts().rowBold)
    pin.count:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.count:SetTextColor(0.03, 0.05, 0.04)
    pin.count:Hide()

    pin:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end

        -- EINE BUENDELUNG ZEIGT ALLE, DIE DORT STEHEN: Name in Klassenfarbe,
        -- Stufe, Alter — sortiert nach Name, damit dieselbe Gruppe zweimal
        -- gleich aussieht.
        if self.cluster then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format(L.MAP_CLUSTER, #self.cluster), 0.96, 0.90, 0.71)
            local sortiert = {}
            for _, entry in ipairs(self.cluster) do sortiert[#sortiert + 1] = entry end
            table.sort(sortiert, function(a, b) return (a.name or "") < (b.name or "") end)
            for _, entry in ipairs(sortiert) do
                local r, g, b = Util.ClassColor(entry.class)
                local rechts = entry.level and string.format(L.LEVEL_FMT, tostring(entry.level)) or ""
                GameTooltip:AddDoubleLine(Util.ShortName(entry.name), rechts, r, g, b, 0.66, 0.61, 0.52)
            end
            GameTooltip:Show()
            return
        end

        if not self.entry then return end
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

-- ================================================================ Buendeln ---

--- Fasst Punkte zusammen, die einander ueberschneiden.
---
--- REIN, OHNE RAHMEN: Jeder Punkt traegt px/py in Bildschirmpixeln und
--- seinen Eintrag. Heraus kommt eine Liste in Zeichenreihenfolge — eine
--- Buendelung ({ cluster = true, members, px, py } mit der Mitte ihrer
--- Mitglieder) fuer jede Gruppe ab `minimum`, und jeden anderen Punkt
--- einzeln, wie er kam.
---
--- GIERIG UND DETERMINISTISCH: Ein Punkt geht zur ersten Gruppe, deren
--- ERSTEM Punkt er naeher als `radius` ist. Das ist nicht die schoenste
--- Buendelung, aber dieselbe bei jedem Zeichnen — und zweimal je Sekunde
--- gezeichnet darf eine Gruppe nicht flackern, weil ihre Mitte wandert.
function MapPins.Cluster(points, radius, minimum)
    local gruppen = {}
    for _, point in ipairs(points) do
        local ziel
        for _, gruppe in ipairs(gruppen) do
            local dx, dy = point.px - gruppe.anker.px, point.py - gruppe.anker.py
            if (dx * dx + dy * dy) < (radius * radius) then ziel = gruppe break end
        end
        if not ziel then
            ziel = { anker = point, members = {} }
            gruppen[#gruppen + 1] = ziel
        end
        ziel.members[#ziel.members + 1] = point
    end

    -- DER EIGENE PUNKT ZAEHLT MIT, WIRD ABER NICHT GEZEICHNET. Gemessen
    -- 28.09.2026: Vier standen beisammen, einer davon der Spieler selbst,
    -- und es wurde nicht gebuendelt — der eigene Punkt war vorher gar nicht
    -- erst gesammelt, also waren es fuer die Buendelung drei. Wer "vier
    -- Leute" sieht, zaehlt sich mit. Ein Buendel traegt ihn also in Zahl
    -- und Liste; bleibt die Gruppe darunter, faellt er weg, denn seinen
    -- Pfeil zeichnet Blizzard.
    local out = {}
    for _, gruppe in ipairs(gruppen) do
        if #gruppe.members >= (minimum or 4) then
            local sx, sy, entries = 0, 0, {}
            for _, point in ipairs(gruppe.members) do
                sx, sy = sx + point.px, sy + point.py
                entries[#entries + 1] = point.entry
            end
            out[#out + 1] = { cluster = true, members = entries,
                px = sx / #gruppe.members, py = sy / #gruppe.members }
        else
            for _, point in ipairs(gruppe.members) do
                if not point.own then out[#out + 1] = point end
            end
        end
    end
    return out
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

    -- GLEICH GROSS AUF JEDEM BILDSCHIRM UND IN JEDER ZOOMSTUFE.
    --
    -- GEFRAGT 26.09.2026: "wird das skaliert, wenn jemand nur auf 1920 oder
    -- auf 2560 oder auf 3440x1440 spielt?"
    --
    -- Der Bildschirm allein waere kein Problem — WoW rechnet die ganze
    -- Oberflaeche um, und ein Rahmen von 24 Einheiten sieht ueberall gleich
    -- gross aus. Die Nadel haengt aber nicht an der Oberflaeche, sondern an
    -- der KARTENFLAECHE, und die hat ihren eigenen Massstab: Sie wird beim
    -- Zoomen gedehnt. Eine Nadel darin waechst mit — beim Hineinzoomen zu
    -- einem Klotz, bei der Kontinentkarte zu einem Fleck.
    --
    -- Der Ausgleich ist ein Verhaeltnis: Steht die Nadel auf dem Massstab
    -- der Oberflaeche geteilt durch den der Kartenflaeche, hat sie am Ende
    -- genau den Massstab, den jedes andere Fenster auch hat. Damit gilt
    -- wieder, was oben ueber 24 Pixel steht — auf jeder Aufloesung.
    --
    -- OHNE MESSUNG KEIN AUSGLEICH: Antwortet einer der beiden nicht, bleibt
    -- es bei 1. Eine Nadel in falscher Groesse ist besser als gar keine.
    local massstab = 1
    local okUi, uiMass = pcall(UIParent.GetEffectiveScale, UIParent)
    local okKarte, karteMass = pcall(canvas.GetEffectiveScale, canvas)
    if okUi and okKarte and type(uiMass) == "number" and type(karteMass) == "number"
        and karteMass > 0 and uiMass > 0 then
        massstab = uiMass / karteMass
    end

    -- ERST SAMMELN, DANN BUENDELN, DANN ZEICHNEN. Wer beim Sammeln schon
    -- zeichnet, kann nicht wissen, ob an derselben Stelle noch drei kommen.
    local punkte = {}
    for _, entry in ipairs(Positions:All()) do
      -- DIE EIGENE NADEL WIRD NICHT GEZEICHNET (Blizzard zeichnet den
      -- Pfeil), aber sie wird GESAMMELT: Fuer die Buendelung zaehlt der
      -- Spieler mit, siehe MapPins.Cluster.
      do
        -- AUF DIE ANGEZEIGTE KARTE UMRECHNEN. Gespeichert ist die Position
        -- auf der Zonenkarte; wer die Kontinentkarte aufzieht, saehe sonst
        -- gar nichts, obwohl alle Daten da sind.
        local x, y = entry.x, entry.y
        if entry.mapID ~= mapID then
            x, y = Compat.TranslateMapPosition(entry.mapID, entry.x, entry.y, mapID)
        end

        -- DIE VERSCHIEBUNG WIRD DURCH DEN MASSSTAB GETEILT.
        --
        -- Ankerabstaende gelten im Massstab des Rahmens SELBST. Wer die
        -- Nadel auf 0.7 stellt und weiter 300 als Abstand angibt, setzt
        -- sie auf 210 — sie waere also zu weit oben links, und zwar
        -- umso mehr, je weiter man hineinzoomt. Das faellt beim
        -- Ausprobieren nicht auf, wenn man nicht zoomt. Und im selben
        -- Massstab ist eine Nadel PIN_SIZE breit — der Umkreis der
        -- Buendelung.
        if x then
            punkte[#punkte + 1] = { entry = entry, own = entry.own or nil,
                px = (x * breite) / massstab, py = (y * hoehe) / massstab }
        end
      end
    end

    local sichtbar = 0
    for _, gruppe in ipairs(MapPins.Cluster(punkte, PIN_SIZE, CLUSTER_MIN)) do
        sichtbar = sichtbar + 1
        local pin = self:Pin(sichtbar)

        if gruppe.cluster then
            -- EINE NADEL FUER ALLE: goldene Flaeche, weisser Rand, die Zahl
            -- darauf. Kein Wappen — es waere das einer Person, und hier
            -- stehen vier oder mehr.
            pin.entry = nil
            pin.cluster = gruppe.members
            pin.rand:Hide()
            Theme.Paint(pin.fill, { 0.898, 0.800, 0.502, 1 })
            for _, line in ipairs(pin.ring) do line:Show() end
            pin.count:SetText(tostring(#gruppe.members))
            pin.count:Show()
            pin.label:SetText("")
            pin.label:Hide()
        else
            local entry = gruppe.entry
            pin.entry = entry
            pin.cluster = nil
            pin.count:Hide()

            local r, g, b = Util.ClassColor(entry.class)

            -- ERST BEIM ZEICHNEN, WEIL ERST HIER DIE KLASSE BEKANNT IST.
            --
            -- Das Wappen traegt seine Farben selbst; eingefaerbt wird nur
            -- der Rand dahinter — dasselbe Wappen in Schwarz, also mit
            -- derselben Silhouette.
            local rund = Theme.SetClassPortrait(pin.fill, entry.class)
            pin.rund = rund

            if rund then
                pin.fill:SetVertexColor(1, 1, 1, 1)
                if Theme.SetClassPortrait(pin.rand, entry.class) then
                    pin.rand:SetVertexColor(
                        RAND_FARBE[1], RAND_FARBE[2], RAND_FARBE[3], RAND_FARBE[4])
                    pin.rand:Show()
                else
                    pin.rand:Hide()
                end
                for _, line in ipairs(pin.ring) do line:Hide() end
            else
                -- Ohne gemeldete Klasse bleibt der farbige Punkt. Er sagt
                -- weniger, aber er sagt es zuverlaessig.
                pin.rand:Hide()
                Theme.Paint(pin.fill, { r, g, b, 1 })
                for _, line in ipairs(pin.ring) do line:Show() end
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

        end

        -- ERST UMHAENGEN, DANN SETZEN. Ein Anker auf einen Rahmen,
        -- der gleich ausgetauscht wird, ist einer zu viel.
        pin:SetParent(canvas)
        pin:SetScale(massstab)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", gruppe.px, -gruppe.py)
        pin:Show()
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
