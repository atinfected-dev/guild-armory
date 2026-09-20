--[[----------------------------------------------------------------------------
    Widgets/Dropdown — eigenes Auswahlfeld.

    Warum nicht UIDropDownMenu: Das Blizzard-Framework ist in Umbau, sieht nach
    Standard-WoW aus und liesse sich nicht in den Gilden-Look bringen. Vor allem
    aber steht die Zielplattform noch nicht fest, und eine fehlende Vorlage wirft
    beim Erzeugen (docs/ARCHITECTURE.md, 4.8).

    Es gibt genau EINE Popup-Liste fuer das ganze Addon. Sie wird beim Oeffnen an
    das aufrufende Feld gehaengt. Das spart nicht nur Frames — es loest auch das
    Problem, dass zwei offene Listen uebereinander liegen koennen.
------------------------------------------------------------------------------]]

local _, GA = ...

local Widgets = GA.UI.Widgets or {}
GA.UI.Widgets = Widgets

local Theme = GA.UI.Theme

local MAX_VISIBLE = 12

-- ----------------------------------------------------------- Gemeinsames Popup

local popup

local function buildPopup()
    if popup then return popup end

    popup = CreateFrame("Frame", "GuildArmoryDropdownList", UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetToplevel(true)
    popup:EnableMouse(true)
    popup:Hide()

    Theme.Fill(popup, Theme.color.panelBg)
    Theme.Outline(popup, Theme.color.goldDim)

    popup.items = {}

    -- Klick ausserhalb schliesst. Ein unsichtbarer Fänger hinter dem Popup ist
    -- zuverlaessiger als OnLeave, das bei schnellen Mausbewegungen aussetzt.
    local catcher = CreateFrame("Button", nil, popup)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameLevel(math.max(0, popup:GetFrameLevel() - 1))
    catcher:SetScript("OnClick", function() popup:Hide() end)
    popup.catcher = catcher

    popup:SetScript("OnHide", function(self)
        if self.owner then self.owner:SetOpen(false) end
        self.owner = nil
    end)

    return popup
end

--- Erzeugt oder recycelt eine Zeile im Popup.
local function getItem(index)
    local item = popup.items[index]
    if item then return item end

    local fonts = Theme.Fonts()

    item = CreateFrame("Button", nil, popup)
    item:SetHeight(18)
    item:SetPoint("LEFT", popup, "LEFT", 1, 0)
    item:SetPoint("RIGHT", popup, "RIGHT", -1, 0)
    item:SetPoint("TOP", popup, "TOP", 0, -(1 + (index - 1) * 18))

    item.background = Theme.Fill(item, { 0, 0, 0, 0 })
    item.label = Theme.Label(item, "", fonts.row, Theme.color.text)
    item.label:SetPoint("LEFT", item, "LEFT", 8, 0)
    item.label:SetPoint("RIGHT", item, "RIGHT", -8, 0)
    item.label:SetJustifyH("LEFT")

    item:SetScript("OnEnter", function(self)
        Theme.Paint(self.background, Theme.color.rowHover)
    end)
    item:SetScript("OnLeave", function(self)
        Theme.Paint(self.background, { 0, 0, 0, 0 })
    end)

    popup.items[index] = item
    return item
end

-- --------------------------------------------------------------- Dropdown ----

--- @param parent Frame
--- @param options table
---   width       number
---   placeholder string|nil
---   getOptions  function() -> { { text, value, color, indent }, ... }
---   onSelect    function(value, option)
function Widgets.Dropdown(parent, options)
    local fonts = Theme.Fonts()

    local dropdown = CreateFrame("Button", nil, parent)
    dropdown:SetHeight(18)
    dropdown:SetWidth(options.width or 140)

    local background = Theme.Fill(dropdown, Theme.color.rowAltBg)
    local lines = Theme.Outline(dropdown, Theme.color.border)

    local label = Theme.Label(dropdown, options.placeholder or "—", fonts.row, Theme.color.textFaint)
    label:SetPoint("LEFT", dropdown, "LEFT", 7, 0)
    label:SetPoint("RIGHT", dropdown, "RIGHT", -16, 0)
    label:SetJustifyH("LEFT")

    -- Pfeil nach unten, aus zwei Strichen statt einer Textur.
    local arrow = Theme.Label(dropdown, "v", fonts.small, Theme.color.goldDim)
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)

    dropdown.placeholder = options.placeholder or "—"
    dropdown.open = false

    function dropdown:SetOpen(open)
        self.open = open and true or false
        for _, line in ipairs(lines) do
            Theme.Paint(line, self.open and Theme.color.goldDim or Theme.color.border)
        end
    end

    --- Setzt die Anzeige, ohne onSelect auszuloesen.
    --- @param text string|nil
    --- @param color table|nil
    function dropdown:SetDisplay(text, color)
        if text and text ~= "" then
            label:SetText(text)
            local c = color or Theme.color.text
            label:SetTextColor(c[1], c[2], c[3])
        else
            label:SetText(self.placeholder)
            label:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2],
                Theme.color.textFaint[3])
        end
    end

    dropdown:SetScript("OnEnter", function(self)
        Theme.Paint(background, Theme.color.rowHover)
    end)
    dropdown:SetScript("OnLeave", function(self)
        Theme.Paint(background, Theme.color.rowAltBg)
    end)

    dropdown:SetScript("OnClick", function(self)
        buildPopup()

        -- Zweiter Klick auf dasselbe Feld schliesst.
        if popup:IsShown() and popup.owner == self then
            popup:Hide()
            return
        end

        local entries = options.getOptions and options.getOptions() or {}
        if #entries == 0 then
            entries = { { text = "Keine Auswahl verfuegbar", disabled = true } }
        end

        local shown = math.min(#entries, MAX_VISIBLE)

        for index = 1, math.max(#popup.items, shown) do
            local item = popup.items[index]
            if index <= shown then
                item = getItem(index)
                local entry = entries[index]

                item.label:SetText((entry.indent and "   " or "") .. (entry.text or ""))
                local color = entry.color or
                    (entry.disabled and Theme.color.textFaint or Theme.color.text)
                item.label:SetTextColor(color[1], color[2], color[3])

                item:SetScript("OnClick", function()
                    popup:Hide()
                    if not entry.disabled and options.onSelect then
                        options.onSelect(entry.value, entry)
                    end
                end)
                item:Show()
            elseif item then
                item:Hide()
            end
        end

        popup:SetWidth(math.max(self:GetWidth(), options.popupWidth or 0))
        popup:SetHeight(shown * 18 + 2)
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -1)
        popup.owner = self
        popup:Show()

        self:SetOpen(true)

        if #entries > MAX_VISIBLE then
            GA.Core.Debug:Print("ui", "Dropdown zeigt %d von %d Eintraegen",
                MAX_VISIBLE, #entries)
        end
    end)

    dropdown:SetDisplay(nil)
    return dropdown
end

--- Baut die Optionsliste aus den bekannten Charakteren — fuer Lootmeister-
--- Auswahl, Main/Twink-Verknuepfung und Wunschlisten. Klassenfarbe, sortiert.
function Widgets.CharacterOptions(includeEmpty)
    local Util = GA.Core.Util
    local entries = {}

    if includeEmpty then
        entries[#entries + 1] = { text = "— frei —", value = false,
                                  color = Theme.color.textFaint }
    end

    for _, character in ipairs(GA.Core.Database:ListCharacters()) do
        local r, g, b = Util.ClassColor(character.class)
        entries[#entries + 1] = {
            text = character.name,
            value = character.guid,
            color = { r, g, b },
            name = character.name,
        }
    end

    return entries
end
