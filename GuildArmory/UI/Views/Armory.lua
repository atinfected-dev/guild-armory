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
local TWIN_SIZE = 26    -- die BiS-Kachel neben dem Platz, kleiner als das Getragene (08.10.2026)
local TWIN_GAP = 4

--- Anordnung wie im Charakterfenster.
local LEFT_COLUMN  = { 1, 2, 3, 15, 5, 4, 19, 9 }     -- Kopf .. Handgelenke
local RIGHT_COLUMN = { 10, 6, 7, 8, 11, 12, 13, 14 }  -- Haende .. Schmuck 2
local BOTTOM_ROW   = { 16, 17, 18 }                   -- Waffenhand, Schildhand, Distanz

--- Als Funktion, nicht als Tabelle: Eine beim Laden gebaute Spaltenliste
--- traegt die Beschriftungen der Sprache, die beim Laden galt — und die
--- Einstellung steht erst bei PLAYER_LOGIN fest.
---
--- DIE SPALTEN (Entwurf A, 27.09.2026): Wappen, Name mit Online-Punkt,
--- Stufe, Itemlevel mit Balken. Die Klasse als Text ist weg — sie kam mal
--- gross, mal klein, je nach Sprache des Rosters, und das Wappen sagt sie
--- ohne ein Wort. Die Breiten stehen HIER und nirgends sonst: Die Zeilen
--- rechnen ihre Positionen aus dieser Liste, damit Kopf und Zeile nicht
--- auseinanderlaufen koennen.
local COLUMN_GAP = 6
local COLUMN_X0 = 8

local function characterColumns()
    return {
        { key = "crest", label = "",          width = 16 },
        { key = "name",  label = L.COL_NAME,  width = 138 },
        { key = "level", label = L.COL_LEVEL, width = 28, justify = "RIGHT" },
        { key = "ilvl",  label = L.COL_ILVL,  width = 64, justify = "RIGHT" },
    }
end

--- Linke Kante jeder Spalte, aus characterColumns() gerechnet.
local function columnOffsets()
    local x, out = COLUMN_X0, {}
    for _, column in ipairs(characterColumns()) do
        out[column.key] = x
        x = x + column.width + COLUMN_GAP
    end
    return out
end

-- ================================================================== Aufbau ----

