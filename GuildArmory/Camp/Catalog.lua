--[[----------------------------------------------------------------------------
    Camp/Catalog — was es an Lagerausbauten gibt.

    NUR DATEN. Keine Logik, keine Ereignisse, kein UI. Die Auswertung steht in
    Camp/Camp.lua, die Anzeige in UI/CampFrame.lua.

    ===========================================================================
    WOHER DIESE ZAHLEN STAMMEN — UND WAS DAS HEISST
    ===========================================================================

    Das Lagerfeuer-System ist ein Inhalt von WoW: Forever. Es gibt ihn auf
    keinem anderen Client, also auch in keiner Schnittstellendokumentation und
    in keinem Probelauf dieses Addons. Die Gegenstands- und Fertigkeitskennungen
    hier sind ABGESCHRIEBENE BEOBACHTUNG, nicht gemessene Wahrheit.

    Deshalb behandelt das Addon sie auch so:

      * Die NAMEN stehen hier nicht. Der Client kennt sie und zwar uebersetzt —
        eine fest eingetragene englische Liste waere eine zweite Quelle, die
        irgendwann von der ersten abweicht. Bis ein Name geladen ist, zeigt die
        Oberflaeche die Kennung.
      * `/ga camp why` nennt fuer JEDE dieser Kennungen, was dieser Client
        daraus macht: Name, Symbol, Benutzen-Zauber. Eine falsche Zahl faellt
        damit in einer Zeile auf, statt sich als "geht nicht" zu tarnen.
      * Stimmt eine Kennung nicht, faellt genau dieser eine Eintrag aus. Der
        Rest laeuft weiter.

    ===========================================================================
    DIE REIHENFOLGE VON ITEMS IST EIN VERTRAG
    ===========================================================================

    Was ein Client ueber seinen Beutel verschickt, ist eine Zeichenkette aus
    "0" und "1" — eine Stelle je Eintrag in Catalog.items, in genau dieser
    Reihenfolge. Wer hier einen Gegenstand EINFUEGT oder ENTFERNT, aendert die
    Bedeutung jeder folgenden Stelle.

    Darum haengt an der Laenge eine Pruefung: Eine Nachricht, deren Zeichenkette
    nicht genauso lang ist wie der eigene Katalog, wird verworfen statt falsch
    gelesen. Zwei Clients mit verschiedenen Addon-Fassungen zeigen einander dann
    nichts an — was richtig ist. Sie zeigten sonst das Falsche.

    Neue Gegenstaende gehoeren deshalb ans ENDE der jeweiligen Berufsliste,
    nicht in die Mitte.
------------------------------------------------------------------------------]]

local _, GA = ...

local Catalog = {}
GA.Data.CampCatalog = Catalog

--- Der Buff, den ein fertiges Lager gibt.
Catalog.BUFF = 1229741

--- Wie lange eine Aufstellung sperrt, in Sekunden.
---
--- Eine Stunde. Nicht gemessen, sondern die Laufzeit des Buffs — wer sein
--- Stueck gestellt hat, ist bis dahin durch. Liegt der Wert daneben, steht
--- in der Leiste eine Uhr, die zu frueh oder zu spaet abläuft; falsche
--- Gegenstaende zeigt sie deswegen nicht an.
Catalog.COOLDOWN = 3600

--- Ab welcher Fertigkeit eine Ausbaustufe benutzbar ist.
--- Stufe 1 ab 20, Stufe 2 ab 140, Stufe 3 ab 300.
Catalog.TIER_SKILL = { 20, 140, 300 }

--- Die Lagerfeuer selbst, aufsteigend nach Ausbaustufe.
---
--- Sie zaehlen NICHT zu den Ausbauten: Ein Lagerfeuer ist der Platz, auf den
--- die anderen ihre Sachen stellen. Wer eines aufstellt, loest deshalb die
--- Standortmeldung aus statt der eigenen Sperrzeit.
Catalog.CAMPFIRES = { 279981, 279961, 279974, 279982 }

