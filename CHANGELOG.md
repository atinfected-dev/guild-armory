# Changelog

## 0.1.22

In progress.

**Map pins, your way.** Under Settings · On screen: the pin is the
class crest on a dark rim, or a plain dot in the class colour; and a
slider sets its size from 12 to 40 pixels. Both apply to the open map
at once, and pins that overlap at the chosen size are bundled.

### Dungeonhub

Its own tab in the row, beside the Questhub. A run is a dungeon, a day and time in
the next 24 hours, a leader, a note, and exactly five places: tank,
healer, three damage. Anyone in the guild posts one — the form sits on
the right: the dungeon typed freely or picked from a list the client
itself provides (its dungeon journal, with the classic instances behind
it), today or tomorrow, HH:MM, note, your own role. The runs stand as cards in two columns, today and
tomorrow: time, dungeon, leader, the five places as boxes with names in
class colour or "open" in the role's colour, and underneath "Join as"
with only the roles that still have a place, "You are in as …" with
Leave, or for the leader Withdraw and Invite the group, which sends the
game's invitations. Your last role is remembered.

Runs travel over the guild channel (DHUB, DJOIN, DMEMB, DHUBX, DREQ);
the leader's client is the source of the line-up and answers every
join with it, so late arrivals see the same five boxes. A run vanishes
24 hours after posting, an hour after its start, or when the leader
withdraws it. A new run raises a notification ("Dungeon runs" under
Notifications, on by default).

## 0.1.21

Campfires as pins on the world map, and in combat the window closes itself instead of getting stuck.

**In combat the window closes itself.** The carrier for the rank
buttons is gone — it left the arrows hanging in the landscape and the
window unopenable. The arrows are back inside the roster, which makes
the window protected in combat, so the game itself hides it when a
fight starts and it opens again afterwards; trying to open it during a
fight says why it stays closed.

**Campfires on the map.** When somebody in the guild lights a campfire,
the people in that zone already got a notification; now the world map
shows the fire too: the item's own icon on a dark disc where it stands,
the tooltip naming whose it is and when it was lit. Your own fire shows
as well. A pin burns five minutes, like the fire, then goes.

## 0.1.20

The window closes in combat: the secure rank buttons no longer hang on anything inside it.

**The window really closes in combat now.** The secure rank buttons sat
on their carrier but were still anchored to the roster detail, and a
frame a protected button hangs on is locked in combat along with the
window around it. The buttons hang on the carrier alone; the carrier
lays itself over the detail from screen coordinates, following drags,
resizes and scale.

## 0.1.19

Settings as a register with round switches, loot rules as four steps with a summary rail, notifications for ten seconds with a master switch, the guild chat history that stays readable, the window that closes in combat again, map clusters that count you, and the roster stutter gone.

### Loot rules: four steps and a rail

The rules page reads top to bottom in four numbered blocks — how loot
is distributed, the council, bidding, and what runs alongside — with
chips for choices and round switches for on/off. On the right a rail
says what the blocks add up to, one sentence per line (mode, soft
reserves, plus one, seats, who bids and for how long), the warnings
underneath, and at the foot who may change the rules and why. Every
block measures its own height.

### Settings: a register

Six sections in a column on the left — Language, Window, On screen,
Notifications, Loot, Data — and one page on the right, remembered
between openings. Every setting is a row: title, hint underneath, and a
round switch on the right instead of a checkbox — red is off, green is
on, the knob slides (the rounding is a texture of our own, Media/Circle.tga;
where it does not load the switch is square and still works).
Rows measure themselves at the current width, so a long hint never runs
into the next row (the layout test stands on the new function). The
council rotation moved to Loot where it belongs; debug output is a
switch under Data; the sharing row states that gear is shared and what
never leaves. At the bottom of the column, three things this client
measured: combat log, loot methods seen, other clients.

**The window closes in combat again.** The secure rank buttons lived
inside the main window, and a frame with protected children counts as
protected in combat — so the window could not be hidden. They hang on
a carrier beside the window now, following the roster detail in
visibility and layer; in combat the game hides the carrier itself and
brings it back afterwards. The invite dialog hides in combat the same
way.

**Map clusters count you too.** Four on one spot, one of them you, made
no cluster: your own position was never collected, so the cluster saw
three. It is counted now; the cluster shows the number and the list
with you in it, and below four your own pin is still not drawn — the
game draws your arrow.

**Guild chat history stays readable.** The game's keys for history
lines are reissued when its window focuses the stream; the panel had
read them once and kept the dead ones, so yesterday showed "Unknown"
again. It re-reads every minute now and renews a line whose key changed.

**Notifications: ten seconds, once, and a master switch.** The strip
beside the minimap stays ten seconds instead of six and never repeats;
"Show notifications" at the top of the Notifications settings turns
strip and tray off altogether, and the per-kind switches grey out.



## 0.1.18

A roster tab that does what the game's guild window does — with guild chat — and the achievements' category chips wrap.

### Roster: the game's guild window, here

A new tab under Guild, first in the row. Two directions were drawn; the
guild picked the directory. Across the top the guild with members, online
and guild master, the **message of the day** — click edits it when your
rank may — and buttons for the guild info and for the game's own window,
which stays the place for the bank and for rank permissions: no addon
replaces those.

The list: crest, name with the nickname you gave them, level, zone while
online, rank as a coloured chip, public note, and "last" — online in green,
otherwise how long ago the roster saw them. Offline rows step back. Filters
all, online, officers, without note; search over name, note, zone and
nickname.

To the right the selected member: class, level, online and zone, joined
when (from the roster history) and item level; the rank between ▲ and ▼
with the neighbouring ranks' names, enabled only when the game says your
rank may; **one note per member that everyone with Guild Armory sees**,
carried by the addon itself over the guild channel, the newest wins, and
the line below says who wrote it and when — the game's own public and
officer notes are not here, see below; the last three roster history
entries; whisper,
invite, equipment. No "remove from the guild" here: that stays the game's
window — a button that does it from a directory is pressed too easily.

**Guild chat** under the list: guild and officer channels, lines with time
and name in class colour, item links that answer to a click, an input line
that sends. What the panel hears itself is text and is kept — the last
five hundred lines survive a reload. On clients that keep the guild as a
"club" (C_Club) the panel also shows the game's own history for the time
before you logged in, the same lines the game's guild window shows.
Measured on 28.09.2026: that history is not text but keys of the game
("|Kw14208|k") which only the client can render, and only in the session
they were issued in — so the panel shows them, never stores them, and
never compares them to text; where history and heard lines overlap, the
same sender within ten seconds is the same message, and the heard text
wins. `/ga probe` has an entry ("clubChat") for the source; `/ga
clubchat` and `/ga chatdupes` show the raw material, `/ga chatclear`
empties the stored lines.

**Invite to the guild**, in the head: a small dialog with the character's
name and a secure button that runs /ginvite with it — the button is the
game's own, so Enter cannot press it, and the hint says so.

Everything that changes the guild asks the game's own Can* question first
and says in the tooltip why a button is off. What this client does not
hand out shows as "not measurable", never as "no" — `/ga probe` has an
entry ("guildManage") for the whole set: notes, ranks, MOTD, guild info,
the toggle function of the game's window.

