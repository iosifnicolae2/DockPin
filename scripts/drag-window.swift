// A plain titled window for scripts/drag-test.swift to drag. It reads commands on stdin:
// "place X Y" puts the middle of its title bar at (X, Y) (global CoreGraphics coordinates), "quit" ends it.
// It prints "ready <window number>" once the window is on screen, and "placed" after each place.
import AppKit

let titleBarMiddle: CGFloat = 14  // from the window's top edge
let app = NSApplication.shared
app.setActivationPolicy(.regular)
/// Goes exactly where it's put, even hanging off a display (AppKit would otherwise pull it onto one).
final class TestWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 212), styleMask: [.titled, .closable, .miniaturizable],
                      backing: .buffered, defer: false)
window.title = "DockPin drag test"
let label = NSTextField(labelWithString: "Drag me by the title bar")
label.font = .systemFont(ofSize: 26, weight: .semibold)
label.alignment = .center
label.frame = NSRect(x: 0, y: 80, width: 480, height: 50)
window.contentView?.addSubview(label)

func place(_ x: CGFloat, _ y: CGFloat) {
    let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
    window.setFrame(NSRect(x: x - window.frame.width / 2, y: mainHeight - (y - titleBarMiddle) - window.frame.height,
                           width: window.frame.width, height: window.frame.height), display: true)
    window.orderFrontRegardless()
    app.activate(ignoringOtherApps: true)
}

func say(_ line: String) {
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

FileHandle.standardInput.readabilityHandler = { handle in
    let text = String(data: handle.availableData, encoding: .utf8) ?? "quit"
    DispatchQueue.main.async {
        for line in text.split(separator: "\n") {
            let words = line.split(separator: " ")
            if words.first == "place", words.count == 3, let x = Double(words[1]), let y = Double(words[2]) {
                place(x, y)
                say("placed")
            } else if words.first == "quit" || text.isEmpty {
                exit(0)
            }
        }
        if text.isEmpty { exit(0) }
    }
}

place(400, 300)
say("ready \(window.windowNumber)")
app.run()
