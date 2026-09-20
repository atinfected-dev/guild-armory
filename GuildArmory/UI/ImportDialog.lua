--[[----------------------------------------------------------------------------
    UI/ImportDialog — Sicherung einlesen, mit Vorschau.

    ZWEI SCHRITTE, UND DAS IST ABSICHT:

      1. Einfuegen -> das Addon rechnet durch, was passieren WUERDE, und zeigt
         es an. Nichts ist geaendert.
      2. Ein zweiter Klick uebernimmt.

    Ein Import beruehrt die Historie einer ganzen Gilde. Wer ihn ausloest, soll
    vorher sehen, was geschieht — nicht hinterher merken, was geschehen ist.
    Dasselbe Muster wie bei /ga reset, aus demselben Grund.

    Das Haekchen "eigene Sicherung" entscheidet ueber die Herkunft der
    Main/Twink-Zuordnungen: Ein "bewiesen" aus einer fremden Datei war der
    Beweis des Exporteurs, nicht deiner (siehe Core/Import.lua).
------------------------------------------------------------------------------]]

local _, GA = ...

local ImportDialog = {}
GA.UI.ImportDialog = ImportDialog

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local L = GA.L

function ImportDialog:Create()
    if self.frame then return self.frame end

    local fonts = Theme.Fonts()

    local frame = Theme.CreateNative("Frame", "GuildArmoryImportDialog", UIParent,
        "PortraitFrameTemplate")
    if not frame then
        frame = Theme.CreateBackdropFrame("GuildArmoryImportDialog", UIParent)
        if not Theme.Backdrop(frame, "window", Theme.color.windowBg, Theme.color.goldMid) then
            Theme.DoubleFrame(frame)
        end
    end

    frame:SetWidth(620)
    frame:SetHeight(460)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    if frame.SetTitle then pcall(frame.SetTitle, frame, L.IMPORT_TITLE) end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() ImportDialog:Hide() end)
    end

    local hint = Theme.Label(frame, L.IMPORT_HINT, fonts.small, Theme.color.textDim)
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
    hint:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetSpacing(2)

    -- Eingabefeld
    local box = Widgets.Inset(frame)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -76)
    box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -76)
    box:SetHeight(180)

    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(fonts.row)
    edit:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    edit:SetWidth(560)
    edit:SetScript("OnEscapePressed", function() ImportDialog:Hide() end)
    edit:SetScript("OnTextChanged", function() ImportDialog:Analyse() end)
    scroll:SetScrollChild(edit)
    self.edit = edit

    -- Vorschau
    self.report = Theme.Label(frame, "", fonts.body, Theme.color.text)
    self.report:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -10)
    self.report:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    self.report:SetJustifyH("LEFT")
    self.report:SetSpacing(3)

    -- Eigene Sicherung?
    self.trusted = Widgets.CheckBox(frame, L.SET_TRUSTED, function() end)
    self.trusted:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 44)

    local trustedHint = Theme.Label(frame, L.SET_TRUSTED_HINT, fonts.small, Theme.color.textFaint)
    trustedHint:SetPoint("TOPLEFT", self.trusted, "BOTTOMLEFT", 4, -2)
    trustedHint:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    trustedHint:SetJustifyH("LEFT")

    local cancel = Widgets.Button(frame, L.BTN_CLOSE, function() ImportDialog:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)

    self.apply = Widgets.Button(frame, L.BTN_IMPORT, function() ImportDialog:Apply() end, "primary")
    self.apply:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -6, 0)

    if type(_G.UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "GuildArmoryImportDialog")
    end

    self.frame = frame
    return frame
end

--- Rechnet die Vorschau, ohne etwas zu aendern.
function ImportDialog:Analyse()
    local payload, reason = GA.Core.Import:Parse(self.edit:GetText())
    self.payload = payload

    if not payload then
        local text = self.edit:GetText()
        self.report:SetText(text == "" and "" or (L["IMPORT_ERR_" .. tostring(reason)] or reason))
        self.report:SetTextColor(Theme.color.warn[1], Theme.color.warn[2], Theme.color.warn[3])
        self.apply:SetEnabledState(false, L["IMPORT_ERR_" .. tostring(reason)])
        return
    end

    local preview = GA.Core.Import:Preview(payload)
    self.report:SetText(GA.Core.Import:Describe(preview))
    -- Widersprueche in Warnfarbe: Sie sind das Einzige, worueber man vor dem
    -- Uebernehmen wirklich nachdenken muss.
    local color = preview.awards.conflict > 0 and Theme.color.warn or Theme.color.text
    self.report:SetTextColor(color[1], color[2], color[3])
    self.apply:SetEnabledState(true)
end

function ImportDialog:Apply()
    if not self.payload then return end

    local report = GA.Core.Import:Apply(self.payload, {
        trusted = self.trusted:GetChecked() and true or false,
    })

    GA.Core.Debug:Info(L.IMPORT_DONE,
        report.characters.new + report.characters.update,
        report.awards.new, report.awards.conflict)

    self:Hide()
    if GA.UI.MainFrame:IsVisible() then GA.UI.MainFrame:ShowView("loothistory") end
end

--- @param mode string|nil  "own" liest den Block aus dieser Datenbank
function ImportDialog:Open(mode)
    self:Create()

    if mode == "own" then
        local payload, reason = GA.Core.Import:FromOwnExport()
        if not payload then
            GA.Core.Debug:Warn(L["IMPORT_ERR_" .. tostring(reason)] or tostring(reason))
            return
        end
        self.edit:SetText(GA.Core.Database.account.export or "")
    else
        self.edit:SetText("")
    end

    self.trusted:SetChecked(mode == "own")
    self:Analyse()
    self.frame:Show()
    self.edit:SetFocus()
end

function ImportDialog:Hide()
    if self.frame then self.frame:Hide() end
    self.payload = nil
end
