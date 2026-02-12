#!/usr/bin/env bash
set -euo pipefail

# export_menu_icons.sh
# Exports the menu bar SF Symbols to PNGs for docs (e.g. GitHub README).
# Produces two files per symbol: {name}_light.png (black on transparent),
# {name}_dark.png (white on transparent) for light/dark theme.
#
# Requirements: macOS + Xcode Command Line Tools (xcrun + swift)
#
# Usage:
#   ./export_menu_icons.sh              # -> ./docs/icons, 64pt
#   ./export_menu_icons.sh ./out 128    # -> ./out, 128pt

OUT_DIR="${1:-./docs/icons}"
POINT_SIZE="${2:-64}"

mkdir -p "$OUT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SWIFT_PATH="$TMP_DIR/export_symbols.swift"
cat > "$SWIFT_PATH" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

// args: outDir, pointSize
let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "./docs/icons"
let pointSize = CGFloat(Double(args.count > 2 ? args[2] : "64") ?? 64)
let scale: CGFloat = 2
let pixelSize = Int(pointSize * scale)

// (doc filename base, SF Symbol name)
let icons: [(String, String)] = [
  ("idle_clocked_out_unknown", "clock"),
  ("not_ready_cannot_reach_site", "mappin.slash.circle"),
  ("not_ready_keychain_error", "person.crop.circle.badge.exclamationmark"),
  ("not_ready_network_offline", "wifi.exclamationmark.circle"),
  ("not_ready_other", "circle.slash"),
  ("syncing_fetching_timecard", "progress.indicator"),
  ("working_clocked_in", "clock.fill"),
]

let baseDir = URL(fileURLWithPath: outDir)

func exportSymbol(name: String, symbolName: String, color: NSColor, suffix: String) -> Bool {
  guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    fputs("Error: unknown SF Symbol: \(symbolName)\n", stderr)
    return false
  }
  let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
  guard let img = base.withSymbolConfiguration(config) ?? base as NSImage? else { return false }

  let rect = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
  let pixelW = pixelSize
  let pixelH = pixelSize

  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelW,
    pixelsHigh: pixelH,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else { return false }

  rep.size = NSSize(width: pointSize, height: pointSize)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  let ctx = NSGraphicsContext.current!.cgContext
  ctx.clear(CGRect(x: 0, y: 0, width: pointSize, height: pointSize))

  ctx.beginTransparencyLayer(auxiliaryInfo: nil)
  img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
  ctx.setBlendMode(.sourceIn)
  color.set()
  ctx.fill(rect)
  ctx.endTransparencyLayer()

  NSGraphicsContext.restoreGraphicsState()

  let filename = "\(name)_\(suffix).png"
  let url = baseDir.appendingPathComponent(filename)
  guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }
  do {
    try pngData.write(to: url)
  } catch {
    fputs("Error: \(error)\n", stderr)
    return false
  }
  print("  → \(filename)")
  return true
}

print("Exporting \(icons.count) symbols to \(outDir) (\(Int(pointSize))pt, @\(Int(scale))x)")
print("")

for (idx, (name, symbolName)) in icons.enumerated() {
  let n = idx + 1
  let total = icons.count
  print("[\(n)/\(total)] \(name) (\(symbolName))")
  _ = exportSymbol(name: name, symbolName: symbolName, color: .black, suffix: "light")
  _ = exportSymbol(name: name, symbolName: symbolName, color: .white, suffix: "dark")
  print("")
}

print("Done: \(baseDir.path)")
SWIFT

echo "Building and running Swift exporter (one compile, all icons)..."
echo ""
xcrun swift "$SWIFT_PATH" "$OUT_DIR" "$POINT_SIZE"
