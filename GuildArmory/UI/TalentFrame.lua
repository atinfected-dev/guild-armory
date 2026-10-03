--[[----------------------------------------------------------------------------
    UI/TalentFrame — der nachgebaute Talentbaum eines Mitglieds.

    Aufgebaut wie das Talentfenster von Forever (Bild 03.10.2026): die Baeume
    der Klasse nebeneinander, jeder mit rundem Symbol, Namen und seinen
    Punkten oben, darunter die Talente im Raster. Die Rahmen sagen den Stand
    wie im Spiel: gold = voll, gruen = teilweise, hell = offen, grau = noch
    gesperrt. Unten rechts am Symbol der Rang, oben links der hoechste.

    Das Fenster liest nur (siehe Armory/Talents: warum nicht Blizzards
    Talentfenster). Was fehlt, sagt es mit dem Grund, statt leer zu bleiben.
------------------------------------------------------------------------------]]

local _, GA = ...

local TalentFrame = {}
GA.UI.TalentFrame = TalentFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

local ICON = 38
local CELL_X, CELL_Y = 58, 56
local HEAD = 70
local TREE_PAD = 26
local PAD = 16
local TOP = 58
local FOOT = 46

local STATE_COLOR = {
    max     = { 0.95, 0.78, 0.20 },
    partial = { 0.30, 0.88, 0.38 },
    open    = { 0.40, 0.39, 0.36 },   -- nicht geskillt: grau wie gesperrt, nur heller umrandet (Wunsch 03.10.2026)
    locked  = { 0.22, 0.21, 0.19 },
}

-- ================================================================ Rahmen ------

