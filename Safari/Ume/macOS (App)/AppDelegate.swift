import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var aboutWindowController: AboutWindowController?
    private var privacyWindowController: PrivacyWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        installWindowMenu()
        installSettingsShortcut()
        installAboutAction()
        configureSettingsWindow()
    }

    private func configureSettingsWindow() {
        guard let window = NSApp.windows.first else { return }
        window.styleMask.insert([.closable, .miniaturizable, .resizable])
        settingsWindowController = window.windowController
        showSettingsContent(in: window)
        window.center()
        if !OnboardingStore.isComplete {
            window.orderOut(nil)
            showOnboarding(nil)
        }
    }

    private func showSettingsContent(in window: NSWindow) {
        window.title = "Ume Settings"
        window.contentViewController = SettingsTabViewController()
        window.contentMinSize = NSSize(width: 720, height: 500)
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
    }

    private func installEditMenu() {
        guard let mainMenu = NSApp.mainMenu,
              !mainMenu.items.contains(where: { $0.title == "Edit" }) else { return }
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        item.submenu = menu
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.insertItem(item, at: min(1, mainMenu.items.count))
    }

    private func installWindowMenu() {
        guard let mainMenu = NSApp.mainMenu,
              !mainMenu.items.contains(where: { $0.title == "Window" }) else { return }
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")
        item.submenu = menu
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = menu
        let helpIndex = mainMenu.items.firstIndex(where: { $0.title == "Help" }) ?? mainMenu.items.count
        mainMenu.insertItem(item, at: helpIndex)
    }

    private func installSettingsShortcut() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        item.target = self
        appMenu.insertItem(item, at: min(2, appMenu.items.count))
        appMenu.insertItem(.separator(), at: min(3, appMenu.items.count))
    }

    private func installAboutAction() {
        guard let about = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.title == "About Ume" }) else { return }
        about.target = self
        about.action = #selector(showAbout(_:))
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindowController?.showWindow(sender)
        settingsWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding(_ sender: Any?) {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController { [weak self] in
                self?.onboardingWindowController?.close()
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Safari.app"), configuration: NSWorkspace.OpenConfiguration())
            }
        }
        onboardingWindowController?.showWindow(sender)
        onboardingWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout(_ sender: Any?) {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController { [weak self] in self?.showPrivacy() }
        }
        aboutWindowController?.showWindow(sender)
        aboutWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPrivacy() {
        if privacyWindowController == nil { privacyWindowController = PrivacyWindowController() }
        privacyWindowController?.showWindow(nil)
        privacyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "ume" }) else { return }
        if url.host == "onboarding" {
            showOnboarding(nil)
        } else {
            showSettings(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
