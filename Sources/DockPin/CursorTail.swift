import AppKit
import DockPinCore

/// Draws the piece of the pointer's arrow that a moved border would otherwise cut off: on a real border
/// macOS shows it on the neighbouring screen, but the moved screen isn't there in the pinned layout. A small
/// click-through window just above everything shows that piece where it belongs, so the arrow looks whole.
final class CursorTail {
    private let window: NSWindow
    private let imageView = NSImageView()
    private var showing = false

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let content = NSView()
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        content.addSubview(imageView)
        window.contentView = content
        imageView.imageScaling = .scaleAxesIndependently
    }

    func update(pointer p: CGPoint, rules: PointerRules?) {
        let cursor = NSCursor.currentSystem ?? .arrow
        let scale = Self.pointerScale()
        let size = CGSize(width: cursor.image.size.width * scale, height: cursor.image.size.height * scale)
        let hotSpot = CGPoint(x: cursor.hotSpot.x * scale, y: cursor.hotSpot.y * scale)
        guard let rules, let piece = rules.hiddenArrowPart(at: p, arrow: size, hotSpot: hotSpot) else {
            hide()
            return
        }
        // Global coordinates have y down from the main display's top; windows use y up from its bottom.
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        window.setFrame(NSRect(x: piece.frame.minX, y: mainHeight - piece.frame.maxY,
                               width: piece.frame.width, height: piece.frame.height), display: false)
        imageView.image = cursor.image
        imageView.frame = NSRect(x: piece.arrowOrigin.x - piece.frame.minX,
                                 y: piece.frame.maxY - piece.arrowOrigin.y - size.height,
                                 width: size.width, height: size.height)
        if !showing {
            window.orderFrontRegardless()
            showing = true
        }
    }

    private func hide() {
        guard showing else { return }
        window.orderOut(nil)
        showing = false
    }

    /// Accessibility > Display > Pointer size.
    private static func pointerScale() -> CGFloat {
        max(1, UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "mouseDriverCursorSize") ?? 1)
    }
}