**Promote and demote run as the game's own macros.** Measured on the
first try: GuildPromote from addon code is blocked by the game even with
the right rank. The two arrows are secure action buttons now — the click
is yours, and it runs /gpromote or /gdemote with the member's name, set on
the button before the click, never during it, on the edge (press or
release) the client's own setting expects. The rank sits between the
arrows as a chip in its colour; the line below names the neighbouring
ranks; the tooltip says where each arrow leads.

**Notes: the addon carries its own.** Writing the game's public and
officer notes is protected on this client — measured three ways on
28.09.2026 (the roster function is missing, C_GuildInfo.SetNote is thrown
away after the fact, and even the game's own "Set Player Note" dialog
blocks on Accept when an addon opened it). So the roster shows neither;
it has one note per member that Guild Armory distributes to every client
in the guild (GNOTE / GNOTEQ, last writer wins, deletions travel too).
Who may write it: whoever the game would let write the public note; what
the client cannot measure is not a no. `/ga probe` (guildManage) shows
the frame names, the key and its override.

**The J key**, off by default, in the settings: the key the game binds to
its guild window is overridden while the setting is on, so the game's
window never opens — the key toggles this roster. Any other way into the
game's window (the micro menu, a link) is caught when the frame appears
and led here as well; our own "Game's guild window" button is let through.
Not in combat — bindings and the game's frames are protected there; the
override is applied once the fight ends.

### Achievements: the category chips wrap

Fourteen category chips in one chain ran off the right edge of the window at 1000 wide (seen in a screenshot). They wrap now: as many per row as fit, the bar grows with the rows, and the cards below move down.

**Opening the roster no longer stutters.** Measured: 1924 history
messages were read from the club store on every open, each with a
twenty-field author table the client builds fresh, and compared against
every loaded line — a stutter and 70 MB. The reader now walks from the
newest end and stops at five hundred, reads fully once and afterwards
only when the game reports a club event.

**The message of the day is Guild Armory's own.** Setting the game's is
blocked from addon code on this client like the notes. So the roster
carries one of its own, distributed like the shared note (key "@motd",
up to 180 characters); the head shows it with who set it and when, and
click edits it when your rank may set the game's.

## 0.1.17

A Questhub for finding people for a quest, and notifications at the minimap.

### Questhub: who is looking for people for which quest

A new tab. Alt-click a quest in your log and it stands on the board for the
guild: title, level, kind (group, dungeon, elite), the zone heading from
your log, and up to three of your objectives with their state. It stays two
hours, or until you take it back (alt-click again, or the button) or turn
the quest in. Others can say "I am looking too"; that stands at the request
as a count and a list.

The board is a table, because the question there is "is it worth the walk"
and a row answers it without a click: kind, quest with the seeker's
objectives, zone, level (green when within five of yours), who seeks and
how many want in, since when. Filters: all, my zone, my level, group,
dungeon. Pick a row and the right side shows the seeker's objectives —
theirs, from their log, not yours — who else is seeking, and what you have
to do with it: whether the quest is in your own log and how far you are.
One button sends the game's group invitation to the seeker; the addon forms
no group by itself. "I am looking too", "Withdraw" for your own, "Quest in
chat" with the quest link where the client gives one.

"Quest from the log" swaps the right side for your own quest log with a
Post button per quest — the way without alt-click. Whether alt-click
attaches on this client, whether the log can be read at all and by which of
two API paths, whether objectives and links come back: `/ga probe` has an
entry ("questLog"). Nothing of it is assumed; both paths are tried and the
one that hands something back wins.

### Notifications at the minimap

Things happen while the window is closed: somebody offers a bind-on-equip
item, somebody looks for people for a quest, somebody lights a campfire in
your zone, somebody reports a guild first. Three pieces:

- A **counter** on the minimap button: how many are unread.
- A **strip** under the minimap: the newest one, six seconds, no buttons.
  A click on it opens the tray. In combat it waits until the fight is over.
- The **tray**, shift-click on the button: the last notifications, new ones
  highlighted, each with one button that does the obvious thing — ask for
  the item, open the Questhub, open the map, open the achievements.

Nothing stacks over the world; whoever ignores the counter is not disturbed
again. Each kind has a switch in the settings; guild firsts are off until
somebody wants them — a guild first is a claim until the guild confirms it.
The first twenty seconds after login report nothing: the sync brings the
whole guild's offers in at once, and each as a notification would be a
fireworks of old news.

## 0.1.16

The characters page as a family tree, the achievements as a trophy hall, and map pins that bundle up when a crowd stands on one spot.

### Map pins bundle up

Four or more guild members standing on top of each other were four crests
on top of each other, none readable. Now, when pins would overlap — centres
closer than a pin is wide — and there are more than three of them, one gold
pin with the count stands there instead; hovering it lists everybody, name
in class colour and level, sorted by name. Three or fewer stay separate,
as asked.

The bundling is deterministic: a pin joins the first group whose first pin
is within reach, so the same crowd bundles the same way on every redraw —
twice a second, a group whose centre wandered would flicker.

### Characters: the family tree

Two directions were drawn; the guild picked the tree. The page is a grid of
cards now, one per player: the role as a coloured edge on top (gold for
administrators, amber for the loot master, jade for the council), the main
with crest, name in class colour, class, level and item level, a role chip
and, where the roster history saw it, when they joined. Under the main the
alts hang on a line — and **the line itself says how the link came to be**:
solid jade for proven (same account, a fact), dashed grey for set (somebody
assigned it), dotted amber for claimed. The legend stands in the toolbar.
Filters: all, council and up, with alts, claimed only.

The right column keeps every tool the old page had: the unassigned
characters with "Assign" to the selected player and "New player", and under
that the selected player's panel — the four role buttons, nickname and note,
and their characters with "Set main" and "Unlink" (still refused for a
proven character: that link is a fact, not an entry).

### Achievements: the trophy hall

Every achievement is a **card with a rarity edge**, grey to gold in the
order of item quality so nobody learns a second colour system. Unlocked
cards carry their colour; open ones are dimmed; ones the client cannot
measure yet are dimmed further and say so. On each card: the icon, the name,
category and points, the description, the bar with "20 / 30" — and an
**evidence chip**: measured, observed, entered, or not measurable yet. That
chip is what tells this window apart from the game's.

Across the top the three figures as tiles with their footing — points and
how many of them were entered by hand, unlocked of the catalogue and how
many are measurable, guild firsts and how many are contested — with search
and the three views at the right. Under it the categories as chips with
their own count; one pressed shows only that category, open. "All" shows the
thirteen groups with a header each, folded by default as before, because
272 cards nobody reads and thirteen standings everybody does.

The Hall of Fame stands as a column beside your achievements with the
latest guild firsts, holder, date and state — and as its own view with all
of them as cards. The leaderboard stays a table, with a new column **HAND**:
the points somebody entered count in the total, and they also stand beside
it.

## 0.1.15

A congratulation in guild chat when somebody levels, and four things that
were showing the wrong thing: professions in somebody else's language, a
character list sorted by the wrong column, a scrollbar sitting on top of one,
and map pins that changed size with the zoom.

### The armory as a character window

Chosen from four drawn directions: the one that keeps what was already right
— eight slots left, eight right, three weapons below, the way the game's own
character window lays them out — and changes what stood around it.

