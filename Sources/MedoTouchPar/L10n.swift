import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, english, arabic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("System default", "لغة النظام")
        case .english: return "English"
        case .arabic: return "العربية"
        }
    }
}

/// Tiny two-language localisation. Strings live next to the code that uses
/// them as `L("English", "العربية")`, so nothing can drift out of sync.
enum L10n {
    static var language: AppLanguage = .system

    static var isArabic: Bool {
        switch language {
        case .arabic: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ar") ?? false
        }
    }

    static var layoutDirection: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }

    /// Number / date formatting follows the app language, not the system region.
    static var locale: Locale { Locale(identifier: isArabic ? "ar" : "en_US") }

    /// Called before NSApplication starts so AppKit's own controls and panels
    /// (open panel, menus, layout direction) use the chosen language too.
    static func applyToAppKit(_ language: AppLanguage) {
        var defaults: [String: Any] = [:]
        switch language {
        case .english: defaults["AppleLanguages"] = ["en"]
        case .arabic: defaults["AppleLanguages"] = ["ar"]
        case .system: return
        }
        UserDefaults.standard.setVolatileDomain(defaults, forName: UserDefaults.argumentDomain)
    }
}

func L(_ english: String, _ arabic: String) -> String {
    L10n.isArabic ? arabic : english
}

enum AppInfo {
    static let author = "Moath Alhakeem"
    static var madeBy: String { L("Made by Moath Alhakeem", "صنع بواسطة معاذ الحكيم") }
    static let repository = URL(string: "https://github.com/Mo3athAmr/MedoTouchPar")!
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
