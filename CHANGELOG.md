# Changelog

## 0.1.5

One question the guild asks constantly — *who can make this?* — and one the
addon had started asking back: *where did I put that page again?*

### Who can make this

Alt-click a pattern and somebody has it. Ask in guild chat and two people
answer who cannot, and the one who can is offline. A new **Professions**
page answers it directly: type an item name, paste a link, or drop an ID,
and you get everybody in the guild who can craft it, with their profession,
their skill, and how old that information is.

The same line appears in the item tooltip, so most of the time you never
open the page at all. Each row has an **Ask** button that whispers the
crafter the item link — once per minute per item and person.

**Recipes can only be read while a profession window is open.** That is a
property of the game, not of the addon: `C_TradeSkillUI` describes the
window that is open, not your professions. So open each of yours once,
`/ga craft sync` asks the guild for theirs, and `/ga craft` says exactly
that instead of pretending you have not learned anything.

Opening a profession window now reports one line — *"Alchemy read: 7
recipes, skill 31"* — and only when something actually changed. The window
announces itself more than once while it loads; reporting every time would
print the same line twice, then again on your next look.

### What it costs to store and send

A maxed profession has around three hundred recipes. As a Lua table in the
saved variables that is tens of thousands of entries for a guild; as plain
text over a line that carries 240 characters per message, it is dozens of
pieces.

Both are solved the same way: sort ascending, store the **differences**,
write them in base 36. Three hundred six-digit numbers become about five
hundred characters. Storage and transport use the identical format, so
there is one encoder, one decoder, and what arrives can be filed without
conversion.

**Enchanting recipes produce no item.** They are kept in a second list,
because anything that only collects item IDs loses that profession
completely.

**An empty scan never overwrites a filled one.** A window that has not
answered yet looks exactly like a profession with no recipes. Read that
wrong once and every character you have ever seen loses their recipes at
the next login.

**Only the sender decides whose recipes these are.** The message carries no
character ID at all — the sender name comes from the server and cannot be
forged, and a second, weaker source for the same fact would only raise the
question of which to believe.

### Five tabs instead of eleven

The row along the bottom had reached the width of the window, and worse, it
was lying. It put things side by side that do not belong side by side: two
of them were settings, two asked the same question, four were one raid
evening.

Sections now sit along the bottom, and the views inside them along the top
of the content — the arrangement the game uses in its own profession
window:

* **Overview**
* **Guild** — equipment, characters, achievements
* **Loot** — session, history, wishlist, rules
* **Professions**
* **Analytics**

Settings moved to a **gear** in the toolbar. They were never a working
view; they stood in the tab row because there was room.

Where a section holds a single view, the second row stays away and the
content moves up. A tab that offers no choice only costs space.

**Every slash shortcut still works.** `/ga history` selects the Loot
section and the history within it. That was the condition for doing this at
all — five tabs that take away half the navigation would be a poor trade.

### Fixes

* `craft` and `camp` were never registered as debug channels, and unknown
  channels are deliberately silent. Every diagnostic line both modules
  produced had been going nowhere since they were written — including with
  debug switched on.

## 0.1.4

Two things you can now ask for without typing: an item somebody is offering,
and who around you can help build a camp.

### Camp

Forever lets a guild build a camp together — somebody lights a campfire,
everybody else puts their profession's upgrade on it, and the camp gives a
buff for an hour. The hard part is not the building. It is finding out,
while you are standing in the Barrens, who near you happens to be carrying
an anvil.

A small bar answers that, on screen and separate from the main window: one
line per guild member **in your zone**, with the campfire they carry and
four profession slots — your two primaries, First Aid, Fishing. A bright
icon means they carry an upgrade they may actually place, a dim one means
they have the profession but nothing to put down. Hovering says which
pieces exactly, and whether their skill is high enough for each.

Drag it by the header, click the header to fold it away, right-click to
hide it. `/ga camp` brings it back.

**A question mark is not a no.** Somebody without the addon shows as
unknown, never as somebody carrying nothing. That distinction is the point
of the whole bar: an empty slot would send you walking past the one person
who has the anvil.

### Somebody placed a campfire

When a guild member lights one in your zone, a notice names them, says
which campfire and where, and offers a **map pin** plus **Share**, which
puts the waypoint into party or raid chat. It goes away by itself after
fifteen seconds.

Both buttons say in advance whether they can do anything. Map pins come
from a later expansion than the content this client runs; where they do
nothing, the button is greyed out with the reason on it, rather than
admitting it after you have pressed.

A notice older than a minute is dropped. Not as a safeguard — the sender's
name comes from the server and cannot be forged — but because a pin on a
campfire from ten minutes ago sends somebody to a place where nothing is
standing any more.

### What that tells the guild about you

While the bar is on, this client reports your zone, your professions and
which camp upgrades are in your bags. Your position goes out **only** in
the moment you place a campfire — the one moment it is public anyway,
because there is now a campfire standing there.

It is on by default, and that is a decision with a price. Off would be the
cleaner default, and the bar would then stay empty forever, because nobody
switches on something they have never seen. What makes up for it: the first
time this client sends, it says once in chat what goes out and how to stop
it. And off means off — it then neither sends nor receives.

None of it reaches the database. Other people's states live in memory and
are gone when you log out. No sync, no export, nothing in the guild file.
Where somebody stood two weeks ago is none of the addon's business.

### Asking for a tradable item

Every line in the **Tradable items** panel now has an **Ask** button. One
click whispers the owner: *Could I have [Nomad Tunic of the Boar]?*

With the item link, not the name. "Nomad Tunic" turns up three times an
evening with different stats; the link says which one is meant, and the
other side can click it. Afterwards that item stays quiet towards that
person for a minute — a button that sends another line every time it is
pressed turns impatience into pestering, and the recipient cannot even tell
it was the same person twice. A *different* item from the same owner goes
out immediately: somebody who wants two things should not have to wait.

Your own offers have no button at all. Whispering yourself is not an error
worth catching; it should not be clickable in the first place.

### The one thing the addon cannot check

The item numbers behind the camp belong to a server feature that exists
nowhere else. There is no documentation to verify them against, and no run
of `/ga probe` has ever seen them — they are copied observation, not
measurement.

So `/ga camp why` prints what this client actually makes of every one of
them: which names loaded, which use spells resolved, whether map pins work
at all, what arrived and was rejected and for which reason. A wrong number
shows up there as a line, instead of disguising itself as "doesn't work".

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
