# Contributing

## Repository structure

- `apps/macos` — Swift macOS app
- `apps/windows` — WinUI 3 Windows app

## Development setup

### macOS

1. `cd apps/macos`
2. `swift build`
3. `scripts/embed-whisper-base.sh openai_whisper-small` (optional, bundled model)
4. `swift run VoiSER`

### Windows

1. `cd apps/windows`
2. `dotnet restore VoiSER.Windows.sln`
3. `dotnet build VoiSER.Windows.sln -c Release`
4. `dotnet test VoiSER.Windows.sln -c Release`

## Pull requests

- Keep PRs focused and small.
- Include tests for behavior changes when possible.
- Run platform-appropriate tests before opening PR.

## Coding guidelines

- Avoid hardcoding personal/local identifiers.
- Keep security/privacy defaults conservative.
- Do not commit build artifacts, local app bundles, or downloaded model binaries.
