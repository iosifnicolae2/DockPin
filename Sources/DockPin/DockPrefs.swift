import CoreFoundation
import DockPinCore

/// Reads the Dock's "Position on screen" setting.
enum DockPrefs {
    static func edge() -> DockEdge {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String
        return value.flatMap(DockEdge.init(rawValue:)) ?? .bottom
    }
}
