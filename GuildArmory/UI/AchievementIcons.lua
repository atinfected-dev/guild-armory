--[[----------------------------------------------------------------------------
    UI/AchievementIcons — welches Symbol zu welchem Erfolg gehoert.

    Kein Zustand, keine Daten: eine Zuordnung von Text auf Bild.

    ===========================================================================
    WARUM NICHT EIN SYMBOL JE KATEGORIE
    ===========================================================================

    Dreizehn Kategorien auf 272 Erfolge heisst: In einer Liste von zwanzig
    sichtbaren Zeilen stehen fuenf mal dasselbe Bild. Ein Symbol, das sich
    staendig wiederholt, traegt keine Information mehr — es ist dann nur noch
    eine Verzierung am Zeilenanfang.

    Deshalb entscheidet hier der TEXT des Erfolgs, nicht seine Kategorie. Wer
    "Erster Ragnaros-Kill" liest, soll Feuer sehen; wer "25 Wipes" liest,
    einen Totenschaedel. Die Kategorie bleibt als Rueckfall darunter.

    ===========================================================================
    WAS HIER GERATEN IST UND WAS NICHT
    ===========================================================================

    DIE PFADE SIND GEWAEHLT, NICHT GEMESSEN.

    Es gibt keinen Weg, von aussen zu pruefen, welche Symboldateien dieser
    Client mitbringt — das weiss nur das laufende Spiel. Jeder Pfad hier ist
    deshalb eine begruendete Annahme, und jede einzelne wird zur Laufzeit
    geprueft (Theme.TextureExists). Was fehlt, faellt auf das Symbol der
    Kategorie zurueck, und erst danach auf das Fragezeichen. Ein falscher Pfad
    macht die Zeile also schlechter, nie kaputt.

    Damit aus dem Raten eine Messung wird, gibt es Icons:Probe(). /ga icons
    zeigt in einem kopierbaren Fenster, welche Pfade dieser Client NICHT
    kennt. Diese Liste ist die Korrektur — nicht das Herumprobieren im Spiel.

    ===========================================================================
    WIE VERGLICHEN WIRD
    ===========================================================================

    Wortwoertlich und mit Beachtung der Gross-/Kleinschreibung, gegen den
    Katalogtext, wie er dasteht. Das ist Absicht:

      "Jäger"  trifft "Erster Jäger auf Stufe 60"
               und NICHT "Bossjäger", "Rezeptjäger", "Heilerjäger"

    Ein klein geschriebenes Wortende ist hier also die Unterscheidung zwischen
    einer Klasse und einem Spitznamen. Ein Kleinschreib-Vergleich haette neun
    Klassenerfolge falsch bebildert.
------------------------------------------------------------------------------]]

local _, GA = ...

local Icons = {}
GA.UI.AchievementIcons = Icons

local Theme = GA.UI.Theme

--- Wenn gar nichts passt. Dieses Symbol gibt es ueberall.
Icons.FALLBACK = [[Interface\Icons\INV_Misc_QuestionMark]]

--- Der Rueckfall je Kategorie: das gemeinsame Thema der Gruppe.
Icons.CATEGORY = {
    FIRSTS     = [[Interface\Icons\INV_BannerPVP_01]],
    LEVEL      = [[Interface\Icons\INV_Misc_Rune_01]],
    LOOT       = [[Interface\Icons\INV_Misc_Bag_08]],
    RAID       = [[Interface\Icons\INV_Misc_Head_Dragon_01]],
    WIPES      = [[Interface\Icons\INV_Misc_Bone_HumanSkull_01]],
    ATTENDANCE = [[Interface\Icons\INV_Misc_PocketWatch_01]],
    MASTER     = [[Interface\Icons\INV_Misc_Gear_01]],
    PROFESSION = [[Interface\Icons\Trade_BlackSmithing]],
    ECONOMY    = [[Interface\Icons\INV_Misc_Coin_01]],
    PVP        = [[Interface\Icons\INV_Sword_04]],
    SOCIAL     = [[Interface\Icons\INV_Misc_GroupLooking]],
    COLLECTION = [[Interface\Icons\INV_Misc_Gem_Pearl_02]],
    SECRET     = [[Interface\Icons\INV_Misc_Key_03]],
}

