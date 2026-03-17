#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

timestamp() {
  date +"%Y-%m-%dT%H-%M-%S"
}

log() {
  printf '[%s] %s\n' "$(date +"%F %T")" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date +"%F %T")" "$*" >&2
}

fail() {
  printf '[%s] ERROR: %s\n' "$(date +"%F %T")" "$*" >&2
  exit 1
}

bool_is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
  done
}

ensure_dir() {
  mkdir -p "$1"
}

expand_path() {
  local path="${1:-}"
  case "$path" in
    ~) printf '%s\n' "$HOME" ;;
    ~/*) printf '%s\n' "$HOME/${path#~/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

run_cmd() {
  if bool_is_true "${DRY_RUN:-0}"; then
    log "[dry-run] $*"
    return 0
  fi
  log "+ $*"
  "$@"
}

append_log_header() {
  local file="$1"
  ensure_dir "$(dirname "$file")"
  {
    echo "==== $(date +"%F %T") ===="
    echo "PWD=$PWD"
    echo "CMD=$0 $*"
  } >> "$file"
}

load_env_file() {
  local env_file="${ENV_FILE:-$PROJECT_ROOT/.env}"
  if [ -f "$env_file" ]; then
    # shellcheck disable=SC1090
    set -a; source "$env_file"; set +a
  fi
}
