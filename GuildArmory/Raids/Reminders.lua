--[[----------------------------------------------------------------------------
    Raids/Reminders — die Erinnerungen des Raidplans im Bosskampf.
    Kein UI (die Anzeige ist UI/ReminderFrame). Schritt 4, 06.10.2026.

    GETRAGEN VOM PULL UND DER EIGENEN UHR, SONST NICHTS:
      Unter den Retail-Einschraenkungen liest ein Addon im Kampf kaum noch
      etwas: kein Kampflog, Boss-Leben und Bossrufe verschleiert, keine
      Addon-Nachrichten in der Instanz. Was bleibt, ist ENCOUNTER_START mit
      der Kennung des Bosses — und GetTime(). Daraus allein laeuft hier
      alles: Ab dem Pull zaehlt die Uhr, jede Erinnerung erscheint `lead`
      Sekunden vor ihrem Zeitpunkt mit Countdown und steht danach noch `dur`
      Sekunden. Phasen sind die geschaetzten Beginne aus der Webapp.

    JEDER SIEHT SEINE EIGENEN:
      Gezeigt wird, was laut Plan fuer den eigenen Charakter gilt (Name,
      Gruppe, Rolle, Klasse — siehe RaidPlan.Matches). Im Probelauf aus der
      Raidplan-Seite dagegen ALLE Erinnerungen des Bosses, damit der
      Raidleiter seinen Plan ausser Kampf durchsehen kann.
------------------------------------------------------------------------------]]

local _, GA = ...

local Reminders = {}
GA.Modules.Reminders = Reminders

local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

--- Toene je Stufe: Name in SOUNDKIT, Ersatz-ID, falls die Tabelle fehlt.
Reminders.SOUND = {
    info  = { "TELL_MESSAGE", 3081 },
    warn  = { "RAID_WARNING", 8959 },
    alert = { "ALARM_CLOCK_WARNING_3", 12867 },
}

