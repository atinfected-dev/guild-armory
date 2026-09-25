--[[----------------------------------------------------------------------------
    Views/Crafting — wer in der Gilde kann das herstellen?

    Links die Berufe, rechts die Antwort. Die rechte Liste zeigt DREIERLEI,
    immer in demselben Rahmen:

        Suchfeld leer      alle, die den links gewaehlten Beruf koennen
        Suchfeld gefuellt  alle, die diesen einen Gegenstand herstellen
        Person angeklickt  die Rezepte genau dieser Person

    Drei Fenster dafuer waeren eine Verdopplung von etwas, das dieselbe Frage
    aus drei Richtungen ist — und man denkt ohnehin im Kreis: Wer kann das?
    Was kann der sonst noch? Wer kann DAS wiederum? Ein Klick auf ein Rezept
    dreht die Frage deshalb zurueck und sucht nach seinen Herstellern.

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

function CraftingView:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    self.frame = frame

    -- ------------------------------------------------------- Berufe --------
    local professions = Widgets.Panel(frame, L.CRAFT_PROFESSIONS)
    professions:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    professions:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    professions:SetWidth(240)
    self.professionPanel = professions

    self.professionList = Widgets.ScrollList(professions.content, {
        rowHeight = 24,
        createRow = function(row)
            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name:SetWidth(150)
            row.name:SetJustifyH("LEFT")

            row.count = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end,
        updateRow = function(row, entry)
            local gewaehlt = (self.selectedLine == entry.line)
            row.name:SetText(entry.name or tostring(entry.line))
            local color = gewaehlt and Theme.color.goldBright or Theme.color.text
            row.name:SetTextColor(color[1], color[2], color[3])
            row.count:SetText(string.format("%d", #entry.crafters))
        end,
        onClickRow = function(entry)
            -- Nochmal derselbe Beruf hebt die Wahl auf. Ein Filter ohne Weg
            -- zurueck ist eine Sackgasse.
            self.selectedLine = (self.selectedLine == entry.line) and nil or entry.line
            self.detail = nil
            self:Refresh()
        end,
    })
    self.professionList:SetAllPoints(professions.content)

    -- ------------------------------------------------------- Ergebnis ------
    local result = Widgets.Panel(frame, L.CRAFT_WHO)
    result:SetPoint("TOPLEFT", professions, "TOPRIGHT", gap, 0)
    result:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.resultPanel = result

    self.search = Widgets.SearchBox(result.content, L.CRAFT_SEARCH, function(text)
        self:SetSearch(text)
    end)
    self.search:SetPoint("TOPLEFT", result.content, "TOPLEFT", 0, 0)
    self.search:SetPoint("TOPRIGHT", result.content, "TOPRIGHT", 0, 0)

    -- Zurueck aus der Rezeptliste einer Person. Steht nur da, solange es
    -- etwas zurueckzugehen gibt.
    self.backButton = Widgets.Button(result.content, L.CRAFT_BACK, function()
        self.detail = nil
        self:Refresh()
    end)
    self.backButton:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 0, -4)
    self.backButton:Hide()

    -- DAS SPIEL KANN DAS BESSER. Ein Berufe-Link oeffnet Blizzards eigenes
    -- Fenster — mit Kategorien, Reagenzien und allem, was diese Liste nicht
    -- hat. Der Knopf steht trotzdem NEBEN der Liste und nicht an ihrer
    -- Stelle: Der Link ist eine Abfrage beim Server und funktioniert nur,
    -- solange die Person online ist. Die Liste funktioniert auch nachts.
    self.openButton = Widgets.Button(result.content, L.CRAFT_OPEN, function()
        local detail = self.detail
        if not detail or not detail.link then return end
        -- DER GRUND GEHOERT IN DEN CHAT, nicht ins Schweigen. Ein Knopf, der
        -- nichts tut und nichts sagt, ist von aussen nicht aufzuklaeren —
        -- genau so war er gemeldet.
        local ok, grund = Compat.OpenTradeSkillLink(detail.link)
        if not ok then
            GA.Core.Debug:Info("%s (%s)", L.CRAFT_OPEN_FAILED, tostring(grund))
        end
    end, "primary")
    self.openButton:SetPoint("LEFT", self.backButton, "RIGHT", 6, 0)
    self.openButton:Hide()

    self.hint = Theme.Label(result.content, "", fonts.small, Theme.color.textFaint)
    self.hint:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 2, -4)
    self.hint:SetPoint("RIGHT", result.content, "RIGHT", 0, 0)
    self.hint:SetJustifyH("LEFT")

    self.list = Widgets.ScrollList(result.content, {
        rowHeight = 24,
        createRow = function(row) self:BuildRow(row, fonts) end,
        updateRow = function(row, entry) self:UpdateRow(row, entry) end,
        onClickRow = function(entry)
            if entry.recipe then
                -- Ein Rezept anklicken dreht die Frage um: von "was kann
                -- der" zu "wer kann das". Das ist die Schleife, in der man
                -- ohnehin denkt.
                if entry.itemID then
                    -- :Clear(), nicht :SetText(). Beide Fassungen des
                    -- Suchfelds haben Clear; SetText nur die native — der
                    -- gezeichnete Rueckfall ist ein Rahmen um ein EditBox
                    -- und haette hier geworfen.
                    self.search:Clear()
                    self.detail = nil
                    self.searchItemID, self.searchText = entry.itemID, tostring(entry.itemID)
                    self:Refresh()
                end
                return
            end
            -- Eine Person anklicken oeffnet ihre Rezepte.
            self:ShowRecipes(entry.name, entry.line, entry.lineName)
        end,
        onEnterRow = function(row, entry)
            if entry and entry.itemID then
                Widgets.ShowItemTooltip(row, entry.itemID)
            end
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.list:SetPoint("TOPLEFT", self.hint, "BOTTOMLEFT", -2, -6)
    self.list:SetPoint("BOTTOMRIGHT", result.content, "BOTTOMRIGHT", 0, 0)

    GA.Core.Callbacks:On("CRAFTING_CHANGED", function()
        if frame:IsShown() then CraftingView:Refresh() end
    end, "CraftingView")

    return frame
end

function CraftingView:BuildRow(row, fonts)
    -- EINE ZEILENFORM FUER ZWEI LISTEN. Rechts stehen entweder Leute oder
    -- Rezepte; zwei Zeilenbauer in derselben Liste hiessen zwei Vorraete,
    -- die sich beim Umschalten ins Gehege kommen. Das Symbol bleibt bei
    -- Personen einfach leer.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(16)
    row.icon:SetHeight(16)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")

    row.profession = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.profession:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.profession:SetWidth(150)
    row.profession:SetJustifyH("LEFT")

    row.age = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.age:SetPoint("LEFT", row.profession, "RIGHT", 6, 0)
    row.age:SetWidth(110)
    row.age:SetJustifyH("LEFT")

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

function CraftingView:UpdateRow(row, entry)
    row.entry = entry

    if entry.recipe then
        self:UpdateRecipeRow(row, entry)
        return
    end

    row.icon:SetTexture(nil)
    row.name:SetText(entry.name or L.UNKNOWN)
    row.name:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])

    local beruf = entry.lineName or tostring(entry.line or "")
    if entry.rank and entry.rank > 0 then
        beruf = string.format("%s %d", beruf, entry.rank)
    end
    row.profession:SetText(beruf)

    -- DAS ALTER STEHT DABEI, IMMER. Eine Rezeptliste von vor sechs Wochen
    -- ist eine andere Auskunft als eine von heute, und beide sehen ohne
    -- diese Spalte gleich aus.
    row.age:SetText(entry.ts and Util.TimeAgo(entry.ts) or L.UNKNOWN)

    if self.searchItemID and not (GA.Core.Comm and GA.Core.Comm:IsSelf(entry.name)) then
        row.ask:Show()
    else
        row.ask:Hide()
    end
end

--- Eine Zeile in der Rezeptliste einer Person.
function CraftingView:UpdateRecipeRow(row, entry)
    row.ask:Hide()
    row.age:SetText("")

    if entry.itemID then
        local info = Compat.GetItemInfo(entry.itemID)
        local icon = Compat.GetItemIcon(entry.itemID)
        row.icon:SetTexture(icon)

        if info and info.name then
            row.name:SetText(info.name)
            local farbe = info.quality and Theme.QualityColor(info.quality)
            if farbe then row.name:SetTextColor(farbe[1], farbe[2], farbe[3])
            else row.name:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3]) end
        else
            -- NOCH NICHT GELADEN IST NICHT UNBEKANNT. Der Client holt den
            -- Namen nach; bis dahin steht die Kennung da, nicht "unbekannt".
            row.name:SetText(string.format(L.SLASH_ITEM_FALLBACK, tostring(entry.itemID)))
            row.name:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2],
                Theme.color.textFaint[3])
        end
        row.profession:SetText("")
    else
        -- Ein Rezept ohne Gegenstand: eine Verzauberung. Der Name kommt aus
        -- dem Zauberbuch dieses Clients, nicht aus der Nachricht.
        row.icon:SetTexture(nil)
        row.name:SetText(Compat.GetSpellName(entry.spellID)
            or string.format(L.CRAFT_SPELL_FALLBACK, tostring(entry.spellID)))
        row.name:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
        row.profession:SetText(L.CRAFT_ENCHANT)
    end
