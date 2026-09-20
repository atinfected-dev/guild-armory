--[[----------------------------------------------------------------------------
    Widgets/Button — Schaltflaechen, Reiter und Filterchips.

    Seit 19.09.2026 zuerst Blizzards Vorlagen (UIPanelButtonTemplate, die Reiter
    des Charakterfensters, SearchBoxTemplate, UICheckButtonTemplate): So sehen
    Knoepfe aus wie im Spiel, nicht wie auf einer Webseite. Jede Vorlage wird
    ueber Theme.CreateNative per Rueckgabewert geprueft; fehlt sie, zeichnet der
    Rueckfall darunter mit CreateFrame("Button") und Texturen.
------------------------------------------------------------------------------]]

local _, GA = ...

local Widgets = GA.UI.Widgets or {}
GA.UI.Widgets = Widgets

local Theme = GA.UI.Theme

-- ----------------------------------------------------------------- Knopf -----

--- @param parent Frame
--- @param text string
--- @param onClick function|nil
--- @param variant string|nil  "primary" fuer die hervorgehobene Aktion
function Widgets.Button(parent, text, onClick, variant)
    local native = Widgets.NativeButton(parent, text, onClick, variant)
    if native then return native end
    return Widgets.FlatButton(parent, text, onClick, variant)
end

--- Blizzards Standardknopf (rot-braun, goldene Schrift). nil, wenn die Vorlage fehlt.
function Widgets.NativeButton(parent, text, onClick, variant)
    local button = Theme.CreateNative("Button", nil, parent, "UIPanelButtonTemplate")
    if not button then return nil end

    button:SetHeight(22)
    button:SetText(text or "")
    local label = Theme.NativeText(button)
    local width = label and label.GetStringWidth and label:GetStringWidth() or 60
    button:SetWidth(math.max(60, width + 26))
    button.label = label

    if onClick then button:SetScript("OnClick", onClick) end

    button:HookScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)

    function button:SetEnabledState(enabled, reason)
        if enabled then self:Enable() self.tooltip = nil
        else self:Disable() self.tooltip = reason end
    end

    function button:SetLabel(newText)
        self:SetText(newText or "")
        local fs = Theme.NativeText(self)
        local w = fs and fs.GetStringWidth and fs:GetStringWidth() or 60
        self:SetWidth(math.max(60, w + 26))
    end

    return button
end

