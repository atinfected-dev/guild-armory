--[[----------------------------------------------------------------------------
    Views/Crafting — wer in der Gilde kann das herstellen?

    Links die Berufe, rechts die Antwort. Die rechte Liste zeigt ZWEIERLEI,
    je nachdem, was im Suchfeld steht:

        leer      alle, die den links gewaehlten Beruf koennen
        gefuellt  alle, die diesen einen Gegenstand herstellen koennen

    Ein zweites Fenster dafuer waere eine Verdopplung von etwas, das dieselbe
    Frage in zwei Richtungen ist.

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

    self.hint = Theme.Label(result.content, "", fonts.small, Theme.color.textFaint)
    self.hint:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 2, -4)
    self.hint:SetPoint("RIGHT", result.content, "RIGHT", 0, 0)
    self.hint:SetJustifyH("LEFT")

    self.list = Widgets.ScrollList(result.content, {
        rowHeight = 24,
        createRow = function(row) self:BuildRow(row, fonts) end,
        updateRow = function(row, entry) self:UpdateRow(row, entry) end,
    })
    self.list:SetPoint("TOPLEFT", self.hint, "BOTTOMLEFT", -2, -6)
    self.list:SetPoint("BOTTOMRIGHT", result.content, "BOTTOMRIGHT", 0, 0)

    GA.Core.Callbacks:On("CRAFTING_CHANGED", function()
        if frame:IsShown() then CraftingView:Refresh() end
    end, "CraftingView")

    return frame
end

function CraftingView:BuildRow(row, fonts)
    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
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
    row.name:SetText(entry.name or L.UNKNOWN)

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

--- Was im Suchfeld steht, zu einer Gegenstandskennung.
function CraftingView:SetSearch(text)
    text = text and string.gsub(text, "^%s+", "") or ""
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

function CraftingView:Refresh()
    local Crafting = GA.Modules.Crafting
    if not Crafting or not self.frame then return end

    local berufe = Crafting:Professions()
    self.professionList:SetData(berufe)

    local zeilen = {}

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
