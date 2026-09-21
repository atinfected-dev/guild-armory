--[[----------------------------------------------------------------------------
    MainFrame — Huelle: Fensterrahmen, Reiter unten, Werkzeugzeile, Ansichten.

    Seit 19.09.2026 auf Blizzards PortraitFrameTemplate: Metallrahmen mit
    Portraitkreis oben links, Titelleiste, X-Knopf — derselbe Rahmen wie Karte,
    Questlog und Charakterfenster in Forever. Die Ansichten haengen als Reiter
    am unteren Rand (wie "Charakter | Ruf | Waehrung"). Fehlt die Vorlage,
    faellt alles auf den Backdrop-Rahmen mit eigener Kopfzeile zurueck; die
    Ansichten merken davon nichts.

    Ansichtsvertrag:
        view.Create(parent) -> Frame     einmalig
        view.OnShow()                    optional
        view.Refresh()                   optional, nur wenn sichtbar
------------------------------------------------------------------------------]]

local _, GA = ...

local MainFrame = {}
GA.UI.MainFrame = MainFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Config = GA.Core.Config
local L = GA.L

local FRAME_NAME = "GuildArmoryMainFrame"
-- Der Portraitkreis der Vorlage ragt oben links etwa 60px in den Rahmen; die
-- Werkzeugzeile liegt auf seiner Hoehe und beginnt deshalb rechts davon.
local TOOLBAR_HEIGHT = 32
local PORTRAIT_CLEARANCE = 56

--- Reihenfolge der Reiter. `phase` markiert, was es noch nicht gibt.
--- "gear" ist kein Reiter mehr: die Ausruestungskurve wandert in die Armory,
--- bleibt aber ueber /ga gear erreichbar.
local VIEW_ORDER = {
    { key = "dashboard",   label = "NAV_DASHBOARD" },
    { key = "armory",      label = "NAV_ARMORY" },
    { key = "characters",  label = "NAV_CHARACTERS" },
    { key = "lootcouncil", label = "NAV_LOOTCOUNCIL" },
    { key = "loothistory", label = "NAV_LOOTHISTORY" },
    { key = "wishlist",    label = "NAV_WISHLIST" },
    { key = "achievements", label = "NAV_ACHIEVEMENTS" },
    { key = "analytics",   label = "NAV_ANALYTICS" },
    { key = "settings",    label = "NAV_SETTINGS" },
}

local PLACEHOLDER = {
    gear        = "TODO_GEAR",
}

MainFrame.views = {}
MainFrame.tabs = {}
MainFrame.tabIndex = {}
MainFrame.current = nil

function MainFrame:RegisterView(key, view)
    self.views[key] = view
end

-- ================================================================== Aufbau ----

function MainFrame:Create()
    if self.frame then return self.frame end

    local saved = Config:GetUI("main")

    -- Rahmen: Blizzards Portraitfenster, sonst Backdrop.
    local frame = Theme.CreateNative("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
    self.native = frame ~= nil
    if not frame then
        frame = Theme.CreateBackdropFrame(FRAME_NAME, UIParent)
        if not Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid) then
            Theme.DoubleFrame(frame)
        end
    end
    self.frame = frame

    frame:SetWidth(saved.width)
    frame:SetHeight(saved.height)
    frame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
    frame:SetScale(saved.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:Hide()

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        MainFrame:SavePosition()
    end)

    frame:SetResizable(true)
    if not pcall(frame.SetResizeBounds, frame, 860, 540) then
        pcall(frame.SetMinResize, frame, 860, 540)
    end

    local insets
    if self.native then
        self:BuildNativeChrome()
        insets = Theme.PanelInsets()
    else
        self:BuildFallbackHeader()
        insets = { left = 12, right = -12, top = -(Theme.size.headerHeight + 12), bottom = 12 }
    end

    -- Inhalt: Werkzeugzeile oben, darunter die Ansicht.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", insets.left + 4, insets.top - 4)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", insets.right - 4, insets.bottom + 4)
    if not self.native then
        Theme.TexturedFill(content, "Interface\\FrameGeneral\\UI-Background-Rock",
            { 0.42, 0.50, 0.46, 1 })
    end
    self.content = content

    self:BuildToolbar()

    local body = CreateFrame("Frame", nil, content)
    body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -TOOLBAR_HEIGHT)
    body:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    self.body = body

    self:BuildTabs()
    self:BuildResizeGrip()

    if type(_G.UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, FRAME_NAME)
    end

    frame:SetScript("OnSizeChanged", function()
        local view = MainFrame.current and MainFrame.views[MainFrame.current]
        if view and view.Refresh and MainFrame:IsVisible() then view:Refresh() end
    end)
    frame:SetScript("OnShow", function() MainFrame:UpdatePortrait() end)

    self:HookEvents()
    return frame
