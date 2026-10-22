import AppKit

/// Opt-in diagnostics: `defaults write com.medo.MedoTouchPar DebugLog -bool YES`
/// writes to ~/Library/Logs/MedoTouchPar/debug.log.
enum DebugLog {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "DebugLog") }

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MedoTouchPar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message())\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: fileURL)
        }
    }

    static func describe(_ view: NSView?) -> String {
        guard let view else { return "view=nil" }
        var hiddenAncestor = false
        var cursor: NSView? = view
        while let v = cursor { if v.isHidden { hiddenAncestor = true }; cursor = v.superview }
        var chain: [String] = []
        cursor = view.superview
        while let v = cursor, chain.count < 8 {
            chain.append("\(type(of: v))\(v.isHidden ? "[H]" : "")\(NSStringFromRect(v.frame))")
            cursor = v.superview
        }
        return "\(type(of: view)) frame=\(NSStringFromRect(view.frame)) window=\(view.window.map { "\(type(of: $0))" } ?? "nil") hiddenChain=\(hiddenAncestor) alpha=\(view.alphaValue) chain=\(chain.joined(separator: " > "))"
    }
}
