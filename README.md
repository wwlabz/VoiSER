# VoiSER (macOS + Windows)

VoiSER is a multi-platform voice input app with local transcription and smart text output.

## Repository Layout

- `apps/macos` — production macOS app (Swift + AppKit/SwiftUI + WhisperKit)
- `apps/windows` — Windows app (WinUI 3 + local whisper.cpp via whisper.net)
- `docs` — installation, permissions, architecture, release notes guidance
- `scripts` — top-level orchestration scripts

## Quick Start

### macOS

```bash
./scripts/macos-test.sh
./scripts/macos-package.sh
./scripts/macos-install.sh
```

### Windows

```powershell
cd apps/windows
dotnet restore
dotnet test
```

## Downloads

Artifacts are published in GitHub Releases:

- macOS app package
- Windows MSIX package
- Windows portable ZIP

## CI/CD

- Pull requests: matrix validation on macOS + Windows
- Tags `v*`: cross-platform release artifacts are generated and attached

## Documentation

- `docs/install-macos.md`
- `docs/install-windows.md`
- `docs/permissions.md`
- `docs/architecture.md`

## License

MIT — see `LICENSE`.
