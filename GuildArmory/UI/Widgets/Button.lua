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
--- Was jeder Knopf kann, egal ob Blizzard-Vorlage oder flach (07.10.2026,
--- Verfeinerungsplan 1 und 2):
---
---   button:SetTooltip(text)   Hilfetext, der IMMER gilt. Bis dahin erschien
---                             ein Tooltip nur an ausgegrauten Knoepfen
---                             (der Grund fuers Ausgrauen) — ein Knopf, der
---                             geht, erklaerte sich nicht.
---   button:SetConfirm(text)   Bestaetigung fuer Unwiderrufliches: Der erste
---                             Klick faerbt den Knopf rot und schreibt
---                             `text` darauf ("Wirklich?"), der zweite Klick
---                             binnen fuenf Sekunden tut es; sonst faellt
---                             der Knopf zurueck. Ein Muster fuer alle
---                             Stellen statt drei verschiedener.
---   button:SetAction(fn)      der Klick-Handler — statt SetScript, damit
---                             die Bestaetigung davor bleibt.
---   button:Disarm()           eine laufende Bestaetigung abbrechen, z. B.
---                             wenn eine wiederverwendete Zeile einen
---                             anderen Eintrag bekommt.
local CONFIRM_SECONDS = 5

local function decorate(button, text, onClick, paintDanger)
    button.baseText = text
    button.onConfirmed = onClick
    button.paintDanger = paintDanger

    function button:SetTooltip(tip) self.hint = tip end
    function button:SetAction(fn) self.onConfirmed = fn end
    function button:SetConfirm(tip) self.confirmText = tip if not tip then self:Disarm() end end

    function button:Disarm()
        if not self.armedAt then return end
        self.armedAt = nil
        self:SetLabel(self.baseText)
        if self.paintDanger then self:paintDanger(false) end
    end

    button:SetScript("OnClick", function(self, ...)
        if not self.confirmText then
            if self.onConfirmed then self.onConfirmed(self, ...) end
            return
        end
        local now = GA.Core.Compat.GetTime()
        if self.armedAt and now - self.armedAt < CONFIRM_SECONDS then
            self:Disarm()
            if self.onConfirmed then self.onConfirmed(self, ...) end
            return
        end
        self.armedAt = now
        self:SetLabel(self.confirmText)
        if self.paintDanger then self:paintDanger(true) end
        GA.Core.Compat.After(CONFIRM_SECONDS, function()
            if self.armedAt and GA.Core.Compat.GetTime() - self.armedAt >= CONFIRM_SECONDS then self:Disarm() end
        end)
    end)
end

