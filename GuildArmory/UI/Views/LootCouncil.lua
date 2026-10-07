--[[----------------------------------------------------------------------------
    Views/LootCouncil — der Beutetisch: die Ansicht des Lootmeisters und des
    Councils.

    Entwurf L2 (27.09.2026): OBEN die Gegenstaende als Karten nebeneinander,
    wie sie vom Boss fallen — Qualitaetskante, Symbol, Name, Platz, Stand,
    Zahl der Gebote. DARUNTER die Bewerber auf den gewaehlten Gegenstand,
    NACH ANTWORT GRUPPIERT: Best in Slot zuerst, dann Main-Spec, dann der
    Rest; innerhalb einer Gruppe steht oben, wer am wenigsten hat. RECHTS
    die Entscheidung: wer fuehrt, wie die Stimmen liegen, ein Knopf — und
    darunter die Fakten zum Gegenstand (Reservierung, Rotation, Nachweis,
    Alter, Herkunft), die man sonst zusammensuchen muesste.

    DER WICHTIGSTE KNOPF IST "VERGEBEN", UND ER MACHT ZWEI DINGE GETRENNT:

      1. Die Entscheidung festhalten (Awards:Award -> AWARDED). Das ist die
         Buchung: Wer hat den Zuschlag bekommen, mit welcher Antwort.
      2. Die Uebergabe anstossen — per Pluendermeister, wenn das Lootfenster
         offen und der Spieler Pluendermeister ist, sonst gar nicht.

    Beides ist bewusst nicht dasselbe. Ein Zuschlag ohne Uebergabe bleibt als
    "Uebergabe offen" stehen, bis ein Ereignis sie bestaetigt. Das Addon
    verbucht nichts als erhalten, nur weil jemand auf "Vergeben" gedrueckt hat.

    GiveMasterLoot ist eine geschuetzte Funktion: Der Aufruf muss aus dem Klick
    heraus erfolgen. Deshalb passiert er hier direkt im OnClick und nicht in
    einem spaeteren Rueckruf.

    WER FUEHRT, SAGT DIE ANSICHT — ENTSCHEIDEN TUT SIE NICHT. Der Fuehrende
    ist, wer strikt die meisten Stimmen hat (Council), das hoechste Gebot
    (DKP) oder den hoechsten Wurf in der hoechsten Stufe (Wurf). Bei
    Gleichstand steht niemand vorn, und der Knopf ist aus: Das Addon pickt
    nicht heimlich den Erstgenannten.
------------------------------------------------------------------------------]]

local _, GA = ...

local LootCouncil = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

LootCouncil.titleKey = "NAV_LOOTCOUNCIL"

local Status = GA.Data.Schema.LootStatus

--- Die Karten oben: so breit, wie der Platz es zulaesst, zwischen zwei
--- Grenzen. Passen nicht alle, blaettern zwei Pfeile — eine Karte, die
--- auf 60 Pixel gequetscht ist, sagt nichts mehr.
local CARD_H = 72
local CARD_MIN, CARD_MAX, CARD_GAP = 132, 210, 6
local ARROW_W = 22

local DECISION_W = 220
local BAR_WIDTH = 30

--- Als Funktion, nicht als Tabelle: Die Beschriftungen tragen die Sprache,
--- die bei PLAYER_LOGIN feststeht, nicht die vom Laden. Die Breiten stehen
--- HIER und nirgends sonst; Kopfzeile und Zeilen rechnen aus derselben Liste.
local COLUMN_GAP = 6
local COLUMN_X0 = 8

local function candidateColumns()
    return {
        { key = "crest",   label = "",            width = 16 },
        { key = "name",    label = L.COL_NAME,    width = 110 },
        { key = "value",   label = "",            width = 56 },
        { key = "ilvl",    label = L.COL_ILVL,    width = 62, justify = "RIGHT" },
        { key = "plus",    label = "+1",          width = 26, justify = "RIGHT" },
        { key = "note",    label = "",            width = 80 },
        { key = "votes",   label = L.COUNCIL_VOTE, width = 30, justify = "RIGHT" },
    }
end

local function columnOffsets(columns)
    local x, out, breiten = COLUMN_X0, {}, {}
    for _, column in ipairs(columns) do
        out[column.key] = x
        breiten[column.key] = column.width
        x = x + column.width + COLUMN_GAP
    end
    return out, breiten
end

--- Plündermethode als Wort. Die Werte kommen vom Client (GetLootMethod)
--- und sind auf jeder Linie dieselben Kennwoerter.
local LOOT_METHOD_KEYS = {
    freeforall = "LOOT_FREEFORALL", roundrobin = "LOOT_ROUNDROBIN",
    master = "LOOT_MASTER", group = "LOOT_GROUP",
    needbeforegreed = "LOOT_NBG", personalloot = "LOOT_PERSONAL",
}

-- ================================================================== Aufbau ----

