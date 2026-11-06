# CLAUDE.md — project brain for FLUSH ROYALE (Wrong Button Studio, Godot 4 gameplay PoC)

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
Still out of scope: main menu, settings, ads, store (see §9).

## 2. Status
* Engine pinned **Godot 4.4.1-stable** (`tools/ci/godot_version.env`), GDScript, `gl_compatibility`, 1080×1920 `canvas_items` + `expand`
  (a Camera2D centres the design area on any aspect). Physics 60 Hz, gravity 1600, default damping 0.
* Boot splash = Wrong Button Studio logo (`assets/processed/ui/splash_wrong_button.png`, from the original `Studio_Logo.png` at the root,
  which is excluded from the APK), not the Godot one; guarded by `test_project_and_export`. Package `com.wrongbutton.flushroyale`.
* `tests/run_tests.tscn`: 568 checks, all pass (PoC 1 acceptance criteria + every tier of every level flushable within 2 flushes,
  size curve, earned charges, triple merge, chain, royal flush → level done / victory / retry, localisation).
* Multi-language READY (§4d), English only: no translations yet (owner: they come with PoC 3).
* Bot probe (`tests/bot_probe.tscn`, aiming bot, 20 min cap), PoC 2 numbers:
  `--policy=danger` (flush only near the overflow line): tier 9 after ~4-5 min per level, 1 of 3 runs won all three levels,
  the others flooded at 5-9 min. Default policy (flushes whenever the water rises / charges are full): survives 12-20 min but
  rarely grows past tier 6-8 because it keeps flushing its material. Real players should sit between; tune with humans.
  Average physics frame ~1.7 ms (headless).
* Android debug APK is built by CI (`android-debug-apk` job). **Not yet played on a physical phone.**

## 3. Layout
```
game/main.gd            Game: builds the scene, spawning, merging (pair/triple/chain), earned flush, royal flush, levels, save
game/core/cfg.gd        autoload Cfg: config + bowl + levels + generated shapes, current level (set_level), size curve, score formulas
game/core/sfx.gd        autoload Sfx: code-synthesised sound effects (no audio assets)
game/core/loc.gd        autoload Loc: text localisation (English text = key), language table from data/i18n/<code>.json
game/bowl/bowl_geometry.gd  wall profile (Catmull-Rom, identical to tools/asset_pipeline/bowl_geometry.py), x at height, volume<->level table
game/bowl/bowl.gd       collision: thick convex wall pieces, rim slopes, screen walls, drain layer, trap gate
game/bowl/water.gd      water volume/level, buoyancy, drag, displacement, vortex, siphon, blockage, plug squeeze, ripples, drawing
game/objects/flush_object.gd  RigidBody2D tier object: data shapes, sample points, merge pop, squeeze visuals
game/throw/launcher.gd  slingshot input (touch == mouse), preview, launch, cooldown
game/fx/fx.gd · game/ui/hud.gd   floating text/pops/droplets · score, next, FLUSH button, water gauge, warnings, game over
data/config.json        EVERY tuning value (throw, tiers size curve, merge/triple, chain, meter, royal, water, flush, drain, overflow, score)
data/levels.json        3 levels: name, background, spawn weights, optional config `params`, 9 tiers each (name, density, sprite, shapes?)
data/shapes_generated.json  collision for tiers without hand-authored shapes (tools/asset_pipeline/fit_shapes.py; editable data)
data/bowl.json          toilet geometry (single source for physics, water, art guide)
data/i18n/en.json       every player-visible string (generated by tools/i18n/extract_strings.py; other languages = <code>.json)
assets/source/          raw Layer output + guides + layer_jobs.json (provenance)   assets/processed/ bg_<level>.jpg, levels/<level>/tier_N.png
tools/asset_pipeline/   make_bowl_guide.py (guide [--theme kitchen|palace] + --overlay alignment check), build_assets.py (key/split/scale),
                        fit_shapes.py (convex decomposition of new sprites -> data/shapes_generated.json + assets/source/shapes_preview.png), chroma.py
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
* **Flush** (`flush` config): vortex for `duration` = side view of a whirlpool around the vertical drain axis: pull DOWN (strongest on the
  axis), pull toward the axis, sideways slosh + spin. Vortex/outlet forces push *displaced water* (like buoyancy), not object mass —
  otherwise light floaters can never be flushed. Tank adds `inflow_total`; drain removes `outflow_rate × (1 − blockage)`. The siphon
  keeps pulling the outlet for `siphon_tail` after the vortex, then the trap gate closes (only when nothing straddles it).
* **Blockage:** physics point queries along horizontal lines through the funnel/outlet → covered fraction (max over lines).
  **Plug** = an object covering ≥ `plug_cover` of a line, or a resting object wider than the drain covering ≥ `plug_line_cover`
  (wedged); a plug seals the drain to at least `plug_seal`. Blocked flush ⇒ water rises.
* **Pressure passage (every tier flushable):** while flushing, the plug's squeeze gauge (also any object wider than the drain
  that the current holds at the throat: `lodge_zone`, `lodge_max_speed`) fills at `pressure / resistance` per second,
  pressure = 1 … 1 + `max_pressure_bonus` as the water nears the overflow line. Full ⇒ "SQUEEEZE!": the plug ignores the drain layer,
  is squashed horizontally to the drain width and carried out. Gauge decays slowly between flushes. Current: tiers 1–7 one flush,
  tiers 8–9 two (all levels).
* **Merging:** `body_entered` from both bodies → `Game.try_merge` flags both and opens a `triple_window` (0.14 s); a third match that
  touches either (or already rests within `triple_pad`) joins → TRIPLE. Then merge at the mass-weighted centre with `momentum_kept`
  of the momentum; results grow from `grow_from` (no overlap explosion); a triple places its two results apart along the group's axis.
  Max tier never merges. Creating the max tier calls `start_royal_flush()`.
* **Earned flush / chain:** `Game.add_meter` (per_merge + tier_bonus·(t−2)) × chain_mult (+ triple_bonus); chain uses SIMULATION time.
* **Royal flush:** `Game.State.ROYAL`: launcher off, `Engine.time_scale = royal.slowmo` for `royal.delay` real seconds, then
  `water.start_flush(royal.duration)` and objects nearest the drain first get `start_passing(true)` (ignore objects + drain layer) every
  `royal.stagger` s; stragglers after `royal.timeout` are scored anyway. Overflow cannot end the game during it.
* **Level flow:** `Game.carry` (static) = {level, score} survives `reload_current_scene`. Tests set `reload_enabled = false`.
  Save file `user://best.json` = {best, seen{level: highest tier}}.
