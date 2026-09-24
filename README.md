# Guild Armory: Forever Edition

**Everything your guild knows about itself, in one window — and an honest answer whenever it does not know something.**

A guild accumulates facts. Who is wearing what. Who joined in March. Who already got a weapon from Ragnaros. Who is carrying a spare blue they will never use. Who, right now, in the same zone as you, could put an anvil on that campfire.

Most of it lives in somebody's memory, and memory is where it goes wrong.

Guild Armory collects those facts and keeps track of **how well it knows each one**. An item level from an inspect two minutes ago and one from three weeks ago are not the same claim. An award the game reported and one a tired raid leader typed at 1 a.m. are not the same fact. Both pairs look identical the moment you show them as a bare number, so this addon never does.

Where it cannot measure something, it leaves the space empty and says so. **"Don't know" is never displayed as "no".** That rule runs through every corner of the addon, and it is the reason to trust the corners you cannot check yourself.

## What it does

### The armory

The part it is named after: a gear database for the whole guild, not just for you. Any character's equipment as a paper doll with the game's own tooltips, so nobody has to be talked into standing still for an `/inspect`.

Your own gear records itself on every change — two entries for an equip and an unequip, none for a `/reload` that changed nothing — which over weeks becomes an item level history you can read as a chart. Other characters come from inspect and are stored **with their source and age**, labelled plainly: *"Last update 3 days ago, this is NOT live data."*

Item level is computed per item and carries how many slots went into it. Fifteen slots and nineteen slots give different averages.

### The people behind the characters

Mains and alts are grouped into players, so a twink's gear and history are not a separate person. How solid each link is travels with it: **proven** (the same account saw both characters), **entered** (an officer set it), **claimed** (somebody said so). Roles follow the player.

The guild roster is kept as history — joins, departures, promotions — because the question that actually gets asked is *"how long has he been with us?"* The first scan deliberately records nothing: on day one everybody looks new, but nobody joined.

### What is in everybody's bags

Alt-click a rare bind-on-equip piece to offer it to the guild. It appears in a list with the full tooltip and random suffix intact, and an **Ask** button whispers the owner for it — with the item link, not the name, so there is no doubt which of tonight's three Nomad Tunics is meant.

A soulbound piece is never offered. Bind type belongs to the item, not to the copy in your bag; two independent checks are asked, and if either says bound, it is bound.

### Who can make it

Type an item name, paste a link or drop an ID into the **Professions** page and you get everybody in the guild who can craft it, with their skill and how old that information is. The same line appears in the item tooltip, and each row has an **Ask** button that whispers the crafter the item link.

Recipes can only be read while a profession window is open — that is a property of the game, so open each of yours once. An empty scan never overwrites a filled one: a window that has not answered yet looks exactly like a profession with no recipes.

### Building a camp

A small on-screen bar lists guild members **in your zone** with the campfire they carry and four profession slots — two primaries, First Aid, Fishing — showing who could actually place an upgrade. Somebody without the addon shows as unknown, never as somebody carrying nothing.

When a guild member lights a campfire nearby, a notice gives the spot, a map pin and a share button for party chat. Your own position goes out only in the moment you place one.

### Loot

Four ways to distribute — **council**, **soft reserve**, **roll**, **DKP** — through one session, because a roll is a bid with a number and so is a DKP bid. The rules are fixed when the session opens and travel with it, so nobody's local setting contradicts what is running.

Bidding can run on a clock. DKP balances are summed from the ledger on every read rather than stored, so they cannot contradict it, and bids are sealed. Rolling can be kept out of the chat entirely, with the trade-off stated where you switch it.

Council rotation with seats that expire, soft reserves separate from wishlists, plus one computed from history instead of counted.

### The loot history

Loot follows a state machine and nothing skips a step. Every award carries **how it was confirmed**:

| Confirmation | Strength | Where it comes from |
|---|---|---|
| Master looter | **strong** | The game reported the assignment |
| Trade | **strong** | The game reported the trade |
| Chat line | weak | Read from a loot message |
| By hand | an assertion | Somebody typed it in |

Statistics count hand-entered awards separately, because a number that mixes measurements with claims looks more precise than the data really is. Corrections never delete: the old record stays, marked and linked to its replacement.

### Between clients

Characters, wishlists and confirmed awards sync over addon messages, throttled and chunked. **A client can only ever publish the character it is logged in as** — the sender name comes from the server and cannot be forged, which is the one real security property an addon has. Messages are accepted only from your own guild. Conflicts are journalled, never silently overwritten.

## Requirements and limits

**Targets WoW: Forever** (Interface `16001`). It will not load on Retail or Classic Era without "load out of date addons", and parts depend on API behaviour measured specifically on Forever.

**AtlasLootClassic is optional** and only ever read at runtime. Nothing is copied; AtlasLoot is GPL v2 and its data stays its own.

**The camp catalog is copied observation, not measurement.** Those item numbers belong to a server feature that exists nowhere else, so there is nothing to verify them against. `/ga camp why` prints what this client really makes of each one.

**Known beta client issue.** Current Forever beta builds write SavedVariables correctly but never load them back — for every addon, not just this one. Guild Armory says so in one line rather than letting you fill a raid night into something that will be gone tomorrow.

## Getting started

```
/ga               open the window
/ga status        version, language and what this client can actually do
/ga craft <item>  who in the guild can make it
/ga camp          the camp bar for your zone
/ga trade         what you are offering, and what would qualify
/ga council       the loot session
/ga sim           play a raid evening through, without a raid
```

English and German, selected in the settings or from your client.

## The one thing it will not do

It does not decide for you. Reserves, wishlists, plus one and roll results are shown **next to** each candidate, never folded into a score. An addon that sorts the council's decision for it is judging without knowing who was on time, who swapped to off-spec, who stepped aside last week.

Its job is to make sure whoever decides has the facts — and knows how solid each one is.
