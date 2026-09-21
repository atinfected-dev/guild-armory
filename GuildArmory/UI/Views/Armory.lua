--[[----------------------------------------------------------------------------
    Views/Armory — Charakterliste links, Papierpuppe rechts.

    Aufgebaut wie das Charakterfenster: acht Plaetze links, acht rechts, drei
    Waffenplaetze unten, der Charakter in der Mitte. Icons mit Qualitaetsrahmen,
    leere Plaetze mit Blizzards Slot-Silhouetten, native Tooltips.

    Regel aus der Vorgabe (Abschnitt 4): Ein Stand, der nicht vom eigenen
    Charakter live kommt, traegt IMMER Zeitstempel und Quelle — sichtbar, in
    Warnfarbe. Niemals als aktuell, wenn nur alte Daten da sind.
------------------------------------------------------------------------------]]

local _, GA = ...

local Armory = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

Armory.titleKey = "NAV_ARMORY_LONG"

local SLOT_SIZE = 42
local SLOT_GAP = 6

--- Anordnung wie im Charakterfenster.
local LEFT_COLUMN  = { 1, 2, 3, 15, 5, 4, 19, 9 }     -- Kopf .. Handgelenke
local RIGHT_COLUMN = { 10, 6, 7, 8, 11, 12, 13, 14 }  -- Haende .. Schmuck 2
local BOTTOM_ROW   = { 16, 17, 18 }                   -- Waffenhand, Schildhand, Distanz

--- Als Funktion, nicht als Tabelle: Eine beim Laden gebaute Spaltenliste
--- traegt die Beschriftungen der Sprache, die beim Laden galt — und die
--- Einstellung steht erst bei PLAYER_LOGIN fest.
local function characterColumns()
    return {
        { key = "name",  label = L.COL_NAME,  width = 104 },
        { key = "class", label = L.COL_CLASS, width = 66 },
        { key = "ilvl",  label = L.COL_ILVL,  width = 32, justify = "RIGHT" },
    }
end

-- ================================================================== Aufbau ----

