# Saloon Bots

A 5-v-5 six-shooter fight in a two-storey saloon, played out entirely by AI: **the Law** (tin
stars, pale hats) against **the Outlaws** (bandana masks, black hats). Part of the
[Precog sim suite](https://apps.precogsoftwareservices.com).

**Live:** https://saloon-bots.apps.precogsoftwareservices.com

Every man carries the same Colt (six in the cylinder, twelve spare - **18 rounds in all**, one
cartridge at a time to reload) and the same two fists. After the eighteenth, it's fists. Nothing about the men differs but **how they think** — the team's
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
- **Vital hits kill**: head or heart. A gut shot does 38 of 100 and bleeds. Arms and legs cost
  little blood, but a man shot in the **gun arm** shifts the Colt to his left hand (spread ×2,
  slow to settle, no fanning); **either arm** slows his reload and his punches; **both arms** and
  he can barely lift the gun or punch at all. **One leg**: a limp, no sprinting. **Both legs**: he
  drags himself along the floor.
- **Aim time is accuracy**: spread is ×(1 + 2.2·e^(−t/0.42)) — a snap shot is three times as wide
  as a settled one. Patience decides how long a man dares to aim; a gun pointed back at him, a man
  close by or his own wounds cut it short. A man set and watching his lane, or coming back up where
  he ducked, starts half-aimed.
- **Every wound bleeds.** One wound is about a minute from killing a man (arm or leg 1.4 hp/s, gut
  1.1), two about half that; the label counts it down ("bleeding ~40s"). A man who knows he's
  bleeding out and has the nerve makes a last stand.
- **Blood on the boards**: drips, sprays and pools round the bodies fill 0.5 m cells on the floor
  and balcony; a man who runs through a slick cell may **slip** and go down.
- **Arm's length**: right in front of a man, he decides — shoot from the hip, or knock the gun
  aside and hit him (brawlers, and men with a gun on them, go for the fists). A punch into a man
  with his gun up can **jam** it. Any shot can misfire (1.5%), a scuffling one far more (≈24%); a
  jammed Colt takes ~1.6 s and two hands to clear, so a careful man hides to do it.
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

**Modes.** Every man is always in one, shown over his head: **hold** (in cover, peeking to
shoot), **advance** (cover to cover), **duck** (down behind cover for a moment — after a shot, or
when he sees a gun on him), **hide** (out of every enemy's sight altogether — to reload, when
pinned, when dry; pops up already aimed if an enemy walks into him), **cower** (frozen, arms over
his hat, no gun up — a shock to a man with no nerve: a wound, a near miss, a mate dropping beside
him), **flank** (one man at a time slips round out of sight to the angle that beats their cover,
holding fire till he's there), **rush** (sprint at a man, firing or fanning — to punish a reload,
on the charge, or with fists once dry), **fall back**, **brawl**, **hunt**.

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

## Sound

Shots, ricochets (a falling "pteeoww"), near-miss whizzes, wood thunks, breaking bottles, the click
of a hammer on a spent chamber, cartridges thumbed home — all synthesised in `scripts/sfx.gd`. The
voices — "He got me!", "I'm hit!", "My leg!", "My arm!", a dying "He... got me.", "I'm out!" and the
"Draw!" — are espeak-ng lines in three voices, baked into `sfx/voice/` by `tools/make_voices.sh`.

## Running it

Open the page. **Teams / tactics** sets doctrine and personality per side and per man; **Show
intents** prints what each man is doing over his head; the ticker shows each team's calls;
**Batch x10 / x50** runs fast and reports wins, endings, accuracy, hits on men in cover, hits from
the balcony, fist kills, time in each plan and a by-personality table.

The query string stands in for a command line: `?reddoc=Pincer&bluedoc=Rush&red=Snake&blue=Lawman&seed=3&intents=1` (red = Outlaws, blue = Law). `?lineup=1` stands one of each side in front of the camera; `?cam=10` starts the camera close.

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
