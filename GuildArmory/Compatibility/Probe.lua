--[[----------------------------------------------------------------------------
    Compatibility/Probe — was dieser Client fuer die offenen Erfolge hergibt.

    Kein UI ausser der Ausgabe von /ga probe.

    ===========================================================================
    WARUM DIESE DATEI UEBERHAUPT EXISTIERT
    ===========================================================================

    Von 272 Erfolgen sind 64 mit einer Regel hinterlegt. Bei den restlichen
    208 ist die Frage fast nie "wie rechnet man das", sondern "gibt dieser
    Client die Zahl ueberhaupt her".

    Und die Frage laesst sich von aussen NICHT beantworten. Forever ist der
    Retail-Client mit Vanilla-Inhalt: Er traegt die komplette Retail-API mit
    sich, inklusive C_Garrison und C_DelvesUI — Dinge, die es im Spiel gar
    nicht gibt. Ein `if C_MountJournal then` beweist nichts.

    Deshalb wird hier nicht gefragt, ob eine Funktion EXISTIERT, sondern was
    sie ZURUECKGIBT. Drei Ausgaenge:

        ja        liefert etwas Brauchbares — der Erfolg ist messbar
        leer      antwortet, aber ohne Inhalt (0 Reittiere, keine Berufe).
                  Das kann stimmen oder bedeuten, dass der Client es nicht
                  fuehrt. Nur ein Charakter, der es HAT, klaert das.
        nein      gibt es nicht oder wirft

    "leer" ist der wichtigste der drei. Ihn mit "nein" zu verwechseln
    verschenkt eine messbare Quelle; ihn mit "ja" zu verwechseln erzeugt
    Erfolge, die bei null kleben.

    ===========================================================================
    ZWEI ARTEN VON PRUEFUNG
    ===========================================================================

    SOFORT      Eine Funktion aufrufen und ansehen, was kommt. Das ist der
                Grossteil und beantwortet sich beim Ausfuehren.

    UEBER ZEIT  Ob ein EREIGNIS feuert, kann man nicht erfragen. ENCOUNTER_END
                gibt es auf dem Retail-Client — ob Forever es bei einem
                Vanilla-Boss ausloest, zeigt erst ein Bosskill. Diese Sonden
                zaehlen still mit und werden mit ausgegeben.

    Das Combat Log ist bereits gemessen und NICHT verfuegbar (0 Ereignisse in
    37 Kaempfen). Alles, was daran haengt — Todesursachen, vermeidbarer
    Schaden, Flaggenaufnahmen — bleibt draussen, bis jemand das Gegenteil
    misst.
------------------------------------------------------------------------------]]

local _, GA = ...

local Probe = {}
GA.Core.Probe = Probe

local isFunction = function(value) return type(value) == "function" end
local isTable = function(value) return type(value) == "table" end

Probe.YES = "ja"
Probe.EMPTY = "leer"
Probe.NO = "nein"

--- Ruft etwas auf und sagt, was dabei herauskam.
--- @return string zustand, string detail
local function call(fn, ...)
    if not isFunction(fn) then return Probe.NO, "Funktion fehlt" end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return Probe.NO, "wirft: " .. tostring(results[2]):sub(1, 60)
    end
    return Probe.YES, results
end

--- Eine Zahl, die etwas heisst.
local function number(fn, ...)
    local state, results = call(fn, ...)
    if state == Probe.NO then return state, results end

    local value = tonumber(results[2])
    if value == nil then return Probe.NO, "keine Zahl: " .. tostring(results[2]) end
    if value == 0 then return Probe.EMPTY, "0" end
    return Probe.YES, tostring(value)
end

--- Eine Liste, die etwas enthaelt.
local function list(fn, ...)
    local state, results = call(fn, ...)
    if state == Probe.NO then return state, results end

    local value = results[2]
    if not isTable(value) then return Probe.NO, "keine Tabelle: " .. type(value) end
    local count = #value
    if count == 0 then return Probe.EMPTY, "0 Eintraege" end
    return Probe.YES, count .. " Eintraege"
end

-- ============================================================ Sofortpruefung --
--
-- Reihenfolge: nach Erfolgsgruppen, nicht nach API-Familien. Wer das liest,
-- will wissen, was er davon hat.

