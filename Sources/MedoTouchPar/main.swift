import AppKit
import ServiceManagement

let arguments = CommandLine.arguments

// AppKit reads the language before NSApplication exists.
if let data = try? Data(contentsOf: ConfigStore.fileURL),
   let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
    L10n.applyToAppKit(saved.language)
}
let app = NSApplication.shared

if arguments.contains("--register-login-item") {
    // Used by build.sh: registers the installed bundle as a login item.
    do {
        try SMAppService.mainApp.register()
    } catch {
        print("login item: \(error.localizedDescription)")
    }
    print("login item status: \(SMAppService.mainApp.status == .enabled ? "enabled" : "\(SMAppService.mainApp.status.rawValue)")")
    exit(0)
}

if let index = arguments.firstIndex(of: "--export-screenshots"), arguments.indices.contains(index + 1) {
    app.setActivationPolicy(.accessory)
    ScreenshotExporter.run(to: URL(fileURLWithPath: arguments[index + 1]))
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
