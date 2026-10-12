# Brawl Bots

Gunslingers and ninja clans fight it out on four maps, played entirely by AI - and the AI is
yours to rewrite. Part of the [Precog sim suite](https://apps.precogsoftwareservices.com).
(It began as Saloon Bots: a 5-v-5 six-shooter fight in a saloon.)

**Live:** https://brawl-bots.apps.precogsoftwareservices.com

## What's in it

- **Four maps**, each mirror-symmetric so neither side starts with the better ground:
  - **The Saloon** - bar of breakable bottles, piano, tables you kick over into cover, a balcony
    with a balustrade (see-through; stops half the slugs) reached by two stairs.
  - **The Dojo** - paper screens you can shoot through but not see through, a great drum, weapon
    racks, rafters up four ladders.
  - **Bamboo Grove** - dense bamboo, rocks and logs, a stream crossed by one bridge (or a jump),
    two shrines whose roofs make lookouts.
  - **Temple Rooftops** - courtyard walls and a koi pond to vault, a pagoda, hall roofs and a
    gallery roof to run along, up ladders or by leaping.
- **Four factions, any against any:** the **Outlaws** (bandana masks, black hats) and the **Law**
  (tin stars, pale hats) with Colts and fists; the **Black Lotus** and **Red Dragon** ninja clans.
- **Ninja characters:** Shinobi (katana, 6 stars), Kunoichi (nunchaku, 10 stars, best jumper),
  Monk (bo staff - longest reach, best block, sweeps legs), Ronin (katana, 3 stars, never backs
  down), Shadow (katana, 12 stars). Western characters are temperaments: Gunslinger,
  Sharpshooter, Brawler, Snake, Lawman, Coward, Desperado, Balanced.
- **Grades - skill, not armour:** Minion, Regular, Veteran, Super (Greenhorn ... Super Gunslinger;
  Genin ... Grandmaster). A Super dies to one good slug or one clean cut like anyone else; he is
  faster (moves, draws, cocks, reloads, swings), jumps further (vaults, drops, leaps up onto
  decks), thinks faster and better, has steadier hands and doesn't panic. Minions are the reverse.
  1-12 fighters a side, so 3 supers against 10 minions is a match.

## Rules of the fight

- Last side standing wins. Three-second standoff. At **2:00** the side with more men standing wins
  on decision; level, it's **sudden death** - next man down loses it.
- **Vital hits kill:** head or heart. Gut shots hurt badly and bleed. Arm and leg hits cost little
  blood but cripple: the gun hand goes to the off hand, reloads and blows slow, both arms and he
  can't punch; one leg is a limp, both and he crawls. **Every wound bleeds** - one is about a
  minute from death, two about half that. Blood pools on the floor and men can **slip** in it.
- **Aim time is accuracy:** spread x(1 + 2.2 e^(-t/0.42)). Six in the Colt, **18 rounds** in all,
  then fists. Guns **jam**, especially in a scuffle; a punch to a raised gun can jam it.
- **Blades and staffs:** reach, wind-up, and the other man's defence - he can **block** a blow he
  sees coming (and a star), **parry** and riposte, or **dodge**. A katana cuts (bleeds; finds the
  throat and heart more often in a better swordsman's hands); nunchaku and staff bruise, break
  limbs and ring skulls (knockdowns). **Bottles** come off the bar, the shelf and every table:
  an empty or jammed gunman (or a brawler) throws one at a head (a skull hit knocks him flat) or
  breaks it over one. **Over the rail:** a man shot or hit at the balcony's edge goes through the
  balustrade and the fall kills him; off a low roof it only knocks him flat. **Throwing stars** are silent, slower than a slug, rarely
  kill outright and always bleed.

## The AI

**Team brain** (`scripts/team_brain.gd`): a blackboard of every enemy seen or heard, counting every
shot (rush a man counted empty); a tactical map scoring every spot for cover, sight lines and the
angles that beat the enemy's cover; and a commander running one of seven plans - Adaptive, Dig In,
Rush, Pincer, High Ground, Leapfrog, Bait - with clock sense in the last 25 s.

**Each man** (`scripts/gunman.gd`): ten personality traits weight a utility score over the map,
blended with his orders by his discipline. He is always in a **mode** you can see over his head:
hold, advance, duck, hide, cower, flank, rush, fall back, brawl, hunt - and he walks the map his
legs allow: vaulting low cover and water, dropping off decks, leaping up onto them, climbing
ladders.

**The rules** (`scripts/ai_script.gd`) - the exposed AI. Each side can run a script, edited in the
app (*Teams / tactics -> Edit AI rules*), checked with line-numbered errors (with "did you mean"
for typos), saved in the browser. Type a few letters and it suggests what can go there - a
condition, a number, an action, a trait - with what it means (Tab or tap to take one); the word
under the cursor is explained; *Add an example* drops in a ready-made rule:

```
# first rule that holds (and can be done) wins; anything uncovered -> built-in brain
set caution 0.85
aim 1.25
when pinned -> hide for 2
when bleeding and bleed_secs < 15 -> rush nearest for 3
when enemy_reloading and nearest < 8 -> rush reloading
when super and stalemate -> flank
when melee and in_reach -> rush nearest
otherwise -> default
```

About 33 yes/no conditions (bleeding, pinned, aimed_at, enemy_reloading, high, edge, outnumbered,
super, melee, in_reach, has_bottle, near_bottle, ...), 14 numbers (hp, bleed_secs, ammo, nearest, time, diff, random, ...),
12 actions (hold, advance, hide, flank, rush nearest|weakest|reloading|high|aiming|melee,
fall back, take high, hunt, flip table, grab bottle, cower, default), `set <trait>` and `aim <multiplier>`.
Presets to start from: Careful hands, Wild bunch, High ground first, Ninja ambush, Supers lead
minions swarm, Last stand. *Show intents* prints which rule each man is following; the results
list how often each rule decided.

## Running it

Query string = command line: `?map=bamboo&redf=lotus&bluef=law&redn=2&redgrade=Super&bluen=5&bluegrade=Minion&intents=1`,
`?redscript=Ninja ambush`, `?lineup=1`, `?cam=10`. Headless (Godot 4.4+):

```sh
godot --headless --path . -- --sim=20 --map=temple --redf=dragon --bluef=outlaws --redgrade=Super --redn=3 --bluen=8
godot --headless --path . -- --sim=20 --redscript=my.rules       # a rules file
godot --headless --path . -- --league=5 [--pairs=Rush:Dig In] [--part=0/4]
godot --headless --path . -- --presets=5
```

## Build and deploy

`bash build.sh` (Godot 4.7.2 + web templates) exports to `dist/`, boot-checks the pack and gzips.
`Dockerfile` + `nginx.conf` serve it; `headers.caddy` adds COOP/COEP. Meshes and most sounds are
built in code; the voices are espeak-ng lines baked into `sfx/voice/` by `tools/make_voices.sh`.
