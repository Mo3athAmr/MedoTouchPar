import AppKit
import TBPrivate

enum AppBadges {
    /// Same text the Dock draws in its red badge, or nil.
    static func label(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        return TBBadgeLabelForPID(app.processIdentifier)
    }
}

enum RunningApps {
    /// Apps that would appear in the Dock (includes Safari/Chrome web apps).
    static var regular: [NSRunningApplication] {
        let me = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleURL != nil && !$0.isTerminated && $0.bundleIdentifier != me
        }
    }

    private static var bundleIDCache: [String: String] = [:]

    static func bundleID(atPath path: String) -> String? {
        if let cached = bundleIDCache[path] { return cached }
        let id = Bundle(path: path)?.bundleIdentifier
        if let id { bundleIDCache[path] = id }
        return id
    }

    static func app(atPath path: String) -> NSRunningApplication? {
        if let id = bundleID(atPath: path),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated }) {
            return app
        }
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return regular.first { $0.bundleURL?.standardizedFileURL.path == target }
    }

    static func isFrontmost(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
}

enum AppLauncher {
    /// Behaves like clicking the app in the Dock: launches it, or brings the
    /// running instance forward (re-opening a window if it has none).
    static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

struct DockEntry: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let app: NSRunningApplication?

    var isRunning: Bool { DemoMode.isActive || app != nil }
    var badge: String? { DemoMode.isActive ? DemoMode.badges[url.path] : AppBadges.label(for: app) }
    var isFrontmost: Bool { DemoMode.isActive ? url.path == DemoMode.frontmostPath : RunningApps.isFrontmost(app) }

    static func == (a: DockEntry, b: DockEntry) -> Bool {
        a.url == b.url && a.app?.processIdentifier == b.app?.processIdentifier
    }
}

enum DockSource {
    /// Pinned apps, in the user's Dock order (com.apple.dock persistent-apps).
    static func pinnedURLs() -> [URL] {
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            return []
        }
        return tiles.compactMap { tile in
            let fileData = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
            return (fileData?["_CFURLString"] as? String).flatMap { URL(string: $0) }?.standardizedFileURL
        }
    }

    static func entries(includePinned: Bool, includeFinder: Bool = true) -> [DockEntry] {
        if DemoMode.isActive {
            return DemoMode.appPaths.map { DockEntry(url: URL(fileURLWithPath: $0), app: nil) }
        }
        // Finder first, then launch order — the same order the Dock uses.
        var running = RunningApps.regular.sorted {
            ($0.bundleIdentifier == "com.apple.finder" ? 0 : 1, $0.launchDate ?? .distantPast)
                < ($1.bundleIdentifier == "com.apple.finder" ? 0 : 1, $1.launchDate ?? .distantPast)
        }
        var result: [DockEntry] = []
        if includePinned {
            for url in pinnedURLs() {
                let id = RunningApps.bundleID(atPath: url.path)
                let index = running.firstIndex {
                    (id != nil && $0.bundleIdentifier == id) || $0.bundleURL?.standardizedFileURL == url
                }
                let app = index.map { running.remove(at: $0) }
                result.append(DockEntry(url: url, app: app))
            }
        }
        result += running.compactMap { app in app.bundleURL.map { DockEntry(url: $0, app: app) } }
        if !includeFinder {
            result.removeAll { RunningApps.bundleID(atPath: $0.url.path) == "com.apple.finder" }
        }
        return result
    }
}

struct InstalledApp: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isWebApp: Bool
}

enum AppCatalog {
    /// Localised Finder name in Arabic ("الرسائل"), bundle file name in English ("Messages").
    static func displayName(atPath path: String) -> String {
        let name = L10n.isArabic ? FileManager.default.displayName(atPath: path) : (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Safari "Add to Dock" apps, Chrome/Edge PWAs and Pake wrappers.
    static func isWebApp(bundleID: String, path: String) -> Bool {
        bundleID.contains(".WebApp.") || bundleID.contains("Chrome.app.") || bundleID.contains("Edge.app.")
            || bundleID.hasPrefix("com.pake.") || path.contains("Chrome Apps") || path.contains("Edge Apps")
    }

    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", "\(home)/Applications"]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        func add(_ path: String) {
            guard seen.insert(path).inserted else { return }
            let id = RunningApps.bundleID(atPath: path) ?? ""
            apps.append(InstalledApp(name: displayName(atPath: path), path: path, isWebApp: isWebApp(bundleID: id, path: path)))
        }

        for root in roots {
            for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let path = "\(root)/\(entry)"
                if entry.hasSuffix(".app") {
                    add(path)
                    continue
                }
                // One level of folders, e.g. "Chrome Apps.localized" or vendor folders.
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where sub.hasSuffix(".app") {
                    add("\(path)/\(sub)")
                }
            }
        }
        // Running apps installed elsewhere (e.g. inside ~/Downloads).
        for app in RunningApps.regular {
            if let path = app.bundleURL?.path { add(path) }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Running state of a single app item (preview and Touch Bar share it).
struct AppItemState {
    let isRunning: Bool
    let badge: String?
    let isFrontmost: Bool

    static func of(path: String) -> AppItemState {
        if DemoMode.isActive {
            return AppItemState(isRunning: true, badge: DemoMode.badges[path], isFrontmost: path == DemoMode.frontmostPath)
        }
        let app = RunningApps.app(atPath: path)
        return AppItemState(isRunning: app != nil, badge: AppBadges.label(for: app), isFrontmost: RunningApps.isFrontmost(app))
    }
}

/// Fixed, privacy-friendly content for README screenshots (`--export-screenshots`).
enum DemoMode {
    static var isActive = false
    static var frontmostPath = "/Applications/Safari.app"
    static var badges: [String: String] = [
        "/System/Applications/Mail.app": "3",
        "/System/Applications/Messages.app": "12",
        "/System/Applications/App Store.app": "2",
    ]

    static var appPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Mail.app",
            "/System/Applications/Messages.app", "\(home)/Applications/YouTube.app", "/System/Applications/Music.app",
            "/System/Applications/Photos.app", "/System/Applications/Notes.app", "/System/Applications/Calendar.app",
            "/Applications/Xcode.app", "/System/Applications/App Store.app", "/System/Applications/System Settings.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }
}
