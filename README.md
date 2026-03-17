# VPS Meeting Recorder Scripts

Small helper scripts for recording browser-based meetings/webinars on a Linux VPS with:

- `Xvfb`
- `PulseAudio`
- `Chromium`
- `ffmpeg`

## Files

- `start-telemost-env.sh` — prepares virtual display and virtual audio sink
- `record-telemost.sh` — records the current X display plus PulseAudio monitor into MP4

## Requirements

Install packages first:

```bash
sudo apt-get update && sudo apt-get install -y ffmpeg chromium xvfb pulseaudio x11-utils dbus-x11
```

## Usage

Prepare environment:

```bash
./start-telemost-env.sh
```

Open browser on virtual display:

```bash
DISPLAY=:99 PULSE_SINK=telemost_sink chromium --no-sandbox --disable-gpu --autoplay-policy=no-user-gesture-required --start-maximized 'https://telemost.yandex.ru/'
```

Record for a fixed duration:

```bash
export DISPLAY=:99
export DURATION=03:05:00
./record-telemost.sh ~/meeting.mp4
```

Record without duration limit:

```bash
export DISPLAY=:99
export DURATION=
./record-telemost.sh ~/meeting-live.mp4
```

## Notes

- Default recording profile is `1280x720`, `25fps`, H.264 video + AAC audio.
- Output file size depends on screen activity and duration.
- Make sure the meeting is actually visible on `DISPLAY=:99` before recording.
