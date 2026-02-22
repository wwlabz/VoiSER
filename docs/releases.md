# Releases and Download Links

## Public download links (always latest)

- macOS: https://github.com/wwlabz/VoiSER/releases/latest/download/VoiSER-macOS.zip
- Windows Portable: https://github.com/wwlabz/VoiSER/releases/latest/download/VoiSER-Windows-portable.zip
- Windows MSIX: https://github.com/wwlabz/VoiSER/releases/latest/download/VoiSER-Windows-msix.zip
- Latest release page: https://github.com/wwlabz/VoiSER/releases/latest

## How to publish a new version

1. Ensure `main` is green in CI.
2. Create and push a semantic tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

3. GitHub Actions `release.yml` builds artifacts and publishes a release.

## Artifacts expected per release

- `VoiSER-macOS.zip`
- `VoiSER-Windows-portable.zip`
- `VoiSER-Windows-msix.zip`

## Troubleshooting

- Windows MSIX build is now required; release fails if a real `.msix/.appx/.msixbundle` is not produced.
- For trusted publisher installs, configure GitHub secrets:
  - `WINDOWS_PFX_BASE64` (base64-encoded `.pfx`)
  - `WINDOWS_PFX_PASSWORD`
- If secrets are absent, workflow generates a temporary self-signed cert and includes `VoiSER-signing.cer` in the MSIX zip.
