--[[----------------------------------------------------------------------------
    Communication/Announce — Vergaben im Gildenchat bekanntgeben.

    Kein UI. Sichtbare Chatnachrichten, keine Addon-Nachrichten.

    ===========================================================================
    WARUM DAS AUSGERECHNET DER WEG NACH DISCORD IST
    ===========================================================================

    Ein Addon hat KEINEN Netzwerkzugriff. Es kann Discord nicht aufrufen, keine
    OAuth-Anmeldung durchfuehren und keinen Webhook bedienen — der Client
    stellt dafuer nichts bereit.

    Wenn eine Gilde eine Bruecke zwischen Gildenchat und Discord eingerichtet
    hat, laeuft die auf der SERVERSEITE: Der Spielserver schickt den Chat
    weiter, nicht das Addon. Fuer dieses Modul heisst das etwas Schoenes: Es
    muss gar nichts von Discord wissen. Es schreibt in den Gildenchat, und die
    Bruecke erledigt den Rest.

    Ob es diese Bruecke in Forever gibt, ist UNGEPRUEFT — die Probe hat dazu
    einen eigenen Abschnitt. Ohne sie bleibt dieses Modul trotzdem nuetzlich:
    Dann liest die Gilde die Vergaben eben im Spiel.

    ===========================================================================
    DIE DREI REGELN GEGEN CHAT-SPAM
    ===========================================================================

    Ein Addon, das ungefragt in den Gildenchat schreibt, fliegt zu Recht raus.
    Deshalb:

    1. STANDARD AUS. Nichts wird geschrieben, bis jemand es einschaltet.

    2. NUR EIN CLIENT MELDET. Angekuendigt wird ausschliesslich vom Client des
       Lootmeisters, der die Vergabe angelegt hat. Sonst schreiben zehn Leute
       dieselbe Zeile — das ist der Fehler, den fast jedes Loot-Addon einmal
       gemacht hat.

    3. NUR BESTAETIGTES. Eine Ankuendigung geht erst raus, wenn die Uebergabe
       bestaetigt ist. Ein Zuschlag kann noch scheitern, und eine
       zurueckgenommene Meldung steht trotzdem fuer immer in Discord.

    Dazu eine Warteschlange mit Mindestabstand: Nach einem Boss fallen fuenf
    Gegenstaende gleichzeitig an, und der Client verwirft zu schnelle
    Chatnachrichten.
------------------------------------------------------------------------------]]

local _, GA = ...

local Announce = {}
GA.Modules.Announce = Announce

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local L = GA.L

--- Mindestabstand zwischen zwei Chatnachrichten.
local RATE = 3

--- Obergrenze je Sitzung. Ein Fehler in der Aufrufkette soll den Gildenchat
--- nicht fluten koennen — er soll auffallen und dann aufhoeren.
local SESSION_LIMIT = 60

local queue = {}
local sending = false
local sentThisSession = 0

-- ================================================================== Versand --

local function drain()
    if sending then return end

    local text = table.remove(queue, 1)
    if not text then return end

    if sentThisSession >= SESSION_LIMIT then
        Debug:Warn(L.ANNOUNCE_LIMIT, SESSION_LIMIT)
        queue = {}
        return
    end

    sending = true
    sentThisSession = sentThisSession + 1
    Compat.SendChatMessage(text, GA.Core.Config:Get("announceChannel") or "GUILD")

    Compat.After(RATE, function()
        sending = false
        drain()
    end)
end

--- Reiht eine Zeile ein.
function Announce:Queue(text)
    if not text or text == "" then return false end
    queue[#queue + 1] = text
    drain()
    return true
end

function Announce:QueueLength() return #queue end

-- ================================================================== Inhalt ---

--- Baut die Zeile zu einer Vergabe.
---
--- Der Itemlink bleibt drin: Im Spiel ist er anklickbar, und eine Bruecke nach
--- Discord macht daraus den Itemnamen. Faellt der Link weg, steht wenigstens
--- der Name da — nie eine blosse Zahl.
function Announce:FormatAward(award)
    local info = award.itemID and Compat.GetItemInfo(award.itemLink or award.itemID)
    local item = (info and info.link) or award.itemName or ("#" .. tostring(award.itemID))
    local who = Util.ShortName(award.recipientName or "?")

    local response = award.response and GA.Modules.Session:ResponseByKey(award.response)
    local reason = response and response.label or award.response

    -- Die Herkunft nur, wenn sie belegt ist. Einen Bossnamen zu erfinden waere
    -- hier besonders unangenehm: Der Satz steht dann dauerhaft in Discord.
    local source = award.encounterName or award.sourceName

    local line = string.format(L.ANNOUNCE_AWARD, item, who)
    if reason then line = line .. string.format(L.ANNOUNCE_REASON, reason) end
    if source then line = line .. string.format(L.ANNOUNCE_SOURCE, source) end
    return line
end

--- Kuendigt eine bestaetigte Vergabe an, wenn alle drei Regeln erfuellt sind.
--- @return boolean angekuendigt, string|nil grund
function Announce:AnnounceAward(awardId)
    if not GA.Core.Config:Get("announceLoot") then return false, "off" end

    local award = GA.Modules.Awards:Get(awardId)
    if not award then return false, "unknown" end
    if award.status ~= GA.Data.Schema.LootStatus.RECEIVED then return false, "unconfirmed" end
    if award.announced then return false, "already" end

    -- Nur der Client, der die Vergabe angelegt hat. Ein uebernommener
    -- Datensatz (source = "sync") wird nie angekuendigt.
    local identity = Compat.GetPlayerIdentity()
    if award.source == "sync" then return false, "notmine" end
    if award.lootMasterGuid and award.lootMasterGuid ~= identity.guid then
        return false, "notmine"
    end

    award.announced = Util.Now()
    self:Queue(self:FormatAward(award))
    Debug:Print("comm", "Angekuendigt: %s an %s", tostring(award.itemName),
        tostring(award.recipientName))
    return true
end

-- ================================================================== Start ------

function Announce:OnEnable()
    GA.Core.Callbacks:On("AWARD_CHANGED", function(awardId, _, newStatus)
        if newStatus ~= GA.Data.Schema.LootStatus.RECEIVED then return end
        Announce:AnnounceAward(awardId)
    end, "Announce")
end