end

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

    if not detail.link then
        self.openButton:SetEnabledState(false, L.CRAFT_OPEN_NOLINK)
        return
    end

    -- Der Link ist eine Abfrage beim Server nach den Daten dieses
    -- Charakters. Ist die Person weg, kommt nichts — und zwar wortlos.
    local online = nil
    for index = 1, Compat.GetNumGuildMembers() do
        local member = Compat.GetGuildMember(index)
        if member and member.name and Util.ShortName(member.name) == detail.name then
            online = member.online
            break
        end
    end

    if online == false then
        self.openButton:SetEnabledState(false, L.CRAFT_OPEN_OFFLINE)
    else
        -- nil heisst "nicht im Roster gefunden" — kein Grund, den Knopf zu
        -- sperren. Weiss nicht ist nicht nein.
        self.openButton:SetEnabledState(true)
    end
end

function CraftingView:Refresh()
    local Crafting = GA.Modules.Crafting
    if not Crafting or not self.frame then return end

    local berufe = Crafting:Professions()
    self.professionList:SetData(berufe)

    local zeilen = {}

    if self.detail then
        zeilen = self:RecipeRows()
        self.backButton:Show()
        self:UpdateOpenButton()
        -- ClearAllPoints ZUERST: SetPoint fuegt einen Anker hinzu, es
        -- ersetzt keinen. Ohne das sammelt der Hinweis bei jedem Wechsel
        -- zwischen Liste und Rezepten einen weiteren an, bis sie sich
        -- widersprechen.
        self.hint:ClearAllPoints()
        self.hint:SetPoint("TOPLEFT", self.backButton, "BOTTOMLEFT", 2, -4)
        self.hint:SetPoint("RIGHT", self.resultPanel.content, "RIGHT", 0, 0)
        self.hint:SetText(string.format(L.CRAFT_RECIPES_OF,
            self.detail.name,
            tostring(self.detail.lineName or self.detail.line),
            self.detail.rank or 0,
            #zeilen,
            self.detail.ts and Util.TimeAgo(self.detail.ts) or L.UNKNOWN))
        self.list:SetData(zeilen)
        GA.UI.MainFrame:SetContext(string.format(L.CRAFT_CONTEXT, #berufe))
        return
    end

    self.backButton:Hide()
    self.openButton:Hide()
    self.hint:ClearAllPoints()
    self.hint:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 2, -4)
    self.hint:SetPoint("RIGHT", self.resultPanel.content, "RIGHT", 0, 0)

    if self.searchItemID then
        zeilen = Crafting:Crafters(self.searchItemID)
        local info = Compat.GetItemInfo(self.searchItemID)
        local was = (info and info.name)
            or string.format(L.SLASH_ITEM_FALLBACK, tostring(self.searchItemID))
        self.hint:SetText(#zeilen > 0
            and string.format(L.CRAFT_FOUND, #zeilen, was)
            or string.format(L.CRAFT_NOBODY, was))

    elseif self.searchText and self.searchText ~= "" then
        -- Etwas eingetippt, aber kein Gegenstand daraus geworden.
        self.hint:SetText(string.format(L.CRAFT_NO_ITEM, self.searchText))

    else
        for _, beruf in ipairs(berufe) do
            if not self.selectedLine or self.selectedLine == beruf.line then
                for _, crafter in ipairs(beruf.crafters) do
                    zeilen[#zeilen + 1] = {
                        name = crafter.name,
                        line = beruf.line, lineName = beruf.name,
                        rank = crafter.rank, ts = crafter.ts,
                        recipes = crafter.recipes,
                    }
                end
            end
        end

        local charaktere, _, rezepte = Crafting:Stats()
        self.hint:SetText(charaktere > 0
            and string.format(L.CRAFT_KNOWN, charaktere, rezepte)
            or L.CRAFT_EMPTY)
    end

    self.list:SetData(zeilen)
    GA.UI.MainFrame:SetContext(string.format(L.CRAFT_CONTEXT, #berufe))
end

GA.UI.MainFrame:RegisterView("crafting", CraftingView)
