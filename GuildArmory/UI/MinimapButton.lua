--[[----------------------------------------------------------------------------
    UI/MinimapButton — Knopf am Minimap-Rand.

    Linksklick oeffnet und schliesst das Fenster, Rechtsklick springt in die
    Einstellungen, Ziehen verschiebt den Knopf um die Minimap.

    WARUM HANDGEBAUT UND NICHT LibDBIcon: Das Projekt kommt ohne eingebettete
    Bibliotheken aus (siehe README). LibDBIcon waere hier die uebliche Wahl,
    braucht aber LibStub und LibDataBroker mit — drei Fremdbibliotheken fuer
    einen Knopf. Die Geometrie unten ist dieselbe, die LibDBIcon benutzt
    (31x31 Knopf, 53x53 Rahmen, 17x17 Symbol), damit er neben Knoepfen anderer
    Addons nicht aus der Reihe faellt.

    GEMESSEN (Probe 19.09.2026): Interface\Minimap\MiniMap-TrackingBorder laedt
    in Forever. Alles andere hier wird zur Laufzeit ueber Theme.TextureExists
    geprueft, bevor es benutzt wird — fehlt eine Textur, bleibt ein sauberer
    Rueckfall stehen statt eines unsichtbaren Knopfes.

    Die Position wird als WINKEL gespeichert, nicht als x/y. Sonst wandert der
    Knopf quer ueber den Bildschirm, sobald jemand die Minimapgroesse aendert.
------------------------------------------------------------------------------]]

local _, GA = ...

local MinimapButton = {}
GA.UI.MinimapButton = MinimapButton

local Theme = GA.UI.Theme
local Config = GA.Core.Config
local L = GA.L

--- Symbolkandidaten, in dieser Reihenfolge. Der erste, der wirklich laedt,
--- gewinnt — Icon-Pfade sind zwischen den Client-Linien nicht garantiert.
local ICON_CANDIDATES = {
    -- Das eigene Logo zuerst: Es ist das Zeichen, unter dem das Addon auch
    -- auf der Seite steht. Liegt die Datei nicht im Paket, faellt die Liste
    -- auf Blizzards Symbole zurueck — "der erste, der wirklich laedt,
    -- gewinnt" gilt hier genauso.
    --
    -- Es ist der AUSSCHNITT auf das Wappen, nicht das ganze Logo: Der Knopf
    -- ist zwanzig Pixel gross, und die Schrift darin waere ein grauer
    -- Streifen.
    "Interface\\AddOns\\GuildArmory\\Media\\Minimap.tga",
    "Interface\\Icons\\INV_Chest_Plate06",
    "Interface\\Icons\\INV_Shield_06",
    "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\INV_Misc_QuestionMark",
}

local BORDER_TEXTURE     = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND_TEXTURE = "Interface\\Minimap\\UI-Minimap-Background"

--- Abstand zum Minimap-Mittelpunkt. Aus der tatsaechlichen Groesse gerechnet,
--- damit der Knopf auch bei vergroesserter Minimap am Rand sitzt.
local function orbitRadius()
    local width = Minimap and Minimap.GetWidth and Minimap:GetWidth() or 140
    if not width or width <= 0 then width = 140 end
    return (width / 2) + 5
end

local function settings()
    return Config:GetUI("minimap")
end

-- ================================================================== Aufbau ----

