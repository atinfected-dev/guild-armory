--[[----------------------------------------------------------------------------
    UI/Notifications — die Ablage am Minimap-Knopf.

    Entwurf N2 (28.09.2026). Etwas passiert in der Gilde, waehrend das
    Fenster zu ist: jemand stellt ein Teil zum Handeln ein, jemand sucht
    Leute fuer eine Quest, jemand entzuendet ein Lagerfeuer, jemand meldet
    einen Gildenersten. Drei Dinge dazu:

      DER ZAEHLER am Minimap-Knopf: wie viele ungelesen sind.
      DER STREIFEN unter der Minimap: die neueste Meldung, sechs Sekunden,
                   ohne Knoepfe. Ein Klick darauf oeffnet die Ablage.
      DIE ABLAGE  links neben der Minimap: die letzten Meldungen, neue oben
                   hervorgehoben, je ein Knopf, der das Naheliegende tut.

    NICHTS STAPELT SICH UEBER DER WELT. Wer den Zaehler ignoriert, wird nicht
    wieder gestoert; wer im Kampf ist, bekommt den Streifen erst danach.
    Jede Art laesst sich in den Einstellungen abschalten — dann kommt sie
    weder als Streifen noch in die Ablage.

    DIE ABLAGE MISST NICHTS. Jede Zeile kommt aus einem Ereignis, das ein
    anderes Modul gemeldet hat, und traegt dessen Woerter.
------------------------------------------------------------------------------]]

local _, GA = ...

local Notifications = {}
GA.UI.Notifications = Notifications

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

local LIMIT = 30
local MAX_AGE = 2 * 3600
-- Zehn Sekunden, einmal (Wunsch 29.09.2026): lang genug zum Lesen, und
-- ein Streifen kommt nie zweimal — was danach kommt, steht in der Ablage.
local STRIP_SECONDS = 10
local TRAY_W = 300
local ROW_H = 40

--- Art -> Farbe und Einstellungsschluessel.
Notifications.KINDS = {
    TRADE = { color = "gold", setting = "notifyTradables" },
    QUEST = { color = "warn", setting = "notifyQuesthub" },
    DUNGEON = { color = "gold", setting = "notifyDungeon" },
    CAMP  = { color = "jade", setting = "notifyCamp" },
    ACH   = { color = "epic", setting = "notifyAchievements" },
}
local EPIC = { 0.64, 0.21, 0.93 }

local function kindColor(kind)
    local key = Notifications.KINDS[kind] and Notifications.KINDS[kind].color or "textDim"
    if key == "epic" then return EPIC end
    return Theme.color[key]
end

Notifications.items = {}
Notifications.unread = 0
Notifications.queued = {}

-- ================================================================== Eintraege -

--- Ist diese Art eingeschaltet? Voreinstellung steht in Schema.lua.
function Notifications:Enabled(kind)
    -- Der Hauptschalter zuerst: aus heisst aus, fuer jede Art.
    if GA.Core.Config:Get("notifyEnabled") == false then return false end
    local def = self.KINDS[kind]
    if not def then return false end
    local wert = GA.Core.Config:Get(def.setting)
    if wert == nil then return kind ~= "ACH" end
    return wert and true or false
end