end

--- Titel, Portrait und X-Knopf der Blizzard-Vorlage.
function MainFrame:BuildNativeChrome()
    local frame = self.frame

    if frame.SetTitle then
        pcall(frame.SetTitle, frame, "Guild Armory")
    else
        local title = Theme.NativeText(frame)
        if title then title:SetText("Guild Armory") end
    end

    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() MainFrame:Hide() end)
    end

    self:UpdatePortrait()
end

--- Portrait des eigenen Charakters im Kreis oben links. Beim Login ist das
--- Modell manchmal noch nicht geladen — deshalb bei jedem Anzeigen erneut.
function MainFrame:UpdatePortrait()
    local frame = self.frame
    if not frame or not self.native then return end

    if frame.SetPortraitToUnit then
        if pcall(frame.SetPortraitToUnit, frame, "player") then return end
    end
    local texture = (frame.PortraitContainer and frame.PortraitContainer.portrait)
        or frame.portrait or frame.Portrait
    if texture then Theme.SetPortrait(texture, "player") end
end

--- Rueckfall ohne Vorlage: eigene Kopfzeile mit Titel und X.
function MainFrame:BuildFallbackHeader()
    local fonts = Theme.Fonts()
    local frame = self.frame

    local inset = 12
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    header:SetHeight(Theme.size.headerHeight)
    Theme.Fill(header, Theme.color.panelBg)
    Theme.Edge(header, "BOTTOM", Theme.color.border)

    local brand = Theme.Label(header, "Guild Armory", fonts.big, Theme.color.gold)
    brand:SetPoint("LEFT", header, "LEFT", 14, 0)
    local tagline = Theme.Label(header, "Forever Edition", fonts.small, Theme.color.textFaint)
    tagline:SetPoint("LEFT", brand, "RIGHT", 8, -1)

    local close = Widgets.Button(header, "X", function() MainFrame:Hide() end)
    close:SetWidth(22)
    close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
end

--- Werkzeugzeile: Ansichtstitel, Kontext, Aktualisieren.
function MainFrame:BuildToolbar()
    local fonts = Theme.Fonts()
    local content = self.content

    local bar = CreateFrame("Frame", nil, content)
    bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    bar:SetHeight(TOOLBAR_HEIGHT)

    self.titleLabel = Theme.Label(bar, "", fonts.big, Theme.color.heading)
    self.titleLabel:SetPoint("LEFT", bar, "LEFT", self.native and PORTRAIT_CLEARANCE or 4, 2)
    if self.titleLabel.SetShadowOffset then self.titleLabel:SetShadowOffset(1, -1) end

    self.contextLabel = Theme.Label(bar, "", fonts.body, Theme.color.textDim)
    self.contextLabel:SetPoint("LEFT", self.titleLabel, "RIGHT", 12, -1)

    local refresh = Widgets.Button(bar, L.BTN_REFRESH, function()
        GA.Modules.Equipment:Capture("manuell")
        GA.Core.Compat.RequestGuildRoster()
    end, "primary")
    refresh:SetPoint("RIGHT", bar, "RIGHT", -2, 2)
    self.refreshButton = refresh
end

--- Reiter am unteren Rand.
function MainFrame:BuildTabs()
    local frame = self.frame
    local previous

    for index, entry in ipairs(VIEW_ORDER) do
        local tab = Widgets.Tab(frame, index, L[entry.label], function()
            MainFrame:ShowView(entry.key)
        end)
        tab.viewKey = entry.key

        if tab.native then
            -- Wie CharacterFrame.xml: erster Reiter unter der linken Ecke,
            -- die weiteren daneben. Die alte Vorlage ueberlappt, die neue nicht.
            local gap = Theme.native.PanelTabButtonTemplate and 3 or -15
            if previous then
                tab:SetPoint("LEFT", previous, "RIGHT", gap, 0)
            else
                tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
            end
        else
            -- Gezeichnete Reiter liegen innen am unteren Rand.
            if previous then
                tab:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else
                tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
                self.body:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", 0, 30)
            end
        end

        self.tabs[index] = tab
        self.tabIndex[entry.key] = index
        previous = tab
    end
end

