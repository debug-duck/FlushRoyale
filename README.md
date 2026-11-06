# 🚽 FLUSH ROYALE — Wrong Button Games gameplay PoC (Godot 4.4)

Throw ridiculous bathroom objects into a giant toilet, merge identical ones into bigger ones, and flush them for points
before the toilet clogs and overflows.

Three levels, nine objects each. Make the ninth and the whole bowl goes down in a **ROYAL FLUSH**:
* **The Bathroom:** Rubber Duck → Toilet Paper → Shampoo → Plunger → Old Boot → Bathroom Scale → Washing Machine → Bathtub → **Golden Toilet**
* **The Kitchen:** Cherry Tomato → Fried Egg → Banana → Frying Pan → Teapot → Roast Chicken → Microwave → Fridge → **Royal Cake**
* **The Royal Palace:** Gold Coin → Diamond Ring → Goblet → Scepter → Crown → Knight Helmet → Treasure Chest → Suit of Armour → **Royal Throne**

## How to play
* **Aim & throw:** touch/click near the object above the bowl, drag *back*, release. Longer drag = harder throw; the dotted line
  shows the flight. A tiny drag cancels.
* **Merge:** two identical objects merge on contact into the next one (small points). Merges in quick succession build a
  **CHAIN** (more points, faster flush meter). **TRIPLE MERGE:** three identical objects at once become TWO of the next one.
* **Discover:** the strip at the top shows the level's nine objects; unknown ones are silhouettes until you create them.
* **FLUSH (earned):** merges fill the ring around the FLUSH button; a full ring is one flush charge (up to 3). The whirlpool pulls
  submerged objects down the drain; flushed objects score big (tier 1 = 10 … tier 9 = 15258).
* **ROYAL FLUSH:** create the level's ninth object: everything in the bowl is flushed at ×3, then the next level starts.
* **Clogs:** objects too wide for the drain get stuck and seal it. A blocked flush makes the water *rise*, but also builds pressure
  on the plug (ring gauge); enough pressure squeezes it through. Knock it loose with a throw, merge it, or risk another flush.
* **Game over:** water above the red dashed line for 3 seconds (RETRY LEVEL restarts the level).

Flush small stuff now for safe points, or keep merging for a much bigger flush and risk the flood?

## Run it on Windows
* **`run_pc.bat`**: pulls the latest version from GitHub (always the repository's default branch), downloads Godot 4.4.1 once (into `build\godot`), re-imports the
  assets and starts the game.
* **`build_android.bat`**: pulls, re-imports, builds `build\flush-royale-debug.apk` and installs + launches it on a phone
  connected over USB (`--no-push` = build only). Needs the Android SDK and JDK 17+ (same as RockRocketLaser).
* Either file also works on its own: run it from anywhere and it clones the project into `C:\temp\FlushRoyale` first (needs Git).

## Run it on Linux
```bash
tools/ci/setup_godot.sh             # pinned Godot 4.4.1 (Linux) -> /opt/godot
godot --path . --import
godot --path .                      # mouse works like touch
```
Keys: `F`/`Space` flush · `R` retry level · `F1` collision debug · debug builds: `1`-`9` drop an object at the mouse,
`C` +1 flush charge, `L` next level.
Android: CI builds a debug APK (artifact `flush-royale-debug-apk`).

## Tests
```bash
godot --headless --path . --fixed-fps 60 tests/run_tests.tscn     # 459 checks
godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=1200 --policy=danger
```
All tuning lives in `data/config.json`, `data/levels.json`, `data/bowl.json`. Architecture and tuning notes: [`CLAUDE.md`](CLAUDE.md).
Art: seven [Layer](https://layer.ai) generations (provenance in `assets/source/layer_jobs.json`); sound, water and effects are procedural.
