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
    -- "Hier ist etwas zu tun": offener Platz, Beruf am Stufendeckel.
    attn       = { 0.851, 0.643, 0.255 },

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
--- Je Schrift, was sie ausmacht — damit eine neue Schriftgroesse sie
--- umsetzen kann, ohne das Fenster neu zu bauen.
local recipes = {}

--- Die eingestellte Schriftgroesse als Faktor (Einstellungen › Fenster,
--- 08.10.2026): 100 heisst wie entworfen. Vor dem Laden der Datenbank 1.
function Theme.FontScale()
    local db = GA.Core.Database
    local config = db and db.account and db.account.config
    local percent = tonumber(config and config.fontScale) or 100
    if percent < 50 or percent > 200 then percent = 100 end
    return percent / 100
end

--- Setzt die Schriftgroesse und wendet sie auf alle schon erzeugten
--- Schriften an. Zeilenhoehen bleiben, wie sie sind — ein sehr grosser
--- Wert schneidet also Text an; dafuer wirkt die Aenderung sofort.
--- @return boolean alleUmgesetzt  false: eine Schrift (Familie) kann ihre
---   Groesse nicht aendern, dann hilft /reload
function Theme.SetFontScale(percent)
    GA.Core.Config:Set("fontScale", percent)
    local scale = Theme.FontScale()
    local alle = true
    for key, recipe in pairs(recipes) do
        local font = created[key]
        local size = math.max(6, math.floor(recipe.size * scale + 0.5))
        if font and font.SetFont then
            local ok, result = pcall(font.SetFont, font, recipe.path, size, recipe.flags)
            if not ok or result == false then alle = false end
        else
            alle = false
        end
    end
    return alle
end

--- Spielschriften fuer Alphabete, die die mitgelieferten Schriften nicht
--- haben. Die Schriften der Looks kennen Latein samt Umlauten, aber kein
--- Chinesisch, Koreanisch oder Kyrillisch — und in der Gilde steht ein
--- Name in chinesischen Zeichen (05.10.2026).
local FALLBACK_ALPHABETS = {
    { alphabet = "korean",             file = [[Fonts\2002.TTF]] },
    { alphabet = "simplifiedchinese",  file = [[Fonts\ARKai_T.ttf]] },
    { alphabet = "traditionalchinese", file = [[Fonts\blei00d.TTF]] },
    { alphabet = "russian",            file = [[Fonts\FRIZQT___CYR.TTF]] },
}

