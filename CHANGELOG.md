# Changelog

## 0.1.11

A guild rule about when a loot session is worth holding, names and levels
on the map, and the memory figure turned from something to watch into
something to measure. Plus the open-profession button, which did nothing and
said nothing about it.

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

Each pin now carries the first name in class colour, in a small outlined
face. Outlined because the background of a map is unknown: over pale sand or
dark water, plain text disappears exactly where somebody is looking. Same
reasoning as the black ring around the dot itself.

Only the first name, because names have two parts on this realm and the
second is mostly width — with several pins side by side the labels run into
each other, and underneath them is a map somebody wants to read. Pointing at
a pin gives the whole name, the level and the rank. The map answers "who is
there", hovering answers "who exactly, and how far along".

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
