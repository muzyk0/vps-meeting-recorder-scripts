#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

DISPLAY="${DISPLAY:-:99}"
SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
OUTPUT_DIR_RAW="${OUTPUT_DIR:-$HOME/Movies/Records}"
OUTPUT_DIR="$(expand_path "$OUTPUT_DIR_RAW")"
OUTPUT_FILE="${1:-${OUTPUT_FILE:-$OUTPUT_DIR/${SESSION_NAME}-$(date +%F-%H%M%S).mp4}}"
DURATION="${DURATION:-03:30:00}"
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
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.state}"
DRY_RUN="${DRY_RUN:-0}"

require_cmd ffmpeg
ensure_dir "$OUTPUT_DIR"
ensure_dir "$LOG_DIR"
ensure_dir "$STATE_DIR"

RECORD_LOG="$LOG_DIR/record-screen.log"
FFMPEG_PID_FILE="$STATE_DIR/${SESSION_NAME}.ffmpeg.pid"
LAST_OUTPUT_FILE="$STATE_DIR/${SESSION_NAME}.last-output"
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

cleanup_pid_file() {
  rm -f "$FFMPEG_PID_FILE"
}

printf '%s\n' "$OUTPUT_FILE" > "$LAST_OUTPUT_FILE"

log "Recording display $DISPLAY to $OUTPUT_FILE"
"${CMD[@]}" &
FFMPEG_PID=$!
printf '%s\n' "$FFMPEG_PID" > "$FFMPEG_PID_FILE"
trap 'log "Received stop signal, forwarding SIGINT to ffmpeg ($FFMPEG_PID)"; kill -INT "$FFMPEG_PID" 2>/dev/null || true' INT TERM
wait "$FFMPEG_PID"
STATUS=$?
cleanup_pid_file
trap - INT TERM

if [ "$STATUS" -eq 0 ]; then
  log "Recording saved to $OUTPUT_FILE"
else
  warn "ffmpeg exited with status $STATUS"
fi

exit "$STATUS"