--- Eine Schriftfamilie: die Schrift des Looks fuer Latein, die Spielschriften
--- fuer den Rest. Nur, wo der Client CreateFontFamily kennt.
local function makeFamily(key, path, size, flags)
    if type(_G.CreateFontFamily) ~= "function" then return nil end
    local members = { { alphabet = "roman", file = path, height = size, flags = flags or "" } }
    for _, entry in ipairs(FALLBACK_ALPHABETS) do
        members[#members + 1] = { alphabet = entry.alphabet, file = entry.file, height = size, flags = flags or "" }
    end
    local ok, family = pcall(CreateFontFamily, "GuildArmoryFamily" .. key, members)
    if ok and family then return family end
    return nil
end

--- Erzeugt ein FontObject oder liefert den Rueckfall.
---
--- @param path string  die Schrift des Looks (oder die des Spiels)
--- @param gamePath string|nil  die Spielschrift, falls path eine eigene ist:
---   Neue Dateien laedt der Client erst nach einem Neustart — bis dahin
---   schlaegt SetFont fehl, und dann gilt die Spielschrift.
--- @param names boolean  traegt Spielernamen: dann als Familie mit Rueckfall
---   fuer fremde Alphabete
local function makeFont(key, path, size, flags, fallback, gamePath, names)
    if created[key] then return created[key] end

    -- Die Groesse, wie entworfen, mal die eingestellte Schriftgroesse.
    local base = size
    size = math.max(6, math.floor(size * Theme.FontScale() + 0.5))

    local font
    local used = path
    if gamePath and names then font = makeFamily(key, path, size, flags) end
    if not font then
        font = CreateFont("GuildArmoryFont" .. key)
        local ok, result = pcall(font.SetFont, font, path, size, flags)
        if (not ok or result == false) and gamePath then
            ok, result = pcall(font.SetFont, font, gamePath, size, flags)
            used = gamePath
        end
        if not ok or result == false then
            created[key] = fallback
            return fallback
        end
    end
    recipes[key] = { path = used, size = base, flags = flags }

    -- Grundfarbe aus dem Look: Wer die Schrift setzt und keine Farbe, soll
    -- auf dem hellen Codex nicht weiss auf Pergament schreiben.
    if font.SetTextColor and Theme.color.text then
        local c = Theme.color.text
        font:SetTextColor(c[1], c[2], c[3])
    end
    created[key] = font
    return font
end

--- Schriftrollen. Aufruf erst nach dem Laden, nicht zur Ladezeit der Datei.
function Theme.Fonts()
    -- Schriften des Looks (05.10.2026, OFL, in Media/Fonts mit Lizenzen).
    -- Titel in der Zierschrift, Daten in der klaren Grotesk des Looks.
    local look = Theme.Look()
    local f = look and look.fonts
    local FONT_SERIF = f and f.title or FONT_SERIF
    local FONT_NARROW = f and f.data or FONT_NARROW
    local FONT_BOLD = f and (f.dataBold or f.data) or FONT_NARROW
    local GAME_SERIF = f and [[Fonts\FRIZQT__.TTF]] or nil
    local GAME_NARROW = f and [[Fonts\ARIALN.TTF]] or nil
    local ts = f and f.titleScale or 1
    local ds = f and f.dataScale or 1
    local function T(n) return math.floor(n * ts + 0.5) end
    local function D(n) return math.floor(n * ds + 0.5) end
    return {
        -- Ueberschriften: Kapitalis, gesperrt, gold. Der Gilden-Look.
        title   = makeFont("Title",   FONT_SERIF,  T(15), nil, GameFontNormal, GAME_SERIF),
        heading = makeFont("Heading", FONT_SERIF,  T(11), nil, GameFontNormalSmall, GAME_SERIF),
        brand   = makeFont("Brand",   FONT_SERIF,  T(17), nil, GameFontNormalLarge, GAME_SERIF),

        -- Daten: schmal und dicht.
        row     = makeFont("Row",     FONT_NARROW, D(13), nil, GameFontHighlightSmall, GAME_NARROW, true),
        -- Die eigenen Schriften haben einen echten fetten Schnitt; der
        -- Umriss war nur der Ersatz dafuer.
        rowBold = makeFont("RowBold", FONT_BOLD,   D(13), (not f) and "OUTLINE" or nil, GameFontHighlightSmall, GAME_NARROW, true),
        small   = makeFont("Small",   FONT_NARROW, D(11), nil, GameFontDisableSmall, GAME_NARROW, true),

        -- Die Beschriftung der Kartennadeln: so klein wie lesbar, und MIT
        -- UMRISS. Auf einer Karte ist der Untergrund unbekannt — heller
        -- Sand, dunkles Meer, Waldgruen —, und Text ohne Umriss
        -- verschwindet genau dort, wo jemand hinsieht. Dieselbe Ueberlegung
        -- wie der schwarze Rand um die Nadel selbst.
        pin     = makeFont("Pin",     FONT_NARROW,  9, "OUTLINE", GameFontDisableSmall, GAME_NARROW, true),
        number  = makeFont("Number",  FONT_BOLD,   D(20), nil, GameFontNormalLarge, GAME_NARROW),

        -- WoW-nativ (19.09.2026): groessere Kapitalis fuer Charakternamen und
        -- Navigation, ohne gesperrte Versalien — wie im Charakterfenster.
        hero    = makeFont("Hero",    FONT_SERIF,  T(22), nil, GameFontNormalHuge, GAME_SERIF, true),
        -- Der Gildenname im Heroband des Dashboards (Entwurf D1, 27.09.2026):
        -- eine Stufe ueber hero. Nur dort — ein zweiter grosser Titel auf
        -- derselben Seite wuerde mit ihm streiten.
        display = makeFont("Display", FONT_SERIF,  T(30), nil, GameFontNormalHuge, GAME_SERIF, true),
        big     = makeFont("Big",     FONT_SERIF,  T(16), nil, GameFontNormalLarge, GAME_SERIF),
        nav     = makeFont("Nav",     f and FONT_BOLD or FONT_SERIF, f and D(12) or 13, nil, GameFontNormal, GAME_SERIF),
        body    = makeFont("Body",    f and FONT_NARROW or FONT_SERIF, f and D(12) or 12, nil, GameFontHighlight, GAME_SERIF, true),
    }
end

-- ---------------------------------------------------------------- Looks -----
--
-- Drei eigene Looks aus den Entwuerfen vom 05.10.2026 plus Blizzards Fenster.
-- Der Nutzer waehlt unter Einstellungen › UI + Language:
--
--   forge     Entwurf B "Ironforge Ember": Stahl, Steinmaserung, Glut.
--   twilight  Entwurf A "Forever Twilight": Daemmerungshimmel wie die
--             Forever-Seite, Juwel-Tuerkis, Bronze.
--   codex     Entwurf C "Codex": Pergament, Tinte, Siegelwachs. Der einzige
--             HELLE Look — Klassenfarben werden dafuer abgedunkelt.
--   blizzard  Blizzards Vorlagen wie vor 0.1.35.
--
-- WIE ES WIRKT: Theme.ApplyLook() tauscht die Farbwerte DIESER Tabelle aus,
-- sobald die Datenbank steht (Core/Events.lua). Alles, was Theme.color.x zur
-- Laufzeit liest, folgt damit von selbst. Und Theme.CreateNative verweigert
-- die rein optischen Blizzard-Vorlagen (Portraitfenster, Knopf, Reiter,
-- Einlage): Dann greifen ueberall die selbst gezeichneten Rueckfaelle, und
-- die tragen die Texturen des Looks. Ein Wechsel wirkt nach /reload.
--
-- Eigene Texturen in Media/, keine Blizzard-Grafik. NEUE DATEIEN DORT LAEDT
-- DER CLIENT ERST NACH EINEM NEUSTART des Spiels, nicht nach /reload. Jede
-- Textur wird darum ueber TextureExists geprueft; laedt sie nicht, bleibt die
-- flache Farbe.

local M = [[Interface\AddOns\GuildArmory\Media\]]
local F = [[Interface\AddOns\GuildArmory\Media\Fonts\]]
Theme.MEDIA = {
    stone     = M .. "Stone.tga",
    metal     = M .. "Metal.tga",
    molten    = M .. "Molten.tga",
    notch     = M .. "Notch.tga",
    rivet     = M .. "Rivet.tga",
    glow      = M .. "Glow.tga",
    -- Goldenes Ausrufezeichen fuer Questobjekte (06.10.2026), 128x256.
    questmark = M .. "QuestMark.tga",
    logo      = M .. "Logo.tga",
    -- Das eigene Gildenlogo (08.10.2026): legt jeder selbst in den Ordner,
    -- ein Addon kann keine Datei hochladen und keine mit der Gilde teilen.
    -- Nicht im Paket, nicht im Repository (publish.mjs, .gitignore).
    guildLogo = M .. "GuildLogo.tga",
    sky       = M .. "Sky.tga",
    jewel     = M .. "Jewel.tga",
    parchment = M .. "Parchment.tga",
    wax       = M .. "Wax.tga",
    velvet    = M .. "Velvet.tga",
    gold      = M .. "Gold.tga",
    corner_filigree = M .. "Corner_Filigree.tga",
    corner_star     = M .. "Corner_Star.tga",
    corner_bracket  = M .. "Corner_Bracket.tga",
    corner_illum    = M .. "Corner_Illum.tga",
    diamond   = M .. "Diamond.tga",
    seal      = M .. "Seal.tga",
    shield    = M .. "Shield.tga",
    shieldopen = M .. "ShieldOpen.tga",
    shieldfill = M .. "ShieldFill.tga",
    shieldrim  = M .. "ShieldRim.tga",
    discord    = M .. "Discord.tga",
}

--- Reihenfolge der Knoepfe in den Einstellungen.
Theme.LOOK_ORDER = { "forge", "twilight", "codex", "crimson", "blizzard" }
Theme.DEFAULT_LOOK = "forge"

--- EIN RAND FUER ALLES (05.10.2026, nach drei Bildern): Kopfleiste und
--- Inhalt halten in den eigenen Looks auf allen vier Seiten denselben
--- Abstand zum Rahmen, ihre Kanten stehen buendig uebereinander. Die
--- Eckornamente liegen ganz in diesem Rand und beruehren nichts — erst
--- stiessen sie an die Kopfleiste, dann sassen sie aussen, dann war die
--- Leiste schmaler als der Inhalt. Alles drei sah unsauber aus.
Theme.FRAME_MARGIN = 24
-- Die Ornamente sind L-foermig: lang an den Kanten, nach innen nur gut 20
-- Pixel tief (Stern, Blattgold-Dreieck, Winkel) — so bleiben sie auch gross
-- im Rand (Wunsch 05.10.2026: "haetten nicht kleiner gemusst").
Theme.CORNER_SIZE = 36
Theme.CORNER_INSET = 3

function Theme.Margin()
    return Theme.Look() and Theme.FRAME_MARGIN or 12
end

--- Abstand der Kopfleiste vom oberen Fensterrand.
function Theme.HeaderTop()
    return Theme.Margin()
end

--- Seitlicher Abstand der Kopfleiste — derselbe wie der des Inhalts.
function Theme.HeaderSide()
    return Theme.Margin()
end

local BLACK = { 0.043, 0.039, 0.035, 1 }

--- Je Look: Palette (dieselben Schluessel wie Theme.color — "gold" ist dort
--- der Akzent, auch wenn er Glut, Tuerkis oder Wachs ist) und die Texturen
--- fuer Fenster, Inhalt, Kopfleiste, Knoepfe, Reiter und Balken.
Theme.LOOKS = {
    forge = {
        palette = {
            attn       = { 1.000, 0.878, 0.541 },        -- weissgluehend: am Deckel
            windowBg   = { 0.075, 0.067, 0.063, 0.97 },  -- Kohle      #131110
            sidebarBg  = { 0.090, 0.082, 0.075, 1.00 },
            panelBg    = { 0.118, 0.106, 0.094, 1.00 },  -- Amboss     #1e1b18
            rowBg      = { 0.141, 0.129, 0.118, 1.00 },
            rowAltBg   = { 0.102, 0.094, 0.086, 1.00 },
            rowHover   = { 0.180, 0.157, 0.137, 1.00 },
            border     = { 0.290, 0.271, 0.251, 1.00 },  -- Stahl dunkel
            borderLit  = { 0.420, 0.396, 0.365, 1.00 },  -- Stahl
            divider    = { 0.165, 0.149, 0.133, 1.00 },
            text       = { 0.925, 0.894, 0.839 },        -- Asche
            textDim    = { 0.702, 0.663, 0.600 },        -- #b3a999, 7.2:1 auf Paneel
            textFaint  = { 0.604, 0.561, 0.502 },        -- #9a8f80, 5.3:1
            heading    = { 0.953, 0.773, 0.541 },
            gold       = { 0.961, 0.706, 0.416 },        -- Glut hell
            goldBright = { 1.000, 0.886, 0.737 },
            goldMid    = { 0.886, 0.443, 0.169 },        -- Glut
            goldDim    = { 0.659, 0.322, 0.110 },
            goldDeep   = { 0.290, 0.137, 0.063, 1.00 },  -- Zunder
        },
        fonts = { title = F .. "SpectralSC-Bold.ttf", data = F .. "BarlowSemiCondensed-Medium.ttf",
                  dataBold = F .. "BarlowSemiCondensed-Bold.ttf", titleScale = 1.0, dataScale = 1.0 },
        window  = { tex = "stone", tile = true, tint = { 0.15, 0.137, 0.123, 0.98 } },
        content = { tex = "stone", tile = true, tint = { 0.10, 0.092, 0.084, 1 } },
        outer = BLACK, corner = "corner_bracket", medal = { 0.62, 0.59, 0.55, 1 },
        mark = { tex = "diamond", tint = { 1.00, 0.60, 0.27, 1 } }, markLine = { 1.00, 0.60, 0.27, 1 },
        header = { 0.36, 0.33, 0.30, 1 },
        btnPrimary = { 0.86, 0.40, 0.13, 1 }, btnPrimaryHover = { 1.00, 0.55, 0.22, 1 },
        btnSecondary = { 0.34, 0.32, 0.30, 1 }, btnSecondaryHover = { 0.46, 0.43, 0.40, 1 },
        btnLine = BLACK,
        tabSelected = { 0.46, 0.30, 0.18, 1 }, tabIdle = { 0.24, 0.22, 0.21, 1 },
        bar = "molten", trough = { 0.035, 0.031, 0.028, 1 },
    },

    twilight = {
        palette = {
            attn       = { 0.941, 0.639, 0.420 },        -- Abendrot #f0a36b
            windowBg   = { 0.039, 0.078, 0.133, 0.97 },  -- Daemmerung #0a1422
            sidebarBg  = { 0.031, 0.071, 0.125, 1.00 },
            panelBg    = { 0.059, 0.133, 0.204, 1.00 },  -- Tiefsee    #0f2234
            rowBg      = { 0.075, 0.161, 0.239, 1.00 },
            rowAltBg   = { 0.047, 0.110, 0.173, 1.00 },
            rowHover   = { 0.094, 0.212, 0.314, 1.00 },
            border     = { 0.369, 0.302, 0.212, 1.00 },  -- Bronze dunkel
            borderLit  = { 0.659, 0.525, 0.353, 1.00 },  -- Bronze     #a8865a
            divider    = { 0.102, 0.188, 0.271, 1.00 },
            text       = { 0.910, 0.886, 0.831 },
            textDim    = { 0.663, 0.733, 0.769 },        -- #a9bbc4, 8.2:1
            textFaint  = { 0.518, 0.600, 0.647 },        -- #8499a5, 5.5:1
            heading    = { 0.918, 0.851, 0.761 },        -- Pergament  #ead9c2
            gold       = { 0.373, 0.878, 0.902 },        -- Juwel hell #5fe0e6
            goldBright = { 0.867, 0.984, 0.988 },
            goldMid    = { 0.224, 0.714, 0.761 },        -- Juwel      #39b6c2
            goldDim    = { 0.122, 0.498, 0.541 },
            goldDeep   = { 0.055, 0.235, 0.275, 1.00 },
        },
        fonts = { title = F .. "Cinzel-Bold.ttf", data = F .. "AlegreyaSans-Medium.ttf",
                  dataBold = F .. "AlegreyaSans-Bold.ttf", titleScale = 0.9, dataScale = 1.08 },
        window  = { tex = "sky", tile = false, tint = { 1, 1, 1, 0.98 } },
        content = { fill = { 0.035, 0.075, 0.12, 0.72 } },
        outer = { 0.659, 0.525, 0.353, 1 }, inner = { 0.224, 0.714, 0.761, 0.45 },
        corner = "corner_star", medal = { 0.66, 0.53, 0.35, 1 },
        mark = { tex = "diamond", tint = { 0.373, 0.878, 0.902, 1 } }, markLine = { 0.66, 0.53, 0.35, 1 },
        header = { 0.13, 0.24, 0.34, 1 },
        btnPrimary = { 0.17, 0.66, 0.71, 1 }, btnPrimaryHover = { 0.30, 0.85, 0.90, 1 },
        btnSecondary = { 0.16, 0.24, 0.32, 1 }, btnSecondaryHover = { 0.22, 0.34, 0.44, 1 },
        btnLine = { 0.659, 0.525, 0.353, 1 },
        tabSelected = { 0.14, 0.45, 0.50, 1 }, tabIdle = { 0.10, 0.17, 0.24, 1 },
        bar = "jewel", trough = { 0.024, 0.063, 0.102, 1 },
    },

    codex = {
        light = true,
        palette = {
            attn       = { 0.184, 0.369, 0.557 },        -- blaue Tinte #2f5e8e
            windowBg   = { 0.914, 0.859, 0.733, 0.98 },  -- Vellum     #e9dbbb
            sidebarBg  = { 0.886, 0.824, 0.682, 1.00 },
            panelBg    = { 0.949, 0.906, 0.800, 1.00 },
            rowBg      = { 0.918, 0.863, 0.741, 1.00 },
            rowAltBg   = { 0.894, 0.831, 0.698, 1.00 },
            rowHover   = { 0.863, 0.780, 0.620, 1.00 },
            border     = { 0.549, 0.455, 0.337, 1.00 },
            borderLit  = { 0.369, 0.290, 0.212, 1.00 },  -- Sepia
            divider    = { 0.804, 0.725, 0.569, 1.00 },
            text       = { 0.169, 0.114, 0.071 },        -- Tinte      #2b1d12
            textDim    = { 0.369, 0.290, 0.212 },
            textFaint  = { 0.431, 0.353, 0.271 },        -- #6e5a45, 5.5:1
            heading    = { 0.431, 0.122, 0.086 },        -- Wachs dunkel
            gold       = { 0.561, 0.165, 0.122 },        -- Siegelwachs #8f2a1f
            -- goldBright ist an 68 Stellen TEXTFARBE (Zahlen, Namen, der
            -- Gildenname). Creme stand dort auf Pergament und war unsichtbar
            -- (Bild vom 05.10.2026) — hier also dunkles Wachs; die Creme-
            -- schrift auf dem roten Knopf kommt aus btnPrimaryText.
            goldBright = { 0.431, 0.122, 0.086 },
            goldMid    = { 0.561, 0.165, 0.122 },
            goldDim    = { 0.722, 0.537, 0.184 },        -- Blattgold  #b8892f
            goldDeep   = { 0.902, 0.808, 0.698, 1.00 },  -- blasses Wachs: Flaeche unter dunkler Schrift
            -- Zustaende und Rollen dunkler: hell auf Pergament waere unlesbar.
            good       = { 0.200, 0.450, 0.180 },
            warn       = { 0.620, 0.400, 0.050 },
            bad        = { 0.620, 0.160, 0.100 },
            info       = { 0.180, 0.360, 0.620 },
            jade       = { 0.180, 0.480, 0.370 },
            TANK       = { 0.180, 0.370, 0.560 },
            HEALER     = { 0.180, 0.480, 0.370 },
            DAMAGER    = { 0.560, 0.170, 0.120 },
        },
        fonts = { title = F .. "IMFellEnglishSC-Regular.ttf", data = F .. "AlegreyaSans-Medium.ttf",
                  dataBold = F .. "AlegreyaSans-Bold.ttf", titleScale = 1.06, dataScale = 1.08 },
        window  = { tex = "parchment", tile = true, tint = { 1, 1, 1, 1 } },
        content = { tex = "parchment", tile = true, tint = { 0.97, 0.95, 0.90, 1 } },
        outer = { 0.16, 0.11, 0.07, 1 }, inner = { 0.722, 0.537, 0.184, 1 },
        corner = "corner_illum", medal = { 0.72, 0.54, 0.18, 1 },
        mark = { tex = "seal", tint = { 1, 1, 1, 1 }, size = 12 }, markLine = { 0.561, 0.165, 0.122, 1 },
        header = { 0.42, 0.27, 0.16, 1 },
        headerText = { 0.965, 0.914, 0.788 }, headerSub = { 0.85, 0.76, 0.60 },
        btnPrimary = { 0.70, 0.20, 0.15, 1 }, btnPrimaryHover = { 0.85, 0.28, 0.20, 1 },
        btnSecondary = { 0.95, 0.90, 0.80, 1 }, btnSecondaryHover = { 1.00, 0.97, 0.88, 1 },
        btnLine = { 0.24, 0.16, 0.10, 1 },
        btnPrimaryText = { 0.973, 0.922, 0.816 },
        tabSelected = { 0.98, 0.95, 0.86, 1 }, tabIdle = { 0.66, 0.56, 0.42, 1 },
        tabIdleText = { 0.169, 0.114, 0.071 },
        bar = "wax", trough = { 0.98, 0.95, 0.87, 1 },
    },
}

Theme.LOOKS.crimson = {
    -- Entwurf D "Crimson Court" (05.10.2026): Weinrot und Altgold, Samt mit
    -- Damast, Goldfiligran in den Ecken, Kerzenlicht statt Glut.
    palette = {
        windowBg   = { 0.078, 0.024, 0.035, 0.97 },  -- Samt       #140609
        sidebarBg  = { 0.098, 0.035, 0.051, 1.00 },
        panelBg    = { 0.165, 0.063, 0.090, 1.00 },  -- Hofwein    #2a1017
        rowBg      = { 0.196, 0.075, 0.106, 1.00 },
        rowAltBg   = { 0.137, 0.051, 0.071, 1.00 },
        rowHover   = { 0.227, 0.086, 0.125, 1.00 },
        border     = { 0.420, 0.322, 0.188, 1.00 },  -- Altgold dunkel
        borderLit  = { 0.788, 0.639, 0.353, 1.00 },  -- Altgold    #c9a35a
        divider    = { 0.259, 0.106, 0.149, 1.00 },
        text       = { 0.953, 0.914, 0.863 },        -- Creme      #f3e9dc
        textDim    = { 0.788, 0.702, 0.651 },        -- #c9b3a6, 8.8:1
        textFaint  = { 0.635, 0.541, 0.498 },        -- #a28a7f, 5.5:1
        heading    = { 0.890, 0.776, 0.494 },        -- #e3c67e
        gold       = { 0.890, 0.776, 0.494 },
        goldBright = { 0.984, 0.945, 0.839 },
        goldMid    = { 0.788, 0.639, 0.353 },
        goldDim    = { 0.541, 0.416, 0.200 },
        goldDeep   = { 0.290, 0.110, 0.161, 1.00 },
        attn       = { 0.816, 0.478, 0.541 },        -- Rose #d07a8a
    },
    -- Cormorant hat kleine Mittellaengen (groesser setzen), Montserrat ist
    -- breit (kleiner setzen) — sonst laufen die Spalten ueber.
    fonts = { title = F .. "Cormorant-Bold.ttf", data = F .. "Montserrat-Medium.ttf",
              dataBold = F .. "Montserrat-Bold.ttf", titleScale = 1.15, dataScale = 0.86 },
    window  = { tex = "velvet", tile = true, tint = { 1, 1, 1, 0.98 } },
    content = { tex = "velvet", tile = true, tint = { 0.82, 0.80, 0.80, 1 } },
    outer = { 0.541, 0.416, 0.200, 1 }, inner = { 0.788, 0.639, 0.353, 0.55 },
    corner = "corner_filigree", medal = { 0.79, 0.64, 0.35, 1 },
    mark = { tex = "diamond", tint = { 0.890, 0.776, 0.494, 1 } }, markLine = { 0.890, 0.776, 0.494, 1 },
    header = { 0.36, 0.13, 0.18, 1 },
    btnPrimary = { 0.92, 0.78, 0.47, 1 }, btnPrimaryHover = { 1.00, 0.90, 0.62, 1 },
    btnSecondary = { 0.36, 0.13, 0.19, 1 }, btnSecondaryHover = { 0.48, 0.18, 0.26, 1 },
    btnLine = { 0.541, 0.416, 0.200, 1 },
    -- Der goldene Hauptknopf traegt dunkle Schrift, wie im Entwurf.
    btnPrimaryText = { 0.165, 0.051, 0.078 },
    tabSelected = { 0.36, 0.13, 0.19, 1 }, tabIdle = { 0.20, 0.07, 0.10, 1 },
    bar = "gold", trough = { 0.047, 0.012, 0.024, 1 },
}

--- Fuer Aufrufer und Tests aus der ersten Fassung (nur Schmiede).
Theme.FORGE_PALETTE = Theme.LOOKS.forge.palette

--- Diese Vorlagen sind nur Optik; mit einem eigenen Look zeichnet das Addon
--- selbst. Eingabefelder, Suchfeld und Haken bleiben nativ: Ihre Rueckfaelle
--- sind nicht ueberall vorhanden, und sie tragen Verhalten, nicht nur Aussehen.
Theme.NATIVE_SKIP = {
    PortraitFrameTemplate = true,
    UIPanelButtonTemplate = true,
    PanelTabButtonTemplate = true,
    CharacterFrameTabButtonTemplate = true,
    InsetFrameTemplate = true,
}
Theme.FORGE_SKIP = Theme.NATIVE_SKIP

--- Der gewaehlte Look laut Einstellung: "forge" | "twilight" | "codex" | "blizzard".
function Theme.LookKey()
    local Config = GA.Core and GA.Core.Config
    if not Config or not Config.Get then return Theme.DEFAULT_LOOK end
    local ok, value = pcall(Config.Get, Config, "uiLook")
    if not ok then return Theme.DEFAULT_LOOK end
    if value == "blizzard" or Theme.LOOKS[value] then return value end
    return Theme.DEFAULT_LOOK
end

--- Die Beschreibung des laufenden Looks, oder nil bei Blizzard.
function Theme.Look()
    return Theme.look and Theme.LOOKS[Theme.look] or nil
end

--- Einmal nach dem Laden der Datenbank: Farben tauschen, Look merken.
function Theme.ApplyLook()
    local key = Theme.LookKey()
    local def = Theme.LOOKS[key]
    if not def then
        Theme.look = "blizzard"
        return
    end
    for name, value in pairs(def.palette) do Theme.color[name] = value end
    Theme.look = key
end

local mediaLoads = {}
--- Pfad einer eigenen Textur — nur, wenn der Client sie wirklich laedt.
function Theme.Media(key)
    if mediaLoads[key] == nil then
        local path = Theme.MEDIA[key]
        mediaLoads[key] = (path and Theme.TextureExists(path)) and path or false
    end
    return mediaLoads[key] or nil
end

--- Woher das Logo kommt: "addon" (das mitgelieferte Bild), "tabard" (das
--- Gildenwappen des Spiels, bei allen gleich, ohne Abgleich) oder "file"
--- (Media/GuildLogo.tga, die jeder selbst hinlegt).
function Theme.LogoSource()
    local db = GA.Core.Database
    local config = db and db.account and db.account.config
    local source = config and config.logoSource
    if source == "tabard" or source == "file" then return source end
    return "addon"
end

--- Ein Logo-Rahmen: drei Texturen uebereinander (fuer das Wappen), eine
--- davon reicht fuer ein Bild. :Refresh() zeichnet nach der Einstellung und
--- sagt, was es gezeichnet hat — "addon" | "tabard" | "file" | nil.
--- Faellt die gewaehlte Quelle aus (Datei fehlt, Wappen nicht lesbar),
--- kommt das Addon-Bild; nil nur, wenn auch das fehlt.
function Theme.LogoFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints(frame)
    frame.emblem = frame:CreateTexture(nil, "ARTWORK")
    frame.emblem:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetAllPoints(frame)

    local function clear()
        for _, tex in ipairs({ frame.background, frame.emblem, frame.border }) do
            pcall(tex.SetTexture, tex, nil)
            tex:Hide()
        end
    end

    local function picture(path)
        clear()
        if not path or not Theme.TextureExists(path) then return false end
        frame.emblem:ClearAllPoints()
        frame.emblem:SetAllPoints(frame)
        if not pcall(frame.emblem.SetTexture, frame.emblem, path) then return false end
        frame.emblem:Show()
        return true
    end

    function frame:Refresh()
        local source = Theme.LogoSource()
        if source == "tabard" then
            clear()
            -- Das Emblem kleiner als der Rock, wie im Gildenfenster.
            local w, h = self:GetWidth() or 64, self:GetHeight() or 64
            self.emblem:ClearAllPoints()
            self.emblem:SetPoint("CENTER", self, "CENTER", 0, 0)
            self.emblem:SetWidth(w * 0.62) self.emblem:SetHeight(h * 0.62)
            if GA.Core.Compat.SetGuildTabard(self.emblem, self.background, self.border) then
                self.background:Show() self.emblem:Show() self.border:Show()
                self.shown = "tabard"
                return "tabard"
            end
        elseif source == "file" then
            if picture(Theme.MEDIA.guildLogo) then self.shown = "file" return "file" end
        end
        if picture(Theme.MEDIA.logo) then self.shown = "addon" return "addon" end
        self.shown = nil
        return nil
    end

    return frame
end

--- Gebuersteter Stahl, eingefaerbt. Ohne Textur: die Farbe flach.
function Theme.Metal(texture, tint)
    local path = Theme.Media("metal")
    if path and pcall(texture.SetTexture, texture, path) then
        texture:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
        return texture
    end
    return Theme.Paint(texture, tint)
end

function Theme.MetalFill(frame, tint, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    return Theme.Metal(texture, tint)
end

--- Flaeche nach einer Beschreibung { tex, tile, tint } oder { fill }.
function Theme.LookFill(frame, spec, layer)
    if spec.fill then return Theme.Fill(frame, spec.fill, layer) end
    if spec.tile then return Theme.TexturedFill(frame, Theme.MEDIA[spec.tex], spec.tint, layer) end
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    local path = Theme.Media(spec.tex)
    if path and pcall(texture.SetTexture, texture, path) then
        local t = spec.tint
        texture:SetVertexColor(t[1], t[2], t[3], t[4] or 1)
        return texture
    end
    return Theme.Paint(texture, Theme.color.windowBg)
end

local function accent(color)
    local c = Theme.color
    return color == nil or color == c.gold or color == c.goldDim or color == c.goldMid
        or color == c.goldDeep or color == c.goldBright or color == c.warn
end

--- Fuellung eines Fortschrittsbalkens: die Balkentextur des Looks (Glut,
--- Juwel, Wachs) fuer die Akzentfarbe, Stahl in der Wunschfarbe fuer alles
--- andere (Rollen, Zustaende). Bei Blizzard flach wie bisher.
function Theme.BarFill(texture, color)
    color = color or Theme.color.gold
    local look = Theme.Look()
    if look then
        if accent(color) then
            local path = Theme.Media(look.bar)
            if path and pcall(texture.SetTexture, texture, path) then
                texture:SetVertexColor(1, 1, 1, 1)
                return texture
            end
        else
            local path = Theme.Media("metal")
            if path and pcall(texture.SetTexture, texture, path) then
                local k = look.light and 1 or 1.3
                texture:SetVertexColor(math.min(1, color[1] * k), math.min(1, color[2] * k),
                    math.min(1, color[3] * k), 1)
                return texture
            end
        end
    end
    return Theme.Paint(texture, color)
end

--- Rinne eines Fortschrittsbalkens.
function Theme.BarTrough(texture)
    local look = Theme.Look()
    if look then return Theme.Paint(texture, look.trough) end
    return Theme.Paint(texture, Theme.color.windowBg)
end

--- Rahmen eines eigenen Looks: aussen dunkel (bei Twilight Bronze), innen
--- eine Linie mit Glanzkante; beim Fenster die Flaeche des Looks und Nieten
--- in den Ecken.
--- @param kind string "window" | "panel"
function Theme.ForgeFrame(frame, kind, bgColor)
    if frame.gaForge then return true end
    frame.gaForge = true
    local look = Theme.Look() or Theme.LOOKS.forge
    local window = kind == "window"

    if window then
        frame.gaFill = Theme.LookFill(frame, look.window)
    else
        frame.gaFill = Theme.Fill(frame, bgColor or Theme.color.panelBg)
    end

    Theme.Outline(frame, window and look.outer or BLACK)
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    Theme.Outline(inner, window and (look.inner or Theme.color.borderLit) or Theme.color.border)
    Theme.Edge(inner, "TOP", look.light and { 1, 1, 1, 0.35 } or { 1, 1, 1, 0.08 }, 1)

    if window then
        local gap = CreateFrame("Frame", nil, frame)
        gap:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        gap:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        Theme.Outline(gap, look.outer)

        -- Eckornamente des Looks, UEBER den Kindern (Kopfleiste, Inhalt):
        -- Texturen eines Frames liegen immer unter seinen Kindern, darum ein
        -- eigener Rahmen weit oben. Er nimmt keine Maus an.
        local cornerTex = look.corner and Theme.Media(look.corner)
        if cornerTex then
            local layer = CreateFrame("Frame", nil, frame)
            layer:SetAllPoints(frame)
            layer:SetFrameLevel((frame:GetFrameLevel() or 1) + 30)
            local FLIP = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 },
                           BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
            for cornerPoint, tc in pairs(FLIP) do
                local orn = layer:CreateTexture(nil, "OVERLAY")
                orn:SetTexture(cornerTex)
                -- Innen in der Ecke; die Kopfleiste haelt seitlich Abstand
                -- (Theme.HeaderSide), damit sie nicht anstoesst.
                orn:SetWidth(Theme.CORNER_SIZE) orn:SetHeight(Theme.CORNER_SIZE)
                local d = Theme.CORNER_INSET
                orn:SetPoint(cornerPoint, frame, cornerPoint, string.find(cornerPoint, "LEFT") and d or -d,
                    string.find(cornerPoint, "TOP") and -d or d)
                orn:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            end
            frame.gaOrnaments = layer
        end

        local rivet = not cornerTex and look.rivet and Theme.Media("rivet")
        if rivet then
            for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
                local dot = frame:CreateTexture(nil, "OVERLAY")
                dot:SetTexture(rivet)
                dot:SetWidth(10) dot:SetHeight(10)
                dot:SetPoint("CENTER", frame, corner, string.find(corner, "LEFT") and 3 or -3,
                    string.find(corner, "TOP") and -3 or 3)
                dot:SetVertexColor(look.rivet[1], look.rivet[2], look.rivet[3], 1)
            end
        end
    end
    return true
end

--- Klassenfarben fuer Text auf der Flaeche des Looks. Auf dem hellen Codex
--- waeren Schurkengelb und Priesterweiss unlesbar — dort die Tintenfassung.
local CLASS_INK = {
    DRUID = { 0.635, 0.290, 0.000 }, ROGUE = { 0.478, 0.416, 0.000 }, WARRIOR = { 0.431, 0.310, 0.173 },
    MAGE = { 0.059, 0.416, 0.522 }, WARLOCK = { 0.294, 0.298, 0.690 }, PRIEST = { 0.290, 0.290, 0.290 },
    SHAMAN = { 0.000, 0.306, 0.612 }, PALADIN = { 0.627, 0.200, 0.416 }, HUNTER = { 0.294, 0.431, 0.118 },
}

function Theme.ClassColor(classFile)
    local look = Theme.Look()
    if look and look.light then
        local ink = classFile and CLASS_INK[classFile]
        if ink then return ink[1], ink[2], ink[3] end
        local r, g, b = GA.Core.Util.ClassColor(classFile)
        return r * 0.45, g * 0.45, b * 0.45
    end
    return GA.Core.Util.ClassColor(classFile)
end

function Theme.ColorByClass(text, classFile)
    local r, g, b = Theme.ClassColor(classFile)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text or "")
