--[[----------------------------------------------------------------------------
    UI/LevelBar — die Levelleiste.

    Eine schmale Leiste im Look des gewaehlten Themes, verschiebbar, wahlweise
    waagerecht (Felder nebeneinander) oder senkrecht (Felder untereinander).
    Jedes Feld laesst sich einzeln ein- und ausschalten (08.10.2026: "die
    einzelnen Sachen wie Gold pro Minute, Kills usw. alles aus- und
    anschaltbar"). Die Zahlen kommen aus Assist/Leveling.

    Ziehen mit gedrueckter Maustaste, solange die Leiste nicht gesperrt ist
    (Einstellungen oder Rechtsklick). Rechtsklick: Menue mit Sperren,
    Ausrichtung, Bereich, Sitzung zuruecksetzen, Einstellungen, ausblenden.
    `/ga levelbar` blendet sie ein und aus.
------------------------------------------------------------------------------]]

local _, GA = ...

local LevelBar = {}
GA.UI.LevelBar = LevelBar

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Compat = GA.Core.Compat
local Config = GA.Core.Config
local L = GA.L

local PAD, GAP = 10, 14          -- Rand, Abstand zwischen zwei Feldern (waagerecht)
local LINE = 16                  -- Zeilenhoehe (senkrecht)
local VWIDTH = 170               -- Breite senkrecht
local XPBAR_W, XPBAR_H = 90, 6
local TICK = 1                   -- Sekunden zwischen zwei Anzeigen

--- Die Felder, in dieser Reihenfolge. default: an oder aus, bis jemand
--- schaltet. scoped: zaehlt im gewaehlten Bereich (Level / Sitzung).
LevelBar.FIELDS = {
    { key = "level",   label = "LB_F_LEVEL",   default = true },
    { key = "xpbar",   label = "LB_F_XPBAR",   default = true },
    { key = "played",  label = "LB_F_PLAYED",  default = true },
    { key = "total",   label = "LB_F_TOTAL",   default = false },
    { key = "session", label = "LB_F_SESSION", default = false },
    { key = "xph",     label = "LB_F_XPH",     default = true },
    { key = "ttl",     label = "LB_F_TTL",     default = true },
    { key = "kills",   label = "LB_F_KILLS",   default = true,  scoped = true },
    { key = "deaths",  label = "LB_F_DEATHS",  default = false, scoped = true },
    { key = "quests",  label = "LB_F_QUESTS",  default = false, scoped = true },
    { key = "gold",    label = "LB_F_GOLD",    default = true,  scoped = true },
    { key = "goldmin", label = "LB_F_GOLDMIN", default = false, scoped = true },
}

function LevelBar.FieldOn(field)
    local value = Config:Get("levelBar_" .. field.key)
    if value == nil then return field.default end
    return value and true or false
end

function LevelBar.Scope()
    return Config:Get("levelBarScope") == "session" and "session" or "level"
end

local function money(copper)
    local T = GA.Modules.Treasury
    if T and T.Money then return T.Money(copper) end
    return string.format("%dg", math.floor((copper or 0) / 10000))
end

-- ================================================================ Aufbau ----

function LevelBar:Create()
    if self.frame then return self.frame end
    local fonts = Theme.Fonts()
    local saved = Config:GetUI("levelbar") or {}

    local frame = CreateFrame("Frame", "GuildArmoryLevelBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetHeight(LINE + PAD)
    frame:SetWidth(VWIDTH)
    if saved.point == "TOPLEFT" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x or 0, saved.y or 0)
    else
        frame:SetPoint(saved.point or "TOP", UIParent, saved.point or "TOP", saved.x or 0, saved.y or -100)
    end

    -- Der Look: Grund und Rand des Themes; ein eigener Look bekommt sein Metall.
    local look = Theme.Look()
    frame.background = Theme.Fill(frame, Theme.color.windowBg)
    if look then Theme.Metal(frame.background, look.header or look.btnSecondary) end
    frame.lines = Theme.Outline(frame, Theme.color.goldDim)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        if Config:Get("levelBarLocked") then return end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        LevelBar:SavePlacement()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then LevelBar:Menu() end
    end)

    frame:SetScript("OnUpdate", function(f, elapsed)
        f.age = (f.age or 0) + elapsed
        if f.age < TICK then return end
        f.age = 0
        LevelBar:Refresh()
    end)

    self.items = {}
    for _, field in ipairs(self.FIELDS) do
        local item = CreateFrame("Frame", nil, frame)
        item:SetHeight(LINE)
        item.label = Theme.Label(item, string.upper(L[field.label] or field.key), fonts.small, Theme.color.goldDim)
        item.label:SetPoint("LEFT", item, "LEFT", 0, 0)
        item.value = Theme.Label(item, "", fonts.rowBold, Theme.color.text)
        item.value:SetPoint("LEFT", item.label, "RIGHT", 5, 0)
        if field.key == "xpbar" then
            item.label:Hide()
            local track = CreateFrame("Frame", nil, item)
            track:SetHeight(XPBAR_H)
            track:SetWidth(XPBAR_W)
            track:SetPoint("LEFT", item, "LEFT", 0, 0)
            Theme.Fill(track, Theme.color.rowAltBg)
            Theme.Outline(track, Theme.color.border)
            item.track = track
            item.rested = track:CreateTexture(nil, "ARTWORK")
            Theme.BarFill(item.rested, Theme.color.info or { 0.3, 0.55, 1 })
            item.rested:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
            item.rested:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
            item.rested:SetWidth(1)
            item.rested:SetAlpha(0.45)
            item.fill = track:CreateTexture(nil, "ARTWORK", nil, 1)
            Theme.BarFill(item.fill, Theme.color.gold)
            item.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
            item.fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
            item.fill:SetWidth(1)
            item.value:ClearAllPoints()
            item.value:SetPoint("LEFT", track, "RIGHT", 5, 0)
        end
        item.field = field
        item:Hide()
        self.items[field.key] = item
    end

    frame:Hide()
    self.frame = frame
    self:ApplyScale()
    return frame
