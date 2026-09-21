--[[----------------------------------------------------------------------------
    UI/GrantDialog — einen Erfolg von Hand eintragen.

    ===========================================================================
    WARUM ES DIESEN WEG GIBT
    ===========================================================================

    Rund fuenfundvierzig Erfolge im Katalog kann ein Addon NIE messen: ein
    Treffen im echten Leben, Stunden im Sprachkanal, ein geschlichteter
    Streit, ein bestaetigter Ersatzeinsatz, eine Spende in die Gildenbank.
    Sie stehen im Katalog, weil sie in einer Gilde zaehlen — nicht, weil ein
    Client sie sehen koennte.

    Bis heute hatte diese Haelfte des Systems keinen Aufrufer: Achievements
    kannte GRANTED und ClaimFirst, aber nichts im Addon rief sie je auf. Die
    Hall of Fame konnte sich strukturell nicht fuellen.

    ===========================================================================
    DIE BEGRUENDUNG IST PFLICHT
    ===========================================================================

    Ein eingetragener Erfolg ist eine Behauptung, keine Messung. Punkte von
    Hand in eine Rangliste zu schreiben, ohne zu sagen wofuer, macht die
    Rangliste wertlos — dieselbe Ueberlegung wie bei GA-153, wo eine Vergabe
    erst als dokumentiert gilt, wenn jemand sich hingesetzt und aufgeschrieben
    hat, warum.

    Der Eintrag traegt deshalb drei Dinge mit: WER, WANN, WARUM. Die Ansicht
    zeigt "eingetragen" in Warnfarbe, und der Tooltip nennt den Grund.

    ===========================================================================
    WAS DER ZEITSTEMPEL BEDEUTET
    ===========================================================================

    Den Zeitpunkt des EINTRAGS, nicht den des Ereignisses. Wann Ragnaros
    wirklich gefallen ist, weiss dieses Addon nicht, und ein Datumsfeld wuerde
    nur so tun als ob. Wer das Datum festhalten will, schreibt es in die
    Begruendung — dort steht es als das, was es ist: eine Angabe eines
    Menschen.
------------------------------------------------------------------------------]]

local _, GA = ...

local GrantDialog = {}
GA.UI.GrantDialog = GrantDialog

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local L = GA.L

local WIDTH, HEIGHT = 620, 420
local LIST_WIDTH = 230

