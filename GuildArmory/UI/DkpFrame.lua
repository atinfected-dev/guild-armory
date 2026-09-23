--[[----------------------------------------------------------------------------
    UI/DkpFrame — Punktestand ansehen, Punkte buchen.

    Ein eigenes Fenster, aufgerufen von der Regelseite. Es zeigt links die
    Rangliste und rechts das KONTOBUCH des Gewaehlten — die Antwort auf die
    Frage, um die es bei DKP immer geht: "Warum habe ich nur 40 Punkte?"

    DAS KONTOBUCH IST NICHT DIE NEBENANSICHT, SONDERN DER ZWECK.

    Eine Rangliste allein ist eine Behauptung. Jede Zeile daneben sagt,
    woher der Stand kommt — wann, wie viel, wofuer. Deshalb nimmt sie die
    groessere Haelfte des Fensters ein, obwohl man die Rangliste oefter
    ansieht.

    GEBUCHT WIRD MIT GRUND, und ohne Grund gar nicht. Das erzwingt schon
    Dkp:Post; hier steht nur das Feld dafuer, und der Knopf bleibt aus,
    solange es leer ist. Eine Buchung, die man spaeter nicht erklaeren
    kann, ist bei Punkten schlimmer als keine.

    ZWEI WEGE ZU BUCHEN, weil es zwei verschiedene Anlaesse sind:

      EINZELN   Eine Korrektur, ein Nachtrag, ein Abzug.
      DER RAID  Anwesenheit. Der haeufigste Fall, und von Hand fuer
                vierzig Leute waere er unzumutbar.
------------------------------------------------------------------------------]]

local _, GA = ...

local DkpFrame = {}
GA.UI.DkpFrame = DkpFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

--- Startwert fuer den Buchungsblock, bis er sich gemessen hat.
---
--- GEMESSEN WIRD ER, NICHT GESETZT. Der Hinweistext bricht um, und wie
--- oft, haengt an Sprache, Schriftgroesse und Fensterbreite. Eine feste
--- Hoehe dafuer ist eine Wette auf alle drei — und die ist in diesem
--- Addon schon zweimal verloren gegangen, zuletzt in den Einstellungen.
---
--- Diese Zahl gilt nur fuer den Augenblick vor der ersten Messung.
local POST_HEIGHT = 120

--- Raender des Fensters. Benannt, weil RelayoutPost mit ihnen rechnet.
local PAD, GAP = 14, 8

-- ================================================================== Aufbau ---

