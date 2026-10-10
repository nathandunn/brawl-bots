# Saloon Bots

A 5-v-5 six-shooter fight in a two-storey saloon, played out entirely by AI. Part of the
[Precog sim suite](https://apps.precogsoftwareservices.com).

**Live:** https://saloon-bots.apps.precogsoftwareservices.com

Every man carries the same Colt (six in the cylinder, thirty spare, one cartridge at a time to
reload) and the same two fists. Nothing about the men differs but **how they think** — the team's
**doctrine** and each man's **personality** — so whatever wins, strategy won it.

## The room

Mirror-symmetric about the middle so neither end starts with the better ground: a balcony along
the back wall at 3.25 m with a solid balustrade, a stair up each side wall, a long bar with a
shelf of bottles (they break), a piano, a stove column, posts, barrels, crates up and down, and a
dozen round tables. A standing table hides nothing — a crouching man's head is above it — so men
**kick tables over** into 1.2 m boards facing the threat. The balcony rail is a balustrade:
you can see between the balusters and a slug gets through about half the time.

## Rules

- Last team standing wins.
- Three-second standoff at the start: the piano stops, nobody draws until the bottle breaks.
- At **2:00** the side with more men standing wins **on decision**. Level? **Sudden death** — the
  next man down loses it for his side. Nobody falls in 45 s: remaining health; dead level: draw.
- Bullets are real lines: they stop in wood and walls, hit whoever is in the way (friends too —
  the men check their lanes), and rattle anyone they pass close to (suppression).
- Head 70, torso 28, arm or leg 15 of 100 HP. An arm wound spoils aim, a leg wound slows.
- A man being punched can't aim; he punches back or backs off. A punch can floor you.

## How the AI decides

**Team brain** (`scripts/team_brain.gd`), one per side:

1. *Blackboard* — every enemy seen or heard, where and when. Every shot in the room is heard and
   **counted**; a team with a disciplined man keeps the count, a team of hotheads loses it. A man
   counted empty, or heard thumbing in cartridges, gets rushed by whoever is best placed — if he
   can be reached before the cylinder is full again.
2. *Tactical map* — for every cover spot and grid point, swept about once a second against the
   known enemies: can they see a man standing here, can they see him crouched, and can a man here
   hit **them** even when they crouch (the flank / high-ground value). Stealthy routes weight
   every metre in an enemy's eye as four.
3. *Commander* — runs the doctrine as a phase machine and hands each man an order (role, zone,
   push, fire policy). Clock sense: under 25 s left, a side that's ahead digs in and a side that's
   level or behind goes all in.

| Doctrine | What it does |
|---|---|
| Adaptive | Reads the fight: presses a man advantage, digs in when behind, rushes counted reloads, flanks a stalemate |
| Dig In | Everyone in cover on our side, shoot only at men who show themselves; one man upstairs |
| Rush | Stack up, then all five charge together, fanning at close range |
| Pincer | Two take the balcony and work across it; three pin from the floor; spring when the high men are over |
| High Ground | Three hold the balcony and shoot down over the cover; two guard the foot of our stair |
| Leapfrog | Two groups: one bounds cover-to-cover while the other suppresses, then swap |
| Bait | One man with nerve draws them out and runs back into the other four's ambush |

**Each man** (`scripts/gunman.gd`) scores every tactical point with weights from his ten traits
(aggression, caution, patience, discipline, cunning, nerve, teamwork, height, brawl, trigger) and
blends in his order by his discipline. Then: peek from cover, aim, fire, duck (or stand in it);
duck a gun he sees pointed at him; fan the hammer up close; reload when low and nobody's in sight;
fall back when hurt and rattled; flip a table when the nearest cover is no cover at all.

Presets: Balanced, Gunslinger, Sharpshooter, Brawler, Snake, Lawman, Coward, Desperado, Random,
and Custom (the sliders). A whole team or any single man can be set.

## Balance (headless, Balanced personalities both sides, both ends of the room)

Doctrine league, 10 matches per pairing (±15 points is 1σ per cell):

| | Adaptive | Dig In | Rush | Pincer | High Ground | Leapfrog | Bait |
|---|---|---|---|---|---|---|---|
| **Adaptive** | – | 8-2 | 9-1 | 6-4 | 5-5 | 6-4 | 6-4 |
| **Dig In** | 2-8 | – | 8-2 | 1-9 | 5-5 | 1-9 | 4-6 |
| **Rush** | 1-9 | 2-8 | – | 5-5 | 1-9 | 4-6 | 5-5 |
| **Pincer** | 4-6 | 9-1 | 5-5 | – | 5-5 | 6-4 | 6-4 |
| **High Ground** | 5-5 | 5-5 | 9-1 | 5-5 | – | 8-2 | 8-2 |
| **Leapfrog** | 4-6 | 9-1 | 6-4 | 4-6 | 2-8 | – | 10-0 |
| **Bait** | 4-6 | 6-4 | 5-5 | 4-6 | 2-8 | 0-10 | – |

The counters are the point: Dig In beats Rush, Leapfrog and Pincer beat Dig In, High Ground
beats Leapfrog, Pincer holds High Ground. Adaptive, which reads the fight, tops the table.
Rush is the weakest fixed plan (~30%) and Bait next (~35%) — open calibration debt.

Personality presets (Adaptive both sides) against Balanced, 10 matches each: Gunslinger 7-3,
Brawler 7-3, Desperado 6-4, Lawman 4-6, Snake 3-7, Sharpshooter 2-8, Coward 2-8. Aggression
still pays more than patience — also open debt.

## Running it

Open the page. **Teams / tactics** sets doctrine and personality per side and per man; **Show
intents** prints what each man is doing over his head; the ticker shows each team's calls;
**Batch x10 / x50** runs fast and reports wins, endings, accuracy, hits on men in cover, hits from
the balcony, fist kills, time in each plan and a by-personality table.

The query string stands in for a command line: `?reddoc=Pincer&bluedoc=Rush&red=Snake&blue=Lawman&seed=3&intents=1`.

Headless (Godot 4.4+):

```sh
godot --headless --path . -- --sim=30 --reddoc=Pincer --bluedoc=Dig\ In --seed=1
godot --headless --path . -- --league=5            # every doctrine vs every other, both ends
godot --headless --path . -- --presets=5           # every preset vs Balanced, both ends
godot --headless --path . -- --league=5 --part=0/4 # split a league over processes
```

## Build and deploy

`bash build.sh` exports to `dist/` (Godot 4.7.2 + web templates on the hub), verifies the pack
boots headless, and gzips the big three. `Dockerfile` + `nginx.conf` serve `dist/`;
`headers.caddy` adds COOP/COEP. Deployed with `/opt/scripts/deploy.sh saloon-bots nathandunn/saloon-bots`.

Everything — meshes, sounds — is built in code; there are no asset files.