function GrantDialog:Create()
    if self.frame then return self.frame end

    local fonts = Theme.Fonts()

    local frame = Theme.CreateNative("Frame", "GuildArmoryGrantDialog", UIParent,
        "PortraitFrameTemplate")
    if not frame then
        frame = Theme.CreateBackdropFrame("GuildArmoryGrantDialog", UIParent)
        if not Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid) then
            Theme.DoubleFrame(frame)
        end
    end

    frame:SetWidth(WIDTH)
    frame:SetHeight(HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    if frame.SetTitle then pcall(frame.SetTitle, frame, L.GRANT_TITLE) end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() GrantDialog:Hide() end)
    end

    -- Kein Charakterkreis: Hier geht es um einen Vorgang, nicht um eine
    -- Person. Der Kreis der Vorlage zeigte den eigenen Kopf, obwohl der
    -- Eintrag meistens jemand anderem gilt.
    Theme.HidePortrait(frame)

    -- Welcher Erfolg. Steht fest, wenn der Dialog aufgeht — gewaehlt wurde er
    -- in der Liste dahinter.
    self.achievement = Theme.Label(frame, "", fonts.big, Theme.color.goldBright)
    self.achievement:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
    self.achievement:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    self.achievement:SetJustifyH("LEFT")

    self.description = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    self.description:SetPoint("TOPLEFT", self.achievement, "BOTTOMLEFT", 0, -3)
    self.description:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    self.description:SetJustifyH("LEFT")
    self.description:SetHeight(26)

    -- ------------------------------------------------------- Spielerliste ---
    --
    -- Eine Liste mit Suchfeld, keine Auswahlliste: Das Dropdown zeigt zwoelf
    -- Eintraege und schweigt ueber den Rest. Eine Gilde hat mehr.
    local left = Widgets.Panel(frame, L.GRANT_PLAYER)
    left:SetPoint("TOPLEFT", self.description, "BOTTOMLEFT", 0, -8)
    left:SetWidth(LIST_WIDTH)
    left:SetPoint("BOTTOM", frame, "BOTTOM", 0, 48)

    self.search = Widgets.SearchBox(left.content, L.GRANT_SEARCH, function()
        GrantDialog:RefreshPlayers()
    end)
    self.search:SetPoint("TOPLEFT", left.content, "TOPLEFT", 0, 0)
    self.search:SetPoint("TOPRIGHT", left.content, "TOPRIGHT", 0, 0)

    self.players = Widgets.ScrollList(left.content, {
        rowHeight = 20,
        createRow = function(row)
            row.name = Theme.Label(row, "", fonts.row, Theme.color.text)
            row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.name:SetJustifyH("LEFT")
        end,
        updateRow = function(row, entry)
            row.name:SetText(entry.name)
            local chosen = entry.id == GrantDialog.playerId
            local color = chosen and Theme.color.goldBright or Theme.color.text
            row.name:SetTextColor(color[1], color[2], color[3])
        end,
        onClickRow = function(entry)
            GrantDialog.playerId = entry.id
            GrantDialog:RefreshPlayers()
            GrantDialog:RefreshStatus()
        end,
    })
    self.players:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 0, -6)
    self.players:SetPoint("BOTTOMRIGHT", left.content, "BOTTOMRIGHT", 0, 0)

    -- ------------------------------------------------------- Begruendung ----
    local right = Widgets.Panel(frame, L.GRANT_REASON)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    right:SetPoint("BOTTOM", left, "BOTTOM", 0, 0)

    local hint = Theme.Label(right.content, L.GRANT_REASON_HINT, fonts.small,
        Theme.color.textDim)
    hint:SetPoint("TOPLEFT", right.content, "TOPLEFT", 0, 0)
    hint:SetPoint("RIGHT", right.content, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetHeight(40)

    local box = CreateFrame("Frame", nil, right.content)
    box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    box:SetPoint("BOTTOMRIGHT", right.content, "BOTTOMRIGHT", 0, 0)
    Theme.Fill(box, Theme.color.rowAltBg)
    Theme.Outline(box, Theme.color.border)

    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(fonts.row)
    edit:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    edit:SetScript("OnEscapePressed", function() GrantDialog:Hide() end)
    edit:SetScript("OnTextChanged", function() GrantDialog:RefreshStatus() end)
    scroll:SetScrollChild(edit)
    self.edit = edit

    -- DAS GANZE GRAUE FELD IST DER MAUSGRIFF, nicht nur die Textzeile.
    --
    -- Gemeldet 21.09.2026: "ich kann keine reason eintragen". Ein
    -- mehrzeiliges Eingabefeld in einem Bildlauf ist nur so hoch wie sein
    -- INHALT — bei leerem Text also eine einzige Zeile am oberen Rand.
    -- Alles darunter war der Rahmen, und der hatte keinen Mausgriff. Wer in
    -- die Mitte klickte, klickte ins Leere.
    --
    -- Widgets.InputDialog hat denselben Aufbau und faellt nicht auf, weil es
    -- SetAutoFocus(true) benutzt. Hier geht das nicht: Daneben steht das
    -- Suchfeld der Spielerliste, und zwei Felder koennen den Fokus nicht
    -- teilen.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Die Breite kommt aus dem Bildlauf, nicht aus einer gerechneten Zahl:
    -- Eine Konstante stimmt genau so lange, bis jemand das Fenster aendert.
    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then edit:SetWidth(width) end
    end)
    edit:SetWidth(WIDTH - LIST_WIDTH - 70)

    -- ------------------------------------------------------- Fusszeile ------
    self.status = Theme.Label(frame, "", fonts.small, Theme.color.textFaint)
    self.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 22)
    self.status:SetPoint("RIGHT", frame, "RIGHT", -230, 0)
    self.status:SetJustifyH("LEFT")

    local cancel = Widgets.Button(frame, L.BTN_CANCEL, function() GrantDialog:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)

    self.accept = Widgets.Button(frame, L.GRANT_ACCEPT, function()
        GrantDialog:Accept()
    end, "primary")
    self.accept:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -6, 0)

    if type(_G.UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "GuildArmoryGrantDialog")
    end

    self.frame = frame
    return frame