**The character list.** The class as text is gone; it came capitalised
differently depending on the roster's language, and the crest says it without
a word. Each row now carries the class crest, the name with an online dot,
the level, and the item level as a number with a short bar beside it. The
bar is measured against the best in the list, not against 60 — in a guild at
level 20 a bar against 60 is equally short everywhere and says nothing. No
measured item level means a dash and no bar: unknown is not zero. The
selected row has a gold edge and stays marked without the mouse over it.

No online dot where the roster says nothing. A grey dot would read as
"offline", and that is a different claim from "don't know".

**Every slot is labelled**, in the client's own language — the game keeps
those names for every locale, so nothing is written down twice. With a
ring or a trinket empty, the silhouette alone does not say which slot it is.

**The character stands in the middle as a model** when they are there to be
shown: yourself, your target, anybody in the group. Anybody else keeps the
text panel from before. The alternative — dressing a stand-in model in their
items — would show the wrong race in the right helmet, and this window shows
nothing invented. The item-level history sits fixed below, above the
weapons, so it stays put whether a model or text is above it.

The model blinked at first. Setting the unit reloads the model, and the
panel refreshes not only on a click but every time the client finishes
loading any item — bundled to twice a second, but still — so the figure was
torn down and rebuilt on a half-second beat. It is set once per unit and
character now; the same unit again is not a refresh, it is a reload with no
reason.

**And now for everybody, not only for those in range.** A guild member in
another zone has no unit — but they have a race id, a sex and seventeen item
ids, all measured. The figure is assembled from those, the way the dressing
room does it: race and sex first, then every item put on. Nothing is guessed.

For that, the sex now travels with the character over the sync, one small
number, checked on arrival to be one of the two the game uses. A record from
before today has none, and shows the text panel until its owner's client
sends again — a guessed body would be wrong for every second character, and
wrong looks exactly like right.

The first probe run crashed on it — not on those calls, but earlier: the
race id came back as a number that "is" a number and throws the moment you
do arithmetic with it, the same obscured kind that killed the health bar.
The check that let strings through and waved every number past now has a
numeric twin that actually adds and compares before it says yes, and race
and sex go through it before anything else touches them. The probe report
also keeps the line number now instead of fifty characters of file path.

Whether Forever's client actually honours the two calls involved was the
open question, and `/ga probe` has an entry for it now ("dressUp").
Measured on the third run, 27 September: **TryOn and Undress exist,
SetCustomRace does not.** Items can be put on a figure, but there is no way
to give the figure a body that is not a unit in range — so on this client
the assembled figure never appears. The fall-back was already there: the
call says why it cannot, and the text panel stands as before. Everything
that carries the data — race id, sex, the sync — stays, because it costs
one number per character and the day a client answers differently, nothing
else has to change. The probe now also reports whether SetDisplayInfo
exists, the one other route to a body, so the next look is one command.

Two things overlapped on first sight and made the whole thing look
unfinished: the line under the name ran into the item level once a race name
was long enough, and the three weapon labels stuck together below their
slots. The line has a right end now, the class tile that hung off it is gone
(the class is a word in that line and a crest in the list already), and the
weapons stand further apart than the columns, because their names sit
underneath and are wider than a slot.

**The guild's logo sits in the portrait circle** of the window instead of
the player's face. That circle says whose window this is, and this one
belongs to the guild.

### The professions page, built the same way

The professions page had the old shape: two framed panels, a plain list on
each side, a hint line doing the work of a title. It is built like the
character window now.

**Left, the professions** as a table with a header — the profession's icon,
its name, how many can do it, how many recipes they know between them. The
selected one has the gold edge. The icon comes from the client by the
profession line's id, the same id the name already comes from; where the
client has no icon for a line, the cell stays empty rather than showing a
guessed one, and `/ga probe` has an entry ("professionIcon") that says how
many of your own lines resolve.

**Right, one surface with a head.** A tile with an icon, a title, a line
underneath, and a large number at the right — the same head the character
window has, and it always says what the table below it is: all professions
(the addon's mark, the number of crafters), one profession (its icon, its
crafters), one item (its icon in its quality colour, how many can make it),
one person (their class crest, name in class colour, skill as 120/300 and
when their list was read, the number of recipes). The search field and the
two buttons sit in one row under the head instead of stacking above the list.

**The crafter table** carries what the character list carries: class crest
and class colour where the character database knows the person, an online
dot where the roster says so and none where it does not, the skill as a
number with a short bar against the profession's maximum — no bar where the
maximum is unknown, because "how full" has no answer then — and when the
list was read. Recipes get their own table with icon, name in quality colour
and whether it is an item or an enchantment; two tables with two honest
headers instead of one whose header lied about half its contents.

**Two gaps in the module came to light while rebuilding.** The list of a
person's professions never handed the profession link back — it was stored
since the beginning, and `/ga craft link` found it in the store, but the
view read it through a function that left it out, so every foreign
profession said "no profession link yet". And the crafter list for an item
looked the profession's display name up with a variable that did not exist,
so it always fell back to the name in the scanner's language. Both fixed;
both have tests now.

### The loot table and the bid cards

Two directions were drawn for each window; the guild picked the second of
each. Both windows are rebuilt.

**The loot window is a table now, not two lists.** Across the top the items
as cards, the way they fall from a boss — quality edge on top, icon, name,
slot and armour type, the state ("bidding open", the recipient in green,
"transfer pending" in amber) and a badge with the number of bids. More
cards than fit, and two arrows page through them; the selected card stays
in view. Below, the candidates for the selected item **grouped by answer**:
Best in Slot first, then Main-Spec, then the rest, each group with its
colour bar and count, Pass folded shut by default — a click on a group head
folds it either way. Inside a group, whoever has the least stands on top:
lowest item level first, then votes, then name. For rolls the roll, for
points the bid. The item level has a short bar against the best in the
list; a class crest and class colour stand at every name.

**At the right, the decision.** Who leads — strictly the most votes, the
highest bid, or the highest roll in the highest tier — with crest, name,
answer and item level, the vote split as three bars, how many votes are in,
and one button: "Award to Rudi". On a tie the button is off and the head
says so: the addon does not quietly pick whoever came first. Below it the
facts about the item that were spread over the old view or not shown at
all: who has it soft-reserved, the rotation seats and cycle, the evidence,
how long ago it was detected, its source, the loot method at the time.

**The bid window is cards.** One card per item, three to a row: icon with
quality edge, name, slot and armour type — and a comparison block that was
missing before: **what you wear at that slot, its item level, the new item
level, and the difference**, as two bars. Measured, not guessed: the game
names the item's slot, the client names what you have there, and where a
slot can be one of two (rings, trinkets, one-hand weapons) the one with the
lower item level is the one you would replace — an empty slot counts as
zero, the biggest upgrade there is. Below the block the seven answers as a
grid, or the three roll ranges, or the points field with bid and withdraw
and the line that says what you have and what the minimum is. The foot of
each card says its state: "no answer yet", or the answer given in green.
The head counts "1 of 3 answered", and a thin amber bar under it shrinks
with the bidding time if the loot master set one. "Pass on the rest" at the
bottom passes on every card that still has an answer to give — not on
rolls or bids, which have no pass.

