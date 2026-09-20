--[[----------------------------------------------------------------------------
    Views/LootCouncil — die Ansicht des Lootmeisters und des Councils.

    Links die Gegenstaende (offene Session oder frisch erkannte Beute), rechts
    die Bewerber mit Antwort, Itemlevel, Notiz und Stimmen.

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
------------------------------------------------------------------------------]]

local _, GA = ...

local LootCouncil = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

LootCouncil.title = L.NAV_LOOTCOUNCIL

local Status = GA.Data.Schema.LootStatus

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
    self.closeButton:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    self.openButton = Widgets.Button(bar, L.COUNCIL_OPEN, function()
        self:OpenSession()
    end, "primary")
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
    self.rotateButton:SetPoint("RIGHT", self.openButton, "LEFT", -6, 0)

    -- Der Stand der Rotation gehoert neben den Knopf und nicht in ein
    -- Untermenue: Wer nicht sieht, wer gerade mitstimmt, kann die Abstimmung
    -- nicht einordnen.
    self.rotationState = Theme.Label(bar, "", fonts.small, Theme.color.textDim)
    self.rotationState:SetPoint("LEFT", self.state, "RIGHT", 10, 0)
    self.rotationState:SetPoint("RIGHT", self.rotateButton, "LEFT", -8, 0)
    self.rotationState:SetJustifyH("LEFT")

    -- Stand der Reservierungen. Steht unter der Werkzeugleiste und nicht in
    -- einem Untermenue: Wer nicht sieht, dass eine Runde laeuft, vergibt
    -- reservierte Gegenstaende nebenbei.
    self.softResState = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.softResState:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -2)
    self.softResState:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    self.softResState:SetJustifyH("LEFT")

    -- ------------------------------------------------------ Gegenstaende ----
    local itemPanel = Widgets.Panel(frame, L.COUNCIL_ITEMS)
    itemPanel:SetWidth(280)
    itemPanel:SetPoint("TOPLEFT", self.softResState, "BOTTOMLEFT", -2, -6)
    itemPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    self.itemPanel = itemPanel

    self.items = Widgets.ScrollList(itemPanel.content, {
        rowHeight = 28,
        createRow = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(22) row.icon:SetHeight(22)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.name:SetJustifyH("LEFT")
            row.tag = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.tag:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end,
        updateRow = function(row, award) self:UpdateItemRow(row, award) end,
        onClickRow = function(award)
            self.selectedAwardId = award.id
            self:Refresh()
        end,
        onEnterRow = function(row, award)
            if award.itemLink then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                if pcall(GameTooltip.SetHyperlink, GameTooltip, award.itemLink) then
                    GameTooltip:Show()
                end
            end
        end,
    })
    self.items:SetAllPoints(itemPanel.content)

    -- ------------------------------------------------------ Bewerber --------
    local bidPanel = Widgets.Panel(frame, L.COUNCIL_CANDIDATES)
    bidPanel:SetPoint("TOPLEFT", itemPanel, "TOPRIGHT", gap, 0)
    bidPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.bidPanel = bidPanel

    self.candidates = Widgets.ScrollList(bidPanel.content, {
        rowHeight = 26,
        createRow = function(row) self:BuildCandidateRow(row) end,
        updateRow = function(row, candidate) self:UpdateCandidateRow(row, candidate) end,
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

-- ================================================================== Zeilen ----

function LootCouncil:UpdateItemRow(row, award)
    local info = award.itemID and Compat.GetItemInfo(award.itemLink or award.itemID)
    if info and info.icon then row.icon:SetTexture(info.icon) row.icon:Show() else row.icon:Hide() end

    row.name:SetText(award.itemName or (info and info.name) or ("#" .. tostring(award.itemID)))
    local quality = Theme.QualityColor(award.quality or (info and info.quality))
    row.name:SetTextColor(quality[1], quality[2], quality[3])

    if award.id == self.selectedAwardId then
        row.name:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
    end

    local session = GA.Modules.Session:Current()
    if award.status == Status.SESSION_OPEN and session then
        local tally = GA.Modules.Session:Tally(session.id, award.id)
        row.tag:SetText(string.format(L.COUNCIL_BIDS, #tally))
        row.tag:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
    elseif award.recipientName then
        row.tag:SetText(Util.ShortName(award.recipientName))
        row.tag:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
    else
        row.tag:SetText(L["LOOT_STATUS_" .. tostring(award.status)] or "")
        row.tag:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end
end

function LootCouncil:BuildCandidateRow(row)
    local fonts = Theme.Fonts()

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetWidth(104)
    row.name:SetJustifyH("LEFT")

    row.response = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.response:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.response:SetWidth(96)
    row.response:SetJustifyH("LEFT")

    row.ilvl = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.ilvl:SetPoint("LEFT", row.response, "RIGHT", 4, 0)
    row.ilvl:SetWidth(44)
    row.ilvl:SetJustifyH("RIGHT")

    -- Plus Eins neben dem Itemlevel: Beides sind Zahlen, die das Council
    -- beim Abwaegen ansieht, und beide sind Hinweise — keine Wertung.
    row.plusOne = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.plusOne:SetPoint("LEFT", row.ilvl, "RIGHT", 6, 0)
    row.plusOne:SetWidth(30)
    row.plusOne:SetJustifyH("RIGHT")

    row.note = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.note:SetPoint("LEFT", row.plusOne, "RIGHT", 8, 0)
    row.note:SetPoint("RIGHT", row, "RIGHT", -190, 0)
    row.note:SetJustifyH("LEFT")

    row.award = Widgets.Button(row, L.COUNCIL_AWARD, function()
        -- GiveMasterLoot ist geschuetzt: direkt aus dem Klick heraus, ohne
        -- Umweg ueber einen Timer oder Rueckruf.
        if row.item then LootCouncil:Award(row.item.name) end
    end, "primary")
    row.award:SetHeight(18)
    row.award:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.vote = Widgets.Button(row, L.COUNCIL_VOTE, function()
        if row.item then LootCouncil:Vote(row.item.name) end
    end)
    row.vote:SetHeight(18)
    row.vote:SetPoint("RIGHT", row.award, "LEFT", -4, 0)

    row.votes = Theme.Label(row, "", fonts.body, Theme.color.goldBright)
    row.votes:SetPoint("RIGHT", row.vote, "LEFT", -6, 0)
    row.votes:SetWidth(24)
    row.votes:SetJustifyH("RIGHT")
end

function LootCouncil:UpdateCandidateRow(row, candidate)
    local r, g, b = Util.ClassColor(candidate.class)
    row.name:SetText(candidate.name)
    row.name:SetTextColor(r, g, b)

    local response = GA.Modules.Session:ResponseByKey(candidate.response)
    row.response:SetText(response and response.label or candidate.response or "?")
    local color = response and response.color or Theme.color.textDim
    row.response:SetTextColor(color[1], color[2], color[3])

    row.ilvl:SetText(candidate.itemLevel and string.format("%.1f", candidate.itemLevel) or "—")

    -- Wunschliste als HINWEIS, nicht als Wertung: Sie steht neben der
    -- Bewerbung, sie ersetzt sie nicht und erzeugt keine Punktzahl.
    -- Wer entscheidet, bleibt das Council (siehe Wishlist/Wishlist.lua).
    local award = self.selectedAwardId and GA.Modules.Awards:Get(self.selectedAwardId)
    local wish = award and award.itemID
        and GA.Modules.Wishlist:ForCandidate(award.itemID, candidate.name) or nil

    -- Plus Eins: wie oft dieser Spieler schon etwas bekommen hat. Wenig ist
    -- nicht "im Recht" und viel nicht "dran gewesen" — die Zahl steht da,
    -- damit sie nicht jeder im Kopf schaetzen muss.
    local plus = candidate.guid and GA.Modules.PlusOne:For(candidate.guid)
    if plus then
        row.plusOne:SetText("+" .. tostring(plus.total))
        -- Wer nichts bekommen hat, faellt auf. Das ist die Information, die
        -- im Gedaechtnis am schnellsten verlorengeht.
        local color = plus.total == 0 and Theme.color.jade or Theme.color.textDim
        row.plusOne:SetTextColor(color[1], color[2], color[3])
    else
        row.plusOne:SetText("")
    end

    -- Reservierung: steht VOR der Wunschliste, weil sie mehr behauptet.
    -- Eine Wunschliste sagt "kann ich gebrauchen", eine Reservierung sagt
    -- "das ist heute meins" — und ist damit eine Zusage der Gilde.
    local reserved
    for _, entry in ipairs(award and award.itemID
        and GA.Modules.SoftRes:For(award.itemID) or {}) do
        if Util.NormalizeName(entry.name) == Util.NormalizeName(candidate.name) then
            reserved = entry
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
    -- Die Reservierung ist die staerkste Aussage in der Zeile und faerbt sie.
    local noteColor = Theme.color.textFaint
    if reserved then noteColor = Theme.color.goldBright
    elseif wish and not wish.fulfilled then noteColor = Theme.color.jade end
    row.note:SetTextColor(noteColor[1], noteColor[2], noteColor[3])

    row.votes:SetText(candidate.votes > 0 and tostring(candidate.votes) or "")

    local identity = Compat.GetPlayerIdentity()
    row.vote:SetWidth(64)
    row.vote:SetEnabledState(GA.Modules.Session:CanVote(identity.guid),
        L.COUNCIL_NEED_COUNCIL)
    row.award:SetWidth(76)
    row.award:SetEnabledState(GA.Modules.Session:CanHost(identity.guid),
        L.COUNCIL_NEED_LOOTMASTER)
end

-- ================================================================== Aktionen --

--- Oeffnet eine Session aus allen frisch erkannten Gegenstaenden.
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

    -- Ohne Session zeigt die Liste, was erkannt wurde und zur Wahl stuende.
    local list
    if session then
        list = {}
        for _, awardId in ipairs(session.awardIds) do
            local award = GA.Modules.Awards:Get(awardId)
            if award then list[#list + 1] = award end
        end
        self.state:SetText(string.format(L.COUNCIL_RUNNING, #session.awardIds,
            Util.ShortName(session.openedByName or "?")))
        self.itemPanel:SetTitle(L.COUNCIL_ITEMS)
    else
        list = GA.Modules.Awards:List({ status = Status.DETECTED })
        self.state:SetText(#list > 0
            and string.format(L.COUNCIL_DETECTED, #list)
            or L.COUNCIL_IDLE)
        self.itemPanel:SetTitle(L.COUNCIL_DETECTED_TITLE)
    end

    self.items:SetData(list)
    self.openButton:SetEnabledState(canHost and not session and #list > 0,
        (not canHost) and L.COUNCIL_NEED_LOOTMASTER
        or (session and L.COUNCIL_ALREADY_OPEN)
        or L.COUNCIL_NOTHING_DETECTED)
    self.closeButton:SetEnabledState(canHost and session ~= nil,
        (not canHost) and L.COUNCIL_NEED_LOOTMASTER or L.COUNCIL_NO_SESSION)

    -- Rotation
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

    -- Reservierungen
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
        -- Umkaempftes oder Ueberschreitungen in Warnfarbe: Genau das sind die
        -- Faelle, in denen das Council etwas entscheiden muss.
        local color = (stats.contested > 0 or stats.overLimit > 0)
            and Theme.color.warn or Theme.color.textDim
        self.softResState:SetTextColor(color[1], color[2], color[3])
    end

    -- Bewerber des gewaehlten Gegenstands.
    if not self.selectedAwardId and list[1] then self.selectedAwardId = list[1].id end

    local candidates = {}
    if session and self.selectedAwardId then
        candidates = Session:Tally(session.id, self.selectedAwardId)
    end
    self.candidates:SetData(candidates)

    local award = self.selectedAwardId and GA.Modules.Awards:Get(self.selectedAwardId)
    self.bidPanel:SetTitle(award
        and string.format(L.COUNCIL_CANDIDATES_FOR, award.itemName or "?")
        or L.COUNCIL_CANDIDATES)

    if session and self.selectedAwardId then
        self.footer:SetText(string.format(L.COUNCIL_FOOTER,
            #candidates, Session:VoteCount(session.id, self.selectedAwardId)))
    elseif session then
        self.footer:SetText(L.COUNCIL_PICK_ITEM)
    else
        self.footer:SetText(L.COUNCIL_HINT)
    end

    GA.UI.MainFrame:SetContext(session and L.COUNCIL_CONTEXT_OPEN or "")
end

GA.UI.MainFrame:RegisterView("lootcouncil", LootCouncil)

-- Sessionaenderungen kommen ueber Nachrichten herein, nicht nur ueber Klicks.
GA.Core.Callbacks:On("SESSION_CHANGED", function()
    if LootCouncil.frame and LootCouncil.frame:IsVisible() then LootCouncil:Refresh() end
end, "LootCouncilView")
