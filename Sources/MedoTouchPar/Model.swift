import AppKit

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case app, dock, button, hideBar, clock, battery, volume, brightness, media, escape, spacer, flexibleSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .app: return L("App (icon + badge)", "تطبيق (بأيقونته وإشعاراته)")
        case .dock: return L("Dock — open apps", "Dock — التطبيقات المفتوحة")
        case .button: return L("Custom button", "زر مخصص")
        case .hideBar: return L("Hide-bar button", "زر إخفاء الشريط")
        case .clock: return L("Clock", "الساعة")
        case .battery: return L("Battery", "البطارية")
        case .volume: return L("Volume slider", "شريط الصوت")
        case .brightness: return L("Brightness slider", "شريط السطوع")
        case .media: return L("Media controls", "تحكم الوسائط")
        case .escape: return L("Esc key", "زر Esc")
        case .spacer: return L("Fixed space", "فراغ ثابت")
        case .flexibleSpace: return L("Flexible space", "فراغ مرن")
        }
    }

    var defaultSymbol: String {
        switch self {
        case .app: return "app.badge"
        case .dock: return "dock.rectangle"
        case .button: return "star.fill"
        case .hideBar: return "chevron.down.circle.fill"
        case .clock: return "clock"
        case .battery: return "battery.100"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .media: return "playpause.fill"
        case .escape: return "escape"
        case .spacer: return "arrow.left.and.right"
        case .flexibleSpace: return "arrow.left.and.right.square"
        }
    }

    /// Kinds whose tap runs the item's configurable action.
    var supportsAction: Bool { self == .button || self == .clock || self == .battery }
    var showsAppTiles: Bool { self == .app || self == .dock }
}

enum ActionType: String, Codable, CaseIterable, Identifiable {
    case none, shortcut, openApp, openURL, shell, mediaKey, system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return L("None", "بدون")
        case .shortcut: return L("Keyboard shortcut", "اختصار لوحة مفاتيح")
        case .openApp: return L("Open app", "فتح تطبيق")
        case .openURL: return L("Open URL", "فتح رابط")
        case .shell: return L("Terminal command", "أمر Terminal")
        case .mediaKey: return L("Media / system key", "مفتاح وسائط/نظام")
        case .system: return L("System action", "إجراء نظام")
        }
    }
}

/// NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h.
enum MediaKey: String, Codable, CaseIterable, Identifiable {
    case playPause, next, previous, volumeUp, volumeDown, mute, brightnessUp, brightnessDown, keyboardLightUp, keyboardLightDown

    var id: String { rawValue }

    var keyType: Int32 {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        case .mute: return 7
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        case .keyboardLightUp: return 21
        case .keyboardLightDown: return 22
        }
    }

    var displayName: String {
        switch self {
        case .playPause: return L("Play / Pause", "تشغيل/إيقاف")
        case .next: return L("Next track", "التالي")
        case .previous: return L("Previous track", "السابق")
        case .volumeUp: return L("Volume up", "رفع الصوت")
        case .volumeDown: return L("Volume down", "خفض الصوت")
        case .mute: return L("Mute", "كتم")
        case .brightnessUp: return L("Brightness up", "رفع السطوع")
        case .brightnessDown: return L("Brightness down", "خفض السطوع")
        case .keyboardLightUp: return L("Keyboard light +", "إضاءة الكيبورد +")
        case .keyboardLightDown: return L("Keyboard light −", "إضاءة الكيبورد −")
        }
    }
}

enum SystemAction: String, Codable, CaseIterable, Identifiable {
    case lockScreen, sleepDisplay, missionControl, screenshot, spotlight, showDesktop, emojiPicker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lockScreen: return L("Lock screen", "قفل الشاشة")
        case .sleepDisplay: return L("Turn display off", "إطفاء الشاشة")
        case .missionControl: return "Mission Control"
        case .screenshot: return L("Screenshot", "لقطة شاشة")
        case .spotlight: return "Spotlight"
        case .showDesktop: return L("Show desktop", "إظهار سطح المكتب")
        case .emojiPicker: return L("Emoji picker", "الإيموجي")
        }
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags raw value
    var display: String
}

