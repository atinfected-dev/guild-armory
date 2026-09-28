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

    DREI NOTIZEN, und der Unterschied steht dran: die oeffentliche und die
    Offiziersnotiz gehen durch die Gilde (Blizzards Felder), die dritte
    bleibt auf diesem Client (Armory/Notes.lua). Eine Oberflaeche, die das
    gleich aussehen laesst, schickt irgendwann etwas Privates an alle.
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
local CHAT_H = 180
local FILTERS = { "ALL", "ONLINE", "OFFICERS", "NONOTE" }

--- Farbe je Rangstufe: die ersten drei tragen Farbe, der Rest ist grau.
local RANK_COLOR = { [0] = "gold", [1] = "warn", [2] = "jade" }
local function rankColor(rankIndex)
    return Theme.color[RANK_COLOR[rankIndex or 99] or "textDim"]
end

local COLUMN_GAP, COLUMN_X0 = 6, 8
local function columns()
    return {
        { key = "crest", label = "",               width = 16 },
        { key = "name",  label = L.COL_NAME,       width = 128 },
        { key = "level", label = L.COL_LEVEL,      width = 28, justify = "RIGHT" },
        { key = "zone",  label = L.ROSTER_COL_ZONE, width = 96 },
        { key = "rank",  label = L.ROSTER_COL_RANK, width = 84 },
        { key = "note",  label = L.ROSTER_COL_NOTE, width = 100 },
        { key = "last",  label = L.ROSTER_COL_LAST, width = 62, justify = "RIGHT" },
    }