function Widgets.Button(parent, text, onClick, variant, tooltip)
    local button = Widgets.NativeButton(parent, text, onClick, variant) or Widgets.FlatButton(parent, text, onClick, variant)
    if tooltip then button:SetTooltip(tooltip) end
    return button
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

    decorate(button, text, onClick, function(self, on)
        local fs = Theme.NativeText(self)
        if not fs then return end
        if on then fs:SetTextColor(Theme.color.bad[1], Theme.color.bad[2], Theme.color.bad[3])
        else fs:SetTextColor(1, 0.82, 0) end
    end)

    button:HookScript("OnEnter", function(self)
        local tip = self.tooltip or self.hint
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)

    function button:SetEnabledState(enabled, reason)
        if enabled then self:Enable() self.tooltip = nil
        else self:Disable() self.tooltip = reason end
    end

    function button:SetLabel(newText)
        if not self.armedAt then self.baseText = newText end
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

    -- Eigener Look: Metall in den Farben des Looks (Schmiede: Kupfer und
    -- Stahl; Twilight: Juwel und Tiefsee; Codex: Wachs und Pergament).
    local look = Theme.Look()
    local forge = look ~= nil
    local TINT = look and (isPrimary and look.btnPrimary or look.btnSecondary)
    local TINT_HOVER = look and (isPrimary and look.btnPrimaryHover or look.btnSecondaryHover)
    local background = Theme.Fill(button, isPrimary and Theme.color.goldDeep or { 0, 0, 0, 0 })
    if forge then Theme.Metal(background, TINT) end
    local lines = Theme.Outline(button, forge and look.btnLine
        or (isPrimary and Theme.color.goldDim or Theme.color.borderLit))

    local label = Theme.Label(button, string.upper(text or ""), fonts.small,
        isPrimary and (look and look.btnPrimaryText or Theme.color.goldBright)
        or (forge and Theme.color.text or Theme.color.goldMid))
    if forge and label.SetShadowOffset then
        -- Schatten nur, wo die Schrift hell ist: Tinte auf Pergament bekommt keinen.
        label:SetShadowOffset((isPrimary or not look.light) and 1 or 0, (isPrimary or not look.light) and -1 or 0)
    end
    label:SetPoint("CENTER", button, "CENTER", 0, 0)

    button:SetWidth(label:GetStringWidth() + 22)

    button:SetScript("OnEnter", function()
        if forge then Theme.Metal(background, TINT_HOVER)
        else Theme.Paint(background, isPrimary and Theme.color.goldDim or Theme.color.goldDeep) end
        label:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
        if not forge then for _, line in ipairs(lines) do Theme.Paint(line, Theme.color.goldDim) end end

        local tip = button.tooltip or button.hint
        if tip then
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function()
        if forge then Theme.Metal(background, TINT)
        else Theme.Paint(background, isPrimary and Theme.color.goldDeep or { 0, 0, 0, 0 }) end
        local color = isPrimary and Theme.color.goldBright or (forge and Theme.color.text or Theme.color.goldMid)
        if button.armedAt then color = Theme.color.bad end
        label:SetTextColor(color[1], color[2], color[3])
        if not forge then
            for _, line in ipairs(lines) do
                Theme.Paint(line, button.armedAt and Theme.color.bad or (isPrimary and Theme.color.goldDim or Theme.color.borderLit))
            end
        end
        GameTooltip:Hide()
    end)

    decorate(button, text, onClick, function(self, on)
        if on then
            label:SetTextColor(Theme.color.bad[1], Theme.color.bad[2], Theme.color.bad[3])
            for _, line in ipairs(lines) do Theme.Paint(line, Theme.color.bad) end
        else
            local color = isPrimary and Theme.color.goldBright or (forge and Theme.color.text or Theme.color.goldMid)
            label:SetTextColor(color[1], color[2], color[3])
            for _, line in ipairs(lines) do
                Theme.Paint(line, forge and look.btnLine or (isPrimary and Theme.color.goldDim or Theme.color.borderLit))
            end
        end
    end)

    button.label = label

    --- Deaktiviert den Knopf sichtbar. Wird z.B. fuer "Ready Check" gebraucht,
    --- wenn der Spieler nicht Raidleiter ist.
    function button:SetEnabledState(enabled, reason)
        if enabled then
            self:Enable()
            local color = isPrimary and Theme.color.goldBright
                or (Theme.Look() and Theme.color.text or Theme.color.goldMid)
            label:SetTextColor(color[1], color[2], color[3])
            self.tooltip = nil
        else
            self:Disable()
            label:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
            self.tooltip = reason
        end
    end

    function button:SetLabel(newText)
        if not self.armedAt then self.baseText = newText end
        label:SetText(string.upper(newText or ""))
        self:SetWidth(label:GetStringWidth() + 22)
    end

    return button
end

