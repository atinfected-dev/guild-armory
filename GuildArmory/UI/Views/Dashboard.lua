--[[----------------------------------------------------------------------------
    Views/Dashboard — der Wappensaal. Was man sieht, wenn man das Addon oeffnet.

    Entwurf D1 (27.09.2026). OBEN das Heroband: das Gildenzeichen, der
    Gildenname gross, darunter Mitglieder und Gildenmeister, und Chips fuer
    das, was gerade laeuft (Lootsession, Pluendermeister, offene Uebergaben).
    Rechts vier Kennzahlen mit ihrer Einordnung darunter — nicht "18.4",
    sondern "18.4, gemessen bei 31 von 38".

    DARUNTER DREI SPALTEN.
      Dein Charakter    Portrait, Name, Itemlevel, die 17 Plaetze als
                        Farbstreifen — und fuenf Zeilen, die DICH betreffen:
                        die offene Session, deine Wuensche darauf, wie alt
                        dein Berufsscan ist, dein DKP-Stand, der naechste
                        Erfolg. Jede Zeile ist ein Klick zur Seite dahinter.
      Heute in der Gilde   Der Strom aus Armory/Activity.lua. Jede Zeile
                        traegt ihre Quelle: "vom Spiel bestaetigt", "von
                        Hand", "Rosterabgleich".
      Wer ist wo        Die Zonen der Online-Mitglieder aus dem Roster, als
                        Klassenpunkte — und das letzte Lagerfeuer. Darunter
                        das Handelbare.

    ZEIGT NUR, WAS GEMESSEN WURDE. Wo eine Zahl fehlt, steht ein Strich; wo
    eine Auskunft fehlt, steht der Grund. Ein Dashboard, das an der Stelle
    einer fehlenden Zahl eine schoene Null zeigt, ist ein Poster.
------------------------------------------------------------------------------]]

local _, GA = ...

local Dashboard = {}

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

Dashboard.titleKey = "NAV_DASHBOARD"

local HERO_HEIGHT = 118
local KPI_W, KPI_H, KPI_GAP = 104, 66, 8
local MINE_WIDTH = 290
local RIGHT_WIDTH = 240
local SLOT_W, SLOT_GAP = 14, 2
local FEED_ROW = 36

local LOGO = [[Interface\AddOns\GuildArmory\Media\Logo.tga]]
local WEEK = 7 * 86400
local DAY = 86400

--- Die Reihenfolge der Plaetze im Farbstreifen: wie im Charakterfenster,
--- links oben nach rechts unten, die Waffen zuletzt. OHNE Hemd und
--- Wappenrock: Sie zaehlen nicht zum Itemlevel, und mit ihnen waren es
--- neunzehn Streifen fuer eine Zeile, die "17" verspricht (27.09.2026).
local SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- ================================================================== Aufbau ----

--- Ein Chip: umrandeter Text in einer Farbe, mit einem Punkt davor.
local function chip(parent, color)
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(18)
    frame.fill = Theme.Fill(frame, { color[1], color[2], color[3], 0.14 })
    frame.lines = Theme.Outline(frame, { color[1], color[2], color[3], 0.6 })

    frame.dot = frame:CreateTexture(nil, "OVERLAY")
    frame.dot:SetWidth(6) frame.dot:SetHeight(6)
    frame.dot:SetPoint("LEFT", frame, "LEFT", 8, 0)
    Theme.Paint(frame.dot, color)

    frame.label = Theme.Label(frame, "", fonts.small, color)
    frame.label:SetPoint("LEFT", frame.dot, "RIGHT", 6, 0)

    function frame:SetText(text)
        self.label:SetText(text or "")
        self:SetWidth(self.label:GetStringWidth() + 28)
    end
    frame:Hide()
    return frame
end

--- Eine Kennzahlkachel: Zahl gross, Beschriftung klein, Einordnung darunter.
local function kpi(parent)
    local fonts = Theme.Fonts()
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetWidth(KPI_W) tile:SetHeight(KPI_H)
    Theme.Fill(tile, { 0.031, 0.047, 0.043, 0.85 })
    Theme.Outline(tile, Theme.color.border)

    tile.value = Theme.Label(tile, "—", fonts.hero, Theme.color.goldBright)
    tile.value:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)

    -- JEDE ZEILE HAT EIN LINKES ENDE. Ein rechts verankerter Text ohne
    -- Breite waechst nach links ueber die Kachel hinaus — gemessen
    -- 27.09.2026 mit Bild: "0 confirmed by the game" stand in der
    -- Nachbarkachel. Was nicht passt, wird abgeschnitten, nicht umgebrochen.
    tile.label = Theme.Label(tile, "", fonts.small, Theme.color.textDim)
    tile.label:SetPoint("TOPRIGHT", tile.value, "BOTTOMRIGHT", 0, -3)
    tile.label:SetWidth(KPI_W - 16)
    tile.label:SetJustifyH("RIGHT")
    tile.label:SetWordWrap(false)

    tile.trend = Theme.Label(tile, "", fonts.small, Theme.color.textFaint)
    tile.trend:SetPoint("TOPRIGHT", tile.label, "BOTTOMRIGHT", 0, -1)
    tile.trend:SetWidth(KPI_W - 16)
    tile.trend:SetJustifyH("RIGHT")
    tile.trend:SetWordWrap(false)

    function tile:Set(value, label, trend, valueColor, trendColor)
        self.value:SetText(value ~= nil and tostring(value) or "—")
        local farbe = valueColor or Theme.color.goldBright
        self.value:SetTextColor(farbe[1], farbe[2], farbe[3])
        self.label:SetText(label or "")
        self.trend:SetText(trend or "")
        local tf = trendColor or Theme.color.textFaint
        self.trend:SetTextColor(tf[1], tf[2], tf[3])
    end
    return tile
