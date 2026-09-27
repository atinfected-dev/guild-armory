--[[----------------------------------------------------------------------------
    UI/BidFrame — das Fenster, das beim Spieler aufgeht, wenn eine Lootsession
    startet. EINE KARTE JE GEGENSTAND (Entwurf B2, 27.09.2026): oben das
    Symbol mit Qualitaetskante, der Name, der Platz; in der Mitte der
    Vergleich mit dem, was man traegt — "Angelegt 22, Neu 27, +5" als zwei
    Balken; darunter die Antworten; unten der Stand der Karte.

    Der Vergleich ist die Auskunft, die im Raid fehlt: Ob ein Teil eine
    Verbesserung ist, weiss der Spieler nur, wenn er sein Charakterfenster
    daneben aufmacht. Hier steht es da — gemessen an seinem eigenen
    Gegenstand am selben Platz, nicht geraten.

    ENTWURFSENTSCHEIDUNG: kein Zwang, keine Zeituhr. Manche Loot-Addons zaehlen
    einen Countdown herunter und werten Schweigen als "Passen". Das erzeugt im
    Raid genau den Streit, den ein LootCouncil vermeiden soll — wer gerade tot
    war oder nachgeladen hat, verliert seine Bewerbung. Hier bleibt das Fenster
    stehen, bis der Spieler antwortet oder der Lootmeister die Session schliesst.
    (Eine Frist, WENN der Lootmeister eine setzt, wird angezeigt — und die
    Knoepfe gehen weg, bevor jemand in eine Ablehnung hineinlaeuft.)

    Das Fenster erscheint nur, wenn wirklich eine Ankuendigung kam. Es baut
    seine Karten aus der Ankuendigung, nicht aus einer eigenen Datenbank: Was
    zur Abstimmung steht, entscheidet der Lootmeister.

    DIE FELDER EINER KARTE HEISSEN WIE VORHER (row.buttons, row.rollButtons,
    row.dkpBox, row.answer …): Session.lua und die Sandbox greifen auf das
    Fenster zu, und ein Umbau der Form ist kein Grund, die Schnittstelle zu
    aendern.
------------------------------------------------------------------------------]]

local _, GA = ...

local BidFrame = {}
GA.UI.BidFrame = BidFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Compat = GA.Core.Compat
local L = GA.L

local CARD_W, CARD_H, CARD_GAP = 212, 272, 8
local MAX_COLUMNS = 3
--- Mehr Karten als das stehen nie gleichzeitig im Fenster. Gemeldet
--- 27.09.2026: Mit neun oder zwoelf Gegenstaenden wuchs das Fenster ueber
--- den Bildschirm hinaus. Was nicht passt, wartet und rueckt nach, sobald
--- eine Karte beantwortet ist — der Zaehler im Kopf sagt, wie viele warten.
local MAX_VISIBLE = 6
local PAD = 14
local HEAD_H = 52          -- Titelleiste der Vorlage + Zeile mit Lootmeister + Fristbalken
local FOOT_H = 34
local BUTTON_W, BUTTON_H, BUTTON_GAP = 60, 18, 4
local PER_ROW = 3          -- Antwortknoepfe je Reihe: 3 x 60 + 2 x 4 = 188 < 192

--- Das Fragezeichen: Platzhalter, solange der Client den Gegenstand nicht
--- kennt. Es haelt den Platz, damit die Karten nicht versetzt stehen.
local QUESTION_MARK = [[Interface\Icons\INV_Misc_QuestionMark]]

--- Spalten und Reihen fuer n Karten.
local function raster(count)
    local columns = math.max(1, math.min(MAX_COLUMNS, count))
    local rows = math.max(1, math.ceil(count / columns))
    return columns, rows
end

