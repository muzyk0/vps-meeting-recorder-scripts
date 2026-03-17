#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.state}"
STOP_LOG="$LOG_DIR/stop-telemost-recording.log"
RUNNER_PID_FILE="$STATE_DIR/${SESSION_NAME}.runner.pid"
FFMPEG_PID_FILE="$STATE_DIR/${SESSION_NAME}.ffmpeg.pid"
LAST_OUTPUT_FILE="$STATE_DIR/${SESSION_NAME}.last-output"
WAIT_SECONDS="${WAIT_SECONDS:-15}"

ensure_dir "$LOG_DIR"
ensure_dir "$STATE_DIR"
append_log_header "$STOP_LOG" "$@"
exec >> >(tee -a "$STOP_LOG") 2>&1

LAST_OUTPUT=""
if [ -f "$LAST_OUTPUT_FILE" ]; then
  LAST_OUTPUT="$(cat "$LAST_OUTPUT_FILE")"
fi

stop_runner_if_active() {
  local pid=""
  if [ -f "$RUNNER_PID_FILE" ]; then
    pid="$(cat "$RUNNER_PID_FILE" 2>/dev/null || true)"
  fi

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "Stopping runner shell (pid=$pid)"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      warn "runner still alive, sending SIGKILL"
      kill -KILL "$pid" 2>/dev/null || true
    fi
  else
    log "No live runner pid file found"
  fi

  rm -f "$RUNNER_PID_FILE"
}

stop_ffmpeg_gracefully() {
  local pid=""
  if [ -f "$FFMPEG_PID_FILE" ]; then
    pid="$(cat "$FFMPEG_PID_FILE" 2>/dev/null || true)"
  fi

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "Stopping ffmpeg gracefully via SIGINT (pid=$pid)"
    kill -INT "$pid" 2>/dev/null || true

    local i
    for i in $(seq 1 "$WAIT_SECONDS"); do
      if ! kill -0 "$pid" 2>/dev/null; then
        log "ffmpeg exited after graceful stop"
        rm -f "$FFMPEG_PID_FILE"
        return 0
      fi
      sleep 1
    done

    warn "ffmpeg did not exit within ${WAIT_SECONDS}s, sending SIGTERM"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
      warn "ffmpeg still alive, sending SIGKILL"
      kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$FFMPEG_PID_FILE"
    return 0
  fi

  log "No live ffmpeg pid file found; falling back to process search"
  if pgrep -af 'ffmpeg.*x11grab.*pulse' >/dev/null 2>&1; then
    pkill -INT -f 'ffmpeg.*x11grab.*pulse' || true
    sleep 2
  fi
}

stop_browser_tail() {
  log "Stopping Telemost browser tail"
  pkill -f 'agent-browser-linux-x64' || true
  sleep 1
  pkill -f '/tmp/agent-browser-chrome-' || true
  sleep 1
}

stop_runner_if_active
stop_ffmpeg_gracefully
stop_browser_tail

cat <<EOF
Stop completed.
  SESSION_NAME=$SESSION_NAME
  LAST_OUTPUT_FILE=${LAST_OUTPUT:-unknown}
  STOP_LOG=$STOP_LOG
EOF