-- --------------------------------------------------------- Reiter (Sidebar) --

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

    --- Ein Symbol links vom Text (z.B. Discord). Ohne geladene Textur: nichts.
    function chip:SetIcon(path, tint)
        if not path then return end
        self.icon = self.icon or self:CreateTexture(nil, "OVERLAY")
        self.icon:SetTexture(path)
        self.icon:SetWidth(12) self.icon:SetHeight(12)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("LEFT", self, "LEFT", 7, 0)
        if tint then Theme.Tint(self.icon, tint) end
        label:ClearAllPoints()
        label:SetPoint("LEFT", self.icon, "RIGHT", 4, 0)
        self:SetWidth(label:GetStringWidth() + 18 + 16)
    end

    --- Eigene Farben fuer den gedrueckten Zustand (Standard: Gold).
    --- @param palette table|nil { fill = {r,g,b,a}, text = {r,g,b}, line = {r,g,b} }
    function chip:SetPalette(palette)
        self.palette = palette
        self:SetPressed(self.pressed)
    end

    function chip:SetPressed(pressed)
        self.pressed = pressed and true or false
        if self.pressed then
            local p = self.palette or {}
            local fill, text, edge = p.fill or Theme.color.goldDeep, p.text or Theme.color.goldBright, p.line or Theme.color.goldDim
            Theme.Paint(background, fill)
            label:SetTextColor(text[1], text[2], text[3])
            for _, line in ipairs(lines) do Theme.Paint(line, edge) end
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

    -- Eigener Look: ein Band statt Karteikarten. Kein Kasten; der gewaehlte
    -- Reiter traegt eine Linie und die Marke des Looks (Raute, Juwel, Siegel).
    local look = Theme.Look()
    local underline, mark, glow
    if look then
        -- Ueber dem Inhalt: Marke und Schein ragen unter den Reiter, und
        -- der Inhaltsbereich liegt auf derselben Ebene — er deckte sie zu.
        tab:SetFrameLevel((owner:GetFrameLevel() or 1) + 12)
        Theme.Paint(background, { 0, 0, 0, 0 })
        for _, line in ipairs(lines) do line:Hide() end
        underline = tab:CreateTexture(nil, "ARTWORK")
        underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 0)
        underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 0)
        underline:SetHeight(2)
        Theme.Paint(underline, look.markLine or Theme.color.gold)
        underline:Hide()
        -- DAS LEUCHTEN UNTER DEM REITER (Bild vom 05.10.2026: fehlte
        -- ueberall). Ein weicher Schein in der Farbe der Linie, additiv.
        local glowTex = Theme.Media("glow")
        if glowTex then
            glow = tab:CreateTexture(nil, "ARTWORK", nil, 1)
            glow:SetTexture(glowTex)
            pcall(glow.SetBlendMode, glow, "ADD")
            glow:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 2, -7)
            glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, -7)
            glow:SetHeight(16)
            local c = look.markLine or Theme.color.gold
            glow:SetVertexColor(c[1], c[2], c[3], look.light and 0.45 or 0.75)
            glow:Hide()
        end
        local markTex = look.mark and Theme.Media(look.mark.tex)
        if markTex then
            mark = tab:CreateTexture(nil, "OVERLAY")
            local size = look.mark.size or 11
            mark:SetWidth(size) mark:SetHeight(size)
            mark:SetPoint("CENTER", tab, "BOTTOM", 0, 1)
            mark:SetTexture(markTex)
            Theme.Tint(mark, look.mark.tint)
            mark:Hide()
        end
    end

    function tab:SetSelected(selected)
        self.selected = selected and true or false
        local look = Theme.Look()
        local color = self.selected and Theme.color.gold
            or (look and look.tabIdleText or Theme.color.textDim)
        label:SetTextColor(color[1], color[2], color[3])
        if look then
            if underline then underline:SetShown(self.selected) end
            if mark then mark:SetShown(self.selected) end
            if glow then glow:SetShown(self.selected) end
        else
            Theme.Paint(background, self.selected and Theme.color.panelBg or Theme.color.sidebarBg)
        end
        if not look then
            for _, line in ipairs(lines) do
                Theme.Paint(line, self.selected and Theme.color.goldDim or Theme.color.border)
            end
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

-- ----------------------------------------------------------- Schliessen-X ----