**An answered card leaves the window, and the rest move up.** Reported
the same evening: with nine or twelve items the window grew past the
screen. Now an answer or a roll takes the card out and whatever was behind
it moves into its place; at most six cards stand in the window at once,
and the head says how many are waiting ("2 of 12 answered · 6 waiting").
When the last card is answered the window closes. A DKP bid does not
remove the card — you can raise it or withdraw it, so it stays until you
pass.

**You can pass everywhere now.** With rolls and points there was no way to
say no; the loot master saw silence, and silence looks exactly like "has
not seen it yet". Roll and DKP cards carry a Pass button in their third
row that sends the same answer the council's Pass sends, and takes the
card out. "Pass on the rest" passes on every open card of any kind; a
standing DKP bid counts as answered and is left alone.

Changing an answer still goes through the loot window's "Bid window"
button, which opens the cards again — a card that can be flipped under
your hand leads to "but I clicked BiS" in the raid.

### The dashboard: the hall of banners

Three directions were drawn for the first page — a banner hall, a command
deck of numbers and curves, a guild newspaper — and the guild picked the
banner hall. It is built.

**Across the top, the guild.** The guild emblem as a tile — dark ground,
thin gold edge, a warm glow behind it — and the guild name large, under it members and online count, the
guild master in class colour, your rank. Chips say what is happening right
now and are simply absent otherwise: a loot session with its item count,
"you are master looter", hand-overs still pending in your bags. At the right
four figures with their footing under each: average item level and how
many of the roster were actually measured (unmeasured members are not
zeros), online of total, loot awarded this week and how many of those the
game itself confirmed, achievements unlocked of the catalogue.

**Left, your character.** Portrait, name in the fullest spelling the addon
knows, level and class and rank, the item level large with "10/17" under
it, and the seventeen slots as a strip of colour — quality where something
is worn, dark where nothing is. Under that five lines about you, each a
click to the page behind it: the open loot session, how many of your
wishes lie on its table, your oldest profession scan and how old it is
(amber past three days), your DKP, and the achievement you are closest to
— the measurable one with the highest fraction that is still reachable.

**In the middle, today in the guild.** A stream: who reached which level,
who joined or was promoted, who received what, who unlocked which
achievement, who lit a campfire where. Every line has the time, the class
crest, and its source under it — "confirmed by the game", "entered by
hand", "roster". This needed a small new module, Armory/Activity: the addon
measured all of these things already but kept none of them as events; a
level-up was only ever a higher number in the roster afterwards. The
module listens to the events the other modules fire and keeps a bounded
log — 150 entries, seven days, the same thing within ten minutes counted
once, a loot award updated in place as it goes from awarded to received.
It measures nothing itself.

**Right, who is where.** The zones of the online members from the roster,
each with its people as class-coloured dots, the unknown zone last and
grey; and, while it is fresh, the last campfire with who lit it. Below it
the tradable items, as before, with the item's icon and its owner on the
same line.

The old "guild online" list is gone from this page: the zones say more
with less, and the full list is one click away on the characters page.

**After the first screenshot.** Four things the picture showed. The
footing lines under the figures had no left end and grew into the
neighbouring tile — "0 confirmed by the game" stood in the online tile;
every line has a width now and clips, the tiles are wider, the loot
footing shorter. The line under your name ended before the item level
number but collided with the label under it, which is wider than the
number; both end before the label now. The slot strip had nineteen strips
for a line that promises seventeen — shirt and tabard do not count and are
out. And the emblem first sat in the minimap's tracking ring: thick,
round, over a square picture that brings its own round wreath; it is the
tile described above now.

The fourth was not the dashboard's at all. "Cooking read vor 1 Tagen" on
an English page: `Util.TimeAgo` had the German words built in, although
the keys for every language had existed since the locale switch. It reads
them at call time now — which fixes every "vor 3 Std." on every English
page, not only this one.

### Profession names in your own language

They were showing in German on an English client. The name that travels with
a profession is the *scanning* client's — so showing it means showing
somebody else's language setting, and in a guild with two of them the same
profession stands in the list twice. That was visible a day earlier without
being understood: "Kochkunst" and "Cooking" under each other, "Lebendige
Wurzel" and "Living Root".

The id of the skill line has no language. Asked for locally it gives the
name this client uses, which is the only version that comes out the same
everywhere.

If the client does not answer for an id, the transmitted name stays. A name
in the wrong language still beats a number — 185 means nothing to anybody.

### The character list: sorted by item level, and a scrollbar that behaves

The list answers one question — who is how far along — and sorted by name it
answered a different one. Highest item level first now; the search field
above is there for looking somebody up.

Anybody without a measured item level goes to the end rather than down among
the weak. Somebody nobody has inspected is not badly geared, they are
unknown, and putting them between the low numbers is a statement nobody
measured. Equal levels are broken by name, so the same guild twice gives the
same list and a change in it means something.

**The scrollbar overlapped the ILVL column.** The rows were already inset by
the width of the bar; the header was not, so the last heading sat over the
bar while the numbers underneath sat six pixels to the left. Two ends that
have to agree were written in two places — a test now insists they match.

The groove is dark instead of row-coloured, and both it and the handle only
appear when there is something to scroll. It used to run the full height in
the colour of a row, which read as the start of another column even in a list
of eight. A control that controls nothing is decoration. The handle sits a
pixel narrower than its groove, which turns a stripe into a handle in a rail.

### A congratulation in guild chat on a level-up

There is no event for somebody else levelling. What the server hands out is
the current level, so the rise is the difference to the last roster read —
and only where there *was* a last one: on the first read after login every
level looks new, and the addon would congratulate half the guild on levels
they have had for weeks.

**Five people with the addon would mean five congratulations.** Every client
reads the same roster and sees the same rise. So whoever sees it first claims
it over the addon channel and waits a moment; anyone who sees a foreign claim
for the same rise stays quiet. The wait is spread at random, because if
everybody waited the same time everybody would claim at once and nobody would
see anybody else — the same shape as the map positions.

**It is off until somebody turns it on.** The addon writes in the player's
name into a channel the whole guild reads, and that is not something to
switch on for them. Not every level either: round tens and the maximum, which
is where a guild actually says something. The maximum is asked for rather
than written down — a 60 in the code is wrong at the next expansion, and only
somebody standing on the old maximum would notice.

And not about yourself. Whoever levels gets a fanfare from the game already;
congratulating yourself in guild chat is a different thing from being
congratulated.

### The map pins are bigger, white-edged, and the same size everywhere

Twenty-two pixels instead of sixteen. The crest needs the room to be a
crest, and the limit upwards is the map itself: what a pin covers, nobody
can read. The way there was twelve, fourteen, sixteen, twenty, twenty-four —
and twenty-four was one step too far, which is the kind of thing only a
screen can say.

**The edge around it is white now, not black.** The edge has a job, which is
to set the pin apart from the map, and which colour does that depends on
what is underneath: black separates better on pale parchment, white on dark
water and forest. The crest itself is dark — deep blue, black, gold — so a
dark edge only makes the dark patch bigger, while a light one turns it into
a token with a rim. Decided on screen rather than reasoned out.

It comes from one place now, for the crest and for the square fallback
alike. Two pairs of numbers meant to mean the same thing drift apart.