Probe.CHECKS = {
    -- --------------------------------------------------------- Raid, Tode ---
    { key = "playerDead", was = "Eigener Tod erkennbar",
      fuer = "GA-112..116 Raidtode, GA-102 Der Unsterbliche",
      run = function()
          if not isFunction(_G.UnitIsDeadOrGhost) then return Probe.NO, "fehlt" end
          local ok, dead = pcall(_G.UnitIsDeadOrGhost, "player")
          if not ok then return Probe.NO, "wirft" end
          return Probe.YES, dead and "gerade tot" or "gerade lebendig"
      end },

    { key = "groupDeaths", was = "Tod anderer Gruppenmitglieder",
      fuer = "GA-106..111 Wipes, GA-101 Makelloser Sieg, GA-104 Letzter Mann",
      run = function()
          if not GA.has.groupApi or not isFunction(_G.UnitIsDeadOrGhost) then
              return Probe.NO, "Gruppen-API oder UnitIsDeadOrGhost fehlt"
          end
          local n = GA.Core.Compat.GetNumGroupMembers()
          if n == 0 then return Probe.EMPTY, "nicht in einer Gruppe — in einem Raid erneut pruefen" end
          local ok = pcall(_G.UnitIsDeadOrGhost, GA.Core.Compat.GetGroupUnit(1) or "player")
          return ok and Probe.YES or Probe.NO, n .. " Mitglieder lesbar"
      end },

    { key = "raidLeader", was = "Bin ich Raidleiter",
      fuer = "GA-147..150 Geleitete Raids",
      run = function()
          if not isFunction(_G.UnitIsGroupLeader) then return Probe.NO, "fehlt" end
          local ok, leader = pcall(_G.UnitIsGroupLeader, "player")
          if not ok then return Probe.NO, "wirft" end
          return Probe.YES, leader and "ja, gerade Leiter" or "gerade nicht Leiter"
      end },

    -- ------------------------------------------------------------- Bosse ---
    { key = "encounterApi", was = "Encounter-Ereignisse (Existenz)",
      fuer = "GA-086..095 Bosskills und Firstkills",
      run = function()
          -- Ob sie FEUERN, steht unten bei den Ereignissonden. Hier nur, ob
          -- der Client die Begriffe ueberhaupt kennt.
          if isTable(_G.C_EncounterJournal) then return Probe.YES, "C_EncounterJournal vorhanden" end
          return Probe.EMPTY, "kein Encounter Journal — Ereignisse trotzdem moeglich"
      end },

    -- ------------------------------------------------------- Combat Log ----
    { key = "combatLogFile", was = "Aufzeichnung in die Datei",
      fuer = "GA-106..121 Wipes und Tode, GA-101..105 — ueber das Begleitprogramm",
      run = function()
          -- DIE DATEI IST ETWAS ANDERES ALS DIE API.
          --
          -- Gemessen 18.09.2026: COMBAT_LOG_EVENT_UNFILTERED feuert nicht,
          -- CombatLogGetCurrentEventInfo fehlt — das Addon ist blind. Die
          -- Datei auf der Platte gibt es trotzdem und vollstaendig (gemessen
          -- 22.09.2026: 7994 Zeilen, Format 22, erweitertes Protokoll an).
          -- Lesen kann sie nur das Begleitprogramm.
          --
          -- Hier steht die Frage, an der alles haengt: Kann das Addon die
          -- Aufzeichnung selbst einschalten? Wenn nicht, muss sie jemand vor
          -- jedem Raid von Hand starten — und das wird jemand vergessen.
          if not isFunction(_G.LoggingCombat) then
              return Probe.NO, "LoggingCombat fehlt — /combatlog bleibt Handarbeit"
          end
          local ok, running = pcall(_G.LoggingCombat)
          if not ok then return Probe.NO, "LoggingCombat wirft" end
          return Probe.YES, running and "laeuft gerade" or "vorhanden, gerade aus"
      end },

    -- --------------------------------------------------------------- PvP ---
    { key = "pvpKills", was = "Ehrenhafte Siege insgesamt",
      fuer = "GA-191..195 Ehrenhafte Siege",
      run = function()
          if not isFunction(_G.GetPVPLifetimeStats) then return Probe.NO, "fehlt" end
          local ok, kills = pcall(_G.GetPVPLifetimeStats)
          if not ok then return Probe.NO, "wirft" end
          local value = tonumber(kills)
          if value == nil then return Probe.NO, "keine Zahl" end
          if value == 0 then return Probe.EMPTY, "0 — mit einem PvP-Charakter erneut pruefen" end
          return Probe.YES, tostring(value)
      end },

    { key = "pvpRank", was = "PvP-Rang",
      fuer = "GA-043, GA-202, GA-203 Ehrenrang",
      run = function()
          if isFunction(_G.UnitPVPRank) then
              local ok, rank = pcall(_G.UnitPVPRank, "player")
              if ok and tonumber(rank) and tonumber(rank) > 0 then
                  return Probe.YES, "Rang " .. tostring(rank)
              end
              if ok then return Probe.EMPTY, "Rang 0 oder keiner" end
          end
          return Probe.NO, "UnitPVPRank fehlt oder wirft"
      end },

    -- ---------------------------------------------------------- Sammlung ---
    { key = "mounts", was = "Reittiere (BESESSENE)",
      fuer = "GA-020, GA-236, GA-237 Reittiersammler",
      run = function()
          if not isTable(_G.C_MountJournal) then return Probe.NO, "C_MountJournal fehlt" end

          -- GetMountIDs LIEFERT ALLE, DIE DER CLIENT KENNT, nicht die
          -- eigenen. Die erste Fassung meldete stolz "136 Eintraege" und
          -- haette daraus "136 Reittiere besessen" gemacht — ein Erfolg, der
          -- sich selbst vergibt. Gezaehlt wird isCollected.
          local ok, ids = pcall(_G.C_MountJournal.GetMountIDs)
          if not ok or not isTable(ids) then return Probe.NO, "GetMountIDs liefert nichts" end
          if not isFunction(_G.C_MountJournal.GetMountInfoByID) then
              return Probe.EMPTY, #ids .. " bekannt, aber Besitz nicht pruefbar"
          end

          local owned = 0
          for _, id in ipairs(ids) do
              local okInfo, _, _, _, _, _, _, _, _, _, _, collected =
                  pcall(_G.C_MountJournal.GetMountInfoByID, id)
              if okInfo and collected then owned = owned + 1 end
          end
          if owned == 0 then
              return Probe.EMPTY, "0 von " .. #ids .. " besessen — mit einem Reittier erneut pruefen"
          end
          return Probe.YES, owned .. " von " .. #ids .. " besessen"
      end },

    { key = "pets", was = "Begleiter",
      fuer = "GA-238 Haustierfreund",
      run = function()
          if not isTable(_G.C_PetJournal) then return Probe.NO, "C_PetJournal fehlt" end
          return number(_G.C_PetJournal.GetNumPets)
      end },

    { key = "taxi", was = "Flugpunkte",
      fuer = "GA-040 Der Kartograph, GA-235 Flugnetz",
      run = function()
          if not isTable(_G.C_TaxiMap) then return Probe.NO, "C_TaxiMap fehlt" end

          -- GetAllTaxiNodes BRAUCHT EINE KARTEN-ID. Die erste Fassung rief
          -- sie ohne Argument auf, bekam "bad argument #1" und meldete
          -- "nein" — fuer eine API, die es sehr wohl gibt. Eine Sonde, die
          -- ihren eigenen Aufruffehler als fehlende Funktion ausgibt, misst
          -- sich selbst statt den Client.
          local okMap, mapID = pcall(_G.C_Map.GetBestMapForUnit, "player")
          if not okMap or not mapID then return Probe.EMPTY, "keine Karte fuer den Spieler" end

          local okNodes, nodes = pcall(_G.C_TaxiMap.GetAllTaxiNodes, mapID)
          if not okNodes or not isTable(nodes) then
              return Probe.NO, "wirft auch mit Karte " .. tostring(mapID)
          end
          if #nodes == 0 then
              return Probe.EMPTY, "0 auf Karte " .. tostring(mapID) .. " — in einem Aussengebiet erneut pruefen"
          end

          -- OFFEN: Ob ein Knoten BEKANNT ist, steckt vermutlich in node.state
          -- — was die Werte bedeuten, ist hier nicht gemessen. Gezaehlt wird
          -- deshalb erst einmal nur, dass die Liste kommt. Fuer GA-040
          -- ("alle Flugpunkte") braucht es die Unterscheidung noch.
          return Probe.YES, #nodes .. " Knoten auf Karte " .. tostring(mapID)
              .. " (bekannt/unbekannt noch nicht unterschieden)"
      end },

    { key = "exploration", was = "Erkundete Gebiete",
      fuer = "GA-231..234 Gebiete entdecken, GA-041 Weltenbummler",
      run = function()
          if not isTable(_G.C_MapExplorationInfo) then
              return Probe.NO, "C_MapExplorationInfo fehlt"
          end
          if not isTable(_G.C_Map) or not isFunction(_G.C_Map.GetBestMapForUnit) then
              return Probe.NO, "C_Map.GetBestMapForUnit fehlt"
          end
          local ok, mapID = pcall(_G.C_Map.GetBestMapForUnit, "player")
          if not ok or not mapID then return Probe.EMPTY, "keine Karte fuer den Spieler" end
          return list(_G.C_MapExplorationInfo.GetExploredMapTextures, mapID)
      end },

    { key = "bankSlots", was = "Gekaufte Bankfaecher",
      fuer = "GA-245 Bank ist voll",
      run = function()
          if not isFunction(_G.GetNumBankSlots) then return Probe.NO, "fehlt" end
          local ok, bought = pcall(_G.GetNumBankSlots)
          if not ok then return Probe.NO, "wirft" end
          -- Ausserhalb der Bank antwortet das oft mit 0. Das ist kein Nein.
          return (tonumber(bought) or 0) > 0 and Probe.YES or Probe.EMPTY,
                 tostring(bought) .. " (verlaesslich nur am Bankier)"
      end },

    -- ----------------------------------------------------------- Berufe ----
    { key = "professions", was = "Gelernte Hauptberufe",
      fuer = "GA-163..165, GA-022, GA-023 Berufe",
      run = function()
          local found = GA.Core.Compat.GetProfessions()
          if found == nil then return Probe.EMPTY, "GetProfessions liefert nichts — mit einem Beruf erneut pruefen" end
          if #found == 0 then return Probe.EMPTY, "keine gelernt" end
          local names = {}
          for _, p in ipairs(found) do
              names[#names + 1] = string.format("%s %d/%d", p.name, p.rank, p.maxRank)
          end
          return Probe.YES, table.concat(names, ", ")
      end },

    { key = "skillLines", was = "Faehigkeitsliste (Vanilla-Weg)",
      fuer = "Rueckfall fuer Berufe, GA-166 Rezeptjaeger",
      run = function()
          if not isFunction(_G.GetNumSkillLines) then return Probe.NO, "fehlt" end
          return number(_G.GetNumSkillLines)
      end },

    { key = "tradeSkill", was = "Berufsfenster-API",
      fuer = "GA-166, GA-167 Rezepte zaehlen",
      run = function()
          if isTable(_G.C_TradeSkillUI) then
              if isFunction(_G.C_TradeSkillUI.GetAllRecipeIDs) then
                  return list(_G.C_TradeSkillUI.GetAllRecipeIDs)
              end
              return Probe.EMPTY, "C_TradeSkillUI ohne GetAllRecipeIDs"
          end
          return Probe.NO, "C_TradeSkillUI fehlt"
      end },

    -- -------------------------------------------------------- Wirtschaft ---
    { key = "guildBank", was = "Gildenbank",
      fuer = "GA-173..181 Spenden, GA-038 Griff in die Kasse",
      run = function()
          if not isFunction(_G.GetNumGuildBankTabs) then
              return Probe.NO, "fehlt — Gildenbank gibt es in Vanilla-Inhalt nicht"
          end
          return number(_G.GetNumGuildBankTabs)
      end },

    -- ----------------------------------------------------------- Kalender --
    { key = "calendar", was = "Kalender",
      fuer = "GA-134..137 Geplante Raids in Folge",
      run = function()
          if not isTable(_G.C_Calendar) then return Probe.NO, "C_Calendar fehlt" end
          if not isFunction(_G.C_Calendar.GetNumDayEvents) then
              return Probe.EMPTY, "C_Calendar ohne GetNumDayEvents"
          end
          return Probe.YES, "vorhanden — Inhalt erst mit einem Termin pruefbar"
      end },

    -- ---------------------------------------------------------- Itemsets ---
    { key = "itemSets", was = "Set-Zugehoerigkeit eines Items",
      fuer = "GA-016..019, GA-075..078 Tier-Sets",
      run = function()
          if isTable(_G.C_Item) and isFunction(_G.C_Item.GetItemSetInfo) then
              return Probe.YES, "C_Item.GetItemSetInfo vorhanden"
          end
          if isFunction(_G.GetItemSetInfo) then return Probe.YES, "GetItemSetInfo vorhanden" end
          return Probe.NO, "keine Set-API — Setteile braeuchten eine eigene Itemliste"
      end },
}

-- ============================================================= Ereignisse ----
--
-- Ob ein Ereignis feuert, ist nicht erfragbar. Diese Sonden zaehlen still mit,
-- und /ga probe sagt, ob je etwas kam. "noch nie" heisst nach einem Raidabend
-- etwas anderes als nach fuenf Minuten in Orgrimmar — deshalb steht dabei,
-- seit wann gezaehlt wird.

Probe.EVENTS = {
    { event = "ENCOUNTER_START", fuer = "GA-086..095 Bosskills" },
    { event = "ENCOUNTER_END",   fuer = "GA-086..095 Bosskills, GA-101 ohne Tod" },
    { event = "BOSS_KILL",       fuer = "GA-086..095 Bosskills" },
    { event = "PLAYER_DEAD",     fuer = "GA-112..116 Raidtode" },
    { event = "PLAYER_MONEY",    fuer = "GA-122 Reparaturkosten" },
    { event = "SKILL_LINES_CHANGED", fuer = "GA-159..162 Hergestellte Gegenstaende" },
    { event = "TRADE_SKILL_SHOW", fuer = "GA-166, GA-167 Rezepte" },
}

local function eventStore()
    local account = GA.Core.Database.account
    account.probeEvents = account.probeEvents or { since = GA.Core.Util.Now() }
    return account.probeEvents
end

-- ================================================================ Ausgabe ----

--- Fuehrt alle Sofortpruefungen aus.
--- @return table { { key, was, fuer, state, detail } }, table zaehlung
function Probe:Run()
    local rows, counts = {}, { ja = 0, leer = 0, nein = 0 }

    for _, check in ipairs(self.CHECKS) do
        local ok, state, detail = pcall(check.run)
        if not ok then
            state, detail = self.NO, "Sonde selbst gescheitert: " .. tostring(state):sub(1, 50)
        end
        state = state or self.NO
        counts[state] = (counts[state] or 0) + 1
        rows[#rows + 1] = {
            key = check.key, was = check.was, fuer = check.fuer,
            state = state, detail = tostring(detail or ""),
        }
    end

    return rows, counts
end

--- Der vollstaendige Bericht als Text — zum Kopieren.
function Probe:Report()
    local rows, counts = self:Run()
    local out = {}

    -- select(4, ...) braucht einen Aufruf, der WIRKLICH mehrere Werte
    -- liefert. `GetBuildInfo and GetBuildInfo()` waere auf einen Wert
    -- gestutzt, und select haette geworfen — in der Sonde, die Fehler
    -- gerade vermeiden soll.
    local interfaceVersion = "?"
    if isFunction(_G.GetBuildInfo) then
        local ok, _, _, _, number = pcall(_G.GetBuildInfo)
        if ok and number then interfaceVersion = tostring(number) end
    end

    out[#out + 1] = string.format(
        "Guild Armory — Client-Sonde  (Addon %s, Interface %s)",
        tostring(GA.version), interfaceVersion)
    out[#out + 1] = string.format("ja: %d   leer: %d   nein: %d",
        counts.ja or 0, counts.leer or 0, counts.nein or 0)
    out[#out + 1] = ""
    out[#out + 1] = "SOFORT GEMESSEN"
    out[#out + 1] = string.rep("-", 60)

    for _, row in ipairs(rows) do
        out[#out + 1] = string.format("%-5s %-34s %s", row.state, row.was, row.detail)
        out[#out + 1] = string.format("      %s", row.fuer)
    end

    local store = eventStore()
    out[#out + 1] = ""
    out[#out + 1] = string.format("EREIGNISSE (gezaehlt seit %s)",
        GA.Core.Util.TimeAgo(store.since))
    out[#out + 1] = string.rep("-", 60)
    for _, entry in ipairs(self.EVENTS) do
        local count = store[entry.event] or 0
        out[#out + 1] = string.format("%-6s %-26s %s",
            count > 0 and "ja" or "noch nie", entry.event, entry.fuer)
    end

    out[#out + 1] = ""
    out[#out + 1] = "Combat Log: NICHT verfuegbar (gemessen 18.09.2026, 0 Ereignisse"
    out[#out + 1] = "in 37 Kaempfen). Alles, was daran haengt, bleibt unmessbar."

    return table.concat(out, "\n"), counts
end

-- ================================================================== Start ----

function Probe:OnEnable()
    local store = eventStore()
    for _, entry in ipairs(self.EVENTS) do
        GA.Core.Events:Register(entry.event, function()
            store[entry.event] = (store[entry.event] or 0) + 1
        end, "Probe")
    end
end
