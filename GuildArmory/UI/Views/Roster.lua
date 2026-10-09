--[[----------------------------------------------------------------------------
    Views/Roster — das Verzeichnis: was Blizzards Gildenfenster kann, hier.

    Entwurf R1 (28.09.2026). Oben die Gilde mit Nachricht des Tages, die
    Liste als Tabelle (Wappen, Name, Stufe, Zone, Rang, Notiz, zuletzt),
    darunter der Gildenchat, rechts das gewaehlte Mitglied mit Rang,
    Notizen, Verlauf und den Handlungen. Fuer Bank und Rangrechte gibt es
    den Knopf zu Blizzards Fenster — das kann kein Addon ersetzen.

    MIT DEINEN RECHTEN IM SPIEL, NICHT MEHR UND NICHT WENIGER. Jeder Knopf,
    der die Gilde veraendert, fragt vorher die Can*-Funktion des Clients
    und sagt im Tooltip, warum er aus ist. Und was der Client nicht hergibt
    (Compat gibt nil zurueck), zeigt die Seite als "nicht messbar", nicht
    als "nein" — die Sonde "guildManage" sagt, was auf dieser Linie da ist.

    EINE NOTIZ, und sie geht durch die Gilde — ueber das Addon
    (Communication/GuildNotes), nicht ueber Blizzards Felder: Die sind
    aus einem Addon auf diesem Client nicht zu schreiben (gemessen
    28.09.2026, drei Wege, alle geblockt) und stehen hier darum nicht.
    Die Beschriftung sagt, dass alle sie sehen; der private Zettel
    (Armory/Notes.lua) bleibt im Charakterfenster, wo er hingehoert.
------------------------------------------------------------------------------]]

local _, GA = ...

local View = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

View.titleKey = "NAV_ROSTER"

local DETAIL_W = 250
local CHAT_H = 260
--- Zugeklappt bleibt nur die Kopfzeile des Chats.
local CHAT_FOLDED_H = 24
local FILTERS = { "ALL", "ONLINE", "OFFICERS", "NONOTE" }

--- Farbe je Rangstufe: die ersten drei tragen Farbe, der Rest ist grau.
local RANK_COLOR = { [0] = "gold", [1] = "warn", [2] = "jade" }
local function rankColor(rankIndex)
    return Theme.color[RANK_COLOR[rankIndex or 99] or "textDim"]
end

local COLUMN_GAP, COLUMN_X0 = 6, 8
--- Entwurf R3 (03.10.2026): Wappen, Name mit Rangzeichen und Unterzeile
--- (Klasse · Stufe · Rang), Zone, Notiz, und rechts, was die Person im
--- Addon gerade tut — oder wann sie zuletzt da war. Die Rangspalte ist weg.
local function columns()
    return {
        { key = "crest", label = "",                 width = 22 },
        { key = "name",  label = L.COL_NAME,         width = 150 },
        -- Stufe als Zahl und Balken bis 60, mit einer Marke je zehn Stufen
        -- (Entwuerfe vom 05.10.2026): der Weg, nicht nur der Stand.
        { key = "level", label = L.COL_LEVEL,        width = 66 },
        { key = "zone",  label = L.ROSTER_COL_ZONE,  width = 110 },
        { key = "note",  label = L.ROSTER_COL_NOTE,  width = 100 },
        { key = "now",   label = L.ROSTER_COL_NOW,   width = 200 },  -- links unter der Ueberschrift, bis zum Rand (Bild 03.10.2026)
    }
end

local ROW_H = 32
local LEVEL_MAX = 60
local LEVEL_BAR_W = 40
--- Rangzeichen des Spiels: Krone fuer den Gildenmeister, Stern fuer den
--- zweiten Rang. Gibt der Client sie nicht her, bleibt der Platz leer.
local RANK_ICON = {
    [0] = [[Interface\GroupFrame\UI-Group-LeaderIcon]],
    [1] = [[Interface\GroupFrame\UI-Group-AssistantIcon]],
}

local function offsets()
    local x, out, w = COLUMN_X0, {}, {}
    for _, column in ipairs(columns()) do
        out[column.key] = x
        w[column.key] = column.width
        x = x + column.width + COLUMN_GAP
    end
    return out, w
end

--- Ein Eingabefeld, das beim Enter speichert und bei Escape verwirft.
local function trim(text)
    return (tostring(text or "")):match("^%s*(.-)%s*$")
end

local function editBox(parent, width, onSave)
    local box = Theme.CreateNative("EditBox", nil, parent, "InputBoxTemplate")
    if not box then
        box = CreateFrame("EditBox", nil, parent)
        Theme.Fill(box, Theme.color.windowBg)
        Theme.Outline(box, Theme.color.border)
        box:SetFontObject(Theme.Fonts().row)
        box:SetTextInsets(6, 6, 0, 0)
    end
    box:SetWidth(width or 100)
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(self.original or "")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onSave then onSave(self:GetText()) end
    end)
    function box:Load(text)
        self.original = text or ""
        self:SetText(text or "")
    end
    return box
end

-- ================================================================== Aufbau ----

function View:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Kopf ------------
    local head = Widgets.Inset(frame)
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    head:SetHeight(58)
    self.head = head

    self.guildName = Theme.Label(head, "", fonts.big, Theme.color.goldBright)
    self.guildName:SetPoint("TOPLEFT", head, "TOPLEFT", 14, -10)
    self.guildName:SetWordWrap(false)

    self.guildMeta = Theme.Label(head, "", fonts.small, Theme.color.textDim)
    self.guildMeta:SetPoint("TOPLEFT", self.guildName, "BOTTOMLEFT", 0, -3)
    self.guildMeta:SetWordWrap(false)

    self.blizzardButton = Widgets.Button(head, L.ROSTER_BLIZZARD, function()
        -- Dieser Knopf WILL Blizzards Fenster: der Haken am Fenster laesst
        -- es dann durch, statt es wieder hierher zu lenken.
        View.openingBlizzard = true
        Compat.After(1, function() View.openingBlizzard = nil end)
        local weg = Compat.OpenBlizzardGuildFrame()
        if not weg then GA.UI.MainFrame:Notice("info", "%s", L.ROSTER_BLIZZARD_NONE) end
    end)
    self.blizzardButton:SetPoint("RIGHT", head, "RIGHT", -12, 0)

    self.infoButton = Widgets.Button(head, L.ROSTER_INFO, function() self:EditGuildInfo() end)
    self.infoButton:SetTooltip(L.TT_ROSTER_INFO)
    self.infoButton:SetPoint("RIGHT", self.blizzardButton, "LEFT", -6, 0)

    self.inviteButton = Widgets.Button(head, L.ROSTER_INVITE, function() self:ShowInvite() end)
    self.inviteButton:SetPoint("RIGHT", self.infoButton, "LEFT", -6, 0)

    -- Die Nachricht des Tages: ein Knopf, weil Klick bearbeitet.
    self.motd = CreateFrame("Button", nil, head)
    self.motd:SetPoint("TOPLEFT", head, "TOPLEFT", 250, -8)
    self.motd:SetPoint("BOTTOMRIGHT", self.inviteButton, "BOTTOMLEFT", -14, 0)
    self.motd:SetPoint("BOTTOM", head, "BOTTOM", 0, 8)
    self.motdHead = Theme.Label(self.motd, "", fonts.heading, Theme.color.goldDim)
    self.motdHead:SetPoint("TOPLEFT", self.motd, "TOPLEFT", 0, -2)
    self.motdText = Theme.Label(self.motd, "", fonts.row, Theme.color.text)
    self.motdText:SetPoint("TOPLEFT", self.motdHead, "BOTTOMLEFT", 0, -4)
    self.motdText:SetPoint("RIGHT", self.motd, "RIGHT", 0, 0)
    self.motdText:SetJustifyH("LEFT")
    self.motdText:SetWordWrap(false)
    self.motd:SetScript("OnClick", function() self:EditMOTD() end)

    -- ------------------------------------------------------ Filter ----------
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    bar:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -6)
    bar:SetHeight(22)

    self.filter = "ALL"
    self.filterChips = {}
    local vorige
    for _, key in ipairs(FILTERS) do
        local chip = Widgets.Chip(bar, L["ROSTER_FILTER_" .. key], function(pressed)
            self.filter = pressed and key or "ALL"
            self:Refresh()
        end)
        if vorige then chip:SetPoint("LEFT", vorige, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", bar, "LEFT", 2, 0) end
        chip.filterKey = key
        self.filterChips[#self.filterChips + 1] = chip
        vorige = chip
    end

    self.search = Widgets.SearchBox(bar, L.ROSTER_SEARCH, function() self:Refresh() end)
    self.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    self.search:SetWidth(200)

    -- ------------------------------------------------------ Rechts ----------
    local detail = Widgets.Inset(frame)
    detail:SetWidth(DETAIL_W)
    detail:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.detail = detail
    self:BuildDetail(detail, fonts)

    -- ------------------------------------------------------ Chat ------------
    local chat = Widgets.Panel(frame, L.ROSTER_CHAT)
    chat:SetHeight(CHAT_H)
    chat:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    chat:SetPoint("RIGHT", detail, "LEFT", -gap, 0)
    self.chatPanel = chat
    self:BuildChat(chat, fonts)

    -- ------------------------------------------------------ Tabelle ---------
    local list = Widgets.Panel(frame, L.ROSTER_TITLE, "")
    list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    list:SetPoint("RIGHT", detail, "LEFT", -gap, 0)
    list:SetPoint("BOTTOM", chat, "TOP", 0, gap)
    self.listPanel = list

    self.rows = Widgets.ScrollList(list.content, {
        rowHeight = ROW_H,
        columns = columns(),
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, member) self:UpdateRow(row, member) end,
        onClickRow = function(member, _, button)
            if member.header then return end
            self.selectedKey = member.name
            self:Refresh()
            -- Rechtsklick auf jemanden, der online ist: Fluestern oder
            -- Einladen (Wunsch 05.10.2026).
            if button == "RightButton" then self:ShowMemberMenu(member) end
        end,
    })
    self.rows:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, 0)
    self.rows:SetPoint("BOTTOMRIGHT", list.content, "BOTTOMRIGHT", 0, 16)

    self.footer = Theme.Label(list.content, "", fonts.small, Theme.color.textFaint)
    self.footer:SetPoint("BOTTOMLEFT", list.content, "BOTTOMLEFT", 2, 1)
    self.footer:SetPoint("RIGHT", list.content, "RIGHT", -2, 0)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetWordWrap(false)

    self.frame = frame
    return frame
