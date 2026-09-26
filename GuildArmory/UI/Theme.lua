--[[----------------------------------------------------------------------------
    Theme — eine einzige Quelle fuer Farben, Abstaende und Schriften.

    HERKUNFT DER PALETTE
    Die Werte hier sind nicht erfunden, sondern aus dem Designsystem der Gildenseite
    isnotalone.de uebernommen (CSS-Custom-Properties, Stand 15.09.2026). Das Addon
    soll sichtbar zur Gilde gehoeren, nicht wie ein Fremdkoerper wirken.

        Grund     tiefes Gruenschwarz   --bg-base   #080c0b
        Text      warmes Pergament      --text-primary #e8e0cf
        Akzent    Gold                  --gold-200  #e5cc80
        Zweit     Jade                  --jade-300  #5fcaa0
        Rahmen    dunkles Gold          --gold-700  #2a2112

    SCHRIFTEN
    Die Seite nutzt Marcellus (Roman-Capitals) fuer Ueberschriften und Inter fuer den
    Rest. Im Spiel gibt es beides nicht — aber FRIZQT__.TTF, die Standardschrift von
    WoW, ist selbst eine Trajan-verwandte Kapitalis und trifft Marcellus erstaunlich
    genau. Ueberschriften laufen deshalb darauf, Datenzeilen auf ARIALN.TTF
    (schmal, dicht, fuer 40 Zeilen lesbar).

    Das ist die Aufloesung des scheinbaren Widerspruchs zur urspruenglichen Vorgabe
    ("kein Fantasy-Design"): Nicht die Schrift macht ein UI verspielt, sondern
    goldene Rahmentexturen und Verzierungen. Die bleiben weg.

    RAHMEN (Stand 19.09.2026): Forever ist der Retail-Client. Das Fenster nutzt
    deshalb Blizzards eigene Vorlagen (PortraitFrameTemplate, InsetFrameTemplate,
    Reiter, Knoepfe, Suchfeld) — genau der Look von Karte, Charakterfenster und
    Questlog. Jede Vorlage wird beim Erzeugen per Rueckgabewert geprueft (Abschnitt
    "WoW-native Vorlagen" unten); fehlt sie, greifen Backdrop und 1px-Linien.
------------------------------------------------------------------------------]]

local _, GA = ...

local Theme = {}
GA.UI.Theme = Theme

-- ------------------------------------------------------------------ Farben ---

Theme.color = {
    -- Flaechen, von hinten nach vorn
    windowBg   = { 0.031, 0.047, 0.043, 0.97 },  -- --bg-base         #080c0b
    sidebarBg  = { 0.020, 0.027, 0.024, 1.00 },  -- --bg-sunken       #050706
    panelBg    = { 0.063, 0.086, 0.078, 1.00 },  -- --bg-panel        #101614
    rowBg      = { 0.082, 0.114, 0.102, 1.00 },  -- --bg-panel-raised #151d1a
    rowAltBg   = { 0.047, 0.071, 0.063, 1.00 },  -- --bg-row-odd      #0c1210
    rowHover   = { 0.086, 0.141, 0.122, 1.00 },  -- --bg-row-hover    #16241f

    -- Linien. Der Rahmen ist goldstichig, nicht neutralgrau — das ist der
    -- auffaelligste Einzelzug des Gilden-Looks.
    border     = { 0.165, 0.129, 0.071, 1.00 },  -- --gold-700        #2a2112
    borderLit  = { 0.263, 0.208, 0.110, 1.00 },  -- --gold-600        #43351c
    divider    = { 0.055, 0.118, 0.102, 1.00 },  -- --mist-800        #0e1e1a

    -- Text
    text       = { 0.910, 0.878, 0.812 },        -- --text-primary    #e8e0cf
    textDim    = { 0.659, 0.612, 0.518 },        -- --text-secondary  #a89c84
    textFaint  = { 0.435, 0.404, 0.325 },        -- --text-muted      #6f6753
    heading    = { 0.898, 0.800, 0.502 },        -- --text-heading    #e5cc80

    -- Gold: der Akzent
    gold       = { 0.898, 0.800, 0.502 },        -- --gold-200        #e5cc80
    goldBright = { 0.965, 0.902, 0.706 },        -- --gold-100        #f6e6b4
    goldMid    = { 0.784, 0.667, 0.431 },        -- --gold-300        #c8aa6e
    goldDim    = { 0.612, 0.498, 0.278 },        -- --gold-400        #9c7f47
    goldDeep   = { 0.263, 0.208, 0.110, 1.00 },  -- --gold-600, Knopfflaeche

    -- Jade: die Zweitfarbe
    jade       = { 0.373, 0.792, 0.627 },        -- --jade-300        #5fcaa0
    jadeDim    = { 0.165, 0.490, 0.384 },        -- --jade-500        #2a7d62
    jadeDeep   = { 0.110, 0.325, 0.263, 1.00 },  -- --jade-600

    -- Zustaende. Bewusst getrennt vom Akzent: Gold heisst "wichtig",
    -- nicht "gut" oder "schlecht".
    good       = { 0.298, 0.686, 0.314 },        -- --ok              #4caf50
    warn       = { 0.851, 0.643, 0.255 },        -- --warn            #d9a441
    bad        = { 0.784, 0.251, 0.184 },        -- --danger          #c8402f
    info       = { 0.290, 0.565, 0.851 },        -- --info            #4a90d9

    -- Rollen. Tank und Heiler kommen direkt aus der Palette; Schaden ist die
    -- Danger-Farbe in Richtung Pergament abgemischt, damit eine Rollenmarkierung
    -- nicht wie eine Warnung aussieht.
    TANK       = { 0.290, 0.565, 0.851 },        -- --info
    HEALER     = { 0.373, 0.792, 0.627 },        -- --jade-300
    DAMAGER    = { 0.722, 0.431, 0.349 },        -- #b86e59
}

