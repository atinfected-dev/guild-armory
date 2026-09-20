--[[----------------------------------------------------------------------------
    Views/Dashboard — Portrait, Charakter, Gilde, Lootzustand, letzte Aenderungen.

    Zeigt nur, was gemessen wurde. Wo eine Zahl fehlt, steht ein Strich.
    Aufgebaut aus Blizzards eingelassenen Flaechen (Widgets.Panel/Inset) mit
    Questlog-Kopfzeilen — wie die rechte Seite von "Karte & Questlog".
------------------------------------------------------------------------------]]

local _, GA = ...

local Dashboard = {}
local Theme = GA.UI.Theme
local Widgets = GA.UI.Widgets
local Util = GA.Core.Util
local Compat = GA.Core.Compat
local L = GA.L

Dashboard.title = L.NAV_DASHBOARD

local CARD_HEIGHT = 92
local ROW_HEIGHT = 90

function Dashboard:Create(parent)
    local fonts = Theme.Fonts()
    local pad, gap = 4, 8

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- ------------------------------------------------- Charakterkarte -------
    local me = Widgets.Inset(frame)
    me:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    me:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
    me:SetHeight(CARD_HEIGHT)

    self.portrait = me:CreateTexture(nil, "ARTWORK")
    self.portrait:SetWidth(58) self.portrait:SetHeight(58)
    self.portrait:SetPoint("LEFT", me, "LEFT", 16, 0)

    local ring = me:CreateTexture(nil, "OVERLAY")
    ring:SetWidth(72) ring:SetHeight(72)
    ring:SetPoint("CENTER", self.portrait, "CENTER", 0, 0)
    pcall(ring.SetTexture, ring, "Interface\\Minimap\\MiniMap-TrackingBorder")
    pcall(ring.SetTexCoord, ring, 0, 0.6, 0, 0.6)

    self.charName = Theme.Label(me, "", fonts.hero, Theme.color.goldBright)
    self.charName:SetPoint("TOPLEFT", me, "TOPLEFT", 92, -18)
    if self.charName.SetShadowOffset then self.charName:SetShadowOffset(1, -1) end

    self.classIcon = me:CreateTexture(nil, "ARTWORK")
    self.classIcon:SetWidth(22) self.classIcon:SetHeight(22)
    self.classIcon:SetPoint("LEFT", self.charName, "RIGHT", 8, 0)

    self.charMeta = Theme.Label(me, "", fonts.body, Theme.color.textDim)
    self.charMeta:SetPoint("TOPLEFT", self.charName, "BOTTOMLEFT", 1, -5)

    self.charGuild = Theme.Label(me, "", fonts.small, Theme.color.textFaint)
    self.charGuild:SetPoint("TOPLEFT", self.charMeta, "BOTTOMLEFT", 0, -3)

    self.ilvl = Theme.Label(me, "", fonts.hero, Theme.color.goldBright)
    self.ilvl:SetPoint("TOPRIGHT", me, "TOPRIGHT", -20, -16)
    if self.ilvl.SetShadowOffset then self.ilvl:SetShadowOffset(1, -1) end
    self.ilvlLabel = Theme.Label(me, L.DASH_ITEMLEVEL, fonts.body, Theme.color.textDim)
    self.ilvlLabel:SetPoint("TOPRIGHT", self.ilvl, "BOTTOMRIGHT", 0, -2)
    self.ilvlHint = Theme.Label(me, L.DASH_COMPUTED, fonts.small, Theme.color.textFaint)
    self.ilvlHint:SetPoint("TOPRIGHT", self.ilvlLabel, "BOTTOMRIGHT", 0, -2)

    -- ------------------------------------------------- Gilde und Loot -------
    local guild = Widgets.Panel(frame, L.DASH_GUILD)
    guild:SetPoint("TOPLEFT", me, "BOTTOMLEFT", 0, -gap)
    guild:SetHeight(ROW_HEIGHT)

    local loot = Widgets.Panel(frame, L.DASH_LOOT_STATE)
    loot:SetPoint("TOPLEFT", guild, "TOPRIGHT", gap, 0)
    loot:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    loot:SetHeight(ROW_HEIGHT)

    self.guildName = Theme.Label(guild.content, "", fonts.big, Theme.color.goldBright)
    self.guildName:SetPoint("TOPLEFT", guild.content, "TOPLEFT", 4, -4)
    self.guildMeta = Theme.Label(guild.content, "", fonts.body, Theme.color.textDim)
    self.guildMeta:SetPoint("TOPLEFT", self.guildName, "BOTTOMLEFT", 0, -4)
    self.guildRank = Theme.Label(guild.content, "", fonts.small, Theme.color.textFaint)
    self.guildRank:SetPoint("TOPLEFT", self.guildMeta, "BOTTOMLEFT", 0, -3)

    self.lootMethod = Theme.Label(loot.content, "", fonts.big, Theme.color.goldBright)
    self.lootMethod:SetPoint("TOPLEFT", loot.content, "TOPLEFT", 4, -4)
    self.lootState = Theme.Label(loot.content, "", fonts.body, Theme.color.textDim)
    self.lootState:SetPoint("TOPLEFT", self.lootMethod, "BOTTOMLEFT", 0, -4)
    self.lootState:SetPoint("RIGHT", loot.content, "RIGHT", -4, 0)
    self.lootState:SetJustifyH("LEFT")

    -- Offene Uebergaben gehoeren hierher und nicht in eine eigene Ansicht:
    -- Wer sie suchen muss, schaut nicht nach.
    self.handover = Theme.Label(loot.content, "", fonts.small, Theme.color.warn)
    self.handover:SetPoint("TOPLEFT", self.lootState, "BOTTOMLEFT", 0, -4)
    self.handover:SetPoint("RIGHT", loot.content, "RIGHT", -4, 0)
    self.handover:SetJustifyH("LEFT")

    -- ------------------------------------------------- Listen ---------------
    local changes = Widgets.Panel(frame, L.DASH_CHANGES)
    changes:SetPoint("TOPLEFT", guild, "BOTTOMLEFT", 0, -gap)
    changes:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)

    local online = Widgets.Panel(frame, L.DASH_ONLINE)
    online:SetPoint("TOPLEFT", changes, "TOPRIGHT", gap, 0)
    online:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    self.onlinePanel = online

    local function layout()
        local width = frame:GetWidth()
        if not width or width <= 0 then return end
        local half = (width - pad * 2 - gap) * 0.5
        guild:SetWidth(half)
        changes:SetWidth(half)
    end
    frame:SetScript("OnSizeChanged", layout)
    self.layout = layout

    self.changes = Widgets.ScrollList(changes.content, {
        rowHeight = 24,
        createRow = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(18) row.icon:SetHeight(18)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.text = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -70, 0)
            row.text:SetJustifyH("LEFT")
            row.when = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.when:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end,
        updateRow = function(row, entry)
            if entry.icon then row.icon:SetTexture(entry.icon) row.icon:Show() else row.icon:Hide() end
            row.text:SetText(entry.text)
            local color = entry.color or Theme.color.text
            row.text:SetTextColor(color[1], color[2], color[3])
            row.when:SetText(entry.when or "")
        end,
        onEnterRow = function(row, entry)
            if entry.link then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                if pcall(GameTooltip.SetHyperlink, GameTooltip, entry.link) then GameTooltip:Show() end
            end
        end,
    })
    self.changes:SetAllPoints(changes.content)

    self.online = Widgets.ScrollList(online.content, {
        rowHeight = 22,
        createRow = function(row)
            row.name = Theme.Label(row, "", fonts.body, Theme.color.text)
            row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name:SetWidth(120)
            row.name:SetJustifyH("LEFT")
            row.rank = Theme.Label(row, "", fonts.small, Theme.color.textDim)
            row.rank:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
            row.rank:SetWidth(90)
            row.rank:SetJustifyH("LEFT")
            row.zone = Theme.Label(row, "", fonts.small, Theme.color.textFaint)
            row.zone:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
            row.zone:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.zone:SetJustifyH("LEFT")
        end,
        updateRow = function(row, member)
            local r, g, b = Util.ClassColor(member.class)
            row.name:SetText(member.name or "?")
            row.name:SetTextColor(r, g, b)
            row.rank:SetText(member.rankName or "")
            row.zone:SetText(member.zone or "")
        end,
    })
    self.online:SetAllPoints(online.content)

    self.frame = frame
    return frame