--- Klassen gehen einen eigenen Weg: Der Client bringt dafuer fertige
--- Klassensymbole mit (Atlas), und die sehen besser aus als jedes Item-Icon.
--- Theme.SetClassIcon prueft am Rueckgabewert, ob es sie wirklich gibt.
---
--- Verglichen wird nur die BESCHREIBUNG. Im Namen stehen Klassenwoerter, die
--- nichts mit der Klasse zu tun haben: "Heiliger Krieger" ist der Paladin.
Icons.CLASS = {
    { "Krieger",      "WARRIOR" },
    { "Magier",       "MAGE" },
    { "Schurke",      "ROGUE" },
    { "Jäger",        "HUNTER" },
    { "Hexenmeister", "WARLOCK" },
    { "Priester",     "PRIEST" },
    { "Paladin",      "PALADIN" },
    { "Schamane",     "SHAMAN" },
    { "Druide",       "DRUID" },
}

--- Die Regeln, der Reihe nach. Die erste, die passt, gewinnt — deshalb steht
--- das Besondere oben und das Allgemeine unten.
Icons.RULES = {
    -- ---------------------------------------------------------- Bosse ------
    { "Ragnaros",     [[Interface\Icons\Spell_Fire_SelfDestruct]] },
    { "Onyxia",       [[Interface\Icons\INV_Misc_Head_Dragon_01]] },
    { "Nefarian",     [[Interface\Icons\INV_Misc_Head_Dragon_Black]] },
    { "Thun",         [[Interface\Icons\Spell_Shadow_EvilEye]] },
    { "Thuzad",       [[Interface\Icons\Spell_Frost_ChillingBlast]] },
    { "Molten Core",  [[Interface\Icons\Spell_Fire_Fire]] },
    { "Kernschmelze", [[Interface\Icons\Spell_Fire_Fire]] },

    -- ---------------------------------------------------------- Fraktion ---
    { "Horde",   [[Interface\Icons\INV_BannerPVP_02]] },
    { "Allianz", [[Interface\Icons\INV_BannerPVP_01]] },

    -- ---------------------------------------------------- Itemqualitaet ----
    { "legendär", [[Interface\Icons\INV_Hammer_Unique_Sulfuras]] },
    { "seltenes Item", [[Interface\Icons\INV_Misc_Gem_Sapphire_02]] },
    { "Blaue Stunde",  [[Interface\Icons\INV_Misc_Gem_Sapphire_02]] },

    -- --------------------------------------------------------- Ausruestung -
    { "Set-Item",      [[Interface\Icons\INV_Helmet_08]] },
    { "Setbonus",      [[Interface\Icons\INV_Shoulder_25]] },
    { "Setteile",      [[Interface\Icons\INV_Shoulder_25]] },
    { "Achtteiler",    [[Interface\Icons\INV_Shoulder_25]] },
    -- Vor "Ausrüstungsslot": "Nackt und furchtlos" ist kein Ruestungserfolg.
    { "leeren Ausrüstungsslot", [[Interface\Icons\INV_Shirt_White_01]] },
    { "roten Ausrüstungsteil",  [[Interface\Icons\Trade_Engineering]] },
    { "Ausrüstungsslot", [[Interface\Icons\INV_Chest_Plate06]] },
    { "Resistenz-Set", [[Interface\Icons\INV_Chest_Chain_05]] },
    { "Feuerresistenz",[[Interface\Icons\Spell_Fire_FireArmor]] },
    { "Naturresistenz",[[Interface\Icons\Spell_Nature_ResistNature]] },
    { "Frostresistenz",[[Interface\Icons\Spell_Frost_FrostArmor02]] },
    { "Outfit",        [[Interface\Icons\INV_Shirt_GreenNoble_01]] },

    -- ------------------------------------------------------------ Beute ----
    { "episch",  [[Interface\Icons\INV_Misc_Gem_Amethyst_02]] },
    { "Epic",    [[Interface\Icons\INV_Misc_Gem_Amethyst_02]] },
    { "Lila",    [[Interface\Icons\INV_Misc_Gem_Amethyst_02]] },
    { "passen",  [[Interface\Icons\Spell_Holy_SealOfSalvation]] },
    { "gepasst", [[Interface\Icons\Spell_Holy_SealOfSalvation]] },
    { "Loot-Pässen", [[Interface\Icons\Spell_Holy_SealOfSalvation]] },
    { "Wunschitem",  [[Interface\Icons\INV_Scroll_08]] },
    { "Wishlist",    [[Interface\Icons\INV_Scroll_08]] },
    { "Offspec",     [[Interface\Icons\Ability_DualWield]] },

    -- ------------------------------------------------------------ Raid -----
    { "Raidstunden", [[Interface\Icons\INV_Misc_PocketWatch_01]] },
    { "Firstkill",   [[Interface\Icons\Ability_Warrior_WarCry]] },
    { "Bosskill",    [[Interface\Icons\Ability_Warrior_Revenge]] },
    { "Boss-Pull",   [[Interface\Icons\Ability_Hunter_BeastTaming]] },
    { "Enrage",      [[Interface\Icons\Spell_Nature_TimeStop]] },
    { "ohne eigenen Tod",     [[Interface\Icons\Spell_Holy_DivineIntervention]] },
    { "ohne einen einzigen",  [[Interface\Icons\Spell_Holy_DivineIntervention]] },
    { "Gesundheit",  [[Interface\Icons\Spell_Holy_SealOfSacrifice]] },
    { "Speedrun",    [[Interface\Icons\Ability_Rogue_Sprint]] },

    -- ------------------------------------------------------------ Wipes ----
    { "Wipe",           [[Interface\Icons\INV_Misc_Bone_HumanSkull_01]] },
    { "Raidtod",        [[Interface\Icons\Spell_Shadow_DeathPact]] },
    { "Grabstein",      [[Interface\Icons\INV_Misc_Bone_Skull_02]] },
    { "Geistheiler",    [[Interface\Icons\Spell_Holy_Resurrection]] },
    { "Lava",           [[Interface\Icons\Spell_Fire_Immolation]] },
    { "Frontal",        [[Interface\Icons\Ability_Warrior_Cleave]] },
    { "Reparat",        [[Interface\Icons\Trade_Engineering]] },
    { "reparatur",      [[Interface\Icons\Trade_Engineering]] },
    { "Reparier",       [[Interface\Icons\Trade_Engineering]] },
    { "sterben",        [[Interface\Icons\Spell_Shadow_DeathPact]] },

    -- ------------------------------------------------------- Teilnahme -----
    { "Raidteilnahme",      [[Interface\Icons\INV_Misc_GroupLooking]] },
    { "Gildenmitgliedschaft",[[Interface\Icons\INV_Misc_PocketWatch_02]] },
    { "Ersatzspieler",      [[Interface\Icons\Spell_Holy_LayOnHands]] },

    -- ------------------------------------------------------ Lootmeister ----
    { "verteilt",       [[Interface\Icons\INV_Misc_Bag_10]] },
    { "verteilen",      [[Interface\Icons\INV_Misc_Bag_10]] },
    { "geleitete",      [[Interface\Icons\Ability_Warrior_BattleShout]] },
    { "geleiteter",     [[Interface\Icons\Ability_Warrior_BattleShout]] },
    { "Lootentscheidung", [[Interface\Icons\Ability_Rogue_Sprint]] },
    { "Einspruch",      [[Interface\Icons\INV_Shield_06]] },
    { "dokumentier",    [[Interface\Icons\INV_Misc_Book_09]] },
    { "historische",    [[Interface\Icons\INV_Misc_Book_09]] },
    { "synchronisieren",[[Interface\Icons\INV_Misc_Gear_01]] },
    { "Roster",         [[Interface\Icons\INV_Misc_Note_02]] },
    { "nachbesetzen",   [[Interface\Icons\INV_Misc_Note_02]] },
    { "Anmeldeschluss", [[Interface\Icons\INV_Misc_Note_02]] },

    -- ---------------------------------------------------------- Berufe -----
    { "Rezept",         [[Interface\Icons\INV_Scroll_03]] },
    { "Rezeptvorlage",  [[Interface\Icons\INV_Scroll_03]] },
    { "Hauptberuf",     [[Interface\Icons\Trade_BlackSmithing]] },
    { "Berufsspezialisierung", [[Interface\Icons\Trade_Alchemy]] },
    { "hergestellt",    [[Interface\Icons\INV_Hammer_20]] },
    { "herstellen",     [[Interface\Icons\INV_Hammer_20]] },
    { "Verbrauch",      [[Interface\Icons\INV_Potion_51]] },
    { "Bufffood",       [[Interface\Icons\INV_Misc_Food_15]] },
    { "Trank",          [[Interface\Icons\INV_Potion_51]] },
    { "Aufträge",       [[Interface\Icons\INV_Misc_Note_03]] },

    -- -------------------------------------------------------- Wirtschaft ---
    { "spenden",        [[Interface\Icons\INV_Misc_Coin_06]] },
    { "Spende",         [[Interface\Icons\INV_Misc_Coin_06]] },
    { "Auktion",        [[Interface\Icons\INV_Misc_Coin_09]] },
    { "Bankplätze",     [[Interface\Icons\INV_Box_01]] },
    { "Banktransaktion",[[Interface\Icons\INV_Box_01]] },
    { "Gildenbank",     [[Interface\Icons\INV_Box_01]] },
    { "Referenzpreis",  [[Interface\Icons\INV_Misc_Coin_09]] },
    { "Gold",           [[Interface\Icons\INV_Misc_Coin_01]] },

    -- ------------------------------------------------------------- PvP -----
    { "Flagge",         [[Interface\Icons\INV_Banner_02]] },
    { "Flaggen",        [[Interface\Icons\INV_Banner_02]] },
    { "Duell",          [[Interface\Icons\INV_Sword_27]] },
    { "PvP-Rang",       [[Interface\Icons\Ability_Warrior_Rampage]] },
    { "Ehrenrang",      [[Interface\Icons\Ability_Warrior_Rampage]] },
    { "Schlachtfeld",   [[Interface\Icons\INV_Banner_03]] },
    { "Heil-Spezialisierung", [[Interface\Icons\Spell_Holy_Heal]] },
    { "Heilers",        [[Interface\Icons\Spell_Holy_Heal]] },
    { "Gildenbanner",   [[Interface\Icons\INV_BannerPVP_03]] },
    { "ehrenhaft",      [[Interface\Icons\Ability_Warrior_Charge]] },

    -- ------------------------------------------------------ Gemeinschaft ---
    { "Hilfe",          [[Interface\Icons\Spell_Holy_PrayerOfHealing02]] },
    { "Hilfen",         [[Interface\Icons\Spell_Holy_PrayerOfHealing02]] },
    { "Gilde beitreten",[[Interface\Icons\INV_Misc_Key_06]] },
    { "Gründungsmitglied", [[Interface\Icons\INV_Misc_Rune_06]] },
    { "begrüßen",       [[Interface\Icons\INV_Letter_15]] },
    { "Mentor",         [[Interface\Icons\INV_Misc_Book_11]] },
    { "Dungeon",        [[Interface\Icons\INV_Misc_Key_11]] },
    { "Voice",          [[Interface\Icons\INV_Misc_Drum_01]] },
    { "Gildentreffen",  [[Interface\Icons\INV_Misc_Drink_15]] },
    { "Jubiläum",       [[Interface\Icons\INV_Misc_Food_15]] },
    { "02:00",          [[Interface\Icons\Spell_Shadow_Twilight]] },
    { "08:00",          [[Interface\Icons\Spell_Holy_SurgeOfLight]] },
    { "questen",        [[Interface\Icons\INV_Misc_Note_01]] },
    { "Dankesmarke",    [[Interface\Icons\INV_ValentinesCard01]] },

    -- --------------------------------------------------------- Sammlung ----
    { "Gebiete",        [[Interface\Icons\INV_Misc_Map_01]] },
    { "Regionen",       [[Interface\Icons\INV_Misc_Map_01]] },
    { "Flugpunkt",      [[Interface\Icons\Ability_Mount_Gryphon_01]] },
    { "Reittier",       [[Interface\Icons\Ability_Mount_RidingHorse]] },
    { "Begleiter",      [[Interface\Icons\Ability_Hunter_BeastTaming]] },
    { "Zugangsschlüssel",[[Interface\Icons\INV_Misc_Key_03]] },
    { "Zugangsquest",   [[Interface\Icons\INV_Misc_Key_03]] },
    { "Tasche",         [[Interface\Icons\INV_Misc_Bag_10]] },
    { "Taschenslot",    [[Interface\Icons\INV_Misc_Bag_10]] },
    { "Itembelege",     [[Interface\Icons\INV_Misc_Book_09]] },
    { "Souvenir",       [[Interface\Icons\INV_Misc_Gem_Variety_01]] },
    { "Kuriosität",     [[Interface\Icons\INV_Misc_Gem_Variety_01]] },

    -- --------------------------------------------------------- Geheimes ----
    { "Ruhestein",      [[Interface\Icons\INV_Misc_Rune_01]] },
    { "Magierportal",   [[Interface\Icons\Spell_Arcane_PortalStormwind]] },
    { "beschworen",     [[Interface\Icons\Spell_Shadow_Twilight]] },
    { "AFK",            [[Interface\Icons\Spell_Nature_Sleep]] },
    { "leeren Ausrüstungsslot", [[Interface\Icons\INV_Shirt_White_01]] },
    { "Fehlerbericht",  [[Interface\Icons\INV_Misc_Note_04]] },

    -- ------------------------------------------------------------ Stufen ---
    { "eigene Charaktere", [[Interface\Icons\INV_Misc_Rune_04]] },
    { "Klasse",            [[Interface\Icons\INV_Misc_Rune_06]] },
    { "Stufe",             [[Interface\Icons\INV_Misc_Rune_01]] },

    -- "in Folge" steht ABSICHTLICH ganz unten: Es kommt in vier verschiedenen
    -- Kategorien vor, und ueberall ist das andere Wort das aussagekraeftigere
    -- ("Duelle in Folge" ist ein Duell, "Wipes in Folge" ein Wipe).
    { "in Folge",          [[Interface\Icons\Ability_Warrior_InnerRage]] },
}