end

--- Blizzards Eingabefeld auf einem hellen Look: helle Unterlage, Tinte als
--- Schrift. Sonst stuende weisse Schrift auf Pergament.
function Theme.StyleEditBox(box)
    local look = Theme.Look()
    if not look or not look.light or not box then return end
    local back = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetPoint("TOPLEFT", box, "TOPLEFT", -4, 0)
    back:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    Theme.Paint(back, { 0.99, 0.97, 0.91, 0.92 })
    if box.SetTextColor then
        local c = Theme.color.text
        box:SetTextColor(c[1], c[2], c[3])
    end
end

-- ------------------------------------------------------------- Hilfsmittel ---

--- Setzt eine einfarbige Textur. SetColorTexture fehlt in sehr alten Linien.
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

--- DIE EINE ROLLENFARBE. Drei Ansichten hatten je eine eigene Tabelle
--- (Dungeonhub, Uebersicht, Zusammen) und zwei Schluesselsaetze gab es
--- auch: TANK/HEAL/DPS in Dungeonhub und Zusammen, tank/healer/melee/
--- ranged im Raidplan (so steht es im Austauschformat). Hier kommen beide
--- an, und die Farbe kommt aus der Palette des Looks — auf Codex dunkler,
--- weil hell auf Pergament unlesbar waere.
local ROLE_KEY = {
    TANK = "TANK", HEAL = "HEALER", HEALER = "HEALER", DPS = "DAMAGER", DAMAGER = "DAMAGER",
    tank = "TANK", healer = "HEALER", melee = "DAMAGER", ranged = "DAMAGER", dps = "DAMAGER",
}
function Theme.RoleColor(role)
    return Theme.color[ROLE_KEY[role or ""] or ""] or Theme.color.textDim
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
--- DIE RUNDE TEXTUR, gemessen statt angenommen. GESEHEN 29.09.2026: Die
--- eigene Media/Circle.tga blieb im Dungeonhub eckig — der Client laedt
--- sie nicht, was TextureExists dort auch sagte. Das Spiel selbst hat
--- runde Scheiben (die Anzeigen der Bereitschaftsabfrage, Indicator-*);
--- die werden zuerst probiert, die eigene danach. Ergebnis gemerkt.
--- @return string|nil pfad  nil, wenn nichts Rundes laedt
--- TOENT eine Textur, statt sie zu uebermalen. GESEHEN 29.09.2026: Nach
--- SetTexture(rund) kam Theme.Paint — und das setzt SetColorTexture, das
--- die Datei durch eine einfarbige Flaeche ERSETZT. Der Kreis war da, er
--- wurde uebermalt; darum blieben Scheiben, Marken und Schalter eckig.
--- Fuer alles mit Textur gilt: Tint, nie Paint.
function Theme.Tint(texture, color)
    if not texture or not texture.SetVertexColor then return end
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