struct TBItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ItemKind
    var title: String = ""
    var symbol: String = ""
    var colorHex: String? = nil
    var width: Double? = nil
    var actionType: ActionType = .none
    /// App path (.app / openApp), URL, shell command, MediaKey or SystemAction raw value.
    var actionValue: String = ""
    var shortcut: Shortcut? = nil
    var clockFormat: String = "HH:mm"
    /// App / Dock items: draw the red notification badge.
    var showBadge: Bool = true
    /// Dock item: also list pinned apps that are not running, in Dock order.
    var dockIncludePinned: Bool = false
    /// App / Dock items: icon side and slot width in points (Touch Bar is 30pt tall).
    var iconSize: Double = 26
    var tileWidth: Double = 38
    /// App / Dock items: white dot under running apps.
    var showRunningDot: Bool = true
    /// App / Dock items: light background behind the frontmost app.
    var highlightActive: Bool = false

    init(kind: ItemKind) {
        self.kind = kind
        switch kind {
        case .app: symbol = ""
        case .dock: symbol = ""; highlightActive = true
        case .escape: symbol = ""; title = "esc"
        default: symbol = kind.defaultSymbol
        }
    }

    // Tolerates items saved by older versions with missing keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ItemKind.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        actionType = try c.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .none
        actionValue = try c.decodeIfPresent(String.self, forKey: .actionValue) ?? ""
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        clockFormat = try c.decodeIfPresent(String.self, forKey: .clockFormat) ?? "HH:mm"
        showBadge = try c.decodeIfPresent(Bool.self, forKey: .showBadge) ?? true
        dockIncludePinned = try c.decodeIfPresent(Bool.self, forKey: .dockIncludePinned) ?? false
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? 26
        tileWidth = try c.decodeIfPresent(Double.self, forKey: .tileWidth) ?? 38
        showRunningDot = try c.decodeIfPresent(Bool.self, forKey: .showRunningDot) ?? true
        highlightActive = try c.decodeIfPresent(Bool.self, forKey: .highlightActive) ?? (kind == .dock)
    }

    var summary: String {
        switch kind {
        case .button:
            let name = title.isEmpty ? (symbol.isEmpty ? L("Button", "زر") : symbol) : title
            return "\(name) — \(actionType.displayName)"
        case .app:
            return actionValue.isEmpty ? L("App — not chosen yet", "تطبيق — لم يُختر بعد") : AppCatalog.displayName(atPath: actionValue)
        default:
            return kind.displayName
        }
    }

    var tileStyle: TileStyle {
        TileStyle(iconSize: CGFloat(iconSize), width: CGFloat(tileWidth), showDot: showRunningDot,
                  showBadge: showBadge, highlightActive: highlightActive)
    }

    /// Approximate width on the Touch Bar, used for the preview and overflow warning.
    func estimatedWidth(dockCount: Int) -> CGFloat {
        let fixed = width.map { CGFloat($0) }
        switch kind {
        case .spacer: return 32
        case .flexibleSpace: return 0
        case .app: return CGFloat(tileWidth)
        case .dock:
            let content = CGFloat(max(dockCount, 1)) * CGFloat(tileWidth + 2)
            return min(content, fixed ?? 520)
        case .escape, .button, .hideBar:
            if let fixed { return fixed }
            let text = CGFloat(title.count) * 7.5
            return max(44, text + (symbol.isEmpty ? 24 : (title.isEmpty ? 44 : 46)))
        case .clock: return fixed ?? max(64, CGFloat(clockFormat.count) * 9 + (symbol.isEmpty ? 24 : 46))
        case .battery: return fixed ?? 78
        case .volume, .brightness: return (fixed ?? 150) + 60
        case .media: return fixed ?? 112
        }
    }
}

struct TileStyle: Equatable {
    var iconSize: CGFloat = 26
    var width: CGFloat = 38
    var showDot = true
    var showBadge = true
    var highlightActive = false
}

/// Touch Bar geometry of the 16" MacBook Pro 2019 (physical Esc key, 2008×60 px).
enum TouchBarGeometry {
    static let totalWidth: CGFloat = 1004
    static let itemSpacing: CGFloat = 8
    static let edgeMargin: CGFloat = 12

    /// Collapsed Control Strip: expand chevron plus one slot per item.
    static func controlStripWidth(itemCount: Int) -> CGFloat {
        28 + CGFloat(itemCount) * 38
    }
}

struct AppConfig: Codable, Equatable {
    var enabled = true
    var hideControlStrip = false
    var items: [TBItem] = AppConfig.defaultItems

    // Settings › feature switches.
    var language: AppLanguage = .system
    /// Put the bar back after Touch ID, lock, sleep or fn takes the Touch Bar.
    var autoRestore = true
    /// After ✕ / hide button, bring the bar back when another app comes forward.
    var returnAfterAppSwitch = true
    /// Seconds between badge / Dock refreshes (launch, quit and switch are instant).
    var refreshInterval: Double = 2
    var showFinderInDock = true
    var showMenuBarIcon = true

    init() {}

    // Tolerates config files written by older versions with missing keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        hideControlStrip = try c.decodeIfPresent(Bool.self, forKey: .hideControlStrip) ?? false
        items = try c.decodeIfPresent([TBItem].self, forKey: .items) ?? AppConfig.defaultItems
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        autoRestore = try c.decodeIfPresent(Bool.self, forKey: .autoRestore) ?? true
        returnAfterAppSwitch = try c.decodeIfPresent(Bool.self, forKey: .returnAfterAppSwitch) ?? true
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 2
        showFinderInDock = try c.decodeIfPresent(Bool.self, forKey: .showFinderInDock) ?? true
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
    }

    static var defaultItems: [TBItem] {
        var dock = TBItem(kind: .dock)
        dock.width = 360
        return [
            TBItem(kind: .hideBar),
            dock,
            TBItem(kind: .flexibleSpace),
            TBItem(kind: .media),
            TBItem(kind: .battery),
            TBItem(kind: .clock),
        ]
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}
