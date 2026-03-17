# VPS meeting recorder scripts

Simple bash-based tooling for recording browser meetings on a Linux VPS.

Current first-class target: **Yandex Telemost guest join flow**.

The project is intentionally small and shell-first:
- `prepare-env.sh` sets up Xvfb + PulseAudio null sink
- `join-telemost.sh` opens a Telemost link via `agent-browser`, fills guest name, tries to keep mic/camera off, and saves troubleshooting artifacts
- `record-screen.sh` records the virtual display and PulseAudio monitor with `ffmpeg`
- `run-telemost-recorder.sh` ties the flow together

It should also be straightforward to extend later with another `join-*.sh` script for VK or other meeting platforms.

## File layout

```text
.
├── .env.example
├── README.md
├── join-telemost.sh
├── lib/
│   └── common.sh
├── prepare-env.sh
├── record-screen.sh
├── record-telemost.sh        # compatibility shim -> record-screen.sh
├── run-telemost-recorder.sh
└── start-telemost-env.sh     # compatibility shim -> prepare-env.sh
```

Runtime-generated directories:
- `artifacts/` — screenshots, HTML dumps, browser debug outputs
- `logs/` — script logs
- `recordings/` — MP4 files

## Requirements

Expected tools on the VPS:
- `agent-browser`
- `ffmpeg`
- `Xvfb`
- `pulseaudio`
- `pactl`
- `xdpyinfo`

Example install on Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg xvfb pulseaudio x11-utils dbus-x11 chromium
```

`agent-browser` is expected to be already installed and available in `PATH`.

## Configuration

Copy `.env.example` to `.env` and adjust what matters:

```bash
cp .env.example .env
```

Most useful variables:
- `MEETING_URL` — Telemost meeting URL
- `GUEST_NAME` — guest display name
- `DISPLAY` — virtual X display, default `:99`
- `SESSION_NAME` — browser session name used by `agent-browser`
- `OUTPUT_DIR` — where recordings go
- `DURATION` — recording duration, empty means no `-t` limit
- `NO_JOIN=1` — stop in the lobby before clicking `Подключиться`
- `DRY_RUN=1` — print commands without changing anything, where supported
- `SCREENSHOT_DIR` — where join-flow screenshots/debug files go
- `HEADED=1` — keep browser headed for VPS screen capture

## Recommended usage

### 1) Prepare the environment

```bash
./prepare-env.sh
```

This starts or reuses:
- `Xvfb` on `DISPLAY`
- PulseAudio daemon
- a null sink like `meeting_sink`

### 2) Inspect Telemost lobby without joining

Safe debugging mode:

```bash
NO_JOIN=1 ./join-telemost.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Artifacts are saved under `artifacts/screenshots/<session-name>/` by default.

### 3) Join and keep the browser ready for recording

```bash
NO_JOIN=0 ./join-telemost.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

The script tries to:
- fill the guest name
- dismiss `Понятно` dialogs
- keep microphone disabled
- keep camera disabled
- save before/after screenshots and debug dumps

### 4) Record the virtual screen

```bash
DURATION=01:00:00 ./record-screen.sh ./recordings/telemost-demo.mp4
```

Unlimited recording:

```bash
DURATION= ./record-screen.sh ./recordings/telemost-live.mp4
```

### 5) One-shot wrapper

This is the main script for real usage. By default it now does:

- prepare environment
- join meeting
- wait briefly for playback to settle
- warm up the Pulse monitor
- start recording

Safe smoke mode without joining and without recording:

```bash
NO_JOIN=1 SKIP_RECORDING=1 ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Real join + recording:

```bash
DURATION=00:45:00 ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

For Telemost, keeping the default warmup is recommended. If audio starts too early or too late on your host, tune these:

```bash
START_RECORDING_DELAY=10 AUDIO_WARMUP_DURATION=3 \
  ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

If needed, you can still override behavior explicitly:

```bash
NO_JOIN=0 DURATION=00:45:00 ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

## Debugging modes

### Dry run

```bash
DRY_RUN=1 ./prepare-env.sh
DRY_RUN=1 ./record-screen.sh ./recordings/test.mp4
```

For `join-telemost.sh`, `DRY_RUN=1` prints `agent-browser` commands, but real UI validation obviously requires normal mode.

### No-join lobby mode

```bash
NO_JOIN=1 ./join-telemost.sh "$MEETING_URL" "$GUEST_NAME"
```

This is the main safe mode for checking Telemost selectors after UI changes.

### Logs and artifacts

- `logs/prepare-env.log`
- `logs/join-telemost.log`
- `logs/record-screen.log`
- `logs/run-telemost-recorder.log`
- `artifacts/screenshots/.../*.png`
- `artifacts/screenshots/.../*-snapshot.txt`
- `artifacts/screenshots/.../*-console.txt`
- `artifacts/screenshots/.../*-errors.txt`
- optional HTML dumps when `SAVE_HTML_DUMP=1`

## Extension path

To support another platform later, keep the same pattern:
- `prepare-env.sh` remains shared
- add `join-vk.sh` or `join-zoom.sh`
- reuse `record-screen.sh`
- add a small wrapper like `run-vk-recorder.sh` if needed

## Notes and caveats

- Telemost UI text and button labels can change. If join starts failing, first run `NO_JOIN=1` and inspect the saved snapshot and screenshot files.
- The current guest flow was inspected against a real Telemost lobby and matched these labels: `Подключиться`, `Включить микрофон`, `Включить камеру`, and `Понятно` dialogs after denied media access.
- On a VPS, microphone/camera are usually unavailable. That is actually helpful here: Telemost exposes disabled-state prompts that the script dismisses, and the lobby still allows guest entry.
- Recording system audio on a VPS depends on how audio reaches PulseAudio. This repo prepares the sink and records its monitor, but you may still need browser/audio routing tweaks depending on the host image.
 sink and records its monitor, but you may still need browser/audio routing tweaks depending on the host image.