end

function Dashboard:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Heroband --------
    local hero = Widgets.Inset(frame)
    hero:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    hero:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    hero:SetHeight(HERO_HEIGHT)
    self.hero = hero

    -- Ein warmer Schein hinter dem Zeichen: der einzige Farbverlauf der
    -- Seite, und er dient dem Emblem, nicht sich selbst.
    local glow = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetWidth(320) glow:SetHeight(HERO_HEIGHT - 4)
    glow:SetPoint("LEFT", hero, "LEFT", 2, 0)
    if glow.SetGradient then
        pcall(glow.SetColorTexture, glow, 1, 1, 1, 1)
        pcall(glow.SetGradient, glow, "HORIZONTAL",
            { r = 0.61, g = 0.50, b = 0.28, a = 0.22 }, { r = 0.03, g = 0.05, b = 0.04, a = 0 })
    else
        glow:Hide()
    end

    local emblemRing = hero:CreateTexture(nil, "OVERLAY")
    emblemRing:SetWidth(96) emblemRing:SetHeight(96)
    emblemRing:SetPoint("LEFT", hero, "LEFT", 14, 0)
    pcall(emblemRing.SetTexture, emblemRing, "Interface\\Minimap\\MiniMap-TrackingBorder")
    pcall(emblemRing.SetTexCoord, emblemRing, 0, 0.6, 0, 0.6)

    self.emblem = hero:CreateTexture(nil, "ARTWORK")
    self.emblem:SetWidth(76) self.emblem:SetHeight(76)
    self.emblem:SetPoint("CENTER", emblemRing, "CENTER", 0, 0)

    self.realmLine = Theme.Label(hero, "", fonts.small, Theme.color.goldDim)
    self.realmLine:SetPoint("TOPLEFT", hero, "TOPLEFT", 118, -14)

    self.guildName = Theme.Label(hero, "", fonts.display, Theme.color.goldBright)
    self.guildName:SetPoint("TOPLEFT", self.realmLine, "BOTTOMLEFT", -1, -3)
    if self.guildName.SetShadowOffset then self.guildName:SetShadowOffset(1, -1) end
    self.guildName:SetWordWrap(false)

    self.guildMeta = Theme.Label(hero, "", fonts.body, Theme.color.textDim)
    self.guildMeta:SetPoint("TOPLEFT", self.guildName, "BOTTOMLEFT", 1, -4)
    self.guildMeta:SetWordWrap(false)

    self.chips = {
        session = chip(hero, Theme.color.jade),
        master = chip(hero, Theme.color.gold),
        handover = chip(hero, Theme.color.warn),
    }
    self.chipOrder = { "session", "master", "handover" }

    -- Die Kennzahlen, rechts, von rechts nach links verankert.
    self.kpis = {}
    local vorige
    for _, key in ipairs({ "achievements", "loot", "online", "ilvl" }) do
        local tile = kpi(hero)
        if vorige then
            tile:SetPoint("RIGHT", vorige, "LEFT", -KPI_GAP, 0)
        else
            tile:SetPoint("RIGHT", hero, "RIGHT", -14, 0)
        end
        self.kpis[key] = tile
        vorige = tile
    end
    -- Titel und Zeile enden vor den Kacheln.
    self.guildName:SetPoint("RIGHT", self.kpis.ilvl, "LEFT", -16, 0)
    self.guildMeta:SetPoint("RIGHT", self.kpis.ilvl, "LEFT", -16, 0)

    -- ------------------------------------------------------ Dein Charakter --
    local mine = Widgets.Panel(frame, L.DASH_MY_CHARACTER, L.DASH_COMPUTED)
    mine:SetWidth(MINE_WIDTH)
    mine:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -gap)
    mine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    self.minePanel = mine
    self:BuildMine(mine.content, fonts)

    -- ------------------------------------------------------ Rechte Spalte ---
    local where = Widgets.Panel(frame, L.DASH_WHERE)
    where:SetWidth(RIGHT_WIDTH)
    where:SetHeight(24 + 190)
    where:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -gap)
    self.wherePanel = where
    self:BuildWhere(where.content, fonts)

    local tradables = Widgets.Panel(frame, L.DASH_TRADABLES)
    tradables:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -gap)
    tradables:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.tradablesPanel = tradables

    self.tradablesPost = Widgets.Button(tradables.header or tradables,
        L.DASH_TRADABLES_POST, function() Dashboard:PostTradables() end)
    self.tradablesPost:SetHeight(18)
    self.tradablesPost:SetPoint("RIGHT", tradables.header or tradables, "RIGHT", -6, 0)
    if self.tradablesPost.SetWidth then self.tradablesPost:SetWidth(96) end
    self:BuildTradables(tradables.content, fonts)

    -- ------------------------------------------------------ Der Strom -------
    local feed = Widgets.Panel(frame, L.DASH_FEED, "")
    feed:SetPoint("TOPLEFT", mine, "TOPRIGHT", gap, 0)
    feed:SetPoint("BOTTOMRIGHT", where, "BOTTOMLEFT", -gap, 0)
    feed:SetPoint("BOTTOM", frame, "BOTTOM", 0, pad)
    self.feedPanel = feed

    self.feed = Widgets.ScrollList(feed.content, {
        rowHeight = FEED_ROW,
        createRow = function(row) self:BuildFeedRow(row, fonts) end,
        updateRow = function(row, entry) self:UpdateFeedRow(row, entry) end,
        onEnterRow = function(row, entry)
            if entry and entry.itemID then
                Widgets.ShowItemTooltip(row, entry.itemID, entry.itemLink)
            end
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.feed:SetAllPoints(feed.content)

    self.feedEmpty = Theme.Label(feed.content, L.DASH_FEED_EMPTY, fonts.small, Theme.color.textFaint)
    self.feedEmpty:SetPoint("TOPLEFT", feed.content, "TOPLEFT", 8, -8)
    self.feedEmpty:SetPoint("RIGHT", feed.content, "RIGHT", -8, 0)
    self.feedEmpty:SetJustifyH("LEFT")
    self.feedEmpty:SetSpacing(2)
    self.feedEmpty:Hide()

    self.frame = frame
    return frame
end

-- ================================================================ Mein Teil ---

function Dashboard:BuildMine(content, fonts)
    self.portrait = content:CreateTexture(nil, "ARTWORK")
    self.portrait:SetWidth(44) self.portrait:SetHeight(44)
    self.portrait:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -4)

    local ring = content:CreateTexture(nil, "OVERLAY")
    ring:SetWidth(56) ring:SetHeight(56)
    ring:SetPoint("CENTER", self.portrait, "CENTER", 0, 0)
    pcall(ring.SetTexture, ring, "Interface\\Minimap\\MiniMap-TrackingBorder")
    pcall(ring.SetTexCoord, ring, 0, 0.6, 0, 0.6)

    self.charName = Theme.Label(content, "", fonts.big, Theme.color.goldBright)
    self.charName:SetPoint("TOPLEFT", self.portrait, "TOPRIGHT", 12, -4)
    self.charName:SetWordWrap(false)

    self.charMeta = Theme.Label(content, "", fonts.small, Theme.color.textDim)
    self.charMeta:SetPoint("TOPLEFT", self.charName, "BOTTOMLEFT", 0, -3)
    self.charMeta:SetWordWrap(false)

    self.ilvl = Theme.Label(content, "", fonts.hero, Theme.color.goldBright)
    self.ilvl:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -2)
    self.ilvlLabel = Theme.Label(content, "", fonts.small, Theme.color.textDim)
    self.ilvlLabel:SetPoint("TOPRIGHT", self.ilvl, "BOTTOMRIGHT", 0, -1)
    -- BEIDE ENDEN VOR DER BESCHRIFTUNG, nicht vor der Zahl: "ILVL · 10/17"
    -- ist breiter als "19" und ragt weiter nach links (27.09.2026, Bild).
    self.charName:SetPoint("RIGHT", self.ilvlLabel, "LEFT", -8, 0)
    self.charMeta:SetPoint("RIGHT", self.ilvlLabel, "LEFT", -8, 0)

    -- Die 17 Plaetze als Streifen. Farbe = Qualitaet, leer = dunkel.
    self.slots = {}
    for index = 1, #SLOT_ORDER do
        local strip = content:CreateTexture(nil, "ARTWORK")
        strip:SetWidth(SLOT_W) strip:SetHeight(12)
        strip:SetPoint("TOPLEFT", content, "TOPLEFT", 2 + (index - 1) * (SLOT_W + SLOT_GAP), -58)
        Theme.Paint(strip, Theme.color.border)
        self.slots[index] = strip
    end
    self.slotsHint = Theme.Label(content, L.DASH_SLOTS_HINT, fonts.small, Theme.color.textFaint)
    self.slotsHint:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -74)

    local divider = content:CreateTexture(nil, "ARTWORK")
    Theme.Paint(divider, Theme.color.border)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -92)
    divider:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    -- Fuenf Zeilen, die dich betreffen. Jede ist ein Knopf zur Seite dahinter.
    self.mine = {}
    for index = 1, 5 do
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(36)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(96 + (index - 1) * 36))
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row.fill = Theme.Fill(row, { 0, 0, 0, 0 })

        row.ring = CreateFrame("Frame", nil, row)
        row.ring:SetWidth(16) row.ring:SetHeight(16)
        row.ring:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.ring.lines = Theme.Outline(row.ring, Theme.color.textDim)
        row.dot = row.ring:CreateTexture(nil, "OVERLAY")
        row.dot:SetWidth(6) row.dot:SetHeight(6)
        row.dot:SetPoint("CENTER", row.ring, "CENTER", 0, 0)

        row.value = Theme.Label(row, "", fonts.rowBold, Theme.color.gold)
        row.value:SetPoint("RIGHT", row, "RIGHT", -6, 0)

        row.title = Theme.Label(row, "", fonts.row, Theme.color.text)
        row.title:SetPoint("TOPLEFT", row.ring, "TOPRIGHT", 8, 1)
        row.title:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)

        row.sub = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
        row.sub:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)

        row:SetScript("OnEnter", function(self) Theme.Paint(self.fill, Theme.color.rowHover) end)
        row:SetScript("OnLeave", function(self) Theme.Paint(self.fill, { 0, 0, 0, 0 }) end)
        row:SetScript("OnClick", function(self)
            if self.view and GA.UI.MainFrame.ShowView then GA.UI.MainFrame:ShowView(self.view) end
        end)

        function row:Set(title, sub, value, color, view)
            local farbe = color or Theme.color.textDim
            self.title:SetText(title or "")
            self.sub:SetText(sub or "")
            self.value:SetText(value or "")
            self.value:SetTextColor(farbe[1], farbe[2], farbe[3])
            Theme.Paint(self.dot, farbe)
            for _, line in ipairs(self.ring.lines) do Theme.Paint(line, farbe) end
            self.view = view
        end
        self.mine[index] = row
    end
