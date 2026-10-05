--[[----------------------------------------------------------------------------
    Views/Crafting — wer in der Gilde kann das herstellen?

    Aufgebaut wie das Charakterfenster (Entwurf A, 27.09.2026): links die
    Berufe als Liste mit Kopfzeile, rechts eine eingelassene Flaeche mit
    KOPF (Symbol, Titel, Zeile darunter, Kennzahl rechts) und darunter die
    Antwort als Tabelle. Der Kopf sagt immer, WAS gerade zu sehen ist —
    derselbe Platz, drei Fragen:

        nichts gewaehlt     alle Berufe, alle Hersteller
        Beruf gewaehlt      wer ihn kann, mit Fertigkeit als Balken
        Suchfeld gefuellt   wer diesen einen Gegenstand herstellen kann
        Person angeklickt   die Rezepte genau dieser Person

    Man denkt ohnehin im Kreis: Wer kann das? Was kann der sonst noch? Wer
    kann DAS wiederum? Ein Klick auf ein Rezept dreht die Frage deshalb
    zurueck und sucht nach seinen Herstellern.

    ZWEI TABELLEN, NICHT EINE. Leute und Rezepte haben verschiedene Spalten
    — Fertigkeit und Alter bei den einen, Symbol und Art bei den anderen.
    Eine Kopfzeile, die je nach Inhalt luegt, waere schlimmer als ein zweiter
    Zeilenvorrat; der kostet so viele Zeilen, wie gerade sichtbar sind.

    WAS EIN KLICK NICHT TUT: nachfragen. Alles, was hier steht, liegt schon
    in der Datenbank — gemeldet hat es die Person beim Scannen ihres eigenen
    Berufsfensters. Es gibt keinen Weg, die Rezepte von jemandem zu holen,
    der sie nie geschickt hat, und die Ansicht tut auch nicht so.

    KEINE AUSWERTUNG HIER. Was zaehlt, entscheidet Professions/Crafting.lua.
------------------------------------------------------------------------------]]

local _, GA = ...

local CraftingView = {}

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

CraftingView.titleKey = "NAV_CRAFTING"

local LIST_WIDTH = 300
local TILE_SIZE = 44
local BAR_WIDTH = 34

--- Als Funktionen, nicht als Tabellen: Eine beim Laden gebaute Spaltenliste
--- traegt die Beschriftungen der Sprache, die beim Laden galt — und die
--- Einstellung steht erst bei PLAYER_LOGIN fest (siehe Locale.lua).
---
--- Die Breiten stehen HIER und nirgends sonst: Kopfzeile und Zeilen rechnen
--- ihre Positionen aus derselben Liste, damit beides zusammen wandert.
local COLUMN_GAP = 6
local COLUMN_X0 = 8

local function professionColumns()
    return {
        { key = "icon",     label = "",               width = 16 },
        { key = "name",     label = L.COL_NAME,       width = 150 },
        { key = "crafters", label = L.COL_CRAFTERS,   width = 36, justify = "RIGHT" },
        { key = "recipes",  label = L.COL_RECIPES,    width = 50, justify = "RIGHT" },
    }
end

local function crafterColumns()
    return {
        { key = "crest",      label = "",                width = 16 },
        { key = "name",       label = L.COL_NAME,        width = 150 },
        { key = "profession", label = L.COL_PROFESSION,  width = 120 },
        { key = "skill",      label = L.COL_SKILL,       width = 84, justify = "RIGHT" },
        { key = "read",       label = L.COL_READ,        width = 90 },
    }
end

local function recipeColumns()
    return {
        { key = "icon", label = "",          width = 16 },
        { key = "name", label = L.COL_ITEM,  width = 260 },
        { key = "kind", label = L.COL_TYPE,  width = 110 },
    }
end

--- Linke Kante jeder Spalte, aus einer Spaltenliste gerechnet.
local function columnOffsets(columns)
    local x, out, breiten = COLUMN_X0, {}, {}
    for _, column in ipairs(columns) do
        out[column.key] = x
        breiten[column.key] = column.width
        x = x + column.width + COLUMN_GAP
    end
    return out, breiten
end

--- Ist das eine Textur, die sich setzen laesst? Eine Zahl (FileID) oder ein
--- nicht leerer Pfad — nil und "" sind keine.
local function zeigeSymbol(texture, icon)
    if not texture then return false end
    local brauchbar = type(icon) == "number" or (type(icon) == "string" and icon ~= "")
    if brauchbar and pcall(texture.SetTexture, texture, icon) then
        pcall(texture.SetTexCoord, texture, 0.08, 0.92, 0.08, 0.92)
        texture:Show()
        return true
    end
    texture:Hide()
    return false
