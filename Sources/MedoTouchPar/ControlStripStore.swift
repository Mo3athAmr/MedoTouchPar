import Foundation

/// One built-in Control Strip button (identifiers taken from ControlStrip.app).
struct SystemStripItem: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    /// Groups (sliders/rows) only exist in the expanded strip.
    var isGroup: Bool { id.contains(".group.") }
}

/// Edits the system's own Touch Bar buttons — the same `com.apple.controlstrip`
/// preferences System Settings › Keyboard › Touch Bar Settings › Customize Control Strip writes.
final class ControlStripStore: ObservableObject {
    /// Collapsed strip shown next to the app's items.
    @Published var mini: [String] = []
    /// Expanded strip shown after tapping the ‹ chevron.
    @Published var full: [String] = []
    @Published private(set) var hasPendingChanges = false
    @Published private(set) var hasBackup = false

    private static let domain = "com.apple.controlstrip" as CFString
    private static let miniKey = "MiniCustomized" as CFString
    private static let fullKey = "FullCustomized" as CFString

    static let appleDefaultMini = [
        "com.apple.system.brightness", "com.apple.system.volume", "com.apple.system.mute", "com.apple.system.siri",
    ]
    static let appleDefaultFull = [
        "com.apple.system.group.brightness", "com.apple.system.mission-control", "com.apple.system.launchpad",
        "com.apple.system.group.keyboard-brightness", "com.apple.system.group.media", "com.apple.system.group.volume",
        "com.apple.system.siri",
    ]

    /// Computed so names follow the current language.
    static var catalog: [SystemStripItem] { [
        .init(id: "com.apple.system.brightness", name: L("Brightness", "السطوع"), symbol: "sun.max.fill"),
        .init(id: "com.apple.system.volume", name: L("Volume", "الصوت"), symbol: "speaker.wave.2.fill"),
        .init(id: "com.apple.system.mute", name: L("Mute", "كتم الصوت"), symbol: "speaker.slash.fill"),
        .init(id: "com.apple.system.screencapture", name: L("Screenshot", "لقطة الشاشة"), symbol: "camera.viewfinder"),
        .init(id: "com.apple.system.siri", name: "Siri", symbol: "waveform.circle.fill"),
        .init(id: "com.apple.system.dictation", name: L("Dictation", "الإملاء الصوتي"), symbol: "mic.fill"),
        .init(id: "com.apple.system.do-not-disturb", name: L("Do Not Disturb", "عدم الإزعاج"), symbol: "moon.fill"),
        .init(id: "com.apple.system.screen-lock", name: L("Screen Lock", "قفل الشاشة"), symbol: "lock.fill"),
        .init(id: "com.apple.system.sleep", name: L("Sleep", "السكون"), symbol: "powersleep"),
        .init(id: "com.apple.system.screen-saver", name: L("Screen Saver", "شاشة التوقف"), symbol: "display"),
        .init(id: "com.apple.system.show-desktop", name: L("Show Desktop", "إظهار سطح المكتب"), symbol: "menubar.dock.rectangle"),
        .init(id: "com.apple.system.mission-control", name: "Mission Control", symbol: "rectangle.3.group"),
        .init(id: "com.apple.system.launchpad", name: L("Apps (Launchpad)", "التطبيقات (Launchpad)"), symbol: "square.grid.3x3.fill"),
        .init(id: "com.apple.system.notification-center", name: L("Notification Center", "مركز الإشعارات"), symbol: "bell.badge.fill"),
        .init(id: "com.apple.system.night-shift", name: "Night Shift", symbol: "sun.haze.fill"),
        .init(id: "com.apple.system.input-menu", name: L("Input Source", "مصدر الإدخال (اللغة)"), symbol: "globe"),
        .init(id: "com.apple.system.search", name: "Spotlight", symbol: "magnifyingglass"),
        .init(id: "com.apple.system.airplay", name: "AirPlay", symbol: "airplayvideo"),
        .init(id: "com.apple.system.workflows", name: L("Quick Actions", "الإجراءات السريعة"), symbol: "bolt.fill"),
        .init(id: "com.apple.system.media-prev", name: L("Previous Track", "المقطع السابق"), symbol: "backward.fill"),
        .init(id: "com.apple.system.media-play-pause", name: L("Play / Pause", "تشغيل/إيقاف"), symbol: "playpause.fill"),
        .init(id: "com.apple.system.media-next", name: L("Next Track", "المقطع التالي"), symbol: "forward.fill"),
        .init(id: "com.apple.system.volume-down", name: L("Volume Down", "خفض الصوت"), symbol: "speaker.wave.1.fill"),
        .init(id: "com.apple.system.volume-up", name: L("Volume Up", "رفع الصوت"), symbol: "speaker.wave.3.fill"),
        .init(id: "com.apple.system.brightness-down", name: L("Brightness Down", "خفض السطوع"), symbol: "sun.min.fill"),
        .init(id: "com.apple.system.brightness-up", name: L("Brightness Up", "رفع السطوع"), symbol: "sun.max"),
        .init(id: "com.apple.system.keyboard-brightness-down", name: L("Keyboard Light Down", "خفض إضاءة الكيبورد"), symbol: "light.min"),
        .init(id: "com.apple.system.keyboard-brightness-up", name: L("Keyboard Light Up", "رفع إضاءة الكيبورد"), symbol: "light.max"),
        .init(id: "com.apple.system.group.brightness", name: L("Brightness Group", "مجموعة السطوع"), symbol: "sun.max.circle.fill"),
        .init(id: "com.apple.system.group.keyboard-brightness", name: L("Keyboard Light Group", "مجموعة إضاءة الكيبورد"), symbol: "keyboard.fill"),
        .init(id: "com.apple.system.group.media", name: L("Media Group", "مجموعة الوسائط"), symbol: "play.circle.fill"),
        .init(id: "com.apple.system.group.volume", name: L("Volume Group", "مجموعة الصوت"), symbol: "speaker.circle.fill"),
    ] }

