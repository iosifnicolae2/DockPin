// Exports this Mac's own app icons and SF Symbols as PNGs for the README picture (never committed).
// Usage: swift scripts/readme-image/assets.swift OUTDIR   (run by scripts/make-readme-image.sh)
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func save(_ image: NSImage, _ name: String, px: Int, height: Int? = nil) {
    let pxH = height ?? px
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: pxH, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = image.size, scale = min(CGFloat(px) / size.width, CGFloat(pxH) / size.height)
    let w = size.width * scale, h = size.height * scale
    image.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(pxH) - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

let apps = ["/System/Library/CoreServices/Finder.app", "/System/Applications/Apps.app", 
            "/System/Cryptexes/App/System/Applications/Safari.app", "/System/Applications/Messages.app", "/System/Applications/Mail.app",
            "/System/Applications/Maps.app", "/System/Applications/Photos.app", "/System/Applications/FaceTime.app",
            "/System/Applications/Calendar.app", "/System/Applications/Notes.app", "/System/Applications/Music.app",
            "/System/Applications/App Store.app", "/System/Applications/System Settings.app"]
for path in apps where FileManager.default.fileExists(atPath: path) {
    let icon = NSWorkspace.shared.icon(forFile: path)
    icon.size = NSSize(width: 256, height: 256)
    save(icon, URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, px: 256)
}

let symbols = ["apple.logo", "wifi", "battery.100", "switch.2", "magnifyingglass", "person.crop.circle"]
for name in symbols {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { print("no symbol \(name)"); continue }
    let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
    let img = base.withSymbolConfiguration(config)!
    let tinted = NSImage(size: img.size, flipped: false) { rect in
        img.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    save(tinted, "sym-" + name, px: Int(128 * img.size.width / img.size.height), height: 128)  // keeps its shape
}
print("ok")