function Theme.RoundTexture()
    if Theme.roundTexture ~= nil then return Theme.roundTexture or nil end
    -- Die eigene zuerst: flach weiss, damit die Toenung die Farbe ist.
    -- Die Anzeige des Spiels ist schattiert und ein Rueckfall.
    for _, path in ipairs({
        "Interface\\AddOns\\GuildArmory\\Media\\Circle.tga",
        "Interface\\COMMON\\Indicator-Gray",
    }) do
        if Theme.TextureExists(path) then
            Theme.roundTexture = path
            return path
        end
    end
    Theme.roundTexture = false
    return nil
end

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
    if Theme.Look() then return Theme.ForgeFrame(frame, kind or "panel", bgColor) end
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
--- Das Rollensymbol des Spiels — Schild, Kreuz, Schwert — aus dem
--- Portrait-Blatt der Gruppensuche, Ausschnitte wie
--- GetTexCoordsForRoleSmallCircle. false, wenn das Blatt fehlt: dann
--- bleibt der Buchstabe (Wunsch 02.10.2026).
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEAL = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DPS  = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local ROLE_SHEET = [[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]]

function Theme.SetRoleIcon(texture, role)
    local box = ROLE_COORDS[role]
    if not box or not Theme.TextureExists(ROLE_SHEET) then return false end
    if not pcall(texture.SetTexture, texture, ROLE_SHEET) then return false end
    pcall(texture.SetTexCoord, texture, box[1], box[2], box[3], box[4])
    return true
end

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
    if Theme.look and Theme.look ~= "blizzard" and Theme.NATIVE_SKIP[template] then
        Theme.native[template] = false
        return nil, "forge"
    end
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
    if frameType == "EditBox" then Theme.StyleEditBox(frame) end
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
    -- Eigener Look: kein Questlog-Leuchten, sondern ein ruhiges Band mit
    -- einer Linie in der Farbe der Reitermarke darunter.
    local look = Theme.Look()
    if look then
        Theme.Paint(bar, look.light and { 0.43, 0.27, 0.12, 0.08 } or { 0, 0, 0, 0.22 })
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        line:SetHeight(1)
        local c = look.markLine or Theme.color.gold
        Theme.Paint(line, { c[1], c[2], c[3], 0.55 })
        return bar
    end
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
