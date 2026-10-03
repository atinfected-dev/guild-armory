--[[----------------------------------------------------------------------------
    UI/TalentFrame — der nachgebaute Talentbaum eines Mitglieds.

    Ein eigenes Fenster, das nur liest (siehe Armory/Talents: warum nicht
    Blizzards Talentfenster). Die Knoten stehen an der Stelle, die das Spiel
    ihnen im Baum gibt, verkleinert auf das Fenster; die Verbindungen sind
    Linien, gekaufte Knoten leuchten, ungekaufte sind grau. Hover zeigt den
    Zauber mit dem Tooltip des Spiels.

    Was fehlt, sagt das Fenster — mit dem Grund, statt leer zu bleiben.
------------------------------------------------------------------------------]]

local _, GA = ...

local TalentFrame = {}
GA.UI.TalentFrame = TalentFrame

local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

local ICON = 30
local AREA_W, AREA_H = 620, 520
local PAD = 18

function TalentFrame:Create()
    if self.frame then return self.frame end
    local fonts = Theme.Fonts()

    local frame = CreateFrame("Frame", "GuildArmoryTalentFrame", UIParent)
    frame:SetWidth(AREA_W + 2 * PAD)
    frame:SetHeight(AREA_H + 96)
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
    frame.sub:SetPoint("RIGHT", frame, "RIGHT", -110, 0)
    frame.sub:SetJustifyH("LEFT")
    frame.sub:SetWordWrap(false)

    frame.points = Theme.Label(frame, "", fonts.big, Theme.color.goldBright)
    frame.points:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -14)
    frame.pointsLabel = Theme.Label(frame, L.TALENTS_POINTS, fonts.small, Theme.color.textDim)
    frame.pointsLabel:SetPoint("TOPRIGHT", frame.points, "BOTTOMRIGHT", 0, -2)

    local area = CreateFrame("Frame", nil, frame)
    area:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -60)
    area:SetWidth(AREA_W) area:SetHeight(AREA_H)
    Theme.Fill(area, Theme.color.rowAltBg)
    Theme.Outline(area, Theme.color.border)
    frame.area = area
    frame.nodes = {}
    frame.lines = {}

    frame.message = Theme.Label(area, "", fonts.body, Theme.color.textDim)
    frame.message:SetPoint("TOPLEFT", area, "TOPLEFT", 20, -20)
    frame.message:SetPoint("RIGHT", area, "RIGHT", -20, 0)
    frame.message:SetJustifyH("LEFT")
    frame.message:SetSpacing(4)

    frame.foot = Theme.Label(frame, "", fonts.small, Theme.color.textFaint)
    frame.foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 16)
    frame.foot:SetPoint("RIGHT", frame, "RIGHT", -110, 0)
    frame.foot:SetJustifyH("LEFT")

    local close = Widgets.Button(frame, L.BTN_CLOSE, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)

    frame:Hide()
    if type(_G.UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildArmoryTalentFrame") end
    self.frame = frame
    return frame
end

--- Ein Knoten: Rahmen, Symbol, Rang.
function TalentFrame:Node(index)
    local frame = self.frame
    local node = frame.nodes[index]
    if node then return node end
    local fonts = Theme.Fonts()
    node = CreateFrame("Button", nil, frame.area)
    node:SetWidth(ICON) node:SetHeight(ICON)
    node:SetFrameLevel(frame.area:GetFrameLevel() + 3)
    node.border = Theme.Fill(node, Theme.color.border, "BACKGROUND")
    node.icon = node:CreateTexture(nil, "ARTWORK")
    node.icon:SetPoint("TOPLEFT", node, "TOPLEFT", 2, -2)
    node.icon:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", -2, 2)
    pcall(node.icon.SetTexCoord, node.icon, 0.08, 0.92, 0.08, 0.92)
    node.rank = Theme.Label(node, "", fonts.small, Theme.color.goldBright)
    node.rank:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 3, -3)
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

--- Eine Verbindungslinie, wenn der Client Linien kann.
function TalentFrame:Line(index)
    local frame = self.frame
    if frame.lines[index] then return frame.lines[index] end
    if type(frame.area.CreateLine) ~= "function" then return nil end
    local ok, line = pcall(frame.area.CreateLine, frame.area, nil, "BORDER")
    if not ok or not line then return nil end
    pcall(line.SetThickness, line, 2)
    frame.lines[index] = line
    return line
end

local function clear(frame)
    for _, node in ipairs(frame.nodes) do node:Hide() end
    for _, line in ipairs(frame.lines) do line:Hide() end
end