--- Rueckfall: flacher Knopf aus Texturen.
function Widgets.FlatButton(parent, text, onClick, variant)
    local fonts = Theme.Fonts()
    local isPrimary = variant == "primary"

    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(20)

    local background = Theme.Fill(button, isPrimary and Theme.color.goldDeep or { 0, 0, 0, 0 })
    local lines = Theme.Outline(button, isPrimary and Theme.color.goldDim or Theme.color.borderLit)

    local label = Theme.Label(button, string.upper(text or ""), fonts.small,
        isPrimary and Theme.color.goldBright or Theme.color.goldMid)
    label:SetPoint("CENTER", button, "CENTER", 0, 0)

    button:SetWidth(label:GetStringWidth() + 22)

    button:SetScript("OnEnter", function()
        Theme.Paint(background, isPrimary and Theme.color.goldDim or Theme.color.goldDeep)
        label:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
        for _, line in ipairs(lines) do Theme.Paint(line, Theme.color.goldDim) end

        if button.tooltip then
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(button.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function()
        Theme.Paint(background, isPrimary and Theme.color.goldDeep or { 0, 0, 0, 0 })
        local color = isPrimary and Theme.color.goldBright or Theme.color.goldMid
        label:SetTextColor(color[1], color[2], color[3])
        for _, line in ipairs(lines) do
            Theme.Paint(line, isPrimary and Theme.color.goldDim or Theme.color.borderLit)
        end
        GameTooltip:Hide()
    end)

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    button.label = label

    --- Deaktiviert den Knopf sichtbar. Wird z.B. fuer "Ready Check" gebraucht,
    --- wenn der Spieler nicht Raidleiter ist.
    function button:SetEnabledState(enabled, reason)
        if enabled then
            self:Enable()
            local color = isPrimary and Theme.color.goldBright or Theme.color.goldMid
            label:SetTextColor(color[1], color[2], color[3])
            self.tooltip = nil
        else
            self:Disable()
            label:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
            self.tooltip = reason
        end
    end

    function button:SetLabel(newText)
        label:SetText(string.upper(newText or ""))
        self:SetWidth(label:GetStringWidth() + 22)
    end

    return button
end

-- --------------------------------------------------------- Reiter (Sidebar) --

--- Eintrag in der Seitenleiste. Ausgewaehlt: goldener Text, goldener Balken links.
--- @param phaseTag string|nil  "P2" usw. fuer noch nicht gebaute Ansichten
function Widgets.NavItem(parent, text, phaseTag, onClick)
    local fonts = Theme.Fonts()

    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(Theme.size.tabHeight)

    local highlight = Theme.Fill(button, { 0, 0, 0, 0 })

    -- Der Auswahlbalken liegt links und ist im Normalzustand unsichtbar.
    local marker = button:CreateTexture(nil, "ARTWORK")
    Theme.Paint(marker, Theme.color.gold)
    marker:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    marker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    marker:SetWidth(2)
    marker:Hide()

    -- Kapitalis in Normalschreibung statt gesperrter Versalien in Schmalschrift:
    -- so liest sich die Navigation wie ein Reiter im Spiel, nicht wie ein
    -- Tabellenkopf.
    local label = Theme.Label(button, text, fonts.nav, Theme.color.textDim)
    label:SetPoint("LEFT", button, "LEFT", 14, 0)

    local phase
    if phaseTag then
        phase = Theme.Label(button, phaseTag, fonts.small, Theme.color.textFaint)
        phase:SetPoint("RIGHT", button, "RIGHT", -10, 0)
    end

    button.selected = false

    function button:SetSelected(selected)
        self.selected = selected and true or false
        if self.selected then
            marker:Show()
            Theme.Paint(highlight, Theme.color.panelBg)
            label:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
        else
            marker:Hide()
            Theme.Paint(highlight, { 0, 0, 0, 0 })
            label:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
        end
    end

    button:SetScript("OnEnter", function(self)
        if self.selected then return end
        Theme.Paint(highlight, Theme.color.rowHover)
        label:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    end)

    button:SetScript("OnLeave", function(self)
        self:SetSelected(self.selected)
    end)

    if onClick then button:SetScript("OnClick", onClick) end

    button.label = label
    button.phaseLabel = phase
    return button
end

-- --------------------------------------------------------------- Filterchip --

--- Kleiner Umschalter fuer Filterzeilen. Gedrueckt: goldener Grund.
function Widgets.Chip(parent, text, onToggle)
    local fonts = Theme.Fonts()

    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(17)

    local background = Theme.Fill(chip, { 0, 0, 0, 0 })
    local lines = Theme.Outline(chip, Theme.color.border)

    local label = Theme.Label(chip, string.upper(text), fonts.small, Theme.color.textDim)
    label:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chip:SetWidth(label:GetStringWidth() + 18)

    chip.pressed = false

    function chip:SetPressed(pressed)
        self.pressed = pressed and true or false
        if self.pressed then
            Theme.Paint(background, Theme.color.goldDeep)
            label:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
            for _, line in ipairs(lines) do Theme.Paint(line, Theme.color.goldDim) end
        else
            Theme.Paint(background, { 0, 0, 0, 0 })
            label:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
            for _, line in ipairs(lines) do Theme.Paint(line, Theme.color.border) end
        end
    end

    chip:SetScript("OnClick", function(self)
        self:SetPressed(not self.pressed)
        if onToggle then onToggle(self.pressed, self) end
    end)

    chip:SetScript("OnEnter", function(self)
        if self.pressed then return end
        label:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
    end)
    chip:SetScript("OnLeave", function(self) self:SetPressed(self.pressed) end)

    chip.label = label
    return chip
end

-- ------------------------------------------------------------- Suchfeld ------

--- Suchfeld. Zuerst Blizzards SearchBoxTemplate (Lupe, Platzhalter, X zum
--- Leeren — wie "Search Quest Log" im Questlog), sonst ein flaches EditBox.
--- Rueckgabe hat immer: .edit, :GetValue(), :Clear()
function Widgets.SearchBox(parent, placeholder, onChange)
    local fonts = Theme.Fonts()

    local native = Theme.CreateNative("EditBox", nil, parent, "SearchBoxTemplate")
    if native then
        native:SetHeight(20)
        native:SetAutoFocus(false)
        if native.Instructions then native.Instructions:SetText(placeholder or "") end
        -- Die Vorlage hat eigene OnTextChanged-Handler (Lupe, X-Knopf): nicht
        -- ueberschreiben, sondern dazuhaengen.
        native:HookScript("OnTextChanged", function(self)
            if onChange then onChange(self:GetText()) end
        end)
        native:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
        native.edit = native
        function native:GetValue() return self:GetText() end
        function native:Clear() self:SetText("") end
        return native
    end

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(18)
    Theme.Fill(holder, Theme.color.rowAltBg)
    Theme.Outline(holder, Theme.color.border)

    local edit = CreateFrame("EditBox", nil, holder)
    edit:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 0)
    edit:SetAutoFocus(false)
    edit:SetFontObject(fonts.row)
    edit:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])

    local hint = Theme.Label(holder, placeholder or "", fonts.row, Theme.color.textFaint)
    hint:SetPoint("LEFT", holder, "LEFT", 6, 0)

    local function updateHint()
        if edit:GetText() == "" and not edit:HasFocus() then hint:Show() else hint:Hide() end
    end

    edit:SetScript("OnTextChanged", function(self)
        updateHint()
        if onChange then onChange(self:GetText()) end
    end)
    edit:SetScript("OnEditFocusGained", updateHint)
    edit:SetScript("OnEditFocusLost", updateHint)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    holder.edit = edit
    function holder:GetValue() return edit:GetText() end
    function holder:Clear() edit:SetText("") end

    return holder
