#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BASE_PNG="$TMP_DIR/base-1024.png"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
OUT_ICNS="$ROOT_DIR/Sources/VoiceWidget/Resources/AppIcon.icns"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"

swift - "$BASE_PNG" <<'SWIFT'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { exit(1) }
let outputPath = args[1]

let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

image.lockFocus()

NSColor.clear.setFill()
rect.fill()

let card = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 190, yRadius: 190)
let cardGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.56, blue: 0.86, alpha: 1.0),
    NSColor(calibratedRed: 0.12, green: 0.33, blue: 0.74, alpha: 1.0)
])!
cardGradient.draw(in: card, angle: -40)

let cardStroke = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 184, yRadius: 184)
cardStroke.lineWidth = 5
NSColor.white.withAlphaComponent(0.16).setStroke()
cardStroke.stroke()

let glowA = NSBezierPath(ovalIn: NSRect(x: 250, y: 470, width: 380, height: 290))
NSColor.white.withAlphaComponent(0.18).setFill()
glowA.fill()

let glowB = NSBezierPath(ovalIn: NSRect(x: 330, y: 310, width: 420, height: 330))
NSColor(calibratedRed: 0.28, green: 0.64, blue: 1.0, alpha: 0.28).setFill()
glowB.fill()

if let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
    let configured = symbol.withSymbolConfiguration(.init(pointSize: 328, weight: .regular)) ?? symbol
    configured.isTemplate = true
    let symbolRect = NSRect(x: 335, y: 320, width: 354, height: 380)
    NSColor.black.withAlphaComponent(0.9).set()
    configured.draw(in: symbolRect)
}

let underline = NSBezierPath(roundedRect: NSRect(x: 390, y: 296, width: 244, height: 18), xRadius: 9, yRadius: 9)
NSColor.white.withAlphaComponent(0.24).setFill()
underline.fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    exit(2)
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

sips -z 16 16   "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64   "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

echo "Generated: $OUT_ICNS"
