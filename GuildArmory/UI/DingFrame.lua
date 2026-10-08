--[[----------------------------------------------------------------------------
    UI/DingFrame — das Level-Up-Banner.

    Beim eigenen Aufstieg: "LEVEL 31!", der Name in Klassenfarbe, eine
    Zeile zum Schmunzeln, darunter drei Zahlen (XP je Stunde, wie lange das
    Level dauerte, Kills darin) und der Platz im Rennen der Gilde. Im Look
    des Themes. Klick schliesst, sonst verblasst es nach acht Sekunden
    (08.10.2026).

    Dasselbe Banner fuer die Ersten der Gilde auf der Hoechststufe
    (ShowFirst) — der Moment, in dem eine Gilde im Chat steht.

    `/ga ding [stufe]` zeigt eine Vorschau; dabei laesst sich das Banner
    ziehen, die Lage wird gemerkt (ui.ding). Einstellungen › Am Bildschirm
    schaltet es ab.
------------------------------------------------------------------------------]]

local _, GA = ...

local DingFrame = {}
GA.UI.DingFrame = DingFrame

local Theme = GA.UI.Theme
local Compat = GA.Core.Compat
local Config = GA.Core.Config
local Util = GA.Core.Util
local L = GA.L

local WIDTH, HEIGHT = 480, 190
local HOLD = 8
local LINES = 12            -- DING_LINE_1 .. DING_LINE_12

function DingFrame:Create()
    if self.frame then return self.frame end
    local fonts = Theme.Fonts()
    local saved = Config:GetUI("ding") or {}

    local frame = CreateFrame("Frame", "GuildArmoryDing", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if saved.point == "TOPLEFT" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
    Theme.Fill(frame, Theme.color.windowBg)
    Theme.DoubleFrame(frame)

    -- Kopfband im Metall des Looks.
    local look = Theme.Look()
    local band = CreateFrame("Frame", nil, frame)
    band:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    band:SetHeight(66)
    if look then Theme.MetalFill(band, look.header) else Theme.Fill(band, Theme.color.goldDeep) end
    Theme.Edge(band, "BOTTOM", Theme.color.goldDim)
    frame.band = band

    frame.small = Theme.Label(band, "", fonts.heading, Theme.color.goldBright)
    frame.small:SetPoint("TOPLEFT", band, "TOPLEFT", 14, -8)
    frame.big = Theme.Label(band, "", fonts.display, Theme.color.goldBright)
    frame.big:SetPoint("CENTER", band, "CENTER", 0, -4)
    if frame.big.SetShadowOffset then frame.big:SetShadowOffset(2, -2) end

    frame.name = Theme.Label(frame, "", fonts.hero, Theme.color.text)
    frame.name:SetPoint("TOP", band, "BOTTOM", 0, -10)
    frame.line = Theme.Label(frame, "", fonts.body, Theme.color.textDim)
    frame.line:SetPoint("TOP", frame.name, "BOTTOM", 0, -4)
    frame.line:SetWidth(WIDTH - 40)
    frame.line:SetJustifyH("CENTER")

    frame.cols = {}
    for k = 1, 3 do
        local col = CreateFrame("Frame", nil, frame)
        col:SetSize(140, 40)
        col:SetPoint("BOTTOM", frame, "BOTTOM", (k - 2) * 150, 12)
        col.label = Theme.Label(col, "", fonts.small, Theme.color.goldDim)
        col.label:SetPoint("TOP", col, "TOP", 0, 0)
        col.value = Theme.Label(col, "", fonts.big, Theme.color.text)
        col.value:SetPoint("TOP", col.label, "BOTTOM", 0, -3)
        if k > 1 then
            local sep = col:CreateTexture(nil, "ARTWORK")
            sep:SetSize(1, 32)
            sep:SetPoint("LEFT", col, "LEFT", -5, 0)
            Theme.Paint(sep, Theme.color.goldDim)
        end
        frame.cols[k] = col
    end

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) if DingFrame.preview then f:StartMoving() end end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        DingFrame:SavePlacement()
    end)
    frame:SetScript("OnMouseUp", function(f, button)
        if button == "LeftButton" and not DingFrame.preview then f:Hide() end
        if button == "RightButton" then f:Hide() end
    end)
    frame:SetScript("OnUpdate", function(f, elapsed)
        f.age = (f.age or 0) + elapsed
        if f.age < HOLD then
            if f.age < 0.3 then f:SetAlpha(f.age / 0.3) else f:SetAlpha(1) end
            return
        end
        local rest = 1 - (f.age - HOLD) / 1.2
        if rest <= 0 then f:Hide() else f:SetAlpha(rest) end
    end)
    frame:Hide()
    self.frame = frame
    return frame
