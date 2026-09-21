--[[----------------------------------------------------------------------------
    Achievements — Erfolge freischalten, aufbewahren und auswerten.

    Kein UI. Der Katalog liegt in Achievements/Catalog.lua (erzeugt), die
    Auslösebedingungen in Achievements/Rules.lua.

    ===========================================================================
    DIE ENTSCHEIDUNG, DIE ALLES TRAEGT
    ===========================================================================

    EIN ERFOLG TRAEGT MIT, WORAUF ER BERUHT.

    Das ist dieselbe Regel wie bei einer Vergabe (Abschnitt 4.3): "erreicht"
    allein ist keine Aussage. Ein Erfolg, den dieser Client selbst aus eigenen
    Daten gerechnet hat, und einer, den jemand von Hand eingetragen hat, sehen
    in einer Liste identisch aus, sobald man nur einen Haken anzeigt.

        gemessen    aus den Daten dieses Clients gerechnet
        beobachtet  ein anderer Client hat es gemeldet
        eingetragen ein Offizier hat es gesetzt

    Eine Hall of Fame, die das verschweigt, ist eine Behauptungssammlung.

    ===========================================================================
    UND DIE ZWEITE, DIE NUR FUER GILDEN-FIRSTS GILT
    ===========================================================================

    EIN FIRST IST "GEMELDET", BIS DIE GILDE ZUSTIMMT.

    45 der 272 Erfolge sind einmalig fuer die ganze Gilde. Dabei ist die Frage
    nicht "habe ich es geschafft", sondern "war jemand frueher". Diese Frage
    kann ein einzelner Client nicht beantworten — er kennt nur sich.

        gemeldet    dieser Client glaubt, der erste gewesen zu sein
        bestaetigt  nach Abgleich hat niemand frueher gemeldet
        ueberholt   jemand anderes war nachweislich frueher

    Bei GLEICHEM Zeitstempel wird NICHT gewaehlt. Der Katalog sagt es selbst:
    Es gewinnt nicht der schnellste Client, sondern der belegte fruehere
    Vorgang. Gibt es keinen Beleg, bleibt der Fall strittig und ein Mensch
    entscheidet. Ein Addon, das hier eine Millisekunde zum Massstab macht,
    kroent den mit der besseren Verbindung.

    ===========================================================================
    WAS HIER NICHT PASSIERT
    ===========================================================================

    Rueckwirkend freischalten. Das Addon kennt nur, was es gesehen hat. Wer es
    heute installiert, hat keine fuenfzig Raids in der Historie, auch wenn er
    fuenfzig gespielt hat. Jeder Erfolg traegt deshalb mit, seit wann gezaehlt
    wird — sonst waere "50 Raidteilnahmen" eine Aussage ueber das Addon und
    nicht ueber den Spieler.
------------------------------------------------------------------------------]]

local _, GA = ...

local Achievements = {}
GA.Modules.Achievements = Achievements

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Worauf ein Erfolg beruht.
Achievements.EVIDENCE = {
    MEASURED = "measured",
    OBSERVED = "observed",
    GRANTED  = "granted",
}

--- Zustand eines Gilden-Firsts.
Achievements.STATE = {
    REPORTED  = "reported",
    VERIFIED  = "verified",
    SUPERSEDED = "superseded",
    CONTESTED = "contested",
}

local function catalog()
    return GA.Data.Catalog
end

local function db()
    local account = GA.Core.Database.account
    account.achievements = account.achievements or {}
    account.guildFirsts = account.guildFirsts or {}
    return account
end

-- ================================================================== Katalog --

function Achievements:Entry(id)
    return id and catalog().ENTRIES[id] or nil
end

--- Ist das ein einmaliger Gilden-First?
---
--- Die Kategorie entscheidet, nicht eine zweite Liste: Sonst stehen zwei
--- Wahrheiten im Code, und irgendwann widersprechen sie sich.
function Achievements:IsGuildFirst(id)
    local entry = self:Entry(id)
    return entry ~= nil and entry.category == "FIRSTS"
end

-- ================================================================== Person ---

--- Wessen Erfolge? Immer das SPIELERPROFIL, nie der einzelne Charakter.
---
--- Sonst haette derselbe Mensch mit drei Twinks dreimal "Stufe 60 erreicht",
--- und die Rangliste waere eine Zaehlung von Charakteren.
--- @return string|nil playerId
local function playerIdOf(guid)
    local profile = guid and GA.Modules.Players:GetProfileFor(guid)
    return profile and profile.id or nil
end

local function ownPlayerId()
    return playerIdOf(Compat.GetPlayerIdentity().guid)
end

-- ================================================================== Freischalten

