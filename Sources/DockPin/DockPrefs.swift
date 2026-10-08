import Foundation
import DockPinCore

/// The Dock's "Position on screen" setting.
enum DockPrefs {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "orientation" as CFString

    static func edge() -> DockEdge {
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue(key, domain) as? String
        return value.flatMap(DockEdge.init(rawValue:)) ?? .bottom
    }

    /// Same as choosing it in System Settings: saves it and restarts the Dock so it takes effect.
    static func setEdge(_ edge: DockEdge) {
        CFPreferencesSetAppValue(key, edge.rawValue as CFString, domain)
        CFPreferencesAppSynchronize(domain)
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Dock"]
        try? restart.run()
    }
}