end

-- ------------------------------------------------------------- Reiter unten --

--- Reiter am unteren Fensterrand wie beim Charakterfenster ("Charakter |
--- Ruf | Waehrung"). Zuerst Blizzards Vorlage — PanelTabButtonTemplate (Retail
--- seit 10.0), davor CharacterFrameTabButtonTemplate — sonst ein gezeichneter
--- Reiter. Die Auswahl schaltet das Fenster ueber Widgets.SelectTab um.
--- @param owner Frame   das Fenster, an dem die Reiter haengen (braucht Namen)
--- @param index number  1-basiert; wird auch die Button-ID
function Widgets.Tab(owner, index, text, onClick)
    local name = owner:GetName() and (owner:GetName() .. "Tab" .. index) or nil

    local tab
    if type(_G.PanelTemplates_SetTab) == "function" then
        tab = Theme.CreateNative("Button", name, owner, "PanelTabButtonTemplate")
            or Theme.CreateNative("Button", name, owner, "CharacterFrameTabButtonTemplate")
    end

    if tab then
        tab.native = true
        tab:SetID(index)
        tab:SetText(text or "")
        if type(_G.PanelTemplates_TabResize) == "function" then
            pcall(PanelTemplates_TabResize, tab, 10)
        end

        -- DIE BREITE WIRD NACHGEMESSEN, NICHT ANGENOMMEN.
        --
        -- PanelTemplates_TabResize rechnet aus den Texturen der Vorlage. Wenn
        -- die fehlen oder nicht greifen, bleibt der Reiter breitenlos — und
        -- dann liegen alle Reiter uebereinander auf demselben Punkt, weil
        -- jeder rechts vom vorigen sitzt und "rechts" null Pixel weiter ist.
        --
        -- Genau das ist im Spiel passiert (gemessen 20.09.2026). Ob der
        -- Aufruf etwas bewirkt hat, verraet nur der Rueckgabewert von
        -- GetWidth — und der wird hier gelesen.
        local label = tab.Text or (name and _G[name .. "Text"])
        local needed = 28
        if label and label.GetStringWidth then
            needed = label:GetStringWidth() + 32
        end
        if (tab:GetWidth() or 0) < needed then
            tab:SetWidth(needed)
            tab.widthMeasured = true
        end

        if onClick then tab:SetScript("OnClick", onClick) end
        function tab:SetSelected() end  -- macht PanelTemplates_SetTab
        return tab
    end

    -- Rueckfall: flacher Reiter, gleiche Schnittstelle.
    local fonts = Theme.Fonts()
    tab = CreateFrame("Button", name, owner)
    tab.native = false
    tab:SetID(index)
    tab:SetHeight(24)

    local background = Theme.Fill(tab, Theme.color.sidebarBg)
    local lines = Theme.Outline(tab, Theme.color.border)
    local label = Theme.Label(tab, text or "", fonts.nav, Theme.color.textDim)
    label:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab:SetWidth(label:GetStringWidth() + 28)
    tab.label = label

    function tab:SetSelected(selected)
        self.selected = selected and true or false
        local color = self.selected and Theme.color.gold or Theme.color.textDim
        label:SetTextColor(color[1], color[2], color[3])
        Theme.Paint(background, self.selected and Theme.color.panelBg or Theme.color.sidebarBg)
        for _, line in ipairs(lines) do
            Theme.Paint(line, self.selected and Theme.color.goldDim or Theme.color.border)
        end
    end
    tab:SetScript("OnEnter", function(self)
        if not self.selected then label:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3]) end
    end)
    tab:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    if onClick then tab:SetScript("OnClick", onClick) end
    tab:SetSelected(false)
    return tab
