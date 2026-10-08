import AppKit
import ApplicationServices
import DockPinCore
import ServiceManagement

/// Menu-bar agent: pins the Dock to the center display (or the one you pick) and keeps it there.
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
        if pinner.pointer.mode == .monitor { askForAccessibility() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pinner.restore()
    }

    /// The point is to keep the Dock pinned after every login, so DockPin turns this on once by itself;
    /// turning it off from the menu sticks.
    private func openAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "loginItemOffered") else { return }
        defaults.set(true, forKey: "loginItemOffered")
        if SMAppService.mainApp.status != .enabled { toggleLogin() }
    }

    /// The Dock position and the Accessibility grant have no change notifications; checking them is cheap.
    private func watchSettings() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let plan = self.pinner.activePlan, plan.edge != DockPrefs.edge() { self.pinner.reconcile() }
            if self.pinner.pointer.upgradeIfTrusted() { self.rebuildMenu() }
            let tracing = UserDefaults.standard.bool(forKey: "traceMoves")
            if tracing != (self.pinner.pointer.trace != nil) { self.pinner.pointer.trace = tracing ? MoveTrace() : nil }
            self.pinner.pointer.trace?.flush()
        }
    }

    /// macOS's own prompt; it also lists DockPin in Privacy & Security > Accessibility. If it was
    /// dismissed before, macOS won't show it again, so the menu item also opens that pane.
    private func askForAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Display changes arrive in bursts (and our own change triggers one); act once they settle.
    @objc private func displaysChanged() {
        pendingReconcile?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pinner.reconcile() }
        pendingReconcile = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        let edge = pinner.activePlan?.edge ?? DockPrefs.edge()
        let status = pinner.targetName.map { "Dock pinned to \($0)" } ?? "No center display found"
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(submenu("Pin Dock To", items: targetItems()))
        menu.addItem(submenu("Dock Position", items: DockEdge.allCases.map { e in
            item(e.rawValue.capitalized, #selector(chooseEdge(_:)), on: e == edge, represented: e.rawValue)
        }))
        if pinner.pointer.mode == .tap {
            menu.addItem(withTitle: "Seamless Crossings: On", action: nil, keyEquivalent: "").isEnabled = false
        } else {
            menu.addItem(item("Make Crossings Seamless…", #selector(makeCrossingsSeamless)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(withTitle: "Quit DockPin (restores the arrangement)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func targetItems() -> [NSMenuItem] {
        let chosen = pinner.chosenTargetName
        return [item("Center Display (Automatic)", #selector(chooseTarget(_:)), on: chosen == nil), .separator()]
            + pinner.displayNames.map { item($0, #selector(chooseTarget(_:)), on: $0 == chosen, represented: $0) }
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false, represented: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.state = on ? .on : .off
        i.representedObject = represented
        return i
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }

    @objc private func chooseTarget(_ sender: NSMenuItem) {
        pinner.chosenTargetName = sender.representedObject as? String
    }

    @objc private func chooseEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = DockEdge(rawValue: raw) else { return }
        DockPrefs.setEdge(edge)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.pinner.reconcile() }
    }

    @objc private func makeCrossingsSeamless() {
        askForAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