end

-- ================================================================== Aufbau ----

function CraftingView:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- ---------------------------------------------------- Linke Spalte ------

    local listPanel = Widgets.Panel(frame, L.CRAFT_PROFESSIONS)
    listPanel:SetWidth(LIST_WIDTH)
    listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    listPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    self.listPanel = listPanel

    -- Unten der Stand des Wissens — dieselbe Stelle, an der im
    -- Charakterfenster der Inspect-Hinweis steht.
    self.status = Theme.Label(listPanel.content, "", fonts.small, Theme.color.textFaint)
    self.status:SetPoint("BOTTOMLEFT", listPanel.content, "BOTTOMLEFT", 2, 0)
    self.status:SetPoint("RIGHT", listPanel.content, "RIGHT", -2, 0)
    self.status:SetJustifyH("LEFT")
    self.status:SetHeight(30)

    self.professionList = Widgets.ScrollList(listPanel.content, {
        rowHeight = Theme.size.rowHeight,
        columns = professionColumns(),
        createRow = function(row) self:BuildProfessionRow(row) end,
        updateRow = function(row, entry) self:UpdateProfessionRow(row, entry) end,
        onClickRow = function(entry)
            -- Nochmal derselbe Beruf hebt die Wahl auf. Ein Filter ohne Weg
            -- zurueck ist eine Sackgasse.
            self.selectedLine = (self.selectedLine == entry.line) and nil or entry.line
            self.detail = nil
            self:Refresh()
        end,
    })
    self.professionList:SetPoint("TOPLEFT", listPanel.content, "TOPLEFT", 0, 0)
    self.professionList:SetPoint("BOTTOMRIGHT", self.status, "TOPRIGHT", 2, 4)

    -- ---------------------------------------------------- Rechte Flaeche ----

    local result = Widgets.Inset(frame)
    result:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", gap, 0)
    result:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.result = result

    -- Kopf: Kachel mit Symbol, Titel, Zeile darunter, Kennzahl rechts.
    local tile = CreateFrame("Frame", nil, result)
    tile:SetWidth(TILE_SIZE) tile:SetHeight(TILE_SIZE)
    tile:SetPoint("TOPLEFT", result, "TOPLEFT", 16, -14)
    Theme.Fill(tile, Theme.color.rowAltBg)
    Theme.Outline(tile, Theme.color.goldDeep)
    self.tile = tile

    self.tileIcon = tile:CreateTexture(nil, "ARTWORK")
    self.tileIcon:SetPoint("TOPLEFT", tile, "TOPLEFT", 2, -2)
    self.tileIcon:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -2, 2)

    self.bigValue = Theme.Label(result, "", fonts.hero, Theme.color.goldBright)
    self.bigValue:SetPoint("TOPRIGHT", result, "TOPRIGHT", -20, -16)
    self.bigLabel = Theme.Label(result, "", fonts.body, Theme.color.textDim)
    self.bigLabel:SetPoint("TOPRIGHT", self.bigValue, "BOTTOMRIGHT", 0, -2)

    self.title = Theme.Label(result, "", fonts.hero, Theme.color.goldBright)
    self.title:SetPoint("TOPLEFT", tile, "TOPRIGHT", 12, -2)
    self.title:SetPoint("RIGHT", self.bigValue, "LEFT", -16, 0)
    self.title:SetJustifyH("LEFT")
    self.title:SetWordWrap(false)

    -- DIE ZEILE ENDET VOR DER KENNZAHL — dieselbe Lehre wie im
    -- Charakterfenster: ohne rechtes Ende laeuft ein langer Text in die
    -- Zahl hinein.
    self.meta = Theme.Label(result, "", fonts.body, Theme.color.textDim)
    self.meta:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 1, -3)
    self.meta:SetPoint("RIGHT", self.bigLabel, "LEFT", -16, 0)
    self.meta:SetJustifyH("LEFT")
    self.meta:SetWordWrap(false)

    -- Werkzeugzeile: Suche links, Knoepfe rechts.
    self.search = Widgets.SearchBox(result, L.CRAFT_SEARCH, function(text)
        self:SetSearch(text)
    end)
    self.search:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, -12)
    self.search:SetWidth(280)

    -- DAS SPIEL KANN DAS BESSER. Ein Berufe-Link oeffnet Blizzards eigenes
    -- Fenster — mit Kategorien, Reagenzien und allem, was diese Liste nicht
    -- hat. Der Knopf steht trotzdem NEBEN der Liste und nicht an ihrer
    -- Stelle: Der Link ist eine Abfrage beim Server und funktioniert nur,
    -- solange die Person online ist. Die Liste funktioniert auch nachts.
    self.openButton = Widgets.Button(result, L.CRAFT_OPEN, function()
        local detail = self.detail
        if not detail then return end

        -- BEI SICH SELBST GAR NICHT ERST UEBER EINEN LINK. Der ist eine
        -- Abfrage beim Server nach fremden Daten; die eigenen liegen im
        -- eigenen Client. Das war auch der gemeldete Fall — bei sich selbst
        -- ging es nicht, und dort kann es gar nicht am Link liegen.
        if self:IstEigen(detail.name) then
            local okEigen, wegEigen =
                Compat.OpenOwnProfession(detail.line, detail.lineName)
            if okEigen then
                GA.Core.Debug:Info(L.CRAFT_OPEN_SENT, tostring(wegEigen))
            else
                GA.Core.Debug:Info("%s (%s)", L.CRAFT_OPEN_FAILED, tostring(wegEigen))
            end
            return
        end

        if not detail.link then return end
        -- DER GRUND GEHOERT IN DEN CHAT, nicht ins Schweigen. Ein Knopf, der
        -- nichts tut und nichts sagt, ist von aussen nicht aufzuklaeren —
        -- genau so war er gemeldet.
        local ok, weg = Compat.OpenTradeSkillLink(detail.link)
        if ok then
            -- AUCH DER ERFOLG MELDET SICH — solange nicht gemessen ist,
            -- welcher der beiden Wege auf dieser Linie traegt. Geht danach
            -- trotzdem kein Fenster auf, ist der Weg gelaufen und der Server
            -- hat nichts herausgegeben; das ist eine andere Baustelle als
            -- ein Link, der nie abgeschickt wurde.
            --
            -- MIT DEM ALTER, IMMER. Ein Berufe-Link ist keine Adresse,
            -- sondern ein Verweis auf eine laufende Sitzung: Der Server
            -- beantwortet ihn nur, solange der andere angemeldet ist UND ihn
            -- in dieser Sitzung erzeugt hat. Ein Eintrag von gestern sieht
            -- genauso aus wie einer von eben — "vor 21 Std." ist die
            -- Auskunft, die den Unterschied macht, und sie sagt gleich, was
            -- zu tun ist. KEINE SCHWELLE: Ab wann ein Link tot ist, haengt
            -- an der Anmeldung des anderen, und die kennt dieser Client
            -- nicht. Das Alter ist eine Messung, eine Stundenzahl waere
            -- eine Behauptung.
            GA.Core.Debug:Info(L.CRAFT_OPEN_SENT, tostring(weg))
            GA.Core.Debug:Info(L.CRAFT_OPEN_STALE, tostring(detail.name),
                detail.ts and Util.TimeAgo(detail.ts) or L.UNKNOWN)
        else
            GA.Core.Debug:Info("%s (%s)", L.CRAFT_OPEN_FAILED, tostring(weg))
        end
    end, "primary")
    self.openButton:SetPoint("RIGHT", result, "RIGHT", -16, 0)
    self.openButton:SetPoint("TOP", self.search, "TOP", 0, 0)
    self.openButton:Hide()

    -- Zurueck aus der Rezeptliste einer Person. Steht nur da, solange es
    -- etwas zurueckzugehen gibt.
    self.backButton = Widgets.Button(result, L.CRAFT_BACK, function()
        self.detail = nil
        self:Refresh()
    end)
    self.backButton:SetPoint("RIGHT", self.openButton, "LEFT", -6, 0)
    self.backButton:SetPoint("TOP", self.search, "TOP", 0, 0)
    self.backButton:Hide()

    -- Die beiden Tabellen liegen uebereinander; es ist immer nur eine da.
    self.crafters = Widgets.ScrollList(result, {
        rowHeight = Theme.size.rowHeight,
        columns = crafterColumns(),
        createRow = function(row) self:BuildCrafterRow(row) end,
        updateRow = function(row, entry) self:UpdateCrafterRow(row, entry) end,
        onClickRow = function(entry)
            -- Eine Person anklicken oeffnet ihre Rezepte.
            self:ShowRecipes(entry.name, entry.line, entry.lineName)
        end,
    })
    self.crafters:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 0, -10)
    self.crafters:SetPoint("BOTTOMRIGHT", result, "BOTTOMRIGHT", -16, 14)

    self.recipes = Widgets.ScrollList(result, {
        rowHeight = Theme.size.rowHeight,
        columns = recipeColumns(),
        createRow = function(row) self:BuildRecipeRow(row) end,
        updateRow = function(row, entry) self:UpdateRecipeRow(row, entry) end,
        onClickRow = function(entry)
            -- Ein Rezept anklicken dreht die Frage um: von "was kann der"
            -- zu "wer kann das". Das ist die Schleife, in der man ohnehin
            -- denkt.
            if not entry.itemID then return end
            -- :Clear(), nicht :SetText(). Beide Fassungen des Suchfelds
            -- haben Clear; SetText nur die native — der gezeichnete
            -- Rueckfall ist ein Rahmen um ein EditBox und haette geworfen.
            self.search:Clear()
            self.detail = nil
            self.searchItemID, self.searchText = entry.itemID, tostring(entry.itemID)
            self:Refresh()
        end,
        onEnterRow = function(row, entry)
            if entry and entry.itemID then
                Widgets.ShowItemTooltip(row, entry.itemID)
            end
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.recipes:SetAllPoints(self.crafters)
    self.recipes:Hide()

    GA.Core.Callbacks:On("CRAFTING_CHANGED", function()
        if frame:IsShown() then CraftingView:Refresh() end
    end, "CraftingView")

    return frame
end

-- ================================================================== Zeilen ----

--- Eine Berufszeile: Symbol, Name, Zahl der Hersteller, Zahl der Rezepte.
function CraftingView:BuildProfessionRow(row)
    local fonts = Theme.Fonts()
    local x, w = columnOffsets(professionColumns())

    row.edge = Theme.Fill(row, Theme.color.gold)
    row.edge:ClearAllPoints()
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(2)
    row.edge:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(14) row.icon:SetHeight(14)
    row.icon:SetPoint("LEFT", row, "LEFT", x.icon, 0)

    row.nameText = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.nameText:SetPoint("LEFT", row, "LEFT", x.name, 0)
    row.nameText:SetWidth(w.name)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.craftersText = Theme.Label(row, "", fonts.rowBold, Theme.color.goldBright)
    row.craftersText:SetPoint("LEFT", row, "LEFT", x.crafters, 0)
    row.craftersText:SetWidth(w.crafters)
    row.craftersText:SetJustifyH("RIGHT")

    row.recipesText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.recipesText:SetPoint("LEFT", row, "LEFT", x.recipes, 0)
    row.recipesText:SetWidth(w.recipes)
    row.recipesText:SetJustifyH("RIGHT")
end

function CraftingView:UpdateProfessionRow(row, entry)
    local selected = entry.line == self.selectedLine
    if selected then
        row.edge:Show()
        Theme.Paint(row.background, Theme.color.rowHover)
    else
        row.edge:Hide()
    end

    zeigeSymbol(row.icon, Compat.GetProfessionIcon(entry.line))

    row.nameText:SetText(entry.name or tostring(entry.line))
    local color = selected and Theme.color.goldBright or Theme.color.text
    row.nameText:SetTextColor(color[1], color[2], color[3])

    row.craftersText:SetText(tostring(#entry.crafters))
    local rezepte = 0
    for _, crafter in ipairs(entry.crafters) do
        rezepte = rezepte + (crafter.recipes or 0)
    end
    row.recipesText:SetText(tostring(rezepte))
end

--- Eine Herstellerzeile: Wappen, Name mit Online-Punkt, Beruf, Fertigkeit
--- als Balken und Zahl, Alter der Auskunft — und bei einer Gegenstandssuche
--- der Fragen-Knopf.
function CraftingView:BuildCrafterRow(row)
    local fonts = Theme.Fonts()
    local x, w = columnOffsets(crafterColumns())

    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(14) row.crest:SetHeight(14)
    row.crest:SetPoint("LEFT", row, "LEFT", x.crest, 0)

    row.nameText = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.nameText:SetPoint("LEFT", row, "LEFT", x.name, 0)
    row.nameText:SetWidth(w.name - 10)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetWidth(5) row.dot:SetHeight(5)
    row.dot:SetPoint("LEFT", row, "LEFT", x.name + w.name - 6, 0)

    row.professionText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.professionText:SetPoint("LEFT", row, "LEFT", x.profession, 0)
    row.professionText:SetWidth(w.profession)
    row.professionText:SetJustifyH("LEFT")
    row.professionText:SetWordWrap(false)

    -- Balken links, Zahl rechts — die Zahl ist die Auskunft, der Balken die
    -- Einordnung auf einen Blick. Wie das Itemlevel im Charakterfenster.
    row.barBg = row:CreateTexture(nil, "ARTWORK")
    Theme.BarTrough(row.barBg)
    row.barBg:SetWidth(BAR_WIDTH) row.barBg:SetHeight(5)
    row.barBg:SetPoint("LEFT", row, "LEFT", x.skill, 0)

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(row.barFill, Theme.color.goldDim)
    row.barFill:SetHeight(5)
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)

    row.skillText = Theme.Label(row, "", fonts.rowBold, Theme.color.goldBright)
    row.skillText:SetPoint("LEFT", row, "LEFT", x.skill + BAR_WIDTH + 6, 0)
    row.skillText:SetWidth(w.skill - BAR_WIDTH - 6)
    row.skillText:SetJustifyH("RIGHT")

    row.readText = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.readText:SetPoint("LEFT", row, "LEFT", x.read, 0)
    row.readText:SetWidth(w.read)
    row.readText:SetJustifyH("LEFT")

    -- DER KNOPF STEHT NUR BEI EINER ITEMSUCHE. Ohne einen bestimmten
    -- Gegenstand gibt es nichts zu erbitten — ein Knopf, der dann nichts
    -- tut, ist schlimmer als keiner.
    row.ask = Widgets.Button(row, L.CRAFT_ASK_BUTTON, function()
        local entry = row.entry
        if not entry then return end
        local ok, grund = GA.Modules.Crafting:Ask(CraftingView.searchItemID, entry.name)
        if not ok then
            GA.Core.Debug:Info("%s", L["CRAFT_ASK_ERR_" .. tostring(grund)])
        end
        CraftingView:Refresh()
    end)
    row.ask:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.ask:Hide()
end

function CraftingView:UpdateCrafterRow(row, entry)
    row.entry = entry

    -- Die Klasse kennt die Berufsliste nicht — die Charakterdatenbank
    -- vielleicht. Bekannt: Wappen und Farbe wie ueberall. Unbekannt: kein
    -- Wappen, Textfarbe. Ein graues Wappen hiesse "keine Klasse".
    local class = self:ClassOf(entry.name)
    if class and Theme.SetClassPortrait(row.crest, class) then
        row.crest:Show()
    else
        row.crest:Hide()
    end

    row.nameText:SetText(entry.name or L.UNKNOWN)
    if class then
        row.nameText:SetTextColor(Util.ClassColor(class))
    else
        row.nameText:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    end

    -- Online ist eine Auskunft des Rosters. Fehlt sie, gibt es keinen Punkt
    -- — ein grauer Punkt hiesse "offline", und das ist etwas anderes als
    -- "weiss nicht".
    local online = self:OnlineOf(entry.name)
    if online == nil then
        row.dot:Hide()
    else
        row.dot:Show()
        Theme.Paint(row.dot, online and Theme.color.good or Theme.color.border)
    end

    row.professionText:SetText(entry.lineName or tostring(entry.line or ""))

    -- Die Fertigkeit: Zahl immer, Balken nur mit bekanntem Hoechstwert.
    -- Ohne Hoechstwert ist "wie voll" keine Frage, die sich beantworten
    -- laesst — also kein Balken, statt einem geratenen.
    local rank, maxRank = tonumber(entry.rank), tonumber(entry.maxRank)
    if rank and rank > 0 then
        row.skillText:SetText(tostring(rank))
        if maxRank and maxRank > 0 then
            local anteil = math.min(1, rank / maxRank)
            row.barFill:SetWidth(math.max(1, math.floor(BAR_WIDTH * anteil)))
            row.barBg:Show() row.barFill:Show()
        else
            row.barBg:Hide() row.barFill:Hide()
        end
    else
        row.skillText:SetText("—")
        row.barBg:Hide() row.barFill:Hide()
    end

    -- DAS ALTER STEHT DABEI, IMMER. Eine Rezeptliste von vor sechs Wochen
    -- ist eine andere Auskunft als eine von heute, und beide sehen ohne
    -- diese Spalte gleich aus.
    row.readText:SetText(entry.ts and Util.TimeAgo(entry.ts) or L.UNKNOWN)

    if self.searchItemID and not (GA.Core.Comm and GA.Core.Comm:IsSelf(entry.name)) then
        row.ask:Show()
    else
        row.ask:Hide()
    end
end

--- Eine Rezeptzeile: Symbol, Name in Qualitaetsfarbe, Art.
function CraftingView:BuildRecipeRow(row)
    local fonts = Theme.Fonts()
    local x, w = columnOffsets(recipeColumns())

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(14) row.icon:SetHeight(14)
    row.icon:SetPoint("LEFT", row, "LEFT", x.icon, 0)

    row.nameText = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.nameText:SetPoint("LEFT", row, "LEFT", x.name, 0)
    row.nameText:SetWidth(w.name)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.kindText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.kindText:SetPoint("LEFT", row, "LEFT", x.kind, 0)
    row.kindText:SetWidth(w.kind)
    row.kindText:SetJustifyH("LEFT")
end

function CraftingView:UpdateRecipeRow(row, entry)
    row.entry = entry

    if entry.itemID then
        local info = Compat.GetItemInfo(entry.itemID)
        zeigeSymbol(row.icon, Compat.GetItemIcon(entry.itemID))

        if info and info.name then
            row.nameText:SetText(info.name)
            local farbe = info.quality and Theme.QualityColor(info.quality)
            if farbe then row.nameText:SetTextColor(farbe[1], farbe[2], farbe[3])
            else row.nameText:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3]) end
        else
            -- NOCH NICHT GELADEN IST NICHT UNBEKANNT. Der Client holt den
            -- Namen nach; bis dahin steht die Kennung da, nicht "unbekannt".
            row.nameText:SetText(string.format(L.SLASH_ITEM_FALLBACK, tostring(entry.itemID)))
            row.nameText:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2],
                Theme.color.textFaint[3])
        end
        row.kindText:SetText(L.CRAFT_TYPE_ITEM)
    else
        -- Ein Rezept ohne Gegenstand: eine Verzauberung. Der Name kommt aus
        -- dem Zauberbuch dieses Clients, nicht aus der Nachricht.
        row.icon:Hide()
        row.nameText:SetText(Compat.GetSpellName(entry.spellID)
            or string.format(L.CRAFT_SPELL_FALLBACK, tostring(entry.spellID)))
        row.nameText:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
        row.kindText:SetText(L.CRAFT_TYPE_ENCHANT)
    end