end

function DingFrame:SavePlacement()
    local frame = self.frame
    if not frame then return end
    local links, oben = frame:GetLeft(), frame:GetTop()
    if not links or not oben then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", links, oben)
    local store = Config:GetUI("ding")
    if store then store.point, store.x, store.y = "TOPLEFT", math.floor(links), math.floor(oben) end
end

--- Eine Zeile zum Level: die runden Stufen haben ihre eigene, sonst eine
--- aus der Liste — nach Stufe gewaehlt, damit dieselbe Stufe dieselbe bekommt.
local function pickLine(level, max)
    if max and level >= max then return L.DING_BIG_MAX end
    local big = L["DING_BIG_" .. tostring(level)]
    if big and big ~= ("DING_BIG_" .. tostring(level)) then return big end
    local index = (level % LINES) + 1
    return L["DING_LINE_" .. index] or ""
end

local function show(frame, preview)
    DingFrame.preview = preview or false
    frame.age = 0
    frame:SetAlpha(0)
    frame:Show()
end

--- Das eigene Banner.
function DingFrame:Show(level, preview)
    if not preview and Config:Get("dingBanner") == false then return false end
    local frame = self:Create()
    local identity = Compat.GetPlayerIdentity()
    level = tonumber(level) or identity.level or 1
    local max = GA.Modules.Race and GA.Modules.Race:MaxLevel() or Compat.GetMaxPlayerLevel() or 60

    frame.small:SetText(string.upper(preview and L.DING_PREVIEW or L.DING_TITLE))
    frame.big:SetText(string.format(L.DING_LEVEL, level))
    frame.name:SetText(Theme.ColorByClass(Util.ShortName(identity.name or "?"), identity.class))
    frame.line:SetText(pickLine(level, max))

    local Leveling = GA.Modules.Leveling
    local snap = Leveling and Leveling:Snapshot("level") or {}
    local history = GA.Core.Database.char and GA.Core.Database.char.leveling and GA.Core.Database.char.leveling.history
    local last = history and history[#history] or nil
    local took = preview and snap.playedLevel or (last and last.seconds) or nil
    local kills = preview and snap.kills or (last and last.kills) or 0
    local fmt = Leveling and Leveling.FormatDuration or tostring
    frame.cols[1].label:SetText(string.upper(L.LB_F_XPH))
    frame.cols[1].value:SetText(snap.xpPerHour and string.format("%d", math.floor(snap.xpPerHour + 0.5)) or "—")
    frame.cols[2].label:SetText(string.upper(preview and L.DING_SO_FAR or L.DING_TOOK))
    frame.cols[2].value:SetText(took and fmt(took) or "—")
    local pos, total = GA.Modules.Race and GA.Modules.Race:MyPosition()
    if pos then
        frame.cols[3].label:SetText(string.upper(L.DING_RACE))
        frame.cols[3].value:SetText(string.format(L.DING_RACE_POS, pos, total))
    else
        frame.cols[3].label:SetText(string.upper(L.LB_F_KILLS))
        frame.cols[3].value:SetText(tostring(kills))
    end
    show(frame, preview)
    return true
end

--- Das Banner fuer einen Ersten der Gilde.
function DingFrame:ShowFirst(name, class, guildFirst)
    if Config:Get("dingBanner") == false then return false end
    local frame = self:Create()
    local max = GA.Modules.Race and GA.Modules.Race:MaxLevel() or 60
    local className = class and (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
    frame.small:SetText(string.upper(L.DING_GUILD))
    frame.big:SetText(guildFirst and string.format(L.DING_FIRST, max) or string.format(L.DING_FIRST_CLASS, className))
    frame.name:SetText(Theme.ColorByClass(Util.ShortName(name or "?"), class))
    frame.line:SetText(guildFirst and string.format(L.DING_FIRST_LINE, max) or string.format(L.DING_FIRST_CLASS_LINE, className, max))
    for k = 1, 3 do frame.cols[k].label:SetText("") frame.cols[k].value:SetText("") end
    frame.cols[2].label:SetText(string.upper(L.DING_GRATS))
    frame.cols[2].value:SetText("/g")
    show(frame, false)
    return true
end

function DingFrame:ResetPlacement()
    local store = Config:GetUI("ding")
    if store then store.point, store.x, store.y = nil, nil, nil end
    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end
end

function DingFrame:OnEnable()
    GA.Core.Events:Register("PLAYER_LEVEL_UP", function(_, level)
        -- Einen Takt warten: Der Levelzaehler archiviert gerade das alte Level.
        Compat.After(0.5, function() DingFrame:Show(tonumber(level), false) end)
    end, "DingFrame")
end
