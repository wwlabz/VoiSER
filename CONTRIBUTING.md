# Contributing

## Development setup

1. `swift build`
2. `scripts/embed-whisper-base.sh openai_whisper-small`
3. `swift run VoiceWidget`

## Pull requests

- Keep PRs focused and small.
- Include tests for behavior changes when possible.
- Run before opening PR:

```bash
swift test
swift build -c release --product VoiceWidget
```

## Coding guidelines

- Avoid hardcoding personal/local identifiers.
- Keep security/privacy defaults conservative.
- Do not commit build artifacts, local app bundles, or downloaded model binaries.