end

-- ================================================================ Nachschlag --

--- Die Klasse eines Herstellers, wenn die Charakterdatenbank ihn kennt.
--- nil = unbekannt, nicht "keine".
function CraftingView:ClassOf(name)
    local db = GA.Core.Database
    if not name or not db or not db.FindCharacterByName then return nil end
    local ok, character = pcall(db.FindCharacterByName, db, name)
    return ok and character and character.class or nil
end

--- Ist die Person angemeldet? Aus dem Roster, einmal je Auffrischen
--- gesammelt — nicht je Zeile durch alle Mitglieder.
--- @return boolean|nil  nil = nicht im Roster gefunden
function CraftingView:OnlineOf(name)
    if not name or not self.online then return nil end
    return self.online[string.lower(Util.ShortName(name))]
end

function CraftingView:SammleOnline()
    local online = {}
    for index = 1, Compat.GetNumGuildMembers() do
        local member = Compat.GetGuildMember(index)
        if member and member.name then
            online[string.lower(Util.ShortName(member.name))] = member.online and true or false
        end
    end
    self.online = online
end

-- ================================================================== Steuerung -

--- Was im Suchfeld steht, zu einer Gegenstandskennung.
function CraftingView:SetSearch(text)
    text = text and string.gsub(text, "^%s+", "") or ""
    -- Wer sucht, will nicht mehr in der Rezeptliste einer Person stehen.
    self.detail = nil
    if text == "" then
        self.searchItemID, self.searchText = nil, ""
    else
        self.searchText = text
        -- Ein Link, eine Wowhead-Adresse, eine Kennung oder ein Name —
        -- dieselbe Auswertung wie ueberall sonst im Addon.
        self.searchItemID = Compat.ParseItemInput(text)
    end
    self:Refresh()