function LootCouncil:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Werkzeugzeile ---
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(24)

    self.state = Theme.Label(bar, "", fonts.body, Theme.color.goldBright)
    self.state:SetPoint("LEFT", bar, "LEFT", 2, 0)

    self.closeButton = Widgets.Button(bar, L.COUNCIL_CLOSE, function()
        local session = GA.Modules.Session:Current()
        if session then GA.Modules.Session:Close(session.id, "vom Lootmeister beendet") end
        self:Refresh()
    end)
    self.closeButton:SetTooltip(L.TT_COUNCIL_CLOSE)
    self.closeButton:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    self.openButton = Widgets.Button(bar, L.COUNCIL_OPEN, function()
        self:OpenSession()
    end, "primary")
    self.openButton:SetTooltip(L.TT_COUNCIL_OPEN)
    self.openButton:SetPoint("RIGHT", self.closeButton, "LEFT", -6, 0)

    -- Rotation: Sitze auf Zeit fuer Leute aus dem Schlachtzug.
    self.rotateButton = Widgets.Button(bar, L.ROTATION_ROTATE, function()
        local ok, result = GA.Modules.Rotation:Rotate()
        if not ok then
            GA.Core.Debug:Info("%s",
                L["ROTATION_ERR_" .. string.upper(tostring(result))] or tostring(result))
        end
        self:Refresh()
    end)
    self.rotateButton:SetTooltip(L.TT_ROTATION_ROTATE)
    self.rotateButton:SetPoint("RIGHT", self.openButton, "LEFT", -6, 0)

    -- DAS GEBOTSFENSTER WIEDER AUFMACHEN.
    --
    -- Es geht von selbst auf, wenn eine Sitzung angekuendigt wird — und es
    -- hat ein Schliesskreuz. Wer darauf drueckt, kam bisher nicht mehr
    -- hin: Die Ankuendigung kommt kein zweites Mal. Ein Fenster, das man
    -- schliessen, aber nicht wieder oeffnen kann, ist eine Falle.
    self.bidButton = Widgets.Button(bar, L.COUNCIL_REOPEN_BID, function()
        self:ReopenBidFrame()
    end)
    self.bidButton:SetTooltip(L.TT_COUNCIL_REOPEN_BID)
    self.bidButton:SetPoint("RIGHT", self.rotateButton, "LEFT", -6, 0)

    -- EINEN ERKANNTEN GEGENSTAND WIEDER HERAUSNEHMEN.
    --
    -- Gewuenscht am 26.09.2026, zusammen mit der Meldung, dass mancher Fund
    -- mehrfach in der Liste stand. Das ist behoben, aber der Knopf bleibt
    -- richtig: Es wird immer etwas darauf landen, das nicht zur Vergabe
    -- gehoert — ein Teil, das der Raid gar nicht verteilt, ein Fehlgriff,
    -- ein Test.
    --
    -- GELOESCHT WIRD NICHTS. Der Eintrag geht auf CANCELLED und bleibt
    -- damit im Journal stehen. Wer spaeter fragt, warum ein Teil nie
    -- vergeben wurde, bekommt eine Antwort statt einer Luecke — und wer
    -- sich verdrueckt, hat nichts unwiederbringlich zerstoert.
    self.removeButton = Widgets.Button(bar, L.COUNCIL_REMOVE, function()
        self:RemoveSelected()
    end)
    self.removeButton:SetTooltip(L.TT_COUNCIL_REMOVE)
    self.removeButton:SetPoint("RIGHT", self.bidButton, "LEFT", -6, 0)

    -- ALLE AUF EINMAL.
    --
    -- Gewuenscht am 26.09.2026, nach einem Abend mit 22 Eintraegen, von
    -- denen die Haelfte Doppel waren. Einzeln wegzuklicken ist Arbeit, die
    -- ein Fehler verursacht hat.
    --
    -- ZWEI DRUECKE, NICHT EINER. Der Knopf fragt erst nach und raeumt beim
    -- zweiten Mal weg; nach zehn Sekunden ohne Bestaetigung vergisst er es
    -- wieder. Ein einzelner Fehlgriff darf keine Liste leeren, auf der der
    -- Abend steht — und ein Bestaetigungsfenster waere fuer etwas,
    -- das im Journal nachvollziehbar bleibt, zu viel.
    self.removeAllButton = Widgets.Button(bar, L.COUNCIL_REMOVE_ALL, function()
        self:RemoveAll()
    end)
    self.removeAllButton:SetTooltip(L.TT_COUNCIL_REMOVE_ALL)
    self.removeAllButton:SetPoint("RIGHT", self.removeButton, "LEFT", -6, 0)

    -- AUS DEM BEUTEL AUF DIE LISTE.
    --
    -- Gewuenscht am 26.09.2026: Wer als Pluendermeister eingesammelt hat,
    -- hat den Abend im Beutel und nicht in der Liste. Auch hier zwei
    -- Druecke — der erste zeigt im Chat, WAS hereinkaeme.
    self.addAllButton = Widgets.Button(bar, L.COUNCIL_ADD_ALL, function()
        self:AddAllFromBags()
    end)
    self.addAllButton:SetTooltip(L.TT_COUNCIL_ADD_ALL)
    self.addAllButton:SetPoint("RIGHT", self.removeAllButton, "LEFT", -6, 0)

    -- Der Stand der Rotation gehoert neben den Knopf und nicht in ein
    -- Untermenue: Wer nicht sieht, wer gerade mitstimmt, kann die Abstimmung
    -- nicht einordnen.
    self.rotationState = Theme.Label(bar, "", fonts.small, Theme.color.textDim)
    self.rotationState:SetPoint("LEFT", self.state, "RIGHT", 10, 0)
    self.rotationState:SetPoint("RIGHT", self.addAllButton, "LEFT", -8, 0)
    self.rotationState:SetJustifyH("LEFT")

    -- Stand der Reservierungen. Steht unter der Werkzeugleiste und nicht in
    -- einem Untermenue: Wer nicht sieht, dass eine Runde laeuft, vergibt
    -- reservierte Gegenstaende nebenbei.
    self.softResState = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.softResState:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -2)
    self.softResState:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    self.softResState:SetJustifyH("LEFT")
    self.softResState:SetHeight(12)

    -- ------------------------------------------------------ Kartenleiste ----
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", self.softResState, "BOTTOMLEFT", -2, -4)
    strip:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    strip:SetHeight(CARD_H)
    self.strip = strip
    self.cards = {}
    self.cardOffset = 0

    self.prevButton = Widgets.Button(strip, "<", function()
        self.cardOffset = math.max(0, self.cardOffset - 1)
        self:Refresh()
    end)
    self.prevButton:SetTooltip(L.TT_COUNCIL_PREV)
    self.prevButton:SetWidth(ARROW_W) self.prevButton:SetHeight(CARD_H)
    self.prevButton:SetPoint("LEFT", strip, "LEFT", 0, 0)
    self.prevButton:Hide()

    self.nextButton = Widgets.Button(strip, ">", function()
        self.cardOffset = self.cardOffset + 1
        self:Refresh()
    end)
    self.nextButton:SetTooltip(L.TT_COUNCIL_NEXT)
    self.nextButton:SetWidth(ARROW_W) self.nextButton:SetHeight(CARD_H)
    self.nextButton:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    self.nextButton:Hide()

    -- Ohne Gegenstaende: ein Satz statt einer leeren Leiste.
    self.stripHint = Theme.Label(strip, "", fonts.body, Theme.color.textFaint)
    self.stripHint:SetPoint("CENTER", strip, "CENTER", 0, 0)

    -- ------------------------------------------------------ Entscheidung ----
    local decision = Widgets.Panel(frame, L.COUNCIL_DECISION)
    decision:SetWidth(DECISION_W)
    decision:SetHeight(24 + 206)
    decision:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -gap)
    self.decisionPanel = decision
    self:BuildDecision(decision.content, fonts)

    local facts = Widgets.Panel(frame, L.COUNCIL_ABOUT_ITEM)
    facts:SetPoint("TOPLEFT", decision, "BOTTOMLEFT", 0, -gap)
    facts:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.factsPanel = facts
    self:BuildFacts(facts.content)

    -- ------------------------------------------------------ Bewerber --------
    local bidPanel = Widgets.Panel(frame, L.COUNCIL_CANDIDATES)
    bidPanel:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -gap)
    bidPanel:SetPoint("BOTTOMRIGHT", decision, "BOTTOMLEFT", -gap, 0)
    bidPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, pad)
    self.bidPanel = bidPanel

    self.collapsed = { PASS = true }

    self.candidates = Widgets.ScrollList(bidPanel.content, {
        emptyText = L.COUNCIL_BIDS_EMPTY,
        rowHeight = 26,
        columns = candidateColumns(),
        createRow = function(row) self:BuildCandidateRow(row) end,
        updateRow = function(row, entry) self:UpdateCandidateRow(row, entry) end,
        onClickRow = function(entry)
            -- Eine Gruppe klappt auf Klick zu und wieder auf.
            if entry.group then
                self.collapsed[entry.key] = not self.collapsed[entry.key]
                self:Refresh()
            end
        end,
    })
    self.candidates:SetPoint("TOPLEFT", bidPanel.content, "TOPLEFT", 0, 0)
    self.candidates:SetPoint("BOTTOMRIGHT", bidPanel.content, "BOTTOMRIGHT", 0, 22)

    self.footer = Theme.Label(bidPanel.content, "", fonts.small, Theme.color.textFaint)
    self.footer:SetPoint("BOTTOMLEFT", bidPanel.content, "BOTTOMLEFT", 2, 2)
    self.footer:SetPoint("RIGHT", bidPanel.content, "RIGHT", -2, 0)
    self.footer:SetJustifyH("LEFT")

    self.frame = frame
    return frame
end

-- ================================================================== Karten ----

