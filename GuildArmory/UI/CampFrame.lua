--[[----------------------------------------------------------------------------
    UI/CampFrame — die Lagerleiste und die Aufstell-Meldung.

    Zwei Fenster, beide unabhaengig vom Hauptfenster:

      LEISTE    Eine Zeile je Gildenmitglied in der eigenen Zone: Name,
                Lagerfeuer, vier Berufssymbole, Sperrzeit. Verschiebbar, die
                Kopfzeile klappt sie zu.

      MELDUNG   Erscheint, wenn jemand in der Zone ein Lagerfeuer aufstellt.
                Nennt Person, Art und Koordinaten und bietet Kartenpin und
                Weitergabe an die Gruppe an. Verschwindet von selbst.

    KEINE AUSWERTUNG HIER. Was angezeigt wird, entscheidet Camp/Camp.lua; diese
    Datei fragt Camp:Roster() und malt das Ergebnis.

    ===========================================================================
    DREI ZUSTAENDE JE SYMBOL, NICHT ZWEI
    ===========================================================================

    Ein Berufssymbol kann heissen:

        hell         traegt eine Ausbaute, die er auch stellen darf
        halb matt    hat sie dabei, aber die Fertigkeit reicht nicht
        sehr matt    hat den Beruf, aber nichts Passendes dabei
        leer         hat den Beruf gar nicht
        Fragezeichen dieser Client weiss nichts ueber die Person

    Der letzte Fall ist der, den man am leichtesten unterschlaegt — und genau
    der, bei dem ein Irrtum teuer ist. Wer das Addon nicht hat, wuerde sonst als
    jemand dastehen, der nichts dabeihat. Man laeuft dann an dem Einzigen
    vorbei, der den Amboss im Beutel hat.

    Ein rotes Kreuz fuer "Beruf nicht gelernt" stand hier einmal im Entwurf.
    Es ist wieder heraus: Die meisten haben zwei der vier Berufe, das waere in
    jeder zweiten Zeile zweimal Alarmfarbe fuer etwas voellig Normales.
------------------------------------------------------------------------------]]

local _, GA = ...

local CampFrame = {}
GA.UI.CampFrame = CampFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local Config = GA.Core.Config
local L = GA.L

local WIDTH = 248
local HEADER = 20
local ROW = 19
local ICON = 15
local NAME_WIDTH = 104

--- So lange bleibt eine Aufstell-Meldung stehen.
local POPUP_SECONDS = 15

--- Abstand zwischen zwei Neuzeichnungen der Uhren.
local TICK = 1

-- ================================================================== Zeiten ---

--- "12:30" aus Restsekunden. Ueber einer Stunde nur volle Minuten — auf die
--- Sekunde genau ist bei einer Stunde Sperrzeit niemandem gedient.
local function clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then
        return string.format("%dh%02d", math.floor(seconds / 3600),
            math.floor((seconds % 3600) / 60))
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function itemName(itemID)
    local info = Compat.GetItemInfo(itemID)
    if info and info.name then return info.name end
    return string.format(L.SLASH_ITEM_FALLBACK, tostring(itemID))
end

-- ================================================================== Leiste ---

