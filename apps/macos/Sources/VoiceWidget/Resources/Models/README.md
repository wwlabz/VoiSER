# Whisper Models

This repository intentionally does not include Whisper model binaries.

Default behavior:

- On first app launch, `Whisper Flow` downloads the selected model automatically.
- Files are stored in:
  `~/Library/Application Support/VoiSER/Models/openai_whisper-<variant>`

Optional developer workflow (manual local pre-download):

- `scripts/embed-whisper-base.sh openai_whisper-small`
- `scripts/embed-whisper-base.sh openai_whisper-tiny`
- `scripts/embed-whisper-base.sh openai_whisper-base`

Manual pre-download is not required for normal app usage.
