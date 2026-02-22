# VoiSER for macOS

Lightweight macOS voice widget with local Whisper transcription.

## Highlights

- Floating overlay widget over all windows/Spaces
- Global hotkey to start/stop recording (`Option + Space` by default)
- Local transcription via WhisperKit (no cloud API for transcription)
- First-launch `Whisper Flow`: user confirms model download, sees progress, then grants permissions
- Text output modes: clipboard, paste to active field, strict paste
- Optional launch at login

## Requirements

- macOS 14+
- Xcode 16+
- Swift 6.1+
- Internet access on first launch (for Whisper model download)

## Quick Start

1. Build/test:

```bash
swift test
```

2. Run:

```bash
swift run VoiSER
```

## Build `.app`

```bash
scripts/package-app.sh
```

Output:

- `dist/VoiSER.app`

By default, the packaged app does not include model binaries and stays small.
Whisper model is installed automatically on first launch.

Optional bundled-model build (larger app bundle):

```bash
INCLUDE_BUNDLED_MODEL=1 MODEL_VARIANT=openai_whisper-small scripts/package-app.sh
```

## Install local app

```bash
scripts/install-app.sh
```

## Privacy Notes

- Audio is processed locally.
- App requires microphone permission for recording.
- Paste-to-active-field modes require Accessibility permission.
- Whisper model files are downloaded from Hugging Face on first launch and stored in:
  `~/Library/Application Support/VoiSER/Models`
