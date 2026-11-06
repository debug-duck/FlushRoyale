#!/usr/bin/env bash
# Layer/Sonilo audio (assets/source/audio, wav or m4a) -> assets/audio/<name>.ogg, loudness-normalised, silence trimmed.
#   tools/asset_pipeline/build_audio.sh        (needs ffmpeg)
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p assets/audio
for f in assets/source/audio/*; do
  name="$(basename "${f%.*}")"
  ext="${f##*.}"
  [ "$ext" = "wav" ] || [ "$ext" = "m4a" ] || continue
  # loops keep their full length (no trim); everything else: trim leading/trailing silence
  if [ "$name" = "water_rising" ]; then filt="loudnorm=I=-20:TP=-2"; else
    filt="silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse,loudnorm=I=-16:TP=-1.5"; fi
  ffmpeg -loglevel error -y -i "$f" -af "$filt" -ar 44100 -ac 1 -c:a libvorbis -q:a 4 "assets/audio/$name.ogg"
  printf '%-16s %s s\n' "$name" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "assets/audio/$name.ogg")"
done