end

--- Baut die Liste der letzten Aenderungen aus den Snapshots aller eigenen
--- Charaktere. Jede Zeile ist ein angelegter oder abgelegter Gegenstand;
--- Staende ohne Platzwechsel (nur Itemlevel) und der erste Stand erscheinen
--- als eigene Zeile, damit die Liste die Erfassung selbst belegt.
function Dashboard:CollectChanges(limit)
    local db = GA.Core.Database.account
    local rows = {}

    for guid, snapshots in pairs(db.snapshots) do
        local character = db.characters[guid]
        local who = Util.ShortName(character and character.name or "?")
        for index = #snapshots, 1, -1 do
            local snapshot = snapshots[index]
            local changes = snapshot.changes or {}
            if index == 1 or #changes == 0 then
                rows[#rows + 1] = {
                    ts = snapshot.ts,
                    text = string.format("%s: %s", who,
                        string.format(L.DASH_SNAPSHOT_ROW, tostring(snapshot.itemLevel or "—"))),
                    color = Theme.color.textDim,
                    when = Util.TimeAgo(snapshot.ts),
                }
            end
            for _, change in ipairs(changes) do
                local itemID = change.to or change.from
                local info = itemID and Compat.GetItemInfo(itemID)
                local name = info and info.name or string.format(L.ITEM_FALLBACK, tostring(itemID))
                rows[#rows + 1] = {
                    ts = snapshot.ts,
                    icon = info and info.icon or nil,
                    link = info and info.link or nil,
                    text = string.format(change.to and L.CHANGE_EQUIPPED or L.CHANGE_UNEQUIPPED, who, name),
                    color = info and Theme.QualityColor(info.quality) or nil,
                    when = Util.TimeAgo(snapshot.ts),
                }
            end
        end
    end

    -- Rosterereignisse gehoeren in dieselbe Liste: "Bert ist beigetreten" und
    -- "Anna hat den Helm angelegt" sind beides Dinge, die seit gestern
    -- passiert sind. Sie getrennt zu zeigen hiesse, zweimal hinsehen zu
    -- muessen.
    for _, event in ipairs(GA.Modules.GuildHistory:List()) do
        local color = Theme.color.textDim
        if event.kind == GA.Modules.GuildHistory.LEFT then color = Theme.color.textFaint
        elseif event.kind == GA.Modules.GuildHistory.PROMOTED then color = Theme.color.jade
        elseif event.kind == GA.Modules.GuildHistory.DEMOTED then color = Theme.color.warn
        elseif event.kind == GA.Modules.GuildHistory.JOINED then color = Theme.color.gold end

        local text = string.format("%s: %s", event.name,
            L["HIST_" .. event.kind] or event.kind)
        if event.detail then text = text .. " " .. string.format(L.HIST_FROM_RANK, event.detail) end

        rows[#rows + 1] = {
            ts = event.ts, text = text, color = color,
            when = Util.TimeAgo(event.ts),
        }
    end

    table.sort(rows, function(a, b) return a.ts > b.ts end)
    while #rows > (limit or 30) do rows[#rows] = nil end
    return rows
