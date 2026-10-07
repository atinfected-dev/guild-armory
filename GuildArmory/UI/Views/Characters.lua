--[[----------------------------------------------------------------------------
    Views/Characters — der Stammbaum: Spieler, ihre Charaktere und die Rollen.

    Entwurf C2 (27.09.2026). Die Gilde als KARTENRASTER: jede Karte ein
    Spieler, oben die Rollenfarbe als Kante, der Main mit Wappen und Namen,
    darunter die Twinks an einer Linie — und DIE LINIE SELBST SAGT DIE
    HERKUNFT: durchgezogen jade = bewiesen, gestrichelt grau = gesetzt,
    gepunktet bernstein = behauptet. Filter oben (alle, Council, mit Twinks,
    nur behauptet). Rechts die Charaktere ohne Spieler, und darunter das
    Werkzeug zum gewaehlten Spieler: Rolle, Spitzname, Notiz, seine
    Charaktere mit "Zum Main" und "Loesen".

    WAS HIER SICHTBAR SEIN MUSS: die Herkunft jeder Zuordnung. "Bewiesen" steht
    nur an Charakteren desselben WoW-Accounts; alles andere ist als "gesetzt"
    oder "behauptet" markiert (siehe Armory/Players.lua). Eine Oberflaeche, die
    beides gleich aussehen laesst, macht aus einer Vermutung eine Tatsache.
    Deshalb ist die Herkunft hier nicht ein Wort in einer Spalte, sondern die
    Form der Linie, an der der Charakter haengt — und die Legende steht oben.
------------------------------------------------------------------------------]]

local _, GA = ...

local Characters = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

Characters.titleKey = "NAV_CHARACTERS"

local ROLES = {
    { key = GA.const.ROLE_ADMIN,      label = "ROLE_ADMIN" },
    { key = GA.const.ROLE_LOOTMASTER, label = "ROLE_LOOTMASTER" },
    { key = GA.const.ROLE_COUNCIL,    label = "ROLE_COUNCIL" },
    { key = GA.const.ROLE_MEMBER,     label = "ROLE_MEMBER" },
}

--- Farbe je Rolle: die Kante oben an der Karte und der Chip.
local ROLE_COLOR = {
    [GA.const.ROLE_ADMIN]      = "gold",
    [GA.const.ROLE_LOOTMASTER] = "warn",
    [GA.const.ROLE_COUNCIL]    = "jade",
    [GA.const.ROLE_MEMBER]     = "borderLit",
}

--- Farbe je Herkunft: Bewiesenes in Jade, Gesetztes neutral, Behauptetes in Warnfarbe.
local ORIGIN_COLOR = {
    account = "jade",
    manual  = "textDim",
    claim   = "warn",
}

--- Die Linie je Herkunft, als Segmente auf zehn Pixeln: durchgezogen,
--- gestrichelt, gepunktet. Drei Formen, die sich auch ohne Farbe
--- unterscheiden — Farbe allein liest nicht jeder.
local ORIGIN_SEGMENTS = {
    account = { { 0, 10 } },
    manual  = { { 0, 4 }, { 6, 10 } },
    claim   = { { 0, 2 }, { 4, 6 }, { 8, 10 } },
}

local CARD_MIN_W, CARD_GAP = 190, 8
local CARD_HEAD = 74      -- Wappen, Name, Meta, Rollenchip
local ALT_ROW = 24
local RIGHT_W = 262
local FILTERS = { "ALL", "COUNCIL", "ALTS", "CLAIM" }

-- ================================================================== Aufbau ----

