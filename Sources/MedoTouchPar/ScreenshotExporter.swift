import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `MedoTouchPar --export-screenshots <dir>` renders the README images from the
/// real views in Demo Mode (fixed Apple apps, sample badges, no user data).
enum ScreenshotExporter {
    static func run(to directory: URL) {
        DemoMode.isActive = true
        // A regular app may activate itself, so captured controls render as active.
        NSApp.setActivationPolicy(.regular)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = ConfigStore(demo: demoConfig)
        let strip = ControlStripStore(demoMini: ["com.apple.system.brightness", "com.apple.system.volume",
                                                 "com.apple.system.mute", "com.apple.system.screencapture"],
                                      demoFull: ControlStripStore.appleDefaultFull)
        defer { NSApp.setActivationPolicy(.accessory) }
        let dockID = store.config.items.first { $0.kind == .dock }?.id

        for (language, suffix) in [(AppLanguage.english, "en"), (.arabic, "ar")] {
            L10n.language = language
            store.config.language = language
            for tab in CustomizerTab.allCases {
                let view = WindowChrome(title: L("MedoTouchPar — Touch Bar customizer", "MedoTouchPar — تخصيص شريط اللمس")) {
                    CustomizerView(initialTab: tab, initialSelection: tab == .items ? dockID : nil, showBar: {})
                        .environmentObject(store)
                        .environmentObject(strip)
                }
                save(render(view, size: NSSize(width: 1180, height: 820)), to: directory, name: "customizer-\(tab.rawValue)-\(suffix).png")
            }
        }

        L10n.language = .english
        save(render(touchBar(store, strip, hideStrip: false), size: NSSize(width: 1060, height: 92)), to: directory, name: "touchbar.png")
        save(render(Banner(store: store, strip: strip), size: NSSize(width: 1280, height: 640)), to: directory, name: "banner.png")
        writeGIF(store: store, strip: strip, to: directory.appendingPathComponent("touchbar.gif"))
        print("exported to \(directory.path)")
    }

    private static var demoConfig: AppConfig {
        var config = AppConfig()
        var messages = TBItem(kind: .app)
        messages.actionValue = "/System/Applications/Messages.app"
        messages.iconSize = 28
        messages.tileWidth = 42
        messages.showRunningDot = false
        var dock = TBItem(kind: .dock)
        dock.width = 330
        config.items = [TBItem(kind: .hideBar), messages, dock, TBItem(kind: .flexibleSpace),
                        TBItem(kind: .media), TBItem(kind: .battery), TBItem(kind: .clock)]
        return config
    }

    private static func touchBar(_ store: ConfigStore, _ strip: ControlStripStore, hideStrip: Bool) -> some View {
        TouchBarPreview(items: store.config.items, controlStrip: strip.mini, hideControlStrip: hideStrip, showsUsage: false, selection: .constant(nil))
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.09))
    }

    // MARK: Rendering

    static func render<V: View>(_ view: V, size: NSSize) -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = KeyableWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        // A key window renders controls active (accent colors, not inactive gray).
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    private static func save(_ rep: NSBitmapImageRep, to directory: URL, name: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
    }

    /// Short loop: the active app moves along the Dock while badges change.
    private static func writeGIF(store: ConfigStore, strip: ControlStripStore, to url: URL) {
        let paths = DemoMode.appPaths
        let frames: [(String, [String: String])] = [
            ("/Applications/Safari.app", ["/System/Applications/Mail.app": "3", "/System/Applications/Messages.app": "12"]),
            ("/System/Applications/Mail.app", ["/System/Applications/Messages.app": "12"]),
            ("/System/Applications/Messages.app", ["/System/Applications/App Store.app": "1"]),
            ("/System/Applications/Music.app", ["/System/Applications/Mail.app": "1", "/System/Applications/App Store.app": "1"]),
            ("/Applications/Xcode.app", ["/System/Applications/Mail.app": "4", "/System/Applications/Messages.app": "2"]),
        ].filter { paths.contains($0.0) }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (front, badges) in frames {
            DemoMode.frontmostPath = front
            DemoMode.badges = badges
            let rep = render(touchBar(store, strip, hideStrip: false), size: NSSize(width: 1060, height: 92))
            if let image = rep.cgImage {
                CGImageDestinationAddImage(destination, image,
                                           [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.1]] as CFDictionary)
            }
        }
        CGImageDestinationFinalize(destination)
    }
}

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// macOS-style window frame (traffic lights + title) around a screenshot.
private struct WindowChrome<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color(white: 0.17))
            content
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.12)))
        .padding(30)
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// 1280×640 GitHub social / README banner.
private struct Banner: View {
    let store: ConfigStore
    let strip: ControlStripStore

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.13), Color(red: 0.11, green: 0.16, blue: 0.38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1).opacity(0.35), .clear],
                           center: .init(x: 0.5, y: 0.78), startRadius: 10, endRadius: 520)
            VStack(spacing: 34) {
                HStack(spacing: 30) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 168, height: 168)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MedoTouchPar")
                            .font(.system(size: 66, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Your Touch Bar. Your apps. Your way.")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 10) {
                            pill("Free", "gift.fill")
                            pill("Open source", "chevron.left.forwardslash.chevron.right")
                            pill("Fully customizable", "slider.horizontal.3")
                            pill("English · العربية", "globe")
                        }
                        .padding(.top, 6)
                    }
                }
                TouchBarPreview(items: store.config.items, controlStrip: strip.mini, hideControlStrip: false, showsUsage: false, selection: .constant(nil))
                    .frame(width: 1004)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55)))
                Text("Made by Moath Alhakeem")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func pill(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}
