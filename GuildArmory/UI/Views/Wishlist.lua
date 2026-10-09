--[[----------------------------------------------------------------------------
    Views/Wishlist — die eigene Wunschliste pflegen, die der Gilde ansehen.

    Links der Charakter und seine Liste, rechts die Gilde: wer sich denselben
    Gegenstand wuenscht.

    WIE MAN ETWAS AUFNIMMT — vier Wege, alle enden bei einer Item-ID:

      1. Wowhead-Link einfuegen   https://www.wowhead.com/item=19019/...
      2. Itemlink einfuegen       (Shift-Klick auf einen Gegenstand)
      3. Item-ID tippen           19019
      4. NAMEN tippen             "Donnerzorn"  -> Trefferliste rechts

    Der vierte Weg ist der, den man eigentlich will, und der einzige mit einer
    Einschraenkung: Ein Addon kann keine HTTP-Anfragen stellen — Wowhead laesst
    sich zur Laufzeit nicht befragen, von keinem Addon. Die Namenssuche laeuft
    deshalb gegen Database/ItemIndex, also gegen das, was DIESER Client schon
    gesehen hat. Findet sie nichts, sagt die Oberflaeche das und nennt den Weg,
    der immer geht: den Wowhead-Link einfuegen.

    Aus den Taschen ziehen geht weiterhin, ist aber der Nebenweg — was man sich
    wuenscht, hat man ja gerade nicht dabei.
------------------------------------------------------------------------------]]

local _, GA = ...

local WishlistView = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

local BIS_ROW_H = 24
local LEFT_W = 420

WishlistView.titleKey = "NAV_WISHLIST"

-- ================================================================== Aufbau ----

