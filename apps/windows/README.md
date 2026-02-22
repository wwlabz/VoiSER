# VoiSER for Windows (v1 scaffold)

Windows companion app for VoiSER, built with WinUI 3 and local-first design.

## Projects

- `src/VoiSER.Windows.App` — WinUI desktop shell
- `src/VoiSER.Windows.Core` — contracts, enums, core models
- `src/VoiSER.Windows.Infrastructure` — audio, hotkeys, output, settings, model bootstrap
- `tests/VoiSER.Windows.Tests` — unit tests

## Build/Test

```powershell
dotnet restore VoiSER.Windows.sln
dotnet build VoiSER.Windows.sln -c Release
dotnet test VoiSER.Windows.sln -c Release
```

## Packaging

```powershell
./scripts/build-windows.ps1
./scripts/package-windows.ps1
```