--- Was fuer mich gilt — im Probelauf (all = true) alles.
--- @return table { { reminder, mine } } nach Zeit
function Reminders.Build(plan, boss, who, all)
    local out = {}
    for _, r in ipairs(boss.reminders or {}) do
        local mine = GA.Modules.RaidPlan.Matches(r, who)
        if mine or all then out[#out + 1] = { reminder = r, mine = mine, state = "wait" } end
    end
    return out
end

--- Startet einen Lauf fuer einen Boss.
--- @param opts table|nil { preview = true }
--- @return boolean gestartet
function Reminders:Start(plan, boss, opts)
    opts = opts or {}
    if not opts.preview and GA.Core.Config:Get("raidReminders") == false then return false end
    local who = GA.Modules.RaidPlan.WhoAmI(plan)
    local list = Reminders.Build(plan, boss, who, opts.preview)
    if #list == 0 then return false end
    if self.run then self:Stop("replaced") end
    self.run = { plan = plan, boss = boss, list = list, start = Compat.GetTime(), preview = opts.preview and true or false }
    Debug:Print("raidplan", "Erinnerungen fuer %s: %d%s", tostring(boss.name or boss.encounterID), #list,
        opts.preview and " (Probelauf)" or "")
    GA.Core.Callbacks:Fire("REMINDERS_START", self.run)
    return true
end

function Reminders:Stop(reason)
    if not self.run then return end
    local run = self.run
    self.run = nil
    GA.Core.Callbacks:Fire("REMINDERS_STOP", run, reason)
end

function Reminders:IsPreview() return self.run and self.run.preview or false end

local function playSound(kind)
    if kind == "none" or GA.Core.Config:Get("raidReminderSound") == false then return end
    local sound = Reminders.SOUND[kind]
    if sound then Compat.PlaySoundKit(sound[1], sound[2]) end
end

--- Der Takt der Anzeige. Schaltet Erinnerungen ein und aus, spielt beim
--- Erscheinen den Ton und beendet den Lauf, wenn alles vorbei ist.
--- @return table sichtbare { reminder, mine, remaining } nach Zeit
function Reminders:Tick(now)
    local run = self.run
    if not run then return {} end
    local t = (now or Compat.GetTime()) - run.start
    local visible, open = {}, 0
    for _, item in ipairs(run.list) do
        local r = item.reminder
        if item.state ~= "done" then
            if t >= r.time + r.dur then
                item.state = "done"
            elseif t >= r.time - r.lead then
                if item.state == "wait" then
                    item.state = "show"
                    -- Im echten Kampf nur die eigenen mit Ton; im Probelauf
                    -- klingt jede, damit man die Toene hoert.
                    if item.mine or run.preview then playSound(r.sound) end
                end
                visible[#visible + 1] = { reminder = r, mine = item.mine, remaining = r.time - t }
                open = open + 1
            else
                open = open + 1
            end
        end
    end
    if open == 0 then self:Stop("done") end
    return visible
end

-- ================================================================ Testen ---
--
-- Zum Ausprobieren ohne Boss (06.10.2026: "ich muss die irgendwie testen
-- koennen durch einen Befehl"):
--   /ga reminder test         drei Beispiel-Erinnerungen, jede Stufe einmal
--   /ga reminder pull [boss]  ein Pull wie im Kampf — mit den EIGENEN
--                             Erinnerungen des aktiven Plans

--- Drei Beispiele in zwoelf Sekunden: info, warn, alert — mit Ton.
function Reminders:Demo()
    local L = GA.L
    local function demo(at, level, text)
        return { at = at, phase = 1, time = at, lead = 4, dur = 3, level = level, sound = level, text = text, to = { "all" } }
    end
    local plan = { groups = {}, roles = {}, bosses = {} }
    for g = 1, 8 do plan.groups[g] = {} end
    local boss = { name = "Demo", reminders = {
        demo(4, "info", L.RP_DEMO_INFO), demo(8, "warn", L.RP_DEMO_WARN), demo(12, "alert", L.RP_DEMO_ALERT),
    } }
    -- Die Warnung zeigt die Markierung: gross links und im Text.
    boss.reminders[2].marker = 6
    return self:Start(plan, boss, { preview = true })
end

--- Ein Pull wie im echten Kampf, ohne Boss. Der Boss ist die Nummer in der
--- Liste, die Kennung oder der Name — ohne Angabe der erste.
--- @return boolean gestartet, string|nil grund
function Reminders:SimulatePull(which)
    local RaidPlan = GA.Modules.RaidPlan
    local entry = RaidPlan and RaidPlan:Active()
    if not entry then return false, "noplan" end
    local plan, boss = entry.plan, nil
    local n = tonumber(which)
    if not which or which == "" then boss = plan.bosses[1]
    elseif n and plan.bosses[n] and n <= #plan.bosses and n < 1000 then boss = plan.bosses[n]
    else boss = RaidPlan.FindBoss(plan, n, which) end
    if not boss then return false, "noboss" end
    if GA.Core.Config:Get("raidReminders") == false then return false, "off" end
    if not self:Start(plan, boss) then return false, "nothing", boss end
    return true, nil, boss
end

-- ================================================================ Kampf ----

--- Ein Bosskampf beginnt: passt ein Boss des aktiven Plans, laeuft die Uhr.
function Reminders:OnEncounterStart(encounterID, encounterName)
    local RaidPlan = GA.Modules.RaidPlan
    -- Eine verschleierte Kennung ist keine Kennung.
    if not Compat.IsReadableNumber(encounterID) then encounterID = nil end
    -- Gesehene Bosse merken: Im Editor stehen sie zur Auswahl, damit niemand
    -- Kennungen nachschlagen muss.
    if encounterID and type(encounterName) == "string" and Compat.IsReadable(encounterName) then
        if RaidPlan and RaidPlan.ShareEncounter then
            -- Merken UND der Gilde sagen (07.10.2026) — die Liste gehoert allen.
            RaidPlan:ShareEncounter(encounterID, encounterName)
        else
            local account = GA.Core.Database.account
            account.seenEncounters = account.seenEncounters or {}
            account.seenEncounters[encounterID] = encounterName
        end
    end
    local entry = RaidPlan and RaidPlan:Active()
    if not entry then return false end
    local boss = RaidPlan.FindBoss(entry.plan, encounterID, encounterName)
    if not boss then return false end
    return self:Start(entry.plan, boss)
end

function Reminders:OnEnable()
    local Events = GA.Core.Events
    Events:Register("ENCOUNTER_START", function(_, id, name) Reminders:OnEncounterStart(id, name) end, "Reminders")
    Events:Register("ENCOUNTER_END", function()
        -- Ein Probelauf ist kein Kampf: der laeuft weiter.
        if Reminders.run and not Reminders.run.preview then Reminders:Stop("end") end
    end, "Reminders")
end