**And it keeps its size on every screen and at every zoom.** The screen
alone would be no problem — WoW rescales the whole interface, and 24 units
look the same everywhere. But a pin does not hang off the interface, it
hangs off the map surface, and that has a scale of its own: it is stretched
as you zoom, and everything in it with it. The pin now carries the ratio
between the two, which leaves it at exactly the scale every other frame
has.

The offsets are divided by that ratio, because anchor offsets count in the
frame’s own scale — set a pin to 0.7 and keep asking for 300 and it lands
at 210, further off the further you zoom in. Without zooming, you would
never see it.

## 0.1.14

The map pins are round now, and the addon carries its own logo — in the
list where addons are switched on and off, and on the minimap button.

### The addon's own logo, in the list and on the minimap

Where the addons are switched on and off, this one showed the red question
mark — WoW's placeholder for a missing icon. It carries the project's logo
now, and so does the minimap button.

WoW reads only `.blp` and `.tga` inside an addon, never PNG, so
`npm run logo <picture.png>` makes both: the whole logo at 64 pixels for the
list, and a crop at 32 for the minimap button, where the lettering would be a
grey smear at twenty pixels. The list icon is pointed at the file only after
it has been written — a path to something missing brings back exactly the
question mark this removes — and a test holds that.

**The crop was picked by looking, after three tries of picking by feel.**
`npm run logo:preview` lays candidates side by side and writes a picture:
each at true button size, and enlarged without smoothing, because a preview
that flatters is the wrong kind of help.

The single most legible one was the lion, and that made it exactly the wrong
choice: it is one faction's crest, and the logo deliberately carries both. A
button that leaves out half the guild is not a good button, however well you
can see it. The crop now spans both shields with the blade between them. It
is wider than tall and gets squeezed — the shields sit side by side and the
button is square, so either enough height comes along and lettering is in the
picture, or it squeezes. Squeezed, the crests stay far enough apart to tell
apart, which is the job.

One bug came out of it that only a small picture could show: a crop was
averaged over a field twice as far from the left edge as it should have been,
so anything cropped came out a soft gradient instead of a picture. With no
offset the mistake cancels itself, which is why the whole logo looked right
in the addon list while the minimap crest was mush — and why the regression
test crops from somewhere that is not zero.

The converter is tested against a picture it builds itself, so no image has
to live in the repository for the test to run. The part worth testing is the
channel order: TGA stores blue first, PNG stores red first, and getting it
wrong does not look like a bug. It looks like a blue logo, and then you go
looking everywhere except at the order of three bytes.

### Round map pins, as class crests

Each pin is the round class emblem now, over a dark copy of itself two pixels
larger. The dark one keeps it off whatever the map is made of — a dark shaman
disappears into the sea otherwise — and having the same silhouette rather
than a circle behind it means no edge stands out anywhere.

It is also the better pin. A coloured dot states the class through a shade
you have to have learned; the crest states it outright.

**Twice guessed, twice wrong.** First Blizzard's portrait mask over a colour
fill, then the same mask used as a picture. Both times the call went through,
the protected call reported success, the fallback never fired — and both
times the pins were still square. This client accepts mask calls and does
nothing with them. It is the most expensive kind of answer: no error, no
"no", just a result that isn't true, and a `pcall` that doesn't throw is no
proof that anything happened.

`UI-Classes-Circles` renders round here — the dashboard portrait has been
going through it for a week and has been looked at. So the third attempt uses
art that is known to work rather than a third guess.

Without a class to draw, the coloured dot with its square outline stays. It
says less, but it says it reliably, and a map with no dots is broken.

## 0.1.13

One evening of raiding, spent finding out what the loot list had been
collecting and why. It had been filing several drops more than once — for
two unrelated reasons, hours apart — and taking in everybody else's
observations on top, which only showed because two clients speak different
languages.

The list has buttons now for tidying up after all that, and one for putting
into it what is already in your bags.

### The same drop, four times over

The guard against that was a note of which slots had been seen, and it was
wiped whenever the loot window closed. Empty a corpse item by item and the
window opens again; `LOOT_OPENED` and `LOOT_READY` both fire anyway. Every
reopen made everything new.

The database is asked now instead of a note. It survives the window closing,
a reload and the evening. The same drop means the same corpse, the same slot
in it, the same item — two identical pieces from one corpse lie in two slots
and stay two finds, because swallowing one of those would never be noticed,
while one entry too many is obvious.

With no known corpse the window shrinks to a minute: slot and item alone will
eventually match a different corpse, and past that point recording twice
beats discarding something real.

That was half of it. The other half came in over the sync and is further
down — same symptom, unrelated cause, found a few hours later.

### A remove button for detected items

Something that does not belong will always end up on that list — a piece the
raid does not hand out, a mistake, a test.

Nothing is deleted. The entry goes to cancelled and stays in the journal, so
anybody asking later why a piece was never awarded gets an answer instead of
a gap, and a misclick destroys nothing. Only items that have not been awarded
yet; taking an awarded one off the list would be editing history, and there
is a correction for that which leaves the old state standing.

Next to it sits **Remove all**, for the evening that ends with twenty-two
entries and half of them duplicates. It asks first: the button turns into
"Really, 22?" and only clears on the second press, forgetting the question
again after ten seconds. One misclick must not empty a list that holds the
whole evening — and a confirmation dialog would be too much ceremony for
something the journal keeps anyway.

It takes everything still open, detected and in-session alike. A tidy-up
button that clears half the list sends you back through it by hand
afterwards.

### From bags — putting collected loot on the list

The other direction: whoever collected as master looter has the evening in
their bags and not on the list — because the addon was off for a while,
because somebody else looted, or because the pieces came out of a trade.

Soulbound pieces stay out. Something already bound cannot reach anybody, and
offering it means letting somebody bid on what they will never get. Only on a
definite yes, though: the bound check has three answers and "don't know"
happens. Here leaving something out is the more expensive mistake — a piece
offered wrongly costs one click on Remove, a piece left out wrongly is simply
missing with no way to fetch it back.

It shows before it acts, listing in chat what would come in, and only adds on
the second press. Whether a piece is "for handing out" is not something this
client knows — it stands in no field, and a rule that tries to guess it
leaves out exactly the piece you meant. So the threshold applies and nothing
else is invented; the decision is made by eye. Nothing already on the list
comes in a second time.

### /ga bags — where is the loot right now

After an evening with a master looter the open loot sits in *his* bags, and
the addon's list only says what is still open, not how much of it he actually
still has.

The command matches the two against each other: what is open and in the bags,
with bag and slot, and separately what is open and not there. That second
list is the useful one — it is either already handed over or never arrived,
and that is a conversation rather than a button. Copyable, like the other
reports.

The first run said "0 in your bags, 22 not", which means two different
things: you have none of them, or the bags could not be read at all. It now
says how many items were read, so the zero can be told apart from the
silence.

### The other half of the duplicates came over the wire

A pattern kept appearing twice even after the fix above, and a green gem sat
in a list with a blue threshold. The saved data answered both at once: that
gem's first entry read *"taken over from the loot master"*, and the record
next to it was marked `source = "sync"`.

Neither had come from this client's own looting. Both arrived over the sync,
and that path had no threshold and no duplicate check at all.

A screenshot settled the rest of it. Two lines under each other read
"Kobrahns Griff" and "Cobrahn's Grasp"; two more, "Lebendige Wurzel" and
"Living Root". The same drop, in two languages, from two clients — which is
also why no comparison by name could ever have caught it.

