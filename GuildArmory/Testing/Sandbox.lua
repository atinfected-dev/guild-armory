--[[----------------------------------------------------------------------------
    Testing/Sandbox — einen Raidabend durchspielen, ohne Raid.

    Loot-Council, Soft Reserves und die Vergabe lassen sich zu zweit kaum
    pruefen und allein gar nicht: Es braucht Gegenstaende, die fallen,
    Leute, die bieten, und ein Council, das abstimmt. Genau das stellt
    diese Datei her.

    ZWEI ZUSAGEN, UND SIE SIND WICHTIGER ALS ALLES ANDERE HIER.

    ERSTENS: NICHTS VERLAESST DIESEN CLIENT. Solange der Probebetrieb
    laeuft, gibt Compat.SendChatMessage nichts aus und Comm stellt nichts
    zu — beide an genau einer Stelle gesperrt, nicht in acht Aufrufern.
    Ein erfundener Gegenstand, der im Gildenchat verkuendet wird, ist nicht
    wieder einzufangen.

    ZWEITENS: JEDER ERFUNDENE DATENSATZ TRAEGT EIN MERKMAL. `simulated`
    steht auf jedem Award, jeder Reservierung, jedem Spieler. Daran raeumt
    Clear() wieder auf, daran erkennt die Anzeige sie, und daran weigert
    sich der Abgleich, sie weiterzugeben. Ein Testaward in der echten
    Historie waere kein Schoenheitsfehler: Plus Eins rechnet damit, die
    Statistik zaehlt ihn mit, und niemand sieht ihm an, woher er kam.

    Die Gegenstaende sind ECHTE Item-IDs aus Classic. Erfunden ist, dass
    sie gefallen sind — nicht, was sie sind. Nur so zeigen Tooltip, Symbol
    und Qualitaetsfarbe das, was sie im Ernstfall zeigen wuerden.

    Bedienung:  /ga sim
------------------------------------------------------------------------------]]

local _, GA = ...

local Sandbox = {}
GA.Modules.Sandbox = Sandbox

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Laeuft der Probebetrieb gerade?
Sandbox.active = false

--- Was der Riegel abgefangen hat. Eine Zahl, die steigt, ist der Beweis,
--- dass er wirkt — ohne sie muesste man ihm glauben.
Sandbox.blocked = { chat = 0, comm = 0 }

-- ================================================================== Vorrat ---

--- Echte Item-IDs aus Classic, quer durch die Qualitaeten und Slots.
---
--- Keine ausgedachten Zahlen: Eine ID, die es nicht gibt, liefert keinen
--- Tooltip, kein Symbol und keine Qualitaetsfarbe — dann prueft man die
--- Anzeige gegen leere Kaesten und haelt sie faelschlich fuer kaputt.
local ITEMS = {
    -- Legendaer
    { id = 19019, name = "Thunderfury, Blessed Blade of the Windseeker" },
    { id = 17182, name = "Sulfuras, Hand of Ragnaros" },
    { id = 17204, name = "Eye of Sulfuras" },

    -- Episch: Waffen
    { id = 17076, name = "Bonereaver's Edge" },
    { id = 18348, name = "Quel'Serrar" },
    { id = 17075, name = "Vis'kag the Bloodletter" },
    { id = 17103, name = "Azuresong Mageblade" },
    { id = 17104, name = "Spinal Reaper" },
    { id = 18805, name = "Core Hound Tooth" },
    { id = 18396, name = "Herald of Woe" },
    { id = 18822, name = "Claw of Chromaggus" },
    { id = 19351, name = "Ashjre'thul, Crossbow of Smiting" },
    { id = 18832, name = "Brutality Blade" },

    -- Episch: Ruestung
    { id = 16909, name = "Bloodfang Hood" },
    { id = 16905, name = "Bloodfang Chestpiece" },
    { id = 16846, name = "Giantstalker's Helmet" },
    { id = 16865, name = "Belt of Might" },
    { id = 16929, name = "Netherwind Crown" },
    { id = 16955, name = "Judgement Crown" },
    { id = 16947, name = "Earthfury Helmet" },
    { id = 16963, name = "Halo of Transcendence" },
    { id = 16921, name = "Felheart Shoulder Pads" },
    { id = 16897, name = "Cenarion Helm" },
    { id = 16899, name = "Cenarion Vestments" },
    { id = 18814, name = "Choker of the Fire Lord" },
    { id = 18813, name = "Talisman of Ephemeral Power" },
    { id = 17063, name = "Band of Accuria" },
    { id = 17065, name = "Medallion of Steadfast Might" },
    { id = 18820, name = "Talisman of Ephemeral Power" },
    { id = 19137, name = "Onslaught Girdle" },
    { id = 19406, name = "Drake Fang Talisman" },

    -- Selten: der Alltag, der die Liste fuellt
    { id = 12602, name = "Draconian Deflector" },
    { id = 13098, name = "Girdle of Uther" },
    { id = 12940, name = "Hyperion Legplates" },
    { id = 11994, name = "Stoneshell Guard" },
    { id = 13012, name = "Nightfall Gloves" },
    { id = 12651, name = "Girdle of Golem Strength" },
    { id = 13001, name = "Ancient Cornerstone Grimoire" },
    { id = 12103, name = "Shadowfang" },
    { id = 13045, name = "Warlord's Iron-Bracers" },
    { id = 12586, name = "Stoneraven" },
    { id = 11815, name = "Hand of Justice" },
    { id = 13095, name = "Bonecreeper Stylus" },
    { id = 12632, name = "Storm Gauntlets" },
    { id = 12640, name = "Legplates of the Eternal Guardian" },
    { id = 12798, name = "Tombstone Breastplate" },
    { id = 13245, name = "Berserker Bracers" },

    -- Ungewoehnlich: damit auch die untere Haelfte der Anzeige Farbe bekommt
    { id = 7728, name = "Stealthblade" },
    { id = 9395, name = "Sword of Corruption" },
    { id = 10250, name = "Skullsmasher" },
    { id = 6220, name = "Robe of the Magi" },
}