end

--- Waehlt einen Reiter aus. Native Reiter ueber PanelTemplates (Blizzard
--- zeichnet aktiv/inaktiv selbst), gezeichnete ueber SetSelected.
--- @param tabs table  Liste der Reiter in Reihenfolge
function Widgets.SelectTab(owner, tabs, index)
    local native = tabs[1] and tabs[1].native
    if native and type(_G.PanelTemplates_SetNumTabs) == "function" then
        owner.Tabs = tabs
        pcall(PanelTemplates_SetNumTabs, owner, #tabs)
        local ok = pcall(PanelTemplates_SetTab, owner, index)
        if ok then return end
    end
    for i, tab in ipairs(tabs) do tab:SetSelected(i == index) end
end

-- ------------------------------------------------------------- Kontrollkaestchen

--- Kontrollkaestchen mit Beschriftung. Zuerst Blizzards UICheckButtonTemplate
--- (das goldene Haekchen aus den Optionen), sonst der Filterchip.
--- Rueckgabe hat immer: :SetChecked(bool), :GetChecked()
function Widgets.CheckBox(parent, text, onToggle)
    local box = Theme.CreateNative("CheckButton", nil, parent, "UICheckButtonTemplate")
    if box then
        box:SetWidth(26) box:SetHeight(26)

        -- DER HAKEN WIRD SELBST GEZEICHNET.
        --
        -- Zwei Anlaeufe ueber die Vorlage sind gescheitert (20.09.2026): erst
        -- der Haken der Vorlage, dann SetCheckedTexture mit dem Standardpfad.
        -- Der Rahmen kam beide Male, der Haken nie — der gespeicherte Wert
        -- stand nachweislich auf true, und Refresh lief nachweislich durch.
        --
        -- Woran es genau liegt, ist von innen nicht feststellbar: Ob eine
        -- Textur tatsaechlich Pixel auf den Bildschirm bringt, verraet keine
        -- API. Prueffbar ist nur, ob ein Objekt existiert — und das tat es.
        --
        -- Also nicht weiter raten. Eine eingefaerbte Flaeche ist die
        -- einfachste Zeichenoperation, die es gibt, und das ganze uebrige
        -- Design des Addons steht darauf (Panels, Raender, Auswahlbalken).
        -- Der Knopf bleibt Blizzards Knopf, der Zustand wird selbst gemalt.
        local mark = box:CreateTexture(nil, "OVERLAY")
        Theme.Paint(mark, Theme.color.goldBright)
        mark:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
        mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
        mark:Hide()
        box.mark = mark

        -- Die Haken-Textur der Vorlage wird unsichtbar gemacht, falls sie
        -- doch zeichnet: Zwei Markierungen uebereinander waeren schlimmer
        -- als keine.
        local native = box.GetCheckedTexture and box:GetCheckedTexture()
        if native and native.SetAlpha then native:SetAlpha(0) end

        local label = Theme.NativeText(box)
        if label then
            label:SetText(text or "")
            label:SetFontObject(GameFontHighlight)
            label:ClearAllPoints()
            label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        else
            label = Theme.Label(box, text or "", GameFontHighlight, Theme.color.text)
            label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        end
        box.label = label

        -- SetChecked wird ueberschrieben, damit JEDER Weg zum Zustand auch
        -- die Anzeige mitnimmt — der Aufruf aus Refresh genauso wie der Klick.
        local setChecked = box.SetChecked
        function box:SetChecked(value)
            value = value and true or false
            setChecked(self, value)
            if value then self.mark:Show() else self.mark:Hide() end
        end

        box:SetScript("OnClick", function(self)
            local checked = self:GetChecked() and true or false
            if checked then self.mark:Show() else self.mark:Hide() end
            if onToggle then onToggle(checked, self) end
        end)
        return box
    end

    local chip = Widgets.Chip(parent, text, onToggle)
    function chip:SetChecked(value) self:SetPressed(value) end
    function chip:GetChecked() return self.pressed end
    return chip
end

-- ------------------------------------------------------ Kopierbares Textfeld -

--- Fenster mit vorselektiertem Text. Der einzige Weg, etwas aus dem Spiel
--- herauszubekommen: Ein Addon kann nicht in die Zwischenablage schreiben
--- (docs/ARCHITECTURE.md, Grenze 2).
function Widgets.CopyDialog(title, text)
    local frame = Widgets._copyDialog

    if not frame then
        local fonts = Theme.Fonts()

        frame = CreateFrame("Frame", "GuildArmoryCopyDialog", UIParent)
        frame:SetWidth(560)
        frame:SetHeight(420)
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

        frame.title = Theme.Label(frame, "", fonts.title, Theme.color.heading)
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)

        local hint = Theme.Label(frame, "STRG+A, DANN STRG+C", fonts.small, Theme.color.textFaint)
        hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -15)

        local close = Widgets.Button(frame, "Schliessen", function() frame:Hide() end)
        close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)

        local box = CreateFrame("Frame", nil, frame)
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
        box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 44)
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
        edit:SetWidth(505)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        scroll:SetScrollChild(edit)

        frame.edit = edit
        frame:Hide()

        -- Mit ESC schliessbar machen.
        if type(_G.UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "GuildArmoryCopyDialog")
        end

        Widgets._copyDialog = frame
    end

    frame.title:SetText(string.upper(title or ""))
    frame.edit:SetText(text or "")
    frame.edit:HighlightText()
    frame.edit:SetFocus()
    frame:Show()

    return frame
