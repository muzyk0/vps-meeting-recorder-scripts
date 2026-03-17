# VPS meeting recorder scripts

Небольшой shell-based проект для записи созвонов на Linux VPS.

Сейчас основной поддерживаемый сценарий: **Yandex Telemost guest join + запись экрана и звука**.

---

## Основной рабочий flow

Для обычного запуска используй **detached launcher**:

```bash
cd ~/.openclaw/workspace/projects/vps-meeting-recorder-scripts
./start-telemost-recording.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

С ограничением по времени:

```bash
cd ~/.openclaw/workspace/projects/vps-meeting-recorder-scripts
DURATION=00:45:00 ./start-telemost-recording.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Это рекомендуемый способ для чата, автоматизации и фонового запуска.

### Что делает detached launcher

1. запускает запись в фоне, не привязывая её к текущей shell/tool session
2. поднимает/проверяет `Xvfb` и `PulseAudio`
3. открывает Telemost через `agent-browser`
4. заходит гостем во встречу
5. ждёт перед записью и прогревает аудио
6. пишет mp4 через `ffmpeg`
7. после штатного завершения закрывает browser tail, чтобы гость вышел из встречи

---

## Куда сохраняются записи

По умолчанию итоговые файлы пишутся сюда:

```bash
~/Movies/Records/
```

Пример:

```bash
~/Movies/Records/telemost-recorder-2026-03-18-001942.mp4
```

Проверить последний файл:

```bash
ls -1t ~/Movies/Records/*.mp4 | head
```

---

## Как остановить запись

Используй штатный stop-скрипт:

```bash
cd ~/.openclaw/workspace/projects/vps-meeting-recorder-scripts
./stop-telemost-recording.sh
```

Он:

- останавливает detached runner
- мягко завершает `ffmpeg` через `SIGINT`, чтобы mp4 успел закрыться
- при необходимости добивает процесс сильнее
- закрывает browser tail, чтобы бот вышел из встречи

---

## Основные файлы

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
├── run-telemost-recorder.sh  # foreground/debug flow
├── start-telemost-recording.sh
├── stop-telemost-recording.sh
└── start-telemost-env.sh     # compatibility shim -> prepare-env.sh
```

Runtime-директории:

- `~/Movies/Records/` — итоговые mp4 по умолчанию
- `logs/` — логи скриптов
- `artifacts/` — скриншоты, html dump, debug-артефакты браузера
- `.state/` — pid/state-файлы для корректного start/stop flow

---

## Подготовка окружения

```bash
cd ~/.openclaw/workspace/projects/vps-meeting-recorder-scripts
cp .env.example .env
./prepare-env.sh
```

---

## Foreground/debug flow

Если нужно дебажить по шагам, используй foreground-скрипт:

```bash
./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Это debug-вариант. Для обычной работы предпочитай `start-telemost-recording.sh`.

### Полезные debug-режимы

Проверить только окружение:

```bash
PREPARE_ONLY=1 ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Не входить и не писать:

```bash
NO_JOIN=1 SKIP_RECORDING=1 ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Войти, но не писать:

```bash
SKIP_RECORDING=1 ./run-telemost-recorder.sh 'https://telemost.yandex.ru/j/64264378385479' 'Recorder Bot'
```

Только запись без повторного входа:

```bash
RECORD_ONLY=1 DURATION=00:10:00 ./run-telemost-recorder.sh dummy 'Recorder Bot'
```

Dry-run:

```bash
DRY_RUN=1 ./prepare-env.sh
DRY_RUN=1 ./record-screen.sh ~/Movies/Records/test.mp4
```

---

## Настройка через `.env`

Самые важные переменные:

- `MEETING_URL` — ссылка на Телемост
- `GUEST_NAME` — имя гостя
- `OUTPUT_DIR` — куда писать записи
- `DURATION` — длительность записи
- `START_RECORDING_DELAY` — ждать после входа перед записью
- `AUDIO_WARMUP_DURATION` — прогрев monitor перед записью
- `NO_JOIN=1` — не нажимать `Подключиться`, только дойти до lobby
- `HEADED=1` — держать браузер в visual/headed режиме

Текущий дефолт для файлов:

```bash
OUTPUT_DIR=~/Movies/Records
```

---

## Bundled skill launcher

Если используешь skill launcher, вызывай его по абсолютному пути:

```bash
python3 /home/admin/.openclaw/workspace/skills/telemost-recording/scripts/launch_telemost_recording.py --url 'https://telemost.yandex.ru/j/64264378385479' --guest-name 'Recorder Bot'
```

Важно: **не** запускай `python3 scripts/launch_telemost_recording.py` из каталога проекта — такого файла в проекте нет; launcher лежит в skill-директории.

---

## Логи и артефакты

Логи:

- `logs/prepare-env.log`
- `logs/join-telemost.log`
- `logs/record-screen.log`
- `logs/run-telemost-recorder.log`
- `logs/start-telemost-recording.log`
- `logs/stop-telemost-recording.log`

Артефакты браузера:

- `artifacts/screenshots/.../*.png`
- `artifacts/screenshots/.../*-snapshot.txt`
- `artifacts/screenshots/.../*-console.txt`
- `artifacts/screenshots/.../*-errors.txt`

---

## Как понять, что всё сработало

Признаки рабочего запуска:

- `join-telemost.sh` дошёл до `Joined Telemost meeting`
- `run-telemost-recorder.sh` дошёл до `Step 3/3: recording screen`
- в `~/Movies/Records/` появился `.mp4`
- в `logs/record-screen.log` есть `Recording saved to ...`

Быстрая проверка файла:

```bash
ffprobe ~/Movies/Records/<file>.mp4
```

Проверка наличия звука:

```bash
ffmpeg -i ~/Movies/Records/<file>.mp4 -af volumedetect -vn -sn -dn -f null -
```

---

## Что сейчас считается каноничным

- обычный старт: `start-telemost-recording.sh`
- обычная остановка: `stop-telemost-recording.sh`
- debug/foreground: `run-telemost-recorder.sh`
- путь для сохранения: `~/Movies/Records`

Если что-то расходится с этим правилом — считай старой инструкцией и правь в пользу этого блока.
