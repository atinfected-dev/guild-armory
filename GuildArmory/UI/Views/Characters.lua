--[[----------------------------------------------------------------------------
    Views/Characters — Spieler, ihre Charaktere und die Rollen.

    Links die Spielerprofile, rechts oben die Charaktere des gewaehlten Profils,
    rechts unten die noch nicht zugeordneten.

    WAS HIER SICHTBAR SEIN MUSS: die Herkunft jeder Zuordnung. "Bewiesen" steht
    nur an Charakteren desselben WoW-Accounts; alles andere ist als "gesetzt"
    oder "behauptet" markiert (siehe Armory/Players.lua). Eine Oberflaeche, die
    beides gleich aussehen laesst, macht aus einer Vermutung eine Tatsache.
------------------------------------------------------------------------------]]

local _, GA = ...

local Characters = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

Characters.titleKey = "NAV_CHARACTERS"

local ROLES = {
    { key = GA.const.ROLE_ADMIN,      label = "ROLE_ADMIN" },
    { key = GA.const.ROLE_LOOTMASTER, label = "ROLE_LOOTMASTER" },
    { key = GA.const.ROLE_COUNCIL,    label = "ROLE_COUNCIL" },
    { key = GA.const.ROLE_MEMBER,     label = "ROLE_MEMBER" },
}

--- Farbe je Herkunft: Bewiesenes in Jade, Gesetztes neutral, Behauptetes in Warnfarbe.
local ORIGIN_COLOR = {
    account = "jade",
    manual  = "textDim",
    claim   = "warn",
}

-- ================================================================== Aufbau ----

