# 🚽 FLUSH ROYALE — Wrong Button Games gameplay PoC (Godot 4.4)

Throw ridiculous bathroom objects into a giant toilet, merge identical ones into bigger ones, and flush them for points
before the toilet clogs and overflows.

**Rubber Duck → Toilet Paper → Shampoo → Plunger → Old Boot → Golden Toilet**

## How to play
* **Aim & throw:** touch/click near the object above the bowl, drag *back*, release. Longer drag = harder throw; the dotted line
  shows the flight. A tiny drag cancels.
* **Merge:** two identical objects merge on contact into the next one (small points).
* **FLUSH:** the whirlpool pulls submerged objects down the drain. Flushed objects score big: 10 / 30 / 90 / 270 / 810 / 2430.
  The tank needs a few seconds to refill.
* **Clogs:** objects too wide for the drain get stuck and seal it. A blocked flush makes the water *rise*, but also builds pressure
  on the plug (ring gauge); enough pressure squeezes it through. Knock it loose with a throw, merge it, or risk another flush.
* **Game over:** water above the red dashed line for 3 seconds.

Flush small stuff now for safe points, or keep merging for a much bigger flush and risk the flood?

## Run it
```bash
tools/ci/setup_godot.sh             # pinned Godot 4.4.1 (Linux) -> /opt/godot
godot --path . --import
godot --path .                      # mouse works like touch
```
Keys: `F`/`Space` flush · `R` restart · `F1` collision debug · `1`-`6` drop an object at the mouse (debug builds).
Android: CI builds a debug APK (artifact `flush-royale-debug-apk`).

## Tests
```bash
godot --headless --path . --fixed-fps 60 tests/run_tests.tscn     # acceptance criteria (230 checks)
godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=600
```
All tuning lives in `data/config.json`, `data/objects.json`, `data/bowl.json`. Architecture and tuning notes: [`CLAUDE.md`](CLAUDE.md).
Art: two [Layer](https://layer.ai) generations (provenance in `assets/source/layer_jobs.json`); sound, water and effects are procedural.