function DkpFrame:Create()
    if self.frame then return self.frame end

    local fonts = Theme.Fonts()

    local frame = Theme.CreateNative("Frame", "GuildArmoryDkpFrame", UIParent,
        "PortraitFrameTemplate")
    if not frame then
        frame = Theme.CreateBackdropFrame("GuildArmoryDkpFrame", UIParent)
        Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid)
    end

    -- Kein Portrait: Hier stehen Zahlen, kein Charakter.
    Theme.HidePortrait(frame)

    frame:SetWidth(680)
    frame:SetHeight(460)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    if frame.SetTitle then pcall(frame.SetTitle, frame, L.DKP_TITLE) end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() DkpFrame:Hide() end)
    end

    local pad, gap = PAD, GAP

    -- ------------------------------------------------------- Rangliste ------
    local liste = Widgets.Panel(frame, L.DKP_LIST_TITLE)
    liste:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -34)
    liste:SetWidth(260)

    self.players = Widgets.ScrollList(liste.content, {
        rowHeight = 20,
        createRow = function(row)
            row.nameText = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -56, 0)
            row.nameText:SetJustifyH("LEFT")

            row.points = Theme.Label(row, "", fonts.row, Theme.color.gold)
            row.points:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.points:SetWidth(50)
            row.points:SetJustifyH("RIGHT")
        end,
        updateRow = function(row, entry)
            row.nameText:SetText(Util.ColorByClass(entry.name or "?", entry.class))
            row.points:SetText(tostring(entry.total))
            -- Ein Konto bei null faellt auf. Das ist die Zahl, bei der
            -- jemand nicht mitbieten kann — und die er selten selbst sagt.
            local color = entry.total <= 0 and Theme.color.textFaint or Theme.color.gold
            row.points:SetTextColor(color[1], color[2], color[3])
        end,
        onClickRow = function(entry)
            DkpFrame.selected = entry.guid
            DkpFrame:Refresh()
        end,
    })
    self.players:SetAllPoints(liste.content)
    self.standingsPanel = liste

    -- ------------------------------------------------------- Kontobuch ------
    local buch = Widgets.Panel(frame, L.DKP_LEDGER)
    buch:SetPoint("TOPLEFT", liste, "TOPRIGHT", gap, 0)
    buch:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -34)
    buch:SetPoint("BOTTOM", liste, "BOTTOM", 0, 0)
    self.ledgerPanel = buch

    self.ledger = Widgets.ScrollList(buch.content, {
        rowHeight = 18,
        createRow = function(row)
            row.whenText = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.whenText:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.whenText:SetWidth(84)
            row.whenText:SetJustifyH("LEFT")

            row.delta = Theme.Label(row, "", fonts.small, Theme.color.text)
            row.delta:SetPoint("LEFT", row, "LEFT", 90, 0)
            row.delta:SetWidth(44)
            row.delta:SetJustifyH("RIGHT")

            row.why = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.why:SetPoint("LEFT", row, "LEFT", 140, 0)
            row.why:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.why:SetJustifyH("LEFT")
        end,
        updateRow = function(row, entry)
            row.whenText:SetText(Util.TimeAgo(entry.ts))
            row.delta:SetText(string.format("%+d", entry.points))
            local color = entry.points >= 0 and Theme.color.jade or Theme.color.warn
            row.delta:SetTextColor(color[1], color[2], color[3])
            row.why:SetText(entry.reason or "?")
        end,
    })
    self.ledger:SetAllPoints(buch.content)

    -- Die Unterkante setzt RelayoutPost, sobald der Block gemessen ist.
    liste:SetPoint("BOTTOM", frame, "BOTTOM", 0, pad + POST_HEIGHT + gap)

    -- ------------------------------------------------------- Buchen ---------
    -- DER BUCHUNGSBLOCK BESTIMMT, WIE VIEL PLATZ DIE LISTEN BEKOMMEN,
    -- nicht umgekehrt. Er ist der einzige Teil mit Text, der umbrechen
    -- kann; die Listen nehmen, was uebrig bleibt.
    --
    -- Vorher waren beide an feste Kanten gehaengt, und der Hinweistext
    -- lief unten aus dem Fenster heraus, waehrend die Knoepfe darueber
    -- standen.
    local buchen = Widgets.Panel(frame, L.DKP_POST_TITLE)
    buchen:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    buchen:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    buchen:SetHeight(POST_HEIGHT)
    self.postPanel = buchen

    self.amount = Theme.CreateNative("EditBox", nil, buchen.content, "InputBoxTemplate")
    if self.amount then
        self.amount:SetWidth(56)
        self.amount:SetHeight(20)
        self.amount:SetPoint("TOPLEFT", buchen.content, "TOPLEFT", 8, -2)
        self.amount:SetAutoFocus(false)
        self.amount:SetNumeric(false)  -- Minuszeichen muss erlaubt bleiben.
        self.amount:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        self.amount:SetScript("OnTextChanged", function() DkpFrame:RefreshButtons() end)
    end

    self.reason = Theme.CreateNative("EditBox", nil, buchen.content, "InputBoxTemplate")
    if self.reason then
        self.reason:SetHeight(20)
        self.reason:SetPoint("LEFT", self.amount, "RIGHT", 10, 0)
        self.reason:SetPoint("RIGHT", buchen.content, "RIGHT", -6, 0)
        self.reason:SetAutoFocus(false)
        self.reason:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        self.reason:SetScript("OnTextChanged", function() DkpFrame:RefreshButtons() end)
    end

    self.hint = Theme.Label(buchen.content, L.DKP_POST_HINT, fonts.small,
        Theme.color.textDim)
    -- Ohne feste Hoehe: Wie hoch dieser Text wird, misst RelayoutPost.

    self.postOne = Widgets.Button(buchen.content, L.DKP_POST_ONE, function()
        DkpFrame:Post(false)
    end, "primary")
    self.postOne:SetHeight(22)
    self.postOne:SetWidth(170)
    -- Gesetzt wird in RelayoutPost.

    self.postRaid = Widgets.Button(buchen.content, L.DKP_POST_RAID, function()
        DkpFrame:Post(true)
    end)
    self.postRaid:SetHeight(22)
    self.postRaid:SetWidth(180)
    self.postRaid:SetPoint("LEFT", self.postOne, "RIGHT", 8, 0)

    -- Die Rueckmeldung auf EIGENER ZEILE. Neben den Knoepfen war kein
    -- Platz fuer einen Satz, und abgeschnitten sagt er nichts.
    self.status = Theme.Label(buchen.content, "", fonts.small, Theme.color.textFaint)
    self.status:SetJustifyH("LEFT")

    if type(_G.UISpecialFrames) == "table" then
        table.insert(_G.UISpecialFrames, "GuildArmoryDkpFrame")
    end

    self.frame = frame
    return frame
