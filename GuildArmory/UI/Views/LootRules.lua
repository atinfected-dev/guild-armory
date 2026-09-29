--[[----------------------------------------------------------------------------
    UI/Views/LootRules — wie diese Gilde verteilt (Entwurf LR2, 29.09.2026).

    Vier nummerierte Bloecke von oben nach unten — Verteilart, Council,
    Bieten, Nebenher — und rechts eine Schiene, die sagt, was die Bloecke
    ZUSAMMEN ergeben: was heute Abend gilt, Satz fuer Satz, darunter die
    Warnungen, darunter wer hier ueberhaupt aendern darf.

    WARUM EINE EIGENE SEITE UND NICHT DREI KAESTCHEN IN DEN EINSTELLUNGEN.

    Diese Schalter ergeben zusammen eine Regel. "Council aus" und "jeder
    darf abstimmen" widersprechen sich; "Soft Reserves an" ohne offene
    Runde zeigt eine leere Liste, die nie jemand fuellt. Wer sie einzeln
    verstellt, ohne die anderen zu sehen, bekommt einen Abend, den niemand
    erklaeren kann. Deshalb steht die Zusammenfassung DANEBEN, nicht
    darunter: Sie aendert sich mit jedem Klick, und man sieht es.

    Die Hoehen werden GEMESSEN (Widgets.Stack), nicht gesetzt: Eine feste
    Hoehe fuer umbrechenden Text ist eine Wette auf Sprache und
    Fensterbreite, und die ist in den Einstellungen schon einmal verloren
    gegangen.
------------------------------------------------------------------------------]]

local _, GA = ...

local LootRules = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local L = GA.L

local Config = GA.Core.Config

LootRules.titleKey = "NAV_LOOTRULES"

local RAIL_W = 250
local BLOCK_HEAD = 40


--- Die vier Verteilarten, in der Reihenfolge der Chips.
---
--- In ALLEN vieren vergibt am Ende der Plündermeister. Das ist kein
--- Zufall, sondern der Grund, warum es eine Seite und nicht vier
--- Verfahren gibt.
local MODES = {
    { key = "COUNCIL", label = "LR_MODE_COUNCIL" },
    { key = "SOFTRES", label = "LR_MODE_SOFTRES" },
    { key = "ROLL",    label = "LR_MODE_ROLL" },
    { key = "DKP",     label = "LR_MODE_DKP" },
}

--- Wer abstimmen darf, in der Reihenfolge der Chips.
local VOTERS = {
    { key = "COUNCIL",    label = "LR_VOTE_COUNCIL" },
    { key = "LOOTMASTER", label = "LR_VOTE_LOOTMASTER" },
    { key = "ALL",        label = "LR_VOTE_ALL" },
}

-- ================================================================== Helfer ----

--- Ein Block: Nummer im goldenen Kreis, Titel, Untertitel, darunter der
--- Inhalt (block.content), dessen Hoehe Relayout misst.
local function block(parent, number, title, subtitle)
    local fonts = Theme.Fonts()
    local box = Widgets.Inset(parent)
    box:SetHeight(100)

    box.badge = CreateFrame("Frame", nil, box)
    box.badge:SetSize(26, 26)
    box.badge:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    local disc = box.badge:CreateTexture(nil, "BACKGROUND")
    disc:SetAllPoints(box.badge)
    if Theme.RoundTexture() then
        disc:SetTexture(Theme.RoundTexture())
        Theme.Tint(disc, Theme.color.heading)
    else
        Theme.Paint(disc, Theme.color.heading)
    end
    box.number = Theme.Label(box.badge, tostring(number), fonts.title, Theme.color.windowBg)
    box.number:SetPoint("CENTER", box.badge, "CENTER", 0, 0)

    box.title = Theme.Label(box, title, fonts.title, Theme.color.heading)
    box.title:SetPoint("LEFT", box.badge, "RIGHT", 10, 0)
    box.subtitle = Theme.Label(box, subtitle or "", fonts.small, Theme.color.textDim)
    box.subtitle:SetPoint("LEFT", box.title, "RIGHT", 10, -1)
    box.subtitle:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    box.subtitle:SetJustifyH("LEFT")
    box.subtitle:SetWordWrap(false)

    box.content = CreateFrame("Frame", nil, box)
    box.content:SetPoint("TOPLEFT", box, "TOPLEFT", 48, -BLOCK_HEAD)
    box.content:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    box.content:SetHeight(1)
    return box