--- Baut eine Karte der Leiste. Einmal je Platz; danach wird nur gesetzt.
function LootCouncil:BuildCard(index)
    if self.cards[index] then return self.cards[index] end
    local fonts = Theme.Fonts()

    local card = CreateFrame("Button", nil, self.strip)
    card:SetHeight(CARD_H)
    card.background = Theme.Fill(card, Theme.color.panelBg)
    card.lines = Theme.Outline(card, Theme.color.border)

    -- Die Qualitaetskante oben: Das ist die eine Farbe, die jeder im Raid
    -- ohne Lesen versteht.
    card.edge = card:CreateTexture(nil, "OVERLAY")
    card.edge:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.edge:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.edge:SetHeight(3)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetWidth(30) card.icon:SetHeight(30)
    card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -10)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.name = Theme.Label(card, "", fonts.row, Theme.color.text)
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -1)
    card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    card.slot = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.slot:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.slot:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.slot:SetJustifyH("LEFT")
    card.slot:SetWordWrap(false)

    card.tag = Theme.Label(card, "", fonts.small, Theme.color.textFaint)
    card.tag:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 7)
    card.tag:SetPoint("RIGHT", card, "RIGHT", -40, 0)
    card.tag:SetJustifyH("LEFT")
    card.tag:SetWordWrap(false)

    card.badge = CreateFrame("Frame", nil, card)
    card.badge:SetWidth(26) card.badge:SetHeight(16)
    card.badge:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 6)
    card.badgeFill = Theme.Fill(card.badge, Theme.color.goldDeep)
    card.badgeText = Theme.Label(card.badge, "", fonts.rowBold, Theme.color.goldBright)
    card.badgeText:SetPoint("CENTER", card.badge, "CENTER", 0, 0)

    card:SetScript("OnClick", function(button)
        if button.award then
            self.selectedAwardId = button.award.id
            self:Refresh()
        end
    end)
    card:SetScript("OnEnter", function(button)
        if button.award then
            Widgets.ShowItemTooltip(button, button.award.itemID, button.award.itemLink)
        end
        if not button.selected then Theme.Paint(button.background, Theme.color.rowHover) end
    end)
    card:SetScript("OnLeave", function(button)
        Widgets.HideItemTooltip()
        if not button.selected then Theme.Paint(button.background, Theme.color.panelBg) end
    end)

    self.cards[index] = card
    return card
end