--- Berufe mit Lagerausbauten.
---
--- `line` ist die Kennung der Fertigkeitslinie, wie GetProfessionInfo sie an
--- siebter Stelle liefert. Zugeordnet wird ueber sie und nie ueber den Namen:
--- "Schneiderei" und "Tailoring" sind derselbe Beruf.
---
--- `kind` entscheidet die Spalte in der Leiste:
---   PRIMARY   die beiden Hauptberufe, in der Reihenfolge des Clients
---   FIRSTAID  feste dritte Spalte
---   FISHING   feste vierte Spalte
---
--- Kochen fehlt mit Absicht: Dafuer gibt es keine Lagerausbaute.
Catalog.professions = {
    { key = "ALCHEMY",        line = 171, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_Alchemy",
      items = { { id = 279956, tier = 1 }, { id = 279970, tier = 2 }, { id = 279990, tier = 3 } } },

    { key = "BLACKSMITHING",  line = 164, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_BlackSmithing",
      items = { { id = 279944, tier = 1 }, { id = 279988, tier = 2 }, { id = 279955, tier = 3 } } },

    { key = "ENCHANTING",     line = 333, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_Engraving",
      items = { { id = 279976, tier = 1 }, { id = 279985, tier = 2 }, { id = 279987, tier = 3 } } },

    { key = "ENGINEERING",    line = 202, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_Engineering",
      items = { { id = 279950, tier = 1 }, { id = 279949, tier = 2 }, { id = 279989, tier = 3 } } },

    { key = "HERBALISM",      line = 182, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_Herbalism",
      items = { { id = 279962, tier = 1 }, { id = 279964, tier = 2 }, { id = 279947, tier = 3 } } },

    { key = "LEATHERWORKING", line = 165, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_LeatherWorking",
      items = { { id = 279978, tier = 1 }, { id = 279941, tier = 2 }, { id = 279945, tier = 3 } } },

    { key = "MINING",         line = 186, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_Mining",
      items = { { id = 279960, tier = 1 }, { id = 279948, tier = 2 }, { id = 279952, tier = 3 } } },

    { key = "SKINNING",       line = 393, kind = "PRIMARY",
      icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
      items = { { id = 279979, tier = 1 }, { id = 279969, tier = 2 }, { id = 279938, tier = 3 } } },

    -- Zwei Banner auf Stufe 1: je eines fuer Allianz und Horde. Beide stehen
    -- in der Liste, weil ein Client beide Kennungen kennen muss, um die
    -- Nachricht der Gegenseite nicht zu verwerfen.
    { key = "TAILORING",      line = 197, kind = "PRIMARY",
      icon = "Interface\\Icons\\Trade_Tailoring",
      items = { { id = 279972, tier = 1 }, { id = 279973, tier = 1 },
                { id = 279943, tier = 2 }, { id = 279959, tier = 3 } } },

    { key = "FIRSTAID",       line = 129, kind = "FIRSTAID",
      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
      items = { { id = 279968, tier = 1 }, { id = 279940, tier = 2 }, { id = 279951, tier = 3 } } },

    { key = "FISHING",        line = 356, kind = "FISHING",
      icon = "Interface\\Icons\\Trade_Fishing",
      items = { { id = 279967, tier = 1 }, { id = 279965, tier = 2 }, { id = 279966, tier = 3 } } },
}

-- ============================================================== Aufbereitung -

--- Alle Ausbauten flach, in Uebertragungsreihenfolge.
--- @type table { { id, tier, profession } }
Catalog.items = {}

--- Von der Gegenstandskennung zum Eintrag.
Catalog.byItem = {}

--- Von der Fertigkeitslinie zum Beruf.
Catalog.byLine = {}

--- Ist diese Kennung ein Lagerfeuer?
Catalog.isCampfire = {}

for _, profession in ipairs(Catalog.professions) do
    Catalog.byLine[profession.line] = profession

    for _, item in ipairs(profession.items) do
        item.profession = profession
        item.index = #Catalog.items + 1
        Catalog.items[item.index] = item
        Catalog.byItem[item.id] = item
    end
end

for _, itemID in ipairs(Catalog.CAMPFIRES) do
    Catalog.isCampfire[itemID] = true
end

--- Laenge der Beutel-Zeichenkette. Siehe Dateikopf: Wer sie aendert, aendert
--- die Bedeutung jeder Stelle — und darum lehnt der Empfaenger jede Nachricht
--- ab, deren Zeichenkette anders lang ist.
Catalog.WIDTH = #Catalog.items

--- Welche Ausbaustufe erreicht diese Fertigkeit?
--- @return number 0..3  0 = noch keine
function Catalog.TierFor(rank)
    rank = tonumber(rank) or 0
    local tier = 0
    for stufe, noetig in ipairs(Catalog.TIER_SKILL) do
        if rank >= noetig then tier = stufe end
    end
    return tier
end