function Characters:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------------ Spielerliste ----
    local playerPanel = Widgets.Panel(frame, L.CHAR_PLAYERS)
    playerPanel:SetWidth(240)
    playerPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    playerPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
    self.playerPanel = playerPanel

    self.players = Widgets.ScrollList(playerPanel.content, {
        rowHeight = 30,
        createRow = function(row)
            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
            row.detail = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -16)
            row.detail:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.detail:SetJustifyH("LEFT")
        end,
        updateRow = function(row, profile)
            local main = profile.mainGuid and GA.Core.Database.account.characters[profile.mainGuid]
            local r, g, b = Util.ClassColor(main and main.class)
            row.name:SetText(GA.Modules.Players:DisplayName(profile))
            if profile.id == self.selectedPlayerId then
                row.name:SetTextColor(Theme.color.goldBright[1], Theme.color.goldBright[2], Theme.color.goldBright[3])
            else
                row.name:SetTextColor(r, g, b)
            end

            local count = 0
            for _ in pairs(profile.characterGuids) do count = count + 1 end
            local role = main and GA.Core.Database:GetEffectiveRole(main.guid) or GA.const.ROLE_MEMBER
            row.detail:SetText(string.format(L.CHAR_PLAYER_DETAIL, count,
                L["ROLE_" .. role] or role))
        end,
        onClickRow = function(profile)
            self.selectedPlayerId = profile.id
            self:Refresh()
        end,
    })
    self.players:SetAllPoints(playerPanel.content)

    -- ------------------------------------------------ Charaktere des Spielers
    local memberPanel = Widgets.Panel(frame, L.CHAR_MEMBERS)
    memberPanel:SetPoint("TOPLEFT", playerPanel, "TOPRIGHT", gap, 0)
    memberPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    self.memberPanel = memberPanel

    -- Rollenknoepfe im Kopf des Panels: Sie setzen die Rolle am MAIN. Twinks
    -- erben sie ueber Database:GetEffectiveRole — deshalb steht hier auch der
    -- Hinweis, warum nicht jeder Charakter eine eigene Rolle bekommt.
    self.roleButtons = {}
    local previousRole
    for _, entry in ipairs(ROLES) do
        local button = Widgets.Button(memberPanel.content, L[entry.label], function()
            self:SetRole(entry.key)
        end)
        button:SetHeight(20)
        if previousRole then
            button:SetPoint("LEFT", previousRole, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", memberPanel.content, "TOPLEFT", 0, 0)
        end
        button.roleKey = entry.key
        self.roleButtons[#self.roleButtons + 1] = button
        previousRole = button
    end

    self.roleHint = Theme.Label(memberPanel.content, L.CHAR_ROLE_HINT, fonts.small, Theme.color.textFaint)
    self.roleHint:SetPoint("TOPLEFT", memberPanel.content, "TOPLEFT", 2, -24)
    self.roleHint:SetPoint("RIGHT", memberPanel.content, "RIGHT", -2, 0)
    self.roleHint:SetJustifyH("LEFT")

    -- Spitzname und Notiz zum Main des gewaehlten Profils. Sie stehen hier und
    -- nicht in jeder Zeile: Es ist eine Angabe zur PERSON, nicht zum Charakter.
    self.nickBox = Widgets.SearchBox(memberPanel.content, L.NOTE_NICKNAME, function(text)
        if self.noteGuid then GA.Modules.Notes:SetNickname(self.noteGuid, text) end
    end)
    self.nickBox:SetPoint("TOPLEFT", self.roleHint, "BOTTOMLEFT", -2, -6)
    self.nickBox:SetWidth(160)

    self.noteBox = Widgets.SearchBox(memberPanel.content, L.NOTE_NOTE, function(text)
        if self.noteGuid then GA.Modules.Notes:SetNote(self.noteGuid, text) end
    end)
    self.noteBox:SetPoint("LEFT", self.nickBox, "RIGHT", 8, 0)
    self.noteBox:SetPoint("RIGHT", memberPanel.content, "RIGHT", 0, 0)

    local noteHint = Theme.Label(memberPanel.content, L.NOTE_HINT, fonts.small, Theme.color.textFaint)
    noteHint:SetPoint("TOPLEFT", self.nickBox, "BOTTOMLEFT", 2, -3)
    noteHint:SetPoint("RIGHT", memberPanel.content, "RIGHT", 0, 0)
    noteHint:SetJustifyH("LEFT")

    self.members = Widgets.ScrollList(memberPanel.content, {
        rowHeight = 26,
        createRow = function(row) self:BuildCharacterRow(row, "member") end,
        updateRow = function(row, character) self:UpdateCharacterRow(row, character, "member") end,
    })
    self.members:SetPoint("TOPLEFT", memberPanel.content, "TOPLEFT", 0, -96)
    self.members:SetPoint("BOTTOMRIGHT", memberPanel.content, "BOTTOMRIGHT", 0, 0)

    -- ------------------------------------------------ Nicht zugeordnet ------
    local freePanel = Widgets.Panel(frame, L.CHAR_UNASSIGNED)
    freePanel:SetPoint("TOPLEFT", memberPanel, "BOTTOMLEFT", 0, -gap)
    freePanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.freePanel = freePanel

    self.free = Widgets.ScrollList(freePanel.content, {
        rowHeight = 26,
        createRow = function(row) self:BuildCharacterRow(row, "free") end,
        updateRow = function(row, character) self:UpdateCharacterRow(row, character, "free") end,
    })
    self.free:SetAllPoints(freePanel.content)

    local function layout()
        local height = frame:GetHeight()
        if not height or height <= 0 then return end
        memberPanel:SetHeight(math.max(140, (height - pad * 2 - gap) * 0.58))
    end
    frame:SetScript("OnSizeChanged", layout)
    self.layout = layout

    self.frame = frame
    return frame
end

-- ================================================================== Zeilen ----

--- Eine Charakterzeile mit zwei Aktionsknoepfen. Die Knoepfe werden einmal
--- gebaut und je Zeile umbeschriftet — die Liste recycelt ihre Zeilen.
function Characters:BuildCharacterRow(row, kind)
    local fonts = Theme.Fonts()

    row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetWidth(130)
    row.name:SetJustifyH("LEFT")

    row.meta = Theme.Label(row, "", fonts.small, Theme.color.textDim)
    row.meta:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.meta:SetWidth(130)
    row.meta:SetJustifyH("LEFT")

    row.origin = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
    row.origin:SetPoint("LEFT", row.meta, "RIGHT", 4, 0)
    row.origin:SetWidth(96)
    row.origin:SetJustifyH("LEFT")

    row.secondary = Widgets.Button(row, "", function()
        if row.item then self:OnSecondary(row.item, kind) end
    end)
    row.secondary:SetHeight(18)
    row.secondary:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.primary = Widgets.Button(row, "", function()
        if row.item then self:OnPrimary(row.item, kind) end
    end)
    row.primary:SetHeight(18)
    row.primary:SetPoint("RIGHT", row.secondary, "LEFT", -4, 0)
end

--- SetLabel misst die Beschriftung und setzt die Breite danach — in einer
--- Tabellenzeile muessen die Knoepfe aber gleich breit bleiben, sonst wandert
--- bei jedem Neuzeichnen die Spalte. Deshalb Breite nach dem Beschriften.
local BUTTON_WIDTH = 92

local function setLabel(button, text)
    button:SetLabel(text)
    button:SetWidth(BUTTON_WIDTH)
end

function Characters:UpdateCharacterRow(row, character, kind)
    local Players = GA.Modules.Players
    local profile = Players:GetProfileFor(character.guid)
    local isMain = profile and profile.mainGuid == character.guid

    local r, g, b = Util.ClassColor(character.class)
    local label = Util.ShortName(character.name or "?")
    if isMain then label = label .. "  " .. L.CHAR_MAIN_TAG end
    row.name:SetText(label)
    row.name:SetTextColor(r, g, b)

    local level = character.itemLevel and character.itemLevel.value
    row.meta:SetText(string.format("%s  ·  %s",
        character.className or character.class or "?",
        level and (L.DASH_ITEMLEVEL .. " " .. level) or "—"))

    if kind == "member" then
        local origin = profile and profile.origin[character.guid]
        local key = origin and ("CHAR_ORIGIN_" .. origin) or nil
        row.origin:SetText(key and L[key] or "")
        local color = Theme.color[ORIGIN_COLOR[origin] or "textFaint"]
        row.origin:SetTextColor(color[1], color[2], color[3])

        -- Ein bewiesener Charakter (derselbe Account) laesst sich nicht
        -- "loesen": Die Zuordnung ist eine Tatsache, kein Eintrag.
        local proven = origin == Players.ORIGIN_ACCOUNT
        setLabel(row.primary, L.CHAR_SET_MAIN)
        row.primary:SetEnabledState(not isMain, isMain and L.CHAR_ALREADY_MAIN or nil)
        setLabel(row.secondary, L.CHAR_UNLINK)
        row.secondary:SetEnabledState(not proven, proven and L.CHAR_PROVEN_HINT or nil)
        row.secondary:Show()
    else
        row.origin:SetText(character.ownAccount and L.CHAR_ORIGIN_account or "")
        local color = character.ownAccount and Theme.color.jade or Theme.color.textFaint
        row.origin:SetTextColor(color[1], color[2], color[3])

        local hasTarget = self.selectedPlayerId ~= nil
        setLabel(row.primary, L.CHAR_ASSIGN)
        row.primary:SetEnabledState(hasTarget, hasTarget and nil or L.CHAR_PICK_PLAYER)
        setLabel(row.secondary, L.CHAR_NEW_PLAYER)
        row.secondary:SetEnabledState(true)
        row.secondary:Show()
    end
end

-- ================================================================== Aktionen --

function Characters:OnPrimary(character, kind)
    local Players = GA.Modules.Players
    if kind == "member" then
        local profile = Players:GetProfileFor(character.guid)
        if profile then Players:SetMain(profile.id, character.guid, true) end
    else
        if self.selectedPlayerId then
            Players:Link(character.guid, self.selectedPlayerId, Players.ORIGIN_MANUAL)
        end
    end
    self:Refresh()
end

function Characters:OnSecondary(character, kind)
    local Players = GA.Modules.Players
    if kind == "member" then
        Players:Unlink(character.guid)
    else
        local profile = Players:Create(character.guid, Players.ORIGIN_MANUAL)
        self.selectedPlayerId = profile.id
    end
    self:Refresh()
end

--- Setzt die Rolle am Main des gewaehlten Profils.
function Characters:SetRole(role)
    local Players = GA.Modules.Players
    local profile = Players:Get(self.selectedPlayerId)
    if not profile or not profile.mainGuid then return end

    local own = Compat.GetPlayerIdentity().guid
    if not GA.Core.Database:HasAtLeast(own, GA.const.ROLE_ADMIN) then
        GA.Core.Debug:Warn(L.CHAR_NEED_ADMIN)
        return
    end

    GA.Core.Database:SetRole(profile.mainGuid, role, own)
    self:Refresh()
end

-- ================================================================== Refresh ---

function Characters:OnShow()
    if self.layout then self.layout() end
end

function Characters:Refresh()
    if self.layout then self.layout() end

    local Players = GA.Modules.Players
    local list = Players:List()

    -- Beim ersten Anzeigen das eigene Profil waehlen — das ist fast immer das,
    -- was der Spieler sehen will.
    if not self.selectedPlayerId or not Players:Get(self.selectedPlayerId) then
        local ownProfile = Players:GetProfileFor(Compat.GetPlayerIdentity().guid)
        self.selectedPlayerId = (ownProfile and ownProfile.id) or (list[1] and list[1].id)
    end

    self.players:SetData(list)

    local profile = Players:Get(self.selectedPlayerId)
    self.memberPanel:SetTitle(profile
        and string.format(L.CHAR_MEMBERS_OF, Players:DisplayName(profile))
        or L.CHAR_MEMBERS)
    self.members:SetData(profile and Players:CharactersOf(profile) or {})

    -- Notizfelder auf den Main des gewaehlten Profils. Das Setzen der Texte
    -- loest OnTextChanged aus, deshalb wird der Empfaenger vorher abgeschaltet:
    -- Sonst schriebe das blosse Anzeigen die Notiz zurueck.
    self.noteGuid = nil
    local mainGuid = profile and profile.mainGuid
    self.nickBox.edit:SetText(mainGuid and (GA.Modules.Notes:GetNickname(mainGuid) or "") or "")
    self.noteBox.edit:SetText(mainGuid and (GA.Modules.Notes:GetNote(mainGuid) or "") or "")
    self.noteGuid = mainGuid

    local free = Players:Unassigned()
    self.freePanel:SetTitle(#free > 0
        and string.format("%s (%d)", L.CHAR_UNASSIGNED, #free) or L.CHAR_UNASSIGNED)
    self.free:SetData(free)

    -- Rollenknoepfe: der aktuelle Rang ist gedrueckt (deaktiviert), die
    -- anderen waehlbar — aber nur fuer einen Admin.
    local own = Compat.GetPlayerIdentity().guid
    local isAdmin = GA.Core.Database:HasAtLeast(own, GA.const.ROLE_ADMIN)
    local current = profile and profile.mainGuid
        and GA.Core.Database:GetEffectiveRole(profile.mainGuid) or nil

    for _, button in ipairs(self.roleButtons) do
        local usable = isAdmin and profile ~= nil and button.roleKey ~= current
        button:SetEnabledState(usable,
            (not isAdmin) and L.CHAR_NEED_ADMIN
            or (button.roleKey == current and L.CHAR_ROLE_CURRENT or nil))
    end

    GA.UI.MainFrame:SetContext(string.format(L.CHAR_CONTEXT, #list, #free))
end

GA.UI.MainFrame:RegisterView("characters", Characters)
