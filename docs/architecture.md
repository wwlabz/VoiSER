# Architecture

## Monorepo

- `apps/macos`: Swift app target and tests.
- `apps/windows`: WinUI app, core contracts, infrastructure, and tests.

## Shared Product Contracts (logical)

- `CaptureState`
- `TextOutputMode` (`clipboard`, `pasteAtCursor`, `pasteStrict`)
- `TextDeliveryOutcome`
- `TextOutputFallbackReason`

The two apps keep platform-native implementation details while preserving user-facing behavior parity.
