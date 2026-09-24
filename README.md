# Guild Armory: Forever Edition

**Everything your guild knows about itself, in one window.** Gear, roster
history, professions, tradable items, camps, the world map and loot — and an
honest answer wherever it does not know something.

English and German. Built for **WoW: Forever** (Interface 16001).

---

## What it does

| | |
|---|---|
| **Armory** | Every guild member's equipment as a paper doll. Your own gear records itself on every change; others come from inspect, always labelled with source and age. |
| **Players, not characters** | Mains and alts grouped together. Roles follow the player, so council rights are granted once, not four times. |
| **Roster history** | Joins, departures, promotions — because the question that gets asked is *"how long has he been with us?"* |
| **Professions** | Type an item and see who can craft it. Open anybody's recipe list, or their real profession window through the game's own link. |
| **Tradable items** | Alt-click a bind-on-equip drop to offer it to the guild. One button whispers the owner for it. |
| **Guild map** | Guild members as pins on the world map, with the age of each position. |
| **Camp bar** | Who in your zone can put an anvil on that campfire — and a notice with a map pin when somebody lights one. |
| **Loot sessions** | Council, soft reserve, roll or DKP. Four ways, one session, one history. |
| **Loot history** | Every award carries how it was confirmed. Corrections never delete. |
| **Achievements** | 60+ guild achievements for things this client can actually observe. |
| **Sync & export** | Characters, wishlists and awards travel between clients. A versioned export for your website. |

---

## What makes it different

**It tracks how well it knows each thing.** An item level from two minutes
ago and one from three weeks ago are not the same claim. An award the game
reported and one a raid leader typed at 1 a.m. are not the same fact. Both
pairs look identical as a bare number, so this addon never shows them that
way.

| Confirmation | Strength |
|---|---|
| Master looter | **strong** — the game reported the assignment |
| Trade | **strong** — the game reported the trade |
| Chat line | weak — read from a loot message |
| By hand | an assertion — somebody typed it in |

Statistics count hand-entered awards separately. A number that mixes
measurements with claims looks more precise than the data really is.

**"Don't know" is never shown as "no".** Somebody without the addon shows as
unknown, not as somebody carrying nothing. Where the client will not answer,
the space stays empty and says why.

**It does not decide for you.** Reserves, wishlists, plus one and rolls are
shown *next to* each candidate, never folded into a score. An addon that
ranks the council's decision is judging without knowing who was on time and
who stepped aside last week.

---

## Getting started

```
/ga               open the window
/ga probe         what this client can actually do
/ga craft <item>  who in the guild can make it
/ga map           positions known, and whether you are sharing
/ga camp          the camp bar for your zone
/ga trade         what you are offering
/ga sim           play a raid evening through, without a raid
```

Everything else is in the window. Nothing is hidden that changes results.

---

## Privacy, in one place

Two features send more than the rest, both switchable, both off with one
click:

* **Guild map** — while on, your map and coordinates go to the guild for as
  long as you are online. Your zone was already in the guild roster; the
  coordinates are what is new.
* **Camp bar** — your zone, professions and which camp items are in your
  bags. Your position only in the moment you place a campfire.

Off means this client neither sends nor receives. Both say once in chat what
goes out, the first time they send.

Addon messages are accepted only from your own guild, and a client can only
ever publish the character it is logged in as — the sender name comes from
the server and cannot be forged.

---

## Requirements and limits

* **WoW: Forever only.** It will not load on Retail or Classic Era without
  "load out of date addons".
* **AtlasLootClassic is optional**, read at runtime, never copied.
* **No readable health values on this client** — measured, both ways. Any
  feature that would need them is not there.
* **Known beta issue:** current Forever builds write SavedVariables but never
  load them back, for every addon. Guild Armory says so in one line rather
  than letting you fill a raid night into something that will be gone
  tomorrow.

The full story behind every design decision is in the changelog.
