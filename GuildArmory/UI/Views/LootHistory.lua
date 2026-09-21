--[[----------------------------------------------------------------------------
    Views/LootHistory — jede erkannte und vergebene Beute.

    Die Liste oben, der gewaehlte Eintrag unten im Detail.

    ZWEI DINGE MUESSEN HIER SICHTBAR SEIN, sonst taeuscht die Ansicht:

    1. WIE eine Uebergabe bestaetigt wurde. Master Loot und Handel sind stark
       (das Spiel hat es gemeldet), die Loot-Nachricht im Chat ist schwach, und
       "von Hand" ist eine Behauptung des Lootmeisters. Alle drei stehen da —
       farblich unterschieden, nicht als eine gemeinsame Haekchen-Spalte.

    2. WOHER der Gegenstand kam. Wo weder ENCOUNTER_START noch die Leichen-GUID
       etwas hergaben, steht "Herkunft unbekannt" — und nicht der Name des
       zuletzt anvisierten Gegners.
------------------------------------------------------------------------------]]

local _, GA = ...

local LootHistory = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

LootHistory.titleKey = "NAV_LOOTHISTORY"

local Status = GA.Data.Schema.LootStatus
local Confirmation = GA.Data.Schema.Confirmation

--- Farbe je Status. Gold heisst "wichtig", nicht "gut" — deshalb ist RECEIVED
--- jade und AWARDED gold: Das eine ist erledigt, das andere braucht noch etwas.
local STATUS_COLOR = {
    [Status.DETECTED]         = "textDim",
    [Status.SESSION_OPEN]     = "info",
    [Status.AWARDED]          = "gold",
    [Status.TRANSFER_PENDING] = "warn",
    [Status.RECEIVED]         = "jade",
    [Status.EQUIPPED]         = "good",
    [Status.CANCELLED]        = "textFaint",
    [Status.CORRECTED]        = "warn",
}

--- Starke Bestaetigung = das Spiel hat den Vorgang gemeldet.
local STRONG_CONFIRMATION = {
    [Confirmation.MASTER_LOOT] = true,
    [Confirmation.TRADE] = true,
}

local COLUMNS = {
    { key = "when",   label = "COL_WHEN",   width = 74 },
    { key = "item",   label = "COL_ITEM",   width = 210 },
    { key = "who",    label = "COL_WHO",    width = 110 },
    { key = "status", label = "COL_STATUS", width = 110 },
    { key = "proof",  label = "COL_PROOF",  width = 120 },
}

-- ================================================================== Aufbau ----

function LootHistory:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- Werkzeugzeile
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(24)

    self.search = Widgets.SearchBox(bar, L.LOOT_SEARCH, function(text)
        self.filter.search = text
        self:Refresh()
    end)
    self.search:SetPoint("LEFT", bar, "LEFT", 0, 0)
    self.search:SetWidth(200)

    self.filter = {}

    self.openOnly = Widgets.CheckBox(bar, L.LOOT_ONLY_OPEN, function(checked)
        self.filter.open = checked or nil
        self:Refresh()
    end)
    self.openOnly:SetPoint("LEFT", self.search, "RIGHT", 12, 0)

    self.summary = Theme.Label(bar, "", fonts.small, Theme.color.textFaint)
    self.summary:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    -- Liste
    local listPanel = Widgets.Panel(frame)
    listPanel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    listPanel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)

    local localizedColumns = {}
    for index, column in ipairs(COLUMNS) do
        localizedColumns[index] = { key = column.key, label = L[column.label],
                                    width = column.width, justify = column.justify }
    end

    self.list = Widgets.ScrollList(listPanel.content, {
        rowHeight = 22,
        columns = localizedColumns,
        createRow = function(row, columns)
            Widgets.BuildCells(row, columns)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(14) row.icon:SetHeight(14)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.icon:SetPoint("LEFT", row.cells.item, "LEFT", 0, 0)
        end,
        updateRow = function(row, award) self:UpdateRow(row, award) end,
        onClickRow = function(award)
            self.selectedId = award.id
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
    self.list:SetAllPoints(listPanel.content)

    -- Detail
    local detail = Widgets.Panel(frame, L.LOOT_DETAIL)
    detail:SetPoint("TOPLEFT", listPanel, "BOTTOMLEFT", 0, -gap)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.detailPanel = detail

    self.detailTitle = Theme.Label(detail.content, "", fonts.big, Theme.color.goldBright)
    self.detailTitle:SetPoint("TOPLEFT", detail.content, "TOPLEFT", 0, 0)

    self.detailSource = Theme.Label(detail.content, "", fonts.body, Theme.color.textDim)
    self.detailSource:SetPoint("TOPLEFT", self.detailTitle, "BOTTOMLEFT", 0, -4)
    self.detailSource:SetPoint("RIGHT", detail.content, "RIGHT", 0, 0)
    self.detailSource:SetJustifyH("LEFT")

    self.detailHistory = Theme.Label(detail.content, "", fonts.small, Theme.color.textFaint)
    self.detailHistory:SetPoint("TOPLEFT", self.detailSource, "BOTTOMLEFT", 0, -6)
    self.detailHistory:SetPoint("RIGHT", detail.content, "RIGHT", 0, 0)
    self.detailHistory:SetJustifyH("LEFT")
    self.detailHistory:SetSpacing(2)

    local function layout()
        local height = frame:GetHeight()
        if not height or height <= 0 then return end
        listPanel:SetHeight(math.max(120, (height - 24 - pad * 2 - gap - 6) * 0.62))
    end
    frame:SetScript("OnSizeChanged", layout)
    self.layout = layout

    self.frame = frame
    return frame
end

-- ================================================================== Zeile -----

function LootHistory:UpdateRow(row, award)
    local cells = row.cells

    cells.when:SetText(Util.TimeAgo(award.ts))
    cells.when:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])

    -- Gegenstand: Icon plus Name in Qualitaetsfarbe.
    local info = award.itemID and Compat.GetItemInfo(award.itemLink or award.itemID)
    if info and info.icon then
        row.icon:SetTexture(info.icon)
        row.icon:Show()
        cells.item:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    else
        row.icon:Hide()
    end
    cells.item:SetText(award.itemName or (info and info.name) or ("#" .. tostring(award.itemID)))
    local quality = Theme.QualityColor(award.quality or (info and info.quality))
    cells.item:SetTextColor(quality[1], quality[2], quality[3])

    if award.recipientName then
        local character = award.recipientGuid
            and GA.Core.Database.account.characters[award.recipientGuid]
        local r, g, b = Util.ClassColor(character and character.class)
        cells.who:SetText(Util.ShortName(award.recipientName))
        cells.who:SetTextColor(r, g, b)
    else
        cells.who:SetText("—")
        cells.who:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    local statusColor = Theme.color[STATUS_COLOR[award.status] or "textDim"]
    cells.status:SetText(L["LOOT_STATUS_" .. tostring(award.status)] or award.status)
    cells.status:SetTextColor(statusColor[1], statusColor[2], statusColor[3])

    -- Die Bestaetigungsspalte ist der Kern dieser Ansicht.
    if award.confirmation then
        cells.proof:SetText(L["LOOT_PROOF_" .. award.confirmation] or award.confirmation)
        local strong = STRONG_CONFIRMATION[award.confirmation]
        local color = strong and Theme.color.jade or Theme.color.warn
        cells.proof:SetTextColor(color[1], color[2], color[3])
    else
        cells.proof:SetText(L.LOOT_PROOF_NONE)
        cells.proof:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end