end

-- ================================================================== Wo -------

function Dashboard:BuildWhere(content, fonts)
    self.zones = Widgets.ScrollList(content, {
        rowHeight = 24,
        createRow = function(row)
            row.zone = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.zone:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.zone:SetJustifyH("LEFT")
            row.zone:SetWordWrap(false)
            -- Bis zu acht Punkte, danach eine Zahl.
            row.dots = {}
            local vorige
            for index = 1, 8 do
                local dot = row:CreateTexture(nil, "ARTWORK")
                dot:SetWidth(9) dot:SetHeight(9)
                if vorige then dot:SetPoint("RIGHT", vorige, "LEFT", -3, 0)
                else dot:SetPoint("RIGHT", row, "RIGHT", -6, 0) end
                dot:Hide()
                row.dots[index] = dot
                vorige = dot
            end
            row.more = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.more:SetPoint("RIGHT", row.dots[8], "LEFT", -4, 0)
            row.zone:SetPoint("RIGHT", row.more, "LEFT", -4, 0)
        end,
        updateRow = function(row, entry)
            row.zone:SetText(entry.zone)
            local farbe = entry.unknown and Theme.color.textFaint or Theme.color.text
            row.zone:SetTextColor(farbe[1], farbe[2], farbe[3])
            for index, dot in ipairs(row.dots) do
                local member = entry.members[index]
                if member then
                    dot:Show()
                    if member.class then
                        Theme.Paint(dot, { Util.ClassColor(member.class) })
                    else
                        Theme.Paint(dot, Theme.color.border)
                    end
                else
                    dot:Hide()
                end
            end
            row.more:SetText(#entry.members > 8 and ("+" .. (#entry.members - 8)) or "")
        end,
    })
    self.zones:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.zones:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 34)

    -- Das letzte Lagerfeuer, aus dem Strom — nur, solange es frisch ist.
    self.camp = CreateFrame("Frame", nil, content)
    self.camp:SetHeight(28)
    self.camp:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    self.camp:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    Theme.Fill(self.camp, { 0.851, 0.643, 0.255, 0.10 })
    Theme.Outline(self.camp, { 0.851, 0.643, 0.255, 0.35 })
    self.campText = Theme.Label(self.camp, "", fonts.small, Theme.color.warn)
    self.campText:SetPoint("LEFT", self.camp, "LEFT", 8, 0)
    self.campText:SetPoint("RIGHT", self.camp, "RIGHT", -8, 0)
    self.campText:SetJustifyH("LEFT")
    self.campText:SetWordWrap(false)
    self.camp:Hide()
