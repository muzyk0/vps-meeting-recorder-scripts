#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

DISPLAY="${DISPLAY:-:99}"
SCREEN_SIZE="${SCREEN_SIZE:-1280x720x24}"
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1280x720}"
XVFB_ARGS="${XVFB_ARGS:--ac +extension RANDR +render -noreset}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-$USER}"
PULSE_SINK_NAME="${PULSE_SINK_NAME:-meeting_sink}"
PULSE_SINK_DESCRIPTION="${PULSE_SINK_DESCRIPTION:-MeetingRecorderSink}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$SCRIPT_DIR/artifacts}"
SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
FORCE_RESTART_AUDIO="${FORCE_RESTART_AUDIO:-0}"
FORCE_RESTART_XVFB="${FORCE_RESTART_XVFB:-0}"
DRY_RUN="${DRY_RUN:-0}"

require_cmd Xvfb pulseaudio pactl xdpyinfo
ensure_dir "$LOG_DIR"
ensure_dir "$ARTIFACTS_DIR"
ensure_dir "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

XVFB_LOG="$LOG_DIR/xvfb.log"
PULSE_LOG="$LOG_DIR/pulseaudio.log"
PREPARE_LOG="$LOG_DIR/prepare-env.log"
append_log_header "$PREPARE_LOG" "$@"
exec >> >(tee -a "$PREPARE_LOG") 2>&1

xvfb_running() {
  pgrep -af "Xvfb $DISPLAY" >/dev/null 2>&1
}

start_xvfb() {
  if xvfb_running; then
    log "Xvfb already running on $DISPLAY"
    return 0
  fi

  log "Starting Xvfb on $DISPLAY with screen $SCREEN_SIZE"
  if bool_is_true "$DRY_RUN"; then
    log "[dry-run] Xvfb $DISPLAY -screen 0 $SCREEN_SIZE $XVFB_ARGS"
    return 0
  fi

  nohup Xvfb "$DISPLAY" -screen 0 "$SCREEN_SIZE" $XVFB_ARGS >> "$XVFB_LOG" 2>&1 &
  sleep 2
  DISPLAY="$DISPLAY" xdpyinfo >/dev/null 2>&1 || fail "Xvfb did not become ready on $DISPLAY"
}

restart_xvfb_if_needed() {
  if bool_is_true "$FORCE_RESTART_XVFB" && xvfb_running; then
    warn "FORCE_RESTART_XVFB=1: stopping existing Xvfb on $DISPLAY"
    if ! bool_is_true "$DRY_RUN"; then
      pkill -f "Xvfb $DISPLAY" || true
      sleep 1
    fi
  fi
  start_xvfb
}

start_pulseaudio() {
  if pulseaudio --check >/dev/null 2>&1; then
    log "PulseAudio already running"
    return 0
  fi

  log "Starting PulseAudio"
  if bool_is_true "$DRY_RUN"; then
    log "[dry-run] pulseaudio --start --exit-idle-time=-1"
    return 0
  fi

  pulseaudio --start --exit-idle-time=-1 >> "$PULSE_LOG" 2>&1 || true
  sleep 2
  pulseaudio --check >/dev/null 2>&1 || fail "PulseAudio did not become ready"
}

restart_pulseaudio_if_needed() {
  if bool_is_true "$FORCE_RESTART_AUDIO"; then
    warn "FORCE_RESTART_AUDIO=1: killing existing PulseAudio"
    if ! bool_is_true "$DRY_RUN"; then
      pulseaudio --kill >/dev/null 2>&1 || true
      sleep 1
    fi
  fi
  start_pulseaudio
}

ensure_sink() {
  if pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -Fx "$PULSE_SINK_NAME" >/dev/null 2>&1; then
    log "Pulse sink already exists: $PULSE_SINK_NAME"
    return 0
  fi

  log "Creating null sink: $PULSE_SINK_NAME"
  if bool_is_true "$DRY_RUN"; then
    log "[dry-run] pactl load-module module-null-sink sink_name=$PULSE_SINK_NAME sink_properties=device.description=$PULSE_SINK_DESCRIPTION"
    return 0
  fi

  pactl load-module module-null-sink \
    sink_name="$PULSE_SINK_NAME" \
    sink_properties="device.description=$PULSE_SINK_DESCRIPTION" >/dev/null
}

set_default_audio_routes() {
  local current_default_sink current_default_source
  current_default_sink="$(pactl info | sed -n 's/^Default Sink: //p' | head -n1)"
  current_default_source="$(pactl info | sed -n 's/^Default Source: //p' | head -n1)"

  if [ "$current_default_sink" != "$PULSE_SINK_NAME" ]; then
    log "Setting default Pulse sink to $PULSE_SINK_NAME"
    if ! bool_is_true "$DRY_RUN"; then
      pactl set-default-sink "$PULSE_SINK_NAME"
    fi
  fi

  if [ "$current_default_source" != "${PULSE_SINK_NAME}.monitor" ]; then
    log "Setting default Pulse source to ${PULSE_SINK_NAME}.monitor"
    if ! bool_is_true "$DRY_RUN"; then
      pactl set-default-source "${PULSE_SINK_NAME}.monitor"
    fi
  fi
}

print_summary() {
  cat <<EOF
Environment ready.
  DISPLAY=$DISPLAY
  SCREEN_GEOMETRY=$SCREEN_GEOMETRY
  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
  PULSE_SINK_NAME=$PULSE_SINK_NAME
  PULSE_MONITOR=${PULSE_SINK_NAME}.monitor
  SESSION_NAME=$SESSION_NAME
  LOG_DIR=$LOG_DIR
  ARTIFACTS_DIR=$ARTIFACTS_DIR
EOF
}

restart_xvfb_if_needed
restart_pulseaudio_if_needed
ensure_sink
set_default_audio_routes
print_summary
