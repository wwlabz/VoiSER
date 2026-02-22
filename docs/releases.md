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

- If Windows MSIX is unavailable on a runner, workflow publishes `VoiSER-Windows-msix.zip` with a notice file.
- Check workflow logs in Actions for packaging toolchain details.