end

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
        local weg = Compat.OpenBlizzardGuildFrame()
        if not weg then GA.Core.Debug:Info("%s", L.ROSTER_BLIZZARD_NONE) end
    end)
    self.blizzardButton:SetPoint("RIGHT", head, "RIGHT", -12, 0)

    self.infoButton = Widgets.Button(head, L.ROSTER_INFO, function() self:EditGuildInfo() end)
    self.infoButton:SetPoint("RIGHT", self.blizzardButton, "LEFT", -6, 0)

    -- Die Nachricht des Tages: ein Knopf, weil Klick bearbeitet.
    self.motd = CreateFrame("Button", nil, head)
    self.motd:SetPoint("TOPLEFT", head, "TOPLEFT", 250, -8)
    self.motd:SetPoint("BOTTOMRIGHT", self.infoButton, "BOTTOMLEFT", -14, 0)
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
    local list = Widgets.Panel(frame, L.ROSTER_TITLE)
    list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    list:SetPoint("RIGHT", detail, "LEFT", -gap, 0)
    list:SetPoint("BOTTOM", chat, "TOP", 0, gap)
    self.listPanel = list

    self.rows = Widgets.ScrollList(list.content, {
        rowHeight = 24,
        columns = columns(),
        createRow = function(row) self:BuildRow(row) end,
        updateRow = function(row, member) self:UpdateRow(row, member) end,
        onClickRow = function(member)
            self.selectedKey = member.name
            self:Refresh()
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
    row.crest:SetWidth(14) row.crest:SetHeight(14)
    row.crest:SetPoint("LEFT", row, "LEFT", x.crest, 0)

    row.name = Theme.Label(row, "", fonts.row, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", x.name, 0)
    row.name:SetWidth(w.name)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.level = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.level:SetPoint("LEFT", row, "LEFT", x.level, 0)
    row.level:SetWidth(w.level)
    row.level:SetJustifyH("RIGHT")

    row.zone = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.zone:SetPoint("LEFT", row, "LEFT", x.zone, 0)
    row.zone:SetWidth(w.zone)
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)

    row.rank = CreateFrame("Frame", nil, row)
    row.rank:SetHeight(15)
    row.rank:SetPoint("LEFT", row, "LEFT", x.rank, 0)
    row.rankLines = Theme.Outline(row.rank, Theme.color.border)
    row.rankText = Theme.Label(row.rank, "", fonts.small, Theme.color.textDim)
    row.rankText:SetPoint("CENTER", row.rank, "CENTER", 0, 0)

    row.note = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.note:SetPoint("LEFT", row, "LEFT", x.note, 0)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)

    row.last = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.last:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.last:SetWidth(w.last)
    row.last:SetJustifyH("RIGHT")
    row.note:SetPoint("RIGHT", row.last, "LEFT", -6, 0)
end

function View:UpdateRow(row, member)
    local selected = member.name == self.selectedKey
    if selected then
        row.edge:Show()
        Theme.Paint(row.background, Theme.color.rowHover)
    else
        row.edge:Hide()
    end

    local r, g, b = Util.ClassColor(member.class)
    if member.class and Theme.SetClassPortrait(row.crest, member.class) then row.crest:Show() else row.crest:Hide() end

    local nick = member.guid and GA.Modules.Notes:GetNickname(member.guid)
    row.name:SetText(member.name .. (nick and nick ~= "" and (" |cff6f6753„" .. nick .. "“|r") or ""))
    row.name:SetTextColor(r, g, b)
    row.level:SetText(member.level and tostring(member.level) or "")
    row.zone:SetText(member.online and (member.zone or "") or "")

    local farbe = rankColor(member.rankIndex)
    row.rankText:SetText(string.upper(member.rankName or "?"))
    row.rankText:SetTextColor(farbe[1], farbe[2], farbe[3])
    for _, line in ipairs(row.rankLines) do Theme.Paint(line, farbe) end
    row.rank:SetWidth(math.min(84, row.rankText:GetStringWidth() + 12))

    row.note:SetText(member.publicNote or "")

    -- Zuletzt gesehen: online jetzt, sonst das Roster, sonst der Strich.
    if member.online then
        row.last:SetText(L.ROSTER_ONLINE)
        row.last:SetTextColor(Theme.color.jade[1], Theme.color.jade[2], Theme.color.jade[3])
    else
        local weg = member.lastOnlineTs and Util.TimeAgo(member.lastOnlineTs)
        if not weg then
            local index = Compat.FindGuildMemberIndex(member.name)
            local sekunden = index and Compat.GetGuildMemberLastOnline(index)
            weg = sekunden and Util.TimeAgo(Util.Now() - sekunden) or nil
        end
        row.last:SetText(weg or "—")
        row.last:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
    end

    -- Offline gedaempft: Die Zeile bleibt lesbar, aber sie tritt zurueck.
    local alpha = member.online and 1 or 0.6
    row.name:SetAlpha(alpha) row.crest:SetAlpha(alpha) row.zone:SetAlpha(alpha)
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

    d.promote = Widgets.Button(d, "", function() self:ChangeRank(-1) end)
    d.promote:SetHeight(20)
    d.promote:SetPoint("TOPLEFT", d.rankHead, "BOTTOMLEFT", 0, -4)
    d.promote:SetWidth(72)

    d.rankNow = CreateFrame("Frame", nil, d)
    d.rankNow:SetHeight(20)
    d.rankNow:SetPoint("LEFT", d.promote, "RIGHT", 4, 0)
    d.rankLines = Theme.Outline(d.rankNow, Theme.color.border)
    d.rankText = Theme.Label(d.rankNow, "", fonts.small, Theme.color.text)
    d.rankText:SetPoint("CENTER", d.rankNow, "CENTER", 0, 0)

    d.demote = Widgets.Button(d, "", function() self:ChangeRank(1) end)
    d.demote:SetHeight(20)
    d.demote:SetPoint("LEFT", d.rankNow, "RIGHT", 4, 0)
    d.demote:SetWidth(72)

    d.rankHint = Theme.Label(d, L.ROSTER_RANK_HINT, fonts.small, Theme.color.textFaint)
    d.rankHint:SetPoint("TOPLEFT", d.promote, "BOTTOMLEFT", 0, -3)
    d.rankHint:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.rankHint:SetJustifyH("LEFT")
    d.rankHint:SetWordWrap(false)

    -- Notizen: drei Felder, drei Reichweiten.
    d.notesHead = Theme.Label(d, string.upper(L.ROSTER_NOTES), fonts.heading, Theme.color.goldDim)
    d.notesHead:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -128)

    local function feld(y, label, onSave)
        local caption = Theme.Label(d, label, fonts.small, Theme.color.textDim)
        caption:SetPoint("TOPLEFT", d, "TOPLEFT", 12, y)
        local box = editBox(d, DETAIL_W - 30, onSave)
        box:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 6, -2)
        return box, caption
    end
    d.publicBox, d.publicCaption = feld(-144, L.ROSTER_NOTE_PUBLIC, function(text) self:SaveNote("public", text) end)
    d.officerBox, d.officerCaption = feld(-184, L.ROSTER_NOTE_OFFICER, function(text) self:SaveNote("officer", text) end)
    d.ownBox, d.ownCaption = feld(-224, L.ROSTER_NOTE_OWN, function(text) self:SaveNote("own", text) end)

    -- Verlauf: die letzten drei Eintraege der Rosterhistorie.
    d.historyHead = Theme.Label(d, string.upper(L.ROSTER_HISTORY), fonts.heading, Theme.color.goldDim)
    d.historyHead:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -270)
    d.history = {}
    for index = 1, 3 do
        local line = Theme.Label(d, "", fonts.small, Theme.color.textDim)
        line:SetPoint("TOPLEFT", d.historyHead, "BOTTOMLEFT", 0, -(4 + (index - 1) * 14))
        line:SetPoint("RIGHT", d, "RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        d.history[index] = line
    end

    -- Handlungen unten.
    d.remove = Widgets.Button(d, L.ROSTER_REMOVE, function() self:RemoveMember() end)
    d.remove:SetHeight(22)
    d.remove:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 10)
    d.remove:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -12, 10)

    d.whisper = Widgets.Button(d, L.QH_WHISPER, function()
        local member = self:Selected()
        if member then Compat.OpenWhisper(member.name) end
    end)
    d.whisper:SetHeight(22)
    d.whisper:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 38)
    d.whisper:SetWidth(72)

    d.invite = Widgets.Button(d, L.QH_INVITE, function()
        local member = self:Selected()
        if member then Compat.InviteUnit(member.name) end
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
    for _, channel in ipairs({ "GUILD", "OFFICER" }) do
        local chip = Widgets.Chip(panel.header or content, L["ROSTER_CHAT_" .. channel], function(pressed)
            self.chatChannel = pressed and channel or "GUILD"
            self:RefreshChat()
        end)
        if vorige then chip:SetPoint("LEFT", vorige, "RIGHT", 4, 0)
        else chip:SetPoint("LEFT", panel.heading, "RIGHT", 12, 0) end
        chip.channel = channel
        self.chatChips[#self.chatChips + 1] = chip
        vorige = chip
    end
    self.chatState = Theme.Label(panel.header or content, "", fonts.small, Theme.color.textFaint)
    self.chatState:SetPoint("RIGHT", panel.header or content, "RIGHT", -8, 0)

    self.chatInput = editBox(content, 100, function(text)
        local ok, grund = GA.Modules.GuildChat:Send(text, self.chatChannel)
        if ok then self.chatInput:Load("") else GA.Core.Debug:Info("%s", L["ROSTER_CHAT_ERR_" .. tostring(grund)] or tostring(grund)) end
    end)
    self.chatInput:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 0)
    self.chatSend = Widgets.Button(content, L.ROSTER_CHAT_SEND, function()
        local ok, grund = GA.Modules.GuildChat:Send(self.chatInput:GetText(), self.chatChannel)
        if ok then self.chatInput:Load("") else GA.Core.Debug:Info("%s", L["ROSTER_CHAT_ERR_" .. tostring(grund)] or tostring(grund)) end
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
            local r, g, b = Util.ClassColor(line.class)
            row.text:SetText(string.format("%s: %s", Util.Colorize(line.who or "?", r, g, b), line.text or ""))
        end,
    })
    self.chatLines:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.chatLines:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 26)