end

-- ================================================================== Detail ----

--- Beschreibt die Herkunft — und sagt ausdruecklich, wenn sie unbekannt ist.
function LootHistory:DescribeSource(award)
    local parts = {}
    if award.encounterName then
        parts[#parts + 1] = string.format(L.LOOT_FROM_ENCOUNTER, award.encounterName)
    elseif award.sourceName then
        parts[#parts + 1] = string.format(L.LOOT_FROM_CREATURE, award.sourceName)
    elseif award.sourceNpcID then
        parts[#parts + 1] = string.format(L.LOOT_FROM_NPCID, award.sourceNpcID)
    else
        parts[#parts + 1] = L.LOOT_FROM_UNKNOWN
    end

    if award.instanceName then parts[#parts + 1] = award.instanceName
    elseif award.zone then parts[#parts + 1] = award.zone end

    if award.lootMethod then
        parts[#parts + 1] = L["LOOT_" .. string.upper(award.lootMethod)] or award.lootMethod
    end
    return table.concat(parts, "  ·  ")
end

function LootHistory:RefreshDetail(award)
    if not award then
        self.detailPanel:SetTitle(L.LOOT_DETAIL)
        self.detailTitle:SetText("")
        self.detailSource:SetText(L.LOOT_PICK_ROW)
        self.detailHistory:SetText("")
        return
    end

    self.detailPanel:SetTitle(L.LOOT_DETAIL)
    self.detailTitle:SetText(award.itemLink or award.itemName or "?")
    self.detailSource:SetText(self:DescribeSource(award))

    local lines = {}
    for _, entry in ipairs(award.statusHistory or {}) do
        local who = entry.by and GA.Core.Database.account.characters[entry.by]
        lines[#lines + 1] = string.format("%s  —  %s%s%s",
            date("%d.%m. %H:%M", entry.ts or 0),
            L["LOOT_STATUS_" .. tostring(entry.status)] or tostring(entry.status),
            who and ("  ·  " .. Util.ShortName(who.name or "?")) or "",
            entry.reason and ("  ·  " .. entry.reason) or "")
    end

    if award.confirmation then
        local strong = STRONG_CONFIRMATION[award.confirmation]
        lines[#lines + 1] = (strong and L.LOOT_PROOF_STRONG or L.LOOT_PROOF_WEAK)
            .. ": " .. (L["LOOT_PROOF_" .. award.confirmation] or award.confirmation)
    end
    if award.correctionOf then
        lines[#lines + 1] = string.format(L.LOOT_CORRECTION_OF, award.correctionOf)
    end
    if award.correctedBy then
        lines[#lines + 1] = string.format(L.LOOT_CORRECTED_BY, award.correctedBy)
    end

    self.detailHistory:SetText(table.concat(lines, "\n"))
end

-- ================================================================== Refresh ---

function LootHistory:OnShow()
    if self.layout then self.layout() end
end

function LootHistory:Refresh()
    if self.layout then self.layout() end

    local Awards = GA.Modules.Awards
    local list = Awards:List(self.filter)
    self.list:SetData(list)

    local selected = self.selectedId and Awards:Get(self.selectedId) or nil
    self:RefreshDetail(selected)

    local stats = Awards:Stats()
    self.summary:SetText(string.format(L.LOOT_SUMMARY, stats.total, stats.open, stats.manual))

    GA.UI.MainFrame:SetContext(string.format(L.LOOT_CONTEXT, #list))
end

GA.UI.MainFrame:RegisterView("loothistory", LootHistory)
