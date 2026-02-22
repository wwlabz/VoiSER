# Install on Windows

## Developer build

```powershell
cd apps/windows
dotnet restore
dotnet build -c Release
dotnet test
```

## Run packaged app

- **MSIX**: install from GitHub Releases package.
- **Portable ZIP**: unzip and run `VoiSER.Windows.App.exe`.

## Notes

- First launch may request microphone permissions.
- Single-key exclusive mode may require elevated trust from security tools/AV.