-- ================================================================= Auswahl ---

--- Geprueft, nicht geraten: SetTexture nimmt jeden Pfad an, auch einen
--- falschen. Das Ergebnis wird gemerkt — 272 Zeilen sollen nicht bei jedem
--- Bildlauf neu proben.
local exists = {}
local function usable(path)
    if path == nil then return false end
    local known = exists[path]
    if known == nil then
        known = Theme.TextureExists(path) and true or false
        exists[path] = known
    end
    return known
end

--- Das Symbol fuer einen Erfolg.
--- @return string pfad
--- @return string|nil klasse  gesetzt, wenn ein Klassensymbol besser passt
function Icons:For(entry)
    if not entry then return self.FALLBACK end

    -- Rueckfall: das Symbol der Kategorie, dann das Fragezeichen. Ein Pfad,
    -- den dieser Client nicht kennt, macht die Zeile schlechter — nie kaputt.
    local category = self.CATEGORY[entry.category]
    local fallback = usable(category) and category or self.FALLBACK

    local description = entry.description or ""

    -- Klassen zuerst und nur ueber die Beschreibung (siehe Dateikopf).
    for _, rule in ipairs(self.CLASS) do
        if string.find(description, rule[1], 1, true) then
            return fallback, rule[2]
        end
    end

    local text = description .. " " .. (entry.name or "")
    for _, rule in ipairs(self.RULES) do
        if string.find(text, rule[1], 1, true) and usable(rule[2]) then
            return rule[2]
        end
    end

    return fallback