--- Erfundene Raidmitglieder.
---
--- Die Namen sind ausdruecklich keine, die jemand haben koennte: Ein
--- Testspieler, der wie ein Gildenmitglied heisst, taucht spaeter in einer
--- Liste auf und wird fuer echt gehalten.
local ROSTER = {
    { name = "Probe Anvil", class = "WARRIOR", role = "TANK" },
    { name = "Probe Brick", class = "WARRIOR", role = "DAMAGER" },
    { name = "Probe Candle", class = "PRIEST", role = "HEALER" },
    { name = "Probe Dust", class = "MAGE", role = "DAMAGER" },
    { name = "Probe Ember", class = "WARLOCK", role = "DAMAGER" },
    { name = "Probe Fern", class = "DRUID", role = "HEALER" },
    { name = "Probe Grit", class = "ROGUE", role = "DAMAGER" },
    { name = "Probe Haze", class = "HUNTER", role = "DAMAGER" },
    { name = "Probe Iron", class = "PALADIN", role = "HEALER" },
    { name = "Probe Jolt", class = "SHAMAN", role = "DAMAGER" },
}

--- Welche Rolle der wievielte Testspieler bekommt.
---
--- NICHT ALLE GLEICH. Wer voten darf, entscheidet Session:CanVote ueber
--- die Rolle — und das laesst sich nur pruefen, wenn es auch Leute gibt,
--- die NICHT voten duerfen. Ein Raid, in dem jeder im Council sitzt, sieht
--- nie so aus wie einer.
local SIM_ROLES = {
    [1] = "LOOTMASTER",
    [2] = "COUNCIL",
    [3] = "COUNCIL",
    [4] = "COUNCIL",
}

--- Das Praefix, an dem ein erfundener Name erkennbar ist.
---
--- VORNAME LEERZEICHEN NACHNAME — so heissen Charaktere auf Forever
--- wirklich ("Harry Ghosthook"). Testdaten, die das nicht nachbilden,
--- laufen an genau den Stellen vorbei, an denen Namen mit Leerzeichen
--- bisher Aerger gemacht haben: Fluesterziele, Chatzeilen, Kuerzung.
---
--- UND KEIN BINDESTRICH. Util.ShortName schneidet dort ab, weil in WoW
--- der Realm dahinter steht. Der erste Anlauf hiess "Probe-Anvil" und
--- wurde damit fuer ALLE zehn zu "Probe": Session:RecordBid legt die
--- Gebote unter dem gekuerzten Namen ab, also ueberschrieben sie sich
--- gegenseitig. Aus dreissig Geboten wurden drei, eines je Gegenstand —
--- genau das war zu sehen.
local MARKER = "Probe "