end

-- ================================================================== Handel ----

function Dashboard:BuildTradables(content, fonts)
    self.tradables = Widgets.ScrollList(content, {
        rowHeight = 22,
        createRow = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(14) row.icon:SetHeight(14)
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.ask = Widgets.Button(row, L.TRADE_ASK_BUTTON, function()
                local entry = row.item
                if not entry then return end
                local ok, grund = GA.Modules.Tradables:Ask(
                    entry.itemID, entry.ownerFull or entry.owner, entry.link)
                if not ok then
                    GA.Core.Debug:Info("%s",
                        L["TRADE_ASK_ERR_" .. tostring(grund)] or tostring(grund))
                end
            end)
            row.ask:SetHeight(16)
            row.ask:SetWidth(48)
            row.ask:SetPoint("RIGHT", row, "RIGHT", -4, 0)

            row.itemText = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.itemText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.itemText:SetPoint("RIGHT", row.ask, "LEFT", -6, 0)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)

            row.ownerText = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.ownerText:SetPoint("TOPRIGHT", row.ask, "BOTTOMRIGHT", 0, 0)
            row.ownerText:Hide()
        end,
        updateRow = function(row, entry)
            -- Name und Besitzer in EINER Zeile: "Umhang · Ari".
            row.itemText:SetText(string.format("%s  ·  |cff%s%s|r", entry.label,
                entry.sure and "a89c84" or "d9a441", entry.owner))
            local color = entry.quality and Theme.QualityColor(entry.quality) or Theme.color.text
            row.itemText:SetTextColor(color[1], color[2], color[3])
            if entry.icon then row.icon:SetTexture(entry.icon) row.icon:Show() else row.icon:Hide() end

            local Comm = GA.Core.Comm
            local eigenes = Comm and entry.ownerFull and Comm:IsSelf(entry.ownerFull)
            if eigenes then row.ask:Hide() else row.ask:Show() end
        end,
        onEnterRow = function(row, entry)
            if not entry or not entry.itemID then return end
            Widgets.ShowItemTooltip(row, entry.itemID, entry.link)
        end,
        onLeaveRow = function() Widgets.HideItemTooltip() end,
    })
    self.tradables:SetAllPoints(content)

    self.tradablesEmpty = Theme.Label(content, L.DASH_TRADABLES_NONE, fonts.small, Theme.color.textFaint)
    self.tradablesEmpty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    self.tradablesEmpty:SetPoint("RIGHT", content, "RIGHT", -4, 0)
    self.tradablesEmpty:SetJustifyH("LEFT")
    self.tradablesEmpty:Hide()
