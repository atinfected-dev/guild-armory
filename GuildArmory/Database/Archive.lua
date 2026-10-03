--[[----------------------------------------------------------------------------
    Database/Archive — Vergaben und Journal nach Saison verdichten.
    Kein UI. Entwurf S3 vom 03.10.2026.

    WARUM:
      Die Vergaben sind das Einzige in den SavedVariables, das ohne Grenze
      waechst — mit jedem Raid. Gemessen am 03.10.2026: 69 Vergaben, je
      646 Byte, und davon entfielen 53 % auf die Statushistorie. Die braucht
      nach der Vergabe kaum noch jemand: Sie erzaehlt, wie es zur Vergabe
      kam, und das ist nach einer Saison erzaehlt.

    WAS VERDICHTET WIRD:
      Vergaben, die aelter als AFTER_DAYS sind UND einen endgueltigen Status
      haben (erhalten, angelegt, abgebrochen, korrigiert). Offene bleiben
      unangetastet, egal wie alt — an ihnen haengt noch Arbeit.

      Wegfallen nur Felder, die nach der Vergabe niemand mehr liest:
      die Statushistorie, die Stimmen, der Itemlink, die Session, und was
      die Lootverfolgung waehrend des Kampfes brauchte (Quelle, Platz,
      Lootmethode, Schwierigkeit, Encounter-Kennung). Alles, was Plus Eins,
      Rotation, Auswertung, Erfolge, Abgleich und Export lesen, BLEIBT —
      deshalb muessen diese Leser nichts von einem Archiv wissen.

      Was die Statushistorie noch beantworten musste, steht danach in einem
      Feld: clean = false, wenn es je eine Korrektur oder einen Abbruch gab
      (Erfolg "Null Beschwerden"). archived = Zeitpunkt der Verdichtung.

      Im Journal fallen bei Eintraegen aelter als AFTER_DAYS die Felder
      before und after weg. Wer was wann geaendert hat, bleibt.

    WAS NICHT VERLORENGEHT:
      Die Webseite bekommt ueber den Export ohnehin nur die Felder, die hier
      bleiben. Die volle Geschichte steht also dort, wie bisher.
------------------------------------------------------------------------------]]

local _, GA = ...

local Archive = {}
GA.Modules.Archive = Archive

local Util = GA.Core.Util

Archive.AFTER_DAYS = 90

--- Was nach der Vergabe niemand mehr liest (geprueft am 03.10.2026 gegen
--- alle Leser von account.awards).
Archive.DROP = {
    "statusHistory", "votes", "itemLink", "sessionId",
    "sourceGuid", "slot", "lootMethod", "difficultyID", "encounterID",
}

local function finalStatus()
    local Status = GA.Data.Schema.LootStatus
    return {
        [Status.RECEIVED] = true, [Status.EQUIPPED] = true,
        [Status.CANCELLED] = true, [Status.CORRECTED] = true,
    }
end

--- Verdichtet eine Vergabe. Zweimal aufgerufen tut der zweite Aufruf nichts.
--- @return boolean ob etwas verdichtet wurde
function Archive.CompactAward(award, now)
    if type(award) ~= "table" or award.archived then return false end
    if not finalStatus()[award.status] then return false end

    local Status = GA.Data.Schema.LootStatus
    for _, step in ipairs(award.statusHistory or {}) do
        if step.status == Status.CORRECTED or step.status == Status.CANCELLED then
            award.clean = false
        end
    end
    for _, key in ipairs(Archive.DROP) do award[key] = nil end
    award.archived = now or Util.Now()
    return true
end

--- Verdichtet alles, was alt genug ist.
--- @return number vergaben, number journal
function Archive:Run(now)
    now = now or Util.Now()
    local db = GA.Core.Database and GA.Core.Database.account
    if not db then return 0, 0 end
    local grenze = now - self.AFTER_DAYS * 86400

    local vergaben = 0
    for _, award in pairs(db.awards or {}) do
        if (award.ts or now) < grenze and Archive.CompactAward(award, now) then
            vergaben = vergaben + 1
        end
    end

    local journal = 0
    for _, entry in ipairs(db.journal or {}) do
        if (entry.ts or now) < grenze and (entry.before ~= nil or entry.after ~= nil) then
            entry.before, entry.after = nil, nil
            journal = journal + 1
        end
    end

    db.archiveTs = now
    if vergaben > 0 and GA.Core.Callbacks then
        GA.Core.Callbacks:Fire("AWARDS_ARCHIVED", vergaben)
    end
    return vergaben, journal
end

function Archive:OnEnable()
    -- Nach dem Anmelden, wenn alles geladen ist — nicht im ersten Takt.
    local Compat = GA.Core.Compat
    if Compat and type(Compat.After) == "function" then
        Compat.After(20, function()
            local vergaben, journal = Archive:Run()
            if vergaben + journal > 0 and GA.Core.Debug then
                GA.Core.Debug:Print("core", "Archiv: %d Vergaben, %d Journaleintraege verdichtet", vergaben, journal)
            end
        end)
    end
end