end

-- ================================================================== Zeilen ----

function View:BuildRow(row)
    local fonts = Theme.Fonts()
    local x, w = offsets()

    row.edge = Theme.Fill(row, Theme.color.gold)
    row.edge:ClearAllPoints()
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(2)
    row.edge:Hide()

    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetWidth(20) row.crest:SetHeight(20)
    row.crest:SetPoint("LEFT", row, "LEFT", x.crest, 0)

    row.rankIcon = row:CreateTexture(nil, "OVERLAY")
    row.rankIcon:SetWidth(11) row.rankIcon:SetHeight(11)
    row.rankIcon:SetPoint("TOPLEFT", row, "TOPLEFT", x.name, -4)
    row.rankIcon:Hide()

    row.name = Theme.Label(row, "", fonts.rowBold or fonts.row, Theme.color.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", x.name, -3)
    row.name:SetWidth(w.name)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.sub = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.sub:SetWidth(w.name)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.levelText = Theme.Label(row, "", fonts.rowBold or fonts.row, Theme.color.heading)
    row.levelText:SetPoint("LEFT", row, "LEFT", x.level, 0)
    row.levelText:SetWidth(20)
    row.levelText:SetJustifyH("RIGHT")
    row.levelBg = row:CreateTexture(nil, "ARTWORK")
    Theme.BarTrough(row.levelBg)
    row.levelBg:SetWidth(LEVEL_BAR_W) row.levelBg:SetHeight(4)
    row.levelBg:SetPoint("LEFT", row, "LEFT", x.level + 24, 0)
    row.levelFill = row:CreateTexture(nil, "OVERLAY")
    Theme.BarFill(row.levelFill, Theme.color.gold)
    row.levelFill:SetHeight(4)
    row.levelFill:SetPoint("LEFT", row.levelBg, "LEFT", 0, 0)
    row.levelTicks = {}
    for i = 1, 5 do
        local tick = row:CreateTexture(nil, "OVERLAY", nil, 2)
        tick:SetWidth(1) tick:SetHeight(6)
        tick:SetPoint("CENTER", row.levelBg, "LEFT", math.floor(LEVEL_BAR_W * i * 10 / LEVEL_MAX), 0)
        Theme.Paint(tick, { Theme.color.windowBg[1], Theme.color.windowBg[2], Theme.color.windowBg[3], 0.85 })
        row.levelTicks[i] = tick
    end

    row.zone = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.zone:SetPoint("LEFT", row, "LEFT", x.zone, 0)
    row.zone:SetWidth(w.zone)
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)

    row.note = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.note:SetPoint("LEFT", row, "LEFT", x.note, 0)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)

    -- Links an der Spalte, bis zum rechten Rand: der Text beginnt unter
    -- seiner Ueberschrift, nicht am Rand (Bild 03.10.2026).
    row.now = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.now:SetPoint("LEFT", row, "LEFT", x.now, 0)
    row.now:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.now:SetJustifyH("LEFT")
    row.now:SetWordWrap(false)
    row.note:SetPoint("RIGHT", row, "LEFT", x.now - 6, 0)

    -- Die Gruppenzeile: Punkt, Beschriftung, Linie bis zum Rand.
    row.groupDot = row:CreateTexture(nil, "ARTWORK")
    row.groupDot:SetWidth(7) row.groupDot:SetHeight(7)
    row.groupDot:SetPoint("LEFT", row, "LEFT", x.crest + 6, -2)
    if Theme.RoundTexture() then row.groupDot:SetTexture(Theme.RoundTexture()) end
    row.groupDot:Hide()
    row.groupText = Theme.Label(row, "", fonts.small, Theme.color.goldDim)
    row.groupText:SetPoint("LEFT", row.groupDot, "RIGHT", 6, 0)
    row.groupText:Hide()
    row.groupLine = row:CreateTexture(nil, "ARTWORK")
    row.groupLine:SetHeight(1)
    row.groupLine:SetPoint("LEFT", row.groupText, "RIGHT", 8, 0)
    row.groupLine:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    Theme.Paint(row.groupLine, Theme.color.border)
    row.groupLine:Hide()
end