end

--- Eine Zeile mit Schalter rechts: Beschriftung links, der Schalter am
--- rechten Rand des Inhalts. Der Hinweis dazu ist eine eigene Beschriftung
--- darunter (Relayout stellt sie mit stapel:Text).
local function switchLine(parent, text, onToggle)
    local fonts = Theme.Fonts()
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(26)
    line.label = Theme.Label(line, text, fonts.body, Theme.color.text)
    line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.label:SetJustifyH("LEFT")
    line.label:SetWordWrap(false)
    line.chip = Theme.Label(line, "", fonts.small, Theme.color.textFaint)
    line.chip:SetJustifyH("RIGHT")
    line.switch = Widgets.Switch(line, onToggle)
    line.switch:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.chip:SetPoint("RIGHT", line.switch, "LEFT", -10, 0)
    line.label:SetPoint("RIGHT", line.chip, "LEFT", -8, 0)
    function line:SetChecked(on) self.switch:SetChecked(on) end
    function line:SetEnabledState(enabled, reason) self.switch:SetEnabledState(enabled, reason) end
    return line
end

--- Chips mit ihrer natuerlichen Breite nebeneinander, umbrechend, wenn
--- die Zeile voll ist. Widgets.Stack:Row verteilt gleichmaessig — bei
--- "Loot master only" neben "All" saehe das nach Tabelle aus.
local function chipRow(stapel, label, chips, abstand)
    stapel.y = stapel.y - (abstand or 0)
    local x = 0
    local rowTop = stapel.y
    local rowHeight = 0
    if label then
        stapel:Text(label, 0, 0)
        stapel.y = stapel.y - 4
        rowTop = stapel.y
    end
    for _, chip in ipairs(chips) do
        local w = chip:GetWidth() or 60
        if x > 0 and x + w > stapel.breite then
            x = 0
            rowTop = rowTop - rowHeight - 4
            rowHeight = 0
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", stapel.content, "TOPLEFT", x, rowTop)
        x = x + w + 4
        rowHeight = math.max(rowHeight, chip:GetHeight() or 17)
    end
    stapel.y = rowTop - rowHeight
end