-- ------------------------------------------------------------------ Masse ----

Theme.size = {
    padding      = 14,
    gap          = 10,
    rowHeight    = 22,   -- dicht: 40 Spieler sollen ohne Scrollen sichtbar sein
    headerHeight = 44,
    sidebarWidth = 168,
    tabHeight    = 30,
    borderWidth  = 1,

    -- Abstand zwischen aeusserer und innerer Rahmenlinie. Uebernommen aus
    -- --frame-gap der Gildenseite und gleichzeitig das klassische WoW-Panelmotiv:
    -- zwei duenne Linien statt einer dicken Rahmentextur.
    frameGap     = 3,
}

-- --------------------------------------------------------------- Schriften ---

--- Pfade sind in jeder Client-Linie vorhanden. Bei abweichenden Locales kann
--- SetFont fehlschlagen — dann greift der Rueckfall auf die Spielschriften.
local FONT_SERIF = [[Fonts\FRIZQT__.TTF]]   -- Kapitalis, nah an Marcellus
local FONT_NARROW = [[Fonts\ARIALN.TTF]]    -- schmal, fuer Datenzeilen

local created = {}

--- Erzeugt ein FontObject oder liefert den Rueckfall.
local function makeFont(key, path, size, flags, fallback)
    if created[key] then return created[key] end

    local font = CreateFont("GuildArmoryFont" .. key)
    local ok = pcall(font.SetFont, font, path, size, flags)
    if not ok then
        created[key] = fallback
        return fallback
    end

    created[key] = font
    return font
end

--- Schriftrollen. Aufruf erst nach dem Laden, nicht zur Ladezeit der Datei.
function Theme.Fonts()
    return {
        -- Ueberschriften: Kapitalis, gesperrt, gold. Der Gilden-Look.
        title   = makeFont("Title",   FONT_SERIF,  15, nil, GameFontNormal),
        heading = makeFont("Heading", FONT_SERIF,  11, nil, GameFontNormalSmall),
        brand   = makeFont("Brand",   FONT_SERIF,  17, nil, GameFontNormalLarge),

        -- Daten: schmal und dicht.
        row     = makeFont("Row",     FONT_NARROW, 13, nil, GameFontHighlightSmall),
        rowBold = makeFont("RowBold", FONT_NARROW, 13, "OUTLINE", GameFontHighlightSmall),
        small   = makeFont("Small",   FONT_NARROW, 11, nil, GameFontDisableSmall),

        -- Die Beschriftung der Kartennadeln: so klein wie lesbar, und MIT
        -- UMRISS. Auf einer Karte ist der Untergrund unbekannt — heller
        -- Sand, dunkles Meer, Waldgruen —, und Text ohne Umriss
        -- verschwindet genau dort, wo jemand hinsieht. Dieselbe Ueberlegung
        -- wie der schwarze Rand um die Nadel selbst.
        pin     = makeFont("Pin",     FONT_NARROW,  9, "OUTLINE", GameFontDisableSmall),
        number  = makeFont("Number",  FONT_NARROW, 20, nil, GameFontNormalLarge),

        -- WoW-nativ (19.09.2026): groessere Kapitalis fuer Charakternamen und
        -- Navigation, ohne gesperrte Versalien — wie im Charakterfenster.
        hero    = makeFont("Hero",    FONT_SERIF,  22, nil, GameFontNormalHuge),
        big     = makeFont("Big",     FONT_SERIF,  16, nil, GameFontNormalLarge),
        nav     = makeFont("Nav",     FONT_SERIF,  13, nil, GameFontNormal),
        body    = makeFont("Body",    FONT_SERIF,  12, nil, GameFontHighlight),
    }
end

-- ------------------------------------------------------------- Hilfsmittel ---

