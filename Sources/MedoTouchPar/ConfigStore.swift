import Combine
import Foundation

/// Persists AppConfig as JSON in ~/Library/Application Support/MedoTouchPar.
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig

    private var cancellable: AnyCancellable?

    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MedoTouchPar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Settings of the earlier "TouchBar Studio" build, imported once.
    private static var legacyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchBarStudio/config.json")
    }

    private(set) var isFirstLaunch = false
    private var persists = true

    /// In-memory store for screenshot export; never touches the user's file.
    init(demo config: AppConfig) {
        self.config = config
        persists = false
    }

    init() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.fileURL.path) {
            isFirstLaunch = true
            if fm.fileExists(atPath: Self.legacyFileURL.path) {
                try? fm.copyItem(at: Self.legacyFileURL, to: Self.fileURL)
            }
        }
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = saved
        } else {
            config = AppConfig()
        }
        cancellable = $config
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    func save() {
        guard persists else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func resetToDefaults() {
        config.items = AppConfig.defaultItems
    }
}