function Characters:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Werkzeugzeile ---
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    bar:SetHeight(24)

    self.state = Theme.Label(bar, "", fonts.body, Theme.color.textDim)
    self.state:SetPoint("LEFT", bar, "LEFT", 2, 0)

    -- Filter als Chips: genau einer gedrueckt.
    self.filter = "ALL"
    self.filterChips = {}
    local vorige
    for _, key in ipairs(FILTERS) do
        local chip = Widgets.Chip(bar, L["CHAR_FILTER_" .. key], function(pressed, this)
            -- Ein Chip laesst sich nicht "ausdruecken": Ohne Filter ist
            -- "Alle" der Filter.
            self.filter = pressed and key or "ALL"
            self:Refresh()
        end)
        if vorige then chip:SetPoint("LEFT", vorige, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", self.state, "RIGHT", 14, 0) end
        chip.filterKey = key
        self.filterChips[#self.filterChips + 1] = chip
        vorige = chip
    end

    -- Die Legende, rechts: drei Linienformen mit Wort.
    local legend
    for _, origin in ipairs({ "claim", "manual", "account" }) do
        local label = Theme.Label(bar, L["CHAR_ORIGIN_" .. origin], fonts.small,
            Theme.color[ORIGIN_COLOR[origin]])
        if legend then label:SetPoint("RIGHT", legend, "LEFT", -14, 0)
        else label:SetPoint("RIGHT", bar, "RIGHT", -2, 0) end
        local line = CreateFrame("Frame", nil, bar)
        line:SetWidth(14) line:SetHeight(2)
        line:SetPoint("RIGHT", label, "LEFT", -4, 0)
        self:DrawSegments(line, origin, 14)
        legend = line
    end

    -- ------------------------------------------------------ Kartenraster ----
    local gridPanel = Widgets.Panel(frame, L.CHAR_PLAYERS)
    gridPanel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    gridPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    gridPanel:SetPoint("RIGHT", frame, "RIGHT", -(pad + RIGHT_W + gap), 0)
    self.gridPanel = gridPanel

    self.scroll = Widgets.ScrollArea(gridPanel.content)
    self.scroll:SetAllPoints(gridPanel.content)
    self.scroll:SetScript("OnSizeChanged", function(scroll)
        self:LayoutCards()
        scroll:Refresh()
    end)
    self.cards = {}

    self.gridEmpty = Theme.Label(gridPanel.content, L.CHAR_NONE, fonts.small, Theme.color.textFaint)
    self.gridEmpty:SetPoint("TOPLEFT", gridPanel.content, "TOPLEFT", 8, -8)
    self.gridEmpty:Hide()

    -- ------------------------------------------------------ Ohne Spieler ----
    local freePanel = Widgets.Panel(frame, L.CHAR_UNASSIGNED)
    freePanel:SetWidth(RIGHT_W)
    freePanel:SetHeight(24 + 150)
    freePanel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    self.freePanel = freePanel

    self.freeHint = Theme.Label(freePanel.content, L.CHAR_FREE_HINT, fonts.small, Theme.color.textFaint)
    self.freeHint:SetPoint("TOPLEFT", freePanel.content, "TOPLEFT", 2, 0)
    self.freeHint:SetPoint("RIGHT", freePanel.content, "RIGHT", -2, 0)
    self.freeHint:SetJustifyH("LEFT")

    self.free = Widgets.ScrollList(freePanel.content, {
        rowHeight = 26,
        createRow = function(row) self:BuildCharacterRow(row, "free") end,
        updateRow = function(row, character) self:UpdateCharacterRow(row, character, "free") end,
    })
    self.free:SetPoint("TOPLEFT", self.freeHint, "BOTTOMLEFT", -2, -2)
    self.free:SetPoint("BOTTOMRIGHT", freePanel.content, "BOTTOMRIGHT", 0, 0)

    -- ------------------------------------------------------ Der Gewaehlte ---
    local memberPanel = Widgets.Panel(frame, L.CHAR_MEMBERS)
    memberPanel:SetWidth(RIGHT_W)
    memberPanel:SetPoint("TOPLEFT", freePanel, "BOTTOMLEFT", 0, -gap)
    memberPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.memberPanel = memberPanel

    -- Rollenknoepfe: Sie setzen die Rolle am MAIN. Twinks erben sie ueber
    -- Database:GetEffectiveRole — deshalb steht hier auch der Hinweis, warum
    -- nicht jeder Charakter eine eigene Rolle bekommt. Zwei Reihen zu zwei:
    -- vier nebeneinander passen nicht in die Spalte.
    self.roleButtons = {}
    for index, entry in ipairs(ROLES) do
        local button = Widgets.Button(memberPanel.content, L[entry.label], function()
            self:SetRole(entry.key)
        end)
        button:SetHeight(20)
        local spalte, reihe = (index - 1) % 2, math.floor((index - 1) / 2)
        button:SetPoint("TOPLEFT", memberPanel.content, "TOPLEFT",
            spalte * 124, -(reihe * 24))
        button:SetWidth(120)
        button.roleKey = entry.key
        self.roleButtons[#self.roleButtons + 1] = button
    end

    self.roleHint = Theme.Label(memberPanel.content, L.CHAR_ROLE_HINT, fonts.small, Theme.color.textFaint)
    self.roleHint:SetPoint("TOPLEFT", memberPanel.content, "TOPLEFT", 2, -50)
    self.roleHint:SetPoint("RIGHT", memberPanel.content, "RIGHT", -2, 0)
    self.roleHint:SetJustifyH("LEFT")
    self.roleHint:SetWordWrap(false)

    -- Spitzname und Notiz zum Main des gewaehlten Profils. Sie stehen hier und
    -- nicht in jeder Zeile: Es ist eine Angabe zur PERSON, nicht zum Charakter.
    self.nickBox = Widgets.SearchBox(memberPanel.content, L.NOTE_NICKNAME, function(text)
        if self.noteGuid then GA.Modules.Notes:SetNickname(self.noteGuid, text) end
    end)
    self.nickBox:SetPoint("TOPLEFT", self.roleHint, "BOTTOMLEFT", -2, -6)
    self.nickBox:SetWidth(100)

    self.noteBox = Widgets.SearchBox(memberPanel.content, L.NOTE_NOTE, function(text)
        if self.noteGuid then GA.Modules.Notes:SetNote(self.noteGuid, text) end
    end)
    self.noteBox:SetPoint("LEFT", self.nickBox, "RIGHT", 6, 0)
    self.noteBox:SetPoint("RIGHT", memberPanel.content, "RIGHT", 0, 0)

    local noteHint = Theme.Label(memberPanel.content, L.NOTE_HINT, fonts.small, Theme.color.textFaint)
    noteHint:SetPoint("TOPLEFT", self.nickBox, "BOTTOMLEFT", 2, -3)
    noteHint:SetPoint("RIGHT", memberPanel.content, "RIGHT", 0, 0)
    noteHint:SetJustifyH("LEFT")
    noteHint:SetWordWrap(false)

    self.members = Widgets.ScrollList(memberPanel.content, {
        rowHeight = 26,
        createRow = function(row) self:BuildCharacterRow(row, "member") end,
        updateRow = function(row, character) self:UpdateCharacterRow(row, character, "member") end,
    })
    self.members:SetPoint("TOPLEFT", memberPanel.content, "TOPLEFT", 0, -108)
    self.members:SetPoint("BOTTOMRIGHT", memberPanel.content, "BOTTOMRIGHT", 0, 0)

    self.frame = frame
    return frame
end

-- ================================================================== Linien ----

--- Zeichnet die Herkunftslinie in einen Rahmen: Segmente auf dessen Breite.
function Characters:DrawSegments(holder, origin, width)
    holder.segments = holder.segments or {}
    for _, segment in ipairs(holder.segments) do segment:Hide() end

    local form = ORIGIN_SEGMENTS[origin] or ORIGIN_SEGMENTS.manual
    local color = Theme.color[ORIGIN_COLOR[origin] or "textDim"]
    local scale = (width or holder:GetWidth() or 10) / 10
    for index, span in ipairs(form) do
        local segment = holder.segments[index]
        if not segment then
            segment = holder:CreateTexture(nil, "ARTWORK")
            segment:SetHeight(2)
            holder.segments[index] = segment
        end
        Theme.Paint(segment, color)
        segment:ClearAllPoints()
        segment:SetPoint("LEFT", holder, "LEFT", span[1] * scale, 0)
        segment:SetWidth(math.max(1, (span[2] - span[1]) * scale))
        segment:Show()
    end
end

-- ================================================================== Karten ----

function Characters:BuildCard(index)
    if self.cards[index] then return self.cards[index] end
    local fonts = Theme.Fonts()

    local card = CreateFrame("Button", nil, self.scroll.content)
    card.fill = Theme.Fill(card, Theme.color.panelBg)
    card.lines = Theme.Outline(card, Theme.color.border)

    card.edge = card:CreateTexture(nil, "OVERLAY")
    card.edge:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.edge:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.edge:SetHeight(3)

    card.crest = card:CreateTexture(nil, "ARTWORK")
    card.crest:SetWidth(30) card.crest:SetHeight(30)
    card.crest:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -12)

    card.name = Theme.Label(card, "", fonts.nav, Theme.color.text)
    card.name:SetPoint("TOPLEFT", card.crest, "TOPRIGHT", 8, -1)
    card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    card.meta = Theme.Label(card, "", fonts.small, Theme.color.textDim)
    card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.meta:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.meta:SetJustifyH("LEFT")
    card.meta:SetWordWrap(false)

    -- Der Rollenchip: Rahmen und Wort in Rollenfarbe.
    card.role = CreateFrame("Frame", nil, card)
    card.role:SetHeight(15)
    card.role:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -50)
    card.roleLines = Theme.Outline(card.role, Theme.color.border)
    card.roleText = Theme.Label(card.role, "", fonts.small, Theme.color.textDim)
    card.roleText:SetPoint("CENTER", card.role, "CENTER", 0, 0)

    card.since = Theme.Label(card, "", fonts.small, Theme.color.textFaint)
    card.since:SetPoint("LEFT", card.role, "RIGHT", 6, 0)
    card.since:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.since:SetJustifyH("LEFT")
    card.since:SetWordWrap(false)

    -- Der Stamm: eine senkrechte Linie, an der die Twinks haengen.
    card.trunk = card:CreateTexture(nil, "ARTWORK")
    Theme.Paint(card.trunk, Theme.color.border)
    card.trunk:SetWidth(1)
    card.trunk:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -CARD_HEAD)

    card.alts = {}
    card.noAlts = Theme.Label(card, L.CHAR_NO_ALTS, fonts.small, Theme.color.textFaint)
    card.noAlts:SetPoint("TOPLEFT", card, "TOPLEFT", 24, -(CARD_HEAD + 6))
    card.noAlts:Hide()

    card:SetScript("OnClick", function(button)
        if button.profile then
            self.selectedPlayerId = button.profile.id
            self:Refresh()
        end
    end)
    card:SetScript("OnEnter", function(button)
        if not button.selected then Theme.Paint(button.fill, Theme.color.rowHover) end
    end)
    card:SetScript("OnLeave", function(button)
        if not button.selected then Theme.Paint(button.fill, Theme.color.panelBg) end
    end)

    self.cards[index] = card
    return card
