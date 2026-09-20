--[[----------------------------------------------------------------------------
    UI/BidFrame — das Fenster, das beim Spieler aufgeht, wenn eine Lootsession
    startet. Eine Zeile je Gegenstand, ein Knopf je Antwortmoeglichkeit.

    ENTWURFSENTSCHEIDUNG: kein Zwang, keine Zeituhr. Manche Loot-Addons zaehlen
    einen Countdown herunter und werten Schweigen als "Passen". Das erzeugt im
    Raid genau den Streit, den ein LootCouncil vermeiden soll — wer gerade tot
    war oder nachgeladen hat, verliert seine Bewerbung. Hier bleibt das Fenster
    stehen, bis der Spieler antwortet oder der Lootmeister die Session schliesst.

    Das Fenster erscheint nur, wenn wirklich eine Ankuendigung kam. Es baut
    seine Zeilen aus der Ankuendigung, nicht aus einer eigenen Datenbank: Was
    zur Abstimmung steht, entscheidet der Lootmeister.
------------------------------------------------------------------------------]]

local _, GA = ...

local BidFrame = {}
GA.UI.BidFrame = BidFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Compat = GA.Core.Compat
local L = GA.L

local ROW_HEIGHT = 34
local BUTTON_WIDTH = 54
local BUTTON_GAP = 3
local NAME_WIDTH = 150

--- Die Breite richtet sich nach der Zahl der Antworten. Eine feste Breite
--- wuerde bei einem erweiterten Antwortsatz die letzten Knoepfe aus dem
--- Fenster schieben — sichtbar erst dann, wenn eine Gilde ihn erweitert.
local function frameWidth()
    local count = #GA.Modules.Session:Responses()
    return 28 + 24 + 8 + NAME_WIDTH + 6
        + count * BUTTON_WIDTH + math.max(0, count - 1) * BUTTON_GAP
end

-- ================================================================== Aufbau ----

function BidFrame:Create()
    if self.frame then return self.frame end

    local fonts = Theme.Fonts()

    local frame = Theme.CreateNative("Frame", "GuildArmoryBidFrame", UIParent, "PortraitFrameTemplate")
    if not frame then
        frame = Theme.CreateBackdropFrame("GuildArmoryBidFrame", UIParent)
        if not Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid) then
            Theme.DoubleFrame(frame)
        end
    end

    frame:SetWidth(frameWidth())
    frame:SetHeight(160)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    if frame.SetTitle then pcall(frame.SetTitle, frame, L.BID_TITLE) end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() BidFrame:Hide() end)
    end

    self.hint = Theme.Label(frame, L.BID_HINT, fonts.small, Theme.color.textFaint)
    self.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -30)
    self.hint:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    self.hint:SetJustifyH("LEFT")

    self.rows = {}
    self.frame = frame

    if type(_G.UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "GuildArmoryBidFrame")
    end
    return frame
end

--- Eine Zeile: Icon, Name, Antwortknoepfe.
function BidFrame:BuildRow(index)
    if self.rows[index] then return self.rows[index] end

    local fonts = Theme.Fonts()
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -(48 + (index - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", self.frame, "RIGHT", -14, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(24) row.icon:SetHeight(24)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")

    -- Der Itemlink soll sich wie ueberall im Spiel verhalten: Tooltip beim
    -- Darueberfahren, Shift-Klick fuegt ihn in den Chat ein.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink) then GameTooltip:Show() end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.buttons = {}
    local previous
    for _, response in ipairs(GA.Modules.Session:Responses()) do
        local button = Widgets.Button(row, response.short or response.label, function()
            BidFrame:Answer(index, response.key)
        end)
        button:SetHeight(18)
        -- Nach SetText misst sich der Blizzard-Knopf selbst; hier muessen alle
        -- gleich breit bleiben, sonst rutscht die Reihe bei jedem Aufbau anders.
        button:SetWidth(BUTTON_WIDTH)
        button.tooltip = response.label
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", BUTTON_GAP, 0)
        else
            button:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        end
        button.responseKey = response.key
        row.buttons[#row.buttons + 1] = button
        previous = button
    end

    row.answer = Theme.Label(row, "", fonts.body, Theme.color.jade)
    row.answer:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.answer:Hide()

    self.rows[index] = row
    return row
end

-- ================================================================== Anzeigen --

--- @param announcement table { id, host, items = { { awardId, itemID } } }
function BidFrame:Show(announcement)
    if not announcement or not announcement.items or #announcement.items == 0 then return end

    self:Create()
    self.announcement = announcement

    local count = #announcement.items
    self.frame:SetWidth(frameWidth())
    self.frame:SetHeight(58 + count * ROW_HEIGHT + 14)
    self.hint:SetText(string.format(L.BID_FROM, announcement.host or "?"))

    for index, item in ipairs(announcement.items) do
        local row = self:BuildRow(index)
        row.awardId = item.awardId

        -- Den Link baut dieser Client selbst aus der Item-ID. Verschickt wird
        -- nur die Zahl — ein Itemlink ueberlebt den Transport nicht unveraendert.
        local info = Compat.GetItemInfo(item.itemID)
        row.itemLink = info and info.link or nil
        row.name:SetText(info and info.name or ("#" .. tostring(item.itemID)))
        local quality = Theme.QualityColor(info and info.quality)
        row.name:SetTextColor(quality[1], quality[2], quality[3])

        if info and info.icon then
            row.icon:SetTexture(info.icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end

        -- Zurueck auf "noch nicht geantwortet".
        row.answer:Hide()
        for _, button in ipairs(row.buttons) do
            button:Show()
            button:SetEnabledState(true)
        end
        row:Show()
    end

    for index = count + 1, #self.rows do self.rows[index]:Hide() end

    self.frame:Show()
end

function BidFrame:Hide()
    if self.frame then self.frame:Hide() end
    self.announcement = nil
end

-- ================================================================== Antwort ---

function BidFrame:Answer(index, responseKey)
    local row = self.rows[index]
    if not row or not row.awardId or not self.announcement then return end

    local ok, reason = GA.Modules.Session:SendBid(
        self.announcement.id, row.awardId, responseKey)

    if not ok then
        GA.Core.Debug:Warn(L.BID_FAILED, tostring(reason))
        return
    end

    -- Die Knoepfe verschwinden, die Antwort bleibt stehen. Aendern geht ueber
    -- ein erneutes Oeffnen — eine Zeile, die sich unter der Hand umstellen
    -- laesst, fuehrt im Raid zu "ich hatte doch BiS geklickt".
    local response = GA.Modules.Session:ResponseByKey(responseKey)
    for _, button in ipairs(row.buttons) do button:Hide() end
    row.answer:SetText(string.format(L.BID_ANSWERED, response and response.label or responseKey))
    row.answer:Show()

    -- Alles beantwortet? Dann kann das Fenster weg.
    local done = true
    for i = 1, #self.announcement.items do
        local other = self.rows[i]
        if other and other:IsShown() and not other.answer:IsShown() then done = false break end
    end
    if done then Compat.After(1.5, function() BidFrame:Hide() end) end
end