--- Legt eine Meldung ab.
--- @param item table { kind, who, class, text, object, objectColor, sub, action = { label, view } }
function Notifications:Push(item)
    if not item or not self:Enabled(item.kind) then return false end
    item.ts = item.ts or Util.Now()
    item.read = false

    table.insert(self.items, 1, item)
    self:Prune()
    self.unread = self.unread + 1
    self:UpdateBadge()

    -- Im Kampf wartet der Streifen; die Ablage nimmt die Meldung jetzt.
    if Compat.InCombat() then
        self.queued[#self.queued + 1] = item
    else
        self:ShowStrip(item)
    end
    if self.tray and self.tray:IsShown() then self:RefreshTray() end
    return true
end

function Notifications:Prune()
    local grenze = Util.Now() - MAX_AGE
    local behalten = {}
    for _, item in ipairs(self.items) do
        if (item.ts or 0) >= grenze and #behalten < LIMIT then behalten[#behalten + 1] = item end
    end
    self.items = behalten
end

function Notifications:MarkAllRead()
    for _, item in ipairs(self.items) do item.read = true end
    self.unread = 0
    self:UpdateBadge()
end

function Notifications:UpdateBadge()
    local button = GA.UI.MinimapButton
    if button and button.SetBadge then button:SetBadge(self.unread) end
end

--- Der Text einer Meldung: "Wer tut was Objekt".
function Notifications:Line(item)
    local r, g, b = Util.ClassColor(item.class)
    local oc = item.objectColor or Theme.color.text
    return string.format("%s %s %s",
        Util.Colorize(Util.FirstName(item.who or "?"), r, g, b),
        item.text or "",
        Util.Colorize(item.object or "", oc[1], oc[2], oc[3]))
end

-- ================================================================== Streifen --

function Notifications:CreateStrip()
    if self.strip then return self.strip end
    if type(_G.Minimap) ~= "table" then return nil end
    local fonts = Theme.Fonts()

    local strip = CreateFrame("Button", "GuildArmoryNotifyStrip", UIParent)
    strip:SetWidth(Minimap:GetWidth() or 140)
    strip:SetHeight(40)
    strip:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -6)
    strip:SetFrameStrata("MEDIUM")
    -- Grund aus dem Look: auf dem hellen Codex stuende sonst Tinte auf Schwarz.
    Theme.Fill(strip, { Theme.color.windowBg[1], Theme.color.windowBg[2], Theme.color.windowBg[3], 0.94 })
    Theme.Outline(strip, Theme.color.borderLit)

    strip.edge = strip:CreateTexture(nil, "OVERLAY")
    strip.edge:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    strip.edge:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    strip.edge:SetWidth(3)

    strip.kicker = Theme.Label(strip, "", fonts.small, Theme.color.warn)
    strip.kicker:SetPoint("TOPLEFT", strip, "TOPLEFT", 9, -5)

    strip.text = Theme.Label(strip, "", fonts.small, Theme.color.text)
    strip.text:SetPoint("TOPLEFT", strip.kicker, "BOTTOMLEFT", 0, -2)
    strip.text:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
    strip.text:SetJustifyH("LEFT")
    strip.text:SetWordWrap(false)

    strip:SetScript("OnClick", function() Notifications:Open() end)
    strip:Hide()
    self.strip = strip
    return strip
end

function Notifications:ShowStrip(item)
    local strip = self:CreateStrip()
    if not strip then return end
    local farbe = kindColor(item.kind)
    Theme.Paint(strip.edge, farbe)
    strip.kicker:SetText(string.upper(L["NOTIFY_KIND_" .. item.kind] or item.kind))
    strip.kicker:SetTextColor(farbe[1], farbe[2], farbe[3])
    strip.text:SetText(self:Line(item))
    strip:Show()

    self.stripToken = (self.stripToken or 0) + 1
    local token = self.stripToken
    Compat.After(STRIP_SECONDS, function()
        if Notifications.stripToken == token and Notifications.strip then Notifications.strip:Hide() end
    end)
end

