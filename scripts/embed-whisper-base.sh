#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_REPO="argmaxinc/whisperkit-coreml"
MODEL_VARIANT="${1:-openai_whisper-base}"
MODEL_ROOT="$ROOT_DIR/Sources/VoiceWidget/Resources/Models"
MODEL_DIR="$MODEL_ROOT/$MODEL_VARIANT"
API_JSON="$(mktemp)"
MODEL_SIZE="${MODEL_VARIANT#openai_whisper-}"
TOKENIZER_REPO="openai/whisper-${MODEL_SIZE}"

cleanup() {
  rm -f "$API_JSON"
}
trap cleanup EXIT

mkdir -p "$MODEL_DIR"

echo "[1/4] Fetching file manifest for $MODEL_REPO ..."
curl -fsSL "https://huggingface.co/api/models/$MODEL_REPO" -o "$API_JSON"

MODEL_FILES=()
while IFS= read -r file; do
  MODEL_FILES+=("$file")
done < <(jq -r --arg prefix "$MODEL_VARIANT/" '.siblings[].rfilename | select(startswith($prefix))' "$API_JSON")

if [[ "${#MODEL_FILES[@]}" -eq 0 ]]; then
  echo "No files found for model variant: $MODEL_VARIANT" >&2
  exit 1
fi

if ! curl -fsSL "https://huggingface.co/api/models/$TOKENIZER_REPO" >/dev/null; then
  echo "Tokenizer repo $TOKENIZER_REPO not found, fallback to openai/whisper-base"
  TOKENIZER_REPO="openai/whisper-base"
fi

echo "[2/4] Downloading CoreML model files (${#MODEL_FILES[@]} files) ..."
for rel_path in "${MODEL_FILES[@]}"; do
  dest="$MODEL_ROOT/$rel_path"
  part="$dest.part"
  url="https://huggingface.co/$MODEL_REPO/resolve/main/$rel_path?download=true"

  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    echo "  - skip (exists): $rel_path"
    continue
  fi

  echo "  - fetch: $rel_path"
  curl -fL --retry 3 --retry-delay 2 --continue-at - --output "$part" "$url"
  mv "$part" "$dest"
done

TOKENIZER_FILES=(
  "tokenizer.json"
  "tokenizer_config.json"
  "config.json"
)

echo "[3/4] Downloading tokenizer files into bundled model ..."
for filename in "${TOKENIZER_FILES[@]}"; do
  dest="$MODEL_DIR/$filename"
  part="$dest.part"
  url="https://huggingface.co/$TOKENIZER_REPO/resolve/main/$filename?download=true"

  if [[ -f "$dest" ]]; then
    echo "  - skip (exists): $filename"
    continue
  fi

  echo "  - fetch: $filename"
  curl -fL --retry 3 --retry-delay 2 --continue-at - --output "$part" "$url"
  mv "$part" "$dest"
done

echo "[4/4] Done. Bundled model is ready at:"
echo "  $MODEL_DIR"
