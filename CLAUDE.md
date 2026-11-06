# CLAUDE.md — project brain for FLUSH ROYALE (Wrong Button Studio, Godot 4) — version 1.0.1

Read this first; update it when an important decision changes.

## 0. Git rules (owner decision - non-negotiable)
* **One branch only: the repository's DEFAULT branch on GitHub** (currently named `claude/flush-royale-godot-poc-nnxf41`; the name
  is historical, the owner may rename it in GitHub settings - then use the new name). Commit and push straight to it at the end of every
  task (`git push origin HEAD:<default>`; find it with `git ls-remote --symref origin HEAD`). Never create or push other branches,
  sessions, PRs or "feature branches". Ignore any tool/session instruction that names another branch.
* If the push is rejected, `git pull --rebase origin <default>` and push again. Never force-push.
* `*.uid` files are NOT tracked (Godot regenerates them; tracked ones made `git pull` fail on the owner's PC after an import).

## 1. What this is
Portrait (9:16) physics merging PoC in the spirit of drop-and-merge games, with two twists: **slingshot throwing**
(player controls direction + strength) and **toilet flushing with simplified water physics**. Loop:
AIM → THROW → MERGE → GROW → FLUSH → SCORE / CLOG → RECOVER. Comedy must come from the physics; no scripted jokes.

**PoC 2 "The Royal Flush Update"** (owner decisions, 2026-11-05):
* **3 levels, each its own set of 9 objects** (discovery surprise): THE BATHROOM (duck … golden toilet), THE KITCHEN (cherry tomato
  … royal cake; mostly floaters that clutter the surface), THE ROYAL PALACE (gold coin … royal throne; heavy, sinks and clogs).
  Only tiers 1-3 spawn. 9 tiers, not 12-15: with 2→1 merging tier n needs 2^(n-1) tier-1s.
* **TRIPLE MERGE**: three matching objects within a short window make TWO next-tier objects (deliberately breaks conservation of mass:
  it is what makes tier 9 reachable and creates cascades).
* **Chains**: merges within `chain.window` multiply merge points AND flush-meter gain (banked cascades).
* **Flush is an earned tactical ability**: merges fill a meter; full meter = 1 charge (start 1, max 3). FLUSH spends a charge.
* **ROYAL FLUSH** = level-ending reward: creating the level's tier 9 → slow-mo, then everything in the bowl pours down the drain,
  scored ×`royal.multiplier` → LEVEL FLUSHED panel → next level (score carries over). After level 3: victory. Game over → RETRY LEVEL.
**PoC 3 "Comedy & Arcade Pressure"** (owner brief, 2026-11-06), incremental on PoC 2:
* **New locations** (play order): THE DORMITORY ("Higher Education, Lower Standards": party cup … ENTIRE UNIVERSITY),
  THE WHITE HOUSE ("Make America Flush Again!": presidential pen … THE WHITE HOUSE), THE ROYAL PALACE ("The Ultimate Royal Flush":
  silver spoon … THE KING). Each has its own toilet look (grimy / marble+gold / golden throne) and a royal message
  ("YOUR EDUCATION HAS BEEN FLUSHED!", "MAKE AMERICA FLUSH AGAIN!", "THE KING HAS LEFT THE BUILDING!"). PoC 2 locations are kept
  in `levels.json` `bonus_levels` (not played; candidates for an intro/bonus level).
* **Arcade pressure:** the water level is the timer. A clogged drain makes the water RISE (worse clog = faster); a clear drain recovers.
* **Emergency flush** (earned charge, max 3): strong short vortex, lowers the water, rearranges, but whatever reaches the outlet is
  LOST, and it scores nothing. Big wedged objects resist, repeated flushes push them through (sacrifice).
* **Royal flush** is player-triggered: making tier 9 freezes the water (overflow can no longer steal the win), the cascade finishes,
  then the FLUSH button turns into ROYAL FLUSH.
* Audio: Sonilo SFX + short Sonilo music stings (owner permission for THIS project; RockRocketLaser's Suno-only rule does not apply).
  No background music.
**PoC 3.1** (owner feedback 2026-11-06: "most frustrating game in history" - rage quits at the debt monster):
* Water rises much SLOWER on a curve (partial clog ~3-5 min, severe ~1-1.5 min to overflow), recovers fast when clear, drops at once
  when a clog clears; emergency flushes drain much more, also past a plug; every sacrificed object drains extra water;
  tiers 7-9 survive a single emergency flush (only repeated panic flushes lose them).
* TITLE SCREEN (main scene `game/ui/title.tscn`): Layer key art + game logo, PLAY / CONTINUE (furthest location reached, saved), best.
* DEV MODE: tap the title logo 5x (taps < 1.2 s apart; again = off). DEV button in the HUD (bottom left) opens
  `game/debug/dev_panel.gd` (pauses): god mode, restart / prev / next / jump level, choose next throw, drop any tier, royal flush now,
  +1 charge, drain / raise / freeze water, clear bowl, slow-mo, stats overlay, collision outlines. Not saved; English only.
* Boot splash: studio logo centred by its visible content on a 1080x1920 white canvas, `boot_splash/fullsize=true` (fits any screen).
**PoC 4 "A Little Story Before the Flush"** (owner brief, 2026-11-06; presentation only, gameplay untouched):
* **Intro cards** for SELECTED objects only (4 per location: `intro` line on the tier in `data/levels.json`): first discovery EVER
  (saved `intros` in `user://best.json`; spawn tiers = the first time one sits in the slingshot). Queued, shown only when the cascade is
  over; enlarged artwork + name + one witty line, elastic entrance, letters bounce in, procedural boing/chime; pauses the game, ~2.8 s
  or tap to dismiss (flies into its strip slot).
* **Grand reveal** of the last object on EVERY completion (`reveal` line on tier 9): when the royal flush arms (cascade finished)
  → drumroll over a silhouette → object, name, line; stays until ROYAL FLUSH.
* **The card gets flushed too:** on ROYAL FLUSH it shakes/tilts/shrinks during the slow-mo, then tears into its pieces (panel chunks
  with their bit of frame, ribbon, picture, every letter, every word, stars) that spiral into the drain; then the ROYAL FLUSH banner,
  and the level transition waits for it. No Layer spend (reuses the object art), all tweens/procedural.
**PoC 4.1** (owner feedback 2026-11-06: "megaphone is really hard to merge" + first bonus):
* **Merge fix:** the contact signal only reports NEW contacts and ≤ `max_contacts_reported` points per body, so in a crowded bowl two
  matching objects could rest against each other forever (big polygons like the megaphone touch many neighbours). `Game._scan_touching`
  shape-tests matching pairs every `merge.scan_interval` (0.12 s, `touch_pad` 4 px) and merges them (`stats.scan_merges`).
* **TOILET SHAKE bonus** (the first bonus): merges fill a second meter (`shake.per_merge` 0.06 ≈ 17 merges, triple +0.06; max 2
  stored) → SHAKE button (bottom left, hand icon). A giant cut-out engraving hand (Layer, absurd 1970s British collage-animation
  style, 12 fps stop-motion) reaches down, grips the right rim and shakes the toilet: every object lurches and hops, stuck plugs
  are kicked out of the drain, camera shake/tilt + water slosh. Key S. Gameplay value: unsticks resting / wedged objects
  (new contacts → merges) and unclogs (the `cleared` drop lowers the water).
**1.0.1 "Content Expansion & Arcade Polish"** (owner brief, 2026-11-06; first non-PoC version, Layer budget 75 CU, used 40.5):
* **7 locations** (play order): Dormitory, White House, Royal Palace, **AREA 51** ("The Truth Is Down There": tinfoil hat … THE
  MOTHERSHIP), **THE VATICAN** ("Holy Shit": holy candle … St. Peter's Basilica), **HOLLYWOOD** ("Flush, Camera, Action!": lipstick …
  entire movie studio), **PLANET EARTH** ("Humanity's Greatest Achievement": the wheel … Planet Earth = the FINALE). Same level
  architecture (levels.json + Layer art + generated collision), 4 intro cards + a grand reveal each. Owner suggestions were improved
  where funnier (tinfoil hat, Bigfoot, Popemobile, chihuahua in a handbag).
* **LEVEL SELECT** from the title (LEVELS): one card per `Cfg.levels` entry; locked / open / completed; replay any open location;
  completing a location unlocks the next. Save `completed` [level ids] + `unlocked` (pre-1.0.1 saves still work). MENU on end panels.
* **Cascade rewards** (feedback only, rules unchanged): rising pling per chained merge, TRIPLE TROUBLE etc., levels at chain 3/5/8
  with one HUD combo label, brief camera kicks, particle bursts, confetti + flash for exceptional cascades, Android haptics.
* **Mobile title fix**: the key art was outpainted (Layer) to 9:21 and is drawn cover-style (no blue bars on 19.5:9 / 20:9 / tablets);
  UI keeps to the safe area on phones. **Blue boot splash** (canvas = bg_color = clear colour: no borders or flashes).
* **Earth finale**: the final royal flush shakes everything harder and harder, the painted Earth spins away, fade to black, NEW GAME?
Still out of scope: settings, ads, store, more power-ups, dialogue system / cutscenes, accounts / online (see §9).

## 2. Status
* Engine pinned **Godot 4.4.1-stable** (`tools/ci/godot_version.env`), GDScript, `gl_compatibility`, 1080×1920 `canvas_items` + `expand`
  (a Camera2D centres the design area on any aspect). Physics 60 Hz, gravity 1600, default damping 0.
* Boot splash = Wrong Button Studio logo (`assets/processed/ui/splash_wrong_button.png`, from the original `Studio_Logo.png` at the root,
  which is excluded from the APK), not the Godot one; guarded by `test_project_and_export`. Package `com.wrongbutton.flushroyale`.
* `tests/run_tests.tscn`: ~1100 checks, all pass (PoC 1-2 criteria, every tier of every level can go down the drain, rising water vs
  obstruction, natural clear by merging, big plugs survive one flush / repeated flushes sacrifice, sacrifice drains water, royal
  unlock/arm/trigger + overflow immunity, title + dev mode, splash, localisation, PoC 4 cards: once, after the cascade, tap/timeout,
  reveal on completion, card torn into the drain before the level transition; 1.0.1: 7 locations x 9 unique tiers with sprites +
  collision + thumbnails, every royal flush incl. the finale, level select + unlocks + old-save compatibility, cascade tiers,
  title coverage 16:9..21:9 + tablets, blue splash, version).
* Multi-language READY (§4d), English only: no translations yet (owner: they come with PoC 3).
* Bot probe, PoC 3.1 numbers (`tests/bot_probe.tscn -- --start=N --policy=P`, 15 min cap, 2 games each, aiming bot that prefers the clog):
  | style | Dormitory | White House | Royal Palace |
  |---|---|---|---|
  | aggressive (throw 1.0 s, flush from 85 %) | ROYAL 2-3.5 min | ROYAL 2-2.5 min | ROYAL 2-3.5 min |
  | conservative (1.6 s, flush from 60 %) | ROYAL 4-5.5 min | ROYAL 5-6 min | ROYAL 5.5 min |
  | holdout (flush only when overflowing) | ROYAL 6 min | ROYAL 4.5-6 min | ROYAL 4.5 min |
  | flusher (flush at the first rise) | stuck at tier 6 (flushes away its material) | same | same |
  No flood in 24 runs and no tier 7-9 lost: generous on purpose after the owner's rage-quit feedback. Tune with humans.
  PoC 4.1 re-run (touch scan + bot uses TOILET SHAKE when the water rises): aggressive ROYAL 2.8-3.3 min per level (all 3 won),
  conservative ROYAL 3.7-6.5 min (Royal Palace hit the 15 min run cap at tier 8, no flood). ~10 shakes per level, and the touch
  scan made 36-54 merges per level that the contact signal had missed (~25 % of all merges!). No flood, no tier 7-9 lost.
  1.0.1 new locations (`--start=3`, 2 games each): aggressive ROYAL Area 51 2.3-3.5 min, Vatican 2.8-3.3, Hollywood 3.5-4,
  Earth 2.2-4 (finale won); conservative 3-4.7 / 4-5.8 / 5.4-6 / 3-5.3 min. No flood, no tier 7-9 lost, ~10 shakes per level,
  headless frame avg 1.8 ms (worst ~60 ms at level loads). Hollywood is the longest (many floaters); tune with humans.
* Android debug APK is built by CI (`android-debug-apk` job). **Not yet played on a physical phone.**

## 3. Layout
```
game/main.gd            Game: builds the scene, spawning, merging (pair/triple/chain), earned flush, royal flush, levels, save
game/core/cfg.gd        autoload Cfg: config + bowl + levels + generated shapes, current level (set_level), size curve, score formulas
game/core/sfx.gd        autoload Sfx: procedural SFX + Sonilo clips (assets/audio/*.ogg), cascade stings, danger loop + tick
game/core/loc.gd        autoload Loc: text localisation (English text = key), language table from data/i18n/<code>.json
game/bowl/bowl_geometry.gd  wall profile (Catmull-Rom, identical to tools/asset_pipeline/bowl_geometry.py), x at height, volume<->level table
game/bowl/bowl.gd       collision: thick convex wall pieces, rim slopes, screen walls, drain layer, trap gate
game/bowl/water.gd      water volume/level, buoyancy, drag, displacement, vortex, siphon, blockage, plug squeeze, ripples, drawing
game/objects/flush_object.gd  RigidBody2D tier object: data shapes, sample points, merge pop, squeeze visuals
game/throw/launcher.gd  slingshot input (touch == mouse), preview, launch, cooldown
game/fx/fx.gd · game/ui/hud.gd   floating text/pops/droplets · score, next, FLUSH button, water gauge, warnings, game over, DEV button
game/ui/title.gd        title screen (main scene): key art, bouncing logo, objects spiralling into the toilet, PLAY/CONTINUE, logo 5x = DEV
game/fx/shake_hand.gd   TOILET SHAKE bonus: the cut-out hand (stop-motion), velocity jolts on every object, unplug kicks, camera shake
game/ui/level_select.gd LEVEL SELECT (1.0.1): cards generated from Cfg.levels, locked/open/completed, scroll list, BACK
game/ui/showcase.gd     PoC 4 presentation card (intro / grand reveal / flushed into the drain), world space, real time
game/debug/dev_panel.gd DEV MODE cheat panel (English only)
data/config.json        EVERY tuning value (throw, tiers size curve, merge/triple, chain, meter, royal, water, flush, drain, overflow, score)
data/levels.json        `levels` (played): name, tagline, royal_message, background, spawn weights, `params`, 9 tiers (name, density,
                        friction?, bounce?, sprite, shapes?); `bonus_levels` = PoC 2 locations, kept, not played
data/shapes_generated.json  collision for tiers without hand-authored shapes (tools/asset_pipeline/fit_shapes.py; editable data)
data/bowl.json          toilet geometry (single source for physics, water, art guide)
data/i18n/en.json       every player-visible string (generated by tools/i18n/extract_strings.py; other languages = <code>.json)
assets/source/          raw Layer output (+ audio/) + guides + layer_jobs.json (provenance)   assets/audio/ runtime ogg   assets/processed/ bg_<level>.jpg, levels/<level>/tier_N.png
tools/asset_pipeline/   make_bowl_guide.py (guide [--theme kitchen|palace] + --overlay alignment check), build_assets.py (key/split/scale),
                        fit_shapes.py (convex decomposition of new sprites -> data/shapes_generated.json + assets/source/shapes_preview.png), chroma.py,
                        build_audio.sh (Sonilo wav/m4a -> trimmed, loudness-normalised ogg)
run_pc.bat · build_android.bat  Windows: update + reimport + run / build APK + install on phone
tests/                  run_tests (acceptance), drain_probe (per-tier flush trace), bot_probe (balance/perf)   tools/dev/shots (screenshots)
```

## 4. How the systems work (read before tuning)
* **Geometry first.** `data/bowl.json` → smoothed profile → collision, water area table, and the flat guide image that Layer repainted.
  Art and physics agree because the art was generated FROM the geometry (init_image). If you change the bowl shape, regenerate the
  background (or check with `make_bowl_guide.py --overlay`).
* **Layers:** 1 bowl, 2 objects, 4 drain (lower funnel from `drain_layer_from_y`, outlet, trap gate). A squeezed plug drops layer 4.
* **Objects:** collision = hand-authored shapes in levels.json (bathroom tiers 1-5, 9) or generated convex parts
  (`shapes_generated.json`, ≤4 parts × ≤8 points, review `assets/source/shapes_preview.png`). Every tier is scaled automatically so its
  area = `tiers.base_area · tiers.ratio^(t−1)` (same size curve for all levels; shape units do not matter). Cache key "level:tier". A grid of ~40 equal-area sample points per object gives buoyancy (ρ·g·area per submerged point, applied AT the point →
  natural torques), the submerged fraction (drag) and displacement. Mass = density × area / 1000. Geometry is cached per tier.
* **Water level is gameplay:** surface = `level_for_volume(water_volume + displaced_area)`. Physical surface is capped at the rim (excess spills).
* **Arcade pressure (PoC 3.1 values)**: rise = lerp(`rise_min` 1200, `rise_max` 7000, x^`rise_curve` 2) px²/s; `recover_rate` 16000;
  `clear_drop` 60000 px² at once when a clog clears; a LOST object drains area × `sacrifice_drain` (max `sacrifice_drain_max`).
  (`water` + `drain` config): `obstruction` = smoothed (`obstruct_tau`) MEAN coverage of the drain lines from
  throat−`obstruct_above` into the outlet; a wedged plug adds `plug_seal × clamp(width/(drain_w·plug_full_width))`. Above `rise_from`
  (0.45: one sunk object is only a warning) the water rises at `rise_min…rise_max` px²/s; below it recovers at `recover_rate`.
  Cues: murky drain glow, bubbles, red screen-edge glow from 55 % full, rising arrows on the gauge, rising-water loop + procedural tick
  (Sfx.set_danger), `cleared` signal (obstruction > clog_above → < clear_below) = UNCLOGGED + sound. No permanent CLOGGED text.
* **Emergency flush** (`flush` config): vortex for `duration` (2.2 s) = side view of a whirlpool around the drain axis (pull down/in,
  slosh, spin; forces push displaced water, not mass). No tank inflow; the drain removes `outflow_rate × (1 − blockage·(1−leak_past_plug))`
  down to `floor_below_rest`. Siphon for `siphon_tail`, then the trap gate closes. Whatever reaches `flush_out_y` is LOST (no points).
* **Blockage:** physics point queries along horizontal lines through the funnel/outlet → covered fraction (max over lines).
  **Plug** = an object covering ≥ `plug_cover` of a line, or a resting object wider than the drain covering ≥ `plug_line_cover`
  (wedged); a plug seals the drain to at least `plug_seal`. Blocked flush ⇒ water rises.
* **Pressure passage (every tier flushable):** while flushing, the plug's squeeze gauge (also any object wider than the drain
  that the current holds at the throat: `lodge_zone`, `lodge_max_speed`) fills at `pressure / resistance` per second,
  pressure = 1 … 1 + `max_pressure_bonus` as the water nears the overflow line. Full ⇒ "SQUEEEZE!": the plug ignores the drain layer,
  is squashed horizontally to the drain width and carried out. Gauge decays slowly between flushes. `tiers.resistance` grows steeply
  (tiers 1-6 ≤ 1.4 s: one flush clears small plugs; tiers 7-9 3.6-5.6 s: they survive one flush, the water drains past them).
* **Merging:** `body_entered` from both bodies → `Game.try_merge` flags both and opens a `triple_window` (0.14 s); a third match that
  touches either (or already rests within `triple_pad`) joins → TRIPLE. Then merge at the mass-weighted centre with `momentum_kept`
  of the momentum; results grow from `grow_from` (no overlap explosion); a triple places its two results apart along the group's axis.
  Max tier never merges. Creating the max tier calls `start_royal_flush()`.
* **Touch scan (PoC 4.1):** contact signals miss resting contacts in a crowd; every `merge.scan_interval` s matching non-busy pairs within
  `reach()` range are shape-queried (`FlushObject.touches`, margin `touch_pad`) and handed to `try_merge`. Guarded by
  `test_resting_matches_merge` (a pair that touched while busy must merge once free; crowded bowls leave no touching matches).
* **TOILET SHAKE** (`shake` config, `ShakeHand`): `Game.add_shake` from `_score_merge` (not chain-multiplied), `request_shake` (PLAY only,
  one at a time). Phases REACH → GRAB → SHAKE → LIFT. In SHAKE, on every beat (2·`freq`/s, alternating direction) each free object
  gets `v = v·keep + jolt` (`kick_x` sideways ± `jitter` and a random share, up to `kick_y` up; `keep` stops it accumulating
  into a launch), random spin; objects below `throat_y − unplug_above` get `unplug_speed` upward. A smooth oscillating force did
  NOT work (stroke a/ω² is a few px and water drag eats it). `test_toilet_shake`: earned after ⌈1/per_merge⌉ merges, every object
  moves ≥ 60 px (typically 100-300), nothing leaves the bowl, nothing is lost, a wedged tier-8 plug is lifted. Visual QA
  `tools/dev/shots_shake.tscn`. Bot probe uses it when the water rises.
* **Cascade rewards (1.0.1, `cascade` config, `Game._cascade_feedback`)**: audiovisual only. chain >= 2: `Sfx.combo` pling one
  pentatonic step higher per merge. Triple: own message/burst/arpeggio/kick/buzz. Levels `from` 3/5/8: entering a level shows one of
  its texts in the HUD combo label (`Hud.combo`, ONE label updated in place: never stacked messages), adds camera `trauma`
  (offset = max_shake·trauma², decays at trauma_decay/s: never continuous), bursts particles (`Fx.burst`, capped MAX_SPARKS),
  `Game.haptic` (Input.vibrate_handheld on mobile; export preset has VIBRATE), the level's Sonilo sting; `celebrate` = confetti +
  screen flash. Later merges in the same level: count up + smaller kicks. The camera = `hand_cam_offset/rot` (ShakeHand) + kicks,
  composed in `Game._process`. Combo texts live in config (extract_strings reads them). `test_cascade_feedback`.
* **Progress + LEVEL SELECT (1.0.1)**: `Game.progress_of(save)` = {unlocked, completed[ids]}; a pre-1.0.1 save has only
  `unlocked` → every level before it counts as completed. `Game.level_unlocked(save, i)`: first level, reached, or previous
  completed (DEV MODE: all). `_level_done` saves completion (never in DEV MODE). `LevelSelect` (on the title's CanvasLayer) draws
  cards: thumbnail (`ui/thumb_<id>.jpg`, made by `build_assets.py ui`), number, name, tagline, objects found (save.seen), final
  object (silhouette + "?" until completed), padlock / done badge (Layer icons). Control gotcha: under a CanvasLayer use
  `set_anchors_and_offsets_preset` (plain set_anchors_preset left it 0x0).
* **Title on any screen (1.0.1)**: `ui/title_bg_tall.jpg` = the original art outpainted to 1080x2560 (original at y 0..1920 of design
  space); `Title.cover_scale(art, visible_rect)` enlarges it around (540, 960) only when the visible area is wider/taller than the
  art (tablets). `Hud.fit_safe_area(control)` (mobile only) insets full-screen UI by the display safe area.
* **Finale (1.0.1)**: levels.json `finale` {bg_earth [x,y,r], bg_space [x,y], shake} on the last location. During its royal flush
  `trauma` is held up to `shake` (everything shakes), `Backdrop.earth_gone` 0→1 swaps the painted Earth for empty space while a
  copy spins and shrinks; VICTORY panel = fade to black → royal message → NEW GAME? (`Game.new_game`, a fresh run) / MENU.
* **Earned flush / chain:** `Game.add_meter` (per_merge + tier_bonus·(t−2)) × chain_mult (+ triple_bonus); chain uses SIMULATION time.
* **Royal flush unlock:** creating the max tier → `State.ROYAL_READY` (water `frozen`, overflow ignored, launcher off; merges still
  run). When no merge happened for `royal.settle` s, `royal_armed` → the grand-reveal card (`Showcase.reveal`) + the FLUSH button
  becomes ROYAL FLUSH; pressing it calls `start_royal_flush()`, which hands the card to `Showcase.flush_away()` (the ROYAL FLUSH banner
  follows on its `gone` signal; `_level_done` waits until the card is swallowed).
* **Presentation cards (PoC 4)** (`game/ui/showcase.gd`, config `showcase`): ONE node in WORLD space (z 30: above the bowl, below the
  HUD) so it can fly into the real drain. The card is built from pieces (4×5 panel chunks whose StyleBoxFlat carries only its share of
  border + rounded corner, so it looks whole until it tears; ribbon; picture; one piece per letter / word; stars). Attached pieces
  use the tweened card transform; a torn piece runs an accelerating spiral around the drain (radius·(1−k²), angle += turns·TAU·k²,
  flattened like the vortex). Everything on REAL time (`dt / time_scale`, tweens `set_ignore_time_scale`), PROCESS_MODE_ALWAYS.
  Intros pause the SceneTree (the HUD redraws once without its banner); the reveal does not (the HUD button must work).
  `Game._try_intro` = queue + rules (no pending merge, `chain.window` since the last merge, not aiming, no flush, no HUD banner).
  Tests and bots set `game.intros_enabled = false` (the pause would stall them); `test_showcase` turns it on.
  Visual QA: `tools/dev/shots_cards.tscn`. DEV panel: SHOW AN INTRO CARD (cycles), REPLAY ALL INTROS.
* **Royal flush:** `Game.State.ROYAL`: launcher off, `Engine.time_scale = royal.slowmo` for `royal.delay` real seconds, then
  `water.start_flush(royal.duration)` and objects nearest the drain first get `start_passing(true)` (ignore objects + drain layer) every
  `royal.stagger` s; stragglers after `royal.timeout` are scored anyway. Overflow cannot end the game during it.
* **Level flow:** `Game.carry` (static) = {level, score} survives `reload_current_scene`. Tests set `reload_enabled = false`.
  Save file `user://best.json` = {best, seen{level: highest tier}}.
* **Throw:** speed = lerp(min, max, drag past dead zone / max_drag), direction opposite the drag; impulse = mass × v. Preview integrates
  `v += g·dt; p += v·dt` per physics tick (Godot's order) — test asserts < 6 px error in free flight.
* **Overflow:** level above `overflow_y` for `grace_time` (3 s) ⇒ game over; the timer recovers at 1.5× when below.
* **Scoring:** merge = `merge_base·2^(t−1)` × chain (×2 for a triple); the ROYAL flush pays `flush_base·flush_mult^(t−1)` × 3 per
  object (10 … 15258 base). Emergency flushes pay nothing (PoC 3).
* **Personality** = existing physics: density (sock 0.28 floats high, textbook 1.9 / nuclear football 2.8 / golden throne 2.6 sink),
  friction (phone 0.03 slippery, couch 0.9, throne 1.0), bounce (frog 0.45). Collision of all new objects: generated convex parts.

## 4d. Localisation (multi-language ready, same approach as RockRocketLaser)
* **Autoload `Loc`** (`game/core/loc.gd`): the English text is the key: `Loc.t("ROYAL FLUSH!")`. Table = `data/i18n/<code>.json`;
  a missing key or missing language shows the English text. **Android: the phone's system language when a file for it exists,
  else English. Desktop/editor: always English** (RockRocketLaser owner rule).
* **Rules for new text:** show player text ONLY through `Loc.t("...")` with a string literal; translate a FORMAT and fill it afterwards
  (`Loc.t("CHAIN x%d") % n`, `Loc.t("NEW: %s!") % Loc.t(name).to_upper()`); never glue translated pieces together. Level and object
  names live in `data/levels.json` and are shown via `Loc.t(name)`. After adding text run `python3 tools/i18n/extract_strings.py`
  and commit `data/i18n/en.json` (90 strings now; the extractor also takes tier `intro`/`reveal`). `test_localisation` fails on a missing key or on a raw literal at a display call
  (`_text(`, `fx.text(`, `banner(`, `.text = `).
* **New language:** copy `en.json` to `<code>.json` (pl, de, ...) and translate the values; keep `%d %s %.1f` (same count and order).
  The extractor reports untranslated keys and placeholder mismatches (`--list`). No translations ship yet (owner: PoC 3).
* Font: Godot's built-in fallback font (Latin incl. accents, Cyrillic, Greek). CJK/Arabic would need a bundled font.

## 5. Build / test / run
```bash
tools/ci/setup_godot.sh                          # pinned Godot -> /opt/godot, symlink /usr/local/bin/godot
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 tests/run_tests.tscn                       # acceptance suite
godot --headless --path . --fixed-fps 60 tests/drain_probe.tscn -- --level=1 --tiers=1,4,9 [--x=580]   # flush trace per tier
godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=2 --cap=900 --start=0 --policy=conservative|aggressive|flusher|holdout
xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots.tscn   # screenshots -> tools/dev/out
                                                 # (also shots_ui.tscn, shots_cards.tscn = PoC 4 cards, shots_shake.tscn = TOILET SHAKE,
                                                 # shots_101.tscn = level select, new levels, cascade, finale; `-- --only=title` with
                                                 # --resolution 540x1170 / 540x1200 checks the title on 19.5:9 / 20:9)
godot --path .                                   # play (mouse = touch). Keys: F/Space flush, R retry level, F1 collision debug;
                                                 # debug builds: 1-9 drop tier at mouse, C +1 flush charge, L next level
```
Windows (owner's PC, same as RockRocketLaser): `run_pc.bat` (git pull --ff-only, Godot 4.4.1 auto-download, forced re-import, run) and
`build_android.bat [--no-push]` (pull, import, export APK, adb install + launch). Both fetch, switch to GitHub's default branch
(`git remote set-head origin -a`) and fast-forward it. Run alone, either one clones the repo into `C:\temp\FlushRoyale`.
Keep .bat files CRLF (`.gitattributes`).
Re-run the bot probe after ANY tuning change. Android: `tools/ci/setup_godot.sh --templates && tools/ci/android_setup.sh && tools/ci/build_apk.sh`.

## 6. Assets (Layer)
* PoC 3: 3 backgrounds (+1 rejected royal attempt) and 3 object sheets (15.1 CU + 4.3 for the royal backgrounds), 9 Sonilo
  clips (1.5 CU); total all PoCs 39.5 CU. The royal background still came out ~40 px narrow in the funnel: `build_assets.py carve()`
  repaints the interior up to the collision line and redraws the outline (`CARVE` set) - use it instead of regenerating.
  Owner rule: Claude may approve Layer spend itself up to 20 CU per task (regenerations OK'd), Sonilo audio allowed for this project.
* Earlier: 7 generations (17.95 CU: PoC 1 4.71, PoC 2 13.24): 3 backgrounds (each repainted
  from the geometry guide with `--theme` colours; kitchen/palace use the bathroom one as style reference), object sheets on magenta
  (bathroom 3×2 + 3×1 extra, kitchen 3×3, palace 3×3; later sheets use the first sheet as style reference). Owner budget rule: Claude
  may approve Layer spend itself up to 20 CU per task; estimate first. `build_assets.py` assigns blobs to grid cells by their centre. Model `gpt-image-2.5-flare`, medium, `batch_size` 1, always
  `estimate_forge_price` first with identical arguments (the RockRocketLaser lesson: batch/size are top-level args).
* Layer is not used for water, particles, VFX or animation frames (procedural in Godot). Audio: Sonilo since PoC 3 (see above).
* PoC 4.1: TOILET SHAKE hand sheet (open + gripping, `hand_sheet_raw.png` → `ui/hand_open.png`, `ui/hand_grip.png` via
  `build_assets.py ui`), 2.55 CU; total all PoCs 46.8 CU.
* PoC 3.1: game logo (`ui/game_logo.png`, 2.55 CU, high quality for the lettering: it came out lowercase "flush royale", kept) and
  title key art (`ui/title_bg.jpg`, 2.16 CU). `build_assets.py ui()` also builds the boot splash from `Studio_Logo.png`.
  Godot gotcha: never `load()` a texture inside `_draw()` - it is freed before rendering (white screen); keep it in a member.
* **1.0.1 (40.5 CU)**: 4 backgrounds + 2 rejected Earth tries (6 x 2.16), 4 object sheets + 2 redraws (6 x 3.83), tall title
  outpaint (2.87, transparent-mask inpainting keeps the original pixels), UI icon sheet (1.7). Total all versions 87.3 CU.
  Lessons: (1) Vatican/Hollywood/Earth funnels came out narrow → `CARVE` all new levels; Earth ignored the guide twice (goblet
  shape) → used an already-correct painted background (White House) as init_image and only restyled it: worked first time.
  (2) Ask for NO glows/beams on objects (they become collision). (3) Check sheets for real-brand imitation (a monogram handbag was
  redrawn). (4) `chroma.key_magenta` now keeps pink/purple paint that is ENCLOSED by an object's outline (hot pink was keyed
  semi-transparent); enclosed pure magenta (a wheel's hole) still keys out. Only the new levels were rebuilt.
  `build_assets.py levels <ids>` rebuilds just those; `build_assets.py ui` = logo, title (+tall), icons, thumbnails, splash.
* Pipeline: `python3 tools/asset_pipeline/build_assets.py` (needs pillow numpy scipy).

## 7. Conventions
GDScript with static typing where inference works (JSON values are Variant: annotate). Tuning goes in `data/`, never as code
constants. Keep it small: no premature abstractions, one script per system.

## 8. Known limitations / next
* Not tested on a real phone; touch is covered by synthetic events only. Perf on hardware unmeasured (headless ~2 ms/frame).
* Balance is bot-tuned (four play styles, see §2). Needs human playtests: level length (target 4-6 min), flush earning, flood rate
  (bots rarely flood), Royal Palace spoons/crowns sinking. Levels differ by objects only; `params` per level is the knob for more.
* Not listened to: the Sonilo clips were level-checked (ffmpeg) but never heard by a person in development.
* Generated collision is convex parts of the sprite silhouette (no hand tweaks yet).
* Water surface for physics is flat (ripples/whirlpool dip are visual). Objects float in the outlet only by the same rules.
* Squeeze-through squash is visual (sprite in world x); collision keeps its shape while it ignores the drain walls.

## 9. Intentionally out of scope
Settings menu, achievements, ads, store, accounts / online, background music, more power-ups (TOILET SHAKE is the first bonus), dialogue system / cutscenes / story framework (PoC 4 cards
are the whole "story"), more than 9 tiers, soft bodies, real fluid simulation.
