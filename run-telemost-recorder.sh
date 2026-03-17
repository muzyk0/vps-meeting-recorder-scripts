#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

MEETING_URL="${1:-${MEETING_URL:-}}"
GUEST_NAME="${2:-${GUEST_NAME:-Recorder Bot}}"
SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/recordings}"
NO_JOIN="${NO_JOIN:-0}"
PREPARE_ONLY="${PREPARE_ONLY:-0}"
RECORD_ONLY="${RECORD_ONLY:-0}"
SKIP_RECORDING="${SKIP_RECORDING:-0}"
START_RECORDING_DELAY="${START_RECORDING_DELAY:-8}"
AUDIO_WARMUP_DURATION="${AUDIO_WARMUP_DURATION:-3}"
PULSE_SINK_NAME="${PULSE_SINK_NAME:-meeting_sink}"
AUDIO_WARMUP_SOURCE="${AUDIO_WARMUP_SOURCE:-${PULSE_SINK_NAME}.monitor}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

ensure_dir "$OUTPUT_DIR"
ensure_dir "$LOG_DIR"

RUN_LOG="$LOG_DIR/run-telemost-recorder.log"
append_log_header "$RUN_LOG" "$@"
exec >> >(tee -a "$RUN_LOG") 2>&1

OUTPUT_FILE="${OUTPUT_FILE:-$OUTPUT_DIR/${SESSION_NAME}-$(date +%F-%H%M%S).mp4}"
export SESSION_NAME OUTPUT_FILE

log "Step 1/3: preparing environment"
"$SCRIPT_DIR/prepare-env.sh"

if bool_is_true "$PREPARE_ONLY"; then
  log "PREPARE_ONLY=1, stopping after environment setup"
  exit 0
fi

if ! bool_is_true "$RECORD_ONLY"; then
  [ -n "$MEETING_URL" ] || fail "Usage: $0 <telemost-url> [guest-name]"
  log "Step 2/3: opening Telemost lobby"
  MEETING_URL="$MEETING_URL" GUEST_NAME="$GUEST_NAME" NO_JOIN="$NO_JOIN" \
    "$SCRIPT_DIR/join-telemost.sh" "$MEETING_URL" "$GUEST_NAME"
else
  log "RECORD_ONLY=1, skipping browser join"
fi

if bool_is_true "$SKIP_RECORDING"; then
  log "SKIP_RECORDING=1, skipping ffmpeg recording step"
  exit 0
fi

if [ "$START_RECORDING_DELAY" -gt 0 ]; then
  log "Waiting $START_RECORDING_DELAY seconds before recording"
  sleep "$START_RECORDING_DELAY"
fi

if [ "$AUDIO_WARMUP_DURATION" -gt 0 ]; then
  log "Warming up audio stream for $AUDIO_WARMUP_DURATION seconds from $AUDIO_WARMUP_SOURCE"
  ffmpeg -hide_banner -loglevel error -f pulse -i "$AUDIO_WARMUP_SOURCE" -t "$AUDIO_WARMUP_DURATION" -f null - >/dev/null 2>&1 || true
fi

log "Step 3/3: recording screen"
"$SCRIPT_DIR/record-screen.sh" "$OUTPUT_FILE"

cat <<EOF
Run completed.
  OUTPUT_FILE=$OUTPUT_FILE
  LOG_FILE=$RUN_LOG
  SESSION_NAME=$SESSION_NAME
EOF
