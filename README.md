# 🚽 FLUSH ROYALE — Wrong Button Studio gameplay PoC (Godot 4.4)

Throw ridiculous bathroom objects into a giant toilet, merge identical ones into bigger ones, and flush them for points
before the toilet clogs and overflows.

Three ridiculous locations, nine objects each - what the hell comes after a radioactive sock? Make the ninth and press
**ROYAL FLUSH**:
* **The Dormitory** - *Higher Education, Lower Standards:* Party Cup → Moldy Pizza → Radioactive Sock → Unopened Textbook →
  Emotional Support Plushie → Laptop with 73 Tabs → Filthy Couch → Student Debt Monster → **Entire University**
* **The White House** - *Make America Flush Again!:* Presidential Pen → Presidential Phone → Classified Documents → Ballot Box →
  Presidential Megaphone → Nuclear Football → Bald Eagle → Statue of Liberty → **The White House**
* **The Royal Palace** - *The Ultimate Royal Flush:* Silver Spoon → Royal Teapot → Tiny Crown → Royal Frog → Palace Guard →
  Golden Throne → Royal Horse → Royal Castle → **The King**

## How to play
* **Aim & throw:** touch/click near the object above the bowl, drag *back*, release. Longer drag = harder throw; the dotted line
  shows the flight. A tiny drag cancels.
* **Merge:** two identical objects merge on contact into the next one (small points). Merges in quick succession build a
  **CHAIN** (more points, faster flush meter). **TRIPLE MERGE:** three identical objects at once become TWO of the next one.
* **Discover:** the strip at the top shows the level's nine objects; unknown ones are silhouettes until you create them.
* **Rising water:** heavy things sink into the drain. When it clogs, the water RISES - slowly for a partial clog, faster for a
  bad one; clear the drain and the water gulps away. Water over the red dashed line for 3 seconds = **FLOODED**.
* **Clear the clog:** merge onto it, knock it loose with a precise throw, or...
* **EMERGENCY FLUSH (earned):** merges fill the ring around the FLUSH button; a full ring = one charge (up to 3). The whirlpool drains
  a lot of water and shakes everything up, but whatever goes down is **LOST** (no points). Big objects survive one flush - panic
  flushing again and again will sacrifice them (each sacrifice drains extra water).
* **ROYAL FLUSH:** create the location's ninth object: the water stops, the cascade finishes, the button turns gold - press it and
  everything goes down at ×3 points. Then the next location.

Keep merging, try the trick shot, or sacrifice your precious objects to survive?

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
**DEV MODE:** tap the logo on the title screen 5 times; a DEV button appears in the game (god mode, level jumps, choose/drop
objects, royal flush now, water controls, stats). Keys: `F`/`Space` flush · `R` retry level · `F1` collision debug · debug builds: `1`-`9` drop an object at the mouse,
`C` +1 flush charge, `L` next level.
Android: CI builds a debug APK (artifact `flush-royale-debug-apk`).

## Languages
The game is multi-language ready; it ships in English only for now. All player-visible text is in `data/i18n/en.json`
(the English text is the key). To add a language: run `python3 tools/i18n/extract_strings.py`, copy `en.json` to e.g.
`pl.json` and translate the values (keep `%d` / `%s` / `%.1f`). On Android the game picks the phone's language when a file
exists, otherwise English; on PC it is always English. Details: `CLAUDE.md` §4d.

## Tests
```bash
godot --headless --path . --fixed-fps 60 tests/run_tests.tscn     # ~640 checks
godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=1200 --policy=conservative
```
All tuning lives in `data/config.json`, `data/levels.json`, `data/bowl.json`. Architecture and tuning notes: [`CLAUDE.md`](CLAUDE.md).
Art: [Layer](https://layer.ai) image generations; the bigger sounds (flush, drain, cascade stings, fanfare) are Sonilo clips via Layer;
small sounds, water and effects are procedural. Provenance: `assets/source/layer_jobs.json`.