function MainFrame:BuildResizeGrip()
    local frame = self.frame
    local grip = CreateFrame("Button", nil, frame)
    grip:SetWidth(16) grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    for index = 1, 3 do
        local line = grip:CreateTexture(nil, "OVERLAY")
        Theme.Paint(line, Theme.color.goldDim)
        line:SetWidth(12 - index * 3) line:SetHeight(1)
        line:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, index * 3)
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        MainFrame:SavePosition()
    end)
end

-- ================================================================== Ansichten -

function MainFrame:ShowView(key)
    local view = self.views[key]

    local index = self.tabIndex[key]
    if index then Widgets.SelectTab(self.frame, self.tabs, index) end

    if self.current and self.views[self.current] and self.views[self.current].frame then
        self.views[self.current].frame:Hide()
    end
    if self.placeholder then self.placeholder:Hide() end

    self.current = key
    Config:GetUI("main").lastView = key

    if not view then
        local entry
        for _, candidate in ipairs(VIEW_ORDER) do
            if candidate.key == key then entry = candidate break end
        end
        local label = entry and L[entry.label] or L["NAV_" .. string.upper(key)] or key
        local phase = entry and entry.phase and string.format(L.PHASE_LABEL, entry.phase) or ""
        self.placeholder = Widgets.Placeholder(self.body, phase, label, L[PLACEHOLDER[key] or "TODO_TITLE"])
        self.placeholder:Show()
        self:SetTitle(label, nil)
        return
    end

    if not view.frame then view.frame = view:Create(self.body) end
    view.frame:Show()
    if view.OnShow then view:OnShow() end
    if view.Refresh then view:Refresh() end
    -- Der SCHLUESSEL wird erst hier aufgeloest, nicht beim Laden der Ansicht:
    -- Eine beim Laden kopierte Beschriftung wuesste von der gewaehlten Sprache
    -- nichts (siehe Localization/Locale.lua).
    self:SetTitle(view.titleKey and L[view.titleKey] or view.title or key, view.context)
end

function MainFrame:SetTitle(title, context)
    self.titleLabel:SetText(title or "")
    self.contextLabel:SetText(context or "")
end

function MainFrame:SetContext(text)
    if self.contextLabel then self.contextLabel:SetText(text or "") end
end

-- ================================================================== Sichtbarkeit

function MainFrame:IsVisible() return self.frame and self.frame:IsShown() end

function MainFrame:Show()
    self:Create()
    self.frame:Show()
    self:ShowView(self.current or Config:GetUI("main").lastView or "dashboard")
end

function MainFrame:Hide()
    if self.frame then self:SavePosition() self.frame:Hide() end
end

function MainFrame:Toggle()
    if self:IsVisible() then self:Hide() else self:Show() end
end

function MainFrame:SavePosition()
    if not self.frame then return end
    local saved = Config:GetUI("main")
    local point, _, _, x, y = self.frame:GetPoint()
    saved.point = point or "CENTER"
    saved.x = math.floor((x or 0) + 0.5)
    saved.y = math.floor((y or 0) + 0.5)
    saved.width = math.floor(self.frame:GetWidth() + 0.5)
    saved.height = math.floor(self.frame:GetHeight() + 0.5)
end

function MainFrame:SetScale(scale)
    scale = math.max(0.6, math.min(1.4, tonumber(scale) or 1))
    Config:GetUI("main").scale = scale
    if self.frame then self.frame:SetScale(scale) end
    return scale
end

-- ================================================================== Ereignisse -

function MainFrame:HookEvents()
    local Callbacks = GA.Core.Callbacks
    local function refreshCurrent()
        if not MainFrame:IsVisible() then return end
        local view = MainFrame.views[MainFrame.current]
        if view and view.Refresh then view:Refresh() end
    end
    -- TARGET_CHANGED steht bewusst NICHT in dieser Liste: Zielwechsel kommen im
    -- Raid im Sekundentakt, und ein kompletter Neuaufbau aller Listen dafuer
    -- waere Verschwendung. Die Armory haengt sich selbst daran und aktualisiert
    -- nur ihren Inspect-Knopf.
    for _, event in ipairs({ "EQUIPMENT_UPDATED", "GUILD_UPDATED", "CONFIG_CHANGED",
                             "DATABASE_RESET", "ROLES_CHANGED", "COMPAT_MEASURED",
                             "PLAYERS_CHANGED", "INSPECT_DONE", "INSPECT_FAILED",
                             "AWARD_CREATED", "AWARD_CHANGED", "SESSION_CHANGED",
                             "WISHLIST_CHANGED" }) do
        Callbacks:On(event, refreshCurrent, "MainFrame")
    end
end