--- Nach dem Kampf: das Neueste als Streifen, der Rest ist in der Ablage.
function Notifications:FlushQueue()
    local letzte = self.queued[#self.queued]
    self.queued = {}
    if letzte then self:ShowStrip(letzte) end
end

-- ================================================================== Ablage ----

function Notifications:CreateTray()
    if self.tray then return self.tray end
    if type(_G.Minimap) ~= "table" then return nil end
    local fonts = Theme.Fonts()

    local tray = CreateFrame("Frame", "GuildArmoryNotifyTray", UIParent)
    tray:SetWidth(TRAY_W)
    tray:SetHeight(24 + 5 * ROW_H + 22)
    tray:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -8, 0)
    tray:SetFrameStrata("HIGH")
    tray:SetClampedToScreen(true)
    Theme.Fill(tray, { Theme.color.windowBg[1], Theme.color.windowBg[2], Theme.color.windowBg[3], 0.97 })
    Theme.Outline(tray, Theme.color.borderLit)

    local head = CreateFrame("Frame", nil, tray)
    head:SetHeight(24)
    head:SetPoint("TOPLEFT", tray, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", tray, "TOPRIGHT", 0, 0)
    Theme.Fill(head, Theme.color.rowAltBg)
    Theme.Edge(head, "BOTTOM", Theme.color.border)

    tray.title = Theme.Label(head, "", fonts.heading, Theme.color.heading)
    tray.title:SetPoint("LEFT", head, "LEFT", 10, 0)

    tray.close = Widgets.Button(head, L.NOTIFY_CLOSE, function() Notifications:Close() end)
    tray.close:SetHeight(18)
    tray.close:SetPoint("RIGHT", head, "RIGHT", -6, 0)

    tray.settings = Widgets.Button(head, L.NAV_SETTINGS, function()
        Notifications:Close()
        GA.UI.MainFrame:Show()
        GA.UI.MainFrame:ShowView("settings")
    end)
    tray.settings:SetHeight(18)
    tray.settings:SetPoint("RIGHT", tray.close, "LEFT", -4, 0)

    tray.list = Widgets.ScrollList(tray, {
        rowHeight = ROW_H,
        createRow = function(row)
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.bar:SetWidth(3)

            row.action = Widgets.Button(row, "", function()
                local item = row.item
                if not item or not item.action then return end
                Notifications:Close()
                if item.action.view then
                    GA.UI.MainFrame:Show()
                    GA.UI.MainFrame:ShowView(item.action.view)
                end
                if item.action.fn then item.action.fn(item) end
            end)
            row.action:SetHeight(18)
            row.action:SetPoint("RIGHT", row, "RIGHT", -6, 0)

            row.text = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
            row.text:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row.sub = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -21)
            row.sub:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
            row.sub:SetJustifyH("LEFT")
            row.sub:SetWordWrap(false)
        end,
        updateRow = function(row, item)
            local farbe = kindColor(item.kind)
            Theme.Paint(row.bar, farbe)
            row.text:SetText(Notifications:Line(item))
            if not item.read then Theme.Paint(row.background, Theme.color.rowHover) end
            row.sub:SetText((item.sub and (item.sub .. " · ") or "") .. Util.TimeAgo(item.ts))
            if item.action then
                row.action:SetLabel(item.action.label or "")
                row.action:SetWidth(math.max(60, row.action:GetWidth()))
                row.action:Show()
            else
                row.action:Hide()
            end
        end,
    })
    tray.list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    tray.list:SetPoint("BOTTOMRIGHT", tray, "BOTTOMRIGHT", 0, 22)

    tray.foot = Theme.Label(tray, L.NOTIFY_FOOT, fonts.small, Theme.color.textFaint)
    tray.foot:SetPoint("BOTTOMLEFT", tray, "BOTTOMLEFT", 10, 5)
    tray.foot:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
    tray.foot:SetJustifyH("LEFT")
    tray.foot:SetWordWrap(false)

    tray.empty = Theme.Label(tray, L.NOTIFY_EMPTY, fonts.small, Theme.color.textFaint)
    tray.empty:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 10, -10)
    tray.empty:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
    tray.empty:SetJustifyH("LEFT")
    tray.empty:SetSpacing(2)

    tray:Hide()
    self.tray = tray
    return tray
end