local function frameSize(count)
    local columns, rows = raster(count)
    local width = 2 * PAD + columns * CARD_W + (columns - 1) * CARD_GAP
    local height = HEAD_H + rows * CARD_H + (rows - 1) * CARD_GAP + 10 + FOOT_H
    return width, height
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

    local width, height = frameSize(1)
    frame:SetWidth(width)
    frame:SetHeight(height)
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

    self.hint = Theme.Label(frame, L.BID_HINT, fonts.small, Theme.color.textDim)
    self.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    self.hint:SetJustifyH("LEFT")

    -- Die Uhr steht rechts im Kopf, neben dem Hinweis: Dort sucht man
    -- sie, und sie verdeckt keine Karte. Links davon der Zaehler.
    self.timer = Theme.Label(frame, "", fonts.small, Theme.color.textFaint)
    self.timer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
    self.timer:SetJustifyH("RIGHT")

    self.counter = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.counter:SetPoint("RIGHT", self.timer, "LEFT", -10, 0)
    self.counter:SetJustifyH("RIGHT")
    self.hint:SetPoint("RIGHT", self.counter, "LEFT", -10, 0)

    -- DIE FRIST ALS BALKEN unter der Kopfzeile: schrumpft mit der Zeit.
    -- Eine Zahl liest man, einen Balken sieht man aus dem Augenwinkel.
    self.timerTrack = frame:CreateTexture(nil, "ARTWORK")
    Theme.Paint(self.timerTrack, Theme.color.rowBg)
    self.timerTrack:SetHeight(2)
    self.timerTrack:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEAD_H - 6))
    self.timerTrack:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    self.timerTrack:Hide()

    self.timerFill = frame:CreateTexture(nil, "OVERLAY")
    Theme.Paint(self.timerFill, Theme.color.warn)
    self.timerFill:SetHeight(2)
    self.timerFill:SetPoint("TOPLEFT", self.timerTrack, "TOPLEFT", 0, 0)
    self.timerFill:SetWidth(1)
    self.timerFill:Hide()

    -- Fusszeile: der Satz zum Fenster und "Rest passen".
    self.footHint = Theme.Label(frame, L.BID_HINT_CARDS, fonts.small, Theme.color.textFaint)
    self.footHint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 12)
    self.footHint:SetJustifyH("LEFT")
    self.footHint:SetWordWrap(false)

    -- REST PASSEN: alles, was noch offen ist und auf das man mit einer
    -- Antwort passen KANN. Wurf und Gebot haben kein Passen — dort heisst
    -- Nichtstun schon nichts.
    self.passRest = Widgets.Button(frame, L.BID_PASS_REST, function()
        BidFrame:PassRest()
    end)
    self.passRest:SetHeight(20)
    self.passRest:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 10)
    self.footHint:SetPoint("RIGHT", self.passRest, "LEFT", -8, 0)

    -- Einmal je Viertelsekunde genuegt: Eine Uhr, die dreissigmal in der
    -- Sekunde dieselbe Zahl schreibt, kostet nur Rechenzeit.
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

