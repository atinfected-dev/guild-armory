# Changelog

## 0.1.3

Loot distribution, reworked. The page is called **Loot Session** now,
because it no longer covers only the council: one session handles whichever
way your guild hands loot out.

### Four ways to distribute

A new **Loot rules** page, next to Settings, picks one:

* **Council** — people bid, the council votes, the loot master awards.
* **Soft reserve** — a reservation decides. Anything nobody reserved is
  rolled for.
* **Roll** — everything is rolled for: 100 main-spec, 50 off-spec, 25
  transmog.
* **DKP** — people bid points, the highest bid wins, and only the winner
  pays.

In all four the loot master awards, out of the same candidate list. That is
not a coincidence — it is why one session can do all of them. A roll is a
bid with a number; a DKP bid is a bid with a number. Neither needed a second
procedure beside the first.

**The rules belong to the session, not to your settings.** They are fixed
when it opens and travel with the announcement, so a raid member whose own
page says something else still sees what the loot master actually chose.
Changing a setting mid-evening does not retroactively change what is
running.

The page also says, in one sentence, what applies tonight — and warns about
combinations that contradict each other, like rotating council seats while
nobody may vote.

### Rolling

A low roll in the larger range beats a high one in the smaller: 3 on 100
beats 49 on 50. That is the point of the ranges — whoever claims more rolls
higher up. Sorting by the raw number gives a procedure that decides wrongly
a few times an evening and looks entirely plausible doing it.

**Who rolls is a choice.** By default the loot master's client draws the
number: no chat lines at all, and a bidder cannot influence their own
number because their client does not draw it. The trade is real and worth
stating — the raid cannot check the number either. The alternative is
everyone rolling with `/roll`, where the server draws and the whole raid
reads it; with 20 people and 10 items that is 200 lines for everybody,
including people without the addon.

### DKP

**A balance is not a number, it is a sum.** Every posting stands in the
ledger on its own — when, how much, what for, by whom — and the balance is
computed from it on every read. It cannot contradict the ledger, because it
is nothing but the ledger, added up. Somebody asking "why do I only have 40
points" gets a list, not a claim.

* **Bids are sealed.** No message and no chat line ever carries an amount;
  only the loot master sees them. Whoever knows the top bid simply bids one
  more, and the auction turns into a race for the last second.
* **Open bids reserve points.** With 500, after bidding 100 on one item you
  can still bid 400 across the rest. Otherwise somebody bids 500 on five
  items and can pay for one.
* **Bids can be changed and withdrawn** while bidding is open. Nothing is
  charged until the award, and only the winner pays.
* **Being outbid whispers you** — without the new amount. Optional.
* A **Points and ledger** window from the Loot rules page: standings on the
  left, the selected player's ledger on the right, and posting at the
  bottom — to one player or to everyone in the raid. Nothing is posted
  without a reason.

### A clock for bidding

Bidding can stay open for 60, 120 or 180 seconds, or until you close it
yourself. The bid window counts down; when the time is up, no bid can be
placed, changed **or withdrawn** any more. That last one is what makes the
clock worth anything: somebody who can step out once they see the situation
has exactly the second move the clock is there to prevent.

The loot master's clock decides. The countdown everyone else sees only says
where they stand — two clients never have quite the same time, and the last
second is the one people argue about.

### Who takes part

A session is announced over the raid or party channel, never to the guild,
and only guild members are accepted — checked on both sides. Somebody from
outside sees no bid window and their bids would not arrive either.

That can now be widened to everyone in your raid, for guilds that pug.
**It applies to the session only**: characters, wishlists and confirmed
awards stay between guild members either way.

### Testing without a raid

`/ga sim` plays a raid evening through on one client: made-up raid members
with roles and points, items dropping, bids, votes. Awarding is left to
you — that is the part worth testing.

Two promises hold it together. **Nothing leaves the client** while it runs:
chat and addon messages are both blocked, at one place each. And **every
made-up record is marked**, so `/ga sim clear` removes exactly those, and
the guild sync refuses to pass them on even after you switch the test mode
off.

### Fixes

* Item tooltips now work from the item ID alone. They used to depend on a
  link, which only exists once this client has seen the item — so awards
  from the sync, other people's trade offers and anything in a test run
  showed no tooltip at all. Five places did the same thing; there is one
  now.
* The loot history threw an error on any row with an item icon: the icon
  was anchored to the label and the label to the icon. `SetPoint` adds an
  anchor rather than replacing one, so they also stacked up on every
  refresh.
* Bidding as the loot master failed with "no channel". The bid went over
  the group channel — to yourself. A session that lives on this client is
  now recorded directly.
* The settings window could not be configured by role at all; the loot
  rules now are. The bootstrap administrator is the guild leader rather
  than whoever started the addon first.
* Your own character was only registered once equipment was first captured,
  so looking it up by name failed — including in `/ga dkp add <your name>`.
  It is registered at login now, and name lookup falls back to a scan when
  the index is incomplete.
* Explanatory text with a fixed height ran into the control below it in
  three places. Heights are measured now, and a test looks for the pattern
  across the whole interface.

## 0.1.2

All of this came out of one report: *"I can't offer blue items any more."*
Blue turned out to be right and green wrong, and two further problems were
sitting behind it.

### Fixes