* **Throw:** speed = lerp(min, max, drag past dead zone / max_drag), direction opposite the drag; impulse = mass × v. Preview integrates
  `v += g·dt; p += v·dt` per physics tick (Godot's order) — test asserts < 6 px error in free flight.
* **Overflow:** level above `overflow_y` for `grace_time` (3 s) ⇒ game over; the timer recovers at 1.5× when below.
* **Scoring:** merge = `merge_base·2^(t−1)` × chain (×2 for a triple, small); flush = `flush_base·flush_mult^(t−1)`
  (10, 25, 62, 156, 390, 976, 2441, 6103, 15258), ×3 in the royal flush.

## 4d. Localisation (multi-language ready, same approach as RockRocketLaser)
* **Autoload `Loc`** (`game/core/loc.gd`): the English text is the key: `Loc.t("ROYAL FLUSH!")`. Table = `data/i18n/<code>.json`;
  a missing key or missing language shows the English text. **Android: the phone's system language when a file for it exists,
  else English. Desktop/editor: always English** (RockRocketLaser owner rule).
* **Rules for new text:** show player text ONLY through `Loc.t("...")` with a string literal; translate a FORMAT and fill it afterwards
  (`Loc.t("CHAIN x%d") % n`, `Loc.t("NEW: %s!") % Loc.t(name).to_upper()`); never glue translated pieces together. Level and object
  names live in `data/levels.json` and are shown via `Loc.t(name)`. After adding text run `python3 tools/i18n/extract_strings.py`
  and commit `data/i18n/en.json` (60 strings now). `test_localisation` fails on a missing key or on a raw literal at a display call
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
godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=1200 [--policy=danger] [--random]
xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots.tscn   # screenshots -> tools/dev/out
godot --path .                                   # play (mouse = touch). Keys: F/Space flush, R retry level, F1 collision debug;
                                                 # debug builds: 1-9 drop tier at mouse, C +1 flush charge, L next level
```
Windows (owner's PC, same as RockRocketLaser): `run_pc.bat` (git pull --ff-only, Godot 4.4.1 auto-download, forced re-import, run) and
`build_android.bat [--no-push]` (pull, import, export APK, adb install + launch). Both fetch, switch to GitHub's default branch
(`git remote set-head origin -a`) and fast-forward it. Run alone, either one clones the repo into `C:\temp\FlushRoyale`.
Keep .bat files CRLF (`.gitattributes`).
Re-run the bot probe after ANY tuning change. Android: `tools/ci/setup_godot.sh --templates && tools/ci/android_setup.sh && tools/ci/build_apk.sh`.

## 6. Assets (Layer)
* 7 generations total (17.95 CU: PoC 1 4.71, PoC 2 13.24), recorded in `assets/source/layer_jobs.json`: 3 backgrounds (each repainted
  from the geometry guide with `--theme` colours; kitchen/palace use the bathroom one as style reference), object sheets on magenta
  (bathroom 3×2 + 3×1 extra, kitchen 3×3, palace 3×3; later sheets use the first sheet as style reference). Owner budget rule: Claude
  may approve Layer spend itself up to 20 CU per task; estimate first. `build_assets.py` assigns blobs to grid cells by their centre. Model `gpt-image-2.5-flare`, medium, `batch_size` 1, always
  `estimate_forge_price` first with identical arguments (the RockRocketLaser lesson: batch/size are top-level args).
* Layer is **not** used for audio, water, particles, VFX or animation frames: all procedural in Godot.
* Pipeline: `python3 tools/asset_pipeline/build_assets.py` (needs pillow numpy scipy).

## 7. Conventions
GDScript with static typing where inference works (JSON values are Variant: annotate). Tuning goes in `data/`, never as code
constants. Keep it small: no premature abstractions, one script per system.

## 8. Known limitations / next
* Not tested on a real phone; touch is covered by synthetic events only. Perf on hardware unmeasured (headless ~2 ms/frame).
* Balance is bot-tuned; the bot either over-flushes or never flushes. Needs human playtests: level length (target 4-6 min), meter gain,
  Palace difficulty (heavy objects). Levels differ by objects (density/shape) only; `params` per level is the knob for more.
* Generated collision is convex parts of the sprite silhouette (no hand tweaks yet).
* Water surface for physics is flat (ripples/whirlpool dip are visual). Objects float in the outlet only by the same rules.
* Squeeze-through squash is visual (sprite in world x); collision keeps its shape while it ignores the drain walls.

## 9. Intentionally out of scope
Main menu, settings, achievements, ads, store, music, more than 9 tiers, soft bodies, real fluid simulation.