end

-- ================================================================== Inhalt ---

function GrantDialog:RefreshPlayers()
    local search = string.lower(self.search and self.search:GetValue() or "")
    local Players = GA.Modules.Players

    local rows = {}
    for _, profile in ipairs(Players:List()) do
        local name = Players:DisplayName(profile) or profile.id
        if search == "" or string.find(string.lower(name), search, 1, true) then
            rows[#rows + 1] = { id = profile.id, name = name }
        end
    end
    self.players:SetData(rows)
end

--- Sagt VORHER, was passieren wird oder warum nicht.
---
--- Ein Knopf, der erst beim Klicken erklaert, dass etwas fehlt, ist eine
--- Falle. Hier steht der Grund, solange er gilt.
function GrantDialog:RefreshStatus()
    local Achievements = GA.Modules.Achievements
    local reason = self.edit:GetText() or ""
    local ok, message = true, ""

    if not self.playerId then
        ok, message = false, L.GRANT_NEED_PLAYER
    elseif string.gsub(reason, "%s", "") == "" then
        ok, message = false, L.GRANT_NEED_REASON
    else
        local unlocked, existing = Achievements:IsUnlocked(self.id, self.playerId)
        if unlocked then
            -- Ein staerkerer Beleg liegt schon vor. Eintragen wuerde nichts
            -- aendern, und das gehoert gesagt statt stillschweigend abgelehnt.
            local evidence = existing and existing.evidence
            ok = false
            message = string.format(L.GRANT_ALREADY,
                L["ACH_EV_" .. tostring(evidence)] or tostring(evidence))
        end
    end

    self.status:SetText(message)
    local color = ok and Theme.color.textFaint or Theme.color.warn
    self.status:SetTextColor(color[1], color[2], color[3])
    self.accept:SetEnabledState(ok, message ~= "" and message or nil)
    return ok
end

function GrantDialog:Accept()
    if not self:RefreshStatus() then return end

    local ok, result = GA.Modules.Achievements:Grant(self.id, self.playerId,
        self.edit:GetText())
    if not ok then
        self.status:SetText(L["GRANT_ERR_" .. string.upper(tostring(result))]
            or tostring(result))
        self.status:SetTextColor(Theme.color.bad[1], Theme.color.bad[2], Theme.color.bad[3])
        return
    end

    GA.Core.Debug:Info(L.GRANT_DONE, tostring(self.entryName))
    self:Hide()
end

-- ================================================================== Oeffnen --

--- @param id string  Erfolg aus dem Katalog
function GrantDialog:Open(id)
    local Achievements = GA.Modules.Achievements
    local entry = Achievements:Entry(id)
    if not entry then return false, "unknown" end
    if not Achievements:MayGrant() then return false, "notallowed" end

    self:Create()

    self.id = id
    self.entryName = entry.name
    self.playerId = nil

    self.achievement:SetText(string.format("%s  ·  %d", entry.name, entry.points or 0))
    self.description:SetText(entry.description or "")
    self.edit:SetText("")
    if self.search then self.search:Clear() end

    self:RefreshPlayers()
    self:RefreshStatus()
    self.frame:Show()

    -- Der Fokus steht gleich im Begruendungsfeld: Den Spieler waehlt man
    -- ohnehin mit der Maus, die Begruendung will getippt werden.
    self.edit:SetFocus()
    return true
end

function GrantDialog:Hide()
    if self.frame then self.frame:Hide() end
end