--- Was die Person im Addon gerade tut: leitet einen Lauf, steht in einem,
--- sucht Leute, bietet etwas an. Das Erste, das zutrifft.
local function activityOf(name)
    local short = Util.ShortName(name or "")
    local Hub = GA.Modules.Dungeonhub
    if Hub then
        for _, run in ipairs(Hub:List()) do
            local wann = date("%H:%M", run.at or 0)
            if run.leader == short then
                return string.format(L.ROSTER_NOW_LEADS, run.dungeon or "?", wann), Theme.color.gold
            elseif run.members and run.members[short] then
                return string.format(L.ROSTER_NOW_IN, run.dungeon or "?", wann), Theme.color.textDim
            end
        end
    end
    local Questhub = GA.Modules.Questhub
    if Questhub then
        for _, request in ipairs(Questhub:List()) do
            if request.seeker == short then
                return string.format(L.ROSTER_NOW_SEEKS, request.title or "?"), Theme.color.textDim
            end
        end
    end
    local Tradables = GA.Modules.Tradables
    if Tradables and Tradables.All then
        for _, entry in ipairs(Tradables:All()) do
            if Util.ShortName(entry.name or "") == short and entry.items and #entry.items > 0 then
                return string.format(L.ROSTER_NOW_OFFERS, #entry.items), Theme.color.textDim
            end
        end
    end
    return nil
end

local function showLevel(row, on)
    for _, w in ipairs({ row.levelText, row.levelBg, row.levelFill }) do w:SetShown(on) end
    for _, tick in ipairs(row.levelTicks or {}) do tick:SetShown(on) end
end

local function showMember(row, on)
    for _, w in ipairs({ row.crest, row.name, row.sub, row.zone, row.note, row.now }) do w:SetShown(on) end
    showLevel(row, on)
    for _, w in ipairs({ row.groupDot, row.groupText, row.groupLine }) do w:SetShown(not on) end
    if on then row.rankIcon:Hide() end
end

function View:UpdateRow(row, member)
    if member.header then
        row.edge:Hide()
        showMember(row, false)
        row.rankIcon:Hide()
        local c = member.online and Theme.color.jade or Theme.color.border
        Theme.Tint(row.groupDot, c)
        local t = member.online and Theme.color.goldDim or Theme.color.textFaint
        row.groupText:SetText(string.upper(member.label) .. "  \194\183  " .. tostring(member.count))
        row.groupText:SetTextColor(t[1], t[2], t[3])
        row:SetAlpha(1)
        return
    end
    showMember(row, true)

    local selected = member.name == self.selectedKey
    if selected then
        row.edge:Show()
        Theme.Paint(row.background, Theme.color.rowHover)
    else
        row.edge:Hide()
    end

    local r, g, b = Theme.ClassColor(member.class)
    if member.class and Theme.SetClassPortrait(row.crest, member.class) then row.crest:Show() else row.crest:Hide() end

    -- Rangzeichen vor dem Namen; der Name rueckt dafuer ein.
    local icon = RANK_ICON[member.rankIndex or 99]
    local x = offsets()
    local einzug = 0
    if icon and Theme.TextureExists(icon) and pcall(row.rankIcon.SetTexture, row.rankIcon, icon) then
        row.rankIcon:Show()
        einzug = 14
    else
        row.rankIcon:Hide()
    end
    -- Neu verankern heisst erst loesen: SetPoint fuegt hinzu, es ersetzt nicht.
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", x.name + einzug, -3)

    local nick = member.guid and GA.Modules.Notes:GetNickname(member.guid)
    row.name:SetText(member.name .. (nick and nick ~= "" and (" |cff6f6753„" .. nick .. "“|r") or ""))
    row.name:SetTextColor(r, g, b)

    local teile = {}
    if member.className or member.class then teile[#teile + 1] = member.className or member.class end
    if member.rankName then teile[#teile + 1] = member.rankName end
    local level = tonumber(member.level)
    if level and level > 0 then
        showLevel(row, true)
        row.levelText:SetText(tostring(level))
        row.levelFill:SetWidth(math.max(1, math.floor(LEVEL_BAR_W * math.min(1, level / LEVEL_MAX))))
    else
        showLevel(row, false)
    end
    local farbe = rankColor(member.rankIndex)
    row.sub:SetText(table.concat(teile, " \194\183 "))
    row.sub:SetTextColor(farbe[1] * 0.85 + 0.1, farbe[2] * 0.85 + 0.1, farbe[3] * 0.85 + 0.1)

    -- Zone, mit "HIER", wenn es die eigene ist.
    local zone = member.online and member.zone or nil
    if zone and self.ownZone and zone == self.ownZone then
        row.zone:SetText(zone .. "  |cffc9a24a" .. L.ROSTER_HERE .. "|r")
    else
        row.zone:SetText(zone or "")
    end

    row.note:SetText(GA.Modules.GuildNotes:Get(GA.Modules.GuildNotes.Key(member.guid, member.name)) or "")

    -- Rechts: online, was die Person gerade tut; offline, wann zuletzt.
    if member.online then
        local text, color = activityOf(member.name)
        row.now:SetText(text or "")
        local c = color or Theme.color.textDim
        row.now:SetTextColor(c[1], c[2], c[3])
    else
        local weg = member.lastOnlineTs and Util.TimeAgo(member.lastOnlineTs)
        if not weg then
            local index = Compat.FindGuildMemberIndex(member.name)
            local sekunden = index and Compat.GetGuildMemberLastOnline(index)
            weg = sekunden and Util.TimeAgo(Util.Now() - sekunden) or nil
        end
        row.now:SetText(weg and string.format(L.ROSTER_LAST_SEEN, weg) or "—")
        row.now:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    -- Offline gedaempft: Die Zeile bleibt lesbar, aber sie tritt zurueck.
    row:SetAlpha(member.online and 1 or 0.6)
end

-- ================================================================== Rechts ----

function View:BuildDetail(parent, fonts)
    local d = parent
    d.crest = d:CreateTexture(nil, "ARTWORK")
    d.crest:SetWidth(32) d.crest:SetHeight(32)
    d.crest:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -12)

    d.name = Theme.Label(d, "", fonts.big, Theme.color.text)
    d.name:SetPoint("TOPLEFT", d.crest, "TOPRIGHT", 8, -1)
    d.name:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)

    d.meta = Theme.Label(d, "", fonts.small, Theme.color.textDim)
    d.meta:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -2)
    d.meta:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.meta:SetJustifyH("LEFT")
    d.meta:SetWordWrap(false)

    d.since = Theme.Label(d, "", fonts.small, Theme.color.textFaint)
    d.since:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -50)
    d.since:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.since:SetJustifyH("LEFT")
    d.since:SetWordWrap(false)

    -- Rang: hoch, aktuell, runter.
    d.rankHead = Theme.Label(d, string.upper(L.ROSTER_COL_RANK), fonts.heading, Theme.color.goldDim)
    d.rankHead:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -70)

    -- SICHERE KNOEPFE: Befoerdern und Degradieren laufen als Makro
    -- des Spiels aus dem Klick des Spielers (Widgets.SecureMacroButton) —
    -- GuildPromote aus Addon-Code wird geblockt (gemessen 28.09.2026).
    -- Kennt der Client die Vorlage nicht, bleiben normale Knoepfe, die
    -- sagen, dass es nur in Blizzards Fenster geht.
    -- DIE SICHEREN KNOEPFE SIND KINDER VON d, und damit ist das Hauptfenster
    -- im Kampf geschuetzt. Zwei Umwege sind gescheitert (28./29.09.2026):
    -- ein Traeger neben dem Fenster, an d verankert, sperrte das Fenster
    -- trotzdem; ein Traeger, der sich aus Bildschirmkoordinaten ueber d
    -- legt, liess die Pfeile in der Landschaft haengen. Die Antwort ist
    -- im Hauptfenster: Das Spiel versteckt es beim Kampfbeginn selbst
    -- (Zustandssteuerung), und danach geht es wieder auf.
    local function macroButton(text, variant)
        local button = Widgets.SecureMacroButton(d, text, variant)
        if button then
            button.onAfter = function() Compat.After(0.5, function() Compat.RequestGuildRoster() end) end
            return button, true
        end
        button = Widgets.Button(d, text, function() GA.UI.MainFrame:Notice("info", "%s", L.ROSTER_SECURE_NONE) end)
        return button, false
    end
    -- Die Zeile: [Pfeil hoch] [aktueller Rang als breiter Chip] [Pfeil runter],
    -- darunter die Namen der Nachbarstufen. Die Pfeile sind Texturen des
    -- Spiels — "▲" als Schrift rendert die Spielschrift als Kaestchen
    -- (gesehen 28.09.2026); fehlt die Textur, steht "+" bzw. "-" da.
    local ARROW = 22
    d.promote, d.secure = macroButton("")
    d.promote:SetSize(ARROW, ARROW)
    -- Am Frame verankert, nicht an der Ueberschrift: ein geschuetzter
    -- Knopf darf nicht an einer Region haengen (gemessen 28.09.2026).
    d.promote:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -86)
    if not (d.promote.SetArrow and d.promote:SetArrow("up", 14)) and d.promote.SetIcon then
        d.promote:SetIcon("Interface\\Buttons\\Arrow-Up-Up", 14, "+")
    end

    d.rankNow = CreateFrame("Frame", nil, d)
    d.rankNow:SetHeight(ARROW)
    d.rankNow:SetWidth(DETAIL_W - 24 - 2 * (ARROW + 4))
    -- An d, nicht am Pfeil: Nichts im Fenster haengt an einem geschuetzten Knopf.
    d.rankNow:SetPoint("TOPLEFT", d, "TOPLEFT", 12 + ARROW + 4, -86)
    -- Eingelassen wie ein Feld in der Platte (Plakette, 09.10.2026).
    d.rankInset = Theme.Look() and Theme.Inset(d.rankNow) or nil
    d.rankFill = Theme.Fill(d.rankNow, { 0, 0, 0, 0 })
    d.rankLines = Theme.Outline(d.rankNow, Theme.color.border)
    d.rankText = Theme.Label(d.rankNow, "", fonts.rowBold, Theme.color.text)
    d.rankText:SetPoint("CENTER", d.rankNow, "CENTER", 0, 0)

    d.demote = macroButton("")
    d.demote:SetSize(ARROW, ARROW)
    d.demote:SetPoint("LEFT", d.rankNow, "RIGHT", 4, 0)
    if not (d.demote.SetArrow and d.demote:SetArrow("down", 14)) and d.demote.SetIcon then
        d.demote:SetIcon("Interface\\Buttons\\Arrow-Down-Up", 14, "-")
    end

    d.rankHint = Theme.Label(d, "", fonts.small, Theme.color.textFaint)
    d.rankHint:SetPoint("TOPLEFT", d.promote, "BOTTOMLEFT", 0, -4)
    d.rankHint:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.rankHint:SetJustifyH("LEFT")
    d.rankHint:SetWordWrap(false)

    -- EINE NOTIZ, die alle mit Guild Armory sehen (Communication/GuildNotes).
    -- Blizzards oeffentliche und Offiziersnotiz stehen hier nicht mehr:
    -- Aus einem Addon sind sie auf diesem Client nicht zu schreiben
    -- (gemessen 28.09.2026, drei Wege, alle geblockt), und eine Notiz,
    -- die nur Blizzards Fenster aendern kann, gehoert in Blizzards Fenster.
    d.notesHead = Theme.Label(d, string.upper(L.ROSTER_NOTES), fonts.heading, Theme.color.goldDim)
    d.notesHead:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -128)
    d.noteCaption = Theme.Label(d, L.ROSTER_NOTE_SHARED, fonts.small, Theme.color.textDim)
    d.noteCaption:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -144)
    d.noteCaption:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.noteCaption:SetJustifyH("LEFT")
    d.noteCaption:SetWordWrap(false)
    d.noteBox = editBox(d, DETAIL_W - 30, function(text) self:SaveNote(text) end)
    d.noteBox:SetPoint("TOPLEFT", d.noteCaption, "BOTTOMLEFT", 6, -2)
    d.noteMeta = Theme.Label(d, "", fonts.small, Theme.color.textFaint)
    d.noteMeta:SetPoint("TOPLEFT", d.noteBox, "BOTTOMLEFT", 0, -3)
    d.noteMeta:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.noteMeta:SetJustifyH("LEFT")
    d.noteMeta:SetWordWrap(false)

    -- Verlauf: die letzten drei Eintraege der Rosterhistorie.
    d.historyHead = Theme.Label(d, string.upper(L.ROSTER_HISTORY), fonts.heading, Theme.color.goldDim)
    d.historyHead:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -204)
    d.history = {}
    for index = 1, 3 do
        local line = Theme.Label(d, "", fonts.small, Theme.color.textDim)
        line:SetPoint("TOPLEFT", d.historyHead, "BOTTOMLEFT", 0, -(4 + (index - 1) * 14))
        line:SetPoint("RIGHT", d, "RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        d.history[index] = line
    end

    -- KEIN ENTFERNEN HIER (28.09.2026, Wunsch der Gilde): Wer jemanden aus
    -- der Gilde wirft, oeffnet dafuer Blizzards Fenster. Ein Knopf, der
    -- das in einem Verzeichnis tut, ist zu leicht gedrueckt.

    d.whisper = Widgets.Button(d, L.QH_WHISPER, function()
        local member = self:Selected()
        if member then Compat.OpenWhisper(member.name) end
    end)
    d.whisper:SetHeight(22)
    d.whisper:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 12)
    d.whisper:SetWidth(72)

    d.invite = Widgets.Button(d, L.QH_INVITE, function()
        local member = self:Selected()
        if member then GA.Modules.Guild:Invite({ member.name }) end
    end)
    d.invite:SetHeight(22)
    d.invite:SetPoint("LEFT", d.whisper, "RIGHT", 4, 0)
    d.invite:SetWidth(72)

    d.gear = Widgets.Button(d, L.NAV_EQUIPMENT, function()
        local member = self:Selected()
        local armory = GA.UI.MainFrame.views and GA.UI.MainFrame.views.armory
        if member and member.guid and armory then armory.selectedGuid = member.guid end
        GA.UI.MainFrame:ShowView("armory")
    end)
    d.gear:SetHeight(22)
    d.gear:SetPoint("LEFT", d.invite, "RIGHT", 4, 0)
    d.gear:SetPoint("RIGHT", d, "RIGHT", -12, 0)

    d.none = Theme.Label(d, L.ROSTER_PICK, fonts.small, Theme.color.textFaint)
    d.none:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -12)
    d.none:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.none:SetJustifyH("LEFT")
    d.none:SetSpacing(2)
