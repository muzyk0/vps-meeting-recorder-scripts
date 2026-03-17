#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
OUT="${1:-$HOME/telemost-$(date +%F-%H%M%S).mp4}"
DURATION="${DURATION:-03:05:00}"
SIZE="${SIZE:-1280x720}"
FPS="${FPS:-25}"
VIDEO_BITRATE="${VIDEO_BITRATE:-1800k}"
MAXRATE="${MAXRATE:-2500k}"
BUFSIZE="${BUFSIZE:-5000k}"
AUDIO_SRC="${AUDIO_SRC:-telemost_sink.monitor}"

CMD=(ffmpeg -y \
  -thread_queue_size 1024 \
  -f x11grab -draw_mouse 1 -video_size "$SIZE" -framerate "$FPS" -i "$DISPLAY.0" \
  -thread_queue_size 1024 \
  -f pulse -i "$AUDIO_SRC")

if [ -n "$DURATION" ]; then
  CMD+=( -t "$DURATION" )
fi

CMD+=( \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  -b:v "$VIDEO_BITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
  -g 50 \
  -c:a aac -b:a 128k -ac 2 -ar 44100 \
  -movflags +faststart \
  "$OUT" )

"${CMD[@]}"

echo "Saved to: $OUT"