--- Eine Reihe von Chips, von denen genau einer gedrueckt ist.
local function exclusiveChips(parent, entries, onPick)
    local chips = {}
    for _, entry in ipairs(entries) do
        local chip = Widgets.Chip(parent, entry.text, function(_, self)
            -- Ein gedrueckter Chip bleibt gedrueckt: Auswahl, kein Umschalter.
            onPick(entry.key)
        end)
        chip:SetHeight(20)
        chip.key = entry.key
        chips[#chips + 1] = chip
    end
    return chips
end

-- ================================================================== Aufbau ----

function LootRules:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    local fonts = Theme.Fonts()
    local pad = 4

    -- ------------------------------------------------------- Schiene rechts -
    local rail = Widgets.Inset(frame)
    rail:SetWidth(RAIL_W)
    rail:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.rail = rail

    self.railHead = Theme.Label(rail, string.upper(L.LR_SUMMARY), fonts.heading, Theme.color.goldDim)
    self.railHead:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -14)

    -- Die Saetze der Zusammenfassung: je einer mit goldener Kante. Ein
    -- Vorrat, weil die Zahl der Saetze von den Schaltern abhaengt.
    self.summaryLines = {}
    for index = 1, 6 do
        local line = CreateFrame("Frame", nil, rail)
        line:SetHeight(20)
        line.edge = Theme.Fill(line, Theme.color.goldMid)
        line.edge:ClearAllPoints()
        line.edge:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
        line.edge:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 0, 0)
        line.edge:SetWidth(2)
        line.text = Theme.Label(line, "", fonts.body, Theme.color.goldBright)
        line.text:SetPoint("TOPLEFT", line, "TOPLEFT", 10, -2)
        line.text:SetPoint("RIGHT", line, "RIGHT", 0, 0)
        line.text:SetJustifyH("LEFT")
        line:Hide()
        self.summaryLines[index] = line
    end

    self.warnHead = Theme.Label(rail, string.upper(L.LR_WARNINGS), fonts.heading, Theme.color.warn)
    self.warning = Theme.Label(rail, "", fonts.small, Theme.color.warn)
    self.warning:SetJustifyH("LEFT")
    self.warning:SetSpacing(2)

    -- Wer aendern darf, steht unten in der Schiene — gesperrt oder nicht,
    -- der Grund steht da. Ein ausgegrautes Fenster ohne Erklaerung sieht
    -- aus wie ein Fehler.
    self.permission = Theme.Label(rail, "", fonts.small, Theme.color.textDim)
    self.permission:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 48)
    self.permission:SetPoint("RIGHT", rail, "RIGHT", -12, 0)
    self.permission:SetJustifyH("LEFT")
    self.permission:SetSpacing(2)

    -- DER WEG ZU DEN PUNKTEN. In der Schiene und nicht beim Modus-Chip: Man
    -- oeffnet die Rangliste auch dann, wenn heute nicht mit DKP verteilt
    -- wird — etwa um einen Nachtrag zu buchen.
    self.dkpButton = Widgets.Button(rail, L.DKP_OPEN, function() GA.UI.DkpFrame:Toggle() end)
    self.dkpButton:SetHeight(22)
    self.dkpButton:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 12, 12)
    self.dkpButton:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -12, 12)

    -- ------------------------------------------------------- Spalte links ---
    self.column = Widgets.ScrollArea(frame)
    self.column:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    self.column:SetPoint("BOTTOMRIGHT", rail, "BOTTOMLEFT", -8, 0)
    local inhalt = self.column.content

    -- 1 · Verteilart
    self.modeBlock = block(inhalt, 1, L.LR_BLOCK_MODE, L.LR_BLOCK_MODE_SUB)
    self.modeBlock:SetPoint("TOPLEFT", inhalt, "TOPLEFT", 0, 0)
    self.modeBlock:SetPoint("RIGHT", inhalt, "RIGHT", -4, 0)
    local modeEntries = {}
    for _, entry in ipairs(MODES) do modeEntries[#modeEntries + 1] = { key = entry.key, text = L[entry.label] } end
    self.modeChips = exclusiveChips(self.modeBlock.content, modeEntries, function(key)
        Config:Set("lootMode", key)
        -- Die alte Einstellung mitziehen, damit ein aelterer Client in
        -- derselben Gilde nicht ploetzlich anders verteilt.
        Config:Set("councilEnabled", key == "COUNCIL")
        self:Refresh()
    end)
    self.modeHint = Theme.Label(self.modeBlock.content, "", fonts.small, Theme.color.textDim)

    -- 2 · Council
    self.councilBlock = block(inhalt, 2, L.LR_BLOCK_COUNCIL, L.LR_BLOCK_COUNCIL_SUB)
    self.councilBlock:SetPoint("TOPLEFT", self.modeBlock, "BOTTOMLEFT", 0, -8)
    self.councilBlock:SetPoint("RIGHT", inhalt, "RIGHT", -4, 0)
    self.voterLabel = Theme.Label(self.councilBlock.content, "", fonts.body, Theme.color.text)
    local voterEntries = {}
    for _, entry in ipairs(VOTERS) do voterEntries[#voterEntries + 1] = { key = entry.key, text = L[entry.label] } end
    self.voterChips = exclusiveChips(self.councilBlock.content, voterEntries, function(key)
        Config:Set("voteRole", key)
        self:Refresh()
    end)
    self.voterHint = Theme.Label(self.councilBlock.content, L.LR_VOTE_HINT, fonts.small, Theme.color.textDim)
    self.rotationLine = switchLine(self.councilBlock.content, L.LR_ROTATION, function(on)
        Config:Set("rotationEnabled", on)
        self:Refresh()
    end)
    self.rotationHint = Theme.Label(self.councilBlock.content, L.LR_ROTATION_HINT, fonts.small, Theme.color.textDim)

    -- 3 · Bieten
    self.bidBlock = block(inhalt, 3, L.LR_BLOCK_BIDDING, L.LR_BLOCK_BIDDING_SUB)
    self.bidBlock:SetPoint("TOPLEFT", self.councilBlock, "BOTTOMLEFT", 0, -8)
    self.bidBlock:SetPoint("RIGHT", inhalt, "RIGHT", -4, 0)
    self.responseLabel = Theme.Label(self.bidBlock.content, L.LR_RESPONSES, fonts.body, Theme.color.text)
    -- Ein Chip je Antwort. "Pass" ist dabei, aber nicht abwaehlbar: Wer
    -- nicht will, muss das sagen koennen — sonst bleibt nur Schweigen, und
    -- das ist von "noch nicht geantwortet" nicht zu unterscheiden.
    self.responseChips = {}
    for _, entry in ipairs(GA.Data.Schema.DefaultResponses) do
        local chip = Widgets.Chip(self.bidBlock.content, entry.label, function(pressed)
            if entry.key == "PASS" then return end
            local aktiv = Config:Get("activeResponses")
            if type(aktiv) ~= "table" then
                aktiv = {}
                for _, e in ipairs(GA.Data.Schema.DefaultResponses) do aktiv[e.key] = true end
            end
            aktiv[entry.key] = pressed or nil
            Config:Set("activeResponses", aktiv)
            self:Refresh()
        end)
        chip:SetHeight(20)
        chip.responseKey = entry.key
        self.responseChips[#self.responseChips + 1] = chip
    end
    self.responseHint = Theme.Label(self.bidBlock.content, L.LR_RESPONSES_HINT, fonts.small, Theme.color.textDim)

    -- WER UEBERHAUPT TEILNIMMT: dieselbe Frage wie "wer darf abstimmen",
    -- nur eine Ebene davor.
    self.scopeLabel = Theme.Label(self.bidBlock.content, "", fonts.body, Theme.color.text)
    self.scopeChips = exclusiveChips(self.bidBlock.content,
        { { key = "GUILD", text = L.LR_SCOPE_GUILD }, { key = "RAID", text = L.LR_SCOPE_RAID } },
        function(key) Config:Set("sessionScope", key) self:Refresh() end)
    self.scopeHint = Theme.Label(self.bidBlock.content, "", fonts.small, Theme.color.textDim)

    -- DIE GEBOTSFRIST. Feste Stufen statt eines Eingabefelds: Es gibt
    -- keinen Grund fuer 47 Sekunden, und eine Zahl, die man eintippt, ist
    -- eine, die man vertippen kann.
    self.timerLabel = Theme.Label(self.bidBlock.content, "", fonts.body, Theme.color.text)
    local timerEntries = {}
    for _, sekunden in ipairs({ 0, 60, 120, 180 }) do
        timerEntries[#timerEntries + 1] = { key = sekunden,
            text = sekunden == 0 and L.LR_TIMER_OFF or string.format(L.LR_TIMER_SECONDS, sekunden) }
    end
    self.timerChips = exclusiveChips(self.bidBlock.content, timerEntries, function(key)
        Config:Set("bidSeconds", key)
        self:Refresh()
    end)
    self.timerHint = Theme.Label(self.bidBlock.content, L.LR_TIMER_HINT, fonts.small, Theme.color.textDim)

    -- 4 · Nebenher
    self.sideBlock = block(inhalt, 4, L.LR_BLOCK_ALONGSIDE, L.LR_BLOCK_ALONGSIDE_SUB)
    self.sideBlock:SetPoint("TOPLEFT", self.bidBlock, "BOTTOMLEFT", 0, -8)
    self.sideBlock:SetPoint("RIGHT", inhalt, "RIGHT", -4, 0)
    local side = self.sideBlock.content
    self.softResLine = switchLine(side, L.LR_SOFTRES, function(on) Config:Set("softResEnabled", on) self:Refresh() end)
    self.softResHint = Theme.Label(side, L.LR_SOFTRES_HINT, fonts.small, Theme.color.textDim)
    self.plusOneLine = switchLine(side, L.LR_PLUSONE, function(on) Config:Set("plusOneEnabled", on) self:Refresh() end)
    self.plusOneHint = Theme.Label(side, L.LR_PLUSONE_HINT, fonts.small, Theme.color.textDim)
    self.autoTradeLine = switchLine(side, L.LR_AUTOTRADE, function(on) Config:Set("autoTrade", on) self:Refresh() end)
    self.autoTradeHint = Theme.Label(side, L.LR_AUTOTRADE_HINT, fonts.small, Theme.color.textDim)
    self.outbidLine = switchLine(side, L.LR_OUTBID, function(on) Config:Set("dkpOutbidWhisper", on) self:Refresh() end)
    self.outbidHint = Theme.Label(side, L.LR_OUTBID_HINT, fonts.small, Theme.color.textDim)
    self.sourceLabel = Theme.Label(side, "", fonts.body, Theme.color.text)
    self.sourceChips = exclusiveChips(side,
        { { key = "MASTER", text = L.LR_ROLLSRC_MASTER }, { key = "CHAT", text = L.LR_ROLLSRC_CHAT } },
        function(key) Config:Set("rollSource", key) self:Refresh() end)
    self.sourceHint = Theme.Label(side, "", fonts.small, Theme.color.textDim)
    self.quietLine = switchLine(side, L.LR_QUIETROLLS, function(on) Config:Set("quietRolls", on) self:Refresh() end)
    self.quietHint = Theme.Label(side, L.LR_QUIETROLLS_HINT, fonts.small, Theme.color.textDim)

    -- Neu messen, sobald die Breite steht.
    inhalt:SetScript("OnSizeChanged", function() LootRules:Relayout() end)

    self.frame = frame
    return frame
end

--- Darfst du diese Regeln aendern?
---
--- Plündermeister und Administrator. Jeder andere sieht die Seite, kann
--- aber nichts verstellen. Die Sperre ist keine Sicherheitsmassnahme —
--- die waere auf einem fremden Client wertlos. Sie sagt die Wahrheit:
--- Massgeblich sind die Regeln DESSEN, DER DIE SITZUNG FUEHRT; sie reisen
--- mit der Ankuendigung. Wer hier etwas umstellt, ohne Plündermeister zu
--- sein, aendert nur sein eigenes Bild.
--- @return boolean darf, string|nil grund
function LootRules:MayEdit()
    local identity = GA.Core.Compat.GetPlayerIdentity()
    if not identity.guid then return false, "noguid" end
    if GA.Core.Database:HasAtLeast(identity.guid, GA.const.ROLE_LOOTMASTER) then
        return true
    end
    return false, "role"
end

--- Schaltet alle Bedienelemente stumpf, wenn man nicht darf.
---
--- EINE RECHTEPRUEFUNG NIMMT WEG, SIE GIBT NICHT: Darf man, bleibt stehen,
--- was Refresh gesetzt hat (etwa der gedrueckte Chip).
function LootRules:ApplyPermission()
    local darf, grund = self:MayEdit()
    local function setze(element)
        if not element or darf then return end
        if element.SetEnabledState then element:SetEnabledState(false)
        elseif element.Disable then element:Disable() end
    end
    for _, liste in ipairs({ self.modeChips, self.voterChips, self.scopeChips,
                            self.sourceChips, self.timerChips, self.responseChips }) do
        for _, element in ipairs(liste or {}) do setze(element) end
    end
    for _, line in ipairs({ self.rotationLine, self.softResLine, self.plusOneLine,
                           self.autoTradeLine, self.outbidLine, self.quietLine }) do
        setze(line)
    end
    if darf then
        self.permission:SetText(L.LR_RAIL_HINT)
    else
        self.permission:SetText(L["LR_LOCKED_" .. tostring(grund)] or L.LR_LOCKED_role)
    end
    return darf
end

-- ================================================================== Layout ----

--- Setzt die vier Bloecke und die Schiene neu und misst dabei jede
--- Erklaerung. Laeuft mehrmals und muss das aushalten; ohne bekannte
--- Breite wird nichts gesetzt.
function LootRules:Relayout()
    if not self.modeBlock then return false end
    local function settle(box, stapel)
        box.content:SetHeight(math.max(1, stapel:Height()))
        box:SetHeight(BLOCK_HEAD + stapel:Height() + 12)
    end

    local s = Widgets.Stack(self.modeBlock.content)
    if not s then return false end
    chipRow(s, nil, self.modeChips, 0)
    s:Text(self.modeHint, 0, 6)
    settle(self.modeBlock, s)

    s = Widgets.Stack(self.councilBlock.content)
    chipRow(s, self.voterLabel, self.voterChips, 0)
    s:Text(self.voterHint, 0, 6)
    self.rotationLine:SetWidth(s.breite)
    s:Add(self.rotationLine, 0, 10)
    s:Text(self.rotationHint, 0, 2)
    settle(self.councilBlock, s)

    s = Widgets.Stack(self.bidBlock.content)
    chipRow(s, self.responseLabel, self.responseChips, 0)
    s:Text(self.responseHint, 0, 6)
    chipRow(s, self.scopeLabel, self.scopeChips, 10)
    s:Text(self.scopeHint, 0, 6)
    chipRow(s, self.timerLabel, self.timerChips, 10)
    s:Text(self.timerHint, 0, 6)
    settle(self.bidBlock, s)

    s = Widgets.Stack(self.sideBlock.content)
    for index, paar in ipairs({
        { self.softResLine, self.softResHint }, { self.plusOneLine, self.plusOneHint },
        { self.autoTradeLine, self.autoTradeHint }, { self.outbidLine, self.outbidHint } }) do
        paar[1]:SetWidth(s.breite)
        s:Add(paar[1], 0, index > 1 and 10 or 0)
        s:Text(paar[2], 0, 2)
    end
    chipRow(s, self.sourceLabel, self.sourceChips, 10)
    s:Text(self.sourceHint, 0, 6)
    self.quietLine:SetWidth(s.breite)
    s:Add(self.quietLine, 0, 10)
    s:Text(self.quietHint, 0, 2)
    settle(self.sideBlock, s)

    local total = self.modeBlock:GetHeight() + self.councilBlock:GetHeight()
        + self.bidBlock:GetHeight() + self.sideBlock:GetHeight() + 3 * 8 + 8
    self.column.content:SetHeight(math.max(1, total))
    self.column:Refresh()

    -- Die Schiene: Saetze, dann Warnungen.
    local y = -34
    local railWidth = (self.rail:GetWidth() or RAIL_W) - 26
    for _, line in ipairs(self.summaryLines) do
        if line:IsShown() then
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", self.rail, "TOPLEFT", 14, y)
            line:SetWidth(railWidth)
            line.text:SetWidth(railWidth - 10)
            local h = (line.text:GetStringHeight() or 14) + 6
            line:SetHeight(h)
            y = y - h - 6
        end
    end
    self.warnHead:ClearAllPoints()
    self.warnHead:SetPoint("TOPLEFT", self.rail, "TOPLEFT", 14, y - 8)
    self.warning:ClearAllPoints()
    self.warning:SetPoint("TOPLEFT", self.warnHead, "BOTTOMLEFT", 0, -4)
    self.warning:SetWidth(railWidth)
    return true
end

-- ================================================================== Refresh ---

--- Welche Antworten gerade freigeschaltet sind.
local function aktiveAntworten()
    local aktiv = Config:Get("activeResponses")
    if type(aktiv) ~= "table" then return nil end
    return aktiv
end

--- Die Saetze, die beschreiben, was heute Abend gilt — einer je Zeile der
--- Schiene. Aus den Schaltern ZUSAMMENGESETZT: Die Frage ist "wie
--- verteilen wir heute", nicht "welche Haekchen stehen".
function LootRules:DescribeParts()
    local mode = GA.Modules.Session:Mode()
    local wer = Config:Get("voteRole") or "COUNCIL"
    local teile = {}
    if mode == "COUNCIL" then
        teile[#teile + 1] = string.format(L.LR_SUM_COUNCIL, L["LR_VOTE_" .. wer] or wer)
    elseif mode == "SOFTRES" then
        teile[#teile + 1] = L.LR_SUM_SOFTRES_MODE
    elseif mode == "DKP" then
        teile[#teile + 1] = L.LR_SUM_DKP_MODE
    else
        teile[#teile + 1] = L.LR_SUM_ROLL_MODE
    end
    if mode == "COUNCIL" and Config:Get("softResEnabled") ~= false then
        teile[#teile + 1] = L.LR_SUM_SOFTRES
    end
    if Config:Get("plusOneEnabled") ~= false then
        teile[#teile + 1] = L.LR_SUM_PLUSONE
    end
    if Config:Get("rotationEnabled") then
        teile[#teile + 1] = string.format(L.LR_SUM_ROTATION, tonumber(Config:Get("rotationSeats")) or 2)
    end
    local bereich = Config:Get("sessionScope") == "RAID" and "RAID" or "GUILD"
    local frist = tonumber(Config:Get("bidSeconds")) or 0
    teile[#teile + 1] = string.format(L.LR_SUM_WHO_HOWLONG, L["LR_SCOPE_" .. bereich],
        frist > 0 and string.format(L.LR_TIMER_WHICH, frist) or L.LR_TIMER_WHICH_OFF)
    return teile
end

--- Derselbe Inhalt als ein Satz — fuer die Ankuendigung und den Test.
function LootRules:Describe()
    return table.concat(self:DescribeParts(), " ")
end

--- Widersprueche, die sonst erst am Raidabend auffallen.
function LootRules:Warnings()
    local out = {}
    if GA.Modules.Session:Mode() ~= "COUNCIL" and Config:Get("rotationEnabled") then
        -- Sitze zu verteilen, an denen niemand abstimmen kann, ist kein
        -- Fehler des Codes — aber es fluestert Leute an und verspricht
        -- ihnen etwas, das es nicht gibt.
        out[#out + 1] = L.LR_WARN_ROTATION_NOCOUNCIL
    end
    if GA.Modules.Session:Mode() == "COUNCIL" and Config:Get("voteRole") == "ALL" then
        out[#out + 1] = L.LR_WARN_ALL_VOTE
    end
    local aktiv = aktiveAntworten()
    if aktiv then
        local anzahl = 0
        for key, an in pairs(aktiv) do
            if an and key ~= "PASS" then anzahl = anzahl + 1 end
        end
        if anzahl == 0 then out[#out + 1] = L.LR_WARN_NO_RESPONSES end
    end
    return table.concat(out, "\n")
end

local function press(chips, field, wert)
    for _, chip in ipairs(chips) do chip:SetPressed(chip[field] == wert) end
end

function LootRules:Refresh()
    if not self.frame then return end
    local mode = GA.Modules.Session:Mode()
    local council = mode == "COUNCIL"

    press(self.modeChips, "key", mode)
    self.modeHint:SetText(L["LR_MODE_" .. mode .. "_HINT"] or "")

    local wer = Config:Get("voteRole") or "COUNCIL"
    self.voterLabel:SetText(string.format(L.LR_VOTE_WHO, L["LR_VOTE_" .. wer] or wer))
    press(self.voterChips, "key", wer)
    for _, chip in ipairs(self.voterChips) do
        -- Ohne Council gibt es keine Abstimmung: Die Chips bleiben stumpf.
        if council then chip:Enable() else chip:Disable() end
        chip:SetAlpha(council and 1 or 0.45)
    end
    self.rotationLine:SetChecked(Config:Get("rotationEnabled") and true or false)
    self.rotationLine.chip:SetText(string.format(L.LR_SEATS, tonumber(Config:Get("rotationSeats")) or 2))

    local aktiv = aktiveAntworten()
    for _, chip in ipairs(self.responseChips) do
        local an = (aktiv == nil) or (aktiv[chip.responseKey] and true or false)
        chip:SetPressed(chip.responseKey == "PASS" or an)
        chip:SetAlpha(chip.responseKey == "PASS" and 0.6 or 1)
    end

    local bereich = Config:Get("sessionScope") == "RAID" and "RAID" or "GUILD"
    self.scopeLabel:SetText(string.format(L.LR_SCOPE_WHICH, L["LR_SCOPE_" .. bereich]))
    self.scopeHint:SetText(L["LR_SCOPE_" .. bereich .. "_HINT"] or "")
    press(self.scopeChips, "key", bereich)

    local frist = tonumber(Config:Get("bidSeconds")) or 0
    self.timerLabel:SetText(frist > 0 and string.format(L.LR_TIMER_WHICH, frist) or L.LR_TIMER_WHICH_OFF)
    press(self.timerChips, "key", frist)

    self.softResLine:SetChecked(Config:Get("softResEnabled") ~= false)
    self.plusOneLine:SetChecked(Config:Get("plusOneEnabled") ~= false)
    self.autoTradeLine:SetChecked(Config:Get("autoTrade") ~= false)
    self.outbidLine:SetChecked(Config:Get("dkpOutbidWhisper") ~= false)

    local quelle = GA.Modules.Session:RollSource()
    self.sourceLabel:SetText(string.format(L.LR_ROLLSRC_WHICH, L["LR_ROLLSRC_" .. quelle] or quelle))
    self.sourceHint:SetText(L["LR_ROLLSRC_" .. quelle .. "_HINT"] or "")
    press(self.sourceChips, "key", quelle)
    -- Im leisen Betrieb gibt es keine Chatzeilen, die man ausblenden
    -- koennte. Ein Schalter, der nichts bewirkt, verwirrt mehr als er nuetzt.
    self.quietLine:SetChecked(Config:Get("quietRolls") ~= false)
    self.quietLine:SetEnabledState(quelle == "CHAT", L.LR_ROLLSRC_MASTER_HINT)

    self:ApplyPermission()

    local parts = self:DescribeParts()
    for index, line in ipairs(self.summaryLines) do
        local text = parts[index]
        line.text:SetText(text or "")
        line:SetShown(text ~= nil)
    end
    local warnings = self:Warnings()
    self.warning:SetText(warnings)
    self.warnHead:SetShown(warnings ~= "")
    self.warning:SetShown(warnings ~= "")

    self:Relayout()
end

function LootRules:OnShow()
    self:Refresh()
end

GA.UI.MainFrame:RegisterView("lootrules", LootRules)
GA.UI.LootRules = LootRules
