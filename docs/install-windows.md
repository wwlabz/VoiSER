# Install on Windows

## Developer build

```powershell
cd apps/windows
dotnet restore
dotnet build -c Release
dotnet test
```

## Run packaged app

- **MSIX**: unzip `VoiSER-Windows-msix.zip`, then run the `.msix` package inside.
  - If publisher is untrusted, install `VoiSER-signing.cer` to `Local Machine -> Trusted People` and retry.
- **Portable ZIP**: unzip and run `VoiSER.cmd` from archive root.
  - App binaries are located in `app\`.
  - Portable build is self-contained and does not require separate Windows App Runtime installation.

## Notes

- First launch may request microphone permissions.
- Single-key exclusive mode may require elevated trust from security tools/AV.
