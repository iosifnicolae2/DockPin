import AppKit
import DockPinCore

/// Reads and changes the live display arrangement.
enum Displays {
    static func current() -> [Display] {
        NSScreen.screens.compactMap { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return Display(uuid: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName, frame: CGDisplayBounds(id))
        }
    }

    /// Moves displays to the given frames' origins until log out; the saved arrangement is left alone.
    @discardableResult
    static func arrange(_ layout: [Display]) -> Bool {
        let ids = activeIDsByUUID()
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for display in layout {
            guard let id = ids[display.uuid] else { continue }
            CGConfigureDisplayOrigin(config, id, Int32(display.frame.minX), Int32(display.frame.minY))
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    static func matches(_ live: [Display], _ layout: [Display]) -> Bool {
        let origins = Dictionary(uniqueKeysWithValues: layout.map { ($0.uuid, $0.frame.origin) })
        return live.count == layout.count && live.allSatisfy { origins[$0.uuid] == $0.frame.origin }
    }

    static func setKey(_ displays: [Display]) -> String {
        displays.map(\.uuid).sorted().joined(separator: "+")
    }

    private static func activeIDsByUUID() -> [String: CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            CGDisplayCreateUUIDFromDisplayID(id).map { (CFUUIDCreateString(nil, $0.takeRetainedValue()) as String, id) }
        })
    }
}
