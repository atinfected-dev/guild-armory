--[[----------------------------------------------------------------------------
    UI/Widgets/Form — ein kleines Formularfenster: Beschriftung links, Feld
    rechts, unten Speichern / Abbrechen (und auf Wunsch Loeschen).
    Gebaut 06.10.2026 fuer den Raidplan-Editor.

    Feldarten:
      text       einzeilig; mit `append` steht rechts eine Auswahl, deren
                 Wahl an den Text angehaengt wird (`appendSep`, sonst ", ")
      multiline  mehrzeilig, `height` Pixel hoch
      select     Auswahl aus `options()` -> { { text, value } }; `onSelect`
                 darf andere Felder fuellen (dlg:SetValue)

    EIN FENSTER JE ART, NICHT JE AUFRUF: Frames lassen sich im Spiel nicht
    wegwerfen. Das Fenster wird beim ersten Mal gebaut und danach nur neu
    befuellt.

    Ein Fehler beim Speichern schliesst das Fenster NICHT: Das Eingetippte
    bleibt stehen, die Meldung steht rot darunter.
------------------------------------------------------------------------------]]

local _, GA = ...

local Widgets = GA.UI.Widgets
local Theme = GA.UI.Theme

local LABEL_W, FIELD_W, PAD = 118, 330, 16
local dialogs = {}

local function textBox(parent, width, height, multiline)
    local fonts = Theme.Fonts()
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)
    Theme.Fill(holder, Theme.color.rowAltBg)
    Theme.Outline(holder, Theme.color.border)
    local edit
    if multiline then
        local scroll = CreateFrame("ScrollFrame", nil, holder)
        scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -4)
        scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 4)
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetWidth(width - 12)
        scroll:SetScrollChild(edit)
        holder:EnableMouse(true)
        holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
    else
        edit = CreateFrame("EditBox", nil, holder)
        edit:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, 0)
        edit:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 0)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
    edit:SetAutoFocus(false)
    edit:SetFontObject(fonts.row)
    edit:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Theme.StyleEditBox(edit)
    holder.edit = edit
    return holder
end

local function build(key, fields)
    local fonts = Theme.Fonts()
    local frame = CreateFrame("Frame", "GuildArmoryForm_" .. key, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetPoint("CENTER")
    Theme.Fill(frame, Theme.color.windowBg)
    Theme.DoubleFrame(frame)

    frame.title = Theme.Label(frame, "", fonts.title, Theme.color.heading)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -14)

    frame.controls, frame.values, frame.fields = {}, {}, {}
    local edits = {}
    local y = -42
    for _, f in ipairs(fields) do
        frame.fields[f.key] = f
        local label = Theme.Label(frame, f.label or "", fonts.row, Theme.color.textDim)
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y - 4)
        label:SetWidth(LABEL_W - 8)
        label:SetJustifyH("LEFT")
        local control, height
        if f.kind == "select" then
            control = Widgets.Dropdown(frame, {
                width = FIELD_W, placeholder = "—",
                getOptions = f.options,
                onSelect = function(value, entry)
                    frame.values[f.key] = value
                    frame.controls[f.key]:SetDisplay(entry and entry.text)
                    if f.onSelect then f.onSelect(value, frame) end
                end,
            })
            control:SetHeight(20)
            height = 20
        else
            height = f.kind == "multiline" and (f.height or 70) or 20
            local width = f.append and (FIELD_W - 104) or FIELD_W
            control = textBox(frame, width, height, f.kind == "multiline")
            edits[#edits + 1] = control.edit
            if f.append then
                local add = Widgets.Dropdown(frame, {
                    width = 98, placeholder = "+",
                    getOptions = f.append,
                    onSelect = function(value)
                        local edit = control.edit
                        local text = GA.Core.Util.Trim(edit:GetText() or "") or ""
                        edit:SetText(text == "" and value or (text .. (f.appendSep or ", ") .. value))
                    end,
                })
                add:SetHeight(20)
                add:SetPoint("LEFT", control, "RIGHT", 6, 0)
            end
        end
        control:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + LABEL_W, y)
        frame.controls[f.key] = control
        if f.hint then
            local hint = Theme.Label(frame, f.hint, fonts.small, Theme.color.textFaint)
            hint:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 2, -2)
            hint:SetWidth(FIELD_W)
            hint:SetJustifyH("LEFT")
            height = height + 14
        end
        y = y - height - 8
    end
    -- Tab springt zum naechsten Textfeld.
    for i, edit in ipairs(edits) do
        local nextEdit = edits[i % #edits + 1]
        edit:SetScript("OnTabPressed", function() nextEdit:SetFocus() end)
    end
    frame.firstEdit = edits[1]

    frame.status = Theme.Label(frame, "", fonts.small, Theme.color.bad)
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y - 2)
    frame.status:SetWidth(LABEL_W + FIELD_W)
    frame.status:SetJustifyH("LEFT")

    local cancel = Widgets.Button(frame, GA.L.BTN_CANCEL, function() frame:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 14)
    local save = Widgets.Button(frame, GA.L.BTN_APPLY, function()
        if not frame.onSave then frame:Hide() return end
        local ok, message = frame.onSave(frame:GetValues())
        if ok then frame:Hide() else frame.status:SetText(message or "") end
    end, "primary")
    save:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
    frame.delete = Widgets.Button(frame, GA.L.BTN_REMOVE, function()
        if frame.onDelete then frame.onDelete() end
        frame:Hide()
    end)
    -- Loeschen ist unwiderruflich: erst rot "Wirklich?", dann weg.
    frame.delete:SetConfirm(GA.L.BTN_REALLY)
    frame.delete:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 14)

    frame:SetSize(PAD * 2 + LABEL_W + FIELD_W + 4, -y + 72)

    function frame:SetValue(fieldKey, value)
        local f, control = self.fields[fieldKey], self.controls[fieldKey]
        if not f then return end
        if f.kind == "select" then
            self.values[fieldKey] = value
            local shown
            for _, option in ipairs(f.options and f.options() or {}) do
                if option.value == value then shown = option.text end
            end
            control:SetDisplay(shown)
        else
            control.edit:SetText(value ~= nil and tostring(value) or "")
            if control.edit.SetCursorPosition then control.edit:SetCursorPosition(0) end
        end
    end

    function frame:GetValues()
        local out = {}
        for fieldKey, f in pairs(self.fields) do
            if f.kind == "select" then out[fieldKey] = self.values[fieldKey]
            else out[fieldKey] = self.controls[fieldKey].edit:GetText() end
        end
        return out
    end

    frame:Hide()
    if type(_G.UISpecialFrames) == "table" then table.insert(UISpecialFrames, frame:GetName()) end
    return frame
end

--- Oeffnet (oder baut beim ersten Mal) ein Formular.
--- @param key string  Art des Formulars — dasselbe key, dasselbe Fenster
--- @param onSave function(values) -> ok, fehlermeldung
--- @param onDelete function|nil  zeigt "Entfernen", wenn gesetzt
function Widgets.FormDialog(key, title, fields, values, onSave, onDelete)
    local frame = dialogs[key]
    if not frame then
        frame = build(key, fields)
        dialogs[key] = frame
    end
    frame.title:SetText(title or "")
    frame.status:SetText("")
    frame.onSave, frame.onDelete = onSave, onDelete
    frame.delete:SetShown(onDelete ~= nil)
    for _, f in ipairs(fields) do frame:SetValue(f.key, values and values[f.key]) end
    frame:Show()
    frame:Raise()
    if frame.firstEdit then frame.firstEdit:SetFocus() end
    return frame
end