end

--- Ein Twinkplatz auf einer Karte: Linie, Wappen, Name, Stufe.
local function buildAlt(card, index)
    local fonts = Theme.Fonts()
    local alt = CreateFrame("Frame", nil, card)
    alt:SetHeight(ALT_ROW)
    alt:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(CARD_HEAD + (index - 1) * ALT_ROW))
    alt:SetPoint("RIGHT", card, "RIGHT", 0, 0)

    alt.line = CreateFrame("Frame", nil, alt)
    alt.line:SetWidth(10) alt.line:SetHeight(2)
    alt.line:SetPoint("LEFT", alt, "LEFT", 17, 0)

    alt.crest = alt:CreateTexture(nil, "ARTWORK")
    alt.crest:SetWidth(12) alt.crest:SetHeight(12)
    alt.crest:SetPoint("LEFT", alt, "LEFT", 31, 0)

    alt.level = Theme.Label(alt, "", fonts.small, Theme.color.textFaint)
    alt.level:SetPoint("RIGHT", alt, "RIGHT", -8, 0)

    alt.name = Theme.Label(alt, "", fonts.small, Theme.color.text)
    alt.name:SetPoint("LEFT", alt.crest, "RIGHT", 5, 0)
    alt.name:SetPoint("RIGHT", alt.level, "LEFT", -4, 0)
    alt.name:SetJustifyH("LEFT")
    alt.name:SetWordWrap(false)

    card.alts[index] = alt
    return alt