--- Ein Berufssymbol in einer Zeile.
local function makeSlot(row, index)
    local button = CreateFrame("Button", nil, row)
    button:SetWidth(ICON)
    button:SetHeight(ICON)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local mark = Theme.Label(button, "", Theme.Fonts().small, Theme.color.textFaint)
    mark:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.mark = mark

    button:SetScript("OnEnter", function(self)
        local slot = self.slot
        if not slot or not _G.GameTooltip then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if slot.empty then
            GameTooltip:SetText(L.CAMP_TT_NOPROF, 1, 1, 1)
        else
            GameTooltip:SetText(string.format("%s — %d",
                L["CAMP_PROF_" .. slot.key] or slot.key, slot.rank or 0), 1, 0.82, 0)
            if not slot.known then
                GameTooltip:AddLine(L.CAMP_TT_UNKNOWN, 0.85, 0.64, 0.25, true)
            else
                for _, entry in ipairs(slot.carried) do
                    local farbe = entry.usable and { 0.30, 0.69, 0.31 }
                        or entry.held and { 0.85, 0.64, 0.25 }
                        or { 0.55, 0.52, 0.45 }
                    local hinweis = entry.held
                        and (entry.usable and L.CAMP_TT_READY or L.CAMP_TT_TOOLOW)
                        or L.CAMP_TT_MISSING
                    GameTooltip:AddDoubleLine(itemName(entry.id), hinweis,
                        0.91, 0.88, 0.81, farbe[1], farbe[2], farbe[3])
                end
            end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", Widgets.HideItemTooltip)

    button:SetPoint("LEFT", row, "LEFT", NAME_WIDTH + ICON + 6 + (index - 1) * (ICON + 2), 0)
    return button
end

local function makeRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 3, -((index - 1) * ROW))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -((index - 1) * ROW))

    -- Nicht `row.background`: Diesen Namen beansprucht Widgets.ScrollList fuer
    -- seine eigenen Zeilen, und zwei Bedeutungen unter einem Namen sind der
    -- Anfang der Verwechslung. Hier ist es bloss der Streifen.
    row.stripe = Theme.Fill(row,
        (index % 2 == 0) and Theme.color.rowAltBg or { 0, 0, 0, 0 })

    row.name = Theme.Label(row, "", Theme.Fonts().row, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetWidth(NAME_WIDTH - 6)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    -- Lagerfeuer: eigenes Symbol, eigener Tooltip. Es ist der Platz, nicht
    -- eine Ausbaute — deshalb steht es vor den Berufen und nicht dazwischen.
    row.fire = CreateFrame("Button", nil, row)
    row.fire:SetWidth(ICON)
    row.fire:SetHeight(ICON)
    row.fire:SetPoint("LEFT", row, "LEFT", NAME_WIDTH, 0)
    row.fireIcon = row.fire:CreateTexture(nil, "ARTWORK")
    row.fireIcon:SetAllPoints(row.fire)
    row.fireIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.fire:SetScript("OnEnter", function(self)
        if self.itemID and self.itemID > 0 then
            Widgets.ShowItemTooltip(self, self.itemID)
        end
    end)
    row.fire:SetScript("OnLeave", Widgets.HideItemTooltip)

    row.slots = {}
    for slot = 1, 4 do row.slots[slot] = makeSlot(row, slot) end

    row.timer = Theme.Label(row, "", Theme.Fonts().small, Theme.color.textDim)
    row.timer:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    return row
end

function CampFrame:Create()
    if self.frame then return self.frame end

    local saved = Config:GetUI("camp") or {}
    local fonts = Theme.Fonts()

    local frame = CreateFrame("Frame", "GuildArmoryCampFrame", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetHeight(HEADER)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetPoint(saved.point or "CENTER", UIParent, saved.point or "CENTER",
        saved.x or -320, saved.y or 220)
    frame:Hide()
    self.frame = frame

    -- ------------------------------------------------------- Kopfzeile ----
    local header = CreateFrame("Button", nil, frame)
    header:SetHeight(HEADER)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    Theme.Fill(header, Theme.color.goldDeep)
    Theme.Outline(header, Theme.color.goldDim)
    self.header = header

    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:RegisterForDrag("LeftButton")
    header:SetMovable(true)
    frame:SetMovable(true)
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint()
        local store = Config:GetUI("camp")
        if store then
            store.point, store.x, store.y = point, math.floor(x), math.floor(y)
        end
    end)
    header:SetScript("OnClick", function(_, button)
        if button == "RightButton" then CampFrame:Hide() return end
        CampFrame:ToggleCollapsed()
    end)

    self.title = Theme.Label(header, L.CAMP_TITLE, fonts.heading, Theme.color.goldBright)
    self.title:SetPoint("LEFT", header, "LEFT", 6, 0)

    self.count = Theme.Label(header, "", fonts.small, Theme.color.gold)
    self.count:SetPoint("RIGHT", header, "RIGHT", -6, 0)

    self.zoneLabel = Theme.Label(header, "", fonts.small, Theme.color.textDim)
    self.zoneLabel:SetPoint("LEFT", self.title, "RIGHT", 6, 0)
    self.zoneLabel:SetPoint("RIGHT", self.count, "LEFT", -6, 0)
    self.zoneLabel:SetJustifyH("LEFT")
    if self.zoneLabel.SetWordWrap then self.zoneLabel:SetWordWrap(false) end

    -- ---------------------------------------------------------- Koerper ---
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    body:SetHeight(1)
    Theme.Fill(body, Theme.color.windowBg)
    Theme.Outline(body, Theme.color.border)
    self.body = body

    self.empty = Theme.Label(body, L.CAMP_ALONE, fonts.small, Theme.color.textFaint)
    self.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -5)

    self.rows = {}

    -- Uhren laufen weiter, auch wenn sich sonst nichts aendert.
    frame:SetScript("OnUpdate", function(_, delta)
        self.since = (self.since or 0) + delta
        if self.since < TICK then return end
        self.since = 0
        self:UpdateClocks()
    end)

    GA.Core.Callbacks:On("CAMP_CHANGED", function() CampFrame:Refresh() end, "CampFrame")
    GA.Core.Callbacks:On("CAMP_PLACED", function(_, info) CampFrame:ShowPlacement(info) end,
        "CampFrame")
    GA.Core.Callbacks:On("CONFIG_CHANGED", function(_, key)
        if key == "campEnabled" then CampFrame:Apply() end
    end, "CampFrame")

    return frame
