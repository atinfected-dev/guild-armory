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

    -- KEIN PORTRAIT. Die Vorlage bringt einen Charakterkreis oben links
    -- mit; hier stehen Gegenstaende, kein Charakter. Der Ring ist Teil des
    -- Rahmens, nicht des Bildes — Theme.HidePortrait raeumt beides ab.
    Theme.HidePortrait(frame)

    if frame.SetTitle then pcall(frame.SetTitle, frame, L.BID_TITLE) end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() BidFrame:Hide() end)
    end

    self.hint = Theme.Label(frame, L.BID_HINT, fonts.small, Theme.color.textFaint)
    self.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -30)
    self.hint:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    self.hint:SetJustifyH("LEFT")

    -- Die Uhr steht rechts im Kopf, neben dem Hinweis: Dort sucht man
    -- sie, und sie verdeckt keine Zeile.
    self.timer = Theme.Label(frame, "", fonts.small, Theme.color.textFaint)
    self.timer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -30)
    self.timer:SetJustifyH("RIGHT")

    -- Einmal je Sekunde genuegt: Eine Uhr, die dreissigmal in der Sekunde
    -- dieselbe Zahl schreibt, kostet nur Rechenzeit.
    frame:SetScript("OnUpdate", function(self, verstrichen)
        self.seit = (self.seit or 0) + verstrichen
        if self.seit < 0.25 then return end
        self.seit = 0
        BidFrame:UpdateTimer()
    end)

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
        GA.UI.Widgets.ShowItemTooltip(self, self.itemID, self.itemLink)
    end)
    row:SetScript("OnLeave", function() GA.UI.Widgets.HideItemTooltip() end)

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

    -- DREI MOEGLICHE RECHTE SEITEN, alle beim Bauen angelegt und je nach
    -- Verteilart gezeigt.
    --
    -- Sie beim Oeffnen neu zu bauen waere einfacher zu schreiben und
    -- schlechter zu benutzen: Die Knopfbreiten messen sich nach dem Text,
    -- und eine Reihe, die bei jedem Aufbau anders sitzt, laesst einen ins
    -- Leere klicken.
    row.rollButtons = {}
    local vorigerWurf
    for _, tier in ipairs(GA.Data.Schema.RollTiers) do
        local button = Widgets.Button(row, tostring(tier.max), function()
            BidFrame:Roll(index, tier.key)
        end)
        button:SetHeight(18)
        button:SetWidth(BUTTON_WIDTH)
        button.tooltip = tier.label
        if vorigerWurf then
            button:SetPoint("LEFT", vorigerWurf, "RIGHT", BUTTON_GAP, 0)
        else
            button:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        end
        button.tierKey = tier.key
        row.rollButtons[#row.rollButtons + 1] = button
        vorigerWurf = button
    end

    -- DKP: ein Eingabefeld statt Knoepfen.
    --
    -- Knoepfe gingen hier nicht: Der Betrag ist nicht aus einer Handvoll
    -- Moeglichkeiten zu waehlen, sondern eine Zahl zwischen dem
    -- Mindestgebot und dem eigenen Stand. Beides steht daneben, damit
    -- niemand raten muss.
    row.dkpBox = Theme.CreateNative("EditBox", nil, row, "InputBoxTemplate")
    if row.dkpBox then
        row.dkpBox:SetWidth(60)
        row.dkpBox:SetHeight(18)
        row.dkpBox:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.dkpBox:SetAutoFocus(false)
        row.dkpBox:SetNumeric(true)
        row.dkpBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- Beim Tippen die alte Ablehnung wegnehmen: Sie gehoert zum
        -- vorigen Versuch und stuende sonst neben einer Zahl, die sie
        -- gar nicht meint.
        row.dkpBox:SetScript("OnTextChanged", function()
            if row.dkpError then
                row.dkpError = nil
                BidFrame:UpdateDkpRow(index)
            end
        end)
        row.dkpBox:SetScript("OnEnterPressed", function(self)
            BidFrame:Bid(index)
            self:ClearFocus()
        end)
        row.dkpBox:Hide()

        row.dkpButton = Widgets.Button(row, L.BID_DKP_SEND, function()
            BidFrame:Bid(index)
        end)
        row.dkpButton:SetHeight(18)
        row.dkpButton:SetWidth(BUTTON_WIDTH)
        row.dkpButton:SetPoint("LEFT", row.dkpBox, "RIGHT", 4, 0)
        row.dkpButton:Hide()

        -- ZURUECKZIEHEN. Abgebucht ist noch nichts, bezahlt wird erst bei
        -- der Vergabe — hier verschwindet man nur aus der Liste. Und die
        -- Punkte, die das Gebot gebunden hat, sind wieder frei.
        row.dkpCancel = Widgets.Button(row, L.BID_DKP_CANCEL, function()
            BidFrame:CancelBid(index)
        end)
        row.dkpCancel:SetHeight(18)
        row.dkpCancel:SetWidth(BUTTON_WIDTH + 12)
        row.dkpCancel:SetPoint("LEFT", row.dkpButton, "RIGHT", 4, 0)
        row.dkpCancel:Hide()

        -- Was man hat und was mindestens geht. Ohne diese Zeile bietet
        -- jemand ins Leere und erfaehrt erst nach dem Druecken, warum es
        -- nicht ging.
        row.dkpInfo = Theme.Label(row, "", fonts.small, Theme.color.textDim)
        row.dkpInfo:SetPoint("LEFT", row.dkpCancel, "RIGHT", 8, 0)
        row.dkpInfo:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.dkpInfo:SetJustifyH("LEFT")
        row.dkpInfo:Hide()
    end

    -- Wer reserviert hat. Steht STATT der Knoepfe: Ist ein Stueck
    -- reserviert, entscheidet die Reservierung, und ein Gebot daneben waere
    -- ein zweites Verfahren fuer dieselbe Sache.
    row.reserved = Theme.Label(row, "", fonts.small, Theme.color.gold)
    row.reserved:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.reserved:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.reserved:SetJustifyH("LEFT")
    row.reserved:Hide()

    row.answer = Theme.Label(row, "", fonts.body, Theme.color.jade)
    row.answer:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.answer:Hide()

    self.rows[index] = row
    return row
end

-- ================================================================== Anzeigen --

--- @param announcement table { id, host, items = { { awardId, itemID } } }
--- Das Fragezeichen: Platzhalter, solange der Client den Gegenstand nicht
--- kennt. Es haelt den Platz, damit die Zeilen nicht versetzt stehen.
local QUESTION_MARK = [[Interface\Icons\INV_Misc_QuestionMark]]

--- Beschriftet die Zeilen neu, sobald der Server Itemdaten nachliefert.
---
--- WARUM UEBERHAUPT.
---
--- Eine Item-ID allein ist keine Auskunft. Was dieser Client noch nie
--- gesehen hat, liefert bei GetItemInfo nichts — im Gebotsfenster stand
--- dann "#12103", und zwar dauerhaft: Das Fenster wird nur beim Oeffnen
--- gefuellt. Man soll aber nicht auf eine Zahl bieten muessen.
---
--- GET_ITEM_INFO_RECEIVED feuert, sobald die Daten da sind. Der Haken
--- haengt nur, solange das Fenster offen ist und noch etwas fehlt — ein
--- Ereignis, das dauernd mitlaeuft, kostet bei jedem Gegenstand im Spiel
--- Rechenzeit fuer nichts.
function BidFrame:WatchItemInfo()
    if not self.announcement then return end

    -- Fehlt ueberhaupt noch etwas?
    local offen = false
    for _, item in ipairs(self.announcement.items) do
        if not Compat.GetItemInfo(item.itemID) then offen = true break end
    end

    if not offen then
        if self.watcher then self.watcher:UnregisterAllEvents() end
        return
    end

    if not self.watcher then
        self.watcher = CreateFrame("Frame")
        self.watcher:SetScript("OnEvent", function()
            -- Nur neu beschriften, nicht neu aufbauen: Ein Neuaufbau wuerde
            -- eine schon gegebene Antwort wieder verwerfen.
            BidFrame:Relabel()
        end)
    end
    self.watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

--- Schreibt Namen, Farbe und Symbol neu — ohne die Antworten anzufassen.
function BidFrame:Relabel()
    if not self.frame or not self.frame:IsShown() or not self.announcement then return end

    local fehlt = false
    for index, item in ipairs(self.announcement.items) do
        local row = self.rows[index]
        local info = Compat.GetItemInfo(item.itemID)
        if row and info then
            row.itemLink = info.link or row.itemLink
            row.name:SetText(info.name or ("#" .. tostring(item.itemID)))
            local quality = Theme.QualityColor(info.quality)
            row.name:SetTextColor(quality[1], quality[2], quality[3])
            row.icon:SetTexture(info.icon or QUESTION_MARK)
        elseif row then
            fehlt = true
        end
    end

    -- Auch die eigene Wurfzahl nachtragen: Relabel wird gerufen, wenn sie
    -- vom Plündermeister ankommt.
    for index in ipairs(self.announcement.items) do
        self:ShowOwnRoll(index)
    end

    -- Alles da: Der Haken wird abgemeldet, statt bis zum Schliessen
    -- mitzulaufen.
    if not fehlt and self.watcher then self.watcher:UnregisterAllEvents() end
end

--- Zeigt in einer Zeile das, was zur Verteilart passt.
---
--- Drei Faelle, und sie schliessen einander aus:
---
---   reserviert   Die Reservierung entscheidet. Es gibt nichts zu tun,
---                also auch keine Knoepfe — nur die Namen.
---   verrollt     Drei Spannen zur Wahl. Der Klick wuerfelt wirklich.
---   sonst        Die Antworten des Councils wie bisher.
function BidFrame:ApplyMode(row, itemID)
    local Session = GA.Modules.Session
    local SoftRes = GA.Modules.SoftRes
    local mode = Session:Mode()

    local reserviert = {}
    if mode == "SOFTRES" and SoftRes then
        for _, entry in ipairs(SoftRes:For(itemID) or {}) do
            reserviert[#reserviert + 1] = GA.Core.Util.ShortName(entry.name or "?")
        end
    end

    local function zeige(liste, an)
        for _, button in ipairs(liste) do
            if an then button:Show() else button:Hide() end
        end
    end

    local function dkpZeigen(an)
        for _, element in ipairs({ row.dkpBox, row.dkpButton, row.dkpCancel, row.dkpInfo }) do
            if element then
                if an then element:Show() else element:Hide() end
            end
        end
    end

    if mode == "DKP" then
        zeige(row.buttons, false)
        zeige(row.rollButtons, false)
        row.reserved:Hide()
        dkpZeigen(true)

        -- Stand und Mindestgebot daneben: Ohne sie bietet jemand ins Leere
        -- und erfaehrt erst nach dem Druecken, warum es nicht ging.
        -- Die grüne Antwortzeile gehoert hier nicht hin: Sie sitzt an
        -- derselben Stelle wie das Eingabefeld und lag im ersten Anlauf
        -- quer darueber. Bei DKP sagt die Infozeile alles.
        row.answer:Hide()
        self:UpdateDkpRow(index)
        return "dkp"
    end

    dkpZeigen(false)

    if #reserviert > 0 then
        zeige(row.buttons, false)
        zeige(row.rollButtons, false)
        row.reserved:SetText(string.format(GA.L.BID_RESERVED_BY,
            table.concat(reserviert, ", ")))
        row.reserved:Show()
        return "reserved"
    end

    row.reserved:Hide()

    if Session:RollsFor(itemID) then
        zeige(row.buttons, false)
        zeige(row.rollButtons, true)
        return "roll"
    end

    zeige(row.rollButtons, false)
    zeige(row.buttons, true)
    return "bid"
end

--- Schickt das eingetippte DKP-Gebot ab.
function BidFrame:Bid(index)
    local row = self.rows[index]
    if not row or not row.dkpBox or not self.announcement then return end

    local punkte = tonumber(row.dkpBox:GetText())
    local Session = GA.Modules.Session
    local identity = Compat.GetPlayerIdentity()

    local ok, grund
    if Session:Get(self.announcement.id) then
        -- Eigene Sitzung: direkt eintragen, wie bei jedem Gebot.
        ok, grund = Session:RecordDkpBid(self.announcement.id, row.awardId,
            identity.name, punkte, identity.guid)
    else
        if not GA.Core.Comm then return end
        ok = GA.Core.Comm:Send("DBID", { self.announcement.id, row.awardId, punkte })
        grund = not ok and "nocomm" or nil
    end

    if not ok then
        -- DER GRUND STEHT IN DER ZEILE, nicht nur im Chat. Im Raid laufen
        -- dort Kampfmeldungen durch, und das Gebotsfenster liegt darueber
        -- — eine Ablehnung im Chat sieht niemand.
        row.dkpError = GA.L["BID_DKP_ERR_" .. tostring(grund)] or tostring(grund)
        self:UpdateDkpRow(index)
        return
    end

    row.dkpError = nil
    row.dkpBox:ClearFocus()
    row.dkpBox:SetText("")

    -- ALLE Zeilen, nicht nur diese: Ein gebundener Punkt fehlt ueberall
    -- sonst.
    self:RefreshDkpRows()
end

--- Schreibt die Infozeile einer DKP-Zeile neu.
---
--- SIE SAGT ALLES, WAS MAN BRAUCHT: das eigene Gebot auf DIESEN
--- Gegenstand, was danach noch frei ist, und das Mindestgebot. Oder,
--- wenn gerade etwas abgelehnt wurde, den Grund — dort, wo man hinsieht.
---
--- Eine Ablehnung nur im Chat ist im Raid unsichtbar: Dort laufen
--- Kampfmeldungen durch, und das Gebotsfenster liegt darueber.
function BidFrame:UpdateDkpRow(index)
    local row = self.rows[index]
    if not row or not row.dkpInfo or not self.announcement then return end

    local Session = GA.Modules.Session
    local Dkp = GA.Modules.Dkp
    if not Dkp then return end

    if row.dkpError then
        local warn = Theme.color.warn
        row.dkpInfo:SetText(row.dkpError)
        row.dkpInfo:SetTextColor(warn[1], warn[2], warn[3])
        return
    end

    local identity = Compat.GetPlayerIdentity()
    local eigenes = self:OwnDkpBid(row.awardId)
    local frei = Session:AvailableDkp(self.announcement.id, identity.name,
        identity.guid, row.awardId)
    frei = math.max(0, (frei or 0) - (eigenes or 0))

    local dim = Theme.color.textDim
    if eigenes then
        row.dkpInfo:SetText(string.format(GA.L.BID_DKP_STATE,
            eigenes, frei, Dkp:MinBid()))
        local jade = Theme.color.jade
        row.dkpInfo:SetTextColor(jade[1], jade[2], jade[3])
    else
        row.dkpInfo:SetText(string.format(GA.L.BID_DKP_AVAILABLE, frei, Dkp:MinBid()))
        row.dkpInfo:SetTextColor(dim[1], dim[2], dim[3])
    end

    -- Zurueckziehen geht nur, wenn etwas dasteht.
    if row.dkpCancel and row.dkpCancel.SetEnabledState then
        row.dkpCancel:SetEnabledState(eigenes ~= nil)
    end
end

--- Das eigene Gebot auf einen Gegenstand, oder nil.
---
--- Zwei Quellen, wie beim Wurf: Der Plündermeister liest in seiner
--- Sitzung, ein Raidmitglied in dem, was zurueckgemeldet wurde.
function BidFrame:OwnDkpBid(awardId)
    local Session = GA.Modules.Session
    if not self.announcement then return nil end

    local session = Session:Get(self.announcement.id)
    if session then
        local gebote = session.responses[awardId]
        local identity = Compat.GetPlayerIdentity()
        local gebot = gebote and gebote[GA.Core.Util.ShortName(identity.name or "")]
        return gebot and gebot.dkp or nil
    end

    local eigen = Session.myBids and Session.myBids[awardId]
    return eigen or nil
end

--- Wann die Gebotsfrist dieses Fensters ablaeuft, als eigene Uhrzeit.
---
--- ZWEI QUELLEN, WIE UEBERALL HIER. Der Plündermeister hat die Sitzung
--- liegen und liest darin; ein Raidmitglied hat nur die Ankuendigung, und
--- die trug die verbleibenden Sekunden mit.
--- @return number|nil
function BidFrame:Deadline()
    if not self.announcement then return nil end

    local session = GA.Modules.Session:Get(self.announcement.id)
    if session then return session.bidsCloseAt end
    return self.announcement.closeAt
end

--- Laeuft die Frist hier noch?
function BidFrame:TimeLeft()
    local ende = self:Deadline()
    if not ende then return nil end
    return math.max(0, ende - Compat.Now())
end

--- Schreibt die Uhr und sperrt alles, wenn sie abgelaufen ist.
---
--- DIE ANZEIGE IST NICHT DIE ENTSCHEIDUNG. Abgelehnt wird beim
--- Plündermeister, nach SEINER Uhr — zwei Clients haben nie genau
--- dieselbe Zeit, und die letzte Sekunde ist genau die, um die gestritten
--- wird. Diese Uhr sagt nur, woran man ist, und nimmt die Knoepfe weg,
--- bevor jemand in eine Ablehnung hineinlaeuft.
function BidFrame:UpdateTimer()
    if not self.frame or not self.frame:IsShown() then return end

    local rest = self:TimeLeft()
    if not rest then
        if self.timer then self.timer:SetText("") end
        return
    end

    if self.timer then
        if rest > 0 then
            local farbe = rest <= 10 and Theme.color.warn or Theme.color.textFaint
            self.timer:SetText(string.format(GA.L.BID_TIME_LEFT, math.ceil(rest)))
            self.timer:SetTextColor(farbe[1], farbe[2], farbe[3])
        else
            local warn = Theme.color.warn
            self.timer:SetText(GA.L.BID_TIME_UP)
            self.timer:SetTextColor(warn[1], warn[2], warn[3])
        end
    end

    -- Abgelaufen: alles aus. Ein Knopf, der nur noch eine Ablehnung
    -- einbringt, ist schlimmer als keiner.
    if rest <= 0 and not self.expired then
        self.expired = true
        self:LockAll()
    end
end

--- Nimmt alle Bedienelemente aus dem Fenster.
function BidFrame:LockAll()
    for _, row in ipairs(self.rows) do
        for _, liste in ipairs({ row.buttons, row.rollButtons }) do
            for _, button in ipairs(liste or {}) do button:Hide() end
        end
        for _, element in ipairs({ row.dkpBox, row.dkpButton, row.dkpCancel }) do
            if element then element:Hide() end
        end
    end
end

--- Zeigt eine Ablehnung, die vom Plündermeister kam.
function BidFrame:ShowBidError(awardId, grund)
    if not self.announcement then return end
    for index, item in ipairs(self.announcement.items) do
        if item.awardId == awardId then
            local row = self.rows[index]
            if row then
                row.dkpError = GA.L["BID_DKP_ERR_" .. tostring(grund)] or tostring(grund)
                self:UpdateDkpRow(index)
            end
            return
        end
    end
end

--- Frischt ALLE DKP-Zeilen auf.
---
--- Nach jedem Gebot, nicht nur nach dem in dieser Zeile: Ein gebundener
--- Punkt fehlt ueberall sonst. Im ersten Anlauf stand bei allen Zeilen
--- dieselbe Zahl, waehrend eine davon laengst gebunden war.
function BidFrame:RefreshDkpRows()
    if not self.announcement then return end
    for index in ipairs(self.announcement.items) do
        self:UpdateDkpRow(index)
    end
end

--- Zieht das eigene DKP-Gebot zurueck.
function BidFrame:CancelBid(index)
    local row = self.rows[index]
    if not row or not self.announcement then return end

    local Session = GA.Modules.Session
    local identity = Compat.GetPlayerIdentity()

    local ok
    if Session:Get(self.announcement.id) then
        ok = Session:CancelDkpBid(self.announcement.id, row.awardId, identity.name)
    else
        if not GA.Core.Comm then return end
        -- Ein Gebot von 0 heisst: zurueckziehen. Eine eigene Nachricht
        -- dafuer waere eine mehr, die alle Clients kennen muessen.
        ok = GA.Core.Comm:Send("DBID", { self.announcement.id, row.awardId, 0 })
    end

    if not ok then return end

    row.dkpError = nil
    if row.dkpBox then row.dkpBox:SetText("") end
    self:RefreshDkpRows()
end

--- Wuerfelt fuer den Gegenstand in dieser Zeile.
--- Traegt das eigene Wurfergebnis in die Zeile nach.
---
--- Gelesen wird es aus der SITZUNG, nicht aus dem Chat: Dort steht es
--- bereits als Bewerbung, und wenn die Chatzeile ausgeblendet ist, ist die
--- Sitzung ohnehin die einzige Quelle.
function BidFrame:ShowOwnRoll(index)
    local row = self.rows[index]
    if not row or not row.awaitingRoll or not self.announcement then return end

    local Session = GA.Modules.Session

    -- ZWEI QUELLEN, JE NACHDEM, WER MAN IST.
    --
    -- Der Plündermeister hat die Sitzung liegen und liest direkt darin.
    -- Ein Raidmitglied hat sie nicht — seine Zahl kommt als Rueckmeldung
    -- vom Plündermeister an. Ohne diesen zweiten Weg haette es auf einen
    -- Knopf gedrueckt und nie etwas gesehen.
    local eigen
    local session = Session:Get(self.announcement.id)
    if session then
        local bids = session.responses[row.awardId]
        local identity = Compat.GetPlayerIdentity()
        eigen = bids and bids[GA.Core.Util.ShortName(identity.name or "")]
    else
        eigen = Session.myRolls and Session.myRolls[row.awardId]
        if eigen then eigen = { roll = eigen.roll, rollMax = eigen.max } end
    end

    if not eigen or not eigen.roll then return end

    row.awaitingRoll = false
    row.answer:SetText(string.format(GA.L.BID_ROLLED_VALUE,
        eigen.roll, eigen.rollMax or 0))
end

function BidFrame:Roll(index, tierKey)
    local row = self.rows[index]
    if not row or not self.announcement then return end

    local ok, grund = GA.Modules.Session:DeclareRoll(
        self.announcement.id, row.awardId, tierKey)

    if not ok then
        GA.Core.Debug:Warn("%s", GA.L["BID_ROLL_ERR_" .. tostring(grund)] or tostring(grund))
        return
    end

    -- Die Knoepfe weg: Ein zweiter Wurf zaehlt nicht, und ein Knopf, der
    -- nichts mehr bewirkt, laedt trotzdem zum Druecken ein.
    for _, button in ipairs(row.rollButtons) do button:Hide() end
    row.answer:SetText(GA.L.BID_ROLLED)
    row.answer:Show()

    -- DIE ZAHL NACHTRAGEN, SOBALD SIE DA IST.
    --
    -- Der Wurf laeuft ueber den Server: Beim Druecken steht das Ergebnis
    -- noch nicht fest. Waere die Zeile aus dem Chat auch noch ausgeblendet,
    -- saehe man sein eigenes Ergebnis nirgends — und genau das soll das
    -- Fenster zeigen.
    row.awaitingRoll = true
    Compat.After(0.5, function() BidFrame:ShowOwnRoll(index) end)
    Compat.After(2, function() BidFrame:ShowOwnRoll(index) end)
end

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
        -- Auch die ID: Der Tooltip kommt sonst nicht zustande, wenn dieser
        -- Client den Gegenstand noch nie gesehen hat.
        row.itemID = item.itemID

        -- Den Link baut dieser Client selbst aus der Item-ID. Verschickt wird
        -- nur die Zahl — ein Itemlink ueberlebt den Transport nicht unveraendert.
        local info = Compat.GetItemInfo(item.itemID)
        row.itemLink = info and info.link or nil
        row.name:SetText(info and info.name or ("#" .. tostring(item.itemID)))
        local quality = Theme.QualityColor(info and info.quality)
        row.name:SetTextColor(quality[1], quality[2], quality[3])

        -- DAS SYMBOL BEHAELT SEINEN PLATZ. Es zu verstecken laesst den
        -- Namen nach links rutschen, und dann stehen die Zeilen versetzt —
        -- ausgerechnet die, bei denen ohnehin noch Daten fehlen.
        row.icon:SetTexture(info and info.icon or QUESTION_MARK)
        row.icon:Show()

        -- Zurueck auf "noch nicht geantwortet".
        row.answer:Hide()
        for _, button in ipairs(row.buttons) do
            button:SetEnabledState(true)
        end
        for _, button in ipairs(row.rollButtons) do
            button:SetEnabledState(true)
        end

        -- Welche Seite ueberhaupt gezeigt wird, entscheidet die Verteilart.
        BidFrame:ApplyMode(row, item.itemID)
        row:Show()
    end

    for index = count + 1, #self.rows do self.rows[index]:Hide() end

    -- FEHLENDE NAMEN NACHREICHEN.
    --
    -- Ein Gegenstand, den dieser Client noch nie gesehen hat, liefert bei
    -- GetItemInfo nichts — dann stand hier "#12103" und blieb so stehen.
    -- Der Server schickt die Daten kurz darauf nach; dieses Ereignis sagt
    -- es, und dann wird die Zeile neu beschriftet.
    self:WatchItemInfo()

    -- Eine neue Ankuendigung heisst: neue Frist.
    self.expired = false
    self:UpdateTimer()

    self.frame:Show()
end

function BidFrame:Hide()
    -- Den Haken loesen: Ein Ereignis, das nach dem Schliessen weiterlaeuft,
    -- kostet bei jedem Gegenstand im Spiel Rechenzeit fuer nichts.
    if self.watcher then self.watcher:UnregisterAllEvents() end
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
