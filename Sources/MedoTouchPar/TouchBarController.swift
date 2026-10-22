import AppKit
import Combine
import TBPrivate

/// Target/action adapter so AppKit controls can call closures.
final class ActionHandler: NSObject {
    private let block: (Any) -> Void
    init(_ block: @escaping (Any) -> Void) { self.block = block }
    @objc func fire(_ sender: Any) { block(sender) }
}

/// Owns one NSTouchBar and keeps it presented system-wide (the mechanism
/// BetterTouchTool's BTTTouchBarCenter uses), restoring it whenever the system
/// takes the Touch Bar away — Touch ID prompts, sleep, lock, fn layer, etc.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let trayIdentifier = NSTouchBarItem.Identifier("com.medo.MedoTouchPar.tray")

    /// Processes whose windows mean an authentication prompt owns the Touch Bar.
    private static let authProcesses: Set<String> = [
        "coreautha", "coreauthd", "SecurityAgent", "LocalAuthenticationRemoteService",
        "AuthenticationServicesAgent", "LocalAuthenticationUIService",
    ]

    private let store: ConfigStore
    private let touchBar = NSTouchBar()
    private var trayItem: NSCustomTouchBarItem?
    private var itemsByIdentifier: [NSTouchBarItem.Identifier: TBItem] = [:]
    private var handlers: [ActionHandler] = []
    private var refreshers: [(Int) -> Void] = []
    /// Run when apps launch, quit or switch, so app/Dock tiles react instantly.
    private var appStateRefreshers: [() -> Void] = []
    private var revision = 0
    private var tick = 0
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var visibilityObservation: NSKeyValueObservation?
    private var appliedHideControlStrip: Bool?
    private var lastPresent = Date.distantPast

    /// Set by the hide button / menu; cleared by the Control Strip icon / menu.
    private(set) var userHidden = false
    /// App that was frontmost when the Touch Bar hide button was tapped; leaving
    /// it brings the bar back. nil while hidden means "until shown again".
    private var hiddenForApp: pid_t?
    /// True while this controller itself dismisses and re-presents the bar.
    private var isTransitioning = false
    var isVisible: Bool { touchBar.isVisible }
    private var wantsVisible: Bool { store.config.enabled && !userHidden }
    private var refreshEvery: Int { max(1, Int(store.config.refreshInterval.rounded())) }

    init(store: ConfigStore) {
        self.store = store
        super.init()
        touchBar.delegate = self
    }

    func start() {
        installTrayItem()

        visibilityObservation = touchBar.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.visibilityChanged() }
        }

        cancellable = store.$config
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] config in self?.apply(config) }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(systemReturned), name: name, object: nil)
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemReturned), name: .init("com.apple.screenIsUnlocked"), object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(self, selector: #selector(appStateChanged), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.refreshers.forEach { $0(self.tick) }
            self.watchdog()
            if self.tick % 3 == 0 { self.debugDump("tick") }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Visibility

    func show() {
        userHidden = false
        hiddenForApp = nil
        if !store.config.enabled { store.config.enabled = true }
        present(force: true)
    }

    /// untilAppSwitch: hide only while the current app stays frontmost
    /// (Touch Bar hide button), so its own Touch Bar tools are reachable.
    func hide(untilAppSwitch: Bool = false) {
        userHidden = true
        hiddenForApp = untilAppSwitch ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        TBMinimizeSystemModal(touchBar)
    }

    @objc private func appActivated(_ note: Notification) {
        guard userHidden, let hiddenForApp, store.config.returnAfterAppSwitch else { return }
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.processIdentifier != hiddenForApp else { return }
        show()
    }

    private func present(force: Bool = false) {
        guard wantsVisible else { return }
        if !force, systemOwnsTouchBar() { return }
        TBSetShowsCloseBox(false)
        TBPresentSystemModal(touchBar, store.config.hideControlStrip, Self.trayIdentifier)
        lastPresent = Date()
    }

    private func visibilityChanged() {
        debugDump("isVisible=\(touchBar.isVisible)")
        guard !touchBar.isVisible, wantsVisible, !isTransitioning else { return }
        // Give an auth prompt / lock a moment to appear before deciding who closed the bar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.touchBar.isVisible, self.wantsVisible, !self.isTransitioning else { return }
            if self.systemOwnsTouchBar() {
                self.watchdog() // retried every tick until the system is done
            } else {
                // The system ✕ close box: show this app's own Touch Bar until the user switches apps.
                DebugLog.write("closed by ✕ — hidden until app switch")
                // With "return after app switch" off it stays hidden until shown from the Control Strip / menu.
                self.userHidden = true
                self.hiddenForApp = self.store.config.returnAfterAppSwitch
                    ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
            }
        }
    }

    /// Re-presents the bar when something else removed it, unless the system
    /// is using the Touch Bar right now; then it retries on the next tick.
    private func watchdog() {
        guard store.config.autoRestore, wantsVisible, !touchBar.isVisible else { return }
        guard Date().timeIntervalSince(lastPresent) > 1 else { return }
        present()
    }

    /// Touch ID / password prompt, locked screen, or fn held (system F-key layer).
    private func systemOwnsTouchBar() -> Bool {
        if CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) { return true }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           session["CGSSessionScreenIsLocked"] as? Bool == true {
            return true
        }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { Self.authProcesses.contains($0[kCGWindowOwnerName as String] as? String ?? "") }
    }

    @objc private func systemReturned() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let trayItem = self.trayItem, self.store.config.autoRestore else { return }
            TBAddSystemTrayItem(trayItem)
            TBSetControlStripPresence(Self.trayIdentifier, true)
            // A ✕ / hide-button hide lasts only while that app stays in front.
            if self.userHidden, self.hiddenForApp != nil {
                self.show()
            } else {
                self.present()
            }
        }
    }

    @objc private func appStateChanged() {
        appStateRefreshers.forEach { $0() }
        debugDump("appStateChanged")
    }

    private func debugDump(_ reason: String) {
        guard DebugLog.isEnabled else { return }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        DebugLog.write("— \(reason) front=\(front) bar.isVisible=\(touchBar.isVisible) userHidden=\(userHidden)")
        for identifier in touchBar.defaultItemIdentifiers {
            guard let item = touchBar.item(forIdentifier: identifier) else {
                DebugLog.write("   \(identifier.rawValue.suffix(12)) item=nil")
                continue
            }
            var extra = ""
            if let strip = item.view as? DockStripView { extra = " " + strip.debugDescriptionLine }
            DebugLog.write("   \(identifier.rawValue.suffix(12)) item.isVisible=\(item.isVisible) \(DebugLog.describe(item.view))\(extra)")
        }
    }

    // MARK: Content

    private func apply(_ config: AppConfig) {
        revision += 1
        handlers.removeAll()
        refreshers.removeAll()
        appStateRefreshers.removeAll()
        itemsByIdentifier.removeAll()

        // New identifiers per revision make AppKit rebuild every item in place
        // on the same bar, so edits never dismiss and re-present it.
        touchBar.defaultItemIdentifiers = config.items.map { item in
            switch item.kind {
            case .spacer: return .fixedSpaceLarge
            case .flexibleSpace: return .flexibleSpace
            default:
                let identifier = NSTouchBarItem.Identifier("com.medo.MedoTouchPar.\(revision).\(item.id.uuidString)")
                itemsByIdentifier[identifier] = item
                return identifier
            }
        }

        guard config.enabled else {
            TBDismissSystemModal(touchBar)
            appliedHideControlStrip = nil
            return
        }
        if let applied = appliedHideControlStrip, applied != config.hideControlStrip, touchBar.isVisible {
            // Placement only changes on a fresh presentation.
            isTransitioning = true
            TBDismissSystemModal(touchBar)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.present(force: true)
                self?.isTransitioning = false
            }
        } else if !userHidden {
            present(force: true)
        }
        appliedHideControlStrip = config.hideControlStrip
    }

    private func installTrayItem() {
        let item = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let handler = ActionHandler { [weak self] _ in self?.show() }
        let image = NSImage(systemSymbolName: "rectangle.split.3x1.fill", accessibilityDescription: "MedoTouchPar")!
        item.view = NSButton(image: image, target: handler, action: #selector(ActionHandler.fire(_:)))
        objc_setAssociatedObject(item, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
        TBAddSystemTrayItem(item)
        TBSetControlStripPresence(Self.trayIdentifier, true)
        trayItem = item
    }

    // MARK: NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let item = itemsByIdentifier[identifier] else { return nil }
        switch item.kind {
        case .escape:
            return makeButtonItem(identifier, item) { KeySender.press(keyCode: 53) }.0
        case .button:
            return makeButtonItem(identifier, item) { ActionRunner.run(item) }.0
        case .hideBar:
            return makeButtonItem(identifier, item) { [weak self] in self?.hide(untilAppSwitch: self?.store.config.returnAfterAppSwitch ?? true) }.0
        case .app:
            return makeAppItem(identifier, item)
        case .dock:
            return makeDockItem(identifier, item)
        case .clock:
            let (barItem, button) = makeButtonItem(identifier, item) { ActionRunner.run(item) }
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateFormat = item.clockFormat.isEmpty ? "HH:mm" : item.clockFormat
            let update = { button.title = formatter.string(from: Date()) }
            update()
            refreshers.append { _ in update() }
            return barItem
        case .battery:
            let (barItem, button) = makeButtonItem(identifier, item) { ActionRunner.run(item) }
            let update = {
                guard let status = Battery.status() else { button.title = "—"; return }
                button.title = "\(status.percent)%"
                button.image = NSImage(systemSymbolName: Battery.symbol(for: status), accessibilityDescription: nil)
                button.imagePosition = .imageLeading
            }
            update()
            refreshers.append { tick in if tick % 20 == 0 { update() } }
            return barItem
        case .volume:
            return makeSlider(identifier, item, minSymbol: "speaker.fill", maxSymbol: "speaker.wave.3.fill",
                              get: { Volume.level }, set: { Volume.level = $0 })
        case .brightness:
            return makeSlider(identifier, item, minSymbol: "sun.min.fill", maxSymbol: "sun.max.fill",
                              get: { Brightness.level }, set: { Brightness.level = $0 })
        case .media:
            return makeMediaItem(identifier, item)
        case .spacer, .flexibleSpace:
            return nil
        }
    }

    // MARK: Item factories

    private func makeButtonItem(_ identifier: NSTouchBarItem.Identifier, _ item: TBItem,
                                action: @escaping () -> Void) -> (NSCustomTouchBarItem, NSButton) {
        let handler = ActionHandler { _ in action() }
        handlers.append(handler)
        let button = NSButton(title: item.title, target: handler, action: #selector(ActionHandler.fire(_:)))
        if !item.symbol.isEmpty, let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title) {
            button.image = image
            button.imagePosition = item.title.isEmpty ? .imageOnly : .imageLeading
        }
        if let hex = item.colorHex, let color = NSColor(hex: hex) {
            button.bezelColor = color
        }
        if let width = item.width, width > 0 {
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let barItem = NSCustomTouchBarItem(identifier: identifier)
        barItem.view = button
        barItem.customizationLabel = item.kind.displayName
        return (barItem, button)
    }

    private func makeAppItem(_ identifier: NSTouchBarItem.Identifier, _ item: TBItem) -> NSTouchBarItem? {
        guard !item.actionValue.isEmpty else { return nil }
        let path = item.actionValue
        let tile = AppTileView(url: URL(fileURLWithPath: path), style: item.tileStyle)
        let update = { [weak tile] in
            let state = AppItemState.of(path: path)
            tile?.update(badge: state.badge, running: state.isRunning, active: state.isFrontmost)
        }
        update()
        let every = refreshEvery
        refreshers.append { tick in if tick % every == 0 { update() } }
        appStateRefreshers.append(update)
        let barItem = NSCustomTouchBarItem(identifier: identifier)
        barItem.view = tile
        barItem.customizationLabel = AppCatalog.displayName(atPath: path)
        barItem.visibilityPriority = .high
        return barItem
    }

    private func makeDockItem(_ identifier: NSTouchBarItem.Identifier, _ item: TBItem) -> NSTouchBarItem {
        let strip = DockStripView(maxWidth: CGFloat(item.width ?? 520),
                                  includePinned: item.dockIncludePinned,
                                  includeFinder: store.config.showFinderInDock,
                                  style: item.tileStyle)
        let every = refreshEvery
        refreshers.append { [weak strip] tick in if tick % every == 0 { strip?.refresh() } }
        appStateRefreshers.append { [weak strip] in strip?.refresh() }
        let barItem = NSCustomTouchBarItem(identifier: identifier)
        barItem.view = strip
        barItem.customizationLabel = ItemKind.dock.displayName
        barItem.visibilityPriority = .high
        return barItem
    }

    private func makeSlider(_ identifier: NSTouchBarItem.Identifier, _ item: TBItem,
                            minSymbol: String, maxSymbol: String,
                            get: @escaping () -> Float, set: @escaping (Float) -> Void) -> NSTouchBarItem {
        let slider = NSSliderTouchBarItem(identifier: identifier)
        slider.slider.minValue = 0
        slider.slider.maxValue = 1
        slider.slider.doubleValue = Double(get())
        slider.minimumValueAccessory = NSSliderAccessory(image: NSImage(systemSymbolName: minSymbol, accessibilityDescription: nil)!)
        slider.maximumValueAccessory = NSSliderAccessory(image: NSImage(systemSymbolName: maxSymbol, accessibilityDescription: nil)!)
        let width = item.width ?? 150
        slider.minimumSliderWidth = width
        slider.maximumSliderWidth = width

        var lastUserChange = Date.distantPast
        let handler = ActionHandler { sender in
            guard let sliderItem = sender as? NSSliderTouchBarItem else { return }
            lastUserChange = Date()
            set(Float(sliderItem.slider.doubleValue))
        }
        handlers.append(handler)
        slider.target = handler
        slider.action = #selector(ActionHandler.fire(_:))

        // Follow changes made elsewhere (keyboard keys, Control Center).
        refreshers.append { [weak slider] _ in
            guard let slider, Date().timeIntervalSince(lastUserChange) > 1.5 else { return }
            slider.slider.doubleValue = Double(get())
        }
        return slider
    }

    private func makeMediaItem(_ identifier: NSTouchBarItem.Identifier, _ item: TBItem) -> NSTouchBarItem {
        let images = ["backward.fill", "playpause.fill", "forward.fill"].map {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)!
        }
        let keys: [MediaKey] = [.previous, .playPause, .next]
        let handler = ActionHandler { sender in
            guard let control = sender as? NSSegmentedControl, keys.indices.contains(control.selectedSegment) else { return }
            KeySender.media(keys[control.selectedSegment])
        }
        handlers.append(handler)
        let control = NSSegmentedControl(images: images, trackingMode: .momentary,
                                         target: handler, action: #selector(ActionHandler.fire(_:)))
        if let width = item.width, width > 0 {
            control.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let barItem = NSCustomTouchBarItem(identifier: identifier)
        barItem.view = control
        return barItem
    }
}