end

-- DKPPOST LAYOUT ANFANG (herausgeschnitten von tools/test/dkplayout.test.js)

--- Setzt den Buchungsblock neu und misst dabei den Hinweistext.
---
--- ER IST DAS EINZIGE UMBRECHENDE HIER, und wie oft er umbricht, haengt an
--- Sprache, Schriftgroesse und Fensterbreite. Eine feste Hoehe dafuer ist
--- eine Wette auf alle drei — im ersten Anlauf lief der Text unten aus dem
--- Fenster heraus, waehrend die Knoepfe darueber standen.
---
--- Die Panelhoehe faellt hinten heraus, und die Listen daruber richten
--- sich danach. Andersherum waere der Block das, was uebrig bleibt.
--- @return boolean gemessen
function DkpFrame:RelayoutPost()
    local panel = self.postPanel
    if not panel then return false end

    local stapel = Widgets.Stack(panel.content)
    if not stapel then return false end

    -- Die Eingabezeile steht schon nebeneinander; hier zaehlt nur ihre
    -- Hoehe.
    if self.amount then
        stapel:Add(self.amount, 2, 0)
    end

    stapel:Text(self.hint, 2, 8)
    stapel:Row({ self.postOne, self.postRaid }, 2, 8)
    stapel:Text(self.status, 2, 6)

    local noetig = stapel:Height() + 24 + 16
    if math.abs((panel:GetHeight() or 0) - noetig) > 0.5 then
        panel:SetHeight(noetig)

        -- Die Listen enden ueber dem Block. Beide an DERSELBEN Kante,
        -- sonst stehen sie verschieden hoch.
        if self.standingsPanel then
            self.standingsPanel:SetPoint("BOTTOM", self.frame, "BOTTOM",
                0, PAD + noetig + GAP)
        end
    end

    return true
end

-- DKPPOST LAYOUT ENDE

-- ================================================================== Rechte ---

--- Darfst du buchen?
---
--- Dieselbe Schwelle wie bei den Lootregeln: Plündermeister und
--- Administrator. Ansehen darf jeder — der eigene Stand geht jeden etwas
--- an, der damit bietet.
function DkpFrame:MayPost()
    local identity = Compat.GetPlayerIdentity()
    if not identity.guid then return false, "noguid" end
    if GA.Core.Database:HasAtLeast(identity.guid, GA.const.ROLE_LOOTMASTER) then
        return true
    end
    return false, "role"
end

-- ================================================================== Buchen ---

