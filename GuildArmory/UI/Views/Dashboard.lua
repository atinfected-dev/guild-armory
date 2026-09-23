--[[----------------------------------------------------------------------------
    Views/Dashboard — Portrait, Charakter, Gilde, Lootzustand, letzte Aenderungen.

    Zeigt nur, was gemessen wurde. Wo eine Zahl fehlt, steht ein Strich.
    Aufgebaut aus Blizzards eingelassenen Flaechen (Widgets.Panel/Inset) mit
    Questlog-Kopfzeilen — wie die rechte Seite von "Karte & Questlog".
------------------------------------------------------------------------------]]

local _, GA = ...

local Dashboard = {}

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

Dashboard.titleKey = "NAV_DASHBOARD"

local CARD_HEIGHT = 92
local ROW_HEIGHT = 90


function Dashboard:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------- Charakterkarte -------
    local me = Widgets.Inset(frame)
    me:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    me:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    me:SetHeight(CARD_HEIGHT)

    self.portrait = me:CreateTexture(nil, "ARTWORK")
    self.portrait:SetWidth(58) self.portrait:SetHeight(58)
    self.portrait:SetPoint("LEFT", me, "LEFT", 16, 0)

    local ring = me:CreateTexture(nil, "OVERLAY")
    ring:SetWidth(72) ring:SetHeight(72)
    ring:SetPoint("CENTER", self.portrait, "CENTER", 0, 0)
    pcall(ring.SetTexture, ring, "Interface\\Minimap\\MiniMap-TrackingBorder")
    pcall(ring.SetTexCoord, ring, 0, 0.6, 0, 0.6)

    self.charName = Theme.Label(me, "", fonts.hero, Theme.color.goldBright)
    self.charName:SetPoint("TOPLEFT", me, "TOPLEFT", 92, -18)
    if self.charName.SetShadowOffset then self.charName:SetShadowOffset(1, -1) end

    self.classIcon = me:CreateTexture(nil, "ARTWORK")
    self.classIcon:SetWidth(22) self.classIcon:SetHeight(22)
    self.classIcon:SetPoint("LEFT", self.charName, "RIGHT", 8, 0)

    self.charMeta = Theme.Label(me, "", fonts.body, Theme.color.textDim)
    self.charMeta:SetPoint("TOPLEFT", self.charName, "BOTTOMLEFT", 1, -5)

    self.charGuild = Theme.Label(me, "", fonts.small, Theme.color.textFaint)
    self.charGuild:SetPoint("TOPLEFT", self.charMeta, "BOTTOMLEFT", 0, -3)

    self.ilvl = Theme.Label(me, "", fonts.hero, Theme.color.goldBright)
    self.ilvl:SetPoint("TOPRIGHT", me, "TOPRIGHT", -20, -16)
    if self.ilvl.SetShadowOffset then self.ilvl:SetShadowOffset(1, -1) end
    self.ilvlLabel = Theme.Label(me, L.DASH_ITEMLEVEL, fonts.body, Theme.color.textDim)
    self.ilvlLabel:SetPoint("TOPRIGHT", self.ilvl, "BOTTOMRIGHT", 0, -2)
    self.ilvlHint = Theme.Label(me, L.DASH_COMPUTED, fonts.small, Theme.color.textFaint)
    self.ilvlHint:SetPoint("TOPRIGHT", self.ilvlLabel, "BOTTOMRIGHT", 0, -2)

    -- ------------------------------------------------- Gilde und Loot -------
    local guild = Widgets.Panel(frame, L.DASH_GUILD)
    guild:SetPoint("TOPLEFT", me, "BOTTOMLEFT", 0, -gap)
    guild:SetHeight(ROW_HEIGHT)

    local loot = Widgets.Panel(frame, L.DASH_LOOT_STATE)
    loot:SetPoint("TOPLEFT", guild, "TOPRIGHT", gap, 0)
    loot:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    loot:SetHeight(ROW_HEIGHT)

    self.guildName = Theme.Label(guild.content, "", fonts.big, Theme.color.goldBright)
    self.guildName:SetPoint("TOPLEFT", guild.content, "TOPLEFT", 4, -4)
    self.guildMeta = Theme.Label(guild.content, "", fonts.body, Theme.color.textDim)
    self.guildMeta:SetPoint("TOPLEFT", self.guildName, "BOTTOMLEFT", 0, -4)
    self.guildRank = Theme.Label(guild.content, "", fonts.small, Theme.color.textFaint)
    self.guildRank:SetPoint("TOPLEFT", self.guildMeta, "BOTTOMLEFT", 0, -3)

    self.lootMethod = Theme.Label(loot.content, "", fonts.big, Theme.color.goldBright)
    self.lootMethod:SetPoint("TOPLEFT", loot.content, "TOPLEFT", 4, -4)
    self.lootState = Theme.Label(loot.content, "", fonts.body, Theme.color.textDim)
    self.lootState:SetPoint("TOPLEFT", self.lootMethod, "BOTTOMLEFT", 0, -4)
    self.lootState:SetPoint("RIGHT", loot.content, "RIGHT", -4, 0)
    self.lootState:SetJustifyH("LEFT")

    -- Offene Uebergaben gehoeren hierher und nicht in eine eigene Ansicht:
    -- Wer sie suchen muss, schaut nicht nach.
    self.handover = Theme.Label(loot.content, "", fonts.small, Theme.color.warn)
    self.handover:SetPoint("TOPLEFT", self.lootState, "BOTTOMLEFT", 0, -4)
    self.handover:SetPoint("RIGHT", loot.content, "RIGHT", -4, 0)
    self.handover:SetJustifyH("LEFT")

    -- ------------------------------------------------- Listen ---------------
    --
    -- "Letzte Aenderungen" stand hier bis zum 22.09.2026 und ist entfernt:
    -- Eine Liste, die jedes An- und Ablegen eines Gegenstands mitschreibt,
    -- fuellt sich schneller, als jemand sie liest — und beantwortet keine
    -- Frage, die man an ein Dashboard stellt. Die Historie steht in der
    -- eigenen Ansicht, der Ausruestungsverlauf in der Armory.
    local online = Widgets.Panel(frame, L.DASH_ONLINE)
    online:SetPoint("TOPLEFT", guild, "BOTTOMLEFT", 0, -gap)
    online:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    self.onlinePanel = online

    local tradables = Widgets.Panel(frame, L.DASH_TRADABLES)
    tradables:SetPoint("TOPLEFT", online, "TOPRIGHT", gap, 0)
    tradables:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.tradablesPanel = tradables

    -- IN DIE KOPFLEISTE, NICHT UEBER DIE LISTE: Der Knopf wird selten
    -- gedrueckt, die Liste dauernd gelesen. Platz, den er sich aus der
    -- Liste nimmt, kostet bei jedem Blick eine Zeile.
    --
    -- Er postet NUR auf Druck. Ein Addon, das von selbst in den Gildenchat
    -- schreibt, fliegt zu Recht raus — deshalb gibt es auch keine
    -- Einstellung, die das automatisiert.
    self.tradablesPost = Widgets.Button(tradables.header or tradables,
        L.DASH_TRADABLES_POST, function() Dashboard:PostTradables() end)
    self.tradablesPost:SetHeight(18)
    self.tradablesPost:SetPoint("RIGHT", tradables.header or tradables, "RIGHT", -6, 0)
    if self.tradablesPost.SetWidth then self.tradablesPost:SetWidth(96) end

    local function layout()
        local width = frame:GetWidth()
        if not width or width <= 0 then return end
        local half = (width - pad * 2 - gap) * 0.5
        guild:SetWidth(half)
        online:SetWidth(half)
    end
    frame:SetScript("OnSizeChanged", layout)
    self.layout = layout

    self.online = Widgets.ScrollList(online.content, {
        rowHeight = 22,
        createRow = function(row)
            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name:SetWidth(120)
            row.name:SetJustifyH("LEFT")
            row.rank = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.rank:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
            row.rank:SetWidth(90)
            row.rank:SetJustifyH("LEFT")
            row.zone = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.zone:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
            row.zone:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.zone:SetJustifyH("LEFT")
        end,
        updateRow = function(row, member)
            local r, g, b = Util.ClassColor(member.class)
            row.name:SetText(member.name or "?")
            row.name:SetTextColor(r, g, b)
            row.rank:SetText(member.rankName or "")
            row.zone:SetText(member.zone or "")
        end,
    })
    self.online:SetAllPoints(online.content)

    -- EINE ZEILE JE GEGENSTAND, nicht je Spieler: Gesucht wird nach dem
    -- Gegenstand ("hat jemand den Guertel?"), nicht nach der Person.
    self.tradables = Widgets.ScrollList(tradables.content, {
        rowHeight = 20,
        -- NICHT row.item: Diesen Namen belegt ScrollList selbst mit dem
        -- Datensatz der Zeile, und zwar VOR jedem updateRow. Eine Anzeige
        -- darin wird beim ersten Zeichnen ueberschrieben.
        createRow = function(row)
            local fonts = Theme.Fonts()
            row.itemText = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.itemText:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.itemText:SetPoint("RIGHT", row, "RIGHT", -120, 0)
            row.itemText:SetJustifyH("LEFT")
            if row.itemText.SetWordWrap then
                pcall(row.itemText.SetWordWrap, row.itemText, false)
            end

            row.ownerText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.ownerText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.ownerText:SetWidth(112)
            row.ownerText:SetJustifyH("RIGHT")
        end,
        updateRow = function(row, entry)
            row.itemText:SetText(entry.label)
            local color = entry.quality and Theme.QualityColor(entry.quality) or Theme.color.text
            row.itemText:SetTextColor(color[1], color[2], color[3])
            row.ownerText:SetText(entry.owner)
            -- UNSICHER HEISST UNSICHER: Konnte der meldende Client nicht
            -- pruefen, ob das Stueck schon gebunden ist, steht der Name in
            -- Warnfarbe statt so auszusehen wie ein geprueftes Angebot.
            local ownerColor = entry.sure and Theme.color.textDim or Theme.color.warn
            row.ownerText:SetTextColor(ownerColor[1], ownerColor[2], ownerColor[3])
        end,
        onEnterRow = function(row, entry)
            if not entry or not entry.itemID then return end
            Widgets.ShowItemTooltip(row, entry.itemID, entry.link)
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.tradables:SetAllPoints(tradables.content)

    self.tradablesEmpty = Theme.Label(tradables.content, L.DASH_TRADABLES_NONE,
        Theme.Fonts().small, Theme.color.textFaint)
    self.tradablesEmpty:SetPoint("TOPLEFT", tradables.content, "TOPLEFT", 4, -4)
    self.tradablesEmpty:SetPoint("RIGHT", tradables.content, "RIGHT", -4, 0)
    self.tradablesEmpty:SetJustifyH("LEFT")
    self.tradablesEmpty:Hide()

    self.frame = frame
    return frame
end

function Dashboard:OnShow()
    if self.layout then self.layout() end
end

function Dashboard:Refresh()
    local identity = Compat.GetPlayerIdentity()
    local db = GA.Core.Database
    local character = identity.guid and db.account.characters[identity.guid]

    if not Theme.SetPortrait(self.portrait, "player") then
        Theme.Paint(self.portrait, Theme.color.rowAltBg)
    end
    local r, g, b = Util.ClassColor(identity.class)
    self.charName:SetText(identity.name or "?")
    self.charName:SetTextColor(r, g, b)
    self.charMeta:SetText(string.format(L.LEVEL_FMT, tostring(identity.level or "?")) .. "  " ..
        (identity.raceName or "") .. " " .. (identity.className or ""))
    if Theme.SetClassIcon(self.classIcon, identity.class) then self.classIcon:Show() else self.classIcon:Hide() end

    local level = character and character.itemLevel and character.itemLevel.value
    self.ilvl:SetText(level and tostring(level) or "—")

    local guildName, rankName = Compat.GetOwnGuildInfo()
    if guildName then
        self.charGuild:SetText(string.format("<%s>  %s  ·  %s", guildName, rankName or "", identity.realm or ""))
        self.guildName:SetText(guildName)
        local total, online = Compat.GetNumGuildMembers()
        self.guildMeta:SetText(string.format(L.DASH_MEMBERS, total, online))
        self.guildRank:SetText(rankName or "")
    else
        self.charGuild:SetText(identity.realm or "")
        self.guildName:SetText(L.DASH_NOT_IN_GUILD)
        self.guildMeta:SetText("")
        self.guildRank:SetText("")
    end

    -- Lootmethode gibt es nur in einer Gruppe. Allein ist "unbekannt" falsch —
    -- es ist schlicht nicht anwendbar.
    if not Compat.IsInGroup() then
        self.lootMethod:SetText(L.LOOT_NO_GROUP)
        self.lootState:SetText(L.LOOT_NO_GROUP_HINT)
    else
        local method = Compat.GetLootMethod()
        local labels = { freeforall = L.LOOT_FREEFORALL, roundrobin = L.LOOT_ROUNDROBIN,
                         master = L.LOOT_MASTER, group = L.LOOT_GROUP,
                         needbeforegreed = L.LOOT_NBG, personalloot = L.LOOT_PERSONAL }
        self.lootMethod:SetText(method and (labels[method] or method) or L.UNKNOWN)
        if method == "master" then
            self.lootState:SetText(Compat.IsMasterLooter() and L.DASH_LOOT_MASTER or L.DASH_LOOT_NOTMASTER)
        else
            self.lootState:SetText(L.DASH_LOOT_NOTMASTER)
        end
    end

    local carrying = GA.Modules.Handover:Pending()
    if #carrying > 0 then
        local names = {}
        for index = 1, math.min(#carrying, 2) do
            names[#names + 1] = tostring(carrying[index].to)
        end
        local text = table.concat(names, ", ")
        if #carrying > 2 then
            text = text .. string.format(L.HANDOVER_MORE, #carrying - 2)
        end
        self.handover:SetText(string.format(L.HANDOVER_REMIND, #carrying, text))
    else
        self.handover:SetText("")
    end

    self:RefreshTradables()

    local onlineRows = GA.Modules.Guild:List(true)
    if self.onlinePanel and self.onlinePanel.SetTitle then
        self.onlinePanel:SetTitle(#onlineRows > 0
            and string.format("%s (%d)", L.DASH_ONLINE, #onlineRows) or L.DASH_ONLINE)
    end
    if #onlineRows == 0 then
        onlineRows = { { name = guildName and L.DASH_NOBODY_ONLINE or L.DASH_NOT_IN_GUILD, class = nil } }
    end
    self.online:SetData(onlineRows)

    GA.UI.MainFrame:SetContext(character and character.equipmentTs
        and string.format(L.ARMORY_SNAPSHOT, Util.TimeAgo(character.equipmentTs)) or "")
end

GA.UI.MainFrame:RegisterView("dashboard", Dashboard)

--- Was die Gilde gerade anzubieten hat.
--- Postet die eigenen Angebote und sagt, was passiert ist.
---
--- DER KNOPF GIBT IMMER ANTWORT. Ein Knopf, der bei leerer Liste einfach
--- nichts tut, sieht aus wie ein kaputter Knopf — und beim naechsten Mal
--- drueckt jemand dreimal.
function Dashboard:PostTradables()
    local Tradables = GA.Modules.Tradables
    if not Tradables then return end

    local ok, grund = Tradables:Announce()
    if ok then
        GA.Core.Debug:Info("%s", L.TRADE_POSTED)
    elseif grund == "leer" then
        GA.Core.Debug:Info("%s", L.TRADE_NONE_OWN)
    else
        GA.Core.Debug:Warn("%s", L.TRADE_POST_FAILED)
    end

    self:RefreshTradables()
end

--- Graut den Knopf aus, wenn es nichts zu posten gibt.
function Dashboard:UpdatePostButton(eigene)
    local button = self.tradablesPost
    if not button then return end

    -- Lieber ausgegraut als versteckt: Ein Knopf, der verschwindet und
    -- wiederkommt, laesst die Kopfleiste zappeln, und man sucht ihn.
    if button.SetEnabledState then
        button:SetEnabledState(eigene > 0)
    elseif button.Enable and button.Disable then
        if eigene > 0 then button:Enable() else button:Disable() end
    end
end

function Dashboard:RefreshTradables()
    local Tradables = GA.Modules.Tradables
    if not Tradables or not self.tradables then return end

    local rows = {}
    for _, entry in ipairs(Tradables:All()) do
        for _, item in ipairs(entry.items) do
            -- UEBER DEN LINK NACHSCHLAGEN, WENN ES IHN GIBT: Der Name aus
            -- der blossen ID heisst "Nomad Tunic", der aus dem Link
            -- "Nomad Tunic of the Boar". Beides ist derselbe Gegenstand
            -- nur fuer jemanden, der die Werte nicht braucht.
            local info = (item.link and GA.Core.Compat.GetItemInfo(item.link))
                or (GA.Modules.ItemIndex and GA.Modules.ItemIndex:Get(item.itemID))
                or GA.Core.Compat.GetItemInfo(item.itemID)
            local label = (info and info.name)
                or string.format(L.SLASH_ITEM_FALLBACK, item.itemID)
            if (item.count or 1) > 1 then label = label .. "  x" .. item.count end

            rows[#rows + 1] = {
                label = label,
                quality = info and info.quality,
                owner = GA.Core.Util.ShortName(entry.name or "?"),
                sure = entry.sure,
                -- Fuer den Tooltip. DIE ID IST DAS EINZIGE, WAS SICHER DA
                -- IST: Bei fremden Angeboten kommt nur sie ueber die
                -- Comm-Nachricht, ein Link existiert dann hoechstens, wenn
                -- dieser Client den Gegenstand schon einmal gesehen hat.
                itemID = item.itemID,
                -- Der Link des BESITZERS, nicht der aus dem eigenen
                -- Verzeichnis: Nur er traegt den Zufallssuffix.
                link = item.link or (info and info.link),
            }
        end
    end

    table.sort(rows, function(a, b) return a.label < b.label end)
    self.tradables:SetData(rows)

    -- Nur die EIGENEN zaehlen fuer den Knopf: Er postet ja auch nur die.
    local eigene = GA.Modules.Tradables:Offered()
    self:UpdatePostButton(#eigene)

    if #rows == 0 then self.tradablesEmpty:Show() else self.tradablesEmpty:Hide() end
end

GA.Core.Callbacks:On("TRADABLES_CHANGED", function()
    if Dashboard.frame and Dashboard.frame:IsVisible() then Dashboard:RefreshTradables() end
end, "DashboardView")