end

--- Holt eine Zeile aus dem Vorrat oder legt eine an.
function CampFrame:Row(index)
    if not self.rows[index] then
        self.rows[index] = makeRow(self.body, index)
    end
    return self.rows[index]
end

function CampFrame:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local Camp = GA.Modules.Camp
    if not Camp then return end

    local rows, summary = Camp:Roster()
    self.current = rows

    self.zoneLabel:SetText(summary.zone or "")
    self.count:SetText(string.format("%d/%d", summary.ready, summary.total))

    for index, data in ipairs(rows) do
        local row = self:Row(index)
        local r, g, b = Util.ClassColor(data.class)
        row.name:SetText(data.name)
        row.name:SetTextColor(r, g, b)

        row.fire.itemID = data.campfire
        if data.campfire > 0 and data.icon then
            row.fireIcon:SetTexture(data.icon)
            row.fireIcon:SetAlpha(1)
        else
            row.fireIcon:SetTexture(nil)
        end

        for slotIndex = 1, 4 do
            local button = row.slots[slotIndex]
            local slot = data.slots[slotIndex]
            button.slot = slot
            self:PaintSlot(button, slot, data.known)
        end

        row:Show()
    end

    for index = #rows + 1, #self.rows do self.rows[index]:Hide() end

    local hoehe = math.max(#rows * ROW + 6, 18)
    self.empty:SetShown(#rows == 0)
    self.body:SetHeight(self:Collapsed() and 1 or hoehe)
    self.frame:SetHeight(HEADER + (self:Collapsed() and 0 or hoehe))
    self.body:SetShown(not self:Collapsed())

    self:UpdateClocks()
end

--- Die vier Zustaende eines Symbols. Siehe Dateikopf.
function CampFrame:PaintSlot(button, slot, personKnown)
    button.mark:SetText("")

    if not slot or slot.empty then
        -- Beruf nicht gelernt — oder gar nichts ueber die Person bekannt.
        button.icon:SetTexture(nil)
        if not personKnown then
            button.mark:SetText("?")
            button.mark:SetTextColor(0.85, 0.64, 0.25)
        end
        return
    end

    button.icon:SetTexture(slot.icon)

    if not slot.known then
        button.icon:SetAlpha(0.35)
        button.mark:SetText("?")
        button.mark:SetTextColor(0.85, 0.64, 0.25)
    elseif slot.hasUsable then
        button.icon:SetAlpha(1)
    elseif slot.hasItem then
        -- Dabei, aber die Fertigkeit reicht nicht.
        button.icon:SetAlpha(0.55)
    else
        button.icon:SetAlpha(0.25)
    end
end

--- Nur die Uhren, ohne alles neu zu bauen.
function CampFrame:UpdateClocks()
    if not self.current or not self.frame or not self.frame:IsShown() then return end
    if self:Collapsed() then return end

    local jetzt = Compat.Now()
    for index, data in ipairs(self.current) do
        local row = self.rows[index]
        if row then
            if data.cdExpires > jetzt then
                row.timer:SetText(clock(data.cdExpires - jetzt))
                row.timer:SetTextColor(0.55, 0.52, 0.45)
            elseif data.buffExpires > jetzt then
                row.timer:SetText(clock(data.buffExpires - jetzt))
                row.timer:SetTextColor(0.37, 0.79, 0.63)
            else
                row.timer:SetText("")
            end
        end
    end
end

-- ================================================================ Zustand ----

function CampFrame:Collapsed()
    local store = Config:GetUI("camp")
    return store and store.collapsed or false
end

function CampFrame:ToggleCollapsed()
    local store = Config:GetUI("camp")
    if store then store.collapsed = not store.collapsed end
    self:Refresh()
end

function CampFrame:Show()
    self:Create()
    if not self.frame then return end
    local store = Config:GetUI("camp")
    if store then store.hidden = false end
    self.frame:Show()
    self:Refresh()
end

function CampFrame:Hide()
    if not self.frame then return end
    local store = Config:GetUI("camp")
    if store then store.hidden = true end
    self.frame:Hide()
end

function CampFrame:Toggle()
    self:Create()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
    return self.frame and self.frame:IsShown() or false
end

--- Richtet sich nach Einstellung und gemerktem Zustand.
function CampFrame:Apply()
    local Camp = GA.Modules.Camp
    if Camp and not Camp:Enabled() then
        if self.frame then self.frame:Hide() end
        return
    end

    local store = Config:GetUI("camp")
    if store and store.hidden then return end
    self:Show()
end

-- =============================================================== Meldung -----

--- Das Fenster fuer die Aufstell-Meldung. Eines, nicht eines je Meldung:
--- Wer zwei Feuer hintereinander stellt, soll nicht zwei Fenster wegklicken.
function CampFrame:Popup()
    if self.popup then return self.popup end

    local fonts = Theme.Fonts()
    local popup = CreateFrame("Frame", "GuildArmoryCampPopup", UIParent)
    popup:SetWidth(320)
    popup:SetHeight(84)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -180)
    popup:Hide()
    Theme.Fill(popup, Theme.color.windowBg)
    Theme.Outline(popup, Theme.color.goldMid)
    self.popup = popup

    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(28)
    icon:SetHeight(28)
    icon:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    popup.icon = icon

    popup.text = Theme.Label(popup, "", fonts.body, Theme.color.text)
    popup.text:SetPoint("TOPLEFT", popup, "TOPLEFT", 44, -10)
    popup.text:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -10)
    popup.text:SetJustifyH("LEFT")

    popup.where = Theme.Label(popup, "", fonts.small, Theme.color.textDim)
    popup.where:SetPoint("TOPLEFT", popup.text, "BOTTOMLEFT", 0, -3)

    popup.pin = Widgets.Button(popup, L.CAMP_BTN_PIN, function()
        CampFrame:PlacePin()
    end)
    popup.pin:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 8, 8)

    popup.share = Widgets.Button(popup, L.CAMP_BTN_SHARE, function()
        CampFrame:SharePin()
    end)
    popup.share:SetPoint("LEFT", popup.pin, "RIGHT", 6, 0)

    popup.close = Widgets.Button(popup, L.BTN_CLOSE, function() popup:Hide() end)
    popup.close:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -8, 8)

    return popup