end

function View:RefreshChat()
    local GuildChat = GA.Modules.GuildChat
    if not GuildChat then return end
    for _, chip in ipairs(self.chatChips) do chip:SetPressed(chip.channel == self.chatChannel) end
    local lines = GuildChat:List(self.chatChannel)
    self.chatLines:SetData(lines)
    -- Ans Ende: Chat liest man von unten.
    if self.chatLines.Scroll then self.chatLines:Scroll(-#lines) end
    self.chatState:SetText(string.format(L.ROSTER_CHAT_STATE, #lines))
    local darf = self.chatChannel ~= "OFFICER" or Compat.CanViewOfficerNote() ~= false
    self.chatInput:SetShown(darf)
    self.chatSend:SetShown(darf)
end

-- ================================================================== Aktionen --

function View:Selected()
    for _, member in ipairs(GA.Modules.Guild:List()) do
        if member.name == self.selectedKey then return member end
    end
    return nil
end

--- Rang aendern: -1 = hoch, +1 = runter. Der Server prueft die Rechte;
--- die Knoepfe fragen sie vorher, damit niemand ins Leere drueckt.
function View:ChangeRank(richtung)
    local member = self:Selected()
    if not member then return end
    local ok, weg
    if richtung < 0 then ok, weg = Compat.GuildPromote(member.name)
    else ok, weg = Compat.GuildDemote(member.name) end
    GA.Core.Debug:Info(ok and L.ROSTER_RANK_SENT or L.ROSTER_RANK_FAILED, member.name, tostring(weg))
    Compat.RequestGuildRoster()
end

function View:SaveNote(kind, text)
    local member = self:Selected()
    if not member then return end
    if kind == "own" then
        if member.guid then GA.Modules.Notes:SetNote(member.guid, text) end
        return
    end
    local index = Compat.FindGuildMemberIndex(member.name)
    local ok, weg
    if kind == "public" then ok, weg = Compat.SetGuildPublicNote(index, text)
    else ok, weg = Compat.SetGuildOfficerNote(index, text) end
    GA.Core.Debug:Info(ok and L.ROSTER_NOTE_SAVED or L.ROSTER_NOTE_FAILED, member.name, tostring(weg))
    Compat.RequestGuildRoster()
end

--- Entfernen: zwei Druecke, wie ueberall, wo etwas nicht rueckgaengig ist.
function View:RemoveMember()
    local member = self:Selected()
    if not member then return end
    if self.removePending ~= member.name then
        self.removePending = member.name
        self.detail.remove:SetLabel(string.format(L.ROSTER_REMOVE_CONFIRM, member.name))
        Compat.After(10, function()
            if View.removePending == member.name then
                View.removePending = nil
                View.detail.remove:SetLabel(L.ROSTER_REMOVE)
            end
        end)
        return
    end
    self.removePending = nil
    self.detail.remove:SetLabel(L.ROSTER_REMOVE)
    local ok, weg = Compat.GuildUninvite(member.name)
    GA.Core.Debug:Info(ok and L.ROSTER_REMOVED or L.ROSTER_REMOVE_FAILED, member.name, tostring(weg))
    Compat.RequestGuildRoster()
end

function View:EditMOTD()
    if Compat.CanEditMOTD() ~= true then
        GA.Core.Debug:Info("%s", L.ROSTER_MOTD_LOCKED)
        return
    end
    Widgets.InputDialog(L.ROSTER_MOTD, L.ROSTER_MOTD_HINT, function(text)
        local ok, weg = Compat.SetGuildMOTD(text)
        if ok then Compat.After(1, function() View:Refresh() end) end
        return ok, ok and nil or tostring(weg)
    end)
end

function View:EditGuildInfo()
    local text = Compat.GetGuildInfoText()
    if Compat.CanEditGuildInfo() ~= true then
        -- Nur lesen: als Bericht, den man kopieren kann.
        Widgets.CopyDialog(L.ROSTER_INFO, text or L.ROSTER_INFO_NONE)
        return
    end
    Widgets.InputDialog(L.ROSTER_INFO, (text and text ~= "" and (text .. "\n\n") or "") .. L.ROSTER_INFO_HINT,
        function(neu)
            local ok, weg = Compat.SetGuildInfoText(neu)
            return ok, ok and nil or tostring(weg)
        end)
end

-- ================================================================== Refresh ---

function View:Filtered(list)
    local search = string.lower(self.search and self.search:GetValue() or "")
    local out = {}
    for _, member in ipairs(list) do
        local keep = true
        if self.filter == "ONLINE" then keep = member.online == true
        elseif self.filter == "OFFICERS" then keep = (member.rankIndex or 99) <= 1
        elseif self.filter == "NONOTE" then keep = not member.publicNote or member.publicNote == "" end
        if keep and search ~= "" then
            local nick = member.guid and GA.Modules.Notes:GetNickname(member.guid) or ""
            local heu = string.lower(table.concat({ member.name or "", member.publicNote or "", member.zone or "", nick }, " "))
            keep = string.find(heu, search, 1, true) ~= nil
        end
        if keep then out[#out + 1] = member end
    end
    return out
end

function View:RefreshDetail(member)
    local d = self.detail
    local widgets = { d.crest, d.name, d.meta, d.since, d.rankHead, d.promote, d.rankNow, d.demote, d.rankHint,
        d.notesHead, d.publicBox, d.publicCaption, d.officerBox, d.officerCaption, d.ownBox, d.ownCaption,
        d.historyHead, d.remove, d.whisper, d.invite, d.gear }
    for _, line in ipairs(d.history) do widgets[#widgets + 1] = line end
    if not member then
        for _, w in ipairs(widgets) do w:Hide() end
        d.none:Show()
        return
    end
    d.none:Hide()
    for _, w in ipairs(widgets) do w:Show() end

    local r, g, b = Util.ClassColor(member.class)
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
    d.rankNow:SetWidth(math.min(90, d.rankText:GetStringWidth() + 14))

    local hoeher = ranks and index and index > 0 and ranks[index] or nil
    local tiefer = ranks and index and ranks[index + 2] or nil
    d.promote:SetLabel("▲ " .. (hoeher or ""))
    d.promote:SetWidth(72)
    d.demote:SetLabel("▼ " .. (tiefer or ""))
    d.demote:SetWidth(72)
    local darfHoch = Compat.CanGuildPromote()
    local darfRunter = Compat.CanGuildDemote()
    d.promote:SetEnabledState(darfHoch == true and index ~= nil and index > 1,
        darfHoch == false and L.ROSTER_NO_RIGHT or (darfHoch == nil and L.ROSTER_UNMEASURED or L.ROSTER_TOP))
    d.demote:SetEnabledState(darfRunter == true and tiefer ~= nil,
        darfRunter == false and L.ROSTER_NO_RIGHT or (darfRunter == nil and L.ROSTER_UNMEASURED or L.ROSTER_BOTTOM))

    -- Notizen: laden, ohne dass das Laden speichert.
    d.publicBox:Load(member.publicNote or "")
    d.publicBox:SetEnabled(Compat.CanEditPublicNote() == true)
    local officer = Compat.CanViewOfficerNote()
    d.officerBox:Load(member.officerNote or "")
    d.officerBox:SetEnabled(Compat.CanEditOfficerNote() == true)
    d.officerBox:SetShown(officer ~= false)
    d.officerCaption:SetShown(officer ~= false)
    d.ownBox:Load(member.guid and GA.Modules.Notes:GetNote(member.guid) or "")
    d.ownBox:SetEnabled(member.guid ~= nil)

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
    local darfWeg = Compat.CanGuildRemove()
    d.remove:SetEnabledState(darfWeg == true and not eigen,
        eigen and L.ROSTER_SELF or (darfWeg == false and L.ROSTER_NO_RIGHT or L.ROSTER_UNMEASURED))
    if self.removePending ~= member.name then d.remove:SetLabel(L.ROSTER_REMOVE) end
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
            teile[#teile + 1] = string.format(L.DASH_GUILD_MASTER, Util.ColorByClass(member.name, member.class))
            break
        end
    end
    self.guildMeta:SetText(table.concat(teile, " · "))

    local motd = Compat.GetGuildMOTD()
    local darfMotd = Compat.CanEditMOTD()
    self.motdHead:SetText(string.upper(L.ROSTER_MOTD) .. (darfMotd == true and ("  |cff6f6753" .. L.ROSTER_MOTD_EDIT .. "|r") or ""))
    self.motdText:SetText(motd and motd ~= "" and motd or (motd and L.ROSTER_MOTD_EMPTY or L.ROSTER_UNMEASURED))

    local gefiltert = self:Filtered(list)
    self.rows:SetData(gefiltert)
    self.footer:SetText(string.format(L.ROSTER_FOOTER, #gefiltert, #list))

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
GA.Core.Callbacks:On("ADDON_READY", function()
    View.hooked = Compat.HookGuildFrameToggle(function()
        if not GA.Core.Config:Get("guildKeyOpensAddon") then return end
        if Compat.InCombat() then return end
        if GA.UI.MainFrame.frame and GA.UI.MainFrame.frame:IsShown()
            and GA.UI.MainFrame.current == "roster" then
            return
        end
        Compat.After(0, function()
            Compat.HideBlizzardGuildFrame()
            GA.UI.MainFrame:Show()
            GA.UI.MainFrame:ShowView("roster")
        end)
    end)
end, "RosterView")
