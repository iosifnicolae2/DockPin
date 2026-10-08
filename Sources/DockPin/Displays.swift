import AppKit
import DockPinCore
import IOKit

/// Reads and changes the live display arrangement.
enum Displays {
    /// The real displays. Virtual ones are left out and never moved: one coming or going must not change
    /// which display is the center (and so main), nor be taken for a change to the user's arrangement.
    static func current() -> [Display] {
        let hardware = hardwareScreens()
        return NSScreen.screens.compactMap { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            guard HardwareScreen.isReal(builtIn: CGDisplayIsBuiltin(id) != 0, vendor: CGDisplayVendorNumber(id),
                                        serial: CGDisplaySerialNumber(id), among: hardware) else { return nil }
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

    /// Every monitor the graphics hardware drives: IOMobileFramebuffer on Apple silicon, IODisplayConnect on Intel.
    private static func hardwareScreens() -> [HardwareScreen] {
        var screens: [HardwareScreen] = []
        forEachService("IOMobileFramebuffer") { service in
            guard let attributes = property(service, "DisplayAttributes") as? [String: Any],
                  let product = attributes["ProductAttributes"] as? [String: Any],
                  let vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value else { return }
            screens.append(HardwareScreen(vendor: vendor, serial: (product["SerialNumber"] as? NSNumber)?.uint32Value))
        }
        forEachService("IODisplayConnect") { service in
            guard let vendor = (property(service, "DisplayVendorID") as? NSNumber)?.uint32Value else { return }
            screens.append(HardwareScreen(vendor: vendor, serial: (property(service, "DisplaySerialNumber") as? NSNumber)?.uint32Value))
        }
        return screens
    }

    private static func forEachService(_ serviceClass: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { return }
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
        IOObjectRelease(iterator)
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