end

function CampFrame:ShowPlacement(info)
    if not info or not info.name then return end

    local Camp = GA.Modules.Camp
    if Camp and not Camp:Enabled() then return end

    local popup = self:Popup()
    popup.info = info

    local r, g, b = Util.ClassColor(self:ClassOf(info.name))
    popup.text:SetText(string.format(L.CAMP_PLACED_BY,
        string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), info.name),
        itemName(info.itemID)))
    popup.where:SetText(string.format(L.CAMP_PLACED_AT, info.x * 100, info.y * 100))

    local icon = Compat.GetItemIcon(info.itemID)
    if icon then popup.icon:SetTexture(icon) else popup.icon:SetTexture(nil) end

    -- BESCHRIFTUNGEN ZURUECKSETZEN. Nach dem ersten Lagerfeuer stehen hier
    -- "Pin gesetzt" und "Geteilt" — beim zweiten waere das eine Auskunft
    -- ueber das erste, auf einem Knopf, der wieder anklickbar ist.
    popup.pin:SetLabel(L.CAMP_BTN_PIN)
    popup.share:SetLabel(L.CAMP_BTN_SHARE)

    -- BEIDE KNOEPFE SAGEN VORHER, OB SIE KOENNEN. Ein Knopf, der erst beim
    -- Druecken zugibt, dass Wegpunkte auf diesem Client nichts tun, hat
    -- jemanden umsonst hinsehen lassen.
    local koennen = Compat.CanSetWaypoint(info.mapID)
    popup.pin:SetEnabledState(koennen, koennen and nil or L.CAMP_NO_WAYPOINT)
    local gruppe = Compat.IsInGroup() or Compat.IsInRaid()
    popup.share:SetEnabledState(koennen and gruppe,
        (not koennen) and L.CAMP_NO_WAYPOINT or (not gruppe) and L.CAMP_NO_GROUP or nil)

    popup:Show()

    self.popupToken = (self.popupToken or 0) + 1
    local token = self.popupToken
    Compat.After(POPUP_SECONDS, function()
        -- Nur ausblenden, wenn seither keine neue Meldung kam.
        if CampFrame.popupToken == token and CampFrame.popup then
            CampFrame.popup:Hide()
        end
    end)
