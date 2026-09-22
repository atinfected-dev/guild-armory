# Changelog

## Tradable Items

Rare bind-on-equip drops are hard to pass around. You loot something you
cannot use, somebody in the guild can, and neither of you finds out. This
release makes that visible.

### Offering items

Your bags are scanned for items that still **bind on equip** and are not
soulbound yet — pieces you can genuinely hand over. Nothing is offered on
its own: you choose, per item.

Two thresholds, and they mean different things. **Uncommon and better can be
offered by hand.** Only **rare and better** ever runs along on its own — a
bag of green quest rewards would otherwise bury the one blue item in the
list, which is the whole point of the list.

* **Alt-click an item in your bags** to offer it, alt-click again to take it
  back. The tooltip says which of the two a click will do.
* `/ga trade add <item>` and `/ga trade remove <item>` do the same from the
  chat line, for anyone whose client does not pass the click through.
* `/ga trade` lists what you offer and what would qualify, and says whether
  alt-click is hooked up on this client at all.
* `/ga trade post`, or the **Post to guild** button in the dashboard, writes
  your offers to guild chat. Only on that command — the addon never posts by
  itself, and there is no setting that automates it.
* `/ga trade why <item>` prints, line by line, what the addon knows about a
  piece: quality, bind type, bag slot, what each bind check returned, and
  whether it is offerable. "Doesn't work" is not something anyone can fix;
  this turns it into a list of values, one of which says no.
* `Offer new finds automatically` in the settings records qualifying new
  finds once, as you pick them up. Off by default: something you are keeping
  for an alt should not be advertised without you saying so.

### Seeing what the guild has

The dashboard has a **Tradable items** panel: one line per item, with the
owner beside it. Hovering a line shows the full item tooltip, including
random suffixes — "Nomad Tunic of the Boar" arrives as exactly that, with
its stats, not as a bare "Nomad Tunic".

An owner shown in **warning colour** means the reporting client could not
check whether that piece is already soulbound. It may be gone. A name in
normal colour means the check ran and passed. The distinction is tracked per
item, not per bag, so one unclear piece does not cast doubt on the rest.

Two independent sources are asked about the bind state, because one of them
stays silent on some items. If either says bound, the piece is treated as
bound — the side where nobody walks across the world for nothing.

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

## Also in this release

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

## Fixes

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
* An item whose bind state could not be checked was treated as *not* bound
  and offered to the guild. A soulbound green would show up as tradable
  while the bind-on-pickup blue beside it correctly did not, which looked
  like blue items being broken. Unknown is no longer read as no.
* `Offer new finds automatically` acted as a live default rather than
  recording a choice, so alt-clicking an item it covered *removed* the
  offer while the same click on an item it did not cover added one. One
  gesture, two directions. The setting now records new finds once, as its
  name says, and a click always reverses what the tooltip shows.
