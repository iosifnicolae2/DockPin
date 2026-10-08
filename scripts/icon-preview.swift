// Saves how macOS draws an app's icon (Liquid Glass, squircle, shadow) as a PNG.
// Usage: swift scripts/icon-preview.swift APP OUT.png [PX]   (run by scripts/make-icon.sh)
import AppKit

let args = CommandLine.arguments
let app = args[1], out = args[2], px = args.count > 3 ? Int(args[3])! : 1024
let icon = NSWorkspace.shared.icon(forFile: app)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