**A bare observation is no longer taken over at all.** Detected means "there
was something here": no session, no decision, nobody handing it out. Three
people with the addon see the same drop three times, and the local rule that
only records under a master looter was being undercut by everybody else's
client, which had its own rules and its own language.

What still comes over the wire is everything with a decision in it — a
session, an award, a handover. That is what the sync is for. And when one
arrives for an item this client had observed itself, the observation gives
way: cancelled in favour of the decision, not deleted, so the journal says
what happened. Compared by item id, never by name.

**Only from your own group, though.** Raised straight away: two loot masters
in two different dungeons have to work as well. Without that condition they
did not. Award messages travel guild-wide, so they also reach whoever is
standing somewhere else entirely — and if the same item drops in both
instances within the hour, which for two groups in the same dungeon is the
rule rather than the exception, one group's award would have cleared the
other group's list. Their evening would simply have vanished.

The sender has to be in your group for that to happen. Otherwise it is two
finds, both stay, and the foreign award still lands in the history, because
it did happen. Session announcements were never affected — those go over the
raid channel, not the guild.

**The threshold applies on arrival too**, for anything not yet awarded.
Whoever records greens on their own client was filling everybody else's
lists. Awarded items still come through whatever their colour: who got what
is history, and a threshold that hides it falsifies it.

### /ga dedupe — clearing up after the bug above

The rule against recording a drop twice works from now on; what already
happened stays on the list. After one evening that was five identical pairs
of bracers among 22 entries, and clicking those away by hand is work caused
by a mistake of mine.

It shows first and clears on the second call, the same as `/ga reset`.
Halving a list quietly would be wrong even when half of it really is
rubbish. The oldest of each group stays, because it carries the first
measurement and any bids and votes hang off its id. Nothing awarded is
touched — that is history, however much it looks like a duplicate — and
nothing with an unknown source, because two finds of the same item from
nowhere in particular may well be two real finds, and this one deletes.

## 0.1.12

Two things the guild asked for after an evening in the dungeons: stop
recording loot nobody is handing out, and put less on the map.

### No loot recorded without a master looter either

Reported from a dungeon run: it takes everything. The saved data said what
had actually happened — fifteen recorded items, every one of them blue, so
the quality threshold was doing its job. What stood next to it was the point:
under `measured.lootMethods` there was exactly one value, `group`. There had
never been a master looter. The server had handed out every one of those
items while the addon filed them as "detected" on a list nothing gets awarded
from.

So the same rule as for sessions now applies one step earlier, at the
recording itself.

With one deliberate difference: here an unknown loot method counts as no. For
the session it does not, and that is not an inconsistency. Blocking a session
on ignorance takes a button away from somebody who may need it; declining to
record on ignorance costs a line that is added by hand in ten seconds, while
a list full of items that never came up for award has to be sorted out by
hand. (On this client the method is measurable anyway — raw value 3 maps to
`group`.)

Alone is unaffected: there is no master looter and no question of who gets
what, so whoever switches on recording outside a group keeps it.

It says so once per session rather than at every corpse. A silent stop gets
looked for in the addon.

### Only the first name on the map pin

The labels from 0.1.11 carried the whole name and the level. Names have two
parts on this realm and the second is mostly width — with several pins side
by side they run into each other, and underneath them is a map somebody wants
to read.

The pin carries the first name now. Pointing at it gives the whole name, the
level and the rank: the map answers "who is there", hovering answers "who
exactly, and how far along".

## 0.1.11

A guild rule about when a loot session is worth holding, names and levels on
the map, and the memory figure turned from something to watch into something
to measure. Plus the open-profession button, which did nothing and said
nothing about it.

### No session without a master looter

Said plainly by the guild: loot only needs to go into a session when there is
a master looter, otherwise it makes no sense. Correct — under group loot or
need-before-greed the server hands the item out while the window is still
collecting bids, and what is left at the end is a decision nobody can carry
out.

Opening a session is refused now when the client reports a loot method that
is not master loot, and says why.

Not when it reports nothing. Outside a group, and on some client lines,
`GetLootMethod` gives no answer at all; treating that as "no master looter"
would block the session exactly where the addon knows nothing, and the loot
master would face a button that refuses without a reason. Only an answer
naming a different method blocks.

Recording carries on either way — who got what is worth keeping whoever
handed it out. This is about the session, not the history.

### The open-profession button

It did nothing, and said nothing about it. The button can stop at four
different places and all four looked identical from outside, so every exit
now names its reason and the button prints it.

That first report already ruled out half the suspects: every stored link
checks out. The link survives both encodings intact — so the break is behind
the check, and there were two candidates for it.

Blizzard's profession window is loaded on demand. Before anyone opens a
profession it does not exist, and clicking a link then goes nowhere — no
error, no return value, exactly the silence that was reported. It is now
loaded first.

And there are two ways to open such a link, the specific
`C_TradeSkillUI.OpenTradeSkill` and the general `SetItemRef`; which of them
carries on this client is unmeasured. Both are tried in that order, and the
message says which one ran. If no window appears after that, the way was
taken and the server handed nothing back — a different problem from a link
that was never sent, and now distinguishable.

**For your own character there is no link at all now.** It did not work there
either — and there it cannot be the link's fault: a link is a request to the
server for somebody else's data, and your own sits in your own client. The
button was disabled for exactly that reason, a missing link that was never
needed. Your own profession opens directly, and the check for "is this me"
goes through the same name comparison as everywhere else, because the two
name sources on this realm disagree and a plain string compare makes you a
stranger to yourself.

**Gathering professions are out of the recipe list.** Herbalism and skinning
craft nothing; they sat there with zero recipes and a button that cannot open
what does not exist. They are recognised by being empty rather than by name
or id — an id list would need maintaining, and names depend on the language
of whoever scanned. Counted across everybody, not per person: somebody whose
window was only open briefly may report zero recipes, and that must not make
a profession disappear for the whole guild.

**A link is a reference to a session, not an address.** Asked after the fix:
somebody else's profession still would not open — did he have to update
first? Yes. That entry was 21 hours old, and the server only answers such a
link while that player is online *and* has had their profession window open
in their current session.

A record from yesterday looks exactly like one from a minute ago, so the age
is now printed with the message: what was recorded, when, and what the other
person has to do. No threshold — when a link dies depends on somebody else's
login, which this client cannot see, so a guessed number of hours would be an
assertion where the age is a measurement.

`/ga craft link` also prints the links in the raw. The first version rendered
them, so the report read "[Alchemy]" — which is what a link is for, and the
opposite of what a diagnostic is for.

### Names and levels on the map

A dot answers "is somebody there". The question people actually have in front
of a map is "who, and is it worth the walk" — and answering it meant pointing
at every dot in turn.

Each pin now carries the name in class colour with the level dimmed behind
it, in a small outlined face. Outlined because the background of a map is
unknown: over pale sand or dark water, plain text disappears exactly where
somebody is looking. Same reasoning as the black ring around the dot itself.

The level comes out of the guild roster, which the server sends anyway — not
over the wire. Nothing was added to the message.

**It switches off.** Twenty guild members in one zone means twenty names over
a map somebody may be trying to read, so whoever wants only dots gets only
dots, and the tooltip still says everything. The setting sits with the other
map options and takes effect immediately; a player who has never touched it
gets the labels.

