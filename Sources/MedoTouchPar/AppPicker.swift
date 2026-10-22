import SwiftUI
import UniformTypeIdentifiers

struct AppIconImage: View {
    let path: String
    var side: CGFloat = 20

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: side, height: side)
    }
}

struct AppPickerField: View {
    @Binding var path: String
    @State private var showingList = false

    var body: some View {
        HStack {
            if path.isEmpty {
                Text(L("No app chosen", "لم يتم اختيار تطبيق")).foregroundStyle(.secondary)
            } else {
                AppIconImage(path: path, side: 24)
                Text(AppCatalog.displayName(atPath: path))
            }
            Spacer()
            Button(L("Choose app…", "اختر تطبيق…")) { showingList = true }
                .popover(isPresented: $showingList, arrowEdge: .bottom) {
                    AppPickerList(isPresented: $showingList) { path = $0.path }
                }
        }
    }
}

/// Searchable list of installed apps, including Safari/Chrome web apps.
struct AppPickerList: View {
    @Binding var isPresented: Bool
    var allowsMultiple = false
    var onPick: (InstalledApp) -> Void
    @State private var query = ""
    @State private var apps: [InstalledApp] = []
    @State private var picked = Set<String>()

    private var filtered: [InstalledApp] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField(L("Search apps…", "ابحث عن تطبيق…"), text: $query)
                .textFieldStyle(.roundedBorder)
            List(filtered) { app in
                Button {
                    if allowsMultiple {
                        if picked.insert(app.path).inserted { onPick(app) }
                    } else {
                        onPick(app)
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        AppIconImage(path: app.path, side: 22)
                        Text(app.name)
                        if app.isWebApp {
                            Text(L("Web", "ويب"))
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        }
                        Spacer()
                        if picked.contains(app.path) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button(L("Choose in Finder…", "اختيار من Finder…")) {
                    isPresented = false
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url {
                        onPick(InstalledApp(name: AppCatalog.displayName(atPath: url.path), path: url.path, isWebApp: false))
                    }
                }
                Spacer()
                if allowsMultiple {
                    Button(L("Done", "تم")) { isPresented = false }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(10)
        .frame(width: 360, height: 460)
        .onAppear { if apps.isEmpty { apps = AppCatalog.scan() } }
    }
}