function MinimapButton:Create()
    if self.button then return self.button end

    -- Ohne Minimap kein Minimap-Knopf. Kein Fehler, nur nichts zu tun.
    if type(_G.Minimap) ~= "table" or type(Minimap.GetWidth) ~= "function" then
        GA.Core.Debug:Print("ui", "Keine Minimap gefunden — kein Minimap-Knopf.")
        return nil
    end

    local button = CreateFrame("Button", "GuildArmoryMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    self.button = button

    -- Dunkle Scheibe unter dem Symbol, damit es nicht auf der Karte schwimmt.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    if Theme.TextureExists(BACKGROUND_TEXTURE) then
        background:SetTexture(BACKGROUND_TEXTURE)
    else
        Theme.Paint(background, { 0, 0, 0, 0.7 })
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(17)
    icon:SetHeight(17)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local chosen
    for _, path in ipairs(ICON_CANDIDATES) do
        if Theme.TextureExists(path) then chosen = path break end
    end
    if chosen then
        icon:SetTexture(chosen)
    else
        -- Letzter Rueckfall: goldene Flaeche mit Kuerzel. Sichtbar ist besser
        -- als ein leerer Knopf, den niemand findet.
        Theme.Paint(icon, Theme.color.goldDeep)
        local label = Theme.Label(button, "GA", Theme.Fonts().small, Theme.color.goldBright)
        label:SetPoint("CENTER", icon, "CENTER", 0, 0)
    end

    -- Der Rahmen liegt ueber dem Symbol und gibt ihm die runde Form.
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    if Theme.TextureExists(BORDER_TEXTURE) then
        border:SetTexture(BORDER_TEXTURE)
    else
        border:Hide()
        Theme.Outline(button, Theme.color.goldDim)
    end

    local highlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
    if Theme.TextureExists(highlight) then
        button:SetHighlightTexture(highlight)
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            GA.UI.MainFrame:Show()
            GA.UI.MainFrame:ShowView("settings")
        else
            GA.UI.MainFrame:Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self) MinimapButton:ShowTooltip(self) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", MinimapButton.OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    self:UpdatePosition()
    self:ApplyVisibility()
    return button
end

-- ================================================================ Position ----

--- Setzt den Knopf auf den gespeicherten Winkel.
function MinimapButton:UpdatePosition()
    if not self.button then return end

    local angle = math.rad(tonumber(settings().angle) or 200)
    local radius = orbitRadius()

    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

--- Waehrend des Ziehens: Winkel aus der Mauszeigerposition berechnen.
--- math.atan2 gibt es in Lua 5.1; neuere Fassungen kennen nur math.atan mit
--- zwei Parametern. Beide Wege stehen bereit.
function MinimapButton.OnDragUpdate(button)
    if not button.dragging then return end

    local centerX, centerY = Minimap:GetCenter()
    if not centerX then return end

    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale == 0 then scale = 1 end
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local atan2 = math.atan2 or math.atan
    settings().angle = math.deg(atan2(cursorY - centerY, cursorX - centerX))
    MinimapButton:UpdatePosition()
end

-- ============================================================== Sichtbarkeit --

function MinimapButton:ApplyVisibility()
    if not self.button then return end
    if settings().hidden then self.button:Hide() else self.button:Show() end
end

--- @param shown boolean|nil  nil schaltet um
--- @return boolean sichtbar danach
function MinimapButton:SetShown(shown)
    local config = settings()
    if shown == nil then shown = config.hidden end
    config.hidden = not shown and true or false

    if not config.hidden then self:Create() end
    self:ApplyVisibility()
    GA.Core.Callbacks:Fire("CONFIG_CHANGED", "minimapHidden", config.hidden)
    return not config.hidden
end

function MinimapButton:IsShown()
    return self.button ~= nil and self.button:IsShown()
end

-- ================================================================== Tooltip ---

function MinimapButton:ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Guild Armory")

    local stats = GA.Core.Database:Stats()
    GameTooltip:AddLine(string.format(L.MINIMAP_STATS, stats.characters, stats.awards),
        0.66, 0.61, 0.52)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.MINIMAP_LEFT, 0.9, 0.8, 0.5)
    GameTooltip:AddLine(L.MINIMAP_RIGHT, 0.9, 0.8, 0.5)
    GameTooltip:AddLine(L.MINIMAP_DRAG, 0.44, 0.40, 0.33)
    GameTooltip:Show()
end

-- ================================================================== Start ------

-- Erst nach ADDON_READY: Vorher ist die Minimap noch nicht sicher da, und die
-- Datenbank, aus der der Tooltip liest, ebenfalls nicht.
GA.Core.Callbacks:On("ADDON_READY", function()
    MinimapButton:Create()
end, "MinimapButton")