--- Fuellt eine Karte mit einem Eintrag.
function LootCouncil:UpdateCard(card, award)
    card.award = award
    local info = award.itemID and Compat.GetItemInfo(award.itemLink or award.itemID)
    if info and info.icon then card.icon:SetTexture(info.icon) card.icon:Show() else card.icon:Hide() end

    local quality = Theme.QualityColor(award.quality or (info and info.quality))
    Theme.Paint(card.edge, quality)

    card.name:SetText(award.itemName or (info and info.name) or ("#" .. tostring(award.itemID)))
    card.name:SetTextColor(quality[1], quality[2], quality[3])
    if award.test then
        card.name:SetText(L.TEST_MARK .. "  " .. (card.name:GetText() or ""))
        card.name:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
    end

    -- Platz, Art, Itemlevel — was der Client dazu weiss, in seiner Sprache.
    local teile = {}
    if info then
        local ort = Compat.EquipLocName(info.equipLoc)
        if ort then teile[#teile + 1] = ort end
        if info.subType and info.subType ~= "" then teile[#teile + 1] = info.subType end
        local level = Compat.GetItemLevelOf(info.link) or info.itemLevel
        if level and level > 0 then teile[#teile + 1] = tostring(level) end
    end
    card.slot:SetText(table.concat(teile, " · "))

    -- Der Stand: Gebote offen, vergeben an, oder der Status als Wort.
    local session = GA.Modules.Session:Current()
    local gebote = 0
    if award.status == Status.SESSION_OPEN and session then
        gebote = #GA.Modules.Session:Tally(session.id, award.id)
        card.tag:SetText(L.LOOT_STATUS_SESSION_OPEN)
        card.tag:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
    elseif award.recipientName then
        card.tag:SetText(Util.ShortName(award.recipientName))
        local farbe = award.status == Status.TRANSFER_PENDING and Theme.color.warn or Theme.color.jade
        card.tag:SetTextColor(farbe[1], farbe[2], farbe[3])
    else
        card.tag:SetText(L["LOOT_STATUS_" .. tostring(award.status)] or "")
        card.tag:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    if gebote > 0 then
        card.badgeText:SetText(tostring(gebote))
        card.badge:Show()
    else
        card.badge:Hide()
    end

    card.selected = (award.id == self.selectedAwardId)
    if card.selected then
        Theme.Paint(card.background, Theme.color.rowHover)
        for _, line in ipairs(card.lines) do Theme.Paint(line, Theme.color.gold) end
    else
        Theme.Paint(card.background, Theme.color.panelBg)
        for _, line in ipairs(card.lines) do Theme.Paint(line, Theme.color.border) end
    end
end

--- Legt die Karten in die Leiste: so viele, wie passen, der Rest blaettert.
function LootCouncil:RefreshCards(list)
    local strip = self.strip
    local breite = strip:GetWidth()
    if not breite or breite < CARD_MIN then breite = 700 end

    local anzahl = #list
    self.stripHint:SetShown(anzahl == 0)
    if anzahl == 0 then
        self.stripHint:SetText(GA.Modules.Session:Current() and L.COUNCIL_PICK_ITEM or L.COUNCIL_HINT)
    end

    -- Passen alle? Sonst Platz fuer die Pfeile abziehen und neu zaehlen.
    local frei = breite
    local passen = math.max(1, math.floor((frei + CARD_GAP) / (CARD_MIN + CARD_GAP)))
    local blaettern = anzahl > passen
    if blaettern then
        frei = breite - 2 * (ARROW_W + 4)
        passen = math.max(1, math.floor((frei + CARD_GAP) / (CARD_MIN + CARD_GAP)))
    end

    local sichtbar = math.min(anzahl, passen)
    local maxOffset = math.max(0, anzahl - sichtbar)
    if self.cardOffset > maxOffset then self.cardOffset = maxOffset end

    -- Die gewaehlte Karte bleibt im Bild: Wer eine Karte waehlt, will sie
    -- sehen, nicht suchen.
    if self.selectedAwardId then
        for index, award in ipairs(list) do
            if award.id == self.selectedAwardId then
                if index - 1 < self.cardOffset then self.cardOffset = index - 1 end
                if index > self.cardOffset + sichtbar then self.cardOffset = index - sichtbar end
                break
            end
        end
    end

    local cardW = sichtbar > 0
        and math.min(CARD_MAX, math.floor((frei - (sichtbar - 1) * CARD_GAP) / sichtbar))
        or CARD_MIN
    local x0 = blaettern and (ARROW_W + 4) or 0

    for slot = 1, sichtbar do
        local card = self:BuildCard(slot)
        card:ClearAllPoints()
        card:SetWidth(cardW)
        card:SetPoint("TOPLEFT", strip, "TOPLEFT", x0 + (slot - 1) * (cardW + CARD_GAP), 0)
        self:UpdateCard(card, list[self.cardOffset + slot])
        card:Show()
    end
    for slot = sichtbar + 1, #self.cards do self.cards[slot]:Hide() end

    self.prevButton:SetShown(blaettern)
    self.nextButton:SetShown(blaettern)
    if blaettern then
        self.prevButton:SetEnabledState(self.cardOffset > 0)
        self.nextButton:SetEnabledState(self.cardOffset < maxOffset)
        self.nextButton.tooltip = self.cardOffset < maxOffset
            and string.format(L.COUNCIL_MORE, maxOffset - self.cardOffset) or nil
    end
end

-- ================================================================== Zeilen ----

--- Eine Zeile hat ZWEI GESICHTER: Gruppenkopf oder Bewerber. Beide werden
--- einmal gebaut und je nach Eintrag gezeigt — zwei Zeilenvorraete in einer
--- Liste kaemen sich beim Umschalten ins Gehege.
function LootCouncil:BuildCandidateRow(row)
    local fonts = Theme.Fonts()
    local x, w = columnOffsets(candidateColumns())

    -- Gruppenkopf
    row.groupBar = row:CreateTexture(nil, "ARTWORK")
    row.groupBar:SetWidth(3) row.groupBar:SetHeight(12)
    row.groupBar:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.groupLabel = Theme.Label(row, "", fonts.heading, Theme.color.heading)
    row.groupLabel:SetPoint("LEFT", row, "LEFT", 17, 0)

    row.groupCount = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.groupCount:SetPoint("LEFT", row.groupLabel, "RIGHT", 6, 0)

    row.groupHint = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.groupHint:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    -- Bewerber
    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(14) row.crest:SetHeight(14)
    row.crest:SetPoint("LEFT", row, "LEFT", x.crest, 0)

    row.name = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", x.name, 0)
    row.name:SetWidth(w.name)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Wurf oder Gebot — nur dort, wo es eines gibt. Die Antwort selbst
    -- steht ueber der Gruppe, nicht in jeder Zeile noch einmal.
    row.value = Theme.Label(row, "", fonts.small, Theme.color.gold)
    row.value:SetPoint("LEFT", row, "LEFT", x.value, 0)
    row.value:SetWidth(w.value)
    row.value:SetJustifyH("LEFT")

    row.barBg = row:CreateTexture(nil, "ARTWORK")
    Theme.BarTrough(row.barBg)
    row.barBg:SetWidth(BAR_WIDTH) row.barBg:SetHeight(5)
    row.barBg:SetPoint("LEFT", row, "LEFT", x.ilvl, 0)

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(row.barFill, Theme.color.goldDim)
    row.barFill:SetHeight(5)
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)

    row.ilvl = Theme.Label(row, "", fonts.rowBold, Theme.color.text)
    row.ilvl:SetPoint("LEFT", row, "LEFT", x.ilvl + BAR_WIDTH + 4, 0)
    row.ilvl:SetWidth(w.ilvl - BAR_WIDTH - 4)
    row.ilvl:SetJustifyH("RIGHT")

    row.plusOne = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.plusOne:SetPoint("LEFT", row, "LEFT", x.plus, 0)
    row.plusOne:SetWidth(w.plus)
    row.plusOne:SetJustifyH("RIGHT")

    -- Der Hinweis nimmt, was bis zu den Stimmen frei ist.
    row.note = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.note:SetPoint("LEFT", row, "LEFT", x.note, 0)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)

    row.award = Widgets.Button(row, L.COUNCIL_AWARD, function()
        if row.item and not row.item.group then LootCouncil:Award(row.item.name) end
    end, "primary")
    row.award:SetTooltip(L.TT_COUNCIL_AWARD)
    row.award:SetHeight(18)
    row.award:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.vote = Widgets.Button(row, L.COUNCIL_VOTE, function()
        if row.item and not row.item.group then LootCouncil:Vote(row.item.name) end
    end)
    row.vote:SetTooltip(L.TT_COUNCIL_VOTE)
    row.vote:SetHeight(18)
    row.vote:SetPoint("RIGHT", row.award, "LEFT", -4, 0)

    row.votes = Theme.Label(row, "", fonts.rowBold, Theme.color.goldBright)
    row.votes:SetPoint("RIGHT", row.vote, "LEFT", -8, 0)
    row.votes:SetWidth(w.votes)
    row.votes:SetJustifyH("RIGHT")
    row.note:SetPoint("RIGHT", row.votes, "LEFT", -6, 0)

    row.candidateWidgets = { row.crest, row.name, row.value, row.barBg, row.barFill,
        row.ilvl, row.plusOne, row.note, row.award, row.vote, row.votes }
    row.groupWidgets = { row.groupBar, row.groupLabel, row.groupCount, row.groupHint }
end

local function zeigeAlle(liste, an)
    for _, element in ipairs(liste) do
        if an then element:Show() else element:Hide() end
    end
end

function LootCouncil:UpdateCandidateRow(row, entry)
    if entry.group then
        zeigeAlle(row.candidateWidgets, false)
        zeigeAlle(row.groupWidgets, true)
        Theme.Paint(row.background, Theme.color.windowBg)
        Theme.Paint(row.groupBar, entry.color)
        row.groupLabel:SetText(string.upper(entry.label or ""))
        row.groupLabel:SetTextColor(entry.color[1], entry.color[2], entry.color[3])
        row.groupCount:SetText("· " .. tostring(entry.count))
        row.groupHint:SetText(entry.hint or "")
        return
    end

    zeigeAlle(row.groupWidgets, false)
    zeigeAlle(row.candidateWidgets, true)

    local candidate = entry
    local r, g, b = Theme.ClassColor(candidate.class)
    if candidate.class and Theme.SetClassPortrait(row.crest, candidate.class) then
        row.crest:Show()
    else
        row.crest:Hide()
    end
    row.name:SetText(candidate.name)
    row.name:SetTextColor(r, g, b)

    -- WURF UND GEBOT als Wert; ein versiegeltes Gebot bleibt versiegelt.
    local session = GA.Modules.Session:Current()
    local eigeneGuid = Compat.GetPlayerIdentity().guid
    local darfSehen = session ~= nil and eigeneGuid ~= nil and session.openedBy == eigeneGuid
    if candidate.dkp and not darfSehen then
        row.value:SetText(L.COUNCIL_SEALED)
        row.value:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
    elseif candidate.dkp then
        row.value:SetText(string.format(L.COUNCIL_DKP, candidate.dkp))
        row.value:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
    elseif candidate.roll then
        row.value:SetText(string.format("%d / %s", candidate.roll, tostring(candidate.rollMax or "?")))
        row.value:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
    else
        row.value:SetText("")
    end

    -- Itemlevel: Zahl immer, Balken gegen das beste unter den Bewerbern.
    -- Ungemessen ist nicht null: Strich, kein Balken.
    if candidate.itemLevel then
        row.ilvl:SetText(string.format("%.0f", candidate.itemLevel))
        local anteil = (self.bestIlvl or 0) > 0 and (candidate.itemLevel / self.bestIlvl) or 0
        row.barFill:SetWidth(math.max(1, math.floor(BAR_WIDTH * math.min(1, anteil))))
        row.barBg:Show() row.barFill:Show()
    else
        row.ilvl:SetText("—")
        row.barBg:Hide() row.barFill:Hide()
    end

    local award = self.selectedAwardId and GA.Modules.Awards:Get(self.selectedAwardId)
    local wish = award and award.itemID
        and GA.Modules.Wishlist:ForCandidate(award.itemID, candidate.name) or nil

    local plus = candidate.guid and GA.Modules.PlusOne:For(candidate.guid)
    if plus then
        row.plusOne:SetText("+" .. tostring(plus.total))
        local color = plus.total == 0 and Theme.color.jade or Theme.color.textDim
        row.plusOne:SetTextColor(color[1], color[2], color[3])
    else
        row.plusOne:SetText("")
    end

    local reserved
    for _, eintrag in ipairs(award and award.itemID
        and GA.Modules.SoftRes:For(award.itemID) or {}) do
        if Util.NormalizeName(eintrag.name) == Util.NormalizeName(candidate.name) then
            reserved = eintrag
            break
        end
    end

    local parts = {}
    if candidate.note and candidate.note ~= "" then parts[#parts + 1] = candidate.note end
    if reserved then
        parts[#parts + 1] = string.format(L.COUNCIL_RESERVED,
            reserved.origin == "claim" and L.SOFTRES_ORIGIN_CLAIM or L.SOFTRES_ORIGIN_LIST)
    end
    if wish then
        local priority = GA.Modules.Wishlist:PriorityByKey(wish.priority)
        local label = string.format(L.COUNCIL_ON_WISHLIST, priority and priority.label or wish.priority)
        if wish.fulfilled then label = label .. " " .. L.COUNCIL_WISH_DONE end
        parts[#parts + 1] = label
    end
    row.note:SetText(table.concat(parts, "  ·  "))
    local noteColor = Theme.color.textFaint
    if reserved then noteColor = Theme.color.goldBright
    elseif wish and not wish.fulfilled then noteColor = Theme.color.jade end
    row.note:SetTextColor(noteColor[1], noteColor[2], noteColor[3])

    row.votes:SetText(candidate.votes > 0 and tostring(candidate.votes) or "")

    local identity = Compat.GetPlayerIdentity()
    row.vote:SetWidth(52)
    row.vote:SetEnabledState(GA.Modules.Session:CanVote(identity.guid), L.COUNCIL_NEED_COUNCIL)
    row.award:SetWidth(66)
    row.award:SetEnabledState(GA.Modules.Session:CanHost(identity.guid), L.COUNCIL_NEED_LOOTMASTER)
end

--- Ordnet die Bewerber in Gruppen nach Antwort und liefert die flache
--- Zeilenliste: Gruppenkopf, dann seine Zeilen — es sei denn, sie ist
--- zugeklappt.
---
--- REIHENFOLGE IN DER GRUPPE: Wer bietet, nach Gebot; wer wuerfelt, nach
--- Wurf; sonst NIEDRIGSTES ITEMLEVEL ZUERST, dann Stimmen, dann Name. Wer
--- am wenigsten hat, steht oben — das ist die Frage, die ein Council
--- stellt, und die Sortierung stellt sie, bevor jemand scrollt.
function LootCouncil:GroupRows(candidates)
    local Session = GA.Modules.Session
    local nachKey, reihe = {}, {}

    for _, candidate in ipairs(candidates) do
        local key, label, color, weight
        if candidate.dkp then
            key, label, color, weight = "DKP", L.DKP_TITLE, Theme.color.gold, 1000
        else
            local response = Session:ResponseByKey(candidate.response)
            key = tostring(candidate.response or "?")
            label = response and response.label or key
            color = response and response.color or Theme.color.textDim
            weight = candidate.weight or 0
        end
        if not nachKey[key] then
            nachKey[key] = { group = true, key = key, label = label, color = color,
                weight = weight, rows = {} }
            reihe[#reihe + 1] = nachKey[key]
        end
        table.insert(nachKey[key].rows, candidate)
    end

    table.sort(reihe, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.label < b.label
    end)

    local zeilen = {}
    for index, gruppe in ipairs(reihe) do
        table.sort(gruppe.rows, function(a, b)
            if a.dkp or b.dkp then return (a.dkp or -1) > (b.dkp or -1) end
            if a.roll or b.roll then return (a.roll or -1) > (b.roll or -1) end
            local ia, ib = a.itemLevel, b.itemLevel
            if ia ~= ib then
                if ia == nil then return false end
                if ib == nil then return true end
                return ia < ib
            end
            if a.votes ~= b.votes then return a.votes > b.votes end
            return a.name < b.name
        end)

        gruppe.count = #gruppe.rows
        gruppe.collapsed = self.collapsed[gruppe.key] and true or false
        if gruppe.collapsed then
            gruppe.hint = L.COUNCIL_GROUP_COLLAPSED
        elseif index == 1 and not (gruppe.rows[1] and (gruppe.rows[1].dkp or gruppe.rows[1].roll)) then
            gruppe.hint = L.COUNCIL_LOWEST_FIRST
        else
            gruppe.hint = ""
        end

        zeilen[#zeilen + 1] = gruppe
        if not gruppe.collapsed then
            for _, candidate in ipairs(gruppe.rows) do zeilen[#zeilen + 1] = candidate end
        end
    end
    return zeilen
end

-- ============================================================ Entscheidung ----

function LootCouncil:BuildDecision(content, fonts)
    self.leaderCrest = content:CreateTexture(nil, "ARTWORK")
    self.leaderCrest:SetWidth(28) self.leaderCrest:SetHeight(28)
    self.leaderCrest:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)

    self.leaderName = Theme.Label(content, "", fonts.big, Theme.color.heading)
    self.leaderName:SetPoint("TOPLEFT", self.leaderCrest, "TOPRIGHT", 8, 0)
    self.leaderName:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    self.leaderName:SetJustifyH("LEFT")
    self.leaderName:SetWordWrap(false)

    self.leaderMeta = Theme.Label(content, "", fonts.small, Theme.color.textDim)
    self.leaderMeta:SetPoint("TOPLEFT", self.leaderName, "BOTTOMLEFT", 0, -2)
    self.leaderMeta:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    self.leaderMeta:SetJustifyH("LEFT")
    self.leaderMeta:SetWordWrap(false)

    -- Drei Balken: die Stimmenverteilung auf einen Blick. Mehr als drei
    -- Namen sind keine Verteilung mehr, sondern die Liste links.
    self.tally = {}
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(14)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(40 + (index - 1) * 16))
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        row.name = Theme.Label(row, "", fonts.small, Theme.color.text)
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name:SetWidth(84)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.count = Theme.Label(row, "", fonts.rowBold, Theme.color.goldBright)
        row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.count:SetWidth(16)
        row.count:SetJustifyH("RIGHT")

        row.track = row:CreateTexture(nil, "ARTWORK")
        Theme.Paint(row.track, Theme.color.windowBg)
        row.track:SetHeight(6)
        row.track:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        row.track:SetPoint("RIGHT", row.count, "LEFT", -6, 0)

        row.fill = row:CreateTexture(nil, "OVERLAY")
        Theme.BarFill(row.fill, Theme.color.gold)
        row.fill:SetHeight(6)
        row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
        row.fill:SetWidth(1)

        row:Hide()
        self.tally[index] = row
    end

    self.votesCast = Theme.Label(content, "", fonts.small, Theme.color.textFaint)
    self.votesCast:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -90)
    self.votesCast:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    self.votesCast:SetJustifyH("LEFT")

    self.awardButton = Widgets.Button(content, L.COUNCIL_AWARD, function()
        if self.leader then LootCouncil:Award(self.leader.name) end
    end, "primary")
    self.awardButton:SetTooltip(L.TT_COUNCIL_AWARD)
    self.awardButton:SetHeight(26)
    self.awardButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -108)
    self.awardButton:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    self.awardNote = Theme.Label(content, L.COUNCIL_AWARD_NOTE, fonts.small, Theme.color.textFaint)
    self.awardNote:SetPoint("TOPLEFT", self.awardButton, "BOTTOMLEFT", 0, -6)
    self.awardNote:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    self.awardNote:SetJustifyH("LEFT")
    self.awardNote:SetSpacing(2)
end

--- Wer vorn liegt — oder niemand.
---
--- @return table|nil leader, string grund (wenn niemand)
function LootCouncil:Leader(candidates)
    if #candidates == 0 then return nil, L.COUNCIL_PICK_ITEM end
    local erster, zweiter = candidates[1], candidates[2]

    if erster.dkp then
        if zweiter and zweiter.dkp == erster.dkp then return nil, L.COUNCIL_TIE_VOTES end
        return erster
    end
    if erster.roll then
        if zweiter and zweiter.roll == erster.roll and zweiter.rollRank == erster.rollRank then
            return nil, L.COUNCIL_TIE_VOTES
        end
        return erster
    end

    -- Council: strikt die meisten Stimmen. Keine Stimme, kein Fuehrender.
    local beste, zahl = nil, 0
    for _, candidate in ipairs(candidates) do
        if candidate.votes > zahl then beste, zahl = candidate, candidate.votes
        elseif candidate.votes == zahl and zahl > 0 then beste = false end
    end
    if zahl == 0 then return nil, L.COUNCIL_NO_VOTES end
    if not beste then return nil, L.COUNCIL_TIE_VOTES end
    return beste
end

function LootCouncil:RefreshDecision(candidates, session)
    local leader, grund = self:Leader(candidates)
    self.leader = leader

    if leader then
        local r, g, b = Theme.ClassColor(leader.class)
        if leader.class and Theme.SetClassPortrait(self.leaderCrest, leader.class) then
            self.leaderCrest:Show()
        else
            self.leaderCrest:Hide()
        end
        self.leaderName:SetText(leader.name)
        self.leaderName:SetTextColor(r, g, b)

        local response = GA.Modules.Session:ResponseByKey(leader.response)
        local teile = {}
        if leader.dkp then teile[#teile + 1] = string.format(L.COUNCIL_DKP, leader.dkp)
        elseif leader.roll then teile[#teile + 1] = string.format("%d / %s", leader.roll, tostring(leader.rollMax or "?")) end
        if response then teile[#teile + 1] = response.label end
        if leader.itemLevel then teile[#teile + 1] = string.format("%s %.0f", L.COL_ILVL, leader.itemLevel) end
        self.leaderMeta:SetText(table.concat(teile, " · "))
    else
        self.leaderCrest:Hide()
        self.leaderName:SetText(grund or "")
        self.leaderName:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
        self.leaderMeta:SetText("")
    end

    -- Die Balken: nach Stimmen, die drei mit den meisten. Ohne eine
    -- einzige Stimme keine Balken — leere Balken sehen aus wie ein Ergebnis.
    local sortiert = {}
    for _, candidate in ipairs(candidates) do
        if candidate.votes > 0 then sortiert[#sortiert + 1] = candidate end
    end
    table.sort(sortiert, function(a, b)
        if a.votes ~= b.votes then return a.votes > b.votes end
        return a.name < b.name
    end)
    local meiste = sortiert[1] and sortiert[1].votes or 0
    for index, row in ipairs(self.tally) do
        local candidate = sortiert[index]
        if candidate then
            local r, g, b = Theme.ClassColor(candidate.class)
            row.name:SetText(candidate.name)
            row.name:SetTextColor(r, g, b)
            row.count:SetText(tostring(candidate.votes))
            local breite = row.track:GetWidth()
            if not breite or breite <= 0 then breite = 80 end
            row.fill:SetWidth(math.max(1, breite * candidate.votes / meiste))
            row:Show()
        else
            row:Hide()
        end
    end

    local abgegeben = session and self.selectedAwardId
        and GA.Modules.Session:VoteCount(session.id, self.selectedAwardId) or 0
    self.votesCast:SetText(string.format(L.COUNCIL_VOTES_CAST, abgegeben))

    local identity = Compat.GetPlayerIdentity()
    local canHost = GA.Modules.Session:CanHost(identity.guid)
    self.awardButton:SetLabel(leader
        and string.format(L.COUNCIL_AWARD_TO, Util.ShortName(leader.name)) or L.COUNCIL_AWARD)
    self.awardButton:SetEnabledState(canHost and leader ~= nil,
        (not canHost) and L.COUNCIL_NEED_LOOTMASTER or grund)
end

-- ================================================================== Fakten ----

function LootCouncil:BuildFacts(content)
    self.facts = {}
    local keys = { "softres", "rotation", "proof", "detected", "source", "method" }
    local labels = {
        softres = L.COUNCIL_FACT_SOFTRES, rotation = L.COUNCIL_FACT_ROTATION,
        proof = L.COUNCIL_FACT_PROOF, detected = L.COUNCIL_FACT_DETECTED,
        source = L.COUNCIL_FACT_SOURCE, method = L.COUNCIL_FACT_METHOD,
    }
    local vorige
    for _, key in ipairs(keys) do
        local row = Widgets.KeyValue(content, labels[key], "")
        if vorige then
            row:SetPoint("TOPLEFT", vorige, "BOTTOMLEFT", 0, -4)
        else
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row.value:SetWidth(120)
        row.value:SetJustifyH("RIGHT")
        row.value:SetWordWrap(false)
        self.facts[key] = row
        vorige = row
    end
end

function LootCouncil:RefreshFacts(award)
    local facts = self.facts
    local keiner = L.LOOT_PROOF_NONE
    if not award then
        for _, row in pairs(facts) do row:SetValue(keiner, Theme.color.textFaint) end
        return
    end

    -- Reservierungen auf DIESEN Gegenstand.
    local namen = {}
    for _, eintrag in ipairs(award.itemID and GA.Modules.SoftRes:For(award.itemID) or {}) do
        namen[#namen + 1] = Util.ShortName(eintrag.name or "?")
    end
    facts.softres:SetValue(#namen > 0 and table.concat(namen, ", ") or keiner,
        #namen > 0 and Theme.color.goldBright or Theme.color.textFaint)

    local Rotation = GA.Modules.Rotation
    if GA.Core.Config:Get("rotationEnabled") then
        local seats, teile = Rotation:Active(), {}
        for _, seat in ipairs(seats) do teile[#teile + 1] = Util.ShortName(seat.name or "?") end
        local done, total = Rotation:CycleProgress()
        facts.rotation:SetValue(#teile > 0
            and string.format("%s · %d/%d", table.concat(teile, ", "), done, total)
            or L.ROTATION_NONE, Theme.color.text)
    else
        facts.rotation:SetValue(keiner, Theme.color.textFaint)
    end

    if award.confirmation then
        local stark = award.confirmation == GA.Data.Schema.Confirmation.MASTER_LOOT
            or award.confirmation == GA.Data.Schema.Confirmation.TRADE
        facts.proof:SetValue(L["LOOT_PROOF_" .. award.confirmation] or award.confirmation,
            stark and Theme.color.jade or Theme.color.warn)
    else
        facts.proof:SetValue(keiner, Theme.color.textFaint)
    end

    facts.detected:SetValue(award.ts and Util.TimeAgo(award.ts) or keiner, Theme.color.text)

    local quelle
    if award.encounterName then quelle = award.encounterName
    elseif award.sourceName then quelle = award.sourceName
    elseif award.sourceNpcID then quelle = string.format(L.LOOT_FROM_NPCID, award.sourceNpcID)
    else quelle = L.LOOT_FROM_UNKNOWN end
    facts.source:SetValue(quelle, award.encounterName and Theme.color.text or Theme.color.textDim)

    local methodKey = award.lootMethod and LOOT_METHOD_KEYS[award.lootMethod]
    facts.method:SetValue(methodKey and L[methodKey] or tostring(award.lootMethod or keiner),
        Theme.color.text)
end

-- ================================================================ Handlungen --

function LootCouncil:ReopenBidFrame()
    local Session = GA.Modules.Session
    if not GA.UI.BidFrame then return false end

    if Session.incoming and #Session.incoming.items > 0 then
        GA.UI.BidFrame:Show(Session.incoming)
        return true
    end

    local session = Session:Current()
    if not session then
        GA.Core.Debug:Info("%s", L.COUNCIL_REOPEN_NONE)
        return false
    end

    local items = {}
    for _, awardId in ipairs(session.awardIds) do
        local award = GA.Modules.Awards:Get(awardId)
        -- Nur, worauf noch geboten werden kann. Ein vergebener Gegenstand
        -- im Gebotsfenster waere eine Einladung zu einem Gebot, das
        -- niemand mehr annehmen kann.
        if award and award.itemID
            and award.status == GA.Data.Schema.LootStatus.SESSION_OPEN
        then
            items[#items + 1] = { awardId = awardId, itemID = award.itemID }
        end
    end

    if #items == 0 then
        GA.Core.Debug:Info("%s", L.COUNCIL_REOPEN_NONE)
        return false
    end

    Session.incoming = {
        id = session.id,
        host = session.openedByName,
        items = items,
    }
    GA.UI.BidFrame:Show(Session.incoming)
    return true
end

--- Nimmt den gewaehlten Gegenstand aus der Liste.
---
--- NUR WAS NOCH NICHT VERGEBEN IST. Ein vergebenes Teil aus der Liste zu
--- nehmen hiesse, die Historie zu frisieren; dafuer gibt es die Korrektur,
--- die den alten Stand stehen laesst.
function LootCouncil:RemoveSelected()
    local award = self.selectedAwardId and GA.Modules.Awards:Get(self.selectedAwardId)
    if not award then
        GA.Core.Debug:Info("%s", L.COUNCIL_REMOVE_NONE)
        return
    end

    local identity = Compat.GetPlayerIdentity()
    local ok, grund = GA.Modules.Awards:Cancel(award.id,
        L.COUNCIL_REMOVE_REASON, identity.guid)
    if not ok then
        GA.Core.Debug:Info("%s", L["COUNCIL_ERR_" .. tostring(grund)] or tostring(grund))
        return
    end

    self.selectedAwardId = nil
    self:Refresh()
end

--- Legt alles aus dem eigenen Beutel auf die Liste, was dafuer in Frage
--- kommt.
---
--- WOZU: Wer als Pluendermeister eingesammelt hat, hat den Abend im Beutel
--- und nicht in der Liste — etwa weil das Addon zwischendurch aus war, weil
--- jemand anders gepluendert hat, oder weil die Teile aus einem Handel
--- kamen. Ohne diesen Knopf muesste er jedes einzeln ueber /ga test
--- eintippen.
---
--- WAS IN FRAGE KOMMT: die Schwelle und sonst nichts Geratenes. Ob ein Teil
--- "zum Verteilen" ist, weiss dieser Client nicht — es steht in keinem Feld,
--- und eine Regel, die es zu erraten versucht, laesst genau das Teil weg, um
--- das es geht. Deshalb wird die Liste VORHER gezeigt: Entschieden wird mit
--- Augen, nicht mit einer Heuristik.
---
--- WAS SCHON DRAUFSTEHT, KOMMT NICHT ZWEIMAL. Nach dem Abend mit den
--- Doppeln waere das die falsche Art von Hilfe.
function LootCouncil:AddAllFromBags()
    local Awards = GA.Modules.Awards
    local schwelle = GA.Core.Config:Get("lootThresholdQuality") or 3

    -- Was schon offen auf der Liste steht, nach Gegenstand.
    local bekannt = {}
    for _, award in ipairs(Awards:List({ open = true })) do
        if award.itemID then bekannt[award.itemID] = true end
    end

    local kandidaten = {}
    for _, eintrag in ipairs(Compat.GetBagItems()) do
        local info = eintrag.link and Compat.GetItemInfo(eintrag.link)
        local quality = info and info.quality

        -- GEBUNDENES GEHOERT NICHT AUF DIE LISTE (26.09.2026: "ich kann
        -- jetzt 2 items aus der bag laden, die sind aber schon soulbound").
        --
        -- Ein seelengebundenes Teil kann niemand mehr bekommen. Es
        -- anzubieten heisst, jemanden auf etwas bieten zu lassen, das er
        -- nie bekommt.
        --
        -- NUR BEI EINEM SICHEREN JA. Compat.ItemIsBound kennt drei
        -- Antworten, und "weiss nicht" kommt vor. Hier waere das
        -- Ausschliessen der teurere Fehler: Ein faelschlich angebotenes
        -- Teil kostet einen Klick auf "Entfernen", ein faelschlich
        -- weggelassenes fehlt, und es gibt keinen Weg, es doch noch
        -- hereinzuholen.
        local gebunden = Compat.ItemIsBound(eintrag.bag, eintrag.slot) == true

        -- OHNE QUALITAET NICHT. Ein unbekannter Wert ist keine Erlaubnis;
        -- der Client holt ihn nach, und beim naechsten Druck steht er da.
        if quality and quality >= schwelle and not gebunden
            and not bekannt[eintrag.itemID] then
            bekannt[eintrag.itemID] = true
            kandidaten[#kandidaten + 1] = {
                itemID = eintrag.itemID, link = eintrag.link,
                name = info.name, quality = quality,
            }
        end
    end

    if #kandidaten == 0 then
        GA.Core.Debug:Info("%s", L.COUNCIL_ADD_NONE)
        return
    end

    if self.addAllPending ~= #kandidaten then
        self.addAllPending = #kandidaten
        GA.Core.Debug:Info(L.COUNCIL_ADD_FOUND, #kandidaten)
        for _, eintrag in ipairs(kandidaten) do
            GA.Core.Debug:Info("  %s", tostring(eintrag.link or eintrag.name))
        end
        self.addAllButton:SetLabel(string.format(L.COUNCIL_ADD_CONFIRM, #kandidaten))
        Compat.After(15, function()
            if not self.addAllButton then return end
            self.addAllPending = nil
            self.addAllButton:SetLabel(L.COUNCIL_ADD_ALL)
        end)
        return
    end

    self.addAllPending = nil
    self.addAllButton:SetLabel(L.COUNCIL_ADD_ALL)

    local identity = Compat.GetPlayerIdentity()
    for _, eintrag in ipairs(kandidaten) do
        -- KEINE ERFUNDENE HERKUNFT. Woher das Teil kam, weiss hier niemand
        -- mehr; der Grund sagt ehrlich, dass es aus dem Beutel stammt.
        Awards:Create(eintrag, {
            by = identity.guid,
            reason = L.COUNCIL_ADD_REASON,
            sourceName = L.COUNCIL_ADD_SOURCE,
            lootMethod = Compat.GetLootMethod(),
        })
    end

    GA.Core.Debug:Info(L.COUNCIL_ADD_DONE, #kandidaten)
    self:Refresh()
end

--- Nimmt ALLES aus der Liste, was noch nicht vergeben ist.
---
--- WAS MITGEHT: erkannte Gegenstaende und solche in einer laufenden Sitzung.
--- Beides ist "noch offen" und beides ist, was nach einem Abend
--- herumliegt — eine Aufraeumtaste, die nur die Haelfte raeumt, schickt
--- einen danach doch wieder durch die Liste.
---
--- WAS BLEIBT: alles Vergebene. Das ist Geschichte, und wer sie aendern
--- will, nimmt die Korrektur — die laesst den alten Stand stehen.
function LootCouncil:RemoveAll()
    local Awards = GA.Modules.Awards
    local offen = {}
    for _, award in ipairs(Awards:List({ open = true })) do
        if award.status == Status.DETECTED or award.status == Status.SESSION_OPEN then
            offen[#offen + 1] = award
        end
    end

    if #offen == 0 then
        GA.Core.Debug:Info("%s", L.COUNCIL_REMOVE_NONE)
        return
    end

    -- ERST FRAGEN. Der Knopf traegt die Frage selbst, damit die Antwort dort
    -- gegeben wird, wo sie gestellt wurde.
    if self.removeAllPending ~= #offen then
        self.removeAllPending = #offen
        self.removeAllButton:SetLabel(string.format(L.COUNCIL_REMOVE_ALL_CONFIRM, #offen))
        Compat.After(10, function()
            if not self.removeAllButton then return end
            self.removeAllPending = nil
            self.removeAllButton:SetLabel(L.COUNCIL_REMOVE_ALL)
        end)
        return
    end

    self.removeAllPending = nil
    self.removeAllButton:SetLabel(L.COUNCIL_REMOVE_ALL)

    local identity = Compat.GetPlayerIdentity()
    local weg = 0
    for _, award in ipairs(offen) do
        if Awards:Cancel(award.id, L.COUNCIL_REMOVE_REASON, identity.guid) then
            weg = weg + 1
        end
    end

    self.selectedAwardId = nil
    GA.Core.Debug:Info(L.COUNCIL_REMOVE_ALL_DONE, weg)
    self:Refresh()
end

function LootCouncil:OpenSession()
    local detected = GA.Modules.Awards:List({ status = Status.DETECTED })
    local ids = {}
    for _, award in ipairs(detected) do ids[#ids + 1] = award.id end

    local session, reason = GA.Modules.Session:Open(ids)
    if not session then
        GA.Core.Debug:Warn(L["COUNCIL_ERR_" .. tostring(reason)] or tostring(reason))
    end
    self:Refresh()
end

function LootCouncil:Vote(candidateName)
    local session = GA.Modules.Session:Current()
    if not session or not self.selectedAwardId then return end

    local identity = Compat.GetPlayerIdentity()
    -- Lokal eintragen UND verschicken: Der Lootmeister zaehlt, aber der
    -- eigene Client soll die Stimme sofort zeigen, nicht erst nach Umweg.
    GA.Modules.Session:RecordVote(session.id, self.selectedAwardId, identity.guid, candidateName)
    GA.Modules.Session:SendVote(session.id, self.selectedAwardId, candidateName)
    self:Refresh()
end

--- Zuschlag erteilen und, wenn moeglich, gleich uebergeben.
function LootCouncil:Award(candidateName)
    local session = GA.Modules.Session:Current()
    if not session or not self.selectedAwardId then return end

    local awardId = self.selectedAwardId
    local ok, reason = GA.Modules.Session:AwardTo(session.id, awardId, candidateName)
    if not ok then
        GA.Core.Debug:Warn(L["COUNCIL_ERR_" .. tostring(reason)] or tostring(reason))
        return
    end

    -- Schritt 2: Uebergabe. Nur wenn wirklich Pluendermeister und der
    -- Gegenstand noch im offenen Lootfenster liegt.
    local award = GA.Modules.Awards:Get(awardId)
    local handed = false

    if award and award.slot and Compat.IsMasterLooter() then
        local index
        for _, entry in ipairs(Compat.GetMasterLootCandidates(award.slot)) do
            if Util.ShortName(entry.name) == Util.ShortName(candidateName) then
                index = entry.index
                break
            end
        end
        if index then
            handed = GA.Modules.LootTracker:GiveMasterLoot(awardId, index)
        else
            GA.Core.Debug:Warn(L.COUNCIL_NO_CANDIDATE, tostring(candidateName))
        end
    end

    if not handed then
        -- Kein Pluendermeister oder Empfaenger nicht in der Liste: Die
        -- Uebergabe steht aus und wird spaeter per Handel bestaetigt.
        GA.Modules.Awards:MarkTransferPending(awardId,
            { by = Compat.GetPlayerIdentity().guid, reason = "keine Master-Loot-Uebergabe" })
    end

    self.selectedAwardId = nil
    self:Refresh()
end

-- ================================================================== Refresh ---

function LootCouncil:OnShow() self:Refresh() end

function LootCouncil:Refresh()
    local Session = GA.Modules.Session
    local session = Session:Current()
    local identity = Compat.GetPlayerIdentity()
    local canHost = Session:CanHost(identity.guid)

    local list
    if session then
        list = {}
        for _, awardId in ipairs(session.awardIds) do
            local award = GA.Modules.Awards:Get(awardId)
            if award then list[#list + 1] = award end
        end
        self.state:SetText(string.format(L.COUNCIL_RUNNING, #session.awardIds,
            Util.ShortName(session.openedByName or "?")))
    else
        list = GA.Modules.Awards:List({ status = Status.DETECTED })
        self.state:SetText(#list > 0
            and string.format(L.COUNCIL_DETECTED, #list)
            or L.COUNCIL_IDLE)
    end

    self.openButton:SetEnabledState(canHost and not session and #list > 0,
        (not canHost) and L.COUNCIL_NEED_LOOTMASTER
        or (session and L.COUNCIL_ALREADY_OPEN)
        or L.COUNCIL_NOTHING_DETECTED)
    self.closeButton:SetEnabledState(canHost and session ~= nil,
        (not canHost) and L.COUNCIL_NEED_LOOTMASTER or L.COUNCIL_NO_SESSION)

    local Rotation = GA.Modules.Rotation
    local enabled = GA.Core.Config:Get("rotationEnabled") and true or false
    self.rotateButton:SetShown(enabled)
    self.rotationState:SetShown(enabled)

    if enabled then
        local seats = Rotation:Active()
        if #seats == 0 then
            self.rotationState:SetText(L.ROTATION_NONE)
        else
            local names = {}
            for _, seat in ipairs(seats) do names[#names + 1] = seat.name end
            local done, total = Rotation:CycleProgress()
            self.rotationState:SetText(string.format("%s  |cff808080%s|r",
                table.concat(names, ", "), string.format(L.ROTATION_CYCLE, done, total)))
        end
        self.rotateButton:SetEnabledState(canHost and Compat.IsInGroup(),
            (not canHost) and L.ROTATION_ERR_NOTALLOWED or L.ROTATION_ERR_NOGROUP)
    end

    local SoftRes = GA.Modules.SoftRes
    if not SoftRes:Current() then
        self.softResState:SetText("")
    else
        local stats = SoftRes:Stats()
        local text = string.format(L.SOFTRES_STATS, stats.entries, stats.players, stats.contested)
        if stats.overLimit > 0 then
            text = text .. "  ·  " .. string.format("%s: %d", L.SOFTRES_OVERLIMIT, stats.overLimit)
        end
        self.softResState:SetText(text)
        local color = (stats.contested > 0 or stats.overLimit > 0)
            and Theme.color.warn or Theme.color.textDim
        self.softResState:SetTextColor(color[1], color[2], color[3])
    end

    -- Die Auswahl: gesetzt bleibt gesetzt, sonst der erste. Eine Auswahl
    -- auf etwas, das nicht mehr in der Liste steht, faellt zurueck.
    local gewaehlt
    for _, award in ipairs(list) do
        if award.id == self.selectedAwardId then gewaehlt = award break end
    end
    if not gewaehlt and list[1] then
        self.selectedAwardId = list[1].id
        gewaehlt = list[1]
    elseif not gewaehlt then
        self.selectedAwardId = nil
    end

    self:RefreshCards(list)

    local candidates = {}
    if session and self.selectedAwardId then
        candidates = Session:Tally(session.id, self.selectedAwardId)
    end

    self.bestIlvl = 0
    for _, candidate in ipairs(candidates) do
        if candidate.itemLevel and candidate.itemLevel > self.bestIlvl then
            self.bestIlvl = candidate.itemLevel
        end
    end

    self.candidates:SetData(self:GroupRows(candidates))

    self.bidPanel:SetTitle(gewaehlt
        and string.format(L.COUNCIL_CANDIDATES_FOR, gewaehlt.itemName or "?")
        or L.COUNCIL_CANDIDATES)

    if session and self.selectedAwardId then
        self.footer:SetText(string.format(L.COUNCIL_FOOTER,
            #candidates, Session:VoteCount(session.id, self.selectedAwardId)))
    elseif session then
        self.footer:SetText(L.COUNCIL_PICK_ITEM)
    else
        self.footer:SetText(L.COUNCIL_HINT)
    end

    self:RefreshDecision(candidates, session)
    self:RefreshFacts(gewaehlt)

    GA.UI.MainFrame:SetContext(session and L.COUNCIL_CONTEXT_OPEN or "")
end

GA.UI.MainFrame:RegisterView("lootcouncil", LootCouncil)

GA.Core.Callbacks:On("SESSION_CHANGED", function()
    if LootCouncil.frame and LootCouncil.frame:IsVisible() then LootCouncil:Refresh() end
end, "LootCouncilView")
