#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-$USER}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start virtual X server if not running
if ! pgrep -f "Xvfb $DISPLAY" >/dev/null 2>&1; then
  nohup Xvfb "$DISPLAY" -screen 0 1280x720x24 -ac +extension RANDR >/tmp/xvfb.log 2>&1 &
  sleep 2
fi

# Start PulseAudio if not running
if ! pulseaudio --check >/dev/null 2>&1; then
  pulseaudio --start --exit-idle-time=-1 >/tmp/pulseaudio.log 2>&1 || true
  sleep 2
fi

# Ensure a virtual sink exists
if ! pactl list short sinks 2>/dev/null | grep -q '^.*telemost_sink'; then
  pactl load-module module-null-sink sink_name=telemost_sink sink_properties=device.description=TelemostSink >/tmp/pactl_sink.log 2>&1 || true
  sleep 1
fi

# Ensure a loopback from sink monitor to output path exists (helps some apps)
if ! pactl list short modules 2>/dev/null | grep -q 'module-loopback.*telemost_sink.monitor'; then
  pactl load-module module-loopback source=telemost_sink.monitor >/tmp/pactl_loopback.log 2>&1 || true
fi

echo "DISPLAY=$DISPLAY"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "Virtual sink: telemost_sink"
echo "Open Chromium with:"
echo "DISPLAY=$DISPLAY chromium --no-sandbox --disable-gpu --autoplay-policy=no-user-gesture-required --start-maximized https://telemost.yandex.ru/"