--- Das X oben rechts an einem eigenen Fenster. Blizzards Vorlagen bringen
--- eins mit; die eigenen Rahmen (alle Looks ausser "blizzard") hatten
--- keins — und ein Fenster ohne X sucht man zu.
--- @param onClick function|nil  Vorgabe: frame:Hide()
function Widgets.CloseX(frame, onClick)
    local fonts = Theme.Fonts()
    local button = CreateFrame("Button", nil, frame)
    button:SetWidth(20)
    button:SetHeight(20)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    button:SetFrameLevel(frame:GetFrameLevel() + 5)

    local label = Theme.Label(button, "X", fonts.rowBold, Theme.color.textDim)
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label = label

    button:SetScript("OnEnter", function()
        label:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
    end)
    button:SetScript("OnLeave", function()
        label:SetTextColor(Theme.color.textDim[1], Theme.color.textDim[2], Theme.color.textDim[3])
    end)
    button:SetScript("OnClick", function()
        if onClick then onClick() else frame:Hide() end
    end)
    frame.closeX = button
    return button
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
        hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -15)
        Widgets.CloseX(frame)

        local close = Widgets.Button(frame, GA.L.BTN_CLOSE, function() frame:Hide() end)
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
--- @param initialText string|nil  steht beim Oeffnen schon im Feld (zum Bearbeiten)
function Widgets.InputDialog(title, hintText, onAccept, initialText)
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
        Widgets.CloseX(frame)

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

        local cancel = Widgets.Button(frame, GA.L.BTN_CANCEL, function() frame:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)

        frame.accept = Widgets.Button(frame, GA.L.BTN_APPLY, function()
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
    frame.edit:SetText(initialText or "")
    frame.onAccept = onAccept
    frame:Show()
    frame.edit:SetFocus()
    if initialText and initialText ~= "" and frame.edit.SetCursorPosition then
        frame.edit:SetCursorPosition(#initialText)
    end

    return frame
end

-- ------------------------------------------------------- Schalter -----------

--- Ein Schalter: eine RUNDE Pille, rot ist aus, gruen ist an, der Knopf
--- wandert (Wunsch 29.09.2026: "runde Slider, rot fuer aus, gruen fuer an").
---
--- Das Spiel kennt keine abgerundeten Rahmen; die Rundung kommt aus einer
--- eigenen Textur (Media/Circle.tga, weisser Kreis mit weichem Rand): Die
--- Kappen der Pille sind ihre linke und rechte Haelfte, die Mitte ein
--- gefuelltes Rechteck, der Knopf der ganze Kreis — alle eingefaerbt.
--- Laedt die Textur nicht, wird die Pille eckig; sie bleibt bedienbar.
--- @param onToggle function(checked)
function Widgets.Switch(parent, onToggle)
    local W, H, KNOB = 46, 22, 16
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(W, H)
    local CIRCLE = Theme.RoundTexture()
    local round = CIRCLE ~= nil

    local function cap(side)
        local t = button:CreateTexture(nil, "BACKGROUND")
        t:SetSize(H / 2, H)
        if round then
            t:SetTexture(CIRCLE)
            if side == "LEFT" then t:SetTexCoord(0, 0.5, 0, 1) else t:SetTexCoord(0.5, 1, 0, 1) end
            t:SetPoint(side, button, side, 0, 0)
        else
            t:Hide()
        end
        return t
    end
    local left, right = cap("LEFT"), cap("RIGHT")
    local middle = button:CreateTexture(nil, "BACKGROUND")
    if round then
        middle:SetPoint("TOPLEFT", button, "TOPLEFT", H / 2, 0)
        middle:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -H / 2, 0)
    else
        middle:SetAllPoints(button)
    end
    local knob = button:CreateTexture(nil, "ARTWORK")
    knob:SetSize(KNOB, KNOB)
    if round then knob:SetTexture(CIRCLE) end
    button.checked = false
    button.enabled = true

    local function paint(self)
        local on = self.checked
        local color = on and Theme.color.good or Theme.color.bad
        -- Kappen und Knopf tragen die runde Textur: TOENEN. Die Mitte ist
        -- eine Flaeche ohne Textur: malen.
        if round then
            Theme.Tint(left, color)
            Theme.Tint(right, color)
        end
        Theme.Paint(middle, color)
        knob:ClearAllPoints()
        local inset = (H - KNOB) / 2
        if on then knob:SetPoint("RIGHT", self, "RIGHT", -inset, 0) else knob:SetPoint("LEFT", self, "LEFT", inset, 0) end
        if round then Theme.Tint(knob, { 0.96, 0.94, 0.88, 1 })
        else Theme.Paint(knob, { 0.96, 0.94, 0.88, 1 }) end
        self:SetAlpha(self.enabled and 1 or 0.45)
    end

    function button:SetChecked(on)
        self.checked = on and true or false
        paint(self)
    end
    function button:GetChecked() return self.checked end
    function button:SetEnabledState(enabled, reason)
        self.enabled = enabled and true or false
        self.tooltip = (not enabled) and reason or nil
        if enabled then self:Enable() else self:Disable() end
        paint(self)
    end
    button:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onToggle then onToggle(self.checked) end
    end)
    button:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    paint(button)
    return button
