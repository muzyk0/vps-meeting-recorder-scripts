#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

DISPLAY="${DISPLAY:-:99}"
SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/recordings}"
OUTPUT_FILE="${1:-${OUTPUT_FILE:-$OUTPUT_DIR/${SESSION_NAME}-$(date +%F-%H%M%S).mp4}}"
DURATION="${DURATION:-00:30:00}"
SIZE="${SIZE:-1280x720}"
FPS="${FPS:-25}"
VIDEO_CODEC="${VIDEO_CODEC:-libx264}"
VIDEO_PRESET="${VIDEO_PRESET:-veryfast}"
VIDEO_BITRATE="${VIDEO_BITRATE:-2500k}"
MAXRATE="${MAXRATE:-3000k}"
BUFSIZE="${BUFSIZE:-6000k}"
AUDIO_CODEC="${AUDIO_CODEC:-aac}"
AUDIO_BITRATE="${AUDIO_BITRATE:-128k}"
AUDIO_CHANNELS="${AUDIO_CHANNELS:-2}"
AUDIO_RATE="${AUDIO_RATE:-44100}"
PULSE_SINK_NAME="${PULSE_SINK_NAME:-meeting_sink}"
AUDIO_SOURCE="${AUDIO_SOURCE:-${PULSE_SINK_NAME}.monitor}"
FFMPEG_LOGLEVEL="${FFMPEG_LOGLEVEL:-warning}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
DRY_RUN="${DRY_RUN:-0}"

require_cmd ffmpeg
ensure_dir "$OUTPUT_DIR"
ensure_dir "$LOG_DIR"

RECORD_LOG="$LOG_DIR/record-screen.log"
append_log_header "$RECORD_LOG" "$@"
exec >> >(tee -a "$RECORD_LOG") 2>&1

CMD=(ffmpeg -y -loglevel "$FFMPEG_LOGLEVEL"
  -thread_queue_size 1024
  -f x11grab -draw_mouse 0 -video_size "$SIZE" -framerate "$FPS" -i "$DISPLAY.0"
  -thread_queue_size 1024
  -f pulse -i "$AUDIO_SOURCE")

if [ -n "$DURATION" ]; then
  CMD+=( -t "$DURATION" )
fi

CMD+=(
  -c:v "$VIDEO_CODEC" -preset "$VIDEO_PRESET" -pix_fmt yuv420p
  -b:v "$VIDEO_BITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE"
  -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" -ac "$AUDIO_CHANNELS" -ar "$AUDIO_RATE"
  -movflags +faststart
  "$OUTPUT_FILE"
)

if bool_is_true "$DRY_RUN"; then
  log "[dry-run] ${CMD[*]}"
  exit 0
fi

log "Recording display $DISPLAY to $OUTPUT_FILE"
"${CMD[@]}"
log "Recording saved to $OUTPUT_FILE"