--- Schaltet einen Erfolg frei.
---
--- @param id string
--- @param options table|nil { playerId, name, evidence, ts, value, character, by }
--- @return boolean ok, string|table grund oder Eintrag
function Achievements:Unlock(id, options)
    options = options or {}
    local entry = self:Entry(id)
    if not entry then return false, "unknown" end

    local playerId = options.playerId or ownPlayerId()
    if not playerId then return false, "noplayer" end

    local evidence = options.evidence or self.EVIDENCE.MEASURED
    local ts = tonumber(options.ts) or Util.Now()

    if self:IsGuildFirst(id) then
        return self:ClaimFirst(id, playerId, options.name, ts, evidence, options.reason)
    end

    local store = db().achievements
    store[playerId] = store[playerId] or {}

    local existing = store[playerId][id]
    if existing then
        -- Schon da. Ein staerkerer Beleg darf den schwaecheren ersetzen, der
        -- umgekehrte Weg nicht: Wer einmal gemessen wurde, wird nicht durch
        -- eine Meldung zur Behauptung.
        local rank = { measured = 3, observed = 2, granted = 1 }
        if (rank[evidence] or 0) > (rank[existing.evidence] or 0) then
            existing.evidence = evidence
            existing.ts = math.min(existing.ts or ts, ts)
            return true, existing
        end
        return false, "already"
    end

    store[playerId][id] = {
        ts = ts,
        evidence = evidence,
        value = options.value,
        character = options.character or Compat.GetPlayerIdentity().name,
        by = options.by,
        -- Nur bei eingetragenen Erfolgen gesetzt. Eine Messung braucht keine
        -- Begruendung, eine Behauptung schon.
        reason = options.reason,
    }

    GA.Core.Database:Journal("ACHIEVEMENT", id, nil,
        { player = playerId, evidence = evidence }, options.by)
    GA.Core.Callbacks:Fire("ACHIEVEMENT_UNLOCKED", id, playerId)
    Debug:Info(GA.L.ACH_UNLOCKED, entry.name, entry.points)

    return true, store[playerId][id]
end