end

--- Setzt das Symbol auf eine Textur. Klassensymbole kommen aus dem Atlas und
--- bringen ihre eigenen Koordinaten mit — deshalb wird SetTexCoord nur im
--- anderen Fall gesetzt, sonst waere der Ausschnitt doppelt beschnitten.
function Icons:Apply(texture, entry)
    local path, class = self:For(entry)

    if class and Theme.SetClassIcon(texture, class) then
        return true
    end

    texture:SetTexture(path)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return false
end

-- =================================================================== Probe ---

--- Welche Pfade kennt dieser Client NICHT?
---
--- Das ist die Messung, die von aussen nicht zu haben ist. Ohne sie bliebe
--- jede Zuordnung hier eine Vermutung, die man nur durch Hinsehen im Spiel
--- pruefen koennte — Zeile fuer Zeile, bei 272 Eintraegen.
function Icons:Probe()
    local seen, missing, checked = {}, {}, 0

    local function check(path, label)
        if not path or seen[path] then return end
        seen[path] = true
        checked = checked + 1
        if not Theme.TextureExists(path) then
            missing[#missing + 1] = string.format("%-22s %s", label, path)
        end
    end

    for category, path in pairs(self.CATEGORY) do check(path, category) end
    for _, rule in ipairs(self.RULES) do check(rule[2], rule[1]) end
    check(self.FALLBACK, "(Rueckfall)")

    table.sort(missing)
    return { checked = checked, missing = missing }
end
