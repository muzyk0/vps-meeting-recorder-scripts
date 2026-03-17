#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
load_env_file

MEETING_URL="${1:-${MEETING_URL:-}}"
GUEST_NAME="${2:-${GUEST_NAME:-Recorder Bot}}"
DISPLAY="${DISPLAY:-:99}"
SESSION_NAME="${SESSION_NAME:-telemost-recorder}"
HEADED="${HEADED:-1}"
NO_JOIN="${NO_JOIN:-1}"
DRY_RUN="${DRY_RUN:-0}"
JOIN_WAIT_MS="${JOIN_WAIT_MS:-2000}"
PAGE_LOAD_WAIT_MS="${PAGE_LOAD_WAIT_MS:-6000}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$SCRIPT_DIR/artifacts/screenshots/$SESSION_NAME}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
BROWSER_TRACE_DIR="${BROWSER_TRACE_DIR:-$SCRIPT_DIR/artifacts/browser/$SESSION_NAME}"
SAVE_HTML_DUMP="${SAVE_HTML_DUMP:-1}"

[ -n "$MEETING_URL" ] || fail "Usage: $0 <telemost-url> [guest-name]"
require_cmd agent-browser
ensure_dir "$SCREENSHOT_DIR"
ensure_dir "$LOG_DIR"
ensure_dir "$BROWSER_TRACE_DIR"

JOIN_LOG="$LOG_DIR/join-telemost.log"
append_log_header "$JOIN_LOG" "$@"
exec >> >(tee -a "$JOIN_LOG") 2>&1

export DISPLAY
export AGENT_BROWSER_HEADED="$HEADED"
export AGENT_BROWSER_SESSION_NAME="$SESSION_NAME"

BROWSER_FLAGS=(--session-name "$SESSION_NAME")
SHOT_PREFIX="$SCREENSHOT_DIR/$(timestamp)"
SNAPSHOT_FILE="$SHOT_PREFIX-snapshot.txt"
HTML_FILE="$SHOT_PREFIX-page.html"
CONSOLE_FILE="$SHOT_PREFIX-console.txt"
ERRORS_FILE="$SHOT_PREFIX-errors.txt"

ab() {
  if bool_is_true "$DRY_RUN"; then
    log "[dry-run] agent-browser ${BROWSER_FLAGS[*]} $*"
    return 0
  fi
  agent-browser "${BROWSER_FLAGS[@]}" "$@"
}

save_debug_artifacts() {
  local label="$1"
  local file_prefix="$SHOT_PREFIX-$label"

  ab snapshot -i > "$file_prefix-snapshot.txt" || true
  ab screenshot "$file_prefix.png" >/dev/null || true
  ab console > "$file_prefix-console.txt" || true
  ab errors > "$file_prefix-errors.txt" || true
  if bool_is_true "$SAVE_HTML_DUMP"; then
    ab get html body > "$file_prefix-body.html" || true
  fi
}

snapshot_text() {
  ab snapshot -i 2>/dev/null || true
}

first_ref_for_pattern() {
  local snapshot="$1"
  local pattern="$2"
  printf '%s\n' "$snapshot" | sed -n "s/.*${pattern} \[ref=\([^]]*\)\].*/\1/p" | head -n1
}

click_if_present() {
  local snapshot="$1"
  local pattern="$2"
  local ref
  ref="$(first_ref_for_pattern "$snapshot" "$pattern")"
  if [ -n "$ref" ]; then
    log "Clicking ${pattern} via @$ref"
    ab click "@$ref" || true
    ab wait 700 || true
    return 0
  fi
  return 1
}

fill_guest_name() {
  local snapshot="$1"
  local ref
  ref="$(printf '%s\n' "$snapshot" | sed -n 's/.*textbox \[ref=\([^]]*\)\].*/\1/p' | head -n1)"
  if [ -n "$ref" ]; then
    log "Filling guest name: $GUEST_NAME"
    ab fill "@$ref" "$GUEST_NAME"
  else
    warn "Guest name textbox not found"
  fi
}

ensure_media_disabled() {
  local snapshot="$1"

  click_if_present "$snapshot" 'button "Выключить микрофон"' || true
  click_if_present "$snapshot" 'button "Выключить камеру"' || true

  snapshot="$(snapshot_text)"
  if printf '%s\n' "$snapshot" | grep -q 'button "Включить микрофон"'; then
    log "Microphone appears disabled"
  else
    warn "Could not confirm disabled microphone state"
  fi

  if printf '%s\n' "$snapshot" | grep -q 'button "Включить камеру"'; then
    log "Camera appears disabled"
  else
    warn "Could not confirm disabled camera state"
  fi
}

handle_permission_dialogs() {
  local snapshot="$1"
  local attempt

  for attempt in 1 2 3 4; do
    if ! printf '%s\n' "$snapshot" | grep -q 'Понятно'; then
      return 0
    fi
    log "Dismissing permission/info dialog (attempt $attempt)"
    click_if_present "$snapshot" 'button ".*Понятно"' || true
    snapshot="$(snapshot_text)"
  done
}

log "Opening Telemost URL: $MEETING_URL"
ab open "$MEETING_URL"
ab wait "$PAGE_LOAD_WAIT_MS" || true

SNAPSHOT="$(snapshot_text)"
handle_permission_dialogs "$SNAPSHOT"
SNAPSHOT="$(snapshot_text)"
fill_guest_name "$SNAPSHOT"
SNAPSHOT="$(snapshot_text)"
ensure_media_disabled "$SNAPSHOT"
SNAPSHOT="$(snapshot_text)"

JOIN_REF="$(first_ref_for_pattern "$SNAPSHOT" 'button "Подключиться"')"
[ -n "$JOIN_REF" ] || {
  save_debug_artifacts "join-button-missing"
  fail "Could not find Telemost 'Подключиться' button. See $SCREENSHOT_DIR and $JOIN_LOG"
}

save_debug_artifacts "before-join"

if bool_is_true "$NO_JOIN"; then
  log "NO_JOIN enabled; skipping final click"
  cat <<EOF
Telemost lobby is ready.
  MEETING_URL=$MEETING_URL
  GUEST_NAME=$GUEST_NAME
  SESSION_NAME=$SESSION_NAME
  DISPLAY=$DISPLAY
  JOIN_BUTTON=@$JOIN_REF
  SCREENSHOT_DIR=$SCREENSHOT_DIR
  LOG_FILE=$JOIN_LOG
EOF
  exit 0
fi

log "Joining meeting via @$JOIN_REF"
ab click "@$JOIN_REF"
ab wait "$JOIN_WAIT_MS" || true
save_debug_artifacts "after-join"

cat <<EOF
Joined Telemost meeting.
  MEETING_URL=$MEETING_URL
  GUEST_NAME=$GUEST_NAME
  SESSION_NAME=$SESSION_NAME
  DISPLAY=$DISPLAY
  SCREENSHOT_DIR=$SCREENSHOT_DIR
  LOG_FILE=$JOIN_LOG
EOF