end

-- ================================================================== Strom -----

function Dashboard:BuildFeedRow(row, fonts)
    row.time = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.time:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.time:SetWidth(36)
    row.time:SetJustifyH("LEFT")

    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(18) row.crest:SetHeight(18)
    row.crest:SetPoint("LEFT", row, "LEFT", 48, 0)

    row.text = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 74, -5)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.tag = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.tag:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
    row.tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.tag:SetJustifyH("LEFT")
    row.tag:SetWordWrap(false)
end

--- Text, Farbe und Quelle eines Eintrags aus Armory/Activity.lua.
function Dashboard:DescribeActivity(entry)
    local Activity = GA.Modules.Activity
    local what, tag, tagColor = "", "", Theme.color.textFaint

    if entry.kind == Activity.LEVELUP then
        what = string.format(L.ACT_LEVELUP, entry.level or 0)
        tag, tagColor = L.ACT_TAG_ROSTER, Theme.color.jade
    elseif entry.kind == Activity.ROSTER then
        if entry.sub == "JOINED" then what = L.ACT_JOINED
        elseif entry.sub == "LEFT" then what = L.ACT_LEFT
        elseif entry.sub == "PROMOTED" then what = string.format(L.ACT_PROMOTED, tostring(entry.rank or "?"))
        else what = string.format(L.ACT_DEMOTED, tostring(entry.rank or "?")) end
        tag, tagColor = L.ACT_TAG_ROSTER, entry.sub == "JOINED" and Theme.color.gold or Theme.color.textFaint
    elseif entry.kind == Activity.LOOT then
        local farbe = Theme.QualityColor(entry.quality)
        local name = entry.itemName or ("#" .. tostring(entry.itemID))
        what = string.format(L.ACT_LOOT, Util.Colorize(name, farbe[1], farbe[2], farbe[3]))
        local Confirmation = GA.Data.Schema.Confirmation
        if entry.status == "TRANSFER_PENDING" or entry.status == "AWARDED" then
            tag, tagColor = L.ACT_TAG_LOOT_OPEN, Theme.color.warn
        elseif entry.confirmation == Confirmation.MASTER_LOOT or entry.confirmation == Confirmation.TRADE then
            tag, tagColor = L.ACT_TAG_LOOT_STRONG, Theme.color.jade
        elseif entry.confirmation == Confirmation.MANUAL then
            tag, tagColor = L.ACT_TAG_LOOT_MANUAL, Theme.color.warn
        else
            tag, tagColor = L.ACT_TAG_LOOT_WEAK, Theme.color.textDim
        end
    elseif entry.kind == Activity.ACHIEVEMENT then
        what = string.format(entry.first and L.ACT_FIRST or L.ACT_ACH, tostring(entry.achievement or "?"))
        tag, tagColor = L.ACT_TAG_ACH, { 0.64, 0.21, 0.93 }
    elseif entry.kind == Activity.CAMP then
        what = string.format(L.ACT_CAMP, tostring(entry.zone or "?"))
        tag, tagColor = L.ACT_TAG_CAMP, Theme.color.warn
    end
    return what, tag, tagColor
end

function Dashboard:UpdateFeedRow(row, entry)
    row.time:SetText(entry.ts and date("%H:%M", entry.ts) or "")

    if entry.class and Theme.SetClassPortrait(row.crest, entry.class) then
        row.crest:Show()
    else
        row.crest:Hide()
    end

    local what, tag, tagColor = self:DescribeActivity(entry)
    local r, g, b = Util.ClassColor(entry.class)
    row.text:SetText(string.format("%s %s", Util.Colorize(entry.name or "?", r, g, b), what))
    row.tag:SetText(tag)
    row.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3])
end

-- ================================================================== Refresh ---

function Dashboard:OnShow() self:Refresh() end