function Notifications:RefreshTray()
    local tray = self:CreateTray()
    if not tray then return end
    self:Prune()
    tray.title:SetText(string.upper(string.format(L.NOTIFY_TITLE, self.unread)))
    tray.list:SetData(self.items)
    tray.empty:SetShown(#self.items == 0)
end

function Notifications:Open()
    local tray = self:CreateTray()
    if not tray then return end
    if self.strip then self.strip:Hide() end
    self:RefreshTray()
    tray:Show()
    -- Gesehen ist gelesen: Der Zaehler faellt beim Oeffnen, nicht beim
    -- Klick auf jede Zeile. Die neuen bleiben in der Liste hervorgehoben,
    -- bis sie beim naechsten Oeffnen alt sind.
    self:MarkAllRead()
end

function Notifications:Close()
    if self.tray then self.tray:Hide() end
    for _, item in ipairs(self.items) do item.read = true end
end

function Notifications:Toggle()
    if self.tray and self.tray:IsShown() then self:Close() else self:Open() end
end

-- ================================================================== Quellen ---

function Notifications:OnEnable()
    local Callbacks = GA.Core.Callbacks

    -- Handelbares: neue Teile eines ANDEREN, gegen das Gemerkte.
    self.seenTrade = {}
    Callbacks:On("TRADABLES_CHANGED", function(guid)
        if not guid then return end
        local Tradables = GA.Modules.Tradables
        for _, entry in ipairs(Tradables and Tradables:All() or {}) do
            if entry.guid == guid and not (GA.Core.Comm and GA.Core.Comm:IsSelf(entry.name)) then
                local neu = {}
                for _, item in ipairs(entry.items) do
                    local key = guid .. ":" .. tostring(item.itemID)
                    if not Notifications.seenTrade[key] then
                        Notifications.seenTrade[key] = true
                        neu[#neu + 1] = item
                    end
                end
                if #neu > 0 and Notifications.primed then
                    local info = Compat.GetItemInfo(neu[1].link or neu[1].itemID)
                    local farbe = info and info.quality and Theme.QualityColor(info.quality)
                    Notifications:Push({
                        kind = "TRADE", who = entry.name, class = nil,
                        text = L.NOTIFY_TRADE, object = info and info.name or ("#" .. tostring(neu[1].itemID)),
                        objectColor = farbe,
                        sub = #neu > 1 and string.format(L.NOTIFY_TRADE_MORE, #neu - 1) or nil,
                        action = { label = L.NOTIFY_ACT_TRADE, view = "dashboard" },
                    })
                end
            end
        end
    end, "Notifications")

    -- Questhub: ein neues Gesuch eines anderen.
    Callbacks:On("QUESTHUB_CHANGED", function(kind, request)
        if kind ~= "new" or not request or request.own then return end
        local eigene = GA.Modules.Questhub:MatchOwn(request.questID)
        Notifications:Push({
            kind = "QUEST", who = request.seeker, class = request.class,
            text = L.NOTIFY_QUEST, object = request.title, objectColor = Theme.color.goldBright,
            sub = (request.zone or "") .. (eigene and (" · " .. L.NOTIFY_QUEST_HAVE) or ""),
            action = { label = L.NOTIFY_ACT_QUEST, view = "questhub" },
        })
    end, "Notifications")

    -- Dungeonhub: ein neuer Lauf eines anderen.
    Callbacks:On("DUNGEONHUB_CHANGED", function(kind, run)
        if kind ~= "new" or not run or run.own then return end
        Notifications:Push({
            kind = "DUNGEON", who = run.leader, class = run.class,
            text = L.NOTIFY_DUNGEON, object = run.dungeon, objectColor = Theme.color.goldBright,
            sub = date("%H:%M", run.at or 0) .. (run.note and run.note ~= "" and (" · " .. run.note) or ""),
            action = { label = L.NOTIFY_ACT_DUNGEON, view = "dungeonhub" },
        })
    end, "Notifications")

    -- Lager: ein Feuer in der eigenen Zone.
    Callbacks:On("CAMP_PLACED", function(feuer)
        if not feuer or not feuer.name then return end
        Notifications:Push({
            kind = "CAMP", who = feuer.name, class = nil,
            text = L.NOTIFY_CAMP, object = feuer.zone or "?",
            sub = L.NOTIFY_CAMP_SUB,
            action = { label = L.NOTIFY_ACT_MAP, fn = function()
                if type(_G.ToggleWorldMap) == "function" then pcall(ToggleWorldMap) end
            end },
        })
    end, "Notifications")

    -- Erfolge: Gildenerste anderer. Aus, bis eingeschaltet.
    Callbacks:On("ACHIEVEMENT_UNLOCKED", function(id, playerId)
        local Achievements = GA.Modules.Achievements
        local entry = Achievements and Achievements:Entry(id)
        if not entry or entry.category ~= "FIRSTS" then return end
        local first = GA.Core.Database.account.guildFirsts and GA.Core.Database.account.guildFirsts[id]
        if not first or not first.name then return end
        if GA.Core.Comm and GA.Core.Comm:IsSelf(first.name) then return end
        Notifications:Push({
            kind = "ACH", who = first.name, class = nil,
            text = L.NOTIFY_ACH, object = "„" .. entry.name .. "“", objectColor = EPIC,
            action = { label = L.NOTIFY_ACT_ACH, view = "achievements" },
        })
    end, "Notifications")

    -- Nach dem Kampf den Streifen nachholen.
    local frame = CreateFrame("Frame")
    if pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED") then
        frame:SetScript("OnEvent", function() Notifications:FlushQueue() end)
    end

    -- DER ANLAUF MELDET NICHTS. Beim Start kommen die Handelsangebote der
    -- ganzen Gilde als Abgleich herein; jedes davon als Meldung waere ein
    -- Feuerwerk aus altem Zeug. Erst was danach kommt, ist neu.
    Compat.After(20, function() Notifications.primed = true end)
end

-- Wie ein Modul gestartet: ueber den Umweg der Modultabelle, damit
-- Events.lua es beim Login mit den anderen einschaltet.
GA.Modules.Notifications = Notifications
