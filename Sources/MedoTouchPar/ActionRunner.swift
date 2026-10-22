import AppKit

enum ActionRunner {
    static func run(_ item: TBItem) {
        switch item.actionType {
        case .none:
            break
        case .shortcut:
            if let shortcut = item.shortcut { KeySender.press(shortcut) }
        case .openApp:
            guard !item.actionValue.isEmpty else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.actionValue),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .openURL:
            if let url = URL(string: item.actionValue) { NSWorkspace.shared.open(url) }
        case .shell:
            runShell(item.actionValue)
        case .mediaKey:
            if let key = MediaKey(rawValue: item.actionValue) { KeySender.media(key) }
        case .system:
            if let action = SystemAction(rawValue: item.actionValue) { run(action) }
        }
    }

    static func run(_ action: SystemAction) {
        switch action {
        case .lockScreen:
            KeySender.press(keyCode: 12, flags: [.maskControl, .maskCommand]) // ⌃⌘Q
        case .sleepDisplay:
            runShell("/usr/bin/pmset displaysleepnow")
        case .missionControl:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .screenshot:
            KeySender.press(keyCode: 23, flags: [.maskShift, .maskCommand]) // ⇧⌘5
        case .spotlight:
            KeySender.press(keyCode: 49, flags: [.maskCommand]) // ⌘Space
        case .showDesktop:
            KeySender.press(keyCode: 103, flags: [.maskSecondaryFn]) // F11
        case .emojiPicker:
            KeySender.press(keyCode: 49, flags: [.maskControl, .maskCommand]) // ⌃⌘Space
        }
    }

    static func runShell(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