end

--- Die Klasse zu einem Namen, fuer die Einfaerbung. nil ist in Ordnung.
function CampFrame:ClassOf(name)
    for index = 1, Compat.GetNumGuildMembers() do
        local member = Compat.GetGuildMember(index)
        if member and member.name and Util.ShortName(member.name) == name then
            return member.class
        end
    end
    return nil
end

function CampFrame:PlacePin()
    local info = self.popup and self.popup.info
    if not info then return false end

    if not Compat.SetWaypoint(info.mapID, info.x, info.y) then
        self.popup.pin:SetEnabledState(false, L.CAMP_NO_WAYPOINT)
        return false
    end
    Compat.TrackWaypoint()
    self.popup.pin:SetLabel(L.CAMP_BTN_PINNED)
    self.popup.pin:SetEnabledState(false)
    return true
end

--- Teilt den Wegpunkt mit der Gruppe.
---
--- Der Wegpunkt muss gesetzt sein, bevor es einen Verweis darauf gibt —
--- deshalb erst setzen, dann holen.
function CampFrame:SharePin()
    local info = self.popup and self.popup.info
    if not info then return false end
    if not self:PlacePin() then return false end

    local link = Compat.GetWaypointLink()
    if not link then
        self.popup.share:SetEnabledState(false, L.CAMP_NO_WAYPOINT)
        return false
    end

    local channel = Compat.IsInRaid() and "RAID" or Compat.IsInGroup() and "PARTY"
    if not channel then
        self.popup.share:SetEnabledState(false, L.CAMP_NO_GROUP)
        return false
    end

    if not Compat.SendChatMessage(string.format(L.CAMP_SHARE_LINE,
        info.name, itemName(info.itemID), link), channel) then
        return false
    end

    self.popup.share:SetLabel(L.CAMP_BTN_SHARED)
    self.popup.share:SetEnabledState(false)
    return true
end

-- Erst nach ADDON_READY: Vorher steht das Gildenroster nicht und die
-- gemerkte Position noch nicht in der Datenbank.
GA.Core.Callbacks:On("ADDON_READY", function()
    CampFrame:Create()
    CampFrame:Apply()
end, "CampFrame")