--- Zeigt die Talente eines Charakters.
function TalentFrame:Show(character)
    local frame = self:Create()
    clear(frame)
    frame.message:SetText("")

    local r, g, b = Util.ClassColor(character.class)
    frame.title:SetText(character.name or "?")
    frame.title:SetTextColor(r, g, b)
    if character.class and Theme.SetClassPortrait(frame.crest, character.class) then frame.crest:Show() else frame.crest:Hide() end

    local Talents = GA.Modules.Talents
    local build, grund, specID = Talents:BuildOf(character)
    specID = build and build.specID or specID or character.specID
    local spec = Compat.GetSpecInfo(specID)
    local teile = {}
    if spec then teile[#teile + 1] = spec.name end
    if character.level then teile[#teile + 1] = string.format(L.LEVEL_FMT, tostring(character.level)) end
    frame.sub:SetText(table.concat(teile, " · "))

    -- Herkunft und Alter: die Regel des Addons.
    local ts = build and build.ts or (character.loadout and character.loadout.ts)
    local quelle = build and build.own and L.TALENTS_SRC_SELF
        or ((character.loadout and character.loadout.source == "inspect") and L.TALENTS_SRC_INSPECT or L.TALENTS_SRC_SYNC)
    frame.foot:SetText(ts and string.format(L.TALENTS_FOOT, Util.TimeAgo(ts), quelle) or "")
    local measured = GA.Core.Database.account.measured
    if measured and measured.talentDecoder and measured.talentDecoder.ok == false and build and not build.own then
        frame.foot:SetText(frame.foot:GetText() .. "  |cffd9a441" .. L.TALENTS_DECODER_WARN .. "|r")
    end

    if not build then
        frame.points:SetText("")
        frame.message:SetText(L["TALENTS_NO_" .. string.upper(tostring(grund))] or L.TALENTS_NO_GENERIC)
        frame:Show()
        return
    end

    -- Lage: das Feld der sichtbaren Knoten auf die Flaeche abbilden.
    local minX, minY, maxX, maxY
    for _, node in ipairs(build.layout.nodes) do
        if node.visible then
            minX = math.min(minX or node.x, node.x) maxX = math.max(maxX or node.x, node.x)
            minY = math.min(minY or node.y, node.y) maxY = math.max(maxY or node.y, node.y)
        end
    end
    if not minX then
        frame.message:SetText(L.TALENTS_NO_NOLAYOUT)
        frame:Show()
        return
    end
    local spanX, spanY = math.max(1, maxX - minX), math.max(1, maxY - minY)
    local scale = math.min((AREA_W - 2 * ICON) / spanX, (AREA_H - 2 * ICON) / spanY)
    local offX = (AREA_W - spanX * scale) / 2
    local offY = (AREA_H - spanY * scale) / 2
    local function place(node)
        return offX + (node.x - minX) * scale, -(offY + (node.y - minY) * scale)
    end

    local byID, punkte = {}, 0
    for _, node in ipairs(build.layout.nodes) do byID[node.id] = node end

    -- Linien zuerst, unter den Knoten.
    local lineIndex = 0
    for _, node in ipairs(build.layout.nodes) do
        if node.visible then
            for _, target in ipairs(node.edges or {}) do
                local other = byID[target]
                if other and other.visible then
                    lineIndex = lineIndex + 1
                    local line = self:Line(lineIndex)
                    if line then
                        local x1, y1 = place(node)
                        local x2, y2 = place(other)
                        pcall(line.SetStartPoint, line, "TOPLEFT", frame.area, x1, y1)
                        pcall(line.SetEndPoint, line, "TOPLEFT", frame.area, x2, y2)
                        local an = build.picks[node.id] and build.picks[target]
                        local c = an and Theme.color.gold or Theme.color.border
                        pcall(line.SetColorTexture, line, c[1], c[2], c[3], an and 0.9 or 0.6)
                        line:Show()
                    end
                end
            end
        end
    end

    local index = 0
    for _, node in ipairs(build.layout.nodes) do
        if node.visible then
            index = index + 1
            local button = self:Node(index)
            local x, y = place(node)
            button:ClearAllPoints()
            button:SetPoint("CENTER", frame.area, "TOPLEFT", x, y)
            local pick = build.picks[node.id]
            local chosen = pick and pick.chosen or 1
            local spellID = node.spells[chosen] or node.spells[1]
            button.spellID = spellID
            button.alternative = node.choice and node.spells[chosen == 1 and 2 or 1] or nil
            button.rankMax = node.max or 1
            button.rankNow = pick and (pick.granted and node.max or pick.rank) or 0
            local icon = Compat.GetSpellIcon(spellID)
            if icon then pcall(button.icon.SetTexture, button.icon, icon) else Theme.Paint(button.icon, Theme.color.border) end
            local an = pick ~= nil
            if button.icon.SetDesaturated then pcall(button.icon.SetDesaturated, button.icon, not an) end
            button.icon:SetAlpha(an and 1 or 0.45)
            Theme.Paint(button.border, an and Theme.color.gold or Theme.color.border)
            if (node.max or 1) > 1 or an then
                button.rank:SetText(string.format("%d/%d", button.rankNow, button.rankMax))
            else
                button.rank:SetText("")
            end
            if an and not pick.granted then punkte = punkte + (pick.rank or 0) end
            button:Show()
        end
    end

    frame.points:SetText(tostring(punkte))
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