    static func info(for id: String) -> SystemStripItem {
        catalog.first { $0.id == id }
            ?? SystemStripItem(id: id, name: id.replacingOccurrences(of: "com.apple.system.", with: ""), symbol: "questionmark.square")
    }

    private static var backupURL: URL { ConfigStore.directory.appendingPathComponent("controlstrip-backup.plist") }

    init() {
        reload()
    }

    /// In-memory strip for screenshot export; never reads or writes preferences.
    init(demoMini: [String], demoFull: [String]) {
        mini = demoMini
        full = demoFull
    }

    func reload() {
        CFPreferencesAppSynchronize(Self.domain)
        mini = CFPreferencesCopyAppValue(Self.miniKey, Self.domain) as? [String] ?? Self.appleDefaultMini
        full = CFPreferencesCopyAppValue(Self.fullKey, Self.domain) as? [String] ?? Self.appleDefaultFull
        hasPendingChanges = false
        hasBackup = FileManager.default.fileExists(atPath: Self.backupURL.path)
    }

    func markChanged() { hasPendingChanges = true }

    func available(forFull: Bool) -> [SystemStripItem] {
        let used = Set(forFull ? full : mini)
        return Self.catalog.filter { !used.contains($0.id) && (forFull || !$0.isGroup) }
    }

    /// Writes both strips and restarts ControlStrip (launchd relaunches it).
    func apply() {
        backupOriginalIfNeeded()
        CFPreferencesSetAppValue(Self.miniKey, mini as CFArray, Self.domain)
        CFPreferencesSetAppValue(Self.fullKey, full as CFArray, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)
        Self.restartControlStrip()
        hasPendingChanges = false
    }

    func useAppleDefaults() {
        mini = Self.appleDefaultMini
        full = Self.appleDefaultFull
        apply()
    }

    func restoreBackup() {
        guard let saved = NSDictionary(contentsOf: Self.backupURL) as? [String: [String]] else { return }
        mini = saved["MiniCustomized"] ?? Self.appleDefaultMini
        full = saved["FullCustomized"] ?? Self.appleDefaultFull
        apply()
    }

    private func backupOriginalIfNeeded() {
        guard !FileManager.default.fileExists(atPath: Self.backupURL.path) else { return }
        CFPreferencesAppSynchronize(Self.domain)
        let original: NSDictionary = [
            "MiniCustomized": CFPreferencesCopyAppValue(Self.miniKey, Self.domain) as? [String] ?? Self.appleDefaultMini,
            "FullCustomized": CFPreferencesCopyAppValue(Self.fullKey, Self.domain) as? [String] ?? Self.appleDefaultFull,
        ]
        original.write(to: Self.backupURL, atomically: true)
        hasBackup = true
    }

    static func restartControlStrip() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["ControlStrip"]
        try? process.run()
        process.waitUntilExit()
    }
}