function Armory:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ---------------------------------------------------- Linke Spalte ------

    local listPanel = Widgets.Panel(frame, L.ARMORY_CHARACTERS)
    listPanel:SetWidth(240)
    listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    listPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    self.listPanel = listPanel

    self.search = Widgets.SearchBox(listPanel.content, L.ARMORY_SEARCH, function(text)
        self.filter = { search = text }
        self:RefreshCharacters()
    end)
    self.search:SetPoint("TOPLEFT", listPanel.content, "TOPLEFT", 0, 0)
    self.search:SetPoint("TOPRIGHT", listPanel.content, "TOPRIGHT", 0, 0)
    self.filter = {}

    self.characters = Widgets.ScrollList(listPanel.content, {
        rowHeight = Theme.size.rowHeight,
        columns = characterColumns(),
        createRow = function(row, columns) Widgets.BuildCells(row, columns) end,
        updateRow = function(row, character)
            local cells = row.cells
            cells.name:SetText(character.name or "?")
            local r, g, b = Util.ClassColor(character.class)
            if character.guid == self.selectedGuid then
                cells.name:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
            else
                cells.name:SetTextColor(r, g, b)
            end
            cells.class:SetText(character.className or character.class or "")
            cells.class:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
            local level = character.itemLevel and character.itemLevel.value
            cells.ilvl:SetText(level and tostring(level) or "—")
            cells.ilvl:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
        end,
        onClickRow = function(character)
            self.selectedGuid = character.guid
            self:RefreshCharacters()
            self:RefreshDoll()
        end,
    })
    -- Inspect: Knopf unten in der Liste, Status darueber. Der Knopf folgt dem
    -- Ziel (TARGET_CHANGED) und ist nur an, wenn ein Inspect moeglich ist.
    self.inspectButton = Widgets.Button(listPanel.content, L.ARMORY_INSPECT_TARGET, function()
        local ok, reason = GA.Modules.Inspect:Request("target")
        if not ok then
            self.inspectStatus:SetText(L["INSPECT_REASON_" .. tostring(reason)] or tostring(reason))
        end
    end)
    self.inspectButton:SetPoint("BOTTOMLEFT", listPanel.content, "BOTTOMLEFT", 0, 0)
    self.inspectButton:SetPoint("BOTTOMRIGHT", listPanel.content, "BOTTOMRIGHT", 0, 0)

    self.inspectStatus = Theme.Label(listPanel.content, L.ARMORY_INSPECT_HINT, fonts.small, Theme.color.textFaint)
    self.inspectStatus:SetPoint("BOTTOMLEFT", self.inspectButton, "TOPLEFT", 2, 4)
    self.inspectStatus:SetPoint("RIGHT", listPanel.content, "RIGHT", -2, 0)
    self.inspectStatus:SetJustifyH("LEFT")
    self.inspectStatus:SetHeight(24)

    self.characters:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 0, -6)
    self.characters:SetPoint("BOTTOMRIGHT", self.inspectStatus, "TOPRIGHT", 2, 4)

    -- ---------------------------------------------------- Papierpuppe -------

    -- Eingelassene Flaeche wie das Charakterfenster; die Slots liegen direkt
    -- darauf, ohne zweiten Rahmen.
    local doll = Widgets.Inset(frame)
    doll:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", gap, 0)
    doll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.doll = doll

    -- Kopfbereich: Portrait, Name, Klasse, Itemlevel
    local portrait = doll:CreateTexture(nil, "ARTWORK")
    portrait:SetWidth(52) portrait:SetHeight(52)
    portrait:SetPoint("TOPLEFT", doll, "TOPLEFT", 16, -14)
    self.portrait = portrait

    local ring = doll:CreateTexture(nil, "OVERLAY")
    ring:SetWidth(64) ring:SetHeight(64)
    ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    pcall(ring.SetTexture, ring, "Interface\\Minimap\\MiniMap-TrackingBorder")
    pcall(ring.SetTexCoord, ring, 0, 0.6, 0, 0.6)
    self.ring = ring

    self.name = Theme.Label(doll, "", fonts.hero, Theme.color.goldBright)
    self.name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 12, -4)

    self.meta = Theme.Label(doll, "", fonts.body, Theme.color.textDim)
    self.meta:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 1, -3)

    self.classIcon = doll:CreateTexture(nil, "ARTWORK")
    self.classIcon:SetWidth(20) self.classIcon:SetHeight(20)
    self.classIcon:SetPoint("LEFT", self.meta, "RIGHT", 6, 0)

    self.ilvlValue = Theme.Label(doll, "", fonts.hero, Theme.color.goldBright)
    self.ilvlValue:SetPoint("TOPRIGHT", doll, "TOPRIGHT", -20, -16)
    self.ilvlLabel = Theme.Label(doll, L.DASH_ITEMLEVEL, fonts.body, Theme.color.textDim)
    self.ilvlLabel:SetPoint("TOPRIGHT", self.ilvlValue, "BOTTOMRIGHT", 0, -2)

    -- Zeitstempel/Quelle — die Regel aus dem Dateikopf.
    self.stamp = Theme.Label(doll, "", fonts.small, Theme.color.textFaint)
    self.stamp:SetPoint("TOPLEFT", self.meta, "BOTTOMLEFT", 0, -6)
    self.stamp:SetPoint("RIGHT", self.ilvlValue, "LEFT", -12, 0)
    self.stamp:SetJustifyH("LEFT")

    -- Slots
    self.slots = {}
    local columnTop = -92

    local function place(slotID, anchorPoint, x, y)
        local slot = Theme.ItemSlot(doll, slotID, SLOT_SIZE)
        slot:SetPoint(anchorPoint, doll, anchorPoint, x, y)
        slot:SetScript("OnEnter", function(button) self:ShowSlotTooltip(button) end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.slots[slotID] = slot
        return slot
    end

    for index, slotID in ipairs(LEFT_COLUMN) do
        place(slotID, "TOPLEFT", 16, columnTop - (index - 1) * (SLOT_SIZE + SLOT_GAP))
    end
    for index, slotID in ipairs(RIGHT_COLUMN) do
        place(slotID, "TOPRIGHT", -16, columnTop - (index - 1) * (SLOT_SIZE + SLOT_GAP))
    end

    -- Waffen unten mittig, als Gruppe.
    local weapons = CreateFrame("Frame", nil, doll)
    weapons:SetWidth(#BOTTOM_ROW * SLOT_SIZE + (#BOTTOM_ROW - 1) * SLOT_GAP)
    weapons:SetHeight(SLOT_SIZE)
    weapons:SetPoint("BOTTOM", doll, "BOTTOM", 0, 16)
    for index, slotID in ipairs(BOTTOM_ROW) do
        local slot = Theme.ItemSlot(weapons, slotID, SLOT_SIZE)
        slot:SetPoint("LEFT", weapons, "LEFT", (index - 1) * (SLOT_SIZE + SLOT_GAP), 0)
        slot:SetScript("OnEnter", function(button) self:ShowSlotTooltip(button) end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.slots[slotID] = slot
    end

    -- Mitte: Talente, Gildenrang, Snapshots — ruhig, in Friz.
    self.centerTitle = Theme.Label(doll, "", fonts.big, Theme.color.heading)
    self.centerTitle:SetPoint("TOP", doll, "TOP", 0, columnTop - 6)

    self.centerBody = Theme.Label(doll, "", fonts.body, Theme.color.textDim)
    self.centerBody:SetPoint("TOP", self.centerTitle, "BOTTOM", 0, -8)
    self.centerBody:SetWidth(280)
    self.centerBody:SetJustifyH("CENTER")
    self.centerBody:SetSpacing(4)

    -- Itemlevel-Verlauf: in der Mitte, wo im Charakterfenster das 3D-Modell
    -- steht. Balken statt Linie — siehe Widgets.LevelChart.
    self.historyTitle = Theme.Label(doll, L.GEAR_HISTORY, fonts.heading, Theme.color.heading)
    self.historyTitle:SetPoint("TOP", self.centerBody, "BOTTOM", 0, -14)

    self.history = Widgets.LevelChart(doll, 24)
    self.history:SetWidth(300)
    self.history:SetHeight(104)
    self.history:SetPoint("TOP", self.historyTitle, "BOTTOM", 0, -6)

    self.historyHint = Theme.Label(doll, L.GEAR_DISCRETE, fonts.small, Theme.color.textFaint)
    self.historyHint:SetPoint("TOP", self.history, "BOTTOM", 0, -4)

    self.frame = frame
    return frame
end

-- ================================================================== Tooltip ---

function Armory:ShowSlotTooltip(button)
    local item = button.item
    if not item or not item.link then return end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    -- Eigener Charakter: SetInventoryItem zeigt den vollen Tooltip inklusive
    -- Vergleich. Fremde: nur der Link — mehr gibt es nicht.
    local own = self.selectedGuid == Compat.GetPlayerIdentity().guid
    local ok = false
    if own then
        ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", button.slotID)
    end
    if not ok then
        ok = pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
    end
    if ok then GameTooltip:Show() end
end

-- ================================================================== Refresh ---

function Armory:RefreshCharacters()
    local list = GA.Core.Database:ListCharacters(self.filter)
    if not self.selectedGuid then
        local own = Compat.GetPlayerIdentity().guid
        self.selectedGuid = own or (list[1] and list[1].guid)
    end
    self.characters:SetData(list)
end

function Armory:RefreshDoll()
    local character = self.selectedGuid and GA.Core.Database.account.characters[self.selectedGuid]
    local identity = Compat.GetPlayerIdentity()
    local own = character and character.guid == identity.guid

    if not character then
        self.name:SetText("")
        self.meta:SetText("")
        self.stamp:SetText(L.ARMORY_NO_DATA)
        self.centerTitle:SetText("")
        self.centerBody:SetText("")
        self.history:SetPoints(nil, L.GEAR_NO_HISTORY)
        self.historyHint:Hide()
        for _, slot in pairs(self.slots) do slot:SetItem(nil) end
        return
    end

    -- Kopf
    local r, g, b = Util.ClassColor(character.class)
    self.name:SetText(character.name or "?")
    self.name:SetTextColor(r, g, b)

    local pieces = {}
    if character.level then pieces[#pieces + 1] = string.format(L.LEVEL_FMT, tostring(character.level)) end
    if character.raceName then pieces[#pieces + 1] = character.raceName end
    if character.className then pieces[#pieces + 1] = character.className end
    if character.guildRank then pieces[#pieces + 1] = character.guildRank end
    self.meta:SetText(table.concat(pieces, "  ·  "))

    if own then
        if not Theme.SetPortrait(self.portrait, "player") then
            Theme.Paint(self.portrait, Theme.color.rowAltBg)
        end
    else
        -- Kein Portrait fuer Fremde: Es gaebe nur ein falsches.
        Theme.Paint(self.portrait, Theme.color.rowAltBg)
    end

    if not Theme.SetClassIcon(self.classIcon, character.class) then
        self.classIcon:Hide()
    else
        self.classIcon:Show()
    end

    local level = character.itemLevel and character.itemLevel.value
    self.ilvlValue:SetText(level and tostring(level) or "—")

    -- Zeitstempel und Quelle
    if character.equipmentTs then
        local ago = Util.TimeAgo(character.equipmentTs)
        if own then
            self.stamp:SetText(string.format(L.ARMORY_SNAPSHOT, ago))
            self.stamp:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
        else
            local source = character.source and L["SOURCE_" .. character.source] or L.UNKNOWN
            self.stamp:SetText(string.format(L.ARMORY_STALE, ago) .. "  ·  " .. tostring(source))
            self.stamp:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
        end
    else
        self.stamp:SetText(L.ARMORY_NO_DATA)
        self.stamp:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    -- Slots
    for slotID, slot in pairs(self.slots) do
        slot:SetItem(character.equipment and character.equipment[slotID] or nil)
    end

    -- Mitte
    local snapshots = GA.Modules.Equipment:GetSnapshots(character.guid)
    local lines = {}
    if character.guildRank then lines[#lines + 1] = character.guildRank end
    if character.itemLevel and character.itemLevel.count then
        lines[#lines + 1] = string.format(L.DASH_EQUIPPED, character.itemLevel.count, 17)
    end
    if character.loadout and character.loadout.value then
        lines[#lines + 1] = L.ARMORY_LOADOUT_CAPTURED
    end
    if #snapshots > 0 then
        lines[#lines + 1] = string.format(L.ARMORY_SNAPSHOT_COUNT, #snapshots, Util.TimeAgo(snapshots[1].ts))
    end
    self.centerTitle:SetText(own and L.ARMORY_OWN or (character.guildName or GA.Core.Database.account.guild.name or L.ARMORY_GUILD_MEMBER))
    self.centerBody:SetText(table.concat(lines, "\n"))

    -- Verlauf: ein Punkt je erfasstem Stand.
    local points = {}
    for _, snapshot in ipairs(snapshots) do
        if snapshot.itemLevel then
            points[#points + 1] = { ts = snapshot.ts, value = snapshot.itemLevel }
        end
    end
    self.history:SetPoints(points, L.GEAR_NO_HISTORY)
    if #points > 1 then self.historyHint:Show() else self.historyHint:Hide() end

    GA.UI.MainFrame:SetContext(level and (L.DASH_ITEMLEVEL .. " " .. level) or "")
end

--- Inspect-Knopf und Statuszeile nach Ziel und laufender Anfrage.
function Armory:RefreshInspect()
    local Inspect = GA.Modules.Inspect
    if not Inspect or not self.inspectButton then return end

    local can, reason = Inspect:CanRequest("target")
    self.inspectButton:SetEnabledState(can, can and nil or (L["INSPECT_REASON_" .. tostring(reason)] or reason))

    if Inspect:IsPending() then
        self.inspectStatus:SetText(string.format(L.ARMORY_INSPECT_SENT, UnitName("target") or "?"))
    elseif can then
        self.inspectStatus:SetText(UnitName("target") or "")
    else
        self.inspectStatus:SetText(L["INSPECT_REASON_" .. tostring(reason)] or L.ARMORY_INSPECT_HINT)
    end
end

function Armory:Refresh()
    self:RefreshCharacters()
    self:RefreshDoll()
    self:RefreshInspect()
end

-- Zielwechsel betrifft nur den Inspect-Knopf. Die teuren Listen bleiben stehen.
GA.Core.Callbacks:On("TARGET_CHANGED", function()
    if Armory.frame and Armory.frame:IsVisible() then Armory:RefreshInspect() end
end, "ArmoryView")

GA.Core.Callbacks:On("INSPECT_REQUESTED", function()
    if Armory.frame and Armory.frame:IsVisible() then Armory:RefreshInspect() end
end, "ArmoryView")

GA.UI.MainFrame:RegisterView("armory", Armory)