function TalentFrame:Create()
    if self.frame then return self.frame end
    local fonts = Theme.Fonts()

    local frame = CreateFrame("Frame", "GuildArmoryTalentFrame", UIParent)
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

    frame.crest = frame:CreateTexture(nil, "ARTWORK")
    frame.crest:SetWidth(32) frame.crest:SetHeight(32)
    frame.crest:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)

    frame.title = Theme.Label(frame, "", fonts.title, Theme.color.heading)
    frame.title:SetPoint("TOPLEFT", frame.crest, "TOPRIGHT", 10, -1)
    frame.sub = Theme.Label(frame, "", fonts.small, Theme.color.textDim)
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)

    frame.points = Theme.Label(frame, "", fonts.big, Theme.color.goldBright)
    frame.points:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -14)
    frame.pointsLabel = Theme.Label(frame, L.TALENTS_POINTS, fonts.small, Theme.color.textDim)
    frame.pointsLabel:SetPoint("RIGHT", frame.points, "LEFT", -8, 0)

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
    Theme.Fill(frame.body, { 0.03, 0.03, 0.03, 1 })
    Theme.Outline(frame.body, Theme.color.border)

    -- Die Pfeile auf eigener Ebene: ueber den Baumflaechen (Kinder der
    -- Grundflaeche, die ihre Linien sonst verdeckten), unter den Kacheln.
    frame.lineLayer = CreateFrame("Frame", nil, frame.body)
    frame.lineLayer:SetAllPoints(frame.body)
    frame.lineLayer:SetFrameLevel(frame.body:GetFrameLevel() + 3)

    frame.message = Theme.Label(frame.body, "", fonts.body, Theme.color.textDim)
    frame.message:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 24, -24)
    frame.message:SetPoint("RIGHT", frame.body, "RIGHT", -24, 0)
    frame.message:SetJustifyH("LEFT")
    frame.message:SetSpacing(4)

    frame.foot = Theme.Label(frame, "", fonts.small, Theme.color.textFaint)
    frame.foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 17)
    frame.foot:SetPoint("RIGHT", frame, "RIGHT", -110, 0)
    frame.foot:SetJustifyH("LEFT")
    frame.foot:SetWordWrap(false)

    local close = Widgets.Button(frame, L.BTN_CLOSE, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)

    frame.trees, frame.nodes, frame.lines = {}, {}, {}
    frame:Hide()
    if type(_G.UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildArmoryTalentFrame") end
    self.frame = frame
    return frame
end

--- Ein Baumfeld: Hintergrund, Kopf mit rundem Symbol, Name und Punkten.
function TalentFrame:Tree(index)
    local frame = self.frame
    if frame.trees[index] then return frame.trees[index] end
    local fonts = Theme.Fonts()
    local tree = CreateFrame("Frame", nil, frame.body)

    tree.bg = {}
    for _, key in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
        local tex = tree:CreateTexture(nil, "BACKGROUND", nil, 1)
        tex:Hide()
        tree.bg[key] = tex
    end
    tree.atlas = tree:CreateTexture(nil, "BACKGROUND", nil, 1)
    tree.atlas:SetAllPoints(tree)
    tree.atlas:Hide()
    tree.tint = Theme.Fill(tree, { 0, 0, 0, 0 }, "BACKGROUND")
    tree.shade = tree:CreateTexture(nil, "BACKGROUND", nil, 2)
    tree.shade:SetAllPoints(tree)
    Theme.Paint(tree.shade, { 0, 0, 0, 0.35 })

    tree.divider = tree:CreateTexture(nil, "BORDER")
    tree.divider:SetWidth(1)
    tree.divider:SetPoint("TOPRIGHT", tree, "TOPRIGHT", 0, 0)
    tree.divider:SetPoint("BOTTOMRIGHT", tree, "BOTTOMRIGHT", 0, 0)
    Theme.Paint(tree.divider, Theme.color.border)

    tree.icon = tree:CreateTexture(nil, "ARTWORK")
    tree.icon:SetWidth(36) tree.icon:SetHeight(36)
    tree.ring = tree:CreateTexture(nil, "OVERLAY")
    tree.ring:SetWidth(46) tree.ring:SetHeight(46)
    tree.ring:SetPoint("CENTER", tree.icon, "CENTER", 0, 0)
    pcall(tree.ring.SetTexture, tree.ring, "Interface\\Minimap\\MiniMap-TrackingBorder")
    pcall(tree.ring.SetTexCoord, tree.ring, 0, 0.6, 0, 0.6)
    if Theme.RoundTexture and Theme.RoundTexture() then
        pcall(tree.icon.SetMask, tree.icon, Theme.RoundTexture())
    end

    tree.badge = CreateFrame("Frame", nil, tree)
    tree.badge:SetWidth(22) tree.badge:SetHeight(15)
    tree.badge:SetPoint("BOTTOMLEFT", tree.icon, "BOTTOMRIGHT", -8, -4)
    tree.badge:SetFrameLevel(tree:GetFrameLevel() + 2)
    Theme.Fill(tree.badge, { 0.05, 0.05, 0.05, 0.95 })
    Theme.Outline(tree.badge, Theme.color.goldDim)
    tree.badgeText = Theme.Label(tree.badge, "", fonts.small, Theme.color.goldBright)
    tree.badgeText:SetPoint("CENTER", tree.badge, "CENTER", 0, 0)

    tree.name = Theme.Label(tree, "", fonts.big, Theme.color.text)
    tree.name:SetPoint("LEFT", tree.icon, "RIGHT", 16, 0)

    tree.line = tree:CreateTexture(nil, "ARTWORK")
    tree.line:SetHeight(1)
    tree.line:SetPoint("TOPLEFT", tree, "TOPLEFT", 14, -HEAD + 6)
    tree.line:SetPoint("TOPRIGHT", tree, "TOPRIGHT", -14, -HEAD + 6)
    Theme.Paint(tree.line, { 0.79, 0.64, 0.29, 0.45 })

    frame.trees[index] = tree
    return tree
end

--- Hintergrund eines Baums: das klassische Bild aus vier Teilen, ein Atlas,
--- oder ein dunkler Grund in Klassenfarbe.
local function paintBackground(tree, bg, classColor)
    for _, tex in pairs(tree.bg) do tex:Hide() end
    tree.atlas:Hide()
    Theme.Paint(tree.tint, { classColor[1] * 0.18, classColor[2] * 0.18, classColor[3] * 0.18, 1 })
    if not bg then return end

    local base = "Interface\\TalentFrame\\" .. bg
    if Theme.TextureExists(base .. "-TopLeft") then
        local w, h = tree:GetWidth(), tree:GetHeight()
        local left, top = w * 0.8, h * 0.667
        local parts = {
            TopLeft     = { 0, 0, left, top },
            TopRight    = { left, 0, w - left, top },
            BottomLeft  = { 0, top, left, h - top },
            BottomRight = { left, top, w - left, h - top },
        }
        for key, rect in pairs(parts) do
            local tex = tree.bg[key]
            if pcall(tex.SetTexture, tex, base .. "-" .. key) then
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", tree, "TOPLEFT", rect[1], -rect[2])
                tex:SetWidth(rect[3]) tex:SetHeight(rect[4])
                tex:Show()
            end
        end
        return
    end
    local textureApi = _G.C_Texture
    if type(textureApi) == "table" and type(textureApi.GetAtlasInfo) == "function" then
        local ok, info = pcall(textureApi.GetAtlasInfo, bg)
        if ok and info and pcall(tree.atlas.SetAtlas, tree.atlas, bg) then tree.atlas:Show() end
    end
end

--- Eine Talentkachel.
function TalentFrame:Node(index)
    local frame = self.frame
    if frame.nodes[index] then return frame.nodes[index] end
    local fonts = Theme.Fonts()
    local node = CreateFrame("Button", nil, frame.body)
    node:SetWidth(ICON) node:SetHeight(ICON)
    node:SetFrameLevel(frame.body:GetFrameLevel() + 5)
    node.border = Theme.Fill(node, STATE_COLOR.locked, "BACKGROUND")
    node.inner = node:CreateTexture(nil, "BORDER")
    node.inner:SetPoint("TOPLEFT", node, "TOPLEFT", 2, -2)
    node.inner:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", -2, 2)
    Theme.Paint(node.inner, { 0, 0, 0, 1 })
    node.icon = node:CreateTexture(nil, "ARTWORK")
    node.icon:SetPoint("TOPLEFT", node, "TOPLEFT", 3, -3)
    node.icon:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", -3, 3)
    pcall(node.icon.SetTexCoord, node.icon, 0.08, 0.92, 0.08, 0.92)

    node.rankBox = CreateFrame("Frame", nil, node)
    node.rankBox:SetWidth(14) node.rankBox:SetHeight(14)
    node.rankBox:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 2, -2)
    node.rankBox:SetFrameLevel(node:GetFrameLevel() + 2)
    node.rankFill = Theme.Fill(node.rankBox, { 0, 0, 0, 0.9 })
    node.rank = Theme.Label(node.rankBox, "", fonts.small, Theme.color.goldBright)
    node.rank:SetPoint("CENTER", node.rankBox, "CENTER", 0, 0)

    node.maxText = Theme.Label(node, "", fonts.small, Theme.color.textDim)
    node.maxText:SetPoint("BOTTOMLEFT", node, "TOPLEFT", -2, -8)

    node:SetScript("OnEnter", function(self)
        if not self.spellID or self.spellID == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
        if not ok then GameTooltip:AddLine(Compat.GetSpellName(self.spellID) or tostring(self.spellID), 1, 1, 1) end
        GameTooltip:AddLine(string.format(L.TALENTS_RANK, self.rankNow or 0, self.rankMax or 1), 0.9, 0.8, 0.5)
        if self.alternative then
            GameTooltip:AddLine(string.format(L.TALENTS_CHOICE, Compat.GetSpellName(self.alternative) or "?"), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    node:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.nodes[index] = node
    return node
end

function TalentFrame:Line(index)
    local frame = self.frame
    if frame.lines[index] then return frame.lines[index] end
    if type(frame.lineLayer.CreateLine) ~= "function" then return nil end
    local ok, line = pcall(frame.lineLayer.CreateLine, frame.lineLayer, nil, "ARTWORK")
    if not ok or not line then return nil end
    pcall(line.SetThickness, line, 2)
    frame.lines[index] = line
    return line
end

local function clear(frame)
    for _, t in ipairs(frame.trees) do t:Hide() end
    for _, n in ipairs(frame.nodes) do n:Hide() end
    for _, l in ipairs(frame.lines) do l:Hide() end
    frame.message:SetText("")
end

-- ================================================================ Zeigen -----

function TalentFrame:Show(character)
    local frame = self:Create()
    clear(frame)

    local cr, cg, cb = Util.ClassColor(character.class)
    frame.title:SetText(character.name or "?")
    frame.title:SetTextColor(cr, cg, cb)
    if character.class and Theme.SetClassPortrait(frame.crest, character.class) then frame.crest:Show() else frame.crest:Hide() end

    local Talents = GA.Modules.Talents
    local build, grund, specID = Talents:BuildOf(character)
    specID = build and build.specID or specID or character.specID
    local spec = Compat.GetSpecInfo(specID)
    local teile = {}
    if spec then teile[#teile + 1] = spec.name end
    if character.level then teile[#teile + 1] = string.format(L.LEVEL_FMT, tostring(character.level)) end
    frame.sub:SetText(table.concat(teile, " · "))

    local ts = build and build.ts or (character.loadout and character.loadout.ts)
    local quelle = build and build.own and L.TALENTS_SRC_SELF
        or ((character.loadout and character.loadout.source == "inspect") and L.TALENTS_SRC_INSPECT or L.TALENTS_SRC_SYNC)
    local foot = ts and string.format(L.TALENTS_FOOT, Util.TimeAgo(ts), quelle) or ""
    local measured = GA.Core.Database.account.measured
    if measured and measured.talentDecoder and measured.talentDecoder.ok == false and build and not build.own then
        foot = foot .. "  |cffd9a441" .. L.TALENTS_DECODER_WARN .. "|r"
    end
    frame.foot:SetText(foot)

    local grid = build and Talents.Grid(build.layout)
    if not build or not grid then
        frame.points:SetText("")
        frame:SetWidth(560) frame:SetHeight(TOP + 200 + FOOT)
        frame.body:SetWidth(560 - 2 * PAD) frame.body:SetHeight(200)
        frame.message:SetText(build and L.TALENTS_NO_NOLAYOUT
            or (L["TALENTS_NO_" .. string.upper(tostring(grund))] or L.TALENTS_NO_GENERIC))
        frame:Show()
        return
    end

    local states, points = Talents.States(build.layout, grid, build.picks)

    -- Groesse aus dem Raster: Baeume nebeneinander, gleich hoch.
    local treeH = HEAD + grid.rows * CELL_Y + 18
    local x = 0
    local origin = {}
    for i, t in ipairs(grid.trees) do
        local w = math.max(4, t.cols) * CELL_X + 2 * TREE_PAD
        local tree = self:Tree(i)
        tree:ClearAllPoints()
        tree:SetPoint("TOPLEFT", frame.body, "TOPLEFT", x, 0)
        tree:SetWidth(w) tree:SetHeight(treeH)
        local tab = build.layout.tabs and build.layout.tabs[i] or {}
        paintBackground(tree, tab.bg, { cr, cg, cb })
        tree.icon:ClearAllPoints()
        tree.icon:SetPoint("TOPLEFT", tree, "TOPLEFT", math.max(18, w / 2 - 70), -16)
        local atlas = type(tab.icon) == "string" and string.match(tab.icon, "^atlas:(.+)$")
        if atlas then pcall(tree.icon.SetAtlas, tree.icon, atlas)
        elseif tab.icon then pcall(tree.icon.SetTexture, tree.icon, tab.icon)
        else Theme.Paint(tree.icon, Theme.color.border) end
        tree.name:SetText(tab.name or string.format(L.TALENTS_TREE_N, i))
        tree.badgeText:SetText(tostring(points[i] or 0))
        tree.divider:SetShown(i < #grid.trees)
        tree:Show()
        origin[i] = { x = x + TREE_PAD + (CELL_X - ICON) / 2 + ((math.max(4, t.cols) - t.cols) * CELL_X) / 2, w = w }
        x = x + w
    end
    frame.body:SetWidth(x) frame.body:SetHeight(treeH)
    frame:SetWidth(x + 2 * PAD) frame:SetHeight(TOP + treeH + FOOT)

    local function cell(node)
        local o = origin[node.tree]
        return o.x + (node.col - 1) * CELL_X, -(HEAD + 6 + (node.row - 1) * CELL_Y)
    end

    -- Pfeile unter den Kacheln: vom unteren Rand der Quelle zum oberen des Ziels.
    local byID = {}
    for _, node in ipairs(build.layout.nodes) do byID[node.id] = node end
    local li = 0
    for _, node in ipairs(build.layout.nodes) do
        if node.visible then
            for _, target in ipairs(node.edges or {}) do
                local other = byID[target]
                if other and other.visible and other.tree == node.tree then
                    li = li + 1
                    local line = self:Line(li)
                    if line then
                        local x1, y1 = cell(node)
                        local x2, y2 = cell(other)
                        local sx, sy = x1 + ICON / 2, y1 - ICON
                        local ex, ey = x2 + ICON / 2, y2
                        if other.row == node.row then sx, sy, ex, ey = x1 + ICON, y1 - ICON / 2, x2, y2 - ICON / 2 end
                        pcall(line.SetStartPoint, line, "TOPLEFT", frame.body, sx, sy)
                        pcall(line.SetEndPoint, line, "TOPLEFT", frame.body, ex, ey)
                        local an = states[node.id] == "max"
                        local c = an and STATE_COLOR.max or { 0.35, 0.33, 0.30 }
                        pcall(line.SetColorTexture, line, c[1], c[2], c[3], an and 0.95 or 0.8)
                        line:Show()
                    end
                end
            end
        end
    end

    local index, gesamt = 0, 0
    for _, node in ipairs(build.layout.nodes) do
        if node.visible and node.tree then
            index = index + 1
            local button = self:Node(index)
            local bx, by = cell(node)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame.body, "TOPLEFT", bx, by)
            local pick = build.picks[node.id]
            local chosen = pick and pick.chosen or 1
            local spellID = node.spells[chosen] or node.spells[1]
            button.spellID = spellID
            button.alternative = node.choice and node.spells[chosen == 1 and 2 or 1] or nil
            button.rankMax = node.max or 1
            button.rankNow = pick and (pick.granted and node.max or pick.rank) or 0
            local state = states[node.id] or "locked"
            local icon = Compat.GetSpellIcon(spellID)
            if icon then pcall(button.icon.SetTexture, button.icon, icon) else Theme.Paint(button.icon, Theme.color.border) end
            -- Nicht geskillt ist grau, offen nur etwas heller als gesperrt.
            local grau = state == "locked" or state == "open"
            if button.icon.SetDesaturated then pcall(button.icon.SetDesaturated, button.icon, grau) end
            button.icon:SetAlpha(state == "locked" and 0.4 or (state == "open" and 0.7 or 1))
            Theme.Paint(button.border, STATE_COLOR[state])

            if button.rankNow > 0 then
                local c = STATE_COLOR[state]
                button.rank:SetText(tostring(button.rankNow))
                button.rank:SetTextColor(c[1], c[2], c[3])
                button.rankBox:Show()
            else
                button.rankBox:Hide()
            end
            button.maxText:SetText((node.max or 1) > 1 and tostring(node.max) or "")
            if pick and not pick.granted then gesamt = gesamt + (pick.rank or 0) end
            button:Show()
        end
    end

    frame.points:SetText(tostring(gesamt))
    frame:Show()
end

function TalentFrame:Toggle(character)
    if self.frame and self.frame:IsShown() and self.shownGuid == character.guid then
        self.frame:Hide()
        return
    end
    self.shownGuid = character.guid
    self:Show(character)
end