--- Meldet einen Gilden-First an.
---
--- Beachte: Das Ergebnis ist IMMER zunaechst "gemeldet". Ob es der erste war,
--- weiss dieser Client nicht — er kennt nur sich.
function Achievements:ClaimFirst(id, playerId, name, ts, evidence, reason)
    local firsts = db().guildFirsts
    local current = firsts[id]

    local claim = {
        playerId = playerId,
        name = name or GA.Modules.Players:DisplayName(
            GA.Core.Database.account.players[playerId] or {}) or playerId,
        ts = ts,
        evidence = evidence,
        reason = reason,
    }

    if not current then
        firsts[id] = {
            playerId = claim.playerId,
            name = claim.name,
            ts = claim.ts,
            evidence = claim.evidence,
            reason = claim.reason,
            state = self.STATE.REPORTED,
            claims = { claim },
        }
        GA.Core.Callbacks:Fire("ACHIEVEMENT_UNLOCKED", id, playerId)
        Debug:Info(GA.L.ACH_FIRST_REPORTED, self:Entry(id).name)
        return true, firsts[id]
    end

    -- Schon jemand gemeldet. Den Anspruch trotzdem aufbewahren: Wer ihn
    -- wegwirft, kann einen Streit spaeter nicht mehr aufloesen.
    current.claims = current.claims or {}
    for _, existing in ipairs(current.claims) do
        if existing.playerId == claim.playerId then return false, "already" end
    end
    current.claims[#current.claims + 1] = claim

    if claim.ts < (current.ts or math.huge) then
        current.playerId = claim.playerId
        current.name = claim.name
        current.ts = claim.ts
        current.evidence = claim.evidence
        current.reason = claim.reason
        current.state = self.STATE.REPORTED
        GA.Core.Callbacks:Fire("ACHIEVEMENT_UNLOCKED", id, playerId)
        return true, current
    end

    if claim.ts == current.ts and claim.playerId ~= current.playerId then
        -- GLEICHSTAND WIRD NICHT AUFGELOEST. Eine Sekunde Unterschied ist
        -- keine Rangfolge, und der Client mit der besseren Verbindung ist
        -- nicht der wuerdigere Sieger. Ein Mensch entscheidet.
        current.state = self.STATE.CONTESTED
        GA.Core.Callbacks:Fire("ACHIEVEMENT_CONTESTED", id)
        Debug:Warn(GA.L.ACH_FIRST_CONTESTED, self:Entry(id).name)
        return false, "contested"
    end

    return false, "superseded"
end

-- ================================================================ Eintragen --
--
-- WARUM ES DIESEN WEG UEBERHAUPT GIBT
--
-- Rund fuenfundvierzig Erfolge im Katalog kann ein Addon NIE messen: ein
-- Treffen im echten Leben, Stunden im Sprachkanal, ein geschlichteter
-- Streit, ein bestaetigter Ersatzeinsatz. Sie stehen im Katalog, weil sie in
-- einer Gilde zaehlen — nicht, weil ein Client sie sehen koennte.
--
-- Fuer sie ist dies der einzige moegliche Weg. Und deshalb muss er genau das
-- mittragen, was ihn von einer Messung unterscheidet: WER es eingetragen hat
-- und WARUM.
--
-- DIE BEGRUENDUNG IST PFLICHT.
--
-- Punkte von Hand in eine Rangliste zu schreiben, ohne zu sagen wofuer, macht
-- die Rangliste wertlos — dieselbe Ueberlegung wie bei GA-153, wo eine
-- Vergabe erst als dokumentiert gilt, wenn jemand sich hingesetzt und
-- aufgeschrieben hat, warum.

--- Traegt einen Erfolg von Hand ein.
---
--- @param id string
--- @param playerId string   Spielerprofil, nicht Charakter-GUID
--- @param reason string     Pflicht
--- @param byGuid string|nil
--- @return boolean ok, string|table grund oder Eintrag
function Achievements:Grant(id, playerId, reason, byGuid)
    byGuid = byGuid or Compat.GetPlayerIdentity().guid

    if not self:Entry(id) then return false, "unknown" end
    if not playerId or not db().players[playerId] then return false, "noplayer" end
    if not GA.Core.Database:HasAtLeast(byGuid, GA.const.ROLE_ADMIN) then
        return false, "notallowed"
    end

    reason = type(reason) == "string" and string.gsub(reason, "^%s*(.-)%s*$", "%1") or ""
    if reason == "" then return false, "noreason" end

    return self:Unlock(id, {
        playerId = playerId,
        evidence = self.EVIDENCE.GRANTED,
        by = byGuid,
        reason = reason,
        name = GA.Modules.Players:DisplayName(db().players[playerId]),
    })
end

--- Nimmt einen eingetragenen Erfolg zurueck.
---
--- NUR EINGETRAGENE. Eine Messung laesst sich nicht zuruecknehmen: Sie stuende
--- beim naechsten Durchlauf wieder da, und ein Loeschen, das sich binnen zehn
--- Minuten selbst repariert, ist keine Bedienung, sondern eine Irrefuehrung.
--- Wer eine Messung fuer falsch haelt, muss die Regel aendern.
function Achievements:Revoke(id, playerId, byGuid)
    byGuid = byGuid or Compat.GetPlayerIdentity().guid
    if not GA.Core.Database:HasAtLeast(byGuid, GA.const.ROLE_ADMIN) then
        return false, "notallowed"
    end

    if self:IsGuildFirst(id) then
        local first = db().guildFirsts[id]
        if not first then return false, "unknown" end
        if first.evidence ~= self.EVIDENCE.GRANTED then return false, "notgranted" end

        -- Ein gemessener Anspruch von jemand anderem wuerde mit geloescht.
        -- Lieber gar nicht als die Meldung eines anderen stillschweigend
        -- wegzuwerfen.
        for _, claim in ipairs(first.claims or {}) do
            if claim.evidence ~= self.EVIDENCE.GRANTED then return false, "hasclaims" end
        end

        db().guildFirsts[id] = nil
        GA.Core.Database:Journal("ACHIEVEMENT_REVOKE", id, first.playerId, nil, byGuid)
        GA.Core.Callbacks:Fire("ACHIEVEMENT_CHANGED", id)
        return true
    end

    local store = db().achievements[playerId]
    local entry = store and store[id]
    if not entry then return false, "unknown" end
    if entry.evidence ~= self.EVIDENCE.GRANTED then return false, "notgranted" end

    store[id] = nil
    GA.Core.Database:Journal("ACHIEVEMENT_REVOKE", id, playerId, nil, byGuid)
    GA.Core.Callbacks:Fire("ACHIEVEMENT_CHANGED", id)
    return true
end

--- Darf dieser Charakter eintragen?
function Achievements:MayGrant(guid)
    return GA.Core.Database:HasAtLeast(guid or Compat.GetPlayerIdentity().guid,
        GA.const.ROLE_ADMIN) and true or false
end

--- Bestaetigt einen gemeldeten First. Nur ein Admin.
function Achievements:VerifyFirst(id, byGuid)
    local first = db().guildFirsts[id]
    if not first then return false, "unknown" end
    if not GA.Core.Database:HasAtLeast(byGuid or Compat.GetPlayerIdentity().guid,
        GA.const.ROLE_ADMIN) then
        return false, "notallowed"
    end

    local before = first.state
    first.state = self.STATE.VERIFIED
    first.verifiedTs = Util.Now()
    GA.Core.Database:Journal("ACHIEVEMENT_VERIFY", id, before, first.state, byGuid)
    GA.Core.Callbacks:Fire("ACHIEVEMENT_CHANGED", id)
    return true, first
end

-- ================================================================== Abfrage --

function Achievements:IsUnlocked(id, playerId)
    if self:IsGuildFirst(id) then
        local first = db().guildFirsts[id]
        return first ~= nil and (not playerId or first.playerId == playerId), first
    end
    playerId = playerId or ownPlayerId()
    local store = playerId and db().achievements[playerId]
    local entry = store and store[id]
    return entry ~= nil, entry
end

--- Alle Erfolge eines Spielers, mit Katalogdaten angereichert.
--- @param filter table|nil { category, rarity, tier, unlockedOnly }
function Achievements:List(playerId, filter)
    filter = filter or {}
    playerId = playerId or ownPlayerId()
    local personal = (playerId and db().achievements[playerId]) or {}
    local firsts = db().guildFirsts

    local out = {}
    for _, id in ipairs(catalog().ORDER) do
        local entry = catalog().ENTRIES[id]
        local keep = true
        if filter.category and entry.category ~= filter.category then keep = false end
        if filter.rarity and entry.rarity ~= filter.rarity then keep = false end
        if filter.tier and entry.tier ~= filter.tier then keep = false end

        if keep then
            local unlock, state
            if entry.category == "FIRSTS" then
                local first = firsts[id]
                if first and first.playerId == playerId then
                    unlock = first
                    state = first.state
                end
            else
                unlock = personal[id]
            end

            if unlock or not filter.unlockedOnly then
                out[#out + 1] = {
                    id = id,
                    name = entry.name,
                    description = entry.description,
                    points = entry.points,
                    rarity = entry.rarity,
                    category = entry.category,
                    tier = entry.tier,
                    unlocked = unlock ~= nil,
                    ts = unlock and unlock.ts,
                    evidence = unlock and unlock.evidence,
                    state = state,
                    character = unlock and unlock.character,
                    -- Nur bei eingetragenen gesetzt. Ohne ihn waere ein
                    -- Eintrag von Hand in der Liste nicht von einer Messung
                    -- zu unterscheiden.
                    reason = unlock and unlock.reason,
                }
            end
        end
    end
    return out
end

--- Punktestand. Handeintraege werden GETRENNT ausgewiesen, nicht im selben
--- Topf: Eine Zahl, die Messungen und Eintraege zusammenwirft, sieht genauer
--- aus als sie ist. Dieselbe Regel wie bei Plus Eins.
function Achievements:Points(playerId)
    playerId = playerId or ownPlayerId()
    local total, granted, count, firsts = 0, 0, 0, 0

    for _, row in ipairs(self:List(playerId, { unlockedOnly = true })) do
        total = total + (row.points or 0)
        count = count + 1
        if row.evidence == self.EVIDENCE.GRANTED then granted = granted + (row.points or 0) end
        if row.category == "FIRSTS" then firsts = firsts + 1 end
    end

    return {
        total = total,
        granted = granted,
        measured = total - granted,
        count = count,
        firsts = firsts,
        available = catalog().COUNT,
    }
end

--- Rangliste ueber alle bekannten Spieler.
function Achievements:Leaderboard()
    local out = {}
    for playerId, profile in pairs(GA.Core.Database.account.players) do
        local points = self:Points(playerId)
        out[#out + 1] = {
            playerId = playerId,
            name = GA.Modules.Players:DisplayName(profile),
            points = points.total,
            granted = points.granted,
            count = points.count,
            firsts = points.firsts,
        }
    end

    table.sort(out, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.firsts ~= b.firsts then return a.firsts > b.firsts end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

--- Die Hall of Fame: wer hat welchen Gilden-First.
function Achievements:HallOfFame()
    local out = {}
    for id, first in pairs(db().guildFirsts) do
        local entry = self:Entry(id)
        if entry then
            out[#out + 1] = {
                id = id,
                name = entry.name,
                description = entry.description,
                points = entry.points,
                rarity = entry.rarity,
                holder = first.name,
                playerId = first.playerId,
                ts = first.ts,
                state = first.state,
                evidence = first.evidence,
                reason = first.reason,
                contested = first.state == self.STATE.CONTESTED,
                claims = first.claims and #first.claims or 1,
            }
        end
    end
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return out
end

-- ================================================================== Start ------

function Achievements:OnEnable()
    -- Seit wann ueberhaupt gezaehlt wird. Ohne diesen Zeitpunkt waere
    -- "50 Raidteilnahmen" eine Aussage ueber das Addon statt ueber den
    -- Spieler (siehe Dateikopf).
    local account = GA.Core.Database.account
    account.achievementsSince = account.achievementsSince or Util.Now()

    Debug:Print("core", "Erfolge: %d im Katalog, %d freigeschaltet",
        catalog().COUNT, self:Points().count)
end