end

-- ================================================================== Chat ------

function View:BuildChat(panel, fonts)
    local content = panel.content
    self.chatChannel = "GUILD"
    self.chatChips = {}
    local vorige
    self.chatHead = panel.header or content
    self.chatHeading = panel.heading
    for _, channel in ipairs({ "GUILD", "OFFICER", "DISCORD" }) do
        local chip = Widgets.Chip(panel.header or content, L["ROSTER_CHAT_" .. channel], function(pressed)
            self.chatChannel = pressed and channel or "GUILD"
            self:RefreshChat()
        end)
        if vorige then chip:SetPoint("LEFT", vorige, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", panel.heading, "RIGHT", 12, 0) end
        chip.channel = channel
        if channel == "DISCORD" then chip:SetIcon(Theme.Media("discord"), { 0.55, 0.60, 1.00, 1 }) end
        self.chatChips[#self.chatChips + 1] = chip
        vorige = chip
    end
    -- Auf- und zuklappen (05.10.2026): standardmaessig zu, die Liste wird
    -- groesser; wer lesen will, klappt auf. Gemerkt wird es.
    self.chatToggle = Widgets.Button(panel.header or content, L.ROSTER_CHAT_OPEN, function()
        self:SetChatOpen(not self.chatOpen)
    end)
    self.chatToggle:SetHeight(18)
    self.chatToggle:SetPoint("RIGHT", panel.header or content, "RIGHT", -6, 0)
    self.chatState = Theme.Label(panel.header or content, "", fonts.small, Theme.color.textFaint)
    self.chatState:SetPoint("RIGHT", self.chatToggle, "LEFT", -8, 0)

    self.chatInput = editBox(content, 100, function(text)
        local ok, grund = GA.Modules.GuildChat:Send(text, self.chatChannel)
        if ok then self.chatInput:Load("") else GA.UI.MainFrame:Notice("info", "%s", L["ROSTER_CHAT_ERR_" .. tostring(grund)] or tostring(grund)) end
    end)
    self.chatInput:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 0)
    self.chatSend = Widgets.Button(content, L.ROSTER_CHAT_SEND, function()
        local ok, grund = GA.Modules.GuildChat:Send(self.chatInput:GetText(), self.chatChannel)
        if ok then self.chatInput:Load("") else GA.UI.MainFrame:Notice("info", "%s", L["ROSTER_CHAT_ERR_" .. tostring(grund)] or tostring(grund)) end
    end, "primary")
    self.chatSend:SetHeight(20)
    self.chatSend:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    self.chatInput:SetPoint("RIGHT", self.chatSend, "LEFT", -6, 0)

    self.chatLines = Widgets.ScrollList(content, {
        rowHeight = 16,
        createRow = function(row)
            row.time = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.time:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.time:SetWidth(34)
            row.text = Theme.Label(row, "", fonts.small, Theme.color.text)
            row.text:SetPoint("LEFT", row, "LEFT", 42, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            -- Item-Links im Chat: an Blizzards Tooltip weiterreichen.
            pcall(row.SetHyperlinksEnabled, row, true)
            row:SetScript("OnHyperlinkClick", function(_, link, text, button)
                if type(_G.SetItemRef) == "function" then pcall(SetItemRef, link, text, button) end
            end)
        end,
        updateRow = function(row, line)
            row.time:SetText(line.ts and date("%H:%M", line.ts) or "")
            local r, g, b = Theme.ClassColor(line.class)
            -- Discord-Absender haben keine Klasse: Discords Blau
            if line.channel == "DISCORD" and (line.remote or not line.class) then r, g, b = 0.48, 0.53, 1 end
            -- Anhang, Emoji, Sticker aus Discord: wie Blizzards Fenster in Gelb dahinter
            local extra = line.extra and L["ROSTER_CHAT_SENT_" .. string.upper(line.extra)]
            row.text:SetText(string.format("%s: %s%s", Util.Colorize(line.who or "?", r, g, b), line.text or "",
                extra and ((line.text and line.text ~= "" and " " or "") .. Util.Colorize(extra, 1, 0.82, 0)) or ""))
        end,
    })
    self.chatLines:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.chatLines:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 26)
end

--- Klappt den Chat auf oder zu. Die Liste haengt mit ihrer Unterkante am
--- Chat und waechst darum von selbst mit.
function View:SetChatOpen(open)
    self.chatOpen = open and true or false
    GA.Core.Config:Set("rosterChatOpen", self.chatOpen)
    if not self.chatPanel then return end
    self.chatPanel:SetHeight(self.chatOpen and CHAT_H or CHAT_FOLDED_H)
    if self.chatPanel.inset then self.chatPanel.inset:SetShown(self.chatOpen) end
    self.chatToggle:SetLabel(self.chatOpen and L.ROSTER_CHAT_CLOSE or L.ROSTER_CHAT_OPEN)
    self:RefreshChat()
end

function View:RefreshChat()
    local GuildChat = GA.Modules.GuildChat
    if not GuildChat then return end
    if self.chatOpen == nil then
        self.chatOpen = GA.Core.Config:Get("rosterChatOpen") == true
        self.chatPanel:SetHeight(self.chatOpen and CHAT_H or CHAT_FOLDED_H)
        if self.chatPanel.inset then self.chatPanel.inset:SetShown(self.chatOpen) end
        self.chatToggle:SetLabel(self.chatOpen and L.ROSTER_CHAT_CLOSE or L.ROSTER_CHAT_OPEN)
    end
    -- Welche Reiter: Offiziere nur, wer zuhoeren darf; Discord nur mit Bruecke.
    local shown = { GUILD = true, OFFICER = Compat.CanListenOfficerChat() ~= false,
        DISCORD = type(Compat.IsDiscordBridgeEnabled) == "function" and Compat.IsDiscordBridgeEnabled() == true }
    if not shown[self.chatChannel] then self.chatChannel = "GUILD" end
    local vorige
    for _, chip in ipairs(self.chatChips) do
        chip:SetShown(shown[chip.channel])
        if shown[chip.channel] then
            chip:ClearAllPoints()
            if vorige then chip:SetPoint("LEFT", vorige, "RIGHT", 4, 0)
            else chip:SetPoint("LEFT", self.chatHeading, "RIGHT", 12, 0) end
            vorige = chip
        end
        chip:SetPressed(chip.channel == self.chatChannel)
        -- Zugeklappt keine Kanalwahl: Die Kopfzeile zeigt nur Titel, Stand
        -- und den Knopf zum Aufklappen.
        if not self.chatOpen then chip:Hide() end
    end
    GuildChat:RequestHistory()
    GuildChat:PullHistory()
    local lines = GuildChat:List(self.chatChannel)
    self.chatLines:SetData(lines)
    -- Ans Ende: Chat liest man von unten.
    if self.chatLines.Scroll then self.chatLines:Scroll(-#lines) end
    self.chatState:SetText(string.format(L.ROSTER_CHAT_STATE, #lines,
        GuildChat:HasHistory() and L.ROSTER_CHAT_SRC_CLUB or string.format(L.ROSTER_CHAT_SRC_LIVE, GuildChat.LIMIT)))
    local darf = shown[self.chatChannel] and (self.chatChannel ~= "OFFICER" or Compat.CanViewOfficerNote() ~= false)
    self.chatInput:SetShown(darf)
    self.chatSend:SetShown(darf)
    -- Was hier offen ist, ist gelesen: die Lesemarke im Spiel nachziehen.
    -- Zugeklappt hat niemand gelesen — dann bleibt die Marke stehen.
    if self.chatOpen and GuildChat.MarkRead then GuildChat:MarkRead(self.chatChannel) end
end

-- ================================================================== Aktionen --

--- Das Menue an der Maus fuer ein Mitglied: Fluestern, Einladen. Nur fuer
--- Mitglieder, die online sind, und nicht fuer sich selbst.
function View:ShowMemberMenu(member)
    if not member or not member.online then return end
    local me = Compat.GetPlayerIdentity().name
    if me and Util.ShortName(me) == Util.ShortName(member.name) then return end
    -- DER NAME OHNE REALM (Bild vom 05.10.2026): "Hoffi Sin-ClassicBetaPvE2"
    -- findet das Spiel auf Forever nicht ("Cannot find player"), "Hoffi Sin"
    -- schon — wie bei den Knoepfen im Detailbereich.
    local target = member.name
    Widgets.ContextMenu(member.name, {
        { text = L.QH_WHISPER, func = function() Compat.OpenWhisper(target) end },
        { text = L.QH_INVITE, func = function() GA.Modules.Guild:Invite({ target }) end },
    }, { Theme.ClassColor(member.class) })
end

function View:Selected()
    for _, member in ipairs(GA.Modules.Guild:List()) do
        if member.name == self.selectedKey then return member end
    end
    return nil
end

--- Rang aendern geschieht NICHT hier: Der Klick auf den sicheren Knopf
--- fuehrt "/gpromote Name" bzw. "/gdemote Name" aus, gesetzt in
--- RefreshDetail. Hier gibt es nichts zu tun, und das ist der Punkt —
--- aus Addon-Code wird der Aufruf geblockt (gemessen 28.09.2026).

function View:SaveNote(text)
    local member = self:Selected()
    if not member then return end
    local ok, grund = GA.Modules.GuildNotes:Set(member.guid, member.name, text)
    if not ok then
        GA.UI.MainFrame:Notice("info", "%s", grund == "noright" and L.ROSTER_NOTE_NORIGHT or L.ROSTER_NOTE_NOKEY)
    end
    self:Refresh()
end

-- ============================================================= Einladen -----
--
-- Ein kleines Fenster: Name eintippen, Knopf druecken. Der Knopf ist ein
-- sicherer Knopf des Spiels mit "/ginvite Name" — GuildInvite aus Addon-
-- Code ist auf dieser Linie so geschuetzt wie GuildPromote (gemessen
-- 28.09.2026), und ein sicherer Knopf laesst sich nicht per Enter
-- druecken; das sagt der Hinweis im Fenster.

function View:ShowInvite(prefill)
    local frame = self.inviteFrame
    if not frame then
        local fonts = Theme.Fonts()
        frame = CreateFrame("Frame", "GuildArmoryInviteDialog", UIParent)
        frame:SetWidth(380)
        frame:SetHeight(170)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetClampedToScreen(true)
        Theme.Fill(frame, Theme.color.windowBg)
        Theme.DoubleFrame(frame)

        local title = Theme.Label(frame, string.upper(L.ROSTER_INVITE), fonts.title, Theme.color.heading)
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
        Widgets.CloseX(frame)

        local hint = Theme.Label(frame, L.ROSTER_INVITE_HINT, fonts.small, Theme.color.textDim)
        hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
        hint:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        hint:SetJustifyH("LEFT")

        local caption = Theme.Label(frame, L.ROSTER_INVITE_NAME, fonts.small, Theme.color.textDim)
        caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -82)

        frame.edit = editBox(frame, 220, nil)
        frame.edit:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 6, -3)
        frame.edit:SetScript("OnTextChanged", function() View:UpdateInvite() end)
        frame.edit:SetScript("OnEscapePressed", function() frame:Hide() end)

        frame.status = Theme.Label(frame, "", fonts.small, Theme.color.jade)
        frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 20)
        frame.status:SetPoint("RIGHT", frame, "RIGHT", -170, 0)
        frame.status:SetJustifyH("LEFT")
        frame.status:SetWordWrap(false)

        local cancel = Widgets.Button(frame, L.BTN_CANCEL, function() frame:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)

        local send = Widgets.SecureMacroButton(frame, L.ROSTER_INVITE_SEND, "primary")
        if send then
            send.onAfter = function()
                local name = trim(frame.edit:GetText())
                frame.status:SetText(string.format(L.ROSTER_INVITE_SENT, name))
                frame.edit:SetText("")
                Compat.After(1, function() Compat.RequestGuildRoster() end)
            end
            frame.secure = true
        else
            send = Widgets.Button(frame, L.ROSTER_INVITE_SEND, function()
                GA.UI.MainFrame:Notice("info", "%s", L.ROSTER_SECURE_NONE)
            end, "primary")
        end
        send:SetHeight(22)
        send:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -6, 0)
        frame.send = send

        frame:Hide()
        if type(_G.UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildArmoryInviteDialog") end
        -- Der sichere Knopf macht das Fenster im Kampf unschliessbar; also
        -- schliesst das Spiel es dort selbst, wie das Hauptfenster (MainFrame).
        if type(_G.RegisterStateDriver) == "function" then
            pcall(RegisterStateDriver, frame, "visibility", "[combat]hide")
        end
        self.inviteFrame = frame
    end
    frame.status:SetText("")
    frame.edit:SetText(prefill or "")
    frame:Show()
    frame.edit:SetFocus()
    self:UpdateInvite()
end

--- Das Makro folgt dem Namen im Feld — VOR dem Klick, nie im Kampf.
function View:UpdateInvite()
    local frame = self.inviteFrame
    if not frame or not frame.secure then return end
    local name = trim(frame.edit:GetText())
    local darf = Compat.CanGuildInvite()
    local combat = Compat.InCombat()
    frame.send:SetMacro(name ~= "" and ("/ginvite " .. name) or "")
    frame.send:SetEnabledState(name ~= "" and darf ~= false and not combat,
        name == "" and L.ROSTER_INVITE_EMPTY or (darf == false and L.ROSTER_NO_RIGHT or L.ROSTER_INVITE_COMBAT))
end

--- Die Nachricht des Tages: die des Addons (Communication/GuildNotes),
--- nicht die des Spiels — GuildSetMOTD ist hier geblockt (28.09.2026).
function View:EditMOTD()
    local GuildNotes = GA.Modules.GuildNotes
    if not GuildNotes:CanEditMOTD() then
        GA.UI.MainFrame:Notice("info", "%s", L.ROSTER_MOTD_LOCKED)
        return
    end
    Widgets.InputDialog(L.ROSTER_MOTD, L.ROSTER_MOTD_HINT, function(text)
        local ok, grund = GuildNotes:SetMOTD(text)
        if ok then View:Refresh() end
        return ok, ok and nil or (grund == "noright" and L.ROSTER_MOTD_LOCKED or tostring(grund))
    end)
end

--- DIE GILDENINFO DES ADDONS (01.10.2026): SetGuildInfoText kommt aus einem
--- Addon nicht durch, also die eigene aus GuildNotes. Wer sie im Spiel
--- aendern duerfte, bekommt den Text zum Bearbeiten; alle anderen lesen.
function View:EditGuildInfo()
    -- Als Global war GuildNotes hier nil: Der Klick warf und tat nichts
    -- (gesehen 02.10.2026).
    local GuildNotes = GA.Modules.GuildNotes
    local text, entry = GuildNotes:GetInfo()
    local by = entry and entry.by and entry.ts
        and string.format(L.ROSTER_NOTE_BY, entry.by, Util.TimeAgo(entry.ts)) or nil
    if not GuildNotes:CanEditInfo() then
        local body = text or L.ROSTER_INFO_NONE
        if by then body = body .. "\n\n" .. by end
        Widgets.CopyDialog(L.ROSTER_INFO, body)
        return
    end
    Widgets.InputDialog(L.ROSTER_INFO, by and (L.ROSTER_INFO_HINT .. "  " .. by) or L.ROSTER_INFO_HINT,
        function(neu)
            local ok, grund = GuildNotes:SetInfo(neu)
            return ok, ok and nil or (grund == "noright" and L.ROSTER_INFO_LOCKED or tostring(grund))
        end, text or "")
end

-- ================================================================== Refresh ---

function View:Filtered(list)
    local search = string.lower(self.search and self.search:GetValue() or "")
    local out = {}
    for _, member in ipairs(list) do
        local keep = true
        if self.filter == "ONLINE" then keep = member.online == true
        elseif self.filter == "OFFICERS" then keep = (member.rankIndex or 99) <= 1
        elseif self.filter == "NONOTE" then keep = GA.Modules.GuildNotes:Get(GA.Modules.GuildNotes.Key(member.guid, member.name)) == nil end
        if keep and search ~= "" then
            local nick = member.guid and GA.Modules.Notes:GetNickname(member.guid) or ""
            local note = GA.Modules.GuildNotes:Get(GA.Modules.GuildNotes.Key(member.guid, member.name)) or ""
            local heu = string.lower(table.concat({ member.name or "", note, member.zone or "", nick }, " "))
            keep = string.find(heu, search, 1, true) ~= nil
        end
        if keep then out[#out + 1] = member end
    end
    return out
end

function View:RefreshDetail(member)
    local d = self.detail
    local widgets = { d.crest, d.name, d.meta, d.since, d.rankHead, d.promote, d.rankNow, d.demote, d.rankHint,
        d.notesHead, d.noteCaption, d.noteBox, d.noteMeta,
        d.historyHead, d.whisper, d.invite, d.gear }
    for _, line in ipairs(d.history) do widgets[#widgets + 1] = line end
    if not member then
        -- Sichere Knoepfe im Kampf: Show/Hide ist dort geblockt, und der
        -- Traeger ist ohnehin weg — pcall, damit der Rest der Seite laeuft.
        for _, w in ipairs(widgets) do pcall(w.Hide, w) end
        d.none:Show()
        return
    end
    d.none:Hide()
    for _, w in ipairs(widgets) do pcall(w.Show, w) end

    local r, g, b = Theme.ClassColor(member.class)
    if member.class and Theme.SetClassPortrait(d.crest, member.class) then d.crest:Show() else d.crest:Hide() end
    d.name:SetText(member.name)
    d.name:SetTextColor(r, g, b)
    local teile = { member.className or member.class or "?" }
    if member.level then teile[#teile + 1] = string.format(L.LEVEL_FMT, tostring(member.level)) end
    teile[#teile + 1] = member.online and Util.Colorize(L.ROSTER_ONLINE, Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3]) or L.ROSTER_OFFLINE
    if member.online and member.zone then teile[#teile + 1] = member.zone end
    d.meta:SetText(table.concat(teile, " · "))

    local ts, gesehen = GA.Modules.GuildHistory:KnownSince(member.name)
    local character = member.guid and GA.Core.Database.account.characters[member.guid]
    local ilvl = character and character.itemLevel and character.itemLevel.value
    local seit = {}
    if gesehen and ts then seit[#seit + 1] = string.format(L.CHAR_SINCE, Util.TimeAgo(ts)) end
    if ilvl then seit[#seit + 1] = L.COL_ILVL .. " " .. ilvl end
    d.since:SetText(table.concat(seit, " · "))

    -- Rang: die Namen der Nachbarstufen, wenn der Client sie hergibt.
    local ranks = Compat.GetGuildRanks()
    local index = member.rankIndex
    local farbe = rankColor(index)
    d.rankText:SetText(string.upper(member.rankName or "?"))
    d.rankText:SetTextColor(farbe[1], farbe[2], farbe[3])
    for _, line in ipairs(d.rankLines) do Theme.Paint(line, farbe) end
    Theme.Paint(d.rankFill, { farbe[1], farbe[2], farbe[3], 0.12 })

    local hoeher = ranks and index and index > 0 and ranks[index] or nil
    local tiefer = ranks and index and ranks[index + 2] or nil
    d.rankHint:SetText(string.format(L.ROSTER_RANK_HINT, hoeher or "—", tiefer or "—"))
    d.promote.hint = hoeher and string.format(L.ROSTER_PROMOTE_TO, hoeher) or nil
    d.demote.hint = tiefer and string.format(L.ROSTER_DEMOTE_TO, tiefer) or nil
    -- Die Makros VOR dem Klick setzen — im Klick ist der Knopf Blizzards.
    if d.secure then
        d.promote:SetMacro("/gpromote " .. member.name)
        d.demote:SetMacro("/gdemote " .. member.name)
    end
    local darfHoch = Compat.CanGuildPromote()
    local darfRunter = Compat.CanGuildDemote()
    local eigenRang = GA.Core.Comm and GA.Core.Comm:IsSelf(member.name)
    d.promote:SetEnabledState(d.secure and darfHoch == true and index ~= nil and index > 1 and not eigenRang,
        eigenRang and L.ROSTER_SELF or (not d.secure and L.ROSTER_SECURE_NONE)
        or (darfHoch == false and L.ROSTER_NO_RIGHT or (darfHoch == nil and L.ROSTER_UNMEASURED or L.ROSTER_TOP)))
    d.demote:SetEnabledState(d.secure and darfRunter == true and tiefer ~= nil and not eigenRang,
        eigenRang and L.ROSTER_SELF or (not d.secure and L.ROSTER_SECURE_NONE)
        or (darfRunter == false and L.ROSTER_NO_RIGHT or (darfRunter == nil and L.ROSTER_UNMEASURED or L.ROSTER_BOTTOM)))

    -- Notizen: laden, ohne dass das Laden speichert.
    -- Die geteilte Notiz: Text, und wer sie wann schrieb.
    local GuildNotes = GA.Modules.GuildNotes
    local text, entry = GuildNotes:Get(GuildNotes.Key(member.guid, member.name))
    d.noteBox:Load(text or "")
    d.noteBox:SetEnabled(GuildNotes:CanEdit())
    d.noteCaption:SetText(GuildNotes:CanEdit() and L.ROSTER_NOTE_SHARED or (L.ROSTER_NOTE_SHARED .. "  |cff6f6753" .. L.ROSTER_NOTE_NORIGHT .. "|r"))
    d.noteMeta:SetText(entry and entry.by and entry.ts and string.format(L.ROSTER_NOTE_BY, entry.by, Util.TimeAgo(entry.ts)) or "")

    local history = GA.Modules.GuildHistory:List({ name = member.name })
    for i, line in ipairs(d.history) do
        local entry = history[i]
        if entry then
            local text = L["HIST_" .. tostring(entry.kind)] or entry.kind
            if entry.rank and (entry.kind == "PROMOTED" or entry.kind == "DEMOTED") then
                text = text .. " " .. entry.rank
            end
            line:SetText(string.format("%s  |cff6f6753%s|r", text, Util.TimeAgo(entry.ts)))
            line:Show()
        else
            line:Hide()
        end
    end
    if #history == 0 then
        d.history[1]:SetText(L.ROSTER_HISTORY_NONE)
        d.history[1]:Show()
    end

    local eigen = GA.Core.Comm and GA.Core.Comm:IsSelf(member.name)
    d.invite:SetEnabledState(member.online == true and not eigen, L.ROSTER_OFFLINE)
    d.whisper:SetEnabledState(not eigen, L.ROSTER_SELF)
end

function View:OnShow()
    Compat.RequestGuildRoster()
    self:Refresh()
end

function View:Refresh()
    if not self.frame then return end
    local Guild = GA.Modules.Guild
    local list = Guild:List()

    for _, chip in ipairs(self.filterChips) do chip:SetPressed(chip.filterKey == self.filter) end

    local guildName = Compat.GetOwnGuildInfo()
    local total, online = Compat.GetNumGuildMembers()
    self.guildName:SetText(guildName or L.DASH_NOT_IN_GUILD)
    local teile = { string.format(L.DASH_MEMBERS_ONLINE, total or #list, online or 0) }
    for _, member in ipairs(list) do
        if member.rankIndex == 0 then
            teile[#teile + 1] = string.format(L.DASH_GUILD_MASTER, Theme.ColorByClass(member.name, member.class))
            break
        end
    end
    self.guildMeta:SetText(table.concat(teile, " · "))

    -- Die Nachricht des Tages beginnt rechts vom Gildennamen und seiner
    -- Zeile — nicht an fester Stelle (dort lief sie in den Gildenmeister,
    -- gesehen 28.09.2026). Hoechstens die halbe Kopfbreite; laengere
    -- Zeilen links werden abgeschnitten.
    local headWidth = self.head:GetWidth()
    if not headWidth or headWidth < 200 then headWidth = 900 end
    local breite = math.max(self.guildName:GetStringWidth() or 0, self.guildMeta:GetStringWidth() or 0)
    local links = math.min(math.max(250, 14 + breite + 24), math.floor(headWidth * 0.5))
    self.motd:SetPoint("TOPLEFT", self.head, "TOPLEFT", links, -8)
    self.guildName:SetWidth(links - 14 - 12)
    self.guildMeta:SetWidth(links - 14 - 12)

    local GuildNotes = GA.Modules.GuildNotes
    local motd, motdEntry = GuildNotes:GetMOTD()
    local kopf = string.upper(L.ROSTER_MOTD)
    if motdEntry and motdEntry.by and motdEntry.ts and motd then
        kopf = kopf .. "  |cff6f6753" .. string.format(L.ROSTER_NOTE_BY, motdEntry.by, Util.TimeAgo(motdEntry.ts)) .. "|r"
    end
    if GuildNotes:CanEditMOTD() then kopf = kopf .. "  |cff6f6753" .. L.ROSTER_MOTD_EDIT .. "|r" end
    self.motdHead:SetText(kopf)
    self.motdText:SetText(motd or L.ROSTER_MOTD_EMPTY)

    local gefiltert = self:Filtered(list)
    self.ownZone = Compat.GetZone and Compat.GetZone() or nil

    -- Zwei Gruppen mit Kopfzeile: online zuerst (nach Rang), dann offline
    -- (zuletzt gesehen zuerst). Die Kopfzeilen sind Zeilen der Liste.
    local da, weg = {}, {}
    for _, member in ipairs(gefiltert) do
        if member.online then da[#da + 1] = member else weg[#weg + 1] = member end
    end
    table.sort(weg, function(a, b)
        local ta, tb = a.lastOnlineTs or 0, b.lastOnlineTs or 0
        if ta ~= tb then return ta > tb end
        return (a.name or "") < (b.name or "")
    end)
    local zeilen = {}
    if #da > 0 then zeilen[#zeilen + 1] = { header = true, online = true, label = L.ROSTER_ONLINE, count = #da } end
    for _, m in ipairs(da) do zeilen[#zeilen + 1] = m end
    if #weg > 0 then zeilen[#zeilen + 1] = { header = true, online = false, label = L.ROSTER_OFFLINE, count = #weg } end
    for _, m in ipairs(weg) do zeilen[#zeilen + 1] = m end
    self.rows:SetData(zeilen)
    self.footer:SetText(string.format(L.ROSTER_FOOTER, #gefiltert, #list))

    -- Die Zusammenfassung in der Kopfzeile der Liste.
    local hier, offiziere = 0, 0
    for _, member in ipairs(list) do
        if member.online then
            if self.ownZone and member.zone == self.ownZone then hier = hier + 1 end
            if (member.rankIndex or 99) <= 1 then offiziere = offiziere + 1 end
        end
    end
    if self.listPanel.tag then
        self.listPanel.tag:SetText(string.format(L.ROSTER_SUMMARY, online or #da, hier, offiziere))
    end

    local selected
    for _, member in ipairs(gefiltert) do
        if member.name == self.selectedKey then selected = member break end
    end
    if not selected and gefiltert[1] then
        self.selectedKey = gefiltert[1].name
        selected = gefiltert[1]
    end
    self:RefreshDetail(selected)
    self:RefreshChat()

    GA.UI.MainFrame:SetContext(string.format(L.DASH_MEMBERS_ONLINE, total or #list, online or 0))
end

GA.UI.MainFrame:RegisterView("roster", View)

for _, event in ipairs({ "GUILD_UPDATED", "NOTES_CHANGED", "GUILD_HISTORY" }) do
    GA.Core.Callbacks:On(event, function()
        if View.frame and View.frame:IsVisible() then View:Refresh() end
    end, "RosterView")
end
GA.Core.Callbacks:On("GUILD_CHAT_HISTORY", function()
    if View.frame and View.frame:IsVisible() then View:RefreshChat() end
end, "RosterView")

GA.Core.Callbacks:On("GUILD_CHAT", function()
    if View.frame and View.frame:IsVisible() then View:RefreshChat() end
end, "RosterView")

-- ================================================================ Die J-Taste -
--
-- Wer will, dass Blizzards Gildenfenster zu diesem Verzeichnis fuehrt,
-- stellt es ein (guildKeyOpensAddon, aus bis dahin): Der Haken an
-- ToggleGuildFrame schliesst Blizzards Fenster wieder und oeffnet
-- unseres. Nicht im Kampf — dort ist das Oeffnen und Schliessen von
-- Blizzards Rahmen geschuetzt, und ein Haken, der dann wirft, macht die
-- J-Taste kaputt.
local function redirectToRoster()
    if not GA.Core.Config:Get("guildKeyOpensAddon") then return end
    if Compat.InCombat() then return end
    if View.openingBlizzard then return end
    -- SOFORT schliessen, noch im selben Takt — sonst blitzt Blizzards
    -- Fenster einen Takt lang auf (gesehen 28.09.2026). Der zweite Aufruf
    -- unten faengt, was erst danach aufgeht.
    Compat.HideBlizzardGuildFrame()
    -- ENTPRELLT. Gemessen 28.09.2026: Beide Aufruffunktionen existieren
    -- ("Gildenfenster-Aufruf=2"), und die eine ruft die andere — ein
    -- Tastendruck kaeme hier zweimal an, und das Fenster meldet sich
    -- obendrein. Der erste gewinnt, der Rest im selben Takt tut nichts.
    if View.togglePending then return end
    View.togglePending = true
    Compat.After(0, function()
        View.togglePending = nil
        Compat.HideBlizzardGuildFrame()
        local main = GA.UI.MainFrame
        if main.frame and main.frame:IsShown() and main.current == "dashboard" then return end
        main:Show()
        main:ShowView("dashboard")
    end)
end

--- Der Knopf, den die umbelegte J-Taste klickt: die Uebersicht auf, oder
--- zu, wenn sie schon offen ist — wie die Taste sich anfuehlen soll. Steht
--- das Fenster auf einer anderen Seite, wechselt J zur Uebersicht
--- (Wunsch 01.10.2026: "immer im Overview landen").
local function guildKeyButton()
    if View.keyButton then return View.keyButton end
    local button = CreateFrame("Button", "GuildArmoryGuildKeyButton", UIParent)
    button:Hide()
    button:SetScript("OnClick", function()
        local main = GA.UI.MainFrame
        if main.frame and main.frame:IsShown() and main.current == "dashboard" then
            main:Hide()
        else
            main:Show()
            main:ShowView("dashboard")
        end
    end)
    View.keyButton = button
    return button
end

--- Die Umbelegung nach der Einstellung setzen oder loesen. Im Kampf geht
--- beides nicht — dann noch einmal, sobald der Kampf vorbei ist.
function View:ApplyGuildKey()
    if GA.Core.Config:Get("guildKeyOpensAddon") then
        local button = guildKeyButton()
        local ok, weg = Compat.OverrideGuildKey(button:GetName())
        View.keyPending = (weg == "combat") or nil
        return ok, weg
    end
    local ok = Compat.ClearGuildKeyOverride()
    View.keyPending = (not ok and Compat.InCombat()) or nil
    return ok
end

-- Zwei Haken: an den Funktionen, die das Fenster oeffnen, UND am Fenster
-- selbst — gemessen 28.09.2026 fing der Funktionshaken die J-Taste nicht.
-- Blizzards Gildenmodule laden bei Bedarf; ihr Rahmen bekommt den Haken,
-- sobald er da ist.
GA.Core.Callbacks:On("ADDON_READY", function()
    View.hooked = Compat.HookGuildFrameToggle(redirectToRoster)
    View.hookedFrames = Compat.HookGuildFrameShow(redirectToRoster)
    GA.Core.Events:Register("ADDON_LOADED", function(_, name)
        if name == "Blizzard_GuildUI" or name == "Blizzard_Communities" then
            View.hookedFrames = Compat.HookGuildFrameShow(redirectToRoster)
        end
    end, "RosterView")

    -- Die Taste selbst: umbelegt, solange die Einstellung an ist. Neu
    -- gesetzt, wenn der Spieler seine Tasten aendert, und nachgeholt,
    -- wenn der Kampf es eben verboten hat.
    View:ApplyGuildKey()
    GA.Core.Events:Register("UPDATE_BINDINGS", function() View:ApplyGuildKey() end, "RosterView")
    GA.Core.Events:Register("PLAYER_REGEN_ENABLED", function()
        if View.keyPending then View:ApplyGuildKey() end
    end, "RosterView")

end, "RosterView")

-- Eine Notiz kam aus der Gilde: Liste und Detail zeigen sie.
GA.Core.Callbacks:On("GUILD_NOTES", function()
    if View.frame and View.frame:IsVisible() then View:Refresh() end
end, "RosterView")

GA.Core.Callbacks:On("CONFIG_CHANGED", function(key)
    if key == "guildKeyOpensAddon" then View:ApplyGuildKey() end
end, "RosterView")