end

--- Fuellt eine Karte. Gibt die Hoehe zurueck, die sie braucht.
function Characters:UpdateCard(card, profile)
    local Players = GA.Modules.Players
    local db = GA.Core.Database
    card.profile = profile

    local main = profile.mainGuid and db.account.characters[profile.mainGuid]
    local role = main and db:GetEffectiveRole(main.guid) or GA.const.ROLE_MEMBER
    local roleColor = Theme.color[ROLE_COLOR[role] or "borderLit"]
    Theme.Paint(card.edge, roleColor)

    local r, g, b = Theme.ClassColor(main and main.class)
    if main and main.class and Theme.SetClassPortrait(card.crest, main.class) then
        card.crest:Show()
    else
        card.crest:Hide()
    end

    card.name:SetText(Players:DisplayName(profile))
    card.name:SetTextColor(r, g, b)

    local level = main and main.itemLevel and main.itemLevel.value
    local teile = {}
    if main and (main.className or main.class) then teile[#teile + 1] = main.className or main.class end
    if main and main.level then teile[#teile + 1] = tostring(main.level) end
    if level then teile[#teile + 1] = L.COL_ILVL .. " " .. level end
    card.meta:SetText(table.concat(teile, " · "))

    card.roleText:SetText(string.upper(L["ROLE_" .. role] or role))
    card.roleText:SetTextColor(roleColor[1], roleColor[2], roleColor[3])
    for _, line in ipairs(card.roleLines) do Theme.Paint(line, roleColor) end
    card.role:SetWidth(card.roleText:GetStringWidth() + 12)

    -- Seit wann: aus der Rosterhistorie, wenn sie den Beitritt gesehen hat.
    local ts, gesehen = GA.Modules.GuildHistory and GA.Modules.GuildHistory:KnownSince(main and main.name)
    card.since:SetText(gesehen and ts and string.format(L.CHAR_SINCE, Util.TimeAgo(ts)) or "")

    -- Die Twinks: alle Charaktere ausser dem Main, wie CharactersOf sie ordnet.
    local alts = {}
    for _, character in ipairs(Players:CharactersOf(profile)) do
        if character.guid ~= profile.mainGuid then alts[#alts + 1] = character end
    end

    for index, character in ipairs(alts) do
        local alt = card.alts[index] or buildAlt(card, index)
        local origin = profile.origin and profile.origin[character.guid] or Players.ORIGIN_MANUAL
        self:DrawSegments(alt.line, origin, 10)
        local ar, ag, ab = Theme.ClassColor(character.class)
        if character.class and Theme.SetClassPortrait(alt.crest, character.class) then
            alt.crest:Show()
        else
            alt.crest:Hide()
        end
        alt.name:SetText(Util.ShortName(character.name or "?"))
        alt.name:SetTextColor(ar, ag, ab)
        alt.level:SetText(character.level and tostring(character.level) or "")
        alt:Show()
    end
    for index = #alts + 1, #card.alts do card.alts[index]:Hide() end

    if #alts == 0 then
        card.noAlts:Show()
        card.trunk:Hide()
    else
        card.noAlts:Hide()
        card.trunk:SetHeight(#alts * ALT_ROW - ALT_ROW / 2)
        card.trunk:Show()
    end

    card.selected = profile.id == self.selectedPlayerId
    if card.selected then
        Theme.Paint(card.fill, Theme.color.rowHover)
        for _, line in ipairs(card.lines) do Theme.Paint(line, Theme.color.gold) end
    else
        Theme.Paint(card.fill, Theme.color.panelBg)
        for _, line in ipairs(card.lines) do Theme.Paint(line, Theme.color.border) end
    end

    return CARD_HEAD + math.max(1, #alts) * ALT_ROW + 8
end

--- Legt die Karten ins Raster: so viele Spalten, wie der Platz hergibt,
--- Reihen so hoch wie ihre hoechste Karte.
function Characters:LayoutCards()
    local profiles = self.visibleProfiles or {}
    local content = self.scroll.content
    local breite = self.scroll:GetWidth()
    if not breite or breite <= 0 then return end
    content:SetWidth(breite)

    local spalten = math.max(1, math.floor((breite + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
    local cardW = math.floor((breite - (spalten - 1) * CARD_GAP) / spalten)

    local y, reihenHoehe, spalte = 0, 0, 0
    for index, profile in ipairs(profiles) do
        local card = self:BuildCard(index)
        local hoehe = self:UpdateCard(card, profile)
        card:ClearAllPoints()
        card:SetWidth(cardW)
        card:SetHeight(hoehe)
        card:SetPoint("TOPLEFT", content, "TOPLEFT", spalte * (cardW + CARD_GAP), -y)
        card:Show()

        reihenHoehe = math.max(reihenHoehe, hoehe)
        spalte = spalte + 1
        if spalte >= spalten then
            spalte = 0
            y = y + reihenHoehe + CARD_GAP
            reihenHoehe = 0
        end
    end
    if spalte > 0 then y = y + reihenHoehe end
    for index = #profiles + 1, #self.cards do self.cards[index]:Hide() end

    content:SetHeight(math.max(1, y))
    self.scroll:Refresh()
end

--- Welche Profile der Filter durchlaesst.
function Characters:FilteredProfiles(list)
    local Players = GA.Modules.Players
    local db = GA.Core.Database
    if self.filter == "ALL" then return list end

    local out = {}
    for _, profile in ipairs(list) do
        local keep = false
        if self.filter == "COUNCIL" then
            keep = profile.mainGuid ~= nil and db:HasAtLeast(profile.mainGuid, GA.const.ROLE_COUNCIL)
        elseif self.filter == "ALTS" then
            local count = 0
            for _ in pairs(profile.characterGuids) do count = count + 1 end
            keep = count >= 2
        elseif self.filter == "CLAIM" then
            for _, origin in pairs(profile.origin or {}) do
                if origin == Players.ORIGIN_CLAIM then keep = true break end
            end
        end
        if keep then out[#out + 1] = profile end
    end
    return out
end

-- ================================================================== Zeilen ----

--- Eine Charakterzeile mit zwei Aktionsknoepfen. Die Knoepfe werden einmal
--- gebaut und je Zeile umbeschriftet — die Liste recycelt ihre Zeilen.
function Characters:BuildCharacterRow(row, kind)
    local fonts = Theme.Fonts()

    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(14) row.crest:SetHeight(14)
    row.crest:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.secondary = Widgets.Button(row, "", function()
        if row.item then self:OnSecondary(row.item, kind) end
    end)
    row.secondary:SetHeight(18)
    row.secondary:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    -- Eine Zuordnung loesen ist unwiderruflich: erst "Wirklich?".
    if kind == "member" then row.secondary:SetConfirm(L.BTN_REALLY) end

    row.primary = Widgets.Button(row, "", function()
        if row.item then self:OnPrimary(row.item, kind) end
    end)
    row.primary:SetHeight(18)
    row.primary:SetPoint("RIGHT", row.secondary, "LEFT", -3, 0)

    row.name = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 26, -2)
    row.name:SetPoint("RIGHT", row.primary, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.meta = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.meta:SetPoint("TOPLEFT", row, "TOPLEFT", 26, -14)
    row.meta:SetPoint("RIGHT", row.primary, "LEFT", -4, 0)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetWordWrap(false)
end

--- SetLabel misst die Beschriftung und setzt die Breite danach — in einer
--- Tabellenzeile muessen die Knoepfe aber gleich breit bleiben, sonst wandert
--- bei jedem Neuzeichnen die Spalte. Deshalb Breite nach dem Beschriften.
local BUTTON_WIDTH = 66

local function setLabel(button, text)
    button:SetLabel(text)
    button:SetWidth(BUTTON_WIDTH)
end

function Characters:UpdateCharacterRow(row, character, kind)
    if row.secondary then row.secondary:Disarm() end
    local Players = GA.Modules.Players
    local profile = Players:GetProfileFor(character.guid)
    local isMain = profile and profile.mainGuid == character.guid

    local r, g, b = Theme.ClassColor(character.class)
    if character.class and Theme.SetClassPortrait(row.crest, character.class) then
        row.crest:Show()
    else
        row.crest:Hide()
    end

    local label = Util.ShortName(character.name or "?")
    if isMain then label = label .. "  " .. L.CHAR_MAIN_TAG end
    row.name:SetText(label)
    row.name:SetTextColor(r, g, b)

    local level = character.itemLevel and character.itemLevel.value
    local teile = { character.className or character.class or "?" }
    if character.level then teile[#teile + 1] = tostring(character.level) end
    teile[#teile + 1] = level and (L.COL_ILVL .. " " .. level) or "—"

    if kind == "member" then
        local origin = profile and profile.origin[character.guid]
        local key = origin and ("CHAR_ORIGIN_" .. origin) or nil
        local color = Theme.color[ORIGIN_COLOR[origin] or "textFaint"]
        if key then
            teile[#teile + 1] = Util.Colorize(L[key], color[1], color[2], color[3])
        end
        row.meta:SetText(table.concat(teile, " · "))

        -- Ein bewiesener Charakter (derselbe Account) laesst sich nicht
        -- "loesen": Die Zuordnung ist eine Tatsache, kein Eintrag.
        local proven = origin == Players.ORIGIN_ACCOUNT
        setLabel(row.primary, L.CHAR_SET_MAIN)
        row.primary:SetEnabledState(not isMain, isMain and L.CHAR_ALREADY_MAIN or nil)
        setLabel(row.secondary, L.CHAR_UNLINK)
        row.secondary:SetEnabledState(not proven, proven and L.CHAR_PROVEN_HINT or nil)
        row.secondary:Show()
    else
        if character.ownAccount then
            local jade = Theme.color.jade
            teile[#teile + 1] = Util.Colorize(L.CHAR_ORIGIN_account, jade[1], jade[2], jade[3])
        end
        row.meta:SetText(table.concat(teile, " · "))

        local hasTarget = self.selectedPlayerId ~= nil
        setLabel(row.primary, L.CHAR_ASSIGN)
        row.primary:SetEnabledState(hasTarget, hasTarget and nil or L.CHAR_PICK_PLAYER)
        setLabel(row.secondary, L.CHAR_NEW_PLAYER)
        row.secondary:SetEnabledState(true)
        row.secondary:Show()
    end
end

-- ================================================================== Aktionen --

function Characters:OnPrimary(character, kind)
    local Players = GA.Modules.Players
    if kind == "member" then
        local profile = Players:GetProfileFor(character.guid)
        if profile then Players:SetMain(profile.id, character.guid, true) end
    else
        if self.selectedPlayerId then
            Players:Link(character.guid, self.selectedPlayerId, Players.ORIGIN_MANUAL)
        end
    end
    self:Refresh()
end

function Characters:OnSecondary(character, kind)
    local Players = GA.Modules.Players
    if kind == "member" then
        Players:Unlink(character.guid)
    else
        local profile = Players:Create(character.guid, Players.ORIGIN_MANUAL)
        self.selectedPlayerId = profile.id
    end
    self:Refresh()
end

--- Setzt die Rolle am Main des gewaehlten Profils.
function Characters:SetRole(role)
    local Players = GA.Modules.Players
    local profile = Players:Get(self.selectedPlayerId)
    if not profile or not profile.mainGuid then return end

    local own = Compat.GetPlayerIdentity().guid
    if not GA.Core.Database:HasAtLeast(own, GA.const.ROLE_ADMIN) then
        GA.Core.Debug:Warn(L.CHAR_NEED_ADMIN)
        return
    end

    GA.Core.Database:SetRole(profile.mainGuid, role, own)
    self:Refresh()
end

-- ================================================================== Refresh ---

function Characters:OnShow() self:Refresh() end

function Characters:Refresh()
    if not self.frame then return end
    local Players = GA.Modules.Players
    local list = Players:List()

    -- Beim ersten Anzeigen das eigene Profil waehlen — das ist fast immer das,
    -- was der Spieler sehen will.
    if not self.selectedPlayerId or not Players:Get(self.selectedPlayerId) then
        local ownProfile = Players:GetProfileFor(Compat.GetPlayerIdentity().guid)
        self.selectedPlayerId = (ownProfile and ownProfile.id) or (list[1] and list[1].id)
    end

    for _, chip in ipairs(self.filterChips) do
        chip:SetPressed(chip.filterKey == self.filter)
    end

    local gesamt = 0
    for _, profile in ipairs(list) do
        for _ in pairs(profile.characterGuids) do gesamt = gesamt + 1 end
    end
    self.state:SetText(string.format(L.CHAR_STATE, #list, gesamt))

    self.visibleProfiles = self:FilteredProfiles(list)
    self.gridEmpty:SetShown(#self.visibleProfiles == 0)
    self:LayoutCards()

    local profile = Players:Get(self.selectedPlayerId)
    self.memberPanel:SetTitle(profile
        and string.format(L.CHAR_MEMBERS_OF, Players:DisplayName(profile))
        or L.CHAR_MEMBERS)
    self.members:SetData(profile and Players:CharactersOf(profile) or {})

    -- Notizfelder auf den Main des gewaehlten Profils. Das Setzen der Texte
    -- loest OnTextChanged aus, deshalb wird der Empfaenger vorher abgeschaltet:
    -- Sonst schriebe das blosse Anzeigen die Notiz zurueck.
    self.noteGuid = nil
    local mainGuid = profile and profile.mainGuid
    self.nickBox.edit:SetText(mainGuid and (GA.Modules.Notes:GetNickname(mainGuid) or "") or "")
    self.noteBox.edit:SetText(mainGuid and (GA.Modules.Notes:GetNote(mainGuid) or "") or "")
    self.noteGuid = mainGuid

    local free = Players:Unassigned()
    self.freePanel:SetTitle(#free > 0
        and string.format("%s (%d)", L.CHAR_UNASSIGNED, #free) or L.CHAR_UNASSIGNED)
    self.freeHint:SetText(profile
        and string.format(L.CHAR_FREE_HINT_TO, Players:DisplayName(profile))
        or L.CHAR_FREE_HINT)
    self.free:SetData(free)

    -- Rollenknoepfe: der aktuelle Rang ist gedrueckt (deaktiviert), die
    -- anderen waehlbar — aber nur fuer einen Admin.
    local own = Compat.GetPlayerIdentity().guid
    local isAdmin = GA.Core.Database:HasAtLeast(own, GA.const.ROLE_ADMIN)
    local current = profile and profile.mainGuid
        and GA.Core.Database:GetEffectiveRole(profile.mainGuid) or nil

    for _, button in ipairs(self.roleButtons) do
        local usable = isAdmin and profile ~= nil and button.roleKey ~= current
        button:SetEnabledState(usable,
            (not isAdmin) and L.CHAR_NEED_ADMIN
            or (button.roleKey == current and L.CHAR_ROLE_CURRENT or nil))
    end

    GA.UI.MainFrame:SetContext(string.format(L.CHAR_CONTEXT, #list, #free))
end

GA.UI.MainFrame:RegisterView("characters", Characters)

for _, event in ipairs({ "PLAYERS_CHANGED", "ROLES_CHANGED", "NOTES_CHANGED" }) do
    GA.Core.Callbacks:On(event, function()
        if Characters.frame and Characters.frame:IsVisible() then Characters:Refresh() end
    end, "CharactersView")
end
