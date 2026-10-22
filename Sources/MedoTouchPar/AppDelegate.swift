import AppKit
import Combine
import ServiceManagement
import SwiftUI
import TBPrivate

/// Background agent (LSUIElement): no Dock icon, lives in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store = ConfigStore()
    private let controlStrip = ControlStripStore()
    private lazy var controller = TouchBarController(store: store)
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var settingsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.language = store.config.language
        setupStatusItem()
        // Language and menu-bar icon follow the settings live. @Published emits
        // before the value is stored, so use the emitted config, not store.config.
        settingsObserver = store.$config.sink { [weak self] config in
            L10n.language = config.language
            self?.statusItem?.isVisible = config.showMenuBarIcon
            self?.window?.title = Self.windowTitle
        }

        guard TBSystemModalAvailable() else {
            let alert = NSAlert()
            alert.messageText = L("Touch Bar not available", "شريط اللمس غير متاح")
            alert.informativeText = L("This macOS version does not provide the Touch Bar APIs MedoTouchPar needs.",
                                      "لم يتم العثور على واجهات Touch Bar في هذا الإصدار من macOS.")
            alert.runModal()
            return
        }
        controller.start()

        if store.isFirstLaunch {
            store.save()
            try? SMAppService.mainApp.register()
            openCustomizer(tab: .items)
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the customizer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCustomizer(tab: nil)
        return true
    }

    private static var windowTitle: String {
        L("MedoTouchPar — Touch Bar customizer", "MedoTouchPar — تخصيص شريط اللمس")
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.split.3x1.fill", accessibilityDescription: "MedoTouchPar")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "MedoTouchPar"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = store.config.showMenuBarIcon
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = menu.addItem(withTitle: "MedoTouchPar \(AppInfo.version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(.separator())
        if controller.isVisible {
            menu.addItem(withTitle: L("Hide Touch Bar", "إخفاء شريط اللمس"), action: #selector(hideBar), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: L("Show Touch Bar", "إظهار شريط اللمس"), action: #selector(showBar), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Customize items…", "تخصيص العناصر…"), action: #selector(openItems), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("System items (Control Strip)…", "عناصر النظام (Control Strip)…"),
                     action: #selector(openSystemItems), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Settings…", "الإعدادات…"), action: #selector(openSettings), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: L("Launch at login", "التشغيل عند تسجيل الدخول"),
                                 action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let credit = menu.addItem(withTitle: AppInfo.madeBy, action: #selector(openRepository), keyEquivalent: "")
        credit.target = self
        menu.addItem(withTitle: L("Quit MedoTouchPar", "إنهاء MedoTouchPar"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func showBar() { controller.show() }
    @objc private func hideBar() { controller.hide() }
    @objc private func openItems() { openCustomizer(tab: .items) }
    @objc private func openSystemItems() { openCustomizer(tab: .system) }
    @objc private func openSettings() { openCustomizer(tab: .settings) }
    @objc private func openRepository() { NSWorkspace.shared.open(AppInfo.repository) }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    private func openCustomizer(tab: CustomizerTab?) {
        if let tab { NotificationCenter.default.post(name: .selectCustomizerTab, object: tab) }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = Self.windowTitle
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: CustomizerView(initialTab: tab ?? .items,
                                                                        showBar: { [weak self] in self?.controller.show() })
                .environmentObject(store)
                .environmentObject(controlStrip))
            window.center()
            self.window = window
        }
        controlStrip.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let selectCustomizerTab = Notification.Name("MedoTouchPar.selectCustomizerTab")
}