end

-- --------------------------------------------------------- Eingabedialog -----

--- Wie CopyDialog, aber zum Einfuegen statt zum Kopieren.
--- Eigener Frame und nicht derselbe: Ein Dialog, der mal liest und mal schreibt,
--- verwechselt man beim Bedienen — und hier haengt an einem Fehlklick, dass eine
--- Strategie ueberschrieben wird.
function Widgets.InputDialog(title, hintText, onAccept)
    local frame = Widgets._inputDialog

    if not frame then
        local fonts = Theme.Fonts()

        frame = CreateFrame("Frame", "GuildArmoryInputDialog", UIParent)
        frame:SetWidth(560)
        frame:SetHeight(320)
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

        frame.title = Theme.Label(frame, "", fonts.title, Theme.color.heading)
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)

        frame.hint = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
        frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
        frame.hint:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        frame.hint:SetJustifyH("LEFT")

        local box = CreateFrame("Frame", nil, frame)
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -54)
        box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 44)
        Theme.Fill(box, Theme.color.rowAltBg)
        Theme.Outline(box, Theme.color.border)

        local scroll = CreateFrame("ScrollFrame", nil, box)
        scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
        scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(true)
        edit:SetFontObject(fonts.row)
        edit:SetTextColor(Theme.color.text[1], Theme.color.text[2], Theme.color.text[3])
        edit:SetWidth(505)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        scroll:SetScrollChild(edit)
        frame.edit = edit

        frame.status = Theme.Label(frame, "", fonts.small, Theme.color.bad)
        frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 20)
        frame.status:SetPoint("RIGHT", frame, "RIGHT", -180, 0)
        frame.status:SetJustifyH("LEFT")

        local cancel = Widgets.Button(frame, "Abbrechen", function() frame:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)

        frame.accept = Widgets.Button(frame, "Uebernehmen", function()
            if not frame.onAccept then frame:Hide() return end

            local ok, message = frame.onAccept(frame.edit:GetText())
            if ok then
                frame:Hide()
            else
                -- Fehlerhafte Eingabe schliesst den Dialog NICHT: Der eingefuegte
                -- Text soll erhalten bleiben, sonst muss der Nutzer ihn neu holen.
                frame.status:SetText(message or "Eingabe konnte nicht gelesen werden.")
            end
        end, "primary")
        frame.accept:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -6, 0)

        frame:Hide()

        if type(_G.UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "GuildArmoryInputDialog")
        end

        Widgets._inputDialog = frame
    end

    frame.title:SetText(string.upper(title or ""))
    frame.hint:SetText(hintText or "")
    frame.status:SetText("")
    frame.edit:SetText("")
    frame.onAccept = onAccept
    frame:Show()
    frame.edit:SetFocus()

    return frame
end