--- Setzt eine einfarbige Textur. SetColorTexture fehlt in sehr alten Linien.
--- Eine runde, eingefaerbte Flaeche.
---
--- WARUM NICHT SetMask — GEMESSEN 26.09.2026, MIT BILD.
---
--- Der erste Versuch legte Blizzards Portraitmaske ueber eine Farbflaeche
--- (SetColorTexture + SetMask). Der Aufruf lief durch, pcall meldete Erfolg,
--- der Rueckfall griff nicht — und die Nadeln waren weiter eckig. Eine Maske
--- auf einer Farbflaeche tut auf dieser Linie nichts.
---
--- Das ist der teuerste Ausgang von allen: kein Fehler, kein "nein", nur ein
--- Ergebnis, das nicht stimmt. Ein pcall, der durchlaeuft, ist eben kein
--- Beweis, dass etwas passiert ist.
---
--- STATTDESSEN DIE MASKE ALS BILD. Sie ist eine weisse Scheibe auf
--- durchsichtigem Grund — als Textur gesetzt und ueber SetVertexColor
--- eingefaerbt, ist sie genau das, was gebraucht wird: ein runder Punkt in
--- der Wunschfarbe, mit weichen Raendern.
---
--- @return boolean gesetzt  false = kein Weg, der Aufrufer braucht einen
---                          anderen
function Theme.RoundTexture(texture, color)
    if not texture or type(texture.SetTexture) ~= "function" then return false end
    if not pcall(texture.SetTexture, texture,
        [[Interface\CHARACTERFRAME\TempPortraitAlphaMask]]) then
        return false
    end

    -- DER PFAD MUSS AUCH ANGEKOMMEN SEIN. SetTexture schweigt bei einer
    -- Datei, die es nicht gibt, und ein unsichtbarer Punkt waere schlimmer
    -- als ein eckiger.
    if type(texture.GetTexture) == "function" then
        local ok, pfad = pcall(texture.GetTexture, texture)
        if not ok or type(pfad) ~= "string" or pfad == "" then return false end
    end

    if color and type(texture.SetVertexColor) == "function" then
        pcall(texture.SetVertexColor, texture,
            color[1], color[2], color[3], color[4] or 1)
    end
    return true
end

function Theme.Paint(texture, color)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1

    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a)
    elseif texture.SetTexture then
        texture:SetTexture(r, g, b, a)
    else
        -- EIN FRAME IST KEINE TEXTUR, und der Unterschied faellt sonst erst
        -- als "attempt to call a nil value" auf — eine Meldung, die nicht
        -- sagt, was gemeint war. Theme.Fill gibt die Textur ZURUECK; wer sie
        -- wegwirft und den Frame bemalt, landet hier.
        error("Theme.Paint braucht eine Textur, keinen " ..
              tostring(texture.GetObjectType and texture:GetObjectType() or type(texture)) ..
              " — Theme.Fill gibt die Textur zurueck, sie wird gebraucht", 2)
    end
    return texture
end

--- Flaechenfuellung fuer einen Frame.
function Theme.Fill(frame, color, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    Theme.Paint(texture, color)
    return texture
end

--- Einzelne 1px-Linie an einer Kante. Ersetzt Rahmen ohne SetBackdrop.
--- @param edge string "TOP" | "BOTTOM" | "LEFT" | "RIGHT"
function Theme.Edge(frame, edge, color, inset)
    inset = inset or 0
    local line = frame:CreateTexture(nil, "BORDER")
    Theme.Paint(line, color or Theme.color.divider)

    local thickness = Theme.size.borderWidth

    if edge == "TOP" then
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, 0)
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, 0)
        line:SetHeight(thickness)
    elseif edge == "BOTTOM" then
        line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, 0)
        line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, 0)
        line:SetHeight(thickness)
    elseif edge == "LEFT" then
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -inset)
        line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, inset)
        line:SetWidth(thickness)
    else
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -inset)
        line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, inset)
        line:SetWidth(thickness)
    end

    return line
end

--- Rahmen aus vier 1px-Linien.
function Theme.Outline(frame, color)
    color = color or Theme.color.border
    return {
        Theme.Edge(frame, "TOP", color),
        Theme.Edge(frame, "BOTTOM", color),
        Theme.Edge(frame, "LEFT", color),
        Theme.Edge(frame, "RIGHT", color),
    }
end

--- Doppelrahmen: aeussere Linie, Zwischenraum, innere Linie.
--- Das klassische WoW-Panelmotiv, flach umgesetzt — und zugleich der
--- --frame-gap der Gildenseite. Nur fuer das Hauptfenster, nicht fuer jedes Panel:
--- ein Motiv, das ueberall klebt, hebt nichts mehr hervor.
function Theme.DoubleFrame(frame)
    Theme.Outline(frame, Theme.color.border)

    local gap = Theme.size.frameGap
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT", frame, "TOPLEFT", gap, -gap)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -gap, gap)
    Theme.Outline(inner, Theme.color.divider)

    return inner
end