end

function LevelBar:ApplyScale()
    if not self.frame then return end
    local percent = tonumber(Config:Get("levelBarScale")) or 100
    self.frame:SetScale(math.max(0.5, math.min(2, percent / 100)))
end

--- Lage merken — auf TOPLEFT normiert, wie die Lagerleiste.
function LevelBar:SavePlacement()
    local frame = self.frame
    if not frame then return end
    local links, oben = frame:GetLeft(), frame:GetTop()
    if not links or not oben then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", links, oben)
    local store = Config:GetUI("levelbar")
    if store then store.point, store.x, store.y = "TOPLEFT", math.floor(links), math.floor(oben) end
end

function LevelBar:ResetPlacement()
    local store = Config:GetUI("levelbar")
    if store then store.point, store.x, store.y = "TOP", 0, -100 end
    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    end
end

-- ================================================================ Anzeige ---

--- Setzt die Felder: Text, dann Lage — waagerecht in einer Reihe, senkrecht
--- untereinander. Die Leiste waechst mit dem, was an ist.
function LevelBar:Refresh()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local Leveling = GA.Modules.Leveling
    if not Leveling then return end
    local snap = Leveling:Snapshot(self.Scope())
    local vertical = Config:Get("levelBarVertical") and true or false
    local dash = "—"

    local function text(field)
        local k = field.key
        if k == "level" then
            if snap.maxLevel then return string.format("%d", snap.level or 0) end
            return string.format("%d · %.1f%%", snap.level or 0, (snap.pct or 0) * 100)
        elseif k == "xpbar" then
            if snap.maxLevel then return nil end
            return string.format("%.1f%%", (snap.pct or 0) * 100)
        elseif k == "played" then return Leveling.FormatDuration(snap.playedLevel)
        elseif k == "total" then return snap.playedTotal and Leveling.FormatDuration(snap.playedTotal) or dash
        elseif k == "session" then return Leveling.FormatDuration(snap.session)
        elseif k == "xph" then
            if snap.maxLevel then return nil end
            return snap.xpPerHour and string.format("%d", math.floor(snap.xpPerHour + 0.5)) or dash
        elseif k == "ttl" then
            if snap.maxLevel then return nil end
            return snap.timeToLevel and Leveling.FormatDuration(snap.timeToLevel) or dash
        elseif k == "kills" then return tostring(snap.kills)
        elseif k == "deaths" then return tostring(snap.deaths)
        elseif k == "quests" then return tostring(snap.quests)
        elseif k == "gold" then return money(snap.gained)
        elseif k == "goldmin" then return money(snap.goldPerMinute)
        end
    end

    local shown = {}
    for _, field in ipairs(self.FIELDS) do
        local item = self.items[field.key]
        local value = self.FieldOn(field) and text(field) or nil
        if value then
            item.value:SetText(value)
            if field.key == "xpbar" then
                local width = math.max(1, (XPBAR_W - 2) * (snap.pct or 0))
                item.fill:SetWidth(width)
                local restedTo = snap.rested and snap.xpMax and snap.xpMax > 0
                    and math.min(1, ((snap.xp or 0) + snap.rested) / snap.xpMax) or 0
                item.rested:SetWidth(math.max(1, (XPBAR_W - 2) * restedTo))
                item.rested:SetShown(restedTo > (snap.pct or 0))
            end
            shown[#shown + 1] = item
        else
            item:Hide()
        end
    end

    -- Lage
    local x, maxWidth = PAD, 0
    for index, item in ipairs(shown) do
        item:ClearAllPoints()
        local width = (item.track and (XPBAR_W + 5) or (item.label:GetStringWidth() + 5)) + item.value:GetStringWidth()
        item:SetWidth(width)
        if vertical then
            item:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD / 2) - (index - 1) * LINE)
            if width > maxWidth then maxWidth = width end
        else
            item:SetPoint("LEFT", frame, "LEFT", x, 0)
            x = x + width + GAP
        end
        item:Show()
    end
    if vertical then
        frame:SetWidth(math.max(VWIDTH, maxWidth + PAD * 2))
        frame:SetHeight(math.max(LINE, #shown * LINE) + PAD)
    else
        frame:SetWidth(math.max(60, x - GAP + PAD))
        frame:SetHeight(LINE + PAD)
    end
    if #shown == 0 then
        frame:SetWidth(120)
        frame:SetHeight(LINE + PAD)
    end
end

-- ================================================================ Menue -----

function LevelBar:Menu()
    local locked = Config:Get("levelBarLocked") and true or false
    local vertical = Config:Get("levelBarVertical") and true or false
    local scope = self.Scope()
    Widgets.ContextMenu(L.LB_TITLE, {
        { text = locked and L.LB_UNLOCK or L.LB_LOCK, func = function()
            Config:Set("levelBarLocked", not locked)
        end },
        { text = vertical and L.LB_HORIZONTAL or L.LB_VERTICAL, func = function()
            Config:Set("levelBarVertical", not vertical)
            LevelBar:Refresh()
        end },
        { text = scope == "level" and L.LB_SCOPE_SESSION or L.LB_SCOPE_LEVEL, func = function()
            Config:Set("levelBarScope", scope == "level" and "session" or "level")
            LevelBar:Refresh()
        end },
        { text = L.LB_RESET_SESSION, func = function()
            GA.Modules.Leveling:ResetSession()
            LevelBar:Refresh()
        end },
        { text = L.LB_SETTINGS, func = function()
            GA.UI.MainFrame:Show()
            GA.UI.MainFrame:ShowView("settings")
            if GA.UI.MainFrame.views.settings.ShowSection then GA.UI.MainFrame.views.settings:ShowSection("onscreen") end
        end },
        { text = L.LB_HIDE, func = function() LevelBar:SetEnabled(false) end },
    })
end

-- ================================================================ Sichtbar --

function LevelBar:Enabled()
    return Config:Get("levelBarEnabled") ~= false
end

function LevelBar:SetEnabled(on)
    Config:Set("levelBarEnabled", on and true or false)
    if on then self:Show() else self:Hide() end
end

function LevelBar:Show()
    self:Create()
    self:ApplyScale()
    self.frame:Show()
    self:Refresh()
end

function LevelBar:Hide()
    if self.frame then self.frame:Hide() end
end

function LevelBar:Toggle()
    if self.frame and self.frame:IsShown() then self:SetEnabled(false) else self:SetEnabled(true) end
end

function LevelBar:OnEnable()
    GA.Core.Callbacks:On("LEVELING_CHANGED", function() LevelBar:Refresh() end, "LevelBar")
    GA.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
        if LevelBar:Enabled() then Compat.After(2, function() LevelBar:Show() end) end
    end, "LevelBar")
end