end

--- Oeffnet die Rezeptliste einer Person.
---
--- SIE WIRD NICHT ABGEFRAGT, SONDERN GEZEIGT. Alles, was hier steht, liegt
--- schon in der Datenbank — verschickt hat es die Person beim Scannen. Ein
--- Klick loest also keine Nachricht aus und kann auch nichts nachladen, was
--- noch nie jemand gemeldet hat.
function CraftingView:ShowRecipes(name, line, lineName)
    if not name or not line then return end
    self.detail = { name = name, line = line, lineName = lineName }
    self:Refresh()
end

--- Die Zeilen fuer die Rezeptliste der gewaehlten Person.
function CraftingView:RecipeRows()
    local Crafting = GA.Modules.Crafting
    local detail = self.detail
    local zeilen = {}

    for _, eintrag in ipairs(Crafting:LinesOf(detail.name)) do
        if eintrag.line == detail.line then
            detail.rank = eintrag.rank
            detail.maxRank = eintrag.maxRank
            detail.ts = eintrag.ts
            detail.link = eintrag.link
            detail.lineName = eintrag.name or detail.lineName

            for _, itemID in ipairs(eintrag.items) do
                -- NACHLADEN ANSTOSSEN, nicht auf den Namen warten. Der
                -- Client holt ihn; bis dahin steht die Kennung in der
                -- Zeile, und beim naechsten Zeichnen der Name.
                Compat.RequestItemData(itemID)
                zeilen[#zeilen + 1] = { recipe = true, itemID = itemID }
            end
            for _, spellID in ipairs(eintrag.spells) do
                zeilen[#zeilen + 1] = { recipe = true, spellID = spellID }
            end
        end
    end

    table.sort(zeilen, function(a, b)
        -- Gegenstaende zuerst, danach die Verzauberungen. Innerhalb nach
        -- Name, damit dieselbe Liste zweimal gleich aussieht.
        local aItem, bItem = a.itemID ~= nil, b.itemID ~= nil
        if aItem ~= bItem then return aItem end
        local an = a.itemID and (Compat.GetItemInfo(a.itemID) or {}).name
            or Compat.GetSpellName(a.spellID)
        local bn = b.itemID and (Compat.GetItemInfo(b.itemID) or {}).name
            or Compat.GetSpellName(b.spellID)
        return tostring(an or a.itemID or a.spellID) < tostring(bn or b.itemID or b.spellID)
    end)

    return zeilen
end

--- Ist das der eigene Charakter?
---
--- NICHT MIT ==. Die Namensquellen dieses Realms sind sich ueber den vollen
--- Namen nicht einig (siehe Util.SameCharacter): Was im Berufsspeicher
--- steht, kann aus einer Nachricht stammen und beide Namensteile tragen,
--- waehrend der Client nur den ersten hergibt.
function CraftingView:IstEigen(name)
    local identity = Compat.GetPlayerIdentity()
    return name ~= nil and identity.name ~= nil
        and Util.SameCharacter(name, identity.name)
end

--- Zeigt den Knopf nur, wenn er auch etwas tun kann — und sagt sonst, woran
--- es liegt.
---
--- EIN AUSGEGRAUTER KNOPF MIT GRUND ist besser als ein fehlender: "Wo ist der
--- Knopf?" ist eine Frage, die niemand beantworten kann; "offline" ist eine
--- Antwort.
function CraftingView:UpdateOpenButton()
    local detail = self.detail
    if not detail then self.openButton:Hide() return end

    self.openButton:Show()

    -- DER EIGENE BERUF BRAUCHT KEINEN LINK und keine Rosterabfrage: Das
    -- Fenster kommt aus dem eigenen Client. Ihn zu sperren, weil ein Link
    -- fehlt, war die Sperre, die gemeldet wurde.
    if self:IstEigen(detail.name) then
        self.openButton:SetEnabledState(true)
        return
    end

    if not detail.link then
        self.openButton:SetEnabledState(false, L.CRAFT_OPEN_NOLINK)
        return
    end

    -- Der Link ist eine Abfrage beim Server nach den Daten dieses
    -- Charakters. Ist die Person weg, kommt nichts — und zwar wortlos.
    -- nil heisst "nicht im Roster gefunden" — kein Grund, den Knopf zu
    -- sperren. Weiss nicht ist nicht nein.
    if self:OnlineOf(detail.name) == false then
        self.openButton:SetEnabledState(false, L.CRAFT_OPEN_OFFLINE)
    else
        self.openButton:SetEnabledState(true)
    end
end

--- Der Kopf der rechten Flaeche: Symbol, Titel, Zeile, Kennzahl.
function CraftingView:SetHeader(icon, title, titleColor, meta, value, unit)
    if icon == false then
        self.tileIcon:Hide()
    elseif type(icon) == "string" and icon:sub(1, 6) == "class:" then
        -- Ein Klassenwappen statt eines Symbols.
        if Theme.SetClassPortrait(self.tileIcon, icon:sub(7)) then
            self.tileIcon:Show()
        else
            self.tileIcon:Hide()
        end
    else
        zeigeSymbol(self.tileIcon, icon)
    end

    self.title:SetText(title or "")
    local farbe = titleColor or Theme.color.goldBright
    self.title:SetTextColor(farbe[1], farbe[2], farbe[3])
    self.meta:SetText(meta or "")
    self.bigValue:SetText(value ~= nil and tostring(value) or "—")
    self.bigLabel:SetText(unit or "")
end

--- Wie viele verschiedene Leute stehen in diesen Berufen?
local function verschiedeneHersteller(berufe)
    local gesehen, zahl = {}, 0
    for _, beruf in ipairs(berufe) do
        for _, crafter in ipairs(beruf.crafters) do
            local key = string.lower(crafter.name or "")
            if not gesehen[key] then
                gesehen[key] = true
                zahl = zahl + 1
            end
        end
    end
    return zahl
end

function CraftingView:Refresh()
    local Crafting = GA.Modules.Crafting
    if not Crafting or not self.frame then return end

    self:SammleOnline()

    local berufe = Crafting:Professions()
    self.professionList:SetData(berufe)

    local charaktere, _, rezepteGesamt = Crafting:Stats()
    self.status:SetText(charaktere > 0
        and string.format(L.CRAFT_KNOWN, charaktere, rezepteGesamt)
        or L.CRAFT_EMPTY)
    GA.UI.MainFrame:SetContext(string.format(L.CRAFT_CONTEXT, #berufe))

    -- ---------------------------------------------------- Eine Person ------
    if self.detail then
        local zeilen = self:RecipeRows()
        local detail = self.detail
        self.backButton:Show()
        self:UpdateOpenButton()

        local class = self:ClassOf(detail.name)
        local fertigkeit = detail.rank and tostring(detail.rank) or "—"
        if detail.rank and detail.maxRank and detail.maxRank > 0 then
            fertigkeit = string.format("%d/%d", detail.rank, detail.maxRank)
        end
        local farbe
        if class then
            local r, g, b = Util.ClassColor(class)
            farbe = { r, g, b }
        end
        self:SetHeader(class and ("class:" .. class) or false,
            detail.name, farbe,
            string.format(L.CRAFT_META_PERSON,
                tostring(detail.lineName or detail.line), fertigkeit,
                detail.ts and Util.TimeAgo(detail.ts) or L.UNKNOWN),
            #zeilen, L.CRAFT_UNIT_RECIPES)

        self.recipes:SetData(zeilen)
        self.crafters:Hide()
        self.recipes:Show()
        return
    end

    self.backButton:Hide()
    self.openButton:Hide()
    self.recipes:Hide()
    self.crafters:Show()

    local zeilen = {}

    -- ---------------------------------------------------- Ein Gegenstand ---
    if self.searchItemID then
        zeilen = Crafting:Crafters(self.searchItemID)
        local info = Compat.GetItemInfo(self.searchItemID)
        local was = (info and info.name)
            or string.format(L.SLASH_ITEM_FALLBACK, tostring(self.searchItemID))
        local farbe = info and info.quality and Theme.QualityColor(info.quality)
        self:SetHeader(Compat.GetItemIcon(self.searchItemID), was, farbe,
            #zeilen > 0 and string.format(L.CRAFT_FOUND, #zeilen, was)
                or string.format(L.CRAFT_NOBODY, was),
            #zeilen, L.CRAFT_UNIT_CANMAKE)

    -- ---------------------------------------------------- Kein Gegenstand --
    elseif self.searchText and self.searchText ~= "" then
        -- Etwas eingetippt, aber kein Gegenstand daraus geworden.
        self:SetHeader(false, self.searchText, Theme.color.textDim,
            string.format(L.CRAFT_NO_ITEM, self.searchText), nil, "")

    -- ---------------------------------------------------- Beruf / alle -----
    else
        local gewaehlt
        for _, beruf in ipairs(berufe) do
            if not self.selectedLine or self.selectedLine == beruf.line then
                if self.selectedLine then gewaehlt = beruf end
                for _, crafter in ipairs(beruf.crafters) do
                    zeilen[#zeilen + 1] = {
                        name = crafter.name,
                        line = beruf.line, lineName = beruf.name,
                        rank = crafter.rank, maxRank = crafter.maxRank,
                        ts = crafter.ts, recipes = crafter.recipes,
                    }
                end
            end
        end

        local rezepte = 0
        for _, zeile in ipairs(zeilen) do rezepte = rezepte + (zeile.recipes or 0) end

        if gewaehlt then
            self:SetHeader(Compat.GetProfessionIcon(gewaehlt.line),
                gewaehlt.name or tostring(gewaehlt.line), nil,
                string.format(L.CRAFT_META_PROFESSION, #zeilen, rezepte),
                #zeilen, L.CRAFT_UNIT_CRAFTERS)
        else
            -- Nichts gewaehlt: das Addon-Zeichen, wie im Fensterportrait.
            local logo = "Interface\\AddOns\\GuildArmory\\Media\\Logo.tga"
            self:SetHeader(Theme.TextureExists(logo) and logo or false,
                L.CRAFT_WHO, nil,
                string.format(L.CRAFT_META_ALL, #berufe, verschiedeneHersteller(berufe), rezepte),
                verschiedeneHersteller(berufe), L.CRAFT_UNIT_CRAFTERS)
        end
    end

    self.crafters:SetData(zeilen)
end

GA.UI.MainFrame:RegisterView("crafting", CraftingView)