--- Bucht auf den Gewaehlten oder auf den ganzen Raid.
function DkpFrame:Post(anDenRaid)
    local Dkp = GA.Modules.Dkp
    if not Dkp then return end

    local darf, grund = self:MayPost()
    if not darf then
        self.status:SetText(L["DKP_LOCKED_" .. tostring(grund)] or L.DKP_LOCKED_role)
        return
    end

    local punkte = tonumber(self.amount and self.amount:GetText())
    local reason = self.reason and Util.Trim(self.reason:GetText() or "") or ""

    if not punkte or punkte == 0 then
        self.status:SetText(L.DKP_NEED_POINTS)
        return
    end
    if reason == "" then
        self.status:SetText(L.DKP_NEED_REASON)
        return
    end

    local ziele = {}
    if anDenRaid then
        -- WER WIRKLICH DA IST, nicht wer in der Gilde steht. Anwesenheit
        -- ist der Anlass, und die Gruppe ist ihr Beleg.
        for _, member in ipairs(Compat.GetGroupMembers and Compat.GetGroupMembers() or {}) do
            local character = member.name
                and GA.Core.Database:FindCharacterByName(member.name)
            if character then ziele[#ziele + 1] = character end
        end
    else
        local character = self.selected
            and GA.Core.Database.account.characters[self.selected]
        if character then ziele[#ziele + 1] = character end
    end

    if #ziele == 0 then
        self.status:SetText(anDenRaid and L.DKP_NO_RAID or L.DKP_NO_SELECTION)
        return
    end

    local gebucht = 0
    for _, character in ipairs(ziele) do
        if Dkp:Post(character.guid, character.name, punkte, Dkp.KIND.ADJUST, reason) then
            gebucht = gebucht + 1
        end
    end

    self.status:SetText(string.format(L.DKP_POSTED_COUNT, punkte, gebucht))
    if self.amount then self.amount:SetText("") end
    self:Refresh()
end

-- ================================================================== Anzeige --

function DkpFrame:RefreshButtons()
    local darf = self:MayPost()
    local punkte = tonumber(self.amount and self.amount:GetText())
    local reason = self.reason and Util.Trim(self.reason:GetText() or "") or ""
    local bereit = darf and punkte and punkte ~= 0 and reason ~= ""

    -- Ein Knopf, der nichts bewirkt, laedt trotzdem zum Druecken ein. Ohne
    -- Betrag oder Grund passiert nichts — also bleibt er aus.
    for _, button in ipairs({ self.postOne, self.postRaid }) do
        if button and button.SetEnabledState then
            button:SetEnabledState(bereit and true or false)
        end
    end
end

function DkpFrame:Refresh()
    if not self.frame then return end
    local Dkp = GA.Modules.Dkp
    if not Dkp then return end

    local liste = Dkp:List()
    for _, stand in ipairs(liste) do
        local character = GA.Core.Database.account.characters[stand.guid]
        stand.class = character and character.class
    end
    self.players:SetData(liste)

    local stand = self.selected and Dkp:Standing(self.selected)
    if stand then
        self.ledgerPanel:SetTitle(string.format(L.DKP_LEDGER_OF,
            tostring(stand.name), stand.total, stand.earned, stand.spent))
    else
        self.ledgerPanel:SetTitle(L.DKP_LEDGER)
    end
    self.ledger:SetData(self.selected and Dkp:History(self.selected, 200) or {})

    local darf, grund = self:MayPost()
    if not darf then
        self.status:SetText(L["DKP_LOCKED_" .. tostring(grund)] or L.DKP_LOCKED_role)
    end
    self:RefreshButtons()

    -- Zuletzt: Der Hinweis und die Rueckmeldung koennen sich geaendert
    -- haben, und beide brechen um.
    self:RelayoutPost()
end

function DkpFrame:Open()
    self:Create()
    if not self.selected then
        self.selected = Compat.GetPlayerIdentity().guid
    end
    self:Refresh()
    self.frame:Show()
end

function DkpFrame:Hide()
    if self.frame then self.frame:Hide() end
end

function DkpFrame:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Open() end
end
