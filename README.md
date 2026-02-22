# VoiSER (macOS + Windows)

VoiSER is a multi-platform voice input app with local transcription and smart text output.

## Download

- macOS (latest): [Download VoiSER-macOS.zip](https://github.com/wwlabz/VoiSER/releases/latest/download/VoiSER-macOS.zip)
- Windows Portable (latest): [Download VoiSER-Windows-portable.zip](https://github.com/wwlabz/VoiSER/releases/latest/download/VoiSER-Windows-portable.zip)
- Windows MSIX (latest): [Download VoiSER-Windows-msix.zip](https://github.com/wwlabz/VoiSER/releases/latest/download/VoiSER-Windows-msix.zip)
- All release notes: [GitHub Releases](https://github.com/wwlabz/VoiSER/releases/latest)

Windows Portable artifact is built as self-contained (no separate Windows App Runtime install required).
Portable archive root contains a single launcher file: `VoiSER.cmd` (binaries are inside `app/`).
Windows MSIX zip contains the package and install notes. If release signing secrets are not configured, the zip also includes a temporary `VoiSER-signing.cer` certificate for sideload install.

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

## Versioning and Releases

- Release artifacts are published on tag push `v*` via GitHub Actions.
- To publish a new version:

```bash
git tag v1.0.0
git push origin v1.0.0
```

- The workflow will attach:
  - `VoiSER-macOS.zip`
  - `VoiSER-Windows-portable.zip`
  - `VoiSER-Windows-msix.zip`

## CI/CD

- Pull requests: matrix validation on macOS + Windows
- Tags `v*`: cross-platform release artifacts are generated and attached

## Documentation

- `docs/install-macos.md`
- `docs/install-windows.md`
- `docs/releases.md`
- `docs/permissions.md`
- `docs/architecture.md`

## License

MIT — see `LICENSE`.