### The memory figure, measured instead of watched

Reported during the session: 18.24 MB with three players online, then 19,
then 20 — and then it fell back to 5 on its own.

That fall is the answer. **Held memory does not fall.** The figure rises with
every allocation and drops when the collector runs, so a climbing number is
throughput, not a leak — which is what 0.1.9 already assumed without ever
checking it.

`/ga mem` now measures it rather than leaving it to be watched: the addon's
figure and the client's total Lua memory, a deliberate collection, then both
again. If most of it goes, it was garbage and the number that remains is what
is actually held. If it stays, the entry counts printed underneath say which
table is holding it.

The first real measurement settled it:

*Before: addon 19.39 MB, Lua total 282.30 MB — After: addon 3.00 MB, Lua
total 249.67 MB*

The addon gave up 84% of what it was holding. Three megabytes remain, for six
characters, 181 known items and 23 guild members — which is the code, the
frames and the tables themselves, not a leak.

It also caught the command's own verdict being wrong. It first read off the
total Lua figure, on the reasoning that this one is measured while the
per-addon number is only an attribution. True, and still the wrong number:
the total is the **whole client**, every addon plus Blizzard's own interface,
and it barely moves no matter what this addon does. It fell 12% and the
command announced "this is REALLY held" — the opposite of the truth, stated
with emphasis. The question is what *this* addon holds, so it now reads the
number that is about this addon, and the total stays above as evidence that a
collection happened at all.

Both `/ga mem` and `/ga status` now also open a window the text can be copied
out of. WoW's chat frame does not hand its text over, and a diagnostic report
nobody can send on is useless as a diagnostic. `/ga probe` has had that window
for a while; the two reports I ask for most often did not.

Two allocations of my own are gone with it. Both name helpers added in 0.1.10
were written as local functions *inside* the routines that use them, which
makes a fresh closure on every incoming addon message and every dashboard
refresh. That is the exact shape of loop that produced the 18 MB in 0.1.9 —
so I wrote two more of them in the release that fixed it.

## 0.1.10

Three reports from one evening, and by the end of it one cause behind all
of them: the way this realm spells names.

### The root: that second value is not a realm

The addon's own dashboard gave it away:

*Total — Level 20 Windshaper Skyborne Shaman — <Is Not Alone> Guild Master · Tumult*

That last field is the realm. The realm is called "Classic Beta PvE 2".
"Tumult" is the second half of the name "Total Tumult": `UnitName` splits the
name at the space and hands the second half back in the realm slot, where
every caller reasonably takes it for a realm.

That is where the half names came from, why the published record carried only
"Total" while the server wrote "Total Tumult", and why a realm nobody has ever
heard of stood under the portrait.

A player is always on their own realm, so anything else in that slot belongs
to the name. It is put back now, and the entries below are the symptoms — all
three fixed separately, because a wrong name must not depend on a single
guess being right.

*(If Forever ever connects realms, this needs measuring again: a genuine
foreign realm would be indistinguishable from a second name part. That is the
same ground on which cross-realm whispering was already given up.)*

### A name change locked the player out of his own guild

*Rejected: Total Tumult-ClassicBetaPvE2 wanted to publish the character
Total.*

That was the player himself. The rule behind the message is a good one — the
sender's name comes from the server and cannot be forged, so a character
record is only accepted from the character it describes. It is the one thing
standing between the guild database and anybody who feels like writing into
it.

It was comparing the wrong things. Character names on this realm may contain
a space ("Horst Hodenhagen"), and the two sources do not agree on how much of
the name they give: the sender comes from the **server** and carries both
parts, while `UnitName("player")` comes from the **client** and may stop after
the first. Two names of the same person, compared as text, are not equal — so
his equipment stopped reaching anyone in the guild.

The comparison now allows the shorter name to be the beginning of the longer
one, at a word boundary. Same realm, and "Total" matches "Total Tumult" while
"Tot" does not. The same faulty comparison sat a second time in the message
layer, where it was less visible because the guild check catches the case
afterwards.

This tolerance stays even though the cause above is now known and fixed. Two
sources disagreeing about a name is not a thing to be sure about once; it is
a thing to survive. `/ga probe` also gained an entry for it ("names") which
puts every name source side by side, including the spelling the server uses —
so the next disagreement is read off a report rather than pieced together
from a screenshot.

### Only half a name on screen

The same cause, one layer up: equipment, characters and the dashboard showed
"Total" where the guild knows a "Total Tumult". The record is built from what
the client hands out, and that is the source that shortens.

The guild roster is the better source — it spells names the way the server
does, the same spelling that appears in the sender field of an addon message.
Full names are now carried over from there into the character records
whenever the roster is read, and the dashboard prefers the fuller of the two
spellings it has.

If two guild members share a first name, nothing is carried over for that
name: the right short name beats a wrong long one, which is the same rule
the name search already follows. It is one pass through each list rather than
name against name — with 200 members and a roster update arriving several
times per login, the pairwise version is how you end up with the memory
figure that 0.1.9 had to fix.

### An inspected stranger stood among the guild

Pressing "inspect target" on somebody outside the guild creates a character
record, and the lists showed every record there was. He turned up under
equipment and among the characters waiting to be assigned to a player.

Now he does not — but on a narrow rule, because the wide one would have been
far worse. Almost nothing the addon knows has a **measured** guild: anything
arriving over the sync carries no guild name at all. Treating that empty value
as "not in the guild" would have emptied half the roster off the screen.

So what decides is whether the guild was ever actually looked up, which
happens during an inspect, where even an empty answer is an answer. Anything
never measured stays visible. The guild roster overrules an older measurement,
so somebody who joins later reappears, and typing a name into the search
finds him regardless — a search field that hides the record you searched for
is broken.

## 0.1.9

### 18 MB of addon memory for two players

Reported from a live client, and it cannot be the data: two positions are a
few dozen bytes. WoW's per-addon memory figure counts everything
**requested**, not what is held. A high number there almost always means too
much garbage per second — none of it stays, but the figure adds it all up.

Three places were producing it.

**The check "is the map open" ran before the throttle** — sixty times a
second, each with its own protected call, all evening, whether or not the map
was ever opened. It now counts the clock first and asks afterwards: from
sixty calls a second to two.

**The roster name lookup was rebuilt on every read.** Class and rank are taken
from the guild roster rather than sent over the wire, which is right — but the
two lookup tables were built fresh each time the pin list was assembled, and
that happens twice a second while the map is open. With two hundred guild
members that is eight hundred table entries a second for data that changes
monthly. It is kept for thirty seconds now.

**The position tick re-armed itself.** A timer whose callback started another
timer, every two seconds, all evening — a fresh timer and closure each round.
It is one frame with an update handler now, which allocates nothing.

### Longer intervals

Not the cause, but worth having:

- Minimum gap between position messages: 8 s → **15 s**
- Tick (check whether anything moved): 2 s → **3 s**
- Movement threshold: 0.004 → **0.006**
- Heartbeat while standing still: 180 s → **300 s**

A pin that lags by up to fifteen seconds still says which corner of the zone
somebody is in, which is what it was for. Half the messages is half the
messages.

## 0.1.8

