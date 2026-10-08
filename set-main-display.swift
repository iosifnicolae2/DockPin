// Makes the named display the main display (menu bar + Dock), keeping the arrangement.
// Usage: swift set-main-display.swift "Odyssey G81SF" [--apply]   (without --apply it only prints the plan)
import AppKit

func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
}

let args = CommandLine.arguments.dropFirst()
guard let name = args.first(where: { !$0.hasPrefix("--") }) else {
    print("usage: set-main-display.swift <display name> [--apply]"); exit(2)
}
let apply = args.contains("--apply")

guard let target = NSScreen.screens.first(where: { $0.localizedName == name }) else {
    print("no display named \(name); have: \(NSScreen.screens.map(\.localizedName))"); exit(1)
}
let shift = CGDisplayBounds(displayID(of: target)).origin

var config: CGDisplayConfigRef?
if apply { CGBeginDisplayConfiguration(&config) }
for screen in NSScreen.screens {
    let id = displayID(of: screen)
    let old = CGDisplayBounds(id).origin
    let new = CGPoint(x: old.x - shift.x, y: old.y - shift.y)
    print("\(screen.localizedName): \(old) -> \(new)")
    if apply { CGConfigureDisplayOrigin(config, id, Int32(new.x), Int32(new.y)) }
}
if apply {
    let err = CGCompleteDisplayConfiguration(config, .permanently)
    print(err == .success ? "applied" : "failed: \(err)")
} else {
    print("dry run; add --apply to change it")
}