--- Legt die sichtbaren Chips nebeneinander; unsichtbare lassen keine Luecke.
function Dashboard:LayoutChips()
    local vorige
    for _, key in ipairs(self.chipOrder) do
        local c = self.chips[key]
        if c:IsShown() then
            c:ClearAllPoints()
            if vorige then
                c:SetPoint("LEFT", vorige, "RIGHT", 6, 0)
            else
                c:SetPoint("TOPLEFT", self.guildMeta, "BOTTOMLEFT", 0, -7)
            end
            vorige = c
        end
    end
end

function Dashboard:RefreshHero(identity, character)
    if Theme.TextureExists(LOGO) and pcall(self.emblem.SetTexture, self.emblem, LOGO) then
        self.emblem:Show()
    else
        self.emblem:Hide()
    end

    local guildName, rankName = Compat.GetOwnGuildInfo()
    local total, online = Compat.GetNumGuildMembers()
    total, online = total or 0, online or 0

    self.realmLine:SetText(string.upper(string.format("Guild Armory · %s", identity.realm or "")))
    if guildName then
        self.guildName:SetText(guildName)
        local teile = { string.format(L.DASH_MEMBERS_ONLINE, total, online) }
        -- Der Gildenmeister: Rang 0 im Roster.
        for _, member in ipairs(GA.Modules.Guild:List()) do
            if member.rankIndex == 0 and member.name then
                teile[#teile + 1] = string.format(L.DASH_GUILD_MASTER,
                    Util.ColorByClass(Util.ShortName(member.name), member.class))
                break
            end
        end
        if rankName then teile[#teile + 1] = rankName end
        self.guildMeta:SetText(table.concat(teile, "  ·  "))
    else
        self.guildName:SetText(L.DASH_NOT_IN_GUILD)
        self.guildMeta:SetText(identity.realm or "")
    end

    -- Chips: nur, was gerade gilt.
    local session = GA.Modules.Session:Current()
    if session then
        self.chips.session:SetText(string.format(L.DASH_CHIP_SESSION, #session.awardIds))
        self.chips.session:Show()
    else
        self.chips.session:Hide()
    end
    if Compat.IsInGroup() and Compat.GetLootMethod() == "master" and Compat.IsMasterLooter() then
        self.chips.master:SetText(L.DASH_CHIP_MASTER)
        self.chips.master:Show()
    else
        self.chips.master:Hide()
    end
    local carrying = GA.Modules.Handover:Pending()
    if #carrying > 0 then
        self.chips.handover:SetText(string.format(L.DASH_CHIP_HANDOVER, #carrying))
        self.chips.handover:Show()
    else
        self.chips.handover:Hide()
    end
    self:LayoutChips()

    -- ------------------------------------------------------ Kennzahlen ------
    -- Itemlevel: Mittel ueber die GEMESSENEN. Ungemessene zaehlen nicht als
    -- Null — die Kachel sagt, wie viele fehlen.
    local characters = GA.Core.Database:ListCharacters({})
    local summe, gemessen = 0, 0
    for _, entry in ipairs(characters) do
        local wert = entry.itemLevel and entry.itemLevel.value
        if wert then summe = summe + wert gemessen = gemessen + 1 end
    end
    self.kpis.ilvl:Set(gemessen > 0 and string.format("%.1f", summe / gemessen) or nil,
        L.DASH_KPI_ILVL, string.format(L.DASH_KPI_ILVL_TREND, gemessen, #characters))

    self.kpis.online:Set(guildName and online or nil, L.DASH_KPI_ONLINE,
        guildName and string.format(L.DASH_KPI_ONLINE_TREND, total) or "",
        Theme.color.jade)

    -- Loot der Woche: nur Vergaben, und getrennt gezaehlt, was das Spiel
    -- bestaetigt hat.
    local Confirmation = GA.Data.Schema.Confirmation
    local vergeben, bestaetigt = 0, 0
    for _, award in ipairs(GA.Modules.Awards:List({ since = Util.Now() - WEEK })) do
        if award.recipientName and award.status ~= "CANCELLED" then
            vergeben = vergeben + 1
            if award.confirmation == Confirmation.MASTER_LOOT or award.confirmation == Confirmation.TRADE then
                bestaetigt = bestaetigt + 1
            end
        end
    end
    self.kpis.loot:Set(vergeben, L.DASH_KPI_LOOT,
        string.format(L.DASH_KPI_LOOT_TREND, bestaetigt),
        nil, bestaetigt > 0 and Theme.color.jade or Theme.color.textFaint)

    local Achievements = GA.Modules.Achievements
    local alle = Achievements and Achievements:List() or {}
    local frei = 0
    for _, entry in ipairs(alle) do if entry.unlocked then frei = frei + 1 end end
    self.kpis.achievements:Set(Achievements and frei or nil, L.DASH_KPI_ACH,
        string.format(L.DASH_KPI_ACH_TREND, #alle))
end

function Dashboard:RefreshMine(identity, character)
    if not Theme.SetPortrait(self.portrait, "player") then
        Theme.Paint(self.portrait, Theme.color.rowAltBg)
    end
    local r, g, b = Util.ClassColor(identity.class)
    self.charName:SetText(Util.FullestName(identity.name, character and character.name) or "?")
    self.charName:SetTextColor(r, g, b)

    local _, rankName = Compat.GetOwnGuildInfo()
    local meta = { string.format(L.LEVEL_FMT, tostring(identity.level or "?")) }
    if identity.className then meta[#meta + 1] = identity.className end
    if rankName then meta[#meta + 1] = rankName end
    self.charMeta:SetText(table.concat(meta, " · "))

    local level = character and character.itemLevel and character.itemLevel.value
    self.ilvl:SetText(level and tostring(level) or "—")
    local count = character and character.itemLevel and character.itemLevel.count
    self.ilvlLabel:SetText(count and string.format("%s · %d/17", string.upper(L.COL_ILVL), count)
        or string.upper(L.DASH_ITEMLEVEL))

    -- Die Plaetze: Qualitaetsfarbe, leer dunkel.
    local equipment = character and character.equipment or {}
    for index, slotID in ipairs(SLOT_ORDER) do
        local item = equipment[slotID]
        local farbe = item and item.quality and Theme.QualityColor(item.quality)
        Theme.Paint(self.slots[index], farbe or Theme.color.border)
    end

    -- ------------------------------------------------------ Fuenf Zeilen ----
    local Session = GA.Modules.Session
    local session = Session:Current()
    local incoming = Session.incoming
    local offen = session and #session.awardIds or (incoming and #incoming.items) or 0

    -- Wuensche auf dem Tisch: die Gegenstaende der Session gegen die eigene
    -- Wunschliste.
    local Wishlist = GA.Modules.Wishlist
    local wuensche = identity.guid and Wishlist and Wishlist:Get(identity.guid, false) or {}
    local treffer = 0
    local items = {}
    if session then
        for _, awardId in ipairs(session.awardIds) do
            local award = GA.Modules.Awards:Get(awardId)
            if award and award.itemID then items[#items + 1] = award.itemID end
        end
    elseif incoming then
        for _, item in ipairs(incoming.items) do items[#items + 1] = item.itemID end
    end
    for _, itemID in ipairs(items) do
        if identity.guid and Wishlist:Find(identity.guid, itemID) then treffer = treffer + 1 end
    end

    if offen > 0 then
        self.mine[1]:Set(L.DASH_MINE_SESSION, string.format(L.DASH_MINE_SESSION_SUB, offen),
            tostring(offen), Theme.color.jade, "lootcouncil")
    else
        self.mine[1]:Set(L.DASH_MINE_SESSION, L.COUNCIL_NO_SESSION, "—", Theme.color.textFaint, "lootcouncil")
    end

    if treffer > 0 then
        self.mine[2]:Set(L.DASH_MINE_WISH, string.format(L.DASH_MINE_WISH_SUB, treffer),
            tostring(treffer), Theme.color.jade, "wishlist")
    else
        self.mine[2]:Set(L.DASH_MINE_WISH, string.format(L.DASH_MINE_WISH_NONE, #wuensche),
            tostring(#wuensche), Theme.color.textDim, "wishlist")
    end

    -- Berufe: die aelteste eigene Lesung. Das ist die, die veraltet.
    local Crafting = GA.Modules.Crafting
    local aeltester
    for _, line in ipairs(Crafting and identity.name and Crafting:LinesOf(identity.name) or {}) do
        if not aeltester or (line.ts or 0) < (aeltester.ts or 0) then aeltester = line end
    end
    if aeltester then
        local alter = Util.Now() - (aeltester.ts or 0)
        self.mine[3]:Set(L.DASH_MINE_PROF,
            string.format(L.DASH_MINE_PROF_SUB, tostring(aeltester.name or aeltester.line),
                aeltester.ts and Util.TimeAgo(aeltester.ts) or L.UNKNOWN),
            tostring(aeltester.rank or ""), alter > 3 * DAY and Theme.color.warn or Theme.color.textDim, "crafting")
    else
        self.mine[3]:Set(L.DASH_MINE_PROF, L.DASH_MINE_PROF_NONE, "—", Theme.color.textFaint, "crafting")
    end

    local Dkp = GA.Modules.Dkp
    local punkte = Dkp and identity.guid and Dkp:Balance(identity.guid) or nil
    self.mine[4]:Set(L.DASH_MINE_DKP,
        punkte and string.format(L.DASH_MINE_DKP_SUB, punkte) or L.UNKNOWN,
        punkte and tostring(punkte) or "—", punkte and Theme.color.gold or Theme.color.textFaint, "lootrules")

    -- Der naechste Erfolg: der messbare, der am weitesten ist und noch fehlt.
    local Achievements, Rules = GA.Modules.Achievements, GA.Modules.Rules
    local bester, besterAnteil
    if Achievements and Rules then
        for _, entry in ipairs(Achievements:List()) do
            if not entry.unlocked then
                local progress = Rules:Progress(entry.id)
                if progress.measurable and not progress.done and not progress.unreachable
                    and (progress.target or 0) > 1 then
                    local anteil = (progress.current or 0) / progress.target
                    if not besterAnteil or anteil > besterAnteil then
                        bester, besterAnteil = entry, anteil
                        bester.progress = progress
                    end
                end
            end
        end
    end
    if bester then
        self.mine[5]:Set(L.DASH_MINE_ACH, bester.name,
            string.format("%d/%d", bester.progress.current, bester.progress.target),
            Theme.color.gold, "achievements")
    else
        self.mine[5]:Set(L.DASH_MINE_ACH, L.DASH_MINE_ACH_NONE, "—", Theme.color.textFaint, "achievements")
    end
end

function Dashboard:RefreshWhere()
    -- Zonen aus dem Roster: Was das Spiel ueber Online-Mitglieder sagt.
    local nachZone, reihe = {}, {}
    for _, member in ipairs(GA.Modules.Guild:List(true)) do
        local zone = member.zone
        local unknown = not zone or zone == ""
        local key = unknown and "?" or zone
        if not nachZone[key] then
            nachZone[key] = { zone = unknown and L.DASH_ZONE_UNKNOWN or zone, unknown = unknown, members = {} }
            reihe[#reihe + 1] = nachZone[key]
        end
        table.insert(nachZone[key].members, member)
    end
    table.sort(reihe, function(a, b)
        if a.unknown ~= b.unknown then return b.unknown end
        if #a.members ~= #b.members then return #a.members > #b.members end
        return a.zone < b.zone
    end)
    self.zones:SetData(reihe)

    -- Das letzte Lagerfeuer, wenn es juenger als eine halbe Stunde ist.
    local Activity = GA.Modules.Activity
    local feuer = Activity and Activity:Latest(Activity.CAMP)
    if feuer and (Util.Now() - (feuer.ts or 0)) < 1800 then
        self.campText:SetText(string.format(L.DASH_CAMP, tostring(feuer.zone or "?"),
            Util.ColorByClass(feuer.name, feuer.class), Util.TimeAgo(feuer.ts)))
        self.camp:Show()
        self.zones:SetPoint("BOTTOMRIGHT", self.wherePanel.content, "BOTTOMRIGHT", 0, 34)
    else
        self.camp:Hide()
        self.zones:SetPoint("BOTTOMRIGHT", self.wherePanel.content, "BOTTOMRIGHT", 0, 0)
    end
end

function Dashboard:RefreshFeed()
    local Activity = GA.Modules.Activity
    local entries = Activity and Activity:List(60, Util.Now() - DAY) or {}
    -- Ohne etwas von heute: die letzten der Woche, damit die Seite nicht
    -- leer aufgeht — mit ihrem Zeitpunkt, der dann als Datum lesbar ist.
    if #entries == 0 and Activity then entries = Activity:List(20) end
    for _, entry in ipairs(entries) do
        if entry.kind == "LOOT" and entry.itemID then Compat.RequestItemData(entry.itemID) end
    end
    self.feed:SetData(entries)
    self.feedEmpty:SetShown(#entries == 0)
    if self.feedPanel.tag then
        self.feedPanel.tag:SetText(#entries > 0 and string.format(L.DASH_FEED_TAG, #entries) or "")
    end
end

function Dashboard:Refresh()
    if not self.frame then return end
    local identity = Compat.GetPlayerIdentity()
    local db = GA.Core.Database
    local character = identity.guid and db.account.characters[identity.guid]

    self:RefreshHero(identity, character)
    self:RefreshMine(identity, character)
    self:RefreshWhere()
    self:RefreshFeed()
    self:RefreshTradables()

    GA.UI.MainFrame:SetContext(character and character.equipmentTs
        and string.format(L.ARMORY_SNAPSHOT, Util.TimeAgo(character.equipmentTs)) or "")
end

GA.UI.MainFrame:RegisterView("dashboard", Dashboard)

-- ================================================================== Handel ----

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

function Dashboard:UpdatePostButton(eigene)
    local button = self.tradablesPost
    if not button then return end

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
            local info = (item.link and GA.Core.Compat.GetItemInfo(item.link))
                or (GA.Modules.ItemIndex and GA.Modules.ItemIndex:Get(item.itemID))
                or GA.Core.Compat.GetItemInfo(item.itemID)
            local label = (info and info.name)
                or string.format(L.SLASH_ITEM_FALLBACK, item.itemID)
            if (item.count or 1) > 1 then label = label .. "  x" .. item.count end

            rows[#rows + 1] = {
                label = label,
                quality = info and info.quality,
                icon = info and info.icon,
                owner = GA.Core.Util.ShortName(entry.name or "?"),
                ownerFull = entry.name,
                sure = entry.sure,
                itemID = item.itemID,
                link = item.link or (info and info.link),
            }
        end
    end

    table.sort(rows, function(a, b) return a.label < b.label end)
    self.tradables:SetData(rows)

    local eigene = GA.Modules.Tradables:Offered()
    self:UpdatePostButton(#eigene)

    if #rows == 0 then self.tradablesEmpty:Show() else self.tradablesEmpty:Hide() end
end

GA.Core.Callbacks:On("TRADABLES_CHANGED", function()
    if Dashboard.frame and Dashboard.frame:IsVisible() then Dashboard:RefreshTradables() end
end, "DashboardView")

-- Der Strom und der Rest der Seite: nur, solange sie zu sehen ist.
for _, event in ipairs({ "ACTIVITY_CHANGED", "SESSION_CHANGED", "GUILD_UPDATED", "EQUIPMENT_UPDATED" }) do
    GA.Core.Callbacks:On(event, function()
        if Dashboard.frame and Dashboard.frame:IsVisible() then Dashboard:Refresh() end
    end, "DashboardView")
end
