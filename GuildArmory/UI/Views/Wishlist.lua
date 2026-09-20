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

WishlistView.title = L.NAV_WISHLIST

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
    self.reserveButton:SetHeight(20)
    self.reserveButton:SetPoint("LEFT", previous or self.input, "RIGHT", 12, 0)

    -- AtlasLoot einlesen. Der Knopf erscheint NUR, wenn AtlasLoot ueberhaupt
    -- da ist — ein Knopf fuer etwas Nichtvorhandenes ist eine Einladung zum
    -- Draufklicken und Enttaeuschtwerden.
    self.atlasButton = Widgets.Button(bar, L.ATLAS_LOAD, function()
        self:LoadAtlas()
    end)
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

    -- ------------------------------------------------------ Eigene Liste ----
    local mine = Widgets.Panel(frame, L.WISH_MINE)
    mine:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -20)
    mine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    mine:SetWidth(420)
    self.minePanel = mine

    self.mine = Widgets.ScrollList(mine.content, {
        rowHeight = 26,
        createRow = function(row) self:BuildEntryRow(row) end,
        updateRow = function(row, entry) self:UpdateEntryRow(row, entry) end,
        onClickRow = function(entry)
            self.selectedItemID = entry.itemID
            self:Refresh()
        end,
        onEnterRow = function(row, entry)
            if row.itemLink then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                if pcall(GameTooltip.SetHyperlink, GameTooltip, row.itemLink) then
                    GameTooltip:Show()
                end
            end
        end,
    })
    self.mine:SetAllPoints(mine.content)

    -- ------------------------------------------------------ Gildenblick -----
    local others = Widgets.Panel(frame, L.WISH_OTHERS)
    others:SetPoint("TOPLEFT", mine, "TOPRIGHT", gap, 0)
    others:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.othersPanel = others

    -- Dieselbe Liste zeigt zwei Dinge: Suchtreffer, solange im Feld ein Name
    -- steht, sonst die anderen Interessenten. Ein zweites Fenster dafuer waere
    -- ein Dialog mehr, den niemand bedienen will.
    self.others = Widgets.ScrollList(others.content, {
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
            local r, g, b = Util.ClassColor(entry.class)
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
            if not entry.itemID then return end
            local info = Compat.GetItemInfo(entry.itemID)
            if not info or not info.link then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if pcall(GameTooltip.SetHyperlink, GameTooltip, info.link) then GameTooltip:Show() end
        end,
    })
    self.others:SetAllPoints(others.content)

    self.frame = frame
    return frame
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
    row.state:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    row.state:SetJustifyH("LEFT")

    row.remove = Widgets.Button(row, L.WISH_REMOVE, function()
        if row.item then
            GA.Modules.Wishlist:Remove(WishlistView:OwnGuid(), row.item.itemID)
            WishlistView:Refresh()
        end
    end)
    row.remove:SetHeight(18)
    row.remove:SetWidth(60)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
end

function WishlistView:UpdateEntryRow(row, entry)
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
