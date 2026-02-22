# Install on macOS

## Build and test

```bash
cd apps/macos
swift test
```

## Package app

```bash
cd apps/macos
scripts/package-app.sh
```

## Install to Applications

```bash
cd apps/macos
scripts/install-app.sh
```

## Notes

- App requests microphone permission for capture.
- Paste modes may request Accessibility.