function Armory:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ---------------------------------------------------- Linke Spalte ------

    local listPanel = Widgets.Panel(frame, L.ARMORY_CHARACTERS)
    listPanel:SetWidth(300)
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
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, character) self:UpdateRow(row, character) end,
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

    self.ilvlValue = Theme.Label(doll, "", fonts.hero, Theme.color.goldBright)
    self.ilvlValue:SetPoint("TOPRIGHT", doll, "TOPRIGHT", -20, -16)
    self.ilvlLabel = Theme.Label(doll, L.DASH_ITEMLEVEL, fonts.body, Theme.color.textDim)
    self.ilvlLabel:SetPoint("TOPRIGHT", self.ilvlValue, "BOTTOMRIGHT", 0, -2)

    -- Talente (03.10.2026): oeffnet den nachgebauten Baum dieses Charakters.
    self.talentButton = Widgets.Button(doll, L.TALENTS_BUTTON, function()
        local character = self.selectedGuid and GA.Core.Database.account.characters[self.selectedGuid]
        if character and GA.UI.TalentFrame then GA.UI.TalentFrame:Toggle(character) end
    end)
    self.talentButton:SetPoint("TOPRIGHT", self.ilvlLabel, "BOTTOMRIGHT", 2, -6)

    -- "BiS 3 von 12": wie viele der gesetzten Teile getragen werden.
    self.bisStand = Theme.Label(doll, "", fonts.small, Theme.color.goldBright)
    self.bisStand:SetPoint("RIGHT", self.talentButton, "LEFT", -10, 0)
    self.talentButton:HookScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TALENTS_BUTTON, 1, 1, 1)
        GameTooltip:AddLine(button.hint or "", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    self.talentButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- DIE ZEILE ENDET VOR DEM ITEMLEVEL. Gemeldet 27.09.2026 mit Bild:
    -- "Level 20 · Windshaper Skyborne · Shaman · Guild Master" lief in
    -- "Item level" hinein. Sie hatte kein rechtes Ende, und die Klassenkachel
    -- hing hinten dran — bei einem langen Rassennamen stand beides ueber der
    -- Zahl. Die Kachel ist weg: Die Klasse steht als Wort in der Zeile und
    -- als Wappen in der Liste; ein drittes Mal sagt sie nichts Neues.
    self.meta = Theme.Label(doll, "", fonts.body, Theme.color.textDim)
    self.meta:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 1, -3)
    self.meta:SetPoint("RIGHT", self.ilvlLabel, "LEFT", -16, 0)
    self.meta:SetJustifyH("LEFT")
    self.meta:SetWordWrap(false)

    -- Zeitstempel/Quelle — die Regel aus dem Dateikopf.
    self.stamp = Theme.Label(doll, "", fonts.small, Theme.color.textFaint)
    self.stamp:SetPoint("TOPLEFT", self.meta, "BOTTOMLEFT", 0, -6)
    self.stamp:SetPoint("RIGHT", self.ilvlValue, "LEFT", -12, 0)
    self.stamp:SetJustifyH("LEFT")

    -- Spielzeit (06.10.2026): wie /played, gesamt und auf dieser Stufe.
    self.played = Theme.Label(doll, "", fonts.small, Theme.color.textDim)
    self.played:SetPoint("TOPLEFT", self.stamp, "BOTTOMLEFT", 0, -3)
    self.played:SetPoint("RIGHT", self.ilvlValue, "LEFT", -12, 0)
    self.played:SetJustifyH("LEFT")

    -- Slots
    self.slots = {}
    local columnTop = -92

    -- JEDER PLATZ TRAEGT SEINEN NAMEN. Bei leeren Plaetzen raet man sonst,
    -- welcher es ist — die Silhouette allein sagt es bei Ring und Schmuck
    -- nicht. Die Namen kommen vom Client in seiner Sprache
    -- (Compat.SlotName), nicht aus einer eigenen Liste.
    --- @param relativeTo Frame|nil  woran der Name haengt — die BiS-Kachel, wo es eine gibt
    local function beschriften(slot, slotID, anchorPoint, relativePoint, x, y, relativeTo)
        local label = Theme.Label(slot, Compat.SlotName(slotID), fonts.small, Theme.color.textDim)
        label:SetPoint(anchorPoint, relativeTo or slot, relativePoint, x, y)
        slot.label = label
    end

    local function place(slotID, anchorPoint, x, y)
        local slot = Theme.ItemSlot(doll, slotID, SLOT_SIZE)
        slot:SetPoint(anchorPoint, doll, anchorPoint, x, y)
        slot:SetScript("OnEnter", function(button) self:ShowSlotTooltip(button) end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.slots[slotID] = slot
        return slot
    end

    -- DIE BiS-KACHEL NEBEN DEM PLATZ (08.10.2026, Entwurf A): kleiner als
    -- das Getragene, zwischen Platz und Namen. Leer und blass, wo nichts
    -- gesetzt ist; gold mit dem Platz zusammen, wenn das Teil getragen wird.
    -- Hemd und Wappenrock haben keine.
    self.twins = {}
    local BIS_OK = {}
    for _, id in ipairs(GA.Modules.Wishlist.BIS_SLOTS) do BIS_OK[id] = true end
    local function twin(slot, slotID, side)
        if not BIS_OK[slotID] then return nil end
        local t = Theme.ItemSlot(doll, slotID, TWIN_SIZE)
        t.level:Hide()
        if side == "RIGHT" then t:SetPoint("LEFT", slot, "RIGHT", TWIN_GAP, 0)
        elseif side == "LEFT" then t:SetPoint("RIGHT", slot, "LEFT", -TWIN_GAP, 0)
        else t:SetPoint("LEFT", slot, "RIGHT", TWIN_GAP, 0) end
        t:SetScript("OnEnter", function(button) self:ShowTwinTooltip(button) end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.twins[slotID] = t
        return t
    end

    for index, slotID in ipairs(LEFT_COLUMN) do
        local slot = place(slotID, "TOPLEFT", 16, columnTop - (index - 1) * (SLOT_SIZE + SLOT_GAP))
        local t = twin(slot, slotID, "RIGHT")
        beschriften(slot, slotID, "LEFT", "RIGHT", 6, 0, t)
    end
    for index, slotID in ipairs(RIGHT_COLUMN) do
        local slot = place(slotID, "TOPRIGHT", -16, columnTop - (index - 1) * (SLOT_SIZE + SLOT_GAP))
        local t = twin(slot, slotID, "LEFT")
        beschriften(slot, slotID, "RIGHT", "LEFT", -6, 0, t)
        slot.label:SetJustifyH("RIGHT")
    end

    -- Waffen unten mittig, als Gruppe.
    -- DIE WAFFEN STEHEN WEITER AUSEINANDER ALS DIE SPALTEN. Ihre Namen
    -- stehen DARUNTER, nicht daneben — und "Main Hand" ist breiter als ein
    -- Slot. Mit dem Spaltenabstand klebten die drei Namen zu "Main HandOff
    -- Hand Ranged" zusammen (gemeldet 27.09.2026 mit Bild).
    -- Breiter als vorher: Rechts von jeder Waffe steht ihre BiS-Kachel.
    local WEAPON_GAP = 24 + TWIN_SIZE + TWIN_GAP
    local weapons = CreateFrame("Frame", nil, doll)
    weapons:SetWidth(#BOTTOM_ROW * SLOT_SIZE + (#BOTTOM_ROW - 1) * WEAPON_GAP)
    weapons:SetHeight(SLOT_SIZE)
    weapons:SetPoint("BOTTOM", doll, "BOTTOM", 0, 26)
    self.weapons = weapons
    for index, slotID in ipairs(BOTTOM_ROW) do
        local slot = Theme.ItemSlot(weapons, slotID, SLOT_SIZE)
        slot:SetPoint("LEFT", weapons, "LEFT", (index - 1) * (SLOT_SIZE + WEAPON_GAP), 0)
        slot:SetScript("OnEnter", function(button) self:ShowSlotTooltip(button) end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        beschriften(slot, slotID, "TOP", "BOTTOM", 0, -2)
        self.slots[slotID] = slot
        local t = twin(slot, slotID, "RIGHT")
        if t then t:SetParent(weapons) end
    end

    -- ---------------------------------------------------- Die Mitte ---------
    --
    -- Entwurf A (27.09.2026): Der Charakter steht als MODELL in der Mitte,
    -- wie im Charakterfenster — darunter der Itemlevel-Verlauf. Das Modell
    -- gibt es nur, wenn der Charakter als Einheit da ist (man selbst, Ziel,
    -- Gruppe); fuer alle anderen bleibt die Textmitte von vorher. Ein
    -- fremdes Modell mit seinen Gegenstaenden anzuziehen zeigte die falsche
    -- Rasse mit dem richtigen Helm — und das waere eine Erfindung.
    --
    -- Der Verlauf sitzt fest UNTEN, ueber den Waffen: So bleibt er an
    -- derselben Stelle, ob darueber das Modell steht oder der Text.
    self.historyHint = Theme.Label(doll, L.GEAR_DISCRETE, fonts.small, Theme.color.textFaint)
    self.historyHint:SetPoint("BOTTOM", weapons, "TOP", 0, 10)

    self.history = Widgets.LevelChart(doll, 24)
    self.history:SetWidth(300)
    self.history:SetHeight(84)
    self.history:SetPoint("BOTTOM", self.historyHint, "TOP", 0, 2)

    self.historyTitle = Theme.Label(doll, L.GEAR_HISTORY, fonts.heading, Theme.color.heading)
    self.historyTitle:SetPoint("BOTTOM", self.history, "TOP", 0, 4)

    -- Das Modell fuellt den Raum zwischen den Slotspalten und dem Verlauf.
    -- GROESSE DER FIGUR NICHT UEBER DEN RAHMEN: Ein kleinerer Rahmen zeigt
    -- die Figur GROESSER und schneidet sie ab (gemessen 08.10.2026, Bild) —
    -- der Rahmen ist ein Fenster auf die Figur, keine Leinwand. Kleiner
    -- wird sie ueber die Kamera, siehe Compat.FitModel.
    -- Ob es den Rahmentyp gibt, sagt Compat — nicht diese Datei.
    local model = Compat.CreateDressUpModel(doll)
    if model then
        model:SetPoint("TOPLEFT", doll, "TOPLEFT", 16 + SLOT_SIZE + 76, columnTop)
        model:SetPoint("BOTTOMRIGHT", self.historyTitle, "TOP", 0, 6)
        model:SetPoint("RIGHT", doll, "RIGHT", -(16 + SLOT_SIZE + 76), 0)
        model:Hide()
    end
    self.model = model

    -- Die Textmitte: Gildenrang, Plaetze, Staende — der Rueckfall ohne
    -- Einheit, und bis dahin genau das, was vorher hier stand.
    self.centerTitle = Theme.Label(doll, "", fonts.big, Theme.color.heading)
    self.centerTitle:SetPoint("TOP", doll, "TOP", 0, columnTop - 30)

    self.centerBody = Theme.Label(doll, "", fonts.body, Theme.color.textDim)
    self.centerBody:SetPoint("TOP", self.centerTitle, "BOTTOM", 0, -8)
    self.centerBody:SetWidth(280)
    self.centerBody:SetJustifyH("CENTER")
    self.centerBody:SetSpacing(4)

    self.frame = frame
    return frame
end

-- ================================================================== Zeilen ----

--- Baut die feste Form einer Listenzeile: Wappen, Name, Online-Punkt,
--- Stufe, Balken und Zahl. Die Positionen kommen aus characterColumns() —
--- dieselbe Quelle wie die Kopfzeile, damit beides zusammen wandert.
function Armory:BuildRow(row)
    local fonts = Theme.Fonts()
    local x = columnOffsets()
    local columns = {}
    for _, column in ipairs(characterColumns()) do columns[column.key] = column end

    row.edge = Theme.Fill(row, Theme.color.gold)
    row.edge:ClearAllPoints()
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(2)
    row.edge:Hide()

    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(14) row.crest:SetHeight(14)
    row.crest:SetPoint("LEFT", row, "LEFT", x.crest, 0)

    row.nameText = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.nameText:SetPoint("LEFT", row, "LEFT", x.name, 0)
    row.nameText:SetWidth(columns.name.width - 10)
    row.nameText:SetJustifyH("LEFT")
    -- Ein Wort, das nicht passt, wird abgeschnitten, nicht umgebrochen: Eine
    -- zweizeilige Zeile ist keine mehr.
    row.nameText:SetWordWrap(false)

    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetWidth(5) row.dot:SetHeight(5)
    row.dot:SetPoint("LEFT", row, "LEFT", x.name + columns.name.width - 6, 0)

    row.levelText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.levelText:SetPoint("LEFT", row, "LEFT", x.level, 0)
    row.levelText:SetWidth(columns.level.width)
    row.levelText:SetJustifyH("RIGHT")

    -- Balken links, Zahl rechts — die Zahl ist die Auskunft, der Balken die
    -- Einordnung auf einen Blick.
    row.barBg = row:CreateTexture(nil, "ARTWORK")
    Theme.BarTrough(row.barBg)
    row.barBg:SetWidth(34) row.barBg:SetHeight(5)
    row.barBg:SetPoint("LEFT", row, "LEFT", x.ilvl, 0)

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(row.barFill, Theme.color.goldDim)
    row.barFill:SetHeight(5)
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)

    row.ilvlText = Theme.Label(row, "", fonts.rowBold, Theme.color.goldBright)
    row.ilvlText:SetPoint("LEFT", row, "LEFT", x.ilvl + 40, 0)
    row.ilvlText:SetWidth(columns.ilvl.width - 40)
    row.ilvlText:SetJustifyH("RIGHT")
end

--- Fuellt eine Zeile. Laeuft je sichtbarer Zeile bei jedem Auffrischen —
--- deshalb nichts Neues anlegen, nur setzen.
function Armory:UpdateRow(row, character)
    local selected = character.guid == self.selectedGuid
    local r, g, b = Theme.ClassColor(character.class)

    -- Die gewaehlte Zeile: goldene Kante und der Hover-Grund, damit sie auch
    -- ohne Maus darueber als gewaehlt zu erkennen ist. ScrollList hat den
    -- Grund vorher nach gerade/ungerade gemalt; hier wird er uebermalt.
    if selected then
        row.edge:Show()
        Theme.Paint(row.background, Theme.color.rowHover)
    else
        row.edge:Hide()
    end

    if not Theme.SetClassPortrait(row.crest, character.class) then
        row.crest:Hide()
    else
        row.crest:Show()
    end

    row.nameText:SetText(character.name or "?")
    row.nameText:SetTextColor(r, g, b)

    -- Online ist eine Auskunft des Rosters. Fehlt sie, gibt es keinen Punkt
    -- — ein grauer Punkt hiesse "offline", und das ist etwas anderes als
    -- "weiss nicht".
    local online = self.online and (self.online[character.guid]
        or (character.name and self.online[string.lower(Util.ShortName(character.name))]))
    if online == nil then
        row.dot:Hide()
    else
        row.dot:Show()
        Theme.Paint(row.dot, online and Theme.color.good or Theme.color.border)
    end

    row.levelText:SetText(character.level and tostring(character.level) or "")

    local value = character.itemLevel and character.itemLevel.value
    if value then
        row.ilvlText:SetText(tostring(value))
        local anteil = (self.bestIlvl or 0) > 0 and (value / self.bestIlvl) or 0
        row.barFill:SetWidth(math.max(1, math.floor(34 * anteil)))
        row.barBg:Show() row.barFill:Show()
    else
        -- Ungemessen ist nicht null: kein Balken, ein Strich.
        row.ilvlText:SetText("—")
        row.barBg:Hide() row.barFill:Hide()
    end
end

-- ================================================================== Tooltip ---

--- Tooltip der BiS-Kachel: der Gegenstand, davor "Best in Slot".
function Armory:ShowTwinTooltip(button)
    local item = button.item
    if item and item.itemID and Widgets.ShowItemTooltip(button, item.itemID) then
        GameTooltip:AddLine(button.gold and button.gold:IsShown() and L.ARMORY_BIS_WORN or L.ARMORY_BIS_WANTED,
            1, 0.84, 0.35)
    else
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.ARMORY_BIS_NONE, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

function Armory:ShowSlotTooltip(button)
    local item = button.item

    -- DIE KENNUNG GENUEGT, DER LINK IST DIE KUER.
    --
    -- Hier stand `if not item.link then return end` — und drei Zeilen
    -- weiter unten der Kommentar, der Weg komme auch ohne Link aus. Die
    -- Wache hat ihn nie erreichen lassen: Ein Charakter aus dem
    -- Gildenabgleich hat NIE einen Link, weil nur itemID, itemLevel und
    -- enchantID uebertragen werden. Damit blieb jeder fremde Gegenstand
    -- ohne Tooltip, waehrend sein Symbol daneben stand.
    if not item or not (item.link or item.itemID) then return end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    -- Eigener Charakter: SetInventoryItem zeigt den vollen Tooltip inklusive
    -- Vergleich. Fremde: nur der Link — mehr gibt es nicht.
    local own = self.selectedGuid == Compat.GetPlayerIdentity().guid
    local ok = false
    if own then
        ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", button.slotID)
    end
    if ok then
        GameTooltip:Show()
        return
    end

    -- Sonst der gemeinsame Weg: Er kommt auch ohne Link aus, und bei
    -- fremden Charakteren aus dem Abgleich ist oft nur die ID da.
    GA.UI.Widgets.ShowItemTooltip(button, item.itemID, item.link)
end

-- ================================================================== Refresh ---

function Armory:RefreshCharacters()
    local list = GA.Core.Database:ListCharacters(self.filter)
    if not self.selectedGuid then
        local own = Compat.GetPlayerIdentity().guid
        self.selectedGuid = own or (list[1] and list[1].guid)
    end

    -- EINMAL JE LISTE, NICHT JE ZEILE. Wer online ist, steht im Roster; die
    -- Zeile fragt nachher nur noch nach. Bei 23 Mitgliedern und 16 Zeilen
    -- waeren es sonst 368 Vergleiche je Auffrischen — nicht viel, aber die
    -- Sorte Schleife, die sich summiert.
    local online = {}
    for _, member in pairs(GA.Core.Database.account.guild.members or {}) do
        if member.guid then online[member.guid] = member.online and true or false end
        if member.name then online[string.lower(member.name)] = member.online and true or false end
    end
    self.online = online

    -- Der Balken ist RELATIV zum Besten der Liste: Ein Balken gegen 60 waere
    -- bei einer Gilde auf Stufe 20 ueberall gleich kurz und sagte nichts.
    local best = 0
    for _, character in ipairs(list) do
        local value = character.itemLevel and character.itemLevel.value
        if value and value > best then best = value end
    end
    self.bestIlvl = best

    self.characters:SetData(list)
end

function Armory:RefreshDoll()
    local character = self.selectedGuid and GA.Core.Database.account.characters[self.selectedGuid]
    local identity = Compat.GetPlayerIdentity()
    local own = character and character.guid == identity.guid

    -- Der Talente-Knopf: an, wenn es einen Stand gibt; sein Hinweis sagt,
    -- woher und wie alt.
    if self.talentButton then
        local hat = character and (character.loadout or own)
        if self.talentButton.SetEnabled then self.talentButton:SetEnabled(hat and true or false) end
        self.talentButton:SetAlpha(hat and 1 or 0.45)
        if character and character.loadout and character.loadout.ts then
            local quelle = own and L.TALENTS_SRC_SELF
                or (character.loadout.source == "inspect" and L.TALENTS_SRC_INSPECT or L.TALENTS_SRC_SYNC)
            self.talentButton.hint = string.format(L.TALENTS_FOOT, Util.TimeAgo(character.loadout.ts), quelle)
        else
            self.talentButton.hint = own and L.TALENTS_SRC_SELF or L.TALENTS_NONE_HINT
        end
    end

    if not character then
        self.name:SetText("")
        self.meta:SetText("")
        self.stamp:SetText(L.ARMORY_NO_DATA)
        self.centerTitle:SetText("")
        self.centerBody:SetText("")
        self.history:SetPoints(nil, L.GEAR_NO_HISTORY)
        self.historyHint:Hide()
        if self.model then self.model:Hide() end
        self.modelKey = nil
        self.centerTitle:Show()
        self.centerBody:Show()
        for _, slot in pairs(self.slots) do slot:SetItem(nil) slot:SetGold(false) end
        for _, t in pairs(self.twins) do t:SetItem(nil) t:SetGold(false) t:SetAlpha(0.3) end
        self.bisStand:SetText("")
        return
    end

    -- Kopf
    local r, g, b = Theme.ClassColor(character.class)
    self.name:SetText(character.name or "?")
    self.name:SetTextColor(r, g, b)

    local pieces = {}
    if character.level then pieces[#pieces + 1] = string.format(L.LEVEL_FMT, tostring(character.level)) end
    if character.raceName then pieces[#pieces + 1] = character.raceName end
    if character.className then pieces[#pieces + 1] = character.className end
    if character.guildRank then pieces[#pieces + 1] = character.guildRank end
    self.meta:SetText(table.concat(pieces, "  ·  "))

    -- DAS KLASSENWAPPEN IST KEINE ERFINDUNG, EIN RASSENBILD WAERE EINE.
    --
    -- Hier stand "kein Portrait fuer Fremde: es gaebe nur ein falsches", und
    -- das stimmt fuer ein Rassenportrait: Blizzards Vorlagen brauchen Rasse
    -- UND Geschlecht, und das Geschlecht wird nicht uebertragen. Wer es
    -- raet, zeigt jedem zweiten Charakter das falsche Gesicht.
    --
    -- Die Klasse dagegen steht im Gildenroster, ist also bekannt. Ein leerer
    -- goldener Ring war deshalb zu viel Zurueckhaltung: Er sagt nichts,
    -- obwohl etwas zu sagen waere.
    self.portrait:SetTexCoord(0, 1, 0, 1)
    local gesetzt = false
    if own then gesetzt = Theme.SetPortrait(self.portrait, "player") end
    if not gesetzt then gesetzt = Theme.SetClassPortrait(self.portrait, character.class) end
    if not gesetzt then Theme.Paint(self.portrait, Theme.color.rowAltBg) end


    local level = character.itemLevel and character.itemLevel.value
    self.ilvlValue:SetText(level and tostring(level) or "—")

    -- "Itemlevel · 10 von 17" unter der grossen Zahl: Die Zahl allein sagt
    -- nicht, aus wie vielen Plaetzen sie kommt — und 21 aus zehn Plaetzen ist
    -- etwas anderes als 21 aus siebzehn.
    local count = character.itemLevel and character.itemLevel.count
    if count then
        self.ilvlLabel:SetText(L.DASH_ITEMLEVEL .. "  ·  " .. string.format(L.DASH_EQUIPPED, count, 17))
    else
        self.ilvlLabel:SetText(L.DASH_ITEMLEVEL)
    end

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

    local played = character.played
    local total = played and GA.Modules.Equipment.FormatPlayed(played.total)
    if total then
        local level = GA.Modules.Equipment.FormatPlayed(played.level)
        self.played:SetText(level and string.format(L.ARMORY_PLAYED_LEVEL, total, level) or string.format(L.ARMORY_PLAYED, total))
    else
        self.played:SetText("")
    end

    -- Slots — und ihre Namen: gedaempft, wo etwas steckt, leise, wo nichts.
    local bisStatus, bisWorn, bisSet = GA.Modules.Wishlist:BisStatus(character.guid)
    for slotID, slot in pairs(self.slots) do
        local item = character.equipment and character.equipment[slotID] or nil
        slot:SetItem(item)
        if slot.label then
            local farbe = item and Theme.color.textDim or Theme.color.textFaint
            slot.label:SetTextColor(farbe[1], farbe[2], farbe[3])
        end
        -- Die BiS-Kachel daneben — und beide gold, wenn das Teil getragen wird.
        local st = bisStatus[slotID]
        local t = self.twins[slotID]
        if t then
            t:SetItem(st and st.itemID and { itemID = st.itemID } or nil)
            t:SetAlpha(st and st.itemID and 1 or 0.3)
            t:SetGold(st and st.worn)
        end
        slot:SetGold(st and st.worn)
    end
    self.bisStand:SetText(bisSet > 0 and string.format(L.ARMORY_BIS, bisWorn, bisSet) or "")

    -- DAS MODELL, WENN ES EINE EINHEIT GIBT — sonst der Text.
    --
    -- Man selbst immer; andere nur, wenn sie als Ziel oder in der Gruppe
    -- da sind. Wer nicht in Reichweite ist, bekommt kein Modell, weil es
    -- keines von IHM waere.
    local unit = own and "player" or Compat.FindUnitByGUID(character.guid)

    -- SetUnit NUR, WENN SICH ETWAS GEAENDERT HAT.
    --
    -- GEMELDET 27.09.2026: "es blinkt." SetUnit laedt das Modell neu, und
    -- RefreshDoll laeuft nicht nur beim Klick auf einen Charakter, sondern
    -- auch bei jedem GET_ITEM_INFO_RECEIVED — das feuert, sobald irgendwer
    -- irgendein Item nachlaedt, alle 0,4 s gebuendelt. Jedes Mal wurde die
    -- Figur weggenommen und neu aufgebaut: ein Blitzen im Halbsekundentakt.
    --
    -- Gemerkt wird, welche Einheit fuer welchen Charakter zuletzt gesetzt
    -- wurde. Dieselbe wieder zu setzen ist kein Auffrischen, sondern ein
    -- Neuladen ohne Anlass.
    -- ZWEI WEGE ZUM MODELL. Ist der Charakter als Einheit da, zeigt das
    -- Modell IHN — live, mit allem, was er gerade traegt. Ist er es nicht,
    -- wird die Figur aus dem zusammengesetzt, was gemessen ist: Rasse,
    -- Geschlecht, Gegenstaende (27.09.2026, "ja bau das"). Der Schluessel
    -- traegt den Weg und den Stand, damit ein Wechsel neu laedt und ein
    -- blosses Auffrischen nicht.
    local schluessel
    if unit then
        schluessel = "unit:" .. tostring(unit) .. ":" .. tostring(character.guid)
    elseif character.raceID and character.sex then
        schluessel = "dress:" .. tostring(character.guid) .. ":" .. tostring(character.equipmentTs or 0)
    end

    local modellSteht
    if self.model and schluessel then
        if self.modelKey == schluessel and self.model:IsShown() then
            modellSteht = true
        elseif unit then
            modellSteht = Compat.ShowUnitInModel(self.model, unit)
            self.modelKey = modellSteht and schluessel or nil
        else
            local items = {}
            for _, entry in pairs(character.equipment or {}) do
                if entry.itemID then items[#items + 1] = entry.itemID end
            end
            modellSteht = Compat.DressModel(self.model, character.raceID, character.sex, items)
            self.modelKey = modellSteht and schluessel or nil
        end
    end

    if modellSteht then
        self.model:Show()
        self.centerTitle:Hide()
        self.centerBody:Hide()
    else
        if self.model then self.model:Hide() end
        self.modelKey = nil
        self.centerTitle:Show()
        self.centerBody:Show()
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

-- NACHGELIEFERTE ITEMS ZEICHNEN NACH.
--
-- Bei einem Charakter aus dem Gildenabgleich kennt dieser Client die
-- Gegenstaende oft noch gar nicht: Er bekommt nur Kennungen und muss sie beim
-- Server nachladen. Ohne diese Zeile blieben die Plaetze leer, bis jemand die
-- Ansicht wechselt und zurueckkommt — und es saehe aus, als fehlten die Daten.
--
-- GEBUENDELT, NICHT JE GEGENSTAND. Beim Oeffnen eines Charakters kommen
-- siebzehn Antworten kurz hintereinander; siebzehnmal die Papierpuppe neu zu
-- bauen waere sichtbares Ruckeln fuer nichts.
local nachzeichnen = false
GA.Core.Events:Register("GET_ITEM_INFO_RECEIVED", function()
    if nachzeichnen then return end
    if not (Armory.frame and Armory.frame:IsVisible()) then return end
    nachzeichnen = true
    GA.Core.Compat.After(0.4, function()
        nachzeichnen = false
        if Armory.frame and Armory.frame:IsVisible() then Armory:RefreshDoll() end
    end)
end, "ArmoryView")

-- Zielwechsel betrifft nur den Inspect-Knopf. Die teuren Listen bleiben stehen.
GA.Core.Callbacks:On("TARGET_CHANGED", function()
    if Armory.frame and Armory.frame:IsVisible() then Armory:RefreshInspect() end
end, "ArmoryView")

GA.Core.Callbacks:On("INSPECT_REQUESTED", function()
    if Armory.frame and Armory.frame:IsVisible() then Armory:RefreshInspect() end
end, "ArmoryView")

GA.UI.MainFrame:RegisterView("armory", Armory)