end

-- ------------------------------------------------------- Schieberegler -----

--- Ein Schieberegler des Spiels (Frame-Typ Slider), in unserer Kleidung:
--- schmale Rinne, goldener Knopf, der Wert daneben. Ohne Vorlage — der
--- Typ selbst reicht, und eine Vorlage, die es auf einer Linie nicht gibt,
--- waere ein Rahmen ohne Regler.
--- @param onChange function(value)  bei jedem Rasterschritt
function Widgets.Slider(parent, min, max, step, onChange)
    local fonts = Theme.Fonts()
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local track = Theme.Fill(slider, Theme.color.border)
    track:ClearAllPoints()
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(2)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(10, 16)
        thumb:SetVertexColor(Theme.color.goldMid[1], Theme.color.goldMid[2], Theme.color.goldMid[3], 1)
    end
    slider.value = Theme.Label(slider, "", fonts.body, Theme.color.goldMid)
    slider.value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    slider.format = "%d"
    local quiet = false
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / (step or 1) + 0.5) * (step or 1)
        self.value:SetText(string.format(self.format, value))
        if not quiet and onChange then onChange(value) end
    end)
    --- Setzt den Wert, ohne onChange auszuloesen — fuer Refresh.
    function slider:SetQuiet(value)
        quiet = true
        self:SetValue(value)
        self.value:SetText(string.format(self.format, value))
        quiet = false
    end
    return slider
end

-- ------------------------------------------------------- Sicherer Knopf -----

