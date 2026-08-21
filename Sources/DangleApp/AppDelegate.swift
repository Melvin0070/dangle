import AppKit
import ServiceManagement
import DangleKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let engine = DangleEngine()
    private var statusItem: NSStatusItem!
    private var pendingURLs: [URL] = []
    private var isLaunched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.start()
        setUpStatusItem()
        setUpHotKeys()
        isLaunched = true
        if !pendingURLs.isEmpty {
            application(NSApp, open: pendingURLs)
            pendingURLs = []
        }
    }

    // MARK: URL scheme — dangle://bless, dangle://note[?text=&from=], dangle://toggle, dangle://charm?glyph=

    func application(_ application: NSApplication, open urls: [URL]) {
        // A URL can launch the app; it then arrives before
        // applicationDidFinishLaunching, when the engine has no window yet.
        // Park it and replay once launch completes.
        guard isLaunched else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query: (String) -> String? = { name in
                components?.queryItems?.first(where: { $0.name == name })?.value
            }
            switch url.host ?? url.path.trimmingCharacters(in: ["/"]) {
            case "bless":
                engine.bless()
            case "note":
                if let text = query("text"), !text.isEmpty {
                    engine.showCustomNote(text: text)
                } else {
                    engine.showNextNote()
                }
            case "charm":
                // dangle://charm?id=<installed charm id> hangs that charm,
                // ?glyph=<emoji> hangs a bare emoji, no query resets to the pack.
                if let id = query("id"), !id.isEmpty {
                    engine.setCharmOverride(id: id)
                } else if let glyph = query("glyph"), !glyph.isEmpty {
                    engine.setCharmOverride(id: "emoji:\(glyph)")
                } else {
                    engine.clearCharmOverride()
                }
                statusItem.button?.title = statusTitle()
            case "debug": engine.dumpDebug()
            case "toggle": engine.toggle()
            case "summon": engine.summon()
            case "dismiss": engine.dismiss()
            default: break
            }
        }
    }

    // MARK: Status item

    private func statusTitle() -> String {
        let charm = engine.effectivePack.charm
        if let menuGlyph = charm.menuGlyph, !menuGlyph.isEmpty { return menuGlyph }
        if charm.kind == "emoji" { return charm.glyph }
        return charm.glyph == "</>" ? "</>" : "🧿"
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        statusItem.button?.title = statusTitle()
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(title: "Dangle", action: #selector(toggleDangle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 1
        menu.addItem(toggleItem)

        let noteItem = NSMenuItem(title: "Show a Note", action: #selector(showNote), keyEquivalent: "")
        noteItem.target = self
        menu.addItem(noteItem)

        let blessItem = NSMenuItem(title: "Bless This Moment", action: #selector(bless), keyEquivalent: "")
        blessItem.target = self
        menu.addItem(blessItem)

        menu.addItem(.separator())

        let charmItem = NSMenuItem(title: "Charm", action: nil, keyEquivalent: "")
        charmItem.submenu = NSMenu()
        menu.addItem(charmItem)

        let autoItem = NSMenuItem(title: "Notes on a Timer", action: #selector(toggleAutoNotes), keyEquivalent: "")
        autoItem.target = self
        autoItem.tag = 2
        menu.addItem(autoItem)

        let behindItem = NSMenuItem(title: "Keep Behind Windows", action: #selector(toggleBehind), keyEquivalent: "")
        behindItem.target = self
        behindItem.tag = 3
        menu.addItem(behindItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = 4
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let editItem = NSMenuItem(title: "Edit Pack…", action: #selector(editPack), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let reloadItem = NSMenuItem(title: "Reload Pack", action: #selector(reloadPack), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(.separator())

        let hintItem = NSMenuItem(title: hotkeyHint(), action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        let quitItem = NSMenuItem(title: "Quit Dangle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }

    // MARK: Hotkeys

    private func hotkeySpecs() -> [String: String] {
        var specs = ["toggle": "ctrl+opt+d", "note": "ctrl+opt+n", "bless": "ctrl+opt+b"]
        for (action, spec) in engine.pack.hotkeys ?? [:] {
            specs[action] = spec
        }
        return specs
    }

    private func hotkeyHint() -> String {
        let specs = hotkeySpecs()
        func pretty(_ s: String?) -> String {
            (s ?? "").replacingOccurrences(of: "ctrl", with: "⌃")
                .replacingOccurrences(of: "control", with: "⌃")
                .replacingOccurrences(of: "opt", with: "⌥")
                .replacingOccurrences(of: "option", with: "⌥")
                .replacingOccurrences(of: "alt", with: "⌥")
                .replacingOccurrences(of: "cmd", with: "⌘")
                .replacingOccurrences(of: "shift", with: "⇧")
                .replacingOccurrences(of: "+", with: "")
                .uppercased()
        }
        return "\(pretty(specs["toggle"])) dangles · \(pretty(specs["note"])) notes"
    }

    private func setUpHotKeys() {
        let actions: [String: () -> Void] = [
            "toggle": { [weak self] in self?.engine.toggle() },
            "note": { [weak self] in self?.engine.showNextNote() },
            "bless": { [weak self] in self?.engine.bless() },
        ]
        for (action, spec) in hotkeySpecs() {
            guard let handler = actions[action],
                  let parsed = HotKeyCenter.parse(spec) else { continue }
            HotKeyCenter.shared.register(keyCode: parsed.keyCode,
                                         modifiers: parsed.modifiers,
                                         handler: handler)
        }
    }

    // MARK: Charm menu

    /// The charm list is data, not code: the pack charm, whatever is
    /// installed in the CharmStore, any emoji, and a way to get more.
    private func rebuildCharmMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let override = engine.charmOverrideID

        let packCharm = NSMenuItem(title: "Pack Charm",
                                   action: #selector(usePackCharm), keyEquivalent: "")
        packCharm.target = self
        packCharm.state = override == nil ? .on : .off
        menu.addItem(packCharm)
        menu.addItem(.separator())

        for charm in CharmStore.shared.installedCharms() {
            let item = NSMenuItem(title: charm.name,
                                  action: #selector(pickInstalledCharm(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = charm.id
            item.state = override == charm.id ? .on : .off
            menu.addItem(item)
        }

        let emojiCharm = NSMenuItem(title: "Pick an Emoji…",
                                    action: #selector(pickEmoji), keyEquivalent: "")
        emojiCharm.target = self
        emojiCharm.state = (override?.hasPrefix("emoji:") ?? false) ? .on : .off
        menu.addItem(emojiCharm)

        menu.addItem(.separator())
        let fetch = NSMenuItem(title: "Get New Charms…",
                               action: #selector(getNewCharms), keyEquivalent: "")
        fetch.target = self
        menu.addItem(fetch)
    }

    @objc private func pickInstalledCharm(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        engine.setCharmOverride(id: id)
        statusItem.button?.title = statusTitle()
    }

    @objc private func getNewCharms() {
        CharmStore.shared.fetchNewCharms { result in
            let alert = NSAlert()
            switch result {
            case .success(let fetch) where fetch.added.isEmpty && fetch.failedCount == 0:
                alert.messageText = "No new charms yet"
                alert.informativeText = "You already have every published charm. New ones land in the project repository from time to time."
            case .success(let fetch) where fetch.added.isEmpty:
                alert.messageText = "Couldn't fetch charms"
                alert.informativeText = "\(fetch.failedCount) charm\(fetch.failedCount == 1 ? "" : "s") couldn't be downloaded. Try again in a bit."
            case .success(let fetch):
                alert.messageText = fetch.added.count == 1
                    ? "One new charm installed"
                    : "\(fetch.added.count) new charms installed"
                var info = fetch.added.map(\.name).joined(separator: ", ")
                    + " — pick them from the Charm menu."
                if fetch.failedCount > 0 {
                    info += " (\(fetch.failedCount) more couldn't be downloaded.)"
                }
                alert.informativeText = info
            case .failure(let error):
                alert.messageText = "Couldn't fetch charms"
                alert.informativeText = error.localizedDescription
            }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Actions

    @objc private func toggleDangle() { engine.toggle() }
    @objc private func showNote() { engine.showNextNote() }
    @objc private func bless() { engine.bless() }
    @objc private func toggleAutoNotes() { engine.autoNotesEnabled.toggle() }
    @objc private func toggleBehind() { engine.setBehindWindows(!engine.isBehindWindows) }

    @objc private func usePackCharm() {
        engine.clearCharmOverride()
        statusItem.button?.title = statusTitle()
    }

    @objc private func pickEmoji() {
        let alert = NSAlert()
        alert.messageText = "Hang an emoji"
        alert.informativeText = "Pick the glyph that feels right. It hangs from the same thread, with a tiny twin as the middle bead."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "🍀"
        alert.accessoryView = field
        alert.addButton(withTitle: "Hang It")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let glyph = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !glyph.isEmpty {
                engine.setCharmOverride(id: "emoji:\(String(glyph.prefix(4)))")
                statusItem.button?.title = statusTitle()
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func reloadPack() {
        engine.reloadPack()
        statusItem.button?.title = statusTitle()
    }

    /// Copies the active pack into Application Support (if not already there)
    /// and reveals it, so customizing never requires a rebuild.
    @objc private func editPack() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask).first else { return }
        let dir = appSupport.appendingPathComponent("Dangle")
        let dest = dir.appendingPathComponent("pack.json")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: dest.path) {
            if let bundled = Bundle.main.url(forResource: "pack", withExtension: "json"),
               let data = try? Data(contentsOf: bundled) {
                try? data.write(to: dest)
            } else if let data = try? JSONEncoder().encode(engine.pack) {
                try? data.write(to: dest)
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.title = engine.isDangled ? "Put Away" : "Dangle"
        menu.item(withTag: 2)?.state = engine.autoNotesEnabled ? .on : .off
        menu.item(withTag: 3)?.state = engine.isBehindWindows ? .on : .off
        menu.item(withTag: 4)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if let charmMenu = menu.item(withTitle: "Charm")?.submenu {
            rebuildCharmMenu(charmMenu)
        }
    }
}
