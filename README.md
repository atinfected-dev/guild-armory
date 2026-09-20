# Guild Armory: Forever Edition

**A loot council addon for WoW: Forever that records not just who got what, but how well each award is actually proven.**

Most loot addons are very good at the easy half: opening a session, collecting bids, announcing a winner. The hard half comes three weeks later, when someone asks *"didn't he already get a weapon from Ragnaros?"* and the answer has to be better than a memory.

Every award this addon stores carries **how it was confirmed**:

| Confirmation | Strength | Where it comes from |
|---|---|---|
| Master looter | **strong** | The game reported the assignment |
| Trade | **strong** | The game reported the trade |
| Chat line | weak | Read from a loot message |
| By hand | an assertion | Somebody typed it in |

In a plain table, an award the game reported and one a tired raid leader typed at 1 a.m. look identical the moment you only display *"received"*. That difference is the entire reason a loot history is worth keeping, so it never gets thrown away. Statistics count hand-entered awards **separately**, because a number that mixes measurements with claims looks more precise than the data actually is.

The same discipline runs through everything else. Item levels travel with their **source and age**, because an inspect from three weeks ago is not the same as one from two minutes ago. Main and alt links record whether they are **proven** (the same account saw both characters) or merely **claimed**. Nothing is guessed, and what cannot be measured is left empty rather than invented.

## The armory

The part the addon is named after. It turns "who is wearing what" from a question you have to ask into something you can look up.

Pick any character from the list and its equipment appears as a paper doll: all 19 slots, item icons in quality colour, the game's own tooltip on hover. Your own gear is recorded automatically, one snapshot per change and none for a `/reload` that changed nothing, which over weeks becomes an item level history you can read as a chart. Other characters come from inspect, stored with their source and their age, and the armory says plainly when the data is old: *"Last update 3 days ago, this is NOT live data."*

Item level is computed per item and carries how many slots it was computed from, because fifteen slots and nineteen slots give different averages.

Characters are grouped into players, so a twink's gear and loot are not a separate person, and roles follow the player rather than each character. The guild roster is kept as history, which answers the question that actually gets asked in a council: *"how long has he been with us?"* The very first scan deliberately records nothing, because on day one everybody looks new but nobody *joined*.

## The loot history

- Detects loot and follows it through a state machine, `detected` to `bidding` to `awarded` to `transfer pending` to `received` to `equipped`, and lets nothing skip a step.
- An award only becomes *received* with a confirmation. There is no path around it.
- Corrections never delete anything. The old record stays, marked as corrected and linked to its replacement.

## The loot council

- Sessions with configurable responses, bids and council voting.
- **Council rotation.** Temporary seats for raid members, fairly cycled so nobody gets a second turn before everyone has had one. A temporary seat is never written into permanent roles; it expires on the clock, so a crash or a forgotten cleanup cannot quietly promote somebody forever.
- **Soft reserves** for one raid night, distinct from wishlists. The loot master imports a list, or players declare their own, and the council sees which is which.
- **Rolls.** `/roll` tracking that only counts rolls inside the open window, from group members, with the announced range, and only the first roll per person. On a tie it tells you there is a tie; it does not pick for you.
- **Plus one.** How often somebody has already received something, computed from the loot history on every read instead of kept as a counter that can drift away from what actually happened.
- **Wishlists** with item search by link, Wowhead URL, ID or name.
- **Handover reminders.** What is still sitting in your bags that belongs to somebody else, with bag and slot.

## Between clients in the guild

Characters, wishlists and confirmed awards sync over addon messages, throttled and chunked, with a running digest so clients that fell behind catch up without anybody flooding the guild.

**A client can only ever publish the character it is logged in as.** The sender name comes from the server and cannot be forged. That is the one real security property an addon has, and it is used everywhere it applies. Conflicting records are journalled, never silently overwritten, because a history that changes quietly is not a history.

A version overview shows who is running what. "No reply" is reported as exactly that, not as "doesn't have the addon", because offline, out of range and a lost message look identical from here.

## Installing

Copy the `GuildArmory` folder into your AddOns directory and restart the client, then type `/ga`.

```
<WoW>/_classic_beta_/Interface/AddOns/GuildArmory
```

This addon targets **WoW: Forever** (Interface `16001`). On other flavours it will need "load out of date addons", and parts of it depend on API behaviour measured specifically on Forever.

```
/ga               open the window
/ga status        version, language and what this client can actually do
/ga council       loot council
/ga sr open       open a soft reserve round for tonight
/ga roll <item>   start a roll
/ga version       who is running the addon, and which version
```

## Known beta client issue

On current Forever beta builds the client writes SavedVariables correctly but never loads them back. Every login starts with an empty database, for *every* addon and not just this one. Guild Armory says so in one line when it happens, instead of letting you fill a raid night's history into something that will be gone tomorrow. The export still works, so the data survives outside the game until Blizzard fixes it.

Ruled out along the way: file contents (a 120 byte file was not loaded either), a broken file (it parses cleanly in a real Lua 5.1 parser), permissions, VirtualStore redirection, `/reload` versus a full client restart, a name collision, and the addon itself (a second addon behaves identically).

## Third-party

This addon bundles no third-party code: no libraries, no embedded frameworks, no copied data.

**AtlasLootClassic** (GPL v2) is an optional companion. If it is installed, Guild Armory reads the tables AtlasLoot has already loaded into the game's own Lua state, to widen item search and show where an item drops. Nothing is copied or redistributed, and the addon works without it.

Ideas were taken from RCLootCouncil, Gargul and GuildParagon without taking their code. All of them are separately licensed and none is included here.

## Licence

MIT, see [GuildArmory/LICENSE](GuildArmory/LICENSE).
