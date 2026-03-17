#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

MEETING_URL="${1:-${MEETING_URL:-}}"
GUEST_NAME="${2:-${GUEST_NAME:-Гость}}"
SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
OUTPUT_DIR_RAW="${OUTPUT_DIR:-$HOME/Movies/Records}"
OUTPUT_DIR="$(expand_path "$OUTPUT_DIR_RAW")"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.state}"
RUN_LOG="$LOG_DIR/run-telemost-recorder.log"
LAUNCH_LOG="$LOG_DIR/start-telemost-recording.log"
RUNNER_PID_FILE="$STATE_DIR/${SESSION_NAME}.runner.pid"
LAST_OUTPUT_FILE="$STATE_DIR/${SESSION_NAME}.last-output"

[ -n "$MEETING_URL" ] || fail "Usage: $0 <telemost-url> [guest-name]"
ensure_dir "$OUTPUT_DIR"
ensure_dir "$LOG_DIR"
ensure_dir "$STATE_DIR"
append_log_header "$LAUNCH_LOG" "$@"
exec >> >(tee -a "$LAUNCH_LOG") 2>&1

if [ -f "$RUNNER_PID_FILE" ]; then
  existing_pid="$(cat "$RUNNER_PID_FILE" 2>/dev/null || true)"
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    fail "Recording runner is already active (pid=$existing_pid)"
  fi
  rm -f "$RUNNER_PID_FILE"
fi

OUTPUT_FILE="${OUTPUT_FILE:-$OUTPUT_DIR/${SESSION_NAME}-$(date +%F-%H%M%S).mp4}"
printf '%s\n' "$OUTPUT_FILE" > "$LAST_OUTPUT_FILE"

log "Starting Telemost recorder in detached mode"
log "Meeting URL: $MEETING_URL"
log "Guest name: $GUEST_NAME"
log "Output file: $OUTPUT_FILE"

nohup env \
  SESSION_NAME="$SESSION_NAME" \
  OUTPUT_DIR="$OUTPUT_DIR" \
  OUTPUT_FILE="$OUTPUT_FILE" \
  STATE_DIR="$STATE_DIR" \
  LOG_DIR="$LOG_DIR" \
  DURATION="${DURATION:-}" \
  "$SCRIPT_DIR/run-telemost-recorder.sh" "$MEETING_URL" "$GUEST_NAME" \
  > /dev/null 2>&1 < /dev/null &

RUNNER_PID=$!
printf '%s\n' "$RUNNER_PID" > "$RUNNER_PID_FILE"
sleep 1
if ! kill -0 "$RUNNER_PID" 2>/dev/null; then
  warn "Detached runner exited immediately; inspect $RUN_LOG"
fi

cat <<EOF
Detached launch started.
  SESSION_NAME=$SESSION_NAME
  RUNNER_PID=$RUNNER_PID
  OUTPUT_FILE=$OUTPUT_FILE
  RUN_LOG=$RUN_LOG
  LAUNCH_LOG=$LAUNCH_LOG
EOF
