import AppKit
import DockPinCore
import QuartzCore

/// Draws the piece of the pointer's arrow that a moved border would otherwise cut off: on a real border
/// macOS shows it on the neighbouring screen, but the moved screen isn't there in the pinned layout. The
/// piece is drawn where it belongs, in a click-through strip along the neighbour's edge.
///
/// This runs for every pointer move, inside the event tap, so it must never wait on the window server.
/// Showing or hiding a window does (a measured multi-ms round trip each time, which made fast crossings
/// lag), so each strip window is ordered in once and stays; per move only a layer inside it changes.
final class CursorTail {
    private var strips: [String: (window: NSWindow, layer: CALayer)] = [:]  // keyed by the strip rect
    private var visible: CALayer?
    private var cursor: (image: CGImage?, hotSpot: CGPoint, size: CGSize, fetched: TimeInterval)?
    /// A box around the pointer that holds any standard cursor (arrow, I-beam, ...) at the user's pointer
    /// size, whichever way it hangs off its hot spot; only used to decide whether to look closer.
    private let roughArrow: CGSize

    init() {
        let side = 64 * Self.pointerScale()
        roughArrow = CGSize(width: side, height: side)
    }

    func update(pointer p: CGPoint, rules: PointerRules?) {
        guard let rules,
              rules.hiddenArrowPart(at: p, arrow: roughArrow, hotSpot: CGPoint(x: roughArrow.width / 2, y: roughArrow.height / 2)) != nil
        else { return hide() }
        let c = currentCursor()
        guard let piece = rules.hiddenArrowPart(at: p, arrow: c.size, hotSpot: c.hotSpot),
              let strip = rules.borderStrip(containing: piece.frame, depth: roughArrow.width)
        else { return hide() }
        let layer = layer(for: strip)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if visible !== layer { visible?.isHidden = true }
        layer.contents = c.image
        // The whole arrow, placed relative to the strip; the strip's bounds cut it to the piece that belongs
        // on this screen. A view's layer has y growing upward (AppKit ignores isGeometryFlipped on it).
        layer.frame = CGRect(x: piece.arrowOrigin.x - strip.minX,
                             y: strip.maxY - piece.arrowOrigin.y - c.size.height,
                             width: c.size.width, height: c.size.height)
        layer.isHidden = false
        CATransaction.commit()
        visible = layer
    }

    /// The layout changed: the strips belong to borders that may no longer exist.
    func reset() {
        strips.values.forEach { $0.window.orderOut(nil) }
        strips = [:]
        visible = nil
    }

    private func hide() {
        guard let visible else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        visible.isHidden = true
        CATransaction.commit()
        self.visible = nil
    }

    /// The transparent, click-through window along one moved border, created and ordered in once.
    private func layer(for strip: CGRect) -> CALayer {
        if let existing = strips[strip.debugDescription] { return existing.layer }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let frame = NSRect(x: strip.minX, y: mainHeight - strip.maxY, width: strip.width, height: strip.height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        let piece = CALayer()
        piece.isHidden = true
        piece.contentsGravity = .resize
        host.layer?.addSublayer(piece)
        window.contentView = host
        window.orderFrontRegardless()
        strips[strip.debugDescription] = (window, piece)
        return piece
    }

    /// The current cursor's image, re-read at most every 0.2 s (apps change it, e.g. to an I-beam).
    private func currentCursor() -> (image: CGImage?, hotSpot: CGPoint, size: CGSize, fetched: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        if let cursor, now - cursor.fetched < 0.2 { return cursor }
        let system = NSCursor.currentSystem ?? .arrow
        let scale = Self.pointerScale()
        let fresh = (system.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                     CGPoint(x: system.hotSpot.x * scale, y: system.hotSpot.y * scale),
                     CGSize(width: system.image.size.width * scale, height: system.image.size.height * scale), now)
        cursor = fresh
        return fresh
    }

    /// Accessibility > Display > Pointer size.
    private static func pointerScale() -> CGFloat {
        max(1, UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "mouseDriverCursorSize") ?? 1)
    }
}