* **A soulbound item could be offered to the guild.** When the client could
  not determine whether a piece was already bound, the addon treated that as
  *not bound* and listed it. So a soulbound green showed up as tradable,
  while the bind-on-pickup blue beside it correctly did not — which from the
  outside looked like blue items being broken. Unknown is no longer read as
  no.

  A second source is now asked about the bind state, because the first one
  stays silent on some items. If either says bound, the piece is bound. That
  is the side on which nobody walks across the world for nothing.

  A piece whose bind state still cannot be verified stays **choosable by
  hand** — you can see what is bound in the game — but never goes out on its
  own. Nobody should have their name on an offer they did not click.

* **Alt-click worked in two different directions.** `Offer new finds
  automatically` acted as a live default rather than recording anything, so
  an item it covered counted as offered without ever having been chosen.
  Alt-clicking that item *removed* the offer, while the same click on an
  item the setting did not cover added one. The setting now records new
  finds once, as its name says, and a click always reverses exactly what the
  tooltip shows.

* Uncertainty about an item's bind state is tracked **per item** rather than
  per bag, so one unclear piece no longer casts doubt on everything else you
  are offering.

### New

* **A "Post to guild" button** in the dashboard's tradable items panel, so
  you no longer have to type `/ga trade post`. It sits in the panel heading
  rather than above the list — it is pressed rarely and the list is read
  constantly — and it is greyed out when you are offering nothing. It posts
  only on that press; the addon still never writes to guild chat by itself.

* **Greens can be offered by hand.** There are now two thresholds instead of
  one: uncommon and better may be *chosen*, but only rare and better ever
  runs along *on its own*. A bag of green quest rewards would otherwise bury
  the one blue item in the list, which is what the list is for.

* **`/ga trade why <item>`** prints what the addon knows about a piece:
  quality, bind type, whether it is in your bags, what each bind check
  returned separately, and whether it is offerable. "Doesn't work" is not
  something anyone can fix; this turns it into a list of values, one of
  which says no.

## 0.1.0 — Tradable Items

Rare bind-on-equip drops are hard to pass around. You loot something you
cannot use, somebody in the guild can, and neither of you finds out. This
release makes that visible.

### Offering items

Your bags are scanned for rare and better items that still **bind on equip**
— pieces you can actually hand over. Nothing is offered on its own: you
choose, per item.

* **Alt-click an item in your bags** to offer it, alt-click again to take it
  back. The tooltip says which of the two a click will do.
* `/ga trade add <item>` and `/ga trade remove <item>` do the same from the
  chat line, for anyone whose client does not support the click.
* `/ga trade` lists what you offer and what would qualify.
* `/ga trade post` writes your offers to guild chat. Only on that command —
  the addon never posts by itself.
* `Offer new finds automatically` in the settings offers everything that
  qualifies, without asking. Off by default: a rare item you are keeping for
  an alt should not be advertised without you saying so.

### Seeing what the guild has

The dashboard has a **Tradable items** panel: one line per item, with the
owner beside it. Hovering a line shows the full item tooltip, including
random suffixes — "Nomad Tunic of the Boar" arrives as exactly that, with
its stats, not as a bare "Nomad Tunic".

An owner shown in **warning colour** means the reporting client could not
check whether the piece is already soulbound. It may be gone. A name in
normal colour means the check ran and passed.

Offers older than three days disappear on their own. Anything listed has
been confirmed by its owner within that window.

### Export

Tradable items are part of the export, with their full item strings, so the
web armory can list them and tell two random-suffix variants apart.

### Guild only

Addon messages are now accepted only from members of your own guild.
Whispers from strangers are counted and dropped. The sender name of an addon
message comes from the server and cannot be forged, which makes this a real
boundary rather than a polite request.

### Also in this release

* **Combat logging in raids** — an optional setting that turns `/combatlog`
  on when you enter a raid instance and off again when you leave. It only
  ever turns off what it turned on. Off by default, and it stays off if you
  never enable it; the addon touches nothing in that case. Note that the
  WoW Forever beta does not persist settings across a reload yet, so this
  has to be switched on per session.
* **Raid history from Warcraft Logs** — raid nights parsed from uploaded
  logs feed attendance, boss kills and guild firsts. Data from logs is
  marked as observed, never as measured: whoever did not upload a night is
  not in it, and a ranking that hides that would reward uploading rather
  than raiding.
* **`/ga probe`** — reports what this client's API actually returns, which
  achievements that unlocks, and which stay unmeasurable. It answers with
  yes, empty or no; "empty" is not "no".
* **Achievements** — 16 further rules can now be tracked, among them
  professions, gold, bag space, boss kills and guild firsts.

### Fixes

* `/ga roll`, `/ga sr add`, `/ga sr del`, `/ga test` and the soft-reserve
  **list import** all threw an error on any item input. The import had been
  silently broken: every reserve list was rejected.
* Item tooltips could throw once per second while the mouse moved over a
  unit frame. Unit tokens are secret values on this client; the addon now
  reads the GUID instead and never calls the restricted function at all.
* Long addon messages sent as whispers went out with an unshortened target
  name and failed.
* The settings window overlapped itself: explanatory text ran into the
  checkbox below it. Heights are now measured instead of assumed, so a
  longer translation or a narrower window cannot push anything out of place.
* Item level and last-award lines in tooltips could compare secret values
  and throw.
* Eight texture paths used single backslashes, which Lua drops silently —
  the reason several backgrounds never drew.
* An unverified tradable report was stored in a way that read back as
  verified. Uncertainty now survives storage.