--- Eine Karte: Symbol, Name, Platz, Vergleich, Antworten, Stand.
function BidFrame:BuildRow(index)
    if self.rows[index] then return self.rows[index] end

    local fonts = Theme.Fonts()
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetWidth(CARD_W)
    row:SetHeight(CARD_H)
    row.fill = Theme.Fill(row, Theme.color.panelBg)
    row.lines = Theme.Outline(row, Theme.color.border)

    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.edge:SetHeight(3)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(40) row.icon:SetHeight(40)
    row.icon:SetPoint("TOP", row, "TOP", 0, -12)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("TOP", row.icon, "BOTTOM", 0, -6)
    row.name:SetWidth(CARD_W - 20)
    row.name:SetHeight(30)
    row.name:SetJustifyH("CENTER")
    row.name:SetJustifyV("TOP")

    row.slot = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.slot:SetPoint("TOP", row.name, "BOTTOM", 0, -2)
    row.slot:SetWidth(CARD_W - 20)
    row.slot:SetJustifyH("CENTER")
    row.slot:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GA.UI.Widgets.ShowItemTooltip(self, self.itemID, self.itemLink)
    end)
    row:SetScript("OnLeave", function() GA.UI.Widgets.HideItemTooltip() end)

    -- ------------------------------------------------------- Vergleich -----
    local cmp = CreateFrame("Frame", nil, row)
    cmp:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -112)
    cmp:SetWidth(CARD_W - 20)
    cmp:SetHeight(58)
    Theme.Fill(cmp, Theme.color.windowBg)
    Theme.Outline(cmp, Theme.color.border)
    row.cmp = cmp

    cmp.haveLabel = Theme.Label(cmp, L.BID_EQUIPPED, fonts.small, Theme.color.textFaint)
    cmp.haveLabel:SetPoint("TOPLEFT", cmp, "TOPLEFT", 6, -5)

    cmp.haveName = Theme.Label(cmp, "", fonts.small, Theme.color.textDim)
    cmp.haveName:SetPoint("TOPRIGHT", cmp, "TOPRIGHT", -6, -5)
    cmp.haveName:SetPoint("LEFT", cmp.haveLabel, "RIGHT", 6, 0)
    cmp.haveName:SetJustifyH("RIGHT")
    cmp.haveName:SetWordWrap(false)

    cmp.haveIlvl = Theme.Label(cmp, "", fonts.small, Theme.color.textDim)
    cmp.haveIlvl:SetPoint("TOPRIGHT", cmp, "TOPRIGHT", -6, -19)
    cmp.haveIlvl:SetWidth(28)
    cmp.haveIlvl:SetJustifyH("RIGHT")

    cmp.haveTrack = cmp:CreateTexture(nil, "ARTWORK")
    Theme.Paint(cmp.haveTrack, Theme.color.rowBg)
    cmp.haveTrack:SetHeight(4)
    cmp.haveTrack:SetPoint("TOPLEFT", cmp, "TOPLEFT", 6, -23)
    cmp.haveTrack:SetPoint("RIGHT", cmp.haveIlvl, "LEFT", -6, 0)

    cmp.haveFill = cmp:CreateTexture(nil, "OVERLAY")
    Theme.Paint(cmp.haveFill, Theme.color.goldDeep)
    cmp.haveFill:SetHeight(4)
    cmp.haveFill:SetPoint("LEFT", cmp.haveTrack, "LEFT", 0, 0)
    cmp.haveFill:SetWidth(1)

    cmp.newIlvl = Theme.Label(cmp, "", fonts.rowBold, Theme.color.goldBright)
    cmp.newIlvl:SetPoint("TOPRIGHT", cmp, "TOPRIGHT", -6, -30)
    cmp.newIlvl:SetWidth(28)
    cmp.newIlvl:SetJustifyH("RIGHT")

    cmp.newTrack = cmp:CreateTexture(nil, "ARTWORK")
    Theme.Paint(cmp.newTrack, Theme.color.rowBg)
    cmp.newTrack:SetHeight(4)
    cmp.newTrack:SetPoint("TOPLEFT", cmp, "TOPLEFT", 6, -35)
    cmp.newTrack:SetPoint("RIGHT", cmp.newIlvl, "LEFT", -6, 0)

    cmp.newFill = cmp:CreateTexture(nil, "OVERLAY")
    Theme.Paint(cmp.newFill, Theme.color.goldDim)
    cmp.newFill:SetHeight(4)
    cmp.newFill:SetPoint("LEFT", cmp.newTrack, "LEFT", 0, 0)
    cmp.newFill:SetWidth(1)

    cmp.newLabel = Theme.Label(cmp, L.BID_NEW, fonts.small, Theme.color.textFaint)
    cmp.newLabel:SetPoint("BOTTOMLEFT", cmp, "BOTTOMLEFT", 6, 5)

    cmp.delta = Theme.Label(cmp, "", fonts.rowBold, Theme.color.jade)
    cmp.delta:SetPoint("BOTTOMRIGHT", cmp, "BOTTOMRIGHT", -6, 5)

    -- ------------------------------------------------------- Antworten -----
    -- DREI MOEGLICHE ANTWORTBLOECKE, alle beim Bauen angelegt und je nach
    -- Verteilart gezeigt. Sie beim Oeffnen neu zu bauen waere einfacher zu
    -- schreiben und schlechter zu benutzen: Knoepfe, die bei jedem Aufbau
    -- anders sitzen, lassen einen ins Leere klicken.
    local answersTop = -(112 + 58 + 8)
    local function platz(button, position)
        local spalte = (position - 1) % PER_ROW
        local reihe = math.floor((position - 1) / PER_ROW)
        button:SetPoint("TOPLEFT", row, "TOPLEFT",
            12 + spalte * (BUTTON_W + BUTTON_GAP), answersTop - reihe * (BUTTON_H + BUTTON_GAP))
    end

    row.buttons = {}
    for position, response in ipairs(GA.Modules.Session:Responses()) do
        local button = Widgets.Button(row, response.short or response.label, function()
            BidFrame:Answer(index, response.key)
        end)
        button:SetHeight(BUTTON_H)
        -- Nach SetText misst sich der Blizzard-Knopf selbst; hier muessen
        -- alle gleich breit bleiben, sonst rutscht das Raster.
        button:SetWidth(BUTTON_W)
        button.tooltip = response.label
        platz(button, position)
        button.responseKey = response.key
        row.buttons[#row.buttons + 1] = button
    end

    row.rollButtons = {}
    for position, tier in ipairs(GA.Data.Schema.RollTiers) do
        local button = Widgets.Button(row, tostring(tier.max), function()
            BidFrame:Roll(index, tier.key)
        end)
        button:SetHeight(BUTTON_H)
        button:SetWidth(BUTTON_W)
        button.tooltip = tier.label
        platz(button, position)
        button.tierKey = tier.key
        row.rollButtons[#row.rollButtons + 1] = button
    end

    -- DKP: ein Eingabefeld statt Knoepfen.
    --
    -- Knoepfe gingen hier nicht: Der Betrag ist nicht aus einer Handvoll
    -- Moeglichkeiten zu waehlen, sondern eine Zahl zwischen dem
    -- Mindestgebot und dem eigenen Stand. Beides steht darunter, damit
    -- niemand raten muss.
    row.dkpBox = Theme.CreateNative("EditBox", nil, row, "InputBoxTemplate")
    if row.dkpBox then
        row.dkpBox:SetWidth(52)
        row.dkpBox:SetHeight(BUTTON_H)
        row.dkpBox:SetPoint("TOPLEFT", row, "TOPLEFT", 18, answersTop)
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
        row.dkpButton:SetHeight(BUTTON_H)
        row.dkpButton:SetWidth(BUTTON_W)
        row.dkpButton:SetPoint("LEFT", row.dkpBox, "RIGHT", 4, 0)
        row.dkpButton:Hide()

        -- ZURUECKZIEHEN. Abgebucht ist noch nichts, bezahlt wird erst bei
        -- der Vergabe — hier verschwindet man nur aus der Liste. Und die
        -- Punkte, die das Gebot gebunden hat, sind wieder frei.
        row.dkpCancel = Widgets.Button(row, L.BID_DKP_CANCEL, function()
            BidFrame:CancelBid(index)
        end)
        row.dkpCancel:SetHeight(BUTTON_H)
        row.dkpCancel:SetWidth(BUTTON_W + 6)
        row.dkpCancel:SetPoint("LEFT", row.dkpButton, "RIGHT", 4, 0)
        row.dkpCancel:Hide()

        -- Was man hat und was mindestens geht. Ohne diese Zeile bietet
        -- jemand ins Leere und erfaehrt erst nach dem Druecken, warum es
        -- nicht ging.
        row.dkpInfo = Theme.Label(row, "", fonts.small, Theme.color.textDim)
        row.dkpInfo:SetPoint("TOPLEFT", row, "TOPLEFT", 12, answersTop - BUTTON_H - 4)
        row.dkpInfo:SetWidth(CARD_W - 24)
        row.dkpInfo:SetHeight(16)
        row.dkpInfo:SetJustifyH("LEFT")
        row.dkpInfo:SetWordWrap(false)
        row.dkpInfo:Hide()
    end

    -- PASSEN BEI WURF UND GEBOT. Im Council-Modus ist Pass eine der
    -- Antworten; bei Wurf und DKP gab es keinen Weg, nein zu sagen
    -- (gemeldet 27.09.2026). Der Knopf schickt dieselbe Antwort wie der
    -- Pass des Councils — der Lootmeister sieht ein "Pass" statt Schweigen,
    -- und Schweigen ist von "noch nicht gesehen" nicht zu unterscheiden.
    -- Dritte Reihe, damit er bei DKP nicht neben dem Feld klemmt.
    local pass = GA.Modules.Session:ResponseByKey("PASS")
    row.passButton = Widgets.Button(row, pass and (pass.short or pass.label) or "Pass", function()
        BidFrame:Answer(index, "PASS")
    end)
    row.passButton:SetHeight(BUTTON_H)
    row.passButton:SetWidth(BUTTON_W)
    platz(row.passButton, 7)
    row.passButton:Hide()

    -- Wer reserviert hat. Steht STATT der Knoepfe: Ist ein Stueck
    -- reserviert, entscheidet die Reservierung, und ein Gebot daneben waere
    -- ein zweites Verfahren fuer dieselbe Sache.
    row.reserved = Theme.Label(row, "", fonts.small, Theme.color.gold)
    row.reserved:SetPoint("TOPLEFT", row, "TOPLEFT", 12, answersTop)
    row.reserved:SetWidth(CARD_W - 24)
    row.reserved:SetJustifyH("CENTER")
    row.reserved:Hide()

    -- Der Stand der Karte, ganz unten: die gegebene Antwort in Jade, sonst
    -- "noch keine Antwort" in Grau.
    row.answer = Theme.Label(row, "", fonts.small, Theme.color.jade)
    row.answer:SetPoint("BOTTOM", row, "BOTTOM", 0, 8)
    row.answer:SetWidth(CARD_W - 16)
    row.answer:SetJustifyH("CENTER")
    row.answer:SetWordWrap(false)
    row.answer:Hide()

    row.pending = Theme.Label(row, L.BID_NOT_ANSWERED, fonts.small, Theme.color.textFaint)
    row.pending:SetPoint("BOTTOM", row, "BOTTOM", 0, 8)

    self.rows[index] = row
    return row
end

-- ================================================================== Anzeigen --

--- Schreibt Name, Farbe, Symbol, Platz und Vergleich einer Karte — alles,
--- was aus den Itemdaten kommt. Ohne Daten: Fragezeichen und Kennung.
function BidFrame:Label(row, itemID)
    local info = Compat.GetItemInfo(itemID)
    row.itemLink = info and info.link or row.itemLink

    row.name:SetText(info and info.name or ("#" .. tostring(itemID)))
    local quality = Theme.QualityColor(info and info.quality)
    row.name:SetTextColor(quality[1], quality[2], quality[3])
    Theme.Paint(row.edge, info and quality or Theme.color.border)
    row.icon:SetTexture(info and info.icon or QUESTION_MARK)
    row.icon:Show()

    local teile = {}
    if info then
        local ort = Compat.EquipLocName(info.equipLoc)
        if ort then teile[#teile + 1] = ort end
        if info.subType and info.subType ~= "" then teile[#teile + 1] = info.subType end
    end
    row.slot:SetText(table.concat(teile, " · "))

    self:Compare(row, info)
    return info ~= nil
end

--- Der Vergleich mit dem eigenen Gegenstand am selben Platz.
---
--- GEMESSEN, NICHT GERATEN: der eigene Gegenstand mit dem niedrigsten
--- Itemlevel unter den Plaetzen, die das Teil belegen kann — den wuerde man
--- tauschen. Ein leerer Platz ist 0 und damit die groesste Verbesserung.
--- Was nicht anlegbar ist, bekommt keinen Vergleich, sondern den Satz dazu.
function BidFrame:Compare(row, info)
    local cmp = row.cmp
    local neu = info and (Compat.GetItemLevelOf(info.link) or info.itemLevel) or nil
    if neu and neu <= 0 then neu = nil end

    local getragen = info and Compat.EquippedToReplace(info.equipLoc)

    local function balken(fill, wert, maximum)
        local breite = cmp.haveTrack:GetWidth()
        if not breite or breite <= 0 then breite = CARD_W - 20 - 12 - 34 end
        if wert and maximum and maximum > 0 then
            fill:SetWidth(math.max(1, math.floor(breite * math.min(1, wert / maximum))))
            fill:Show()
        else
            fill:Hide()
        end
    end

    if not getragen then
        cmp.haveName:SetText(info and L.BID_NO_COMPARE or "")
        cmp.haveIlvl:SetText("")
        cmp.newIlvl:SetText(neu and tostring(neu) or "")
        cmp.delta:SetText("")
        balken(cmp.haveFill, nil)
        balken(cmp.newFill, neu, neu)
        return
    end

    local eigenInfo = getragen.link and Compat.GetItemInfo(getragen.link)
    cmp.haveName:SetText(eigenInfo and eigenInfo.name or L.BID_EMPTY_SLOT)
    cmp.haveIlvl:SetText(getragen.itemLevel > 0 and tostring(getragen.itemLevel) or "—")
    cmp.newIlvl:SetText(neu and tostring(neu) or "—")

    local maximum = math.max(getragen.itemLevel, neu or 0, 1)
    balken(cmp.haveFill, getragen.itemLevel, maximum)
    balken(cmp.newFill, neu, maximum)

    if neu then
        local unterschied = neu - getragen.itemLevel
        local farbe = unterschied > 0 and Theme.color.jade
            or unterschied < 0 and Theme.color.warn or Theme.color.textFaint
        cmp.delta:SetText(unterschied > 0 and ("+" .. unterschied)
            or unterschied < 0 and tostring(unterschied) or "±0")
        cmp.delta:SetTextColor(farbe[1], farbe[2], farbe[3])
    else
        cmp.delta:SetText("")
    end
end

--- Beschriftet die Karten neu, sobald der Server Itemdaten nachliefert.
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

--- Schreibt Namen, Farbe, Symbol und Vergleich neu — ohne die Antworten
--- anzufassen.
function BidFrame:Relabel()
    if not self.frame or not self.frame:IsShown() or not self.announcement then return end

    local fehlt = false
    for index, item in ipairs(self.announcement.items) do
        local row = self.rows[index]
        if row and not self:Label(row, item.itemID) then fehlt = true end
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

--- Zeigt auf einer Karte das, was zur Verteilart passt.
---
--- Vier Faelle, und sie schliessen einander aus:
---
---   DKP          Feld, Bieten, Zurueckziehen, und darunter Stand und Minimum.
---   reserviert   Die Reservierung entscheidet. Es gibt nichts zu tun,
---                also auch keine Knoepfe — nur die Namen.
---   verrollt     Drei Spannen zur Wahl. Der Klick wuerfelt wirklich.
---   sonst        Die Antworten des Councils.
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
        row.passButton:Show()

        row.answer:Hide()
        row.pending:Show()
        row.mode = "dkp"
        self:UpdateDkpRow(row.position)
        return "dkp"
    end

    dkpZeigen(false)

    if #reserviert > 0 then
        zeige(row.buttons, false)
        zeige(row.rollButtons, false)
        row.reserved:SetText(string.format(GA.L.BID_RESERVED_BY,
            table.concat(reserviert, ", ")))
        row.reserved:Show()
        row.pending:Hide()
        row.passButton:Hide()
        row.mode = "reserved"
        return "reserved"
    end

    row.reserved:Hide()
    row.pending:Show()

    if Session:RollsFor(itemID) then
        zeige(row.buttons, false)
        zeige(row.rollButtons, true)
        row.passButton:Show()
        row.mode = "roll"
        return "roll"
    end

    zeige(row.rollButtons, false)
    zeige(row.buttons, true)
    row.passButton:Hide()
    row.mode = "bid"
    return "bid"
end

--- Schreibt den Zaehler "k von n beantwortet" neu.
--- Ist diese Karte beantwortet? Erledigt (weg), oder ein stehendes Gebot.
function BidFrame:IsAnswered(row)
    if not row then return false end
    if row.done then return true end
    return row.mode == "dkp" and self:OwnDkpBid(row.awardId) ~= nil
end

function BidFrame:UpdateCounter()
    if not self.counter or not self.announcement then return end
    local gesamt, beantwortet = #self.announcement.items, 0
    for index = 1, gesamt do
        if self:IsAnswered(self.rows[index]) then beantwortet = beantwortet + 1 end
    end
    local text = string.format(L.BID_ANSWERED_COUNT, beantwortet, gesamt)
    if (self.queued or 0) > 0 then
        text = text .. "  ·  " .. string.format(L.BID_QUEUED, self.queued)
    end
    self.counter:SetText(text)

    -- "Rest passen" nur, wenn es einen Rest gibt.
    local offen = false
    for index = 1, gesamt do
        local row = self.rows[index]
        if row and row.mode ~= "reserved" and not self:IsAnswered(row) then offen = true break end
    end
    self.passRest:SetShown(offen)
end

--- Passt auf alles, was noch offen ist. Ein stehendes DKP-Gebot ist eine
--- Antwort und bleibt.
function BidFrame:PassRest()
    if not self.announcement then return end
    for index = 1, #self.announcement.items do
        local row = self.rows[index]
        if row and row.mode ~= "reserved" and not self:IsAnswered(row) then
            self:Answer(index, "PASS")
        end
    end
end

--- Legt die offenen Karten ins Raster: die ersten MAX_VISIBLE, der Rest
--- wartet. Erledigte Karten sind weg, und was dahinter stand, rueckt nach.
--- Ist nichts mehr offen, schliesst sich das Fenster kurz darauf.
function BidFrame:Layout()
    if not self.frame or not self.announcement then return end

    local offen = {}
    for index = 1, #self.announcement.items do
        local row = self.rows[index]
        if row and not row.done then offen[#offen + 1] = row end
    end

    local sichtbar = math.min(#offen, MAX_VISIBLE)
    self.queued = #offen - sichtbar

    local width, height = frameSize(math.max(sichtbar, 1))
    self.frame:SetWidth(width)
    self.frame:SetHeight(height)

    local columns = raster(math.max(sichtbar, 1))
    for position, row in ipairs(offen) do
        if position <= sichtbar then
            local spalte = (position - 1) % columns
            local reihe = math.floor((position - 1) / columns)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                PAD + spalte * (CARD_W + CARD_GAP), -(HEAD_H + reihe * (CARD_H + CARD_GAP)))
            row:Show()
        else
            row:Hide()
        end
    end
    for index = 1, #self.rows do
        local row = self.rows[index]
        if row.done or index > #self.announcement.items then row:Hide() end
    end

    self:UpdateCounter()

    -- Alles beantwortet? Dann kann das Fenster weg.
    if #offen == 0 then Compat.After(1.5, function() BidFrame:Hide() end) end
end

-- ================================================================== DKP -------

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
        -- DER GRUND STEHT AUF DER KARTE, nicht nur im Chat. Im Raid laufen
        -- dort Kampfmeldungen durch, und das Gebotsfenster liegt darueber
        -- — eine Ablehnung im Chat sieht niemand.
        row.dkpError = GA.L["BID_DKP_ERR_" .. tostring(grund)] or tostring(grund)
        self:UpdateDkpRow(index)
        return
    end

    row.dkpError = nil
    row.dkpBox:ClearFocus()
    row.dkpBox:SetText("")

    -- ALLE Karten, nicht nur diese: Ein gebundener Punkt fehlt ueberall
    -- sonst.
    self:RefreshDkpRows()
end

--- Schreibt die Infozeile einer DKP-Karte neu.
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
        -- Ein stehendes Gebot ist eine Antwort: Das zeigt der Stand unten.
        row.answer:SetText(string.format(GA.L.BID_DKP_SENT, eigenes))
        row.answer:Show()
        row.pending:Hide()
    else
        row.dkpInfo:SetText(string.format(GA.L.BID_DKP_AVAILABLE, frei, Dkp:MinBid()))
        row.dkpInfo:SetTextColor(dim[1], dim[2], dim[3])
        row.answer:Hide()
        row.pending:Show()
    end

    -- Zurueckziehen geht nur, wenn etwas dasteht.
    if row.dkpCancel and row.dkpCancel.SetEnabledState then
        row.dkpCancel:SetEnabledState(eigenes ~= nil)
    end
    self:UpdateCounter()
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

-- ================================================================== Frist -----

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

--- Schreibt die Uhr und den Balken und sperrt alles, wenn sie abgelaufen ist.
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
        if self.timerTrack then self.timerTrack:Hide() self.timerFill:Hide() end
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

    -- Der Balken: gemessen an der Frist, die beim Oeffnen noch lief.
    if self.timerTrack then
        local gesamt = self.timerTotal or rest
        local breite = self.timerTrack:GetWidth()
        if not breite or breite <= 0 then breite = 200 end
        self.timerTrack:Show()
        if gesamt > 0 and rest > 0 then
            self.timerFill:SetWidth(math.max(1, breite * math.min(1, rest / gesamt)))
            self.timerFill:Show()
        else
            self.timerFill:Hide()
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
        for _, element in ipairs({ row.dkpBox, row.dkpButton, row.dkpCancel, row.passButton }) do
            if element then element:Hide() end
        end
    end
    if self.passRest then self.passRest:Hide() end
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

--- Frischt ALLE DKP-Karten auf.
---
--- Nach jedem Gebot, nicht nur nach dem auf dieser Karte: Ein gebundener
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

-- ================================================================== Wurf ------

--- Traegt das eigene Wurfergebnis auf der Karte nach.
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

--- Wuerfelt fuer den Gegenstand auf dieser Karte.
function BidFrame:Roll(index, tierKey)
    local row = self.rows[index]
    if not row or not self.announcement then return end

    local ok, grund = GA.Modules.Session:DeclareRoll(
        self.announcement.id, row.awardId, tierKey)

    if not ok then
        GA.Core.Debug:Warn("%s", GA.L["BID_ROLL_ERR_" .. tostring(grund)] or tostring(grund))
        return
    end

    -- DIE KARTE IST ERLEDIGT und geht aus dem Fenster; was dahinter
    -- wartete, rueckt nach. Ein zweiter Wurf zaehlt ohnehin nicht. Das
    -- Ergebnis steht im Chat und in der Sitzung, nicht auf einer Karte,
    -- die niemand mehr braucht (27.09.2026: "nachdem man seinen Bid
    -- gesetzt hat, das Item aus der Liste").
    row.answer:SetText(GA.L.BID_ROLLED)
    row.answer:Show()
    row.pending:Hide()
    row.done = true
    self:Layout()

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

-- ================================================================== Oeffnen ---

--- @param announcement table { id, host, items = { { awardId, itemID } } }
function BidFrame:Show(announcement)
    if not announcement or not announcement.items or #announcement.items == 0 then return end

    self:Create()
    self.announcement = announcement

    local count = #announcement.items
    self.hint:SetText(string.format(L.BID_FROM, announcement.host or "?"))

    for index, item in ipairs(announcement.items) do
        local row = self:BuildRow(index)
        row.position = index
        row.awardId = item.awardId
        row.itemID = item.itemID
        row.done = false

        self:Label(row, item.itemID)

        row.answer:Hide()
        row.pending:Show()
        row.awaitingRoll = false
        for _, button in ipairs(row.buttons) do
            button:SetEnabledState(true)
        end
        for _, button in ipairs(row.rollButtons) do
            button:SetEnabledState(true)
        end
        row.passButton:SetEnabledState(true)

        BidFrame:ApplyMode(row, item.itemID)
    end

    for index = count + 1, #self.rows do self.rows[index]:Hide() end

    -- Die Karten ins Raster — erst jetzt, nach dem Fenster: Layout misst
    -- den Rahmen, und ein Rahmen ohne Groesse misst nichts.
    self.frame:Show()
    self:Layout()

    self:WatchItemInfo()

    self.expired = false
    self.timerTotal = self:TimeLeft()
    self:UpdateTimer()
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

    -- DIE KARTE GEHT AUS DEM FENSTER, und was dahinter wartete, rueckt nach
    -- (27.09.2026: mit zwoelf Gegenstaenden passte das Fenster nicht mehr
    -- auf den Bildschirm). Aendern geht ueber ein erneutes Oeffnen — eine
    -- Karte, die sich unter der Hand umstellen laesst, fuehrt im Raid zu
    -- "ich hatte doch BiS geklickt". Bei DKP kommt man hier nur ueber den
    -- Pass-Knopf her; ein Gebot selbst laesst die Karte stehen, weil man
    -- es erhoehen oder zurueckziehen kann.
    local response = GA.Modules.Session:ResponseByKey(responseKey)
    row.answer:SetText(string.format(L.BID_ANSWERED, response and response.label or responseKey))
    row.answer:Show()
    row.pending:Hide()
    row.done = true
    self:Layout()
end