Three reports, all about pictures that were not there.

### Guild pins on the map

**Nothing on the continent map.** Positions are stored against the *zone* map,
and pins were only drawn where the map ID matched exactly — Durotar is not
Kalimdor, so the continent stayed empty although every position was known.
They are translated now, by way of the world coordinate. Anything that lands
outside the target map's edges is dropped rather than pinned to the border; a
pin at the edge would be a claim about a place that is somewhere else.

**In the zone, only while the quest log was collapsed.** This was the
instructive one. `ScrollContainer` is the *viewport*; `ScrollContainer.Child`
is the map scaled inside it. Map coordinates refer to the child — computed
against the viewport they are right only for as long as the two happen to be
the same size, which is exactly as long as the quest log is shut.

The fallback to the viewport is gone. A wrong frame is worse than none,
because pins in the wrong place look like information.

Two neighbours of the same bug: the canvas was resolved once and kept, though
the map is rebuilt whenever the quest log opens; and the pins gave up if the
canvas was missing at login. `Blizzard_MapCanvas` loads on demand, so anybody
who opened the map later never got pins at all — and a warning that had
nothing to do with the real problem.

**A crash, twelve times in one session.** `GetMapPosFromWorldPos` returns
*two* values, the map ID first and the point second. One was assumed, and the
code went on to index a number. Rather than now assuming the other order, the
point is looked for: of the two returns it is the one that *is* a point. How
many values there are, and in which order, is in no documentation that applies
to this client.

### Other people's items had no tooltips

The guard bailed out when there was no item link — and a character from the
guild sync never has one, because only item ID, item level and enchant ID are
transmitted. Three lines further down sat the correct path, with a comment
saying it works without a link. The guard never let it run.

### The portrait ring

The class crest introduced in 0.1.7 is a square tile; the portrait ring is a
circle, so the corners stuck out. `UI-Classes-Circles` is the same information
in round, and the crops come from the game rather than from nine pairs of
numbers kept by hand.

## 0.1.7

### Other people's characters were shown empty

The armory said "8 of 17 slots equipped" and item level 6, and next to it
stood seventeen empty silhouettes with a blank portrait ring. The data was
there; only the pictures were missing.

The guild sync sends **only** an item ID, an item level and an enchant ID per
slot. No icon path, no name, no quality — and that is right: a channel that
carries 240 characters per message has no business carrying texture paths.
The receiving client has the ID, and with it everything it needs.

The paper doll was reading a stored icon field instead. On your own character
that field is filled, on everybody else's it never is. Icon and quality are
looked up from the item ID now, anything this client has not seen yet is
requested, and the view redraws once it arrives — batched, because opening a
character brings seventeen answers in a row.

**Strangers get their class crest** where an empty gold ring used to be. A
race portrait would have been a guess: Blizzard's templates need race *and*
gender, and gender is not transmitted, so half of them would show the wrong
face. The class is in the guild roster, so it is a fact rather than a guess.

Enchants and gems still travel as IDs only, so an enchanter's name or the
stones in an item are not shown. An item the server will not hand to this
client stays an empty slot — with its item level beside it, because that
does travel.

## 0.1.6

Guild members on the world map, your guildmates' recipe lists, and a
profession scan that had been quietly filing recipes under the wrong
profession.

### The guild map

Guild members appear as class-coloured pins on the world map, with their
name, rank and **how old that position is** in the tooltip. A pin always
looks equally fresh; whether it is ten seconds or four minutes old decides
whether you walk there.

Pins are drawn for the map you are *looking at*, not the one you are
standing on — page across to Kalimdor and you do not get pins from your own valley. Blizzard already draws your own arrow, so there is no second marker
on top of it.

**This is the furthest-reaching switch in the addon.** While it is on, your
map and your coordinates go to the guild for as long as you are online.
Anyone in the guild can find you at any time. Your zone was already in the
guild roster; the coordinates are what is new. It says so once in chat the
first time it sends, and off means this client neither sends nor receives —
a map on which you stay invisible while watching everybody else is exactly
the habit nobody should be asked to accept.

**"Continuously" does not mean "constantly".** Fifty people each sending
every ten seconds is five messages a second on the channel that also carries
the sync, the loot session and the camp bar. So: standing still sends
nothing at all, a message goes out when you have actually moved and at most
once every eight seconds, there is a heartbeat every three minutes, and one
answer when somebody opens their map. Positions older than five minutes
disappear on their own.

### Recipes, per person

Click somebody in the **Professions** page and you see their recipes — with
icons, quality colours and the game's own tooltips. Clicking a recipe turns
the question around and shows everybody who can make *that*, which is the
loop you think in anyway.

**Or let the game do it properly:** an *Open profession* button uses WoW's
own profession link, which opens Blizzard's window with categories and
reagents. It is greyed out with the reason when the person is offline —
the link asks the server for that character's data, and there is nobody to
ask. The addon's own list stays next to it, because that one works at three
in the morning.

### The scan was filing recipes under the wrong profession

Measured from a live client:

```
Alchemy read: 1 recipes    →  Alchemy read: 7 recipes
Herbalism read: 7 recipes  →  Herbalism read: 1 recipes
Cooking read: 1 recipes    →  Cooking read: 5 recipes
```

Every profession got the *previous* one's recipes on the first read.
Herbalism inherited Alchemy's seven, Cooking inherited Herbalism's one. The
window reports the new profession before the server has sent the new recipe
list — and the interface's own "is it ready" call says yes throughout.

That is where records came from in which a Linen Bandage sat under
Enchanting. There is no signal on this client for "the list belongs to this
profession now", so the scan now waits until nothing more arrives: every
further window event resets the clock, and it reads once when things go
quiet. That fixes the wrong data and the duplicated chat line at the same
time.

**Records written before this are still wrong.** Open each profession window
once and they are replaced.

### The camp bar takes a size

Drag the bottom-right corner. The name column takes whatever the icons and
the clock leave over, so widening it actually helps — before, the extra
space landed as a gap in the middle while long names stayed cut off.

The dragged height is an **upper limit**, not a fixed height: how many rows
there are is decided by the zone, not by you. Fewer people and the bar
shrinks to fit; more and it scrolls with the mouse wheel. Position and size
survive a reload.

### Measured, not assumed

* **This client hands out no readable health values.** Both `UnitHealth` and
  Blizzard's own player bar throw on arithmetic *and* on comparison. A health
  bar under the minimap was built, measured, and removed again — a switch
  that provably cannot do anything only makes the list longer. `/ga probe`
  keeps both lines, so if that ever changes it shows up there.
* Secret values are not only strings. The guard for numbers now tries
  arithmetic **and** comparison, the same lesson the string guard learned in
  September.

### Fixes

* **`/ga probe` was dead.** An earlier branch answered `sim` *and* `probe`,
  and in a chain of `elseif` the first match wins — so the API report three
  hundred lines below was unreachable. `/ga sim` is the test mode now,
  `/ga probe` is the report. A test fails if any command word is ever
  shadowed again.
* The probe reported "Profession window API: 0 entries" when the honest
  answer was "no profession window open". Empty is not none, and "not asked"
  is not "nothing there".
* `craft` and `camp` were never registered as debug channels, and unknown
  channels are deliberately silent — every diagnostic line those two modules
  wrote had been going nowhere.

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