--- Ein Knopf, dessen Klick ein MAKRO des Spiels ausfuehrt — fuer Aufrufe,
--- die Addons nicht tun duerfen.
---
--- GEMESSEN 28.09.2026: GuildPromote lief aus dem Klick eines normalen
--- Knopfs und wurde vom Spiel geblockt ("blocked by Blizzard"), obwohl
--- CanGuildPromote ja sagte. Die Rechte hatte der Spieler; den Aufruf
--- darf nur Blizzards Code machen. Ein SecureActionButton ist Blizzards
--- Code: Der Klick darauf ist der des Spielers, und "/gpromote Name" als
--- Makrotext laeuft so, als haette er es eingetippt.
---
--- DAS MAKRO WIRD VOR DEM KLICK GESETZT, nicht beim Klick — im Klick ist
--- der Knopf nicht mehr unser Code. Und nicht im Kampf: Dort sind die
--- Attribute eines sicheren Rahmens gesperrt; SetMacro merkt sich den
--- Text dann und sagt es mit false.
---
--- GENAU EINE FLANKE, die der Client erwartet (Compat.SecureClickMode):
--- "AnyUp" allein tat auf diesem Client nichts (gemessen 28.09.2026),
--- weil die Vorlage per Einstellung auf "Down" hoert. Wer Down UND Up
--- anmeldet, laesst das Makro auf aelteren Vorlagen zweimal laufen —
--- und "/gpromote" zweimal ist zwei Raenge.
---
--- @return Button|nil  nil, wenn dieser Client die Vorlage nicht kennt
function Widgets.SecureMacroButton(parent, text, variant)
    local fonts = Theme.Fonts()
    local isPrimary = variant == "primary"

    local ok, button = pcall(CreateFrame, "Button", nil, parent, "SecureActionButtonTemplate")
    if not ok or type(button) ~= "table" or type(button.SetAttribute) ~= "function" then return nil end

    button:SetHeight(20)
    local background = Theme.Fill(button, isPrimary and Theme.color.goldDeep or { 0, 0, 0, 0 })
    local lines = Theme.Outline(button, isPrimary and Theme.color.goldDim or Theme.color.borderLit)
    local label = Theme.Label(button, string.upper(text or ""), fonts.small,
        isPrimary and Theme.color.goldBright or Theme.color.goldMid)
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetWidth(label:GetStringWidth() + 22)
    button.label = label

    local clickMode = GA.Core.Compat.SecureClickMode()
    pcall(button.RegisterForClicks, button, clickMode)
    pcall(button.SetAttribute, button, "useOnKeyDown", clickMode == "AnyDown")
    pcall(button.SetAttribute, button, "type", "macro")
    button.clickMode = clickMode

    local function inCombat()
        return type(_G.InCombatLockdown) == "function" and InCombatLockdown() and true or false
    end

    button:SetScript("OnEnter", function(self)
        if self.enabled ~= false then
            Theme.Paint(background, isPrimary and Theme.color.goldDim or Theme.color.goldDeep)
            label:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
        end
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        Theme.Paint(background, isPrimary and Theme.color.goldDeep or { 0, 0, 0, 0 })
        if self.enabled ~= false then
            local color = isPrimary and Theme.color.goldBright or Theme.color.goldMid
            label:SetTextColor(color[1], color[2], color[3])
        end
        GameTooltip:Hide()
    end)
    -- Nach dem Klick — das Makro ist dann gelaufen — darf unser Code wieder.
    button:SetScript("PostClick", function(self)
        if self.onAfter then self.onAfter(self) end
    end)

    function button:SetMacro(macrotext)
        self.macro = macrotext
        if inCombat() then return false end
        pcall(self.SetAttribute, self, "macrotext", macrotext or "")
        return true
    end

    function button:SetEnabledState(enabled, reason)
        self.enabled = enabled and true or false
        if inCombat() then return end
        if enabled then
            pcall(self.Enable, self)
            local color = isPrimary and Theme.color.goldBright or Theme.color.goldMid
            label:SetTextColor(color[1], color[2], color[3])
            if self.icon then self.icon:SetAlpha(1) end
            self.tooltip = self.hint
        else
            pcall(self.Disable, self)
            label:SetTextColor(Theme.color.textFaint[1], Theme.color.textFaint[2], Theme.color.textFaint[3])
            if self.icon then self.icon:SetAlpha(0.3) end
            self.tooltip = reason
        end
    end

    function button:SetLabel(newText)
        label:SetText(string.upper(newText or ""))
        self:SetWidth(label:GetStringWidth() + 22)
    end

    --- Ein Bild statt Schrift — nur, wenn die Textur WIRKLICH laedt; sonst
    --- bleibt der Ersatztext stehen, und der Knopf sagt es mit false.
    function button:SetIcon(path, size, fallbackText)
        size = size or 12
        if not Theme.TextureExists(path) then
            label:SetText(fallbackText or "")
            return false
        end
        if not self.icon then
            self.icon = self:CreateTexture(nil, "ARTWORK")
            self.icon:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
        self.icon:SetTexture(path)
        self.icon:SetSize(size, size)
        self.icon:SetAlpha(self.enabled == false and 0.3 or 1)
        label:SetText("")
        return true
    end

    return button
end
