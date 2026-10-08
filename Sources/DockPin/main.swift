import AppKit
import ServiceManagement

/// Menu-bar agent: pins the Dock to the center display and keeps it there.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pinner = Pinner()
    private var statusItem: NSStatusItem!
    private var pendingReconcile: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockPin")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "DockPin"
        statusItem.button?.image = icon
        pinner.onChange = { [weak self] in self?.rebuildMenu() }

        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        pinner.start()
        openAtLoginOnFirstRun()
        watchSettings()
    }

    /// The Dock position and the Accessibility grant have no change notifications; checking them is cheap.
    private func watchSettings() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let plan = self.pinner.activePlan, plan.edge != DockPrefs.edge() { self.pinner.reconcile() }
            let before = self.pinner.pointer.mode
            self.pinner.pointer.upgradeIfTrusted()
            if self.pinner.pointer.mode != before { self.rebuildMenu() }
        }
    }

    @objc private func askForAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// The point is to keep the Dock pinned after every login, so DockPin turns this on once by itself;
    /// turning it off from the menu sticks.
    private func openAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "loginItemOffered") else { return }
        defaults.set(true, forKey: "loginItemOffered")
        if SMAppService.mainApp.status != .enabled { toggleLogin() }
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
        let edge = pinner.activePlan?.edge.rawValue ?? ""
        let status = pinner.targetName.map { "Dock (\(edge)) pinned to \($0)" } ?? "No center display found"
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        if pinner.pointer.mode == .monitor {
            let smooth = menu.addItem(withTitle: "Make Crossings Seamless (Allow Accessibility)…", action: #selector(askForAccessibility), keyEquivalent: "")
            smooth.target = self
        }
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
        log.notice("open at login: status \(SMAppService.mainApp.status.rawValue) (1 = enabled, 2 = needs approval)")
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