function WishlistView:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Eingabezeile ----
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(24)

    self.input = self:BuildItemBox(bar)
    self.input:SetPoint("LEFT", bar, "LEFT", 0, 0)
    self.input:SetWidth(240)

    self.priorityButtons = {}
    local previous
    for _, priority in ipairs(GA.Modules.Wishlist:Priorities()) do
        local button = Widgets.Button(bar, priority.label, function()
            self:AddCurrent(priority.key)
        end)
        button:SetTooltip(L.TT_WISH_PRIORITY)
        button:SetHeight(20)
        button:SetWidth(72)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 3, 0)
        else
            button:SetPoint("LEFT", self.input, "RIGHT", 8, 0)
        end
        button.priorityKey = priority.key
        self.priorityButtons[#self.priorityButtons + 1] = button
        previous = button
    end

    -- Reservieren steht NEBEN den Prioritaeten, nicht darunter: Es ist eine
    -- Alternative zum Eintragen, keine Verfeinerung davon. Und der Hinweis
    -- darunter sagt den Unterschied, weil er sonst niemandem klar ist.
    self.reserveButton = Widgets.Button(bar, L.SOFTRES_CLAIM, function()
        self:ReserveCurrent()
    end)
    self.reserveButton:SetTooltip(L.TT_SOFTRES_CLAIM)
    self.reserveButton:SetHeight(20)
    self.reserveButton:SetPoint("LEFT", previous or self.input, "RIGHT", 12, 0)

    -- AtlasLoot einlesen. Der Knopf erscheint NUR, wenn AtlasLoot ueberhaupt
    -- da ist — ein Knopf fuer etwas Nichtvorhandenes ist eine Einladung zum
    -- Draufklicken und Enttaeuschtwerden.
    self.atlasButton = Widgets.Button(bar, L.ATLAS_LOAD, function()
        self:LoadAtlas()
    end)
    self.atlasButton:SetTooltip(L.TT_ATLAS_LOAD)
    self.atlasButton:SetHeight(20)
    self.atlasButton:SetPoint("LEFT", self.reserveButton, "RIGHT", 12, 0)
    self.atlasButton:Hide()

    self.status = Theme.Label(bar, L.WISH_DROP_HINT, fonts.small, Theme.color.textFaint)
    self.status:SetPoint("LEFT", self.atlasButton, "RIGHT", 10, 0)
    self.status:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    self.status:SetJustifyH("LEFT")

    local difference = Theme.Label(bar, L.SOFTRES_VS_WISHLIST, fonts.small, Theme.color.textFaint)
    difference:SetPoint("TOPLEFT", self.input, "BOTTOMLEFT", 2, -3)
    difference:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    difference:SetJustifyH("LEFT")

    -- ------------------------------------------------------ Reiter ----------
    --
    -- ENTWURF B DER BiS-LISTE (gewaehlt 09.10.2026): Die linke Spalte hat
    -- zwei Reiter, "Meine Wunschliste" und "Best in Slot". Best in Slot ist
    -- eine Liste je Platz mit Stand (getragen, Wunsch, frei) statt der
    -- kleinen Puppe — und hat damit die ganze Hoehe.
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -20)
    tabs:SetWidth(LEFT_W)
    tabs:SetHeight(18)
    self.tabChips = {}
    local vorher
    for _, t in ipairs({ { "mine", L.WISH_MINE }, { "bis", L.WISH_BIS } }) do
        local chip = Widgets.Chip(tabs, t[2], function() self:ShowTab(t[1]) end)
        chip:SetHeight(18)
        if vorher then chip:SetPoint("LEFT", vorher, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", tabs, "LEFT", 0, 0) end
        chip.tab = t[1]
        self.tabChips[#self.tabChips + 1] = chip
        vorher = chip
    end

    local bis = Widgets.Panel(frame, L.WISH_BIS)
    bis:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -4)
    bis:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    bis:SetWidth(LEFT_W)
    self.bisPanel = bis
    self:BuildBisList(bis)

    -- ------------------------------------------------------ Eigene Liste ----
    local mine = Widgets.Panel(frame, L.WISH_MINE)
    mine:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -4)
    mine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    mine:SetWidth(LEFT_W)
    self.minePanel = mine

    -- Aus Best in Slot laden (09.10.2026): die BiS-Liste als Wuensche.
    self.fromBisButton = Widgets.Button(mine.header or mine, L.WISH_FROM_BIS, function()
        local added, worn, there = GA.Modules.Wishlist:LoadFromBis(self:OwnGuid())
        if added == 0 and worn == 0 and there == 0 then
            GA.UI.MainFrame:Notice("warn", L.WISH_FROM_BIS_EMPTY)
        else
            GA.UI.MainFrame:Notice("info", L.WISH_FROM_BIS_DONE, added, worn, there)
        end
        self:Refresh()
    end)
    self.fromBisButton:SetTooltip(L.TT_WISH_FROM_BIS)
    self.fromBisButton:SetHeight(18)
    self.fromBisButton:SetPoint("RIGHT", mine.header or mine, "RIGHT", -4, 0)

    self.mine = Widgets.ScrollList(mine.content, {
        emptyText = L.WISH_MINE_EMPTY,
        rowHeight = 26,
        createRow = function(row) self:BuildEntryRow(row) end,
        updateRow = function(row, entry) self:UpdateEntryRow(row, entry) end,
        onClickRow = function(entry)
            self.selectedItemID = entry.itemID
            self:Refresh()
        end,
        onEnterRow = function(row, entry)
            Widgets.ShowItemTooltip(row, entry and entry.itemID, row.itemLink)
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.mine:SetAllPoints(mine.content)

    -- ------------------------------------------------------ Gildenblick -----
    local others = Widgets.Panel(frame, L.WISH_OTHERS)
    others:SetPoint("TOPLEFT", tabs, "TOPRIGHT", gap, 0)
    others:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.othersPanel = others

    -- Dieselbe Liste zeigt zwei Dinge: Suchtreffer, solange im Feld ein Name
    -- steht, sonst die anderen Interessenten. Ein zweites Fenster dafuer waere
    -- ein Dialog mehr, den niemand bedienen will.
    self.others = Widgets.ScrollList(others.content, {
        emptyText = L.WISH_OTHERS_EMPTY,
        rowHeight = 22,
        createRow = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(18) row.icon:SetHeight(18)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetWidth(150)
            row.name:SetJustifyH("LEFT")

            row.priority = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.priority:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
            row.priority:SetWidth(70)
            row.priority:SetJustifyH("LEFT")

            row.note = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.note:SetPoint("LEFT", row.priority, "RIGHT", 6, 0)
            row.note:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.note:SetJustifyH("LEFT")
        end,
        updateRow = function(row, entry)
            if entry.itemID then
                -- Suchtreffer: Symbol, Name in Qualitaetsfarbe, Platz und Stufe.
                if entry.icon then row.icon:SetTexture(entry.icon) row.icon:Show()
                else row.icon:Hide() end

                row.name:SetText(entry.name or "?")
                local quality = Theme.QualityColor(entry.quality)
                row.name:SetTextColor(quality[1], quality[2], quality[3])

                row.priority:SetText(entry.level and ("ilvl " .. entry.level) or "")
                row.priority:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
                -- Der Fundort ist der Grund, warum AtlasLoot ueberhaupt
                -- angebunden ist: "Thunderfury" sagt weniger als
                -- "Geschmolzener Kern — Ragnaros".
                local slot = entry.equipLoc and (_G[entry.equipLoc] or entry.equipLoc) or ""
                local source = GA.Modules.AtlasBridge:SourceOf(entry.itemID)
                if source then
                    row.note:SetText(slot ~= "" and (slot .. "  ·  " .. source) or source)
                else
                    row.note:SetText(slot)
                end
                return
            end

            -- Interessent oder Hinweiszeile.
            row.icon:Hide()
            local r, g, b = Theme.ClassColor(entry.class)
            row.name:SetText(entry.name)
            row.name:SetTextColor(r, g, b)

            local priority = GA.Modules.Wishlist:PriorityByKey(entry.priority)
            row.priority:SetText(priority and priority.label or entry.priority or "")
            if entry.fulfilled then
                row.priority:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
                row.note:SetText(L.WISH_ALREADY_GOT)
            else
                row.priority:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
                row.note:SetText(entry.note or "")
            end
        end,
        onClickRow = function(entry)
            -- Ein Suchtreffer uebernimmt sich ins Eingabefeld; danach nur noch
            -- die Prioritaet waehlen.
            if entry.itemID then WishlistView:PickSearchResult(entry) end
        end,
        onEnterRow = function(row, entry)
            local info = entry.itemID and Compat.GetItemInfo(entry.itemID)
            Widgets.ShowItemTooltip(row, entry.itemID, info and info.link)
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.others:SetAllPoints(others.content)

    self.frame = frame
    self:ShowTab(GA.Core.Config:Get("wishlistTab") == "bis" and "bis" or "mine")
    return frame
end

--- Welcher Reiter links offen ist; gemerkt fuer das naechste Oeffnen.
function WishlistView:ShowTab(key)
    self.tab = key
    GA.Core.Config:Set("wishlistTab", key)
    self.minePanel:SetShown(key == "mine")
    self.bisPanel:SetShown(key == "bis")
    for _, chip in ipairs(self.tabChips) do chip:SetPressed(chip.tab == key) end
end

--- Eingabefeld, das Item-Links aus allen drei Wegen annimmt.
function WishlistView:BuildItemBox(parent)
    local fonts = Theme.Fonts()

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(20)
    Theme.Fill(holder, Theme.color.rowAltBg)
    Theme.Outline(holder, Theme.color.border)

    local edit = CreateFrame("EditBox", nil, holder)
    edit:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 0)
    edit:SetAutoFocus(false)
    edit:SetFontObject(fonts.row)
    edit:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    edit:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function() WishlistView:Refresh() end)

    local hint = Theme.Label(holder, L.WISH_INPUT, fonts.row, Theme.color.textFaint)
    hint:SetPoint("LEFT", holder, "LEFT", 6, 0)
    edit:SetScript("OnEditFocusGained", function() hint:Hide() end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then hint:Show() end
    end)

    -- Ziehen aus der Tasche: GetCursorInfo liefert Art und Link. Existiert es
    -- nicht, bleiben Einfuegen und Tippen als Wege.
    holder:EnableMouse(true)
    local function takeCursorItem()
        if type(_G.GetCursorInfo) ~= "function" then return false end
        local ok, kind, _, link = pcall(GetCursorInfo)
        if not ok or kind ~= "item" or not link then return false end
        edit:SetText(link)
        hint:Hide()
        if type(_G.ClearCursor) == "function" then ClearCursor() end
        WishlistView:Refresh()
        return true
    end
    holder:SetScript("OnReceiveDrag", takeCursorItem)
    holder:SetScript("OnMouseDown", function()
        if not takeCursorItem() then edit:SetFocus() end
    end)

    holder.edit = edit
    function holder:GetText() return edit:GetText() end
    function holder:Clear() edit:SetText("") hint:Show() end
    return holder
end

-- ================================================================== Zeilen ----

--- Die BiS-Liste: eine Zeile je Platz mit Symbol, Platz, Gegenstand, Stand.
function WishlistView:BuildBisList(panel)
    local fonts = Theme.Fonts()
    local content = panel.content

    -- "Was ich trage" fuellt jeden leeren Platz mit dem Getragenen.
    self.bisWearButton = Widgets.Button(panel.header or panel, L.WISH_BIS_WEAR_ALL, function()
        self:BisTakeWorn(nil)
    end)
    self.bisWearButton:SetTooltip(L.TT_WISH_BIS_WEAR)
    self.bisWearButton:SetHeight(18)
    self.bisWearButton:SetPoint("RIGHT", panel.header or panel, "RIGHT", -4, 0)

    -- Import aus FojjiCore (09.10.2026, mit Erlaubnis von Fojji): der
    -- Exporttext seines BiS-Managers. Das Abzeichen ist ein eigenes — ein
    -- kleiner Kreis mit "F" —, keine Grafik aus FojjiCore.
    -- Alle Listen aller Charaktere aus FojjiCore; dieselbe Funktion nutzt die
    -- Armory beim eigenen Charakter (GA.UI.FojjiBisMenu).
    self.bisFojjiButton = Widgets.Button(panel.header or panel, L.WISH_BIS_FOJJI, function()
        GA.UI.FojjiBisMenu(self:OwnGuid(), function() self:Refresh() end)
    end)
    self.bisFojjiButton:SetTooltip(L.TT_WISH_BIS_FOJJI)
    self.bisFojjiButton:SetHeight(18)
    self.bisFojjiButton:SetPoint("RIGHT", self.bisWearButton, "LEFT", -6, 0)
    local badge = self.bisFojjiButton:CreateTexture(nil, "OVERLAY")
    badge:SetSize(14, 14)
    badge:SetPoint("RIGHT", self.bisFojjiButton, "LEFT", -3, 0)
    if Theme.RoundTexture() then badge:SetTexture(Theme.RoundTexture()) end
    badge:SetVertexColor(0.40, 0.70, 1.00)
    local letter = Theme.Label(self.bisFojjiButton, "F", Theme.Fonts().pin or Theme.Fonts().small, { 0.05, 0.10, 0.20 })
    letter:SetPoint("CENTER", badge, "CENTER", 0, 0)

    self.bisHint = Theme.Label(content, L.WISH_BIS_HINT, fonts.small, Theme.color.textFaint)
    self.bisHint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 2)
    self.bisHint:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 2)
    self.bisHint:SetJustifyH("LEFT")

    local holder = CreateFrame("Frame", nil, content)
    holder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    holder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 18)

    self.bisList = Widgets.ScrollList(holder, {
        rowHeight = BIS_ROW_H,
        createRow = function(row)
            -- Getragen: goldener Grund und ein Goldstreifen links.
            row.okBg = row:CreateTexture(nil, "BACKGROUND")
            row.okBg:SetAllPoints(row)
            Theme.Paint(row.okBg, { 1, 0.82, 0.25, 0.10 })
            row.okBar = row:CreateTexture(nil, "BORDER")
            row.okBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.okBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.okBar:SetWidth(3)
            Theme.Paint(row.okBar, { 1, 0.82, 0.25, 1 })

            row.slot = Theme.ItemSlot(row, nil, BIS_ROW_H - 4)
            row.slot:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.slot:EnableMouse(false)
            row.slot.level:Hide()

            row.place = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.place:SetPoint("LEFT", row.slot, "RIGHT", 8, 0)
            row.place:SetWidth(84)
            row.place:SetJustifyH("LEFT")

            row.state = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.state:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.state:SetJustifyH("RIGHT")

            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("LEFT", row.place, "RIGHT", 6, 0)
            row.name:SetPoint("RIGHT", row.state, "LEFT", -8, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
        end,
        updateRow = function(row, entry) self:UpdateBisRow(row, entry) end,
        onClickRow = function(entry, _, mouse) self:OnBisClick(entry.slotID, mouse) end,
        onEnterRow = function(row, entry) self:ShowBisTooltip(row, entry) end,
        onLeaveRow = function() GameTooltip:Hide() end,
    })
    self.bisList:SetAllPoints(holder)
end

--- Eine Zeile der BiS-Liste.
function WishlistView:UpdateBisRow(row, entry)
    local fonts = Theme.Fonts()
    row.place:SetText(Compat.SlotName(entry.slotID))
    row.slot:SetItem(entry.itemID and { itemID = entry.itemID } or nil)
    row.slot:SetGold(entry.worn)
    row.okBg:SetShown(entry.worn and true or false)
    row.okBar:SetShown(entry.worn and true or false)

    local color
    if entry.itemID then
        local info = Compat.GetItemInfo(entry.itemID)
        if not info then Compat.RequestItemData(entry.itemID) end
        row.name:SetFontObject(fonts.body)
        row.name:SetText(info and info.name or ("#" .. tostring(entry.itemID)))
        color = entry.worn and Theme.SLOT_FRAME.bis or Theme.SlotFrameColor(true, info and info.quality, false)
        row.name:SetTextColor(color[1], color[2], color[3])
    else
        row.name:SetText("—")
        row.name:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    if entry.worn then
        row.state:SetText(L.WISH_BIS_STATE_WORN)
        color = Theme.SLOT_FRAME.bis
    elseif entry.itemID then
        row.state:SetText(L.WISH_BIS_STATE_WANTED)
        color = Theme.color.info
    else
        row.state:SetText(L.WISH_BIS_STATE_FREE)
        color = Theme.color.textFaint
    end
    row.state:SetTextColor(color[1], color[2], color[3])
end

--- Passt der Gegenstand auf den Platz? Nur, wenn der Client seine Art kennt;
--- sonst wird nicht gemeckert.
local function fitsSlot(itemID, slotID)
    local info = Compat.GetItemInfo(itemID)
    local slots = info and Compat.SlotsForEquipLoc(info.equipLoc)
    if not slots then return true end
    for _, id in ipairs(slots) do if id == slotID then return true end end
    return false
end

function WishlistView:OnBisClick(slotID, mouse)
    local guid = self:OwnGuid()
    local Wishlist = GA.Modules.Wishlist
    local current = Wishlist:Bis(guid)[slotID]
    local itemID = self:CurrentItemID()

    if mouse == "LeftButton" and itemID then
        if not fitsSlot(itemID, slotID) then
            self.status:SetText(string.format(L.WISH_BIS_NO_FIT, Compat.SlotName(slotID)))
            return
        end
        if not Compat.IsItemDataCached(itemID) then Compat.RequestItemData(itemID) end
        Wishlist:SetBis(guid, slotID, itemID)
        self.input:Clear()
        self.status:SetText(L.WISH_DROP_HINT)
        self:Refresh()
        return
    end

    local items = {}
    local character = GA.Core.Database.account.characters[guid]
    local worn = character and character.equipment and character.equipment[slotID]
    if worn and worn.itemID then
        local info = Compat.GetItemInfo(worn.itemID)
        items[#items + 1] = { text = string.format(L.WISH_BIS_TAKE, info and info.name or ("#" .. tostring(worn.itemID))),
            func = function() self:BisTakeWorn(slotID) end }
    end
    if current then
        items[#items + 1] = { text = L.WISH_BIS_REMOVE,
            func = function() Wishlist:SetBis(guid, slotID, nil) self:Refresh() end }
    end
    if #items == 0 then
        self.status:SetText(L.WISH_BIS_NEED_ITEM)
        return
    end
    Widgets.ContextMenu(Compat.SlotName(slotID), items)
end

--- Das Getragene als BiS: ein Platz, oder (nil) jeder leere Platz.
function WishlistView:BisTakeWorn(onlySlot)
    local guid = self:OwnGuid()
    local Wishlist = GA.Modules.Wishlist
    local character = GA.Core.Database.account.characters[guid]
    local equipment = character and character.equipment or {}
    local n = 0
    for _, slotID in ipairs(Wishlist.BIS_SLOTS) do
        if (not onlySlot or onlySlot == slotID) and (onlySlot or not Wishlist:Bis(guid)[slotID]) then
            local worn = equipment[slotID]
            if worn and worn.itemID and Wishlist:SetBis(guid, slotID, worn.itemID) then n = n + 1 end
        end
    end
    self.status:SetText(string.format(L.WISH_BIS_TAKEN, n))
    self:Refresh()
end

function WishlistView:ShowBisTooltip(row, entry)
    if entry.itemID and Widgets.ShowItemTooltip(row, entry.itemID) then
        GameTooltip:AddLine(entry.worn and L.ARMORY_BIS_WORN or L.ARMORY_BIS_WANTED, 1, 0.84, 0.35)
    else
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(Compat.SlotName(entry.slotID))
        GameTooltip:AddLine(L.WISH_BIS_HINT, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

function WishlistView:RefreshBis()
    local Wishlist = GA.Modules.Wishlist
    local status, worn, set = Wishlist:BisStatus(self:OwnGuid())
    local data = {}
    for _, slotID in ipairs(Wishlist.BIS_SLOTS) do
        local st = status[slotID] or {}
        data[#data + 1] = { slotID = slotID, itemID = st.itemID, worn = st.worn and true or false }
    end
    self.bisList:SetData(data)
    self.bisPanel:SetTitle(string.format(L.WISH_BIS_COUNT, worn, set))
end

--- Das Menue der FojjiCore-Listen: jede Liste jedes Charakters, eigene
--- zuerst, die aktive markiert; ein Klick uebernimmt sie in die BiS-Liste
--- von guid. Einfuegen als letzter Eintrag; ohne FojjiCore nur Einfuegen.
--- @param onDone function|nil  nach einer Uebernahme
function GA.UI.FojjiBisMenu(guid, onDone)
    local W = GA.Modules.Wishlist
    local function done(result)
        GA.UI.MainFrame:Notice("info", L.WISH_BIS_FOJJI_DONE, result.set,
            result.name and (" (" .. result.name .. ")") or "", result.alternatives)
        if onDone then onDone(result) end
    end
    local function fail(why)
        GA.UI.MainFrame:Notice("warn", L["WISH_BIS_FOJJI_ERR_" .. tostring(why)] or tostring(why))
    end
    local function paste()
        Widgets.InputDialog(L.WISH_BIS_FOJJI_TITLE, L.WISH_BIS_FOJJI_HINT, function(text)
            local result, why = W:ImportFojji(guid, text)
            if not result then return false, L["WISH_BIS_FOJJI_ERR_" .. tostring(why)] or tostring(why) end
            done(result)
            return true
        end)
    end
    local all = W.FojjiAllLists()
    if #all == 0 and not W.FojjiApi() then paste() return end
    local items = {}
    for _, e in ipairs(all) do
        local label = Theme.ColorByClass(e.char, e.class) .. "  ·  " .. e.list
            .. string.format("  |cff808080(%d)|r", e.count)
            .. (e.active and ("  |cffffd100" .. L.WISH_BIS_FOJJI_ACTIVE .. "|r") or "")
        items[#items + 1] = { text = label, func = function()
            local result, why = W:ImportFojjiList(guid, e)
            if result then done(result) else fail(why) end
        end }
        if #items >= 25 then break end
    end
    if #all == 0 then
        -- FojjiCore geladen, aber keine Listen lesbar: der Weg ueber seinen Export.
        items[#items + 1] = { text = L.WISH_BIS_FOJJI_LIVE, func = function()
            local result, why = W:ImportFojjiLive(guid)
            if result then done(result) else fail(why) end
        end }
    end
    items[#items + 1] = { text = L.WISH_BIS_FOJJI_PASTE, func = paste }
    Widgets.ContextMenu(L.WISH_BIS_FOJJI_TITLE, items)
end

function WishlistView:BuildEntryRow(row)
    local fonts = Theme.Fonts()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(20) row.icon:SetHeight(20)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(170)
    row.name:SetJustifyH("LEFT")

    row.priority = Theme.Label(row, "", fonts.body, Theme.color.gold)
    row.priority:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.priority:SetWidth(74)
    row.priority:SetJustifyH("LEFT")

    row.state = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.state:SetPoint("LEFT", row.priority, "RIGHT", 4, 0)
    row.state:SetPoint("RIGHT", row, "RIGHT", -120, 0)
    row.state:SetJustifyH("LEFT")

    -- Aendern (08.10.2026): Prioritaet und Notiz nachtraeglich, im Formular.
    row.edit = Widgets.Button(row, L.WISH_EDIT, function()
        if row.item then WishlistView:EditEntry(row.item) end
    end)
    row.edit:SetHeight(18)
    row.edit:SetWidth(48)

    row.remove = Widgets.Button(row, L.WISH_REMOVE, function()
        if row.item then
            GA.Modules.Wishlist:Remove(WishlistView:OwnGuid(), row.item.itemID)
            WishlistView:Refresh()
        end
    end)
    row.remove:SetHeight(18)
    row.remove:SetWidth(60)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.remove:SetConfirm(L.BTN_REALLY)
    row.edit:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
end

local WISH_FIELDS = {
    { key = "priority", label = L.WISH_F_PRIORITY, kind = "select", options = function()
        local out = {}
        for _, priority in ipairs(GA.Modules.Wishlist:Priorities()) do
            out[#out + 1] = { value = priority.key, text = priority.label }
        end
        return out
    end },
    { key = "note", label = L.WISH_F_NOTE, hint = L.WISH_F_NOTE_HINT },
}

--- Das Formular zu einem Wunsch: Prioritaet und Notiz.
function WishlistView:EditEntry(entry)
    local info = Compat.GetItemInfo(entry.itemID)
    local guid = self:OwnGuid()
    Widgets.FormDialog("wishEdit", info and info.name or ("#" .. tostring(entry.itemID)), WISH_FIELDS,
        { priority = entry.priority, note = entry.note }, function(v)
            local ok, reason = GA.Modules.Wishlist:Update(guid, entry.itemID,
                { priority = v.priority, note = v.note or "" })
            if not ok then return false, L["WISH_ERR_" .. tostring(reason)] or tostring(reason) end
            WishlistView:Refresh()
            return true
        end)
end

function WishlistView:UpdateEntryRow(row, entry)
    -- Die Zeile wird wiederverwendet: eine angefangene Bestaetigung gilt
    -- nicht fuer den naechsten Eintrag.
    if row.remove then row.remove:Disarm() end
    local info = Compat.GetItemInfo(entry.itemID)
    row.itemLink = info and info.link or nil

    if info and info.icon then row.icon:SetTexture(info.icon) row.icon:Show() else row.icon:Hide() end

    row.name:SetText(info and info.name or ("#" .. tostring(entry.itemID)))
    local quality = Theme.QualityColor(info and info.quality)
    row.name:SetTextColor(quality[1], quality[2], quality[3])

    local priority = GA.Modules.Wishlist:PriorityByKey(entry.priority)
    row.priority:SetText(priority and priority.label or entry.priority or "")

    if entry.fulfilledByAwardId then
        row.state:SetText(string.format(L.WISH_FULFILLED, Util.TimeAgo(entry.fulfilledTs)))
        row.state:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
        row.priority:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    else
        row.state:SetText(entry.note or "")
        row.state:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
        row.priority:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
    end
end

-- ================================================================== Aktionen --

function WishlistView:OwnGuid()
    return Compat.GetPlayerIdentity().guid
end

--- Liest die Item-ID aus dem Eingabefeld: Itemlink, Wowhead-Link oder Zahl.
--- Ein Name ergibt hier bewusst nichts — den loest die Trefferliste auf.
--- @return number|nil itemID, string|nil art
function WishlistView:CurrentItemID()
    local text = self.input and self.input:GetText() or ""
    if text == "" then return nil end
    return Compat.ParseItemInput(text)
end

--- Meldet den Gegenstand im Eingabefeld als Reservierung an.
---
--- Das geht ueber eine Nachricht an den Lootmeister, nicht in die eigene
--- Datenbank: Die Runde liegt bei ihm, und nur er weiss, ob eine offen ist,
--- wie hoch die Grenze steht und was schon eingetragen wurde. Die Antwort
--- kommt zurueck (siehe LootCouncil/SoftRes, OnAck).
function WishlistView:ReserveCurrent()
    local parsed = self:CurrentItemID()
    if not parsed or not parsed.itemID then
        self.status:SetText(L.WISH_NO_ITEM)
        return
    end

    local ok, reason = GA.Modules.SoftRes:Claim(parsed.itemID)
    if not ok then
        self.status:SetText(L["SOFTRES_ERR_" .. string.upper(tostring(reason)) .. "2"]
            or tostring(reason))
    else
        self.status:SetText(L.SOFTRES_CLAIM .. " ...")
    end
end

--- Liest AtlasLoot ein und haelt den Knopf auf dem Laufenden.
---
--- Das Einlesen laeuft getaktet ueber mehrere Sekunden (siehe
--- Database/AtlasBridge). Waehrenddessen ist der Knopf gesperrt — ein
--- zweiter Start waere kein zweites Einlesen, sondern zwei nebeneinander.
function WishlistView:LoadAtlas()
    local Atlas = GA.Modules.AtlasBridge

    local ok, reason = Atlas:Harvest(function(total, resolved)
        self.status:SetText(string.format(L.ATLAS_DONE, total, resolved))
        self:UpdateAtlasButton()
        self:Refresh()
    end)

    if not ok then
        self.status:SetText(L["ATLAS_ERR_" .. string.upper(tostring(reason))]
            or tostring(reason))
    else
        self.status:SetText(L.ATLAS_RUNNING)
    end
    self:UpdateAtlasButton()
end

--- Zeigt am Knopf, in welchem der drei Zustaende AtlasLoot gerade ist.
function WishlistView:UpdateAtlasButton()
    if not self.atlasButton then return end
    local stats = GA.Modules.AtlasBridge:Stats()

    -- Nicht installiert: gar kein Knopf. Wer AtlasLoot nicht hat, soll nicht
    -- erst klicken muessen, um das zu erfahren.
    if not stats.available then
        self.atlasButton:Hide()
        return
    end

    self.atlasButton:Show()
    if GA.Modules.AtlasBridge.running then
        self.atlasButton:SetLabel(L.ATLAS_RUNNING_SHORT)
        self.atlasButton:SetEnabledState(false, L.ATLAS_RUNNING)
    elseif stats.harvested then
        -- Nochmal einlesen ist erlaubt: AtlasLoot laedt seine Module
        -- nachtraeglich, und dann gibt es mehr zu holen als beim ersten Mal.
        self.atlasButton:SetLabel(string.format(L.ATLAS_LOADED, stats.sources))
        self.atlasButton:SetEnabledState(true)
    else
        self.atlasButton:SetLabel(L.ATLAS_LOAD)
        self.atlasButton:SetEnabledState(true)
    end
end

--- Uebernimmt einen Suchtreffer ins Eingabefeld.
function WishlistView:PickSearchResult(entry)
    local info = Compat.GetItemInfo(entry.itemID)
    -- Den Link, wenn der Client ihn hat — sonst die blanke ID. Beides wird von
    -- ParseItemInput gelesen, und die ID steht immer zur Verfuegung.
    self.input.edit:SetText(info and info.link or tostring(entry.itemID))
    self.selectedItemID = entry.itemID
    self:Refresh()
end

function WishlistView:AddCurrent(priorityKey)
    local itemID = self:CurrentItemID()
    if not itemID then
        self.status:SetText(L.WISH_NO_ITEM)
        return
    end

    -- Bei einer getippten ID kennt der Client den Gegenstand womoeglich noch
    -- nicht. Nachladen anstossen, damit Name und Symbol nachkommen — der
    -- Eintrag selbst haengt nicht daran, er braucht nur die ID.
    if not Compat.IsItemDataCached(itemID) then Compat.RequestItemData(itemID) end

    local entry, reason = GA.Modules.Wishlist:Add(self:OwnGuid(), itemID, priorityKey)
    if not entry then
        self.status:SetText(L["WISH_ERR_" .. tostring(reason)] or tostring(reason))
        return
    end

    self.input:Clear()
    self.selectedItemID = itemID
    self.status:SetText(L.WISH_DROP_HINT)
    self:Refresh()
end

-- ================================================================== Refresh ---

function WishlistView:OnShow() self:Refresh() end

function WishlistView:Refresh()
    self:UpdateAtlasButton()

    local guid = self:OwnGuid()
    local Wishlist = GA.Modules.Wishlist

    local list = Wishlist:Get(guid)
    self.mine:SetData(list)

    local stats = Wishlist:Stats(guid)
    self.minePanel:SetTitle(string.format(L.WISH_MINE_COUNT, stats.open, stats.fulfilled))
    self:RefreshBis()

    -- Die Knoepfe sind nur benutzbar, wenn im Feld etwas Brauchbares steht.
    local itemID = self:CurrentItemID()
    for _, button in ipairs(self.priorityButtons) do
        button:SetEnabledState(itemID ~= nil, itemID and nil or L.WISH_NO_ITEM)
    end

    -- Steht im Feld ein NAME? Dann wird rechts gesucht statt "wer will das noch"
    -- angezeigt. Das ist der Weg, den man eigentlich benutzt, und er braucht
    -- keinen zusaetzlichen Dialog.
    local text = self.input:GetText()
    if not itemID and #text >= 2 then
        local matches = GA.Modules.ItemIndex:Search(text, 25)
        self.othersPanel:SetTitle(string.format(L.WISH_SEARCH_TITLE, #matches))
        self.searching = true

        if #matches == 0 then
            -- Ehrlich sagen, warum nichts kommt, und den sicheren Weg nennen.
            -- Liegt AtlasLoot ungenutzt daneben, gehoert das hierher: Genau
            -- jetzt sucht jemand und findet nichts.
            local atlas = GA.Modules.AtlasBridge:Stats()
            local hint = L.WISH_SEARCH_HINT
            if atlas.available and not atlas.harvested then
                hint = L.ATLAS_OFFER
            end
            self.others:SetData({ {
                name = string.format(L.WISH_SEARCH_EMPTY, GA.Modules.ItemIndex:Count()),
                note = hint,
            } })
        else
            self.others:SetData(matches)
        end

        self.status:SetText(string.format(L.WISH_SEARCH_STATUS, GA.Modules.ItemIndex:Count()))
        GA.UI.MainFrame:SetContext(string.format(L.WISH_CONTEXT, stats.open))
        return
    end
    self.searching = false

    -- Rechts: wer will denselben Gegenstand? Ohne Auswahl bleibt es leer.
    local target = self.selectedItemID or itemID
    if target then
        local interested = {}
        for _, entry in ipairs(Wishlist:ForItem(target)) do
            if entry.guid ~= guid then interested[#interested + 1] = entry end
        end
        local info = Compat.GetItemInfo(target)
        self.othersPanel:SetTitle(string.format(L.WISH_OTHERS_FOR,
            info and info.name or ("#" .. tostring(target))))
        if #interested == 0 then
            interested = { { name = L.WISH_NOBODY_ELSE, class = nil, priority = nil } }
        end
        self.others:SetData(interested)
    else
        self.othersPanel:SetTitle(L.WISH_OTHERS)
        self.others:SetData({ { name = L.WISH_PICK, class = nil } })
    end

    GA.UI.MainFrame:SetContext(string.format(L.WISH_CONTEXT, stats.open))
end

GA.UI.MainFrame:RegisterView("wishlist", WishlistView)
