# Permissions

## macOS

- **Microphone**: required for audio capture.
- **Accessibility**: required for automatic paste and strict paste behavior.

## Windows

- **Microphone**: required for capture.
- **Input hooks/simulated input**:
  - required for global hotkeys and single-key exclusive mode.
  - some environments (Defender/AV policies) can restrict keyboard hooks or synthetic key events.
  - app falls back to clipboard when paste injection is unavailable in non-strict mode.