end

function Dashboard:OnShow()
    if self.layout then self.layout() end
end

function Dashboard:Refresh()
    local identity = Compat.GetPlayerIdentity()
    local db = GA.Core.Database
    local character = identity.guid and db.account.characters[identity.guid]

    if not Theme.SetPortrait(self.portrait, "player") then
        Theme.Paint(self.portrait, Theme.color.rowAltBg)
    end
    local r, g, b = Util.ClassColor(identity.class)
    self.charName:SetText(identity.name or "?")
    self.charName:SetTextColor(r, g, b)
    self.charMeta:SetText(string.format(L.LEVEL_FMT, tostring(identity.level or "?")) .. "  " ..
        (identity.raceName or "") .. " " .. (identity.className or ""))
    if Theme.SetClassIcon(self.classIcon, identity.class) then self.classIcon:Show() else self.classIcon:Hide() end

    local level = character and character.itemLevel and character.itemLevel.value
    self.ilvl:SetText(level and tostring(level) or "—")

    local guildName, rankName = Compat.GetOwnGuildInfo()
    if guildName then
        self.charGuild:SetText(string.format("<%s>  %s  ·  %s", guildName, rankName or "", identity.realm or ""))
        self.guildName:SetText(guildName)
        local total, online = Compat.GetNumGuildMembers()
        self.guildMeta:SetText(string.format(L.DASH_MEMBERS, total, online))
        self.guildRank:SetText(rankName or "")
    else
        self.charGuild:SetText(identity.realm or "")
        self.guildName:SetText(L.DASH_NOT_IN_GUILD)
        self.guildMeta:SetText("")
        self.guildRank:SetText("")
    end

    -- Lootmethode gibt es nur in einer Gruppe. Allein ist "unbekannt" falsch —
    -- es ist schlicht nicht anwendbar.
    if not Compat.IsInGroup() then
        self.lootMethod:SetText(L.LOOT_NO_GROUP)
        self.lootState:SetText(L.LOOT_NO_GROUP_HINT)
    else
        local method = Compat.GetLootMethod()
        local labels = { freeforall = L.LOOT_FREEFORALL, roundrobin = L.LOOT_ROUNDROBIN,
                         master = L.LOOT_MASTER, group = L.LOOT_GROUP,
                         needbeforegreed = L.LOOT_NBG, personalloot = L.LOOT_PERSONAL }
        self.lootMethod:SetText(method and (labels[method] or method) or L.UNKNOWN)
        if method == "master" then
            self.lootState:SetText(Compat.IsMasterLooter() and L.DASH_LOOT_MASTER or L.DASH_LOOT_NOTMASTER)
        else
            self.lootState:SetText(L.DASH_LOOT_NOTMASTER)
        end
    end

    local carrying = GA.Modules.Handover:Pending()
    if #carrying > 0 then
        local names = {}
        for index = 1, math.min(#carrying, 2) do
            names[#names + 1] = tostring(carrying[index].to)
        end
        local text = table.concat(names, ", ")
        if #carrying > 2 then
            text = text .. string.format(L.HANDOVER_MORE, #carrying - 2)
        end
        self.handover:SetText(string.format(L.HANDOVER_REMIND, #carrying, text))
    else
        self.handover:SetText("")
    end

    local changeRows = self:CollectChanges(40)
    if #changeRows == 0 then
        changeRows = { { text = L.DASH_NO_CHANGES, color = Theme.color.textFaint } }
    end
    self.changes:SetData(changeRows)

    local onlineRows = GA.Modules.Guild:List(true)
    if self.onlinePanel and self.onlinePanel.SetTitle then
        self.onlinePanel:SetTitle(#onlineRows > 0
            and string.format("%s (%d)", L.DASH_ONLINE, #onlineRows) or L.DASH_ONLINE)
    end
    if #onlineRows == 0 then
        onlineRows = { { name = guildName and L.DASH_NOBODY_ONLINE or L.DASH_NOT_IN_GUILD, class = nil } }
    end
    self.online:SetData(onlineRows)

    GA.UI.MainFrame:SetContext(character and character.equipmentTs
        and string.format(L.ARMORY_SNAPSHOT, Util.TimeAgo(character.equipmentTs)) or "")
end

GA.UI.MainFrame:RegisterView("dashboard", Dashboard)