--- Ein eigener Zufall mit eigenem Faden.
---
--- Nicht math.random: Der Faden gehoert dem Spiel und anderen Addons.
--- Wer ihn setzt, um etwas wiederholbar zu machen, aendert nebenbei jeden
--- Wurf, jede Animation und jedes andere Addon, das ihn benutzt.
---
--- Derselbe Startwert ergibt denselben Durchlauf. Ein Fehler, der beim
--- Vorfuehren auftritt, laesst sich damit noch einmal herstellen.
local seed = 1
local function zufall(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return (seed % n) + 1
end

function Sandbox:Seed(wert)
    seed = math.max(1, math.floor(tonumber(wert) or 1))
    return seed
end

local function waehle(liste)
    return liste[zufall(#liste)]
end

-- ================================================================== Leute ----

--- Legt die erfundenen Raidmitglieder an.
---
--- Sie kommen in dieselben Tabellen wie echte Spieler, damit die Ansichten
--- sie wirklich so behandeln — ein Testlauf gegen einen Sonderweg prueft
--- den Sonderweg, nicht das Addon.
--- @return number angelegt
function Sandbox:Roster(anzahl)
    anzahl = math.min(tonumber(anzahl) or #ROSTER, #ROSTER)
    local db = GA.Core.Database.account
    db.characters = db.characters or {}

    local angelegt = 0
    for index = 1, anzahl do
        local entry = ROSTER[index]
        local guid = "Player-SIM-" .. index

        if not db.characters[guid] then
            -- UEBER GetCharacter, NICHT DIREKT IN DIE TABELLE.
            --
            -- Nur dieser Weg pflegt den Namensindex. Direkt geschrieben
            -- standen die Testspieler zwar in der Liste, waren aber ueber
            -- ihren Namen nicht auffindbar — "/ga dkp add 20 Probe Anvil"
            -- fand niemanden und gab wortlos die Hilfe aus.
            local character = GA.Core.Database:GetCharacter(guid, {
                name = entry.name, class = entry.class, level = 60,
            })

            -- Die uebrigen Felder auf DENSELBEN Datensatz, nicht auf einen
            -- neuen: Ein zweiter wuerde den gerade eingetragenen wieder
            -- ersetzen, und der Namensindex zeigte auf eine Leiche.
            character.role = entry.role
            -- ITEMLEVEL ALS GEMESSENER WERT MIT QUELLE, wie ueberall sonst
            -- auch. Ein Testdatensatz, der Felder weglaesst, die echte
            -- Daten haben, prueft die Anzeige nicht — er laesst sie nur
            -- nicht abstuerzen.
            character.itemLevel = { value = 60 + zufall(20), slots = 19 }
            character.equipmentTs = Util.Now() - zufall(3) * 3600
            character.source = "SIM"
            character.simulated = true
            -- EIN PROFIL DAZU, sonst stehen sie in der Charakteransicht
            -- nur unter "nicht zugeordnet" und koennen gar keine Rolle
            -- bekommen. Rollen haengen am Main eines Profils, nicht am
            -- Charakter.
            local Players = GA.Modules.Players
            if Players then
                local profil = Players:Create(guid, nil, entry.name)
                if profil then
                    profil.simulated = true
                    local rolle = SIM_ROLES[index]
                    if rolle then
                        GA.Core.Database:SetRole(guid, GA.const["ROLE_" .. rolle])
                    end
                end
            end

            angelegt = angelegt + 1
        end
    end

    -- STARTGUTHABEN, damit sich DKP ueberhaupt durchspielen laesst. Ohne
    -- Punkte kann niemand bieten, und der Modus saehe kaputt aus.
    --
    -- Verschieden viel: Ein Feld, in dem alle gleich stehen, zeigt nie,
    -- ob die Rangfolge stimmt.
    local Dkp = GA.Modules.Dkp
    if Dkp then
        for index, person in ipairs(self:Players()) do
            if not Dkp:Standing(person.guid) then
                Dkp:Post(person.guid, person.name, 40 + index * 15,
                    Dkp.KIND.ATTEND, "Probebetrieb", { simulated = true })
            end
        end
    end

    GA.Core.Callbacks:Fire("ROSTER_CHANGED")
    return angelegt
end

--- Alle erfundenen Spieler, als Liste.
function Sandbox:Players()
    local out = {}
    for guid, character in pairs(GA.Core.Database.account.characters or {}) do
        if character.simulated then
            out[#out + 1] = { guid = guid, name = character.name,
                              class = character.class, role = character.role,
                              itemLevel = character.itemLevel and character.itemLevel.value }
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

-- ================================================================ Beute ------

--- Laesst Gegenstaende fallen.
--- @return table awardIds
function Sandbox:Drop(anzahl)
    anzahl = math.max(1, math.min(tonumber(anzahl) or 6, #ITEMS))
    local Awards = GA.Modules.Awards
    local ids = {}

    for _ = 1, anzahl do
        local vorlage = waehle(ITEMS)
        local info = Compat.GetItemInfo(vorlage.id)

        local award = Awards:Create({
            itemID = vorlage.id,
            -- Der Name aus dem Client, wenn er ihn kennt. Die Vorlage ist
            -- nur der Rueckfall: Sie soll die Anzeige nicht schoener
            -- machen, als sie im Ernstfall waere.
            name = (info and info.name) or vorlage.name,
            link = info and info.link,
            quality = info and info.quality,
        }, {
            sourceName = "Probelauf",
            instanceName = "Probelauf",
            lootMethod = "master",
            reason = "Probebetrieb",
        })

        award.simulated = true
        ids[#ids + 1] = award.id
    end

    return ids
end

-- =============================================================== Durchlauf ---

--- Oeffnet eine Sitzung ueber alles, was gerade erkannt ist.
function Sandbox:Session(awardIds)
    local Session = GA.Modules.Session
    if not Session then return nil, "nomodule" end

    -- force: Die Berechtigung des Gastgebers wird hier absichtlich
    -- uebergangen. Wer allein testet, ist selten Plündermeister seiner
    -- eigenen Gilde — und die Pruefung dieser Berechtigung ist nicht das,
    -- was hier geprueft werden soll.
    local session, grund = Session:Open(awardIds, { force = true })
    if not session then return nil, grund end

    session.simulated = true
    return session
end

--- Oeffnet das Gebotsfenster fuer DICH.
---
--- Im Ernstfall kommt es ueber die Leitung: Der Plündermeister oeffnet eine
--- Sitzung, sein Client schickt SOPEN und je ein SITEM, und daraus baut
--- Session.incoming die Ankuendigung, auf die das Fenster aufgeht.
---
--- Im Probebetrieb ist die Leitung gesperrt — sonst gingen die Gebote der
--- erfundenen Spieler an die echte Gilde. Also wird dieselbe Ankuendigung
--- hier von Hand gebaut. Das Fenster bekommt damit genau das, was es sonst
--- auch bekommt; nur der Weg dorthin ist ein anderer.
---
--- Darin waehlst du BiS, Main-Spec, Major, Minor, Off-Spec, Transmog oder
--- Pass — je Gegenstand. Deine Wahl landet ueber Session:RecordBid im
--- selben Topf wie die der erfundenen Spieler.
--- @return boolean ob das Fenster aufgegangen ist
function Sandbox:ShowBidFrame(session)
    local Session = GA.Modules.Session
    if not session or not GA.UI.BidFrame then return false end

    local identity = Compat.GetPlayerIdentity()
    local items = {}
    for _, awardId in ipairs(session.awardIds) do
        local award = GA.Modules.Awards:Get(awardId)
        if award and award.itemID then
            items[#items + 1] = { awardId = awardId, itemID = award.itemID }
        end
    end

    if #items == 0 then return false end

    Session.incoming = {
        id = session.id,
        host = identity.name or "Probelauf",
        items = items,
    }

    GA.UI.BidFrame:Show(Session.incoming)
    return true
end

--- Laesst die erfundenen Spieler bieten.
---
--- NICHT ALLE BIETEN AUF ALLES. Ein Durchlauf, in dem jeder auf jedes
--- Stueck bietet, sieht nie so aus wie ein Abend — und genau die
--- unbesetzten Faelle sind die, in denen eine Liste leer bleibt oder eine
--- Abstimmung ohne Kandidaten dasteht.
--- @return number gebote
function Sandbox:Bids(sessionId)
    local Session = GA.Modules.Session
    local session = Session and Session:Get(sessionId)
    if not session then return 0 end

    local antworten = Session:Responses()
    if #antworten == 0 then return 0 end

    local spieler = self:Players()
    if #spieler == 0 then return 0 end

    local gebote = 0
    for _, awardId in ipairs(session.awardIds) do
        for _, person in ipairs(spieler) do
            -- Etwa zwei von drei bieten.
            if zufall(3) > 1 then
                local antwort = waehle(antworten)
                local ok = Session:RecordBid(sessionId, awardId, person.name, {
                    response = antwort.key,
                    class = person.class,
                    guid = person.guid,
                    itemLevel = person.itemLevel,
                    note = "Probebetrieb",
                })
                if ok then gebote = gebote + 1 end
            end
        end
    end

    return gebote
end

--- Laesst das Council abstimmen.
---
--- Gewaehlt wird nur unter denen, die auch geboten haben: Eine Stimme fuer
--- jemanden, der gar nicht mitbietet, gibt es im Ernstfall nicht, und ein
--- Testlauf, der sie erzeugt, prueft einen Zustand, den es nicht gibt.
--- @return number stimmen
function Sandbox:Votes(sessionId)
    local Session = GA.Modules.Session
    local session = Session and Session:Get(sessionId)
    if not session then return 0 end

    local identity = Compat.GetPlayerIdentity()
    local stimmen = 0

    for _, awardId in ipairs(session.awardIds) do
        local bieter = {}
        for name in pairs(session.responses[awardId] or {}) do
            bieter[#bieter + 1] = name
        end
        table.sort(bieter)

        if #bieter > 0 then
            -- NUR WER AUCH ABSTIMMEN DARF.
            --
            -- Hier stimmte vorher jedes erfundene Mitglied mit: elf Stimmen
            -- auf einen Gegenstand. Das ist kein Council mehr, sondern eine
            -- Umfrage — und es verdeckt genau den Fall, den man pruefen
            -- will, naemlich dass die Stimme eines einfachen Mitglieds
            -- abgelehnt wird.
            local waehler = {}
            if Session:CanVote(identity.guid) then
                waehler[#waehler + 1] = { guid = identity.guid, name = identity.name }
            end
            for _, person in ipairs(self:Players()) do
                if Session:CanVote(person.guid) then
                    waehler[#waehler + 1] = person
                end
            end

            for _, person in ipairs(waehler) do
                local kandidat = bieter[zufall(#bieter)]
                if Session:RecordVote(sessionId, awardId, person.guid,
                    kandidat, person.name)
                then
                    stimmen = stimmen + 1
                end
            end
        end
    end

    return stimmen
end

--- Vergibt jedes Stueck an den Fuehrenden.
--- @return number vergeben, number ohneKandidat
function Sandbox:Award(sessionId)
    local Session = GA.Modules.Session
    local session = Session and Session:Get(sessionId)
    if not session then return 0, 0 end

    local vergeben, leer = 0, 0
    for _, awardId in ipairs(session.awardIds) do
        local tally = Session:Tally(sessionId, awardId)
        local bester = tally and tally[1]

        if bester and bester.name then
            if Session:AwardTo(sessionId, awardId, bester.name) then
                vergeben = vergeben + 1
            end
        else
            -- KEIN KANDIDAT IST EIN ERGEBNIS, KEIN FEHLER. Es passiert an
            -- jedem Abend, und die Anzeige muss damit umgehen koennen.
            leer = leer + 1
        end
    end

    return vergeben, leer
end

--- Fuellt die Soft Reserves.
--- @return number eintraege
function Sandbox:Reserves()
    local SoftRes = GA.Modules.SoftRes
    if not SoftRes then return 0 end

    if not SoftRes:Current() then SoftRes:Open({ force = true }) end
    local runde = SoftRes:Current()
    if runde then runde.simulated = true end

    local eintraege = 0
    for _, person in ipairs(self:Players()) do
        -- Jeder reserviert ein oder zwei Stuecke — und manche dasselbe.
        -- Umstrittene Reservierungen sind der Fall, der interessant ist.
        for _ = 1, zufall(2) do
            local vorlage = ITEMS[zufall(math.min(4, #ITEMS))]
            local ok = SoftRes:Add({ name = person.name, guid = person.guid,
                                     class = person.class },
                vorlage.id, "sim")
            if ok then eintraege = eintraege + 1 end
        end
    end

    return eintraege
end

-- ============================================================== Aufraeumen ---

--- Entfernt alles, was den Probebetrieb traegt — und nur das.
---
--- Geht ueber das MERKMAL, nicht ueber den Zeitpunkt oder die Reihenfolge.
--- Ein Aufraeumen, das "alles seit X" loescht, nimmt echte Daten mit, die
--- waehrenddessen entstanden sind.
--- @return table zahlen
function Sandbox:Clear()
    local db = GA.Core.Database.account
    local weg = { awards = 0, characters = 0, sessions = 0, reserves = 0, profile = 0 }

    for id, award in pairs(db.awards or {}) do
        if award.simulated then db.awards[id] = nil weg.awards = weg.awards + 1 end
    end

    for guid, character in pairs(db.characters or {}) do
        if character.simulated then
            db.characters[guid] = nil
            -- DIE ROLLE MIT. Bliebe sie stehen, saesse ein Spieler, den es
            -- nicht mehr gibt, weiter im Council — und in der
            -- Rollenuebersicht stuende ein Eintrag ohne Namen dahinter.
            if db.roles then db.roles[guid] = nil end
            weg.characters = weg.characters + 1
        end
    end

    for id, profil in pairs(db.players or {}) do
        if profil.simulated then
            db.players[id] = nil
            weg.profile = (weg.profile or 0) + 1
        end
    end

    for id, session in pairs(db.sessions or {}) do
        if session.simulated then
            db.sessions[id] = nil
            weg.sessions = weg.sessions + 1
        end
    end

    -- Die Soft-Reserve-Runde: nur die simulierte, und nur ihre Eintraege.
    local runde = db.softResRound
    if runde and runde.simulated then
        weg.reserves = runde.items and #runde.items or 0
        db.softResRound = nil
    elseif runde and runde.items then
        for index = #runde.items, 1, -1 do
            local eintrag = runde.items[index]
            if eintrag.name and string.sub(eintrag.name, 1, #MARKER) == MARKER then
                table.remove(runde.items, index)
                weg.reserves = weg.reserves + 1
            end
        end
    end

    if GA.Modules.Dkp then
        weg.dkp = GA.Modules.Dkp:ClearSimulated()
    end

    GA.Core.Callbacks:Fire("AWARDS_CHANGED")
    GA.Core.Callbacks:Fire("ROSTER_CHANGED")
    GA.Core.Callbacks:Fire("SESSION_CHANGED")
    return weg
end

--- Zaehlt, was gerade an Erfundenem im Bestand liegt.
function Sandbox:Count()
    local db = GA.Core.Database.account
    local zahlen = { awards = 0, characters = 0, sessions = 0 }

    for _, award in pairs(db.awards or {}) do
        if award.simulated then zahlen.awards = zahlen.awards + 1 end
    end
    for _, character in pairs(db.characters or {}) do
        if character.simulated then zahlen.characters = zahlen.characters + 1 end
    end
    for _, session in pairs(db.sessions or {}) do
        if session.simulated then zahlen.sessions = zahlen.sessions + 1 end
    end

    return zahlen
end

-- =============================================================== Schalter ----

--- Schaltet den Probebetrieb ein oder aus.
---
--- AUSSCHALTEN RAEUMT NICHT AUF. Das sind zwei verschiedene Absichten: Man
--- schaltet aus, um das Ergebnis anzusehen, ohne dass weiter nichts
--- hinausgeht. Wer loeschen will, sagt das.
function Sandbox:SetActive(an)
    self.active = an and true or false
    if self.active then
        self.blocked.chat = 0
        self.blocked.comm = 0
    end
    GA.Core.Callbacks:Fire("SANDBOX_CHANGED")
    return self.active
end

--- Der ganze Durchlauf in einem Zug.
--- @return table bericht
function Sandbox:Run(anzahlItems)
    local bericht = {}

    self:SetActive(true)
    bericht.spieler = self:Roster()
    bericht.gefallen = self:Drop(anzahlItems)

    local session, grund = self:Session(bericht.gefallen)
    if not session then
        bericht.fehler = grund
        return bericht
    end

    bericht.sessionId = session.id

    -- ERST DEIN FENSTER, DANN DIE ERFUNDENEN GEBOTE. So siehst du die
    -- Liste noch leer und kannst selbst waehlen, bevor die anderen
    -- dazukommen — im Ernstfall ist es genauso.
    bericht.gebotsfenster = self:ShowBidFrame(session)
    bericht.gebote = self:Bids(session.id)
    bericht.stimmen = self:Votes(session.id)

    -- HIER WIRD NICHT VERGEBEN.
    --
    -- Der Durchlauf stellt die LAGE her: Gegenstaende liegen da, Gebote
    -- sind abgegeben, das Council hat gestimmt. Das Vergeben ist der
    -- Schritt, den man pruefen will — also macht ihn der Mensch, im
    -- Council-Fenster.
    --
    -- Vorher vergab der Durchlauf alles selbst. Danach war jeder
    -- Gegenstand im Zustand AWARDED, und ein Klick auf "Vergeben" kam
    -- zurueck mit "forbidden": AWARDED -> AWARDED gibt es nicht, und das
    -- ist richtig so. Nur war der Grund nicht zu sehen.
    --
    -- Wer es doch automatisch will: /ga sim award.
    return bericht
end
