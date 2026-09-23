--[[----------------------------------------------------------------------------
    UI/Views/LootRules — wie diese Gilde verteilt.

    Alles, was eine Lootvergabe regelt, auf einer Seite: ob ein Council
    abstimmt, wer abstimmen darf, ob Soft Reserves gelten, ob Plus Eins
    mitlaeuft, welche Antworten die Bieter bekommen.

    WARUM EINE EIGENE SEITE UND NICHT DREI KAESTCHEN IN DEN EINSTELLUNGEN.

    Diese Schalter ergeben ZUSAMMEN eine Regel. "Council aus" und "jeder
    darf abstimmen" widersprechen sich; "Soft Reserves an" ohne offene
    Runde zeigt eine leere Liste, die nie jemand fuellt. Wer sie einzeln
    verstellt, ohne die anderen zu sehen, bekommt einen Abend, den niemand
    erklaeren kann.

    Deshalb steht unter jedem Block, was er BEWIRKT, und ganz unten eine
    Zusammenfassung in einem Satz: was heute Abend gilt. Wer die liest,
    muss die Schalter nicht im Kopf zusammensetzen.

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

--- Die drei Verteilarten, in der Reihenfolge der Knoepfe.
---
--- In ALLEN dreien vergibt am Ende der Plündermeister. Das ist kein
--- Zufall, sondern der Grund, warum es eine Seite und nicht drei
--- Verfahren gibt.
local MODES = {
    { key = "COUNCIL", label = "LR_MODE_COUNCIL" },
    { key = "SOFTRES", label = "LR_MODE_SOFTRES" },
    { key = "ROLL",    label = "LR_MODE_ROLL" },
    { key = "DKP",     label = "LR_MODE_DKP" },
}

--- Wer abstimmen darf, in der Reihenfolge der Knoepfe.
local VOTERS = {
    { key = "COUNCIL",    label = "LR_VOTE_COUNCIL" },
    { key = "LOOTMASTER", label = "LR_VOTE_LOOTMASTER" },
    { key = "ALL",        label = "LR_VOTE_ALL" },
}

-- ================================================================== Aufbau ----

function LootRules:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    local fonts = Theme.Fonts()
    local pad, gap = 10, 8

    -- Eine Spalte mit Bildlauf: Die Seite waechst mit den Erklaerungen, und
    -- die sind in manchen Sprachen deutlich laenger.
    self.column = Widgets.ScrollArea(frame)
    self.column:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    self.column:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)

    local inhalt = self.column.content

    -- ------------------------------------------------------- Council --------
    local council = Widgets.Panel(inhalt, L.LR_COUNCIL)
    council:SetPoint("TOPLEFT", inhalt, "TOPLEFT", 0, 0)
    council:SetPoint("RIGHT", inhalt, "RIGHT", 0, 0)
    council:SetHeight(200)
    self.councilPanel = council

    self.modeLabel = Theme.Label(council.content, "", fonts.row, Theme.color.text)
    self.modeButtons = {}
    for _, entry in ipairs(MODES) do
        local button = Widgets.Button(council.content, L[entry.label], function()
            Config:Set("lootMode", entry.key)
            -- Die alte Einstellung mitziehen, damit ein aelterer Client in
            -- derselben Gilde nicht ploetzlich anders verteilt.
            Config:Set("councilEnabled", entry.key == "COUNCIL")
            self:Refresh()
        end)
        button:SetHeight(20)
        button.modeKey = entry.key
        self.modeButtons[#self.modeButtons + 1] = button
    end
    self.permission = Theme.Label(council.content, "", fonts.small, Theme.color.warn)
    self.councilHint = Theme.Label(council.content, L.LR_COUNCIL_HINT,
        fonts.small, Theme.color.textDim)

    self.voterLabel = Theme.Label(council.content, "", fonts.row, Theme.color.text)
    self.voterButtons = {}
    for _, entry in ipairs(VOTERS) do
        local button = Widgets.Button(council.content, L[entry.label], function()
            Config:Set("voteRole", entry.key)
            self:Refresh()
        end)
        button:SetHeight(20)
        button.voteKey = entry.key
        self.voterButtons[#self.voterButtons + 1] = button
    end
    self.voterHint = Theme.Label(council.content, L.LR_VOTE_HINT,
        fonts.small, Theme.color.textDim)

    -- WER UEBERHAUPT TEILNIMMT. Steht beim Council, weil es dieselbe Frage
    -- ist wie "wer darf abstimmen" — nur eine Ebene davor.
    self.scopeLabel = Theme.Label(council.content, "", fonts.row, Theme.color.text)
    self.scopeButtons = {}
    for _, key in ipairs({ "GUILD", "RAID" }) do
        local button = Widgets.Button(council.content, L["LR_SCOPE_" .. key], function()
            Config:Set("sessionScope", key)
            self:Refresh()
        end)
        button:SetHeight(20)
        button.scopeKey = key
        self.scopeButtons[#self.scopeButtons + 1] = button
    end
    self.scopeHint = Theme.Label(council.content, "", fonts.small, Theme.color.textDim)

    -- ------------------------------------------------------- Antworten ------
    local antworten = Widgets.Panel(inhalt, L.LR_RESPONSES)
    antworten:SetPoint("TOPLEFT", council, "BOTTOMLEFT", 0, -gap)
    antworten:SetPoint("RIGHT", inhalt, "RIGHT", 0, 0)
    antworten:SetHeight(200)
    self.responsePanel = antworten

    self.responseHint = Theme.Label(antworten.content, L.LR_RESPONSES_HINT,
        fonts.small, Theme.color.textDim)

    -- Ein Kaestchen je Antwort. "Pass" ist dabei, aber nicht abwaehlbar:
    -- Wer nicht will, muss das sagen koennen — sonst bleibt nur Schweigen,
    -- und das ist von "noch nicht geantwortet" nicht zu unterscheiden.
    self.responseBoxes = {}
    for _, entry in ipairs(GA.Data.Schema.DefaultResponses) do
        local box = Widgets.CheckBox(antworten.content, entry.label,
            function(checked)
                local aktiv = Config:Get("activeResponses")
                if type(aktiv) ~= "table" then
                    aktiv = {}
                    for _, e in ipairs(GA.Data.Schema.DefaultResponses) do
                        aktiv[e.key] = true
                    end
                end
                aktiv[entry.key] = checked or nil
                Config:Set("activeResponses", aktiv)
                self:Refresh()
            end)
        box.responseKey = entry.key
        box.color = entry.color
        self.responseBoxes[#self.responseBoxes + 1] = box
    end

    -- ------------------------------------------------------- Verfahren ------
    local verfahren = Widgets.Panel(inhalt, L.LR_RULES)
    verfahren:SetPoint("TOPLEFT", antworten, "BOTTOMLEFT", 0, -gap)
    verfahren:SetPoint("RIGHT", inhalt, "RIGHT", 0, 0)
    verfahren:SetHeight(220)
    self.rulesPanel = verfahren

    self.softResBox = Widgets.CheckBox(verfahren.content, L.LR_SOFTRES,
        function(checked)
            Config:Set("softResEnabled", checked)
            self:Refresh()
        end)
    self.softResHint = Theme.Label(verfahren.content, L.LR_SOFTRES_HINT,
        fonts.small, Theme.color.textDim)

    self.plusOneBox = Widgets.CheckBox(verfahren.content, L.LR_PLUSONE,
        function(checked)
            Config:Set("plusOneEnabled", checked)
            self:Refresh()
        end)
    self.plusOneHint = Theme.Label(verfahren.content, L.LR_PLUSONE_HINT,
        fonts.small, Theme.color.textDim)

    self.rotationBox = Widgets.CheckBox(verfahren.content, L.LR_ROTATION,
        function(checked)
            Config:Set("rotationEnabled", checked)
            self:Refresh()
        end)
    self.rotationHint = Theme.Label(verfahren.content, L.LR_ROTATION_HINT,
        fonts.small, Theme.color.textDim)

    self.autoTradeBox = Widgets.CheckBox(verfahren.content, L.LR_AUTOTRADE,
        function(checked)
            Config:Set("autoTrade", checked)
            self:Refresh()
        end)
    self.autoTradeHint = Theme.Label(verfahren.content, L.LR_AUTOTRADE_HINT,
        fonts.small, Theme.color.textDim)

    self.quietBox = Widgets.CheckBox(verfahren.content, L.LR_QUIETROLLS,
        function(checked)
            Config:Set("quietRolls", checked)
            self:Refresh()
        end)
    self.quietHint = Theme.Label(verfahren.content, L.LR_QUIETROLLS_HINT,
        fonts.small, Theme.color.textDim)

    self.outbidBox = Widgets.CheckBox(verfahren.content, L.LR_OUTBID,
        function(checked)
            Config:Set("dkpOutbidWhisper", checked)
            self:Refresh()
        end)
    self.outbidHint = Theme.Label(verfahren.content, L.LR_OUTBID_HINT,
        fonts.small, Theme.color.textDim)

    -- DIE GEBOTSFRIST. Feste Stufen statt eines Eingabefelds: Es gibt
    -- keinen Grund fuer 47 Sekunden, und eine Zahl, die man eintippt, ist
    -- eine, die man vertippen kann.
    self.timerLabel = Theme.Label(verfahren.content, "", fonts.row, Theme.color.text)
    self.timerButtons = {}
    for _, sekunden in ipairs({ 0, 60, 120, 180 }) do
        local button = Widgets.Button(verfahren.content,
            sekunden == 0 and L.LR_TIMER_OFF or string.format(L.LR_TIMER_SECONDS, sekunden),
            function()
                Config:Set("bidSeconds", sekunden)
                self:Refresh()
            end)
        button:SetHeight(20)
        button.seconds = sekunden
        self.timerButtons[#self.timerButtons + 1] = button
    end
    self.timerHint = Theme.Label(verfahren.content, L.LR_TIMER_HINT,
        fonts.small, Theme.color.textDim)

    self.sourceLabel = Theme.Label(verfahren.content, "", fonts.row, Theme.color.text)
    self.sourceButtons = {}
    for _, key in ipairs({ "MASTER", "CHAT" }) do
        local button = Widgets.Button(verfahren.content, L["LR_ROLLSRC_" .. key], function()
            Config:Set("rollSource", key)
            self:Refresh()
        end)
        button:SetHeight(20)
        button.sourceKey = key
        self.sourceButtons[#self.sourceButtons + 1] = button
    end
    self.sourceHint = Theme.Label(verfahren.content, "", fonts.small, Theme.color.textDim)

    -- ------------------------------------------------------- Ergebnis -------
    local ergebnis = Widgets.Panel(inhalt, L.LR_SUMMARY)
    ergebnis:SetPoint("TOPLEFT", verfahren, "BOTTOMLEFT", 0, -gap)
    ergebnis:SetPoint("RIGHT", inhalt, "RIGHT", 0, 0)
    ergebnis:SetHeight(110)
    self.summaryPanel = ergebnis

    -- WAS HEUTE ABEND GILT, in einem Satz. Die Schalter darueber ergeben
    -- zusammen eine Regel; wer sie einzeln liest, setzt sie im Kopf falsch
    -- zusammen.
    -- DER WEG ZU DEN PUNKTEN. Er steht bei der Zusammenfassung und nicht
    -- beim Modusknopf: Man oeffnet die Rangliste auch dann, wenn heute
    -- gar nicht mit DKP verteilt wird — etwa um einen Nachtrag zu buchen.
    self.dkpButton = Widgets.Button(ergebnis.content, L.DKP_OPEN, function()
        GA.UI.DkpFrame:Toggle()
    end)
    self.dkpButton:SetHeight(22)
    self.dkpButton:SetWidth(180)

    self.summary = Theme.Label(ergebnis.content, "", fonts.body, Theme.color.text)
    self.warning = Theme.Label(ergebnis.content, "", fonts.small, Theme.color.warn)

    self.frame = frame
    return frame
end

--- Darfst du diese Regeln aendern?
---
--- Plündermeister und Administrator. Jeder andere sieht die Seite, kann
--- aber nichts verstellen.
---
--- WARUM UEBERHAUPT SPERREN, WENN ES OERTLICHE EINSTELLUNGEN SIND.
---
--- Weil eine Anzeige, die man verstellen kann, ohne dass es etwas bewirkt,
--- schlimmer ist als eine gesperrte. Massgeblich sind die Regeln DESSEN,
--- DER DIE SITZUNG FUEHRT — sie reisen mit der Ankuendigung. Wer hier
--- etwas umstellt, ohne Plündermeister zu sein, aendert nur sein eigenes
--- Bild und wundert sich dann, dass der Abend anders laeuft.
---
--- Die Sperre ist also keine Sicherheitsmassnahme — die waere auf einem
--- fremden Client ohnehin wertlos. Sie sagt die Wahrheit: Hier
--- entscheidest du nichts.
--- @return boolean darf, string|nil grund
function LootRules:MayEdit()
    local identity = GA.Core.Compat.GetPlayerIdentity()
    if not identity.guid then return false, "noguid" end

    if GA.Core.Database:HasAtLeast(identity.guid, GA.const.ROLE_LOOTMASTER) then
        return true
    end
    return false, "role"
end

--- Schaltet alle Bedienelemente scharf oder stumpf.
function LootRules:ApplyPermission()
    local darf, grund = self:MayEdit()

    --- EINE RECHTEPRUEFUNG NIMMT WEG, SIE GIBT NICHT.
    ---
    --- Vorher setzte sie jedes Element auf "darf" — und loeschte damit,
    --- was Refresh gerade entschieden hatte: dass der GEWAEHLTE Knopf aus
    --- ist, weil er kein Ziel mehr ist. Wer darf, sah alle Knoepfe scharf
    --- und konnte nicht erkennen, was eingestellt war.
    ---
    --- Also: Darf man nicht, wird gesperrt. Darf man, bleibt stehen, was
    --- Refresh gesetzt hat.
    local function setze(element)
        if not element then return end
        if darf then return end
        if element.SetEnabledState then element:SetEnabledState(false)
        elseif element.Disable then element:Disable() end
    end

    for _, liste in ipairs({ self.modeButtons, self.voterButtons, self.scopeButtons,
                            self.sourceButtons, self.timerButtons,
                            self.responseBoxes }) do
        for _, element in ipairs(liste or {}) do setze(element) end
    end
    for _, box in ipairs({ self.softResBox, self.plusOneBox, self.rotationBox,
                           self.autoTradeBox, self.quietBox, self.outbidBox }) do
        setze(box)
    end

    -- Der Grund steht DA, nicht nur die Sperre. Ein ausgegrautes Fenster
    -- ohne Erklaerung sieht aus wie ein Fehler.
    if self.permission then
        if darf then
            self.permission:SetText("")
        else
            self.permission:SetText(L["LR_LOCKED_" .. tostring(grund)] or L.LR_LOCKED_role)
        end
    end

    return darf
end

-- ================================================================== Layout ----

-- LOOTRULES LAYOUT ANFANG (herausgeschnitten von tools/test/lootrules.test.js)

--- Setzt alle vier Bloecke neu und misst dabei jede Erklaerung.
function LootRules:Relayout()
    if not self.councilPanel then return false end
    if not self:LayoutCouncil() then return false end
    self:LayoutResponses()
    self:LayoutRules()
    self:LayoutSummary()
    self:UpdateColumnHeight()
    return true
end

function LootRules:LayoutCouncil()
    local stapel = Widgets.Stack(self.councilPanel.content)
    if not stapel then return false end

    stapel:Text(self.permission, 0, 0)
    stapel:Text(self.modeLabel, 0, 6)
    stapel:Row(self.modeButtons, 0, 4)
    stapel:Text(self.councilHint, 0, 6)
    stapel:Text(self.voterLabel, 0, 10)
    stapel:Row(self.voterButtons, 0, 4)
    stapel:Text(self.voterHint, 0, 6)
    stapel:Text(self.scopeLabel, 0, 10)
    stapel:Row(self.scopeButtons, 0, 4)
    stapel:Text(self.scopeHint, 0, 6)

    self.councilPanel:SetHeight(stapel:Height() + 24 + 16)
    return true
end

function LootRules:LayoutResponses()
    local stapel = Widgets.Stack(self.responsePanel.content)
    if not stapel then return end

    stapel:Text(self.responseHint, 0, 0)
    for _, box in ipairs(self.responseBoxes) do
        stapel:Add(box, -4, 2)
    end

    self.responsePanel:SetHeight(stapel:Height() + 24 + 16)
end

function LootRules:LayoutRules()
    local stapel = Widgets.Stack(self.rulesPanel.content)
    if not stapel then return end

    stapel:Add(self.softResBox, -4, 0)
    stapel:Text(self.softResHint, 4, 2)
    stapel:Add(self.plusOneBox, -4, 8)
    stapel:Text(self.plusOneHint, 4, 2)
    stapel:Add(self.rotationBox, -4, 8)
    stapel:Text(self.rotationHint, 4, 2)
    stapel:Add(self.autoTradeBox, -4, 8)
    stapel:Text(self.autoTradeHint, 4, 2)
    stapel:Text(self.sourceLabel, 0, 10)
    stapel:Row(self.sourceButtons, 0, 4)
    stapel:Text(self.sourceHint, 0, 6)
    stapel:Add(self.quietBox, -4, 8)
    stapel:Text(self.quietHint, 4, 2)
    stapel:Add(self.outbidBox, -4, 8)
    stapel:Text(self.outbidHint, 4, 2)
    stapel:Text(self.timerLabel, 0, 10)
    stapel:Row(self.timerButtons, 0, 4)
    stapel:Text(self.timerHint, 0, 6)

    self.rulesPanel:SetHeight(stapel:Height() + 24 + 16)
end

function LootRules:LayoutSummary()
    local stapel = Widgets.Stack(self.summaryPanel.content)
    if not stapel then return end

    stapel:Text(self.summary, 0, 0)
    stapel:Text(self.warning, 0, 6)
    stapel:Add(self.dkpButton, 0, 8)

    self.summaryPanel:SetHeight(stapel:Height() + 24 + 16)
end

function LootRules:UpdateColumnHeight()
    if not self.column then return end
    local hoehe = self.councilPanel:GetHeight() + self.responsePanel:GetHeight()
        + self.rulesPanel:GetHeight() + self.summaryPanel:GetHeight() + 4 * 8
    self.column.content:SetHeight(math.max(1, hoehe))
    self.column:Refresh()
end

-- LOOTRULES LAYOUT ENDE

-- ================================================================== Refresh ---

--- Welche Antworten gerade freigeschaltet sind.
local function aktiveAntworten()
    local aktiv = Config:Get("activeResponses")
    if type(aktiv) ~= "table" then return nil end
    return aktiv
end

--- Der Satz, der beschreibt, was heute Abend gilt.
---
--- Aus den Schaltern ZUSAMMENGESETZT, nicht je Schalter eine Zeile: Die
--- Frage ist "wie verteilen wir heute", nicht "welche Haekchen stehen".
function LootRules:Describe()
    local mode = GA.Modules.Session:Mode()
    local wer = Config:Get("voteRole") or "COUNCIL"

    local teile = {}
    if mode == "COUNCIL" then
        teile[#teile + 1] = string.format(L.LR_SUM_COUNCIL,
            L["LR_VOTE_" .. wer] or wer)
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
        teile[#teile + 1] = string.format(L.LR_SUM_ROTATION,
            tonumber(Config:Get("rotationSeats")) or 2)
    end

    return table.concat(teile, " ")
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

function LootRules:Refresh()
    if not self.frame then return end

    local mode = GA.Modules.Session:Mode()
    local council = mode == "COUNCIL"

    self.modeLabel:SetText(string.format(L.LR_MODE_WHICH,
        L["LR_MODE_" .. mode] or mode))
    for _, button in ipairs(self.modeButtons) do
        if button.SetEnabledState then
            button:SetEnabledState(button.modeKey ~= mode)
        end
    end
    self.councilHint:SetText(L["LR_MODE_" .. mode .. "_HINT"] or "")

    local wer = Config:Get("voteRole") or "COUNCIL"
    self.voterLabel:SetText(string.format(L.LR_VOTE_WHO,
        L["LR_VOTE_" .. wer] or wer))
    for _, button in ipairs(self.voterButtons) do
        -- Der gewaehlte Knopf ist der ausgegraute: Er ist kein Ziel mehr.
        if button.SetEnabledState then
            button:SetEnabledState(council and button.voteKey ~= wer)
        end
    end

    -- Wer teilnimmt. STAND VORHER IN Warnings() — mein Einfuegeanker traf
    -- die falsche Funktion. Dass die Knoepfe trotzdem richtig aussahen,
    -- war Zufall: Warnings() laeuft nach ApplyPermission, die anderen
    -- Knoepfe wurden davor gesetzt und danach ueberschrieben. Eine
    -- Abfragefunktion, die nebenbei Knoepfe schaltet, macht die
    -- Reihenfolge zur Verabredung.
    local bereich = Config:Get("sessionScope") == "RAID" and "RAID" or "GUILD"
    self.scopeLabel:SetText(string.format(L.LR_SCOPE_WHICH, L["LR_SCOPE_" .. bereich]))
    self.scopeHint:SetText(L["LR_SCOPE_" .. bereich .. "_HINT"] or "")
    for _, button in ipairs(self.scopeButtons) do
        if button.SetEnabledState then
            button:SetEnabledState(button.scopeKey ~= bereich)
        end
    end

    local aktiv = aktiveAntworten()
    for _, box in ipairs(self.responseBoxes) do
        local an = (aktiv == nil) or (aktiv[box.responseKey] and true or false)
        box:SetChecked(box.responseKey == "PASS" or an)
    end

    self.softResBox:SetChecked(Config:Get("softResEnabled") ~= false)
    self.plusOneBox:SetChecked(Config:Get("plusOneEnabled") ~= false)
    self.rotationBox:SetChecked(Config:Get("rotationEnabled") and true or false)
    self.autoTradeBox:SetChecked(Config:Get("autoTrade") ~= false)
    local quelle = GA.Modules.Session:RollSource()
    self.sourceLabel:SetText(string.format(L.LR_ROLLSRC_WHICH,
        L["LR_ROLLSRC_" .. quelle] or quelle))
    self.sourceHint:SetText(L["LR_ROLLSRC_" .. quelle .. "_HINT"] or "")
    for _, button in ipairs(self.sourceButtons) do
        if button.SetEnabledState then
            button:SetEnabledState(button.sourceKey ~= quelle)
        end
    end

    -- Im leisen Betrieb gibt es keine Chatzeilen, die man ausblenden
    -- koennte. Ein Kaestchen, das nichts bewirkt, verwirrt mehr als es
    -- nuetzt.
    self.outbidBox:SetChecked(Config:Get("dkpOutbidWhisper") ~= false)

    local frist = tonumber(Config:Get("bidSeconds")) or 0
    self.timerLabel:SetText(frist > 0
        and string.format(L.LR_TIMER_WHICH, frist)
        or L.LR_TIMER_WHICH_OFF)
    for _, button in ipairs(self.timerButtons) do
        if button.SetEnabledState then
            button:SetEnabledState(button.seconds ~= frist)
        end
    end

    self.quietBox:SetChecked(Config:Get("quietRolls") ~= false)
    if self.quietBox.SetEnabledState then
        self.quietBox:SetEnabledState(quelle == "CHAT")
    end

    self:ApplyPermission()

    self.summary:SetText(self:Describe())
    self.warning:SetText(self:Warnings())

    self:Relayout()
end

function LootRules:OnShow()
    self:Refresh()
end

GA.UI.MainFrame:RegisterView("lootrules", LootRules)
GA.UI.LootRules = LootRules