--- Beschriftung mit Themenfarbe.
function Theme.Label(parent, text, fontObject, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(fontObject or GameFontHighlightSmall)
    label:SetText(text or "")
    local c = color or Theme.color.text
    label:SetTextColor(c[1], c[2], c[3])
    return label
end

--- Panel-Ueberschrift: gold, Versalien, gesperrt. Die Gildenseite setzt
--- letter-spacing; im Spiel gibt es das nicht, deshalb wird gesperrt geschrieben.
function Theme.SpacedCaps(text)
    if not text or text == "" then return "" end
    local out = {}
    for index = 1, #text do
        out[#out + 1] = string.sub(text, index, index)
    end
    return string.upper(table.concat(out, " "))
end

function Theme.RoleColor(role)
    return Theme.color[role] or Theme.color.textDim
end

--- Farbe fuer einen Zustand: "good" | "warn" | "bad" | "unknown"
function Theme.StateColor(state)
    if state == "good" then return Theme.color.good end
    if state == "warn" then return Theme.color.warn end
    if state == "bad" then return Theme.color.bad end
    return Theme.color.textFaint
end

-- ============================================================================
-- WoW-NATIVE BAUSTEINE (ergaenzt 19.09.2026)
--
-- Der erste Entwurf war ein flaches Admin-Dashboard: 1px-Linien, gesperrte
-- Versalien, schmale Schrift. Fuer eine Gilden-Armory ist das zu steif — sie
-- soll sich wie das Charakterfenster anfuehlen, nicht wie eine Tabelle.
--
-- BackdropTemplateMixin ist in Forever GEMESSEN vorhanden (Probe 18.09.2026).
-- Damit duerfen Blizzards eigene Rahmentexturen benutzt werden. Alles hier ist
-- trotzdem abgesichert: Fehlt eine Textur oder das Template, faellt es auf die
-- flachen Bausteine oben zurueck, statt zu werfen.
-- ============================================================================

--- TEXTURPFADE STEHEN IN [[...]], NICHT IN ANFUEHRUNGSZEICHEN.
---
--- Gemessen 21.09.2026: Hier stand "Interface\DialogFrame\UI-DialogBox-Border"
--- mit EINFACHEN Backslashes. Lua 5.1 kennt weder \D noch \U als Escape und
--- laesst den Backslash in so einem Fall einfach weg — aus dem Pfad wird
--- "InterfaceDialogFrameUI-DialogBox-Border". Kein Fehler, keine Warnung, nur
--- eine Textur, die nie laedt.
---
--- Genau das beschreibt der Abschnitt weiter unten als "SetBackdrop nahm die
--- Pfade an und zeichnete nichts". Die Ursache lag nicht am Client, sondern an
--- dieser Zeile. Die Schriftpfade oben standen von Anfang an in [[...]] und
--- haben deshalb immer funktioniert — der Unterschied war der ganze Fehler.
---
--- [[...]] kennt keine Escapes. Deshalb steht jeder Pfad in dieser Datei so da.
local BACKDROPS = {
    --- Goldrahmen des Hauptfensters: die klassische Dialogbox.
    window = {
        bgFile   = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 11, bottom = 11 },
    },
    --- Innenpanel: schlanker Tooltip-Rahmen auf dunklem Grund.
    panel = {
        bgFile   = [[Interface\Tooltips\UI-Tooltip-Background]],
        edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
}

--- Erzeugt einen Frame, der einen Backdrop tragen kann. Der kanonische Weg ist
--- die Vorlage "BackdropTemplate" beim Erzeugen; fehlt sie, kommt ein normaler
--- Frame zurueck, und Theme.Backdrop versucht spaeter den Mixin.
function Theme.CreateBackdropFrame(name, parent)
    local ok, frame = pcall(CreateFrame, "Frame", name, parent, "BackdropTemplate")
    if ok and frame then return frame end
    return CreateFrame("Frame", name, parent)
end

--- Prueft, ob eine Texturdatei im Client existiert. SetTexture nimmt jeden Pfad
--- an; ob er zu einer Datei fuehrt, verraet erst GetTexture danach.
local textureProbe
function Theme.TextureExists(path)
    if not textureProbe then
        textureProbe = UIParent:CreateTexture(nil, "BACKGROUND")
        textureProbe:Hide()
    end
    local ok = pcall(textureProbe.SetTexture, textureProbe, path)
    if not ok then return false end
    local loaded = textureProbe:GetTexture()
    return loaded ~= nil and loaded ~= 0 and loaded ~= ""
end

--- Legt einen Rahmen an. Gibt true zurueck, wenn die Rahmentextur WIRKLICH
--- geladen wurde — nicht, wenn der Aufruf bloss durchging.
---
--- Lehre aus dem ersten Screenshot (19.09.2026): SetBackdrop nahm die Pfade an
--- und zeichnete nichts. Fenstergrund und Goldrahmen fehlten, der Text schwebte
--- ueber der Spielwelt. Deshalb:
---   1. Der Hintergrund ist IMMER eine deckende Flaeche (Theme.Fill) — die
---      funktioniert nachweislich. Die Backdrop-Textur liefert nur den Rand.
---   2. Nach SetBackdrop wird geprueft, ob die Randtextur existiert. Wenn nicht,
---      wird der Backdrop wieder entfernt und false zurueckgegeben, damit der
---      Aufrufer den flachen Rahmen zeichnet.
function Theme.Backdrop(frame, kind, bgColor, borderColor)
    -- Schritt 1: deckende Flaeche, unabhaengig von allem Weiteren.
    if not frame.gaFill then
        frame.gaFill = Theme.Fill(frame, bgColor or Theme.color.panelBg)
    end

    local definition = BACKDROPS[kind or "panel"]
    if not definition then return false end

    -- Existiert die Randtextur ueberhaupt? Sonst gar nicht erst versuchen.
    if not Theme.TextureExists(definition.edgeFile) then return false end

    if not frame.SetBackdrop then
        if type(_G.BackdropTemplateMixin) ~= "table" or type(_G.Mixin) ~= "function" then
            return false
        end
        local ok = pcall(Mixin, frame, BackdropTemplateMixin)
        if not ok or not frame.SetBackdrop then return false end
        if frame.OnBackdropLoaded then pcall(frame.OnBackdropLoaded, frame) end
    end

    -- Nur der Rand: bgFile weglassen, die Flaeche steht schon.
    local edgeOnly = {
        edgeFile = definition.edgeFile,
        edgeSize = definition.edgeSize,
        insets = definition.insets,
    }
    local ok, err = pcall(frame.SetBackdrop, frame, edgeOnly)
    if not ok then
        if GA.Core.Debug then GA.Core.Debug:Print("ui", "SetBackdrop fehlgeschlagen: %s", tostring(err)) end
        return false
    end

    -- Schritt 2: Ergebnis pruefen — ueber die oeffentliche Schnittstelle, nicht
    -- ueber geratene Interna. Beim zweiten Screenshot (19.09.2026) hatte eine
    -- Pruefung auf frame.TopEdge den fertigen Goldrahmen wieder verworfen.
    local applied = false
    if frame.GetBackdrop then
        local okGet, info = pcall(frame.GetBackdrop, frame)
        applied = okGet and type(info) == "table" and info.edgeFile ~= nil
    else
        applied = true
    end
    if not applied then
        if GA.Core.Debug then GA.Core.Debug:Print("ui", "GetBackdrop bestaetigt nichts — Rueckfall") end
        pcall(frame.SetBackdrop, frame, nil)
        return false
    end

    local border = borderColor or Theme.color.goldMid
    pcall(frame.SetBackdropBorderColor, frame, border[1], border[2], border[3], 1)
    return true
end

--- Deckende Flaeche aus einer Blizzard-Textur (gekachelt), mit Farbton.
--- Faellt auf eine Farbflaeche zurueck, wenn der Pfad nicht laedt.
--- UI-Background-Rock und -Marble laden in Forever nachweislich (Probe 19.09.).
function Theme.TexturedFill(frame, path, tint, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)

    if Theme.TextureExists(path) then
        pcall(texture.SetTexture, texture, path, "REPEAT", "REPEAT")
        if texture.SetHorizTile then
            pcall(texture.SetHorizTile, texture, true)
            pcall(texture.SetVertTile, texture, true)
        end
        local t = tint or { 1, 1, 1, 1 }
        texture:SetVertexColor(t[1], t[2], t[3], t[4] or 1)
    else
        Theme.Paint(texture, tint or Theme.color.windowBg)
    end
    return texture
end

--- Qualitaetsfarbe als {r,g,b}. Zwei Schnittstellen, dann Rueckfall auf Weiss.
function Theme.QualityColor(quality)
    if quality == nil then return { 0.62, 0.62, 0.62 } end
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemQualityColor) == "function" then
        local ok, r, g, b = pcall(_G.C_Item.GetItemQualityColor, quality)
        if ok and r then return { r, g, b } end
    end
    if type(_G.GetItemQualityColor) == "function" then
        local ok, r, g, b = pcall(GetItemQualityColor, quality)
        if ok and r then return { r, g, b } end
    end
    return { 1, 1, 1 }
end

--- Leere Slot-Hintergruende aus dem Charakterfenster, je Ausruestungsplatz.
local SLOT_BACKGROUNDS = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrists", [10] = "Hands",
    [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
    [15] = "Chest", [16] = "MainHand", [17] = "SecondaryHand", [18] = "Ranged",
    [19] = "Tabard",
}

--- Ein Ausruestungsplatz wie im Charakterfenster: Icon, Qualitaetsrahmen,
--- leerer Slot-Hintergrund, kleine Itemlevel-Zahl unten rechts.
--- @param size number  Kantenlaenge, Standard 40
function Theme.ItemSlot(parent, slotID, size)
    size = size or 40
    local fonts = Theme.Fonts()

    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(size)
    button:SetHeight(size)
    button.slotID = slotID

    -- Leerer Hintergrund: die Silhouette des Slots aus dem Charakterfenster.
    local empty = button:CreateTexture(nil, "BACKGROUND")
    empty:SetAllPoints(button)
    local name = SLOT_BACKGROUNDS[slotID]
    if name then
        pcall(empty.SetTexture, empty, [[Interface\PaperDoll\UI-PaperDoll-Slot-]] .. name)
    end
    if not empty:GetTexture() then
        Theme.Paint(empty, Theme.color.rowAltBg)
    end
    button.empty = empty

    -- Das Icon selbst, leicht beschnitten wie bei Blizzard (kein Randfilm).
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    button.icon = icon

    -- Qualitaetsrahmen: dieselbe Textur, die Blizzards ItemButton benutzt.
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(button)
    pcall(border.SetTexture, border, [[Interface\Common\WhiteIconFrame]])
    border:Hide()
    button.border = border

    -- Hover-Glanz wie bei Aktionsknoepfen.
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    pcall(highlight.SetTexture, highlight, [[Interface\Buttons\ButtonHilight-Square]])
    pcall(highlight.SetBlendMode, highlight, "ADD")

    -- Itemlevel unten rechts, klein, mit Schatten fuer Lesbarkeit auf dem Icon.
    local level = button:CreateFontString(nil, "OVERLAY")
    level:SetFontObject(fonts.small)
    level:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    level:SetTextColor(1, 1, 1)
    if level.SetShadowOffset then level:SetShadowOffset(1, -1) end
    button.level = level

    --- Befuellt den Slot. `item` = Eintrag aus character.equipment oder nil.
    function button:SetItem(item)
        self.item = item

        -- DAS SYMBOL DARF AUS DER KENNUNG KOMMEN — bei fremden Charakteren
        -- MUSS es das.
        --
        -- Der Gildenabgleich schickt je Platz nur itemID, itemLevel und
        -- enchantID. Kein Symbolpfad, kein Name, keine Qualitaet — und das
        -- ist richtig so: Ueber einen Kanal, der 240 Zeichen fasst, gehoeren
        -- keine Texturpfade. Der Empfaenger hat die Kennung, und damit hat
        -- er alles, was er braucht.
        --
        -- Vorher stand hier nur `item.icon`. Ergebnis: Bei jedem Charakter
        -- aus dem Abgleich blieb die Papierpuppe leer, waehrend daneben
        -- "8 von 17 Plaetzen belegt" stand. Dieselbe Falle wie bei den
        -- Tooltips, die einmal am Itemlink hingen.
        local Compat = GA.Core.Compat
        local icon = item and item.icon
        local quality = item and item.quality

        if item and item.itemID and Compat then
            if not icon then icon = Compat.GetItemIcon(item.itemID) end
            if not quality then
                local info = Compat.GetItemInfo(item.itemID)
                quality = info and info.quality
            end
            -- Noch nicht im Client? Anstossen. GET_ITEM_INFO_RECEIVED
            -- bringt die Ansicht danach von selbst zum Nachzeichnen.
            if not icon then Compat.RequestItemData(item.itemID) end
        end

        if item and icon then
            self.icon:SetTexture(icon)
            self.icon:Show()
            local color = Theme.QualityColor(quality)
            self.border:SetVertexColor(color[1], color[2], color[3])
            -- Weiss und Grau bekommen keinen Rahmen — wie bei Blizzard.
            if quality and quality >= 2 then self.border:Show() else self.border:Hide() end
            self.level:SetText(item.itemLevel and tostring(item.itemLevel) or "")
        else
            self.icon:Hide()
            self.border:Hide()
            self.level:SetText("")
        end
    end

    return button
end

--- Klassensymbol als Atlas (Retail-Client, in Forever erwartet). Gibt false
--- zurueck, wenn der Atlas fehlt — dann bleibt die Textur leer.
function Theme.SetClassIcon(texture, classFile)
    if not classFile or not texture.SetAtlas then return false end
    local ok = pcall(texture.SetAtlas, texture, "classicon-" .. string.lower(classFile))
    return ok and texture:GetAtlas() ~= nil
end

--- Dasselbe, aber RUND — fuer den Portraitkreis.
---
--- EIN ECKIGES SYMBOL IN EINEM RUNDEN RAHMEN SIEHT FALSCH AUS, und genau so
--- sah es aus: Der Klassenatlas ist eine quadratische Kachel, der Ring
--- darum ist ein Kreis. Die Ecken standen ueber.
---
--- UI-Classes-Circles ist dieselbe Information in rund — die Kacheln haben
--- durchsichtige Ecken und sitzen deshalb sauber im Ring. Die Zuschnitte
--- liefert das Spiel in CLASS_ICON_TCOORDS; sie selbst zu schreiben hiesse,
--- neun Zahlenpaare zu pflegen, die es schon gibt.
--- @return boolean
function Theme.SetClassPortrait(texture, classFile)
    if not classFile then return false end

    local coords = _G.CLASS_ICON_TCOORDS
    local box = type(coords) == "table" and coords[string.upper(classFile)]
    local path = [[Interface\TargetingFrame\UI-Classes-Circles]]

    if box and Theme.TextureExists(path) then
        if pcall(texture.SetTexture, texture, path) then
            pcall(texture.SetTexCoord, texture, box[1], box[2], box[3], box[4])
            return true
        end
    end

    -- Rueckfall: das eckige Symbol. Es sieht im Ring nicht gut aus, sagt
    -- aber immer noch die Klasse — und das ist mehr als ein leerer Kreis.
    pcall(texture.SetTexCoord, texture, 0, 1, 0, 1)
    return Theme.SetClassIcon(texture, classFile)
end

--- Charakterportrait. SetPortraitTexture ist gemessen vorhanden.
function Theme.SetPortrait(texture, unit)
    if type(_G.SetPortraitTexture) ~= "function" then return false end
    local ok = pcall(SetPortraitTexture, texture, unit or "player")
    return ok
end

-- ============================================================================
-- WoW-NATIVE VORLAGEN (19.09.2026)
--
-- Das Fenster soll aussehen wie Karte, Questlog und Charakterfenster in Forever:
-- Metallrahmen mit Portraitkreis und Titelleiste, dunkle eingelassene Flaechen,
-- Reiter unten, rote Standardknoepfe, Suchfeld mit Lupe. Das sind alles
-- Blizzard-Vorlagen des Retail-Clients. Sie werden hier NICHT vorausgesetzt:
--
--   CreateFrame wirft bei einer unbekannten Vorlage nicht zwingend einen
--   Fehler — der Client meldet "Couldn't find inherited node" und liefert
--   einen nackten Frame. Deshalb prueft jede Erzeugung, ob die erwarteten
--   Teile (parentKeys) wirklich am Frame haengen. Erst dann gilt die Vorlage
--   als vorhanden (GA.has.native.<Vorlage> = true), sonst greift der Rueckfall.
-- ============================================================================

Theme.native = {}
GA.has.native = Theme.native

--- Erwartete Teile je Vorlage. Es reicht, wenn EINE der Alternativen je
--- Eintrag da ist — Blizzard hat parentKeys zwischen den Versionen umbenannt
--- (portrait -> PortraitContainer, TitleText -> TitleContainer.TitleText).
local TEMPLATE_PARTS = {
    PortraitFrameTemplate     = { { "CloseButton" }, { "TitleContainer", "TitleText" },
                                  { "PortraitContainer", "portrait", "Portrait" } },
    InsetFrameTemplate        = { { "NineSlice", "Bg", "InsetBorderTop" } },
    UIPanelButtonTemplate     = { { "Left", "Middle", "NineSlice", "Center" } },
    PanelTabButtonTemplate    = { { "Text", "Left", "Middle" } },
    CharacterFrameTabButtonTemplate = { { "Text" } },
    SearchBoxTemplate         = { { "Instructions" } },
    UICheckButtonTemplate     = { { "Text", "text" } },
}

local function hasAnyPart(frame, alternatives)
    for _, key in ipairs(alternatives) do
        if frame[key] ~= nil then return true end
    end
    -- Knopf-Vorlagen haengen ihre Beschriftung oft nicht als parentKey an.
    if frame.GetFontString then
        local ok, fs = pcall(frame.GetFontString, frame)
        if ok and fs then
            for _, key in ipairs(alternatives) do
                if key == "Text" or key == "text" then return true end
            end
        end
    end
    return false
end

--- Erzeugt einen Frame aus einer Blizzard-Vorlage und prueft ihn.
--- @return Frame|nil frame   nil, wenn die Vorlage fehlt oder unvollstaendig ist
--- @return string|nil reason
function Theme.CreateNative(frameType, name, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
    if not ok or not frame then
        Theme.native[template] = false
        return nil, tostring(frame)
    end

    local parts = TEMPLATE_PARTS[template]
    if parts then
        for _, alternatives in ipairs(parts) do
            if not hasAnyPart(frame, alternatives) then
                -- Nackter Frame ohne die Vorlage: verstecken, nicht benutzen.
                frame:Hide()
                pcall(frame.SetParent, frame, nil)
                Theme.native[template] = false
                return nil, "Vorlage ohne " .. table.concat(alternatives, "/")
            end
        end
    end

    Theme.native[template] = true
    return frame
end

--- Blizzards Abstandskonstanten fuer Fensterinhalt, mit Rueckfall auf die
--- Werte aus UIPanelTemplates.lua (Retail).
function Theme.PanelInsets()
    return {
        left   = tonumber(_G.PANEL_INSET_LEFT_OFFSET)   or 4,
        right  = tonumber(_G.PANEL_INSET_RIGHT_OFFSET)  or -6,
        top    = tonumber(_G.PANEL_INSET_TOP_OFFSET)    or -24,
        bottom = tonumber(_G.PANEL_INSET_BOTTOM_OFFSET) or 4,
    }
end

--- Nimmt den Portraitkreis aus einem Fenster der Portraitvorlage.
---
--- PortraitFrameTemplate bringt oben links einen Charakterkreis mit. Fuer das
--- Hauptfenster ist der richtig — es zeigt einen Charakter. Fuer einen Dialog
--- ist er eine Behauptung: Dort geht es um einen Vorgang, nicht um eine
--- Person, und ein leerer oder fremder Kopf daneben verwirrt nur.
---
--- Blizzard hat den Teil zwischen den Versionen umbenannt, deshalb werden
--- alle bekannten Namen versteckt — und nur die, die es wirklich gibt.
--- @return boolean  ob ueberhaupt etwas versteckt wurde
function Theme.HidePortrait(frame)
    local hidden = false

    local parts = { frame.PortraitContainer, frame.portrait, frame.Portrait,
                    frame.PortraitFrame }
    for _, part in ipairs(parts) do
        if type(part) == "table" and type(part.Hide) == "function" then
            pcall(part.Hide, part)
            hidden = true
        end
    end

    if type(frame.PortraitContainer) == "table" then
        for _, key in ipairs({ "portrait", "CircleMask", "PortraitMaskTexture" }) do
            local part = frame.PortraitContainer[key]
            if type(part) == "table" and type(part.Hide) == "function" then
                pcall(part.Hide, part)
            end
        end
    end

    -- ------------------------------------------------------------------
    -- DER GOLDENE RING IST NICHT DAS PORTRAIT, SONDERN DIE RAHMENECKE.
    --
    -- Gemessen am Screenshot vom 21.09.2026: Nach dem Verstecken des Bildes
    -- stand der Ring weiter da, innen leer. Er gehoert zum NineSlice der
    -- Vorlage — die obere linke Ecke von PortraitFrameTemplate ist eine
    -- Textur MIT Ring. Kein Verstecken am Portrait der Welt entfernt sie.
    --
    -- Blizzard hat fuer genau diesen Fall eine zweite Rahmenaufteilung:
    -- dieselbe Vorlage ohne den Ring. Ob dieser Client sie kennt, sagt der
    -- Vergleich der Eckentextur VORHER und NACHHER — nicht die Existenz der
    -- Funktion.
    -- ------------------------------------------------------------------
    local nine = frame.NineSlice
    if type(nine) ~= "table" then return hidden end

    local function cornerAtlas()
        local corner = nine.TopLeftCorner
        if type(corner) ~= "table" or type(corner.GetAtlas) ~= "function" then return nil end
        local ok, atlas = pcall(corner.GetAtlas, corner)
        return ok and atlas or nil
    end

    local before = cornerAtlas()
    if type(_G.NineSliceUtil) == "table"
        and type(NineSliceUtil.ApplyLayoutByName) == "function"
    then
        pcall(NineSliceUtil.ApplyLayoutByName, nine, "PortraitFrameTemplateNoCorners")
        if cornerAtlas() ~= before then return true end
    end

    -- Rueckfall: den Rahmen der Vorlage ganz weg und den eigenen Goldrahmen
    -- darunter. Lieber ein anderer Rahmen als ein leerer Ring.
    pcall(nine.Hide, nine)
    Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid)
    return true
end

--- Textfeld einer Vorlage, egal wie Blizzard es gerade nennt.
function Theme.NativeText(frame)
    if frame.TitleContainer and frame.TitleContainer.TitleText then return frame.TitleContainer.TitleText end
    if frame.TitleText then return frame.TitleText end
    if frame.Text then return frame.Text end
    if frame.text then return frame.text end
    if frame.GetFontString then
        local ok, fs = pcall(frame.GetFontString, frame)
        if ok then return fs end
    end
    return nil
end

--- Goldener Balken hinter einer Abschnittsueberschrift — das Motiv der
--- Questlog-Kopfzeilen. UI-QuestLogTitleHighlight gibt es seit Vanilla.
function Theme.HeaderBar(frame)
    local bar = frame:CreateTexture(nil, "BACKGROUND")
    bar:SetAllPoints(frame)
    local path = [[Interface\QuestFrame\UI-QuestLogTitleHighlight]]
    if Theme.TextureExists(path) then
        pcall(bar.SetTexture, bar, path)
        pcall(bar.SetBlendMode, bar, "ADD")
        bar:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.28)
    else
        Theme.Paint(bar, { Theme.color.goldDeep[1], Theme.color.goldDeep[2], Theme.color.goldDeep[3], 0.6 })
    end
    return bar
end

--- Kurzbericht fuer /ga status und die Einstellungen.
function Theme.DescribeNative()
    local names = {}
    for template in pairs(TEMPLATE_PARTS) do names[#names + 1] = template end
    table.sort(names)
    local out = {}
    for _, template in ipairs(names) do
        local state = Theme.native[template]
        out[#out + 1] = string.format("%s %s", state == true and "+" or (state == false and "-" or "?"), template)
    end
    return table.concat(out, "  ")
end
