import AppKit
import ServiceManagement

/// Menu-bar agent: pins the Dock to the center display and keeps it there.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pinner = Pinner()
    private var statusItem: NSStatusItem!
    private var pendingReconcile: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockPin")
        pinner.onChange = { [weak self] in self?.rebuildMenu() }

        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        pinner.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pinner.restore()
    }

    /// Display changes arrive in bursts (and our own change triggers one); act once they settle.
    @objc private func displaysChanged() {
        pendingReconcile?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pinner.reconcile() }
        pendingReconcile = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = pinner.targetName.map { "Dock pinned to \($0)" } ?? "No center display found"
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Quit DockPin (restores the arrangement)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
