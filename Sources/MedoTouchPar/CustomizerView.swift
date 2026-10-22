import ServiceManagement
import SwiftUI

enum CustomizerTab: String, CaseIterable, Identifiable {
    case items, system, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .items: return L("My Items", "عناصري")
        case .system: return L("System Items", "عناصر النظام")
        case .settings: return L("Settings", "الإعدادات")
        }
    }
}

struct CustomizerView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var controlStrip: ControlStripStore
    @State private var tab: CustomizerTab
    @State private var selection: UUID?
    let showBar: () -> Void

    init(initialTab: CustomizerTab, initialSelection: UUID? = nil, showBar: @escaping () -> Void) {
        _tab = State(initialValue: initialTab)
        _selection = State(initialValue: initialSelection)
        self.showBar = showBar
    }

    var body: some View {
        VStack(spacing: 0) {
            TouchBarPreview(items: store.config.items,
                            controlStrip: controlStrip.mini,
                            hideControlStrip: store.config.hideControlStrip,
                            includeFinder: store.config.showFinderInDock,
                            selection: Binding(get: { selection }, set: { selection = $0; tab = .items }))
                .padding(14)

            TabSwitcher(tab: $tab)
                .padding(.bottom, 10)

            Divider()
            Group {
                switch tab {
                case .items: ItemsTab(selection: $selection)
                case .system: SystemItemsTab()
                case .settings: SettingsTab(showBar: showBar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(L("MedoTouchPar runs in the background — close this window any time; it lives in the menu bar.",
                       "MedoTouchPar يعمل في الخلفية — أغلق هذه النافذة بأمان، وستجد أيقونته في شريط القوائم أعلى الشاشة."))
                Spacer()
                Text(AppInfo.madeBy).fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 1060, minHeight: 680)
        .environment(\.layoutDirection, L10n.layoutDirection)
        .environment(\.locale, L10n.locale)
        // Rebuild every string when the language changes.
        .id(store.config.language)
        .onReceive(NotificationCenter.default.publisher(for: .selectCustomizerTab)) { note in
            if let tab = note.object as? CustomizerTab { self.tab = tab }
        }
    }
}

/// Segmented tabs drawn in SwiftUI: the AppKit segmented control follows the
/// system's text direction instead of the app language.
private struct TabSwitcher: View {
    @Binding var tab: CustomizerTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CustomizerTab.allCases) { item in
                Button { tab = item } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 120)
                        .padding(.vertical, 5)
                        .foregroundStyle(tab == item ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tab == item ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
    }
}

// MARK: - My items

private struct ItemsTab: View {
    @EnvironmentObject var store: ConfigStore
    @Binding var selection: UUID?
    @State private var showingAppPicker = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.config.items) { item in
                        row(for: item)
                            .tag(item.id)
                            .contextMenu {
                                Button(L("Duplicate", "تكرار")) { duplicate(item.id) }
                                Button(L("Move left", "تحريك لليسار")) { move(item.id, by: -1) }
                                Button(L("Move right", "تحريك لليمين")) { move(item.id, by: 1) }
                                Divider()
                                Button(L("Remove", "حذف"), role: .destructive) { delete(item.id) }
                            }
                    }
                    .onMove { store.config.items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { store.config.items.remove(atOffsets: $0) }
                }
                .onDeleteCommand { if let id = selection { delete(id) } }

                toolbar
            }
            .frame(width: 320)

            Divider()

            if let id = selection, store.config.items.contains(where: { $0.id == id }) {
                ItemEditor(item: binding(for: id),
                           onDelete: { delete(id) },
                           onDuplicate: { duplicate(id) })
                    .id(id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "hand.tap").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("Select an item in the list or in the preview to edit it.",
                           "اختر عنصرًا من القائمة أو من المعاينة لتعديله."))
                    Text(L("List order = left-to-right order on the bar. Drag to reorder; press Delete or right-click to remove.",
                           "الترتيب في القائمة = الترتيب على الشريط من اليسار لليمين. اسحب لإعادة الترتيب، وزر Delete أو كليك يمين للحذف."))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ItemKind.allCases) { kind in
                        Button { add(TBItem(kind: kind)) } label: { Label(kind.displayName, systemImage: kind.defaultSymbol) }
                    }
                } label: {
                    Label(L("Add item", "إضافة عنصر"), systemImage: "plus")
                }
                .fixedSize()

                Button { showingAppPicker = true } label: {
                    Label(L("Add apps", "إضافة تطبيقات"), systemImage: "app.badge")
                }
                .popover(isPresented: $showingAppPicker, arrowEdge: .top) {
                    AppPickerList(isPresented: $showingAppPicker, allowsMultiple: true) { app in
                        var item = TBItem(kind: .app)
                        item.actionValue = app.path
                        add(item)
                    }
                }

                Button(role: .destructive) {
                    if let id = selection { delete(id) }
                } label: {
                    Label(L("Remove", "حذف"), systemImage: "trash")
                }
                .disabled(selection == nil)
            }
            HStack(spacing: 8) {
                Button { if let id = selection { move(id, by: -1) } } label: { Label(L("Left", "لليسار"), systemImage: "arrow.up") }
                    .disabled(selection == nil)
                Button { if let id = selection { move(id, by: 1) } } label: { Label(L("Right", "لليمين"), systemImage: "arrow.down") }
                    .disabled(selection == nil)
                Spacer()
                Button(L("Defaults", "الافتراضي")) {
                    store.resetToDefaults()
                    selection = nil
                }
            }
        }
        .controlSize(.small)
        .padding(10)
    }

    @ViewBuilder private func row(for item: TBItem) -> some View {
        Label {
            Text(item.summary)
        } icon: {
            if item.kind == .app, !item.actionValue.isEmpty {
                AppIconImage(path: item.actionValue, side: 18)
            } else {
                Image(systemName: item.kind == .button && !item.symbol.isEmpty ? item.symbol : item.kind.defaultSymbol)
            }
        }
    }

    private func binding(for id: UUID) -> Binding<TBItem> {
        Binding(
            get: { store.config.items.first { $0.id == id } ?? TBItem(kind: .spacer) },
            set: { newValue in
                if let index = store.config.items.firstIndex(where: { $0.id == id }) {
                    store.config.items[index] = newValue
                }
            })
    }

    private func add(_ item: TBItem) {
        if let id = selection, let index = store.config.items.firstIndex(where: { $0.id == id }) {
            store.config.items.insert(item, at: index + 1)
        } else {
            store.config.items.append(item)
        }
        selection = item.id
    }

    private func delete(_ id: UUID) {
        guard let index = store.config.items.firstIndex(where: { $0.id == id }) else { return }
        store.config.items.remove(at: index)
        let items = store.config.items
        selection = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }

    private func duplicate(_ id: UUID) {
        guard let index = store.config.items.firstIndex(where: { $0.id == id }) else { return }
        var copy = store.config.items[index]
        copy.id = UUID()
        store.config.items.insert(copy, at: index + 1)
        selection = copy.id
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = store.config.items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard store.config.items.indices.contains(target) else { return }
        store.config.items.swapAt(index, target)
    }
}

// MARK: - System items (Control Strip)

private struct SystemItemsTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var strip: ControlStripStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("These are macOS's own buttons (brightness, volume, screenshot…). Remove the ones you don't want, add others or keep them as they are, then press Apply.",
                   "هذه عناصر macOS نفسه (السطوع، الصوت، لقطة الشاشة…). احذف ما لا تريده أو أضف غيره أو اتركها كما هي، ثم اضغط «تطبيق»."))
                .foregroundStyle(.secondary)

            Toggle(L("Hide the system items completely (the whole bar is mine)",
                     "إخفاء عناصر النظام بالكامل (يصبح الشريط كله لعناصري)"), isOn: $store.config.hideControlStrip)

            HStack(alignment: .top, spacing: 18) {
                StripColumn(title: L("Collapsed strip — always next to your items", "الشريط المختصر — يظهر دائمًا يمين عناصرك"),
                            note: L("4 items or fewer works best", "يُفضّل 4 عناصر أو أقل"),
                            ids: $strip.mini, forFull: false)
                StripColumn(title: L("Expanded strip — after tapping the ‹ arrow", "الشريط الموسّع — يظهر عند لمس السهم ‹"),
                            note: L("Accepts groups (brightness row, volume row…)", "يقبل المجموعات (شريط السطوع، الصوت…)"),
                            ids: $strip.full, forFull: true)
            }
            .disabled(store.config.hideControlStrip)
            .opacity(store.config.hideControlStrip ? 0.45 : 1)

            HStack {
                Button(L("Apply changes", "تطبيق التغييرات")) { strip.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!strip.hasPendingChanges)
                Button(L("Revert", "تراجع")) { strip.reload() }
                    .disabled(!strip.hasPendingChanges)
                Spacer()
                if strip.hasBackup {
                    Button(L("Restore my original setup", "استرجاع إعدادي الأصلي")) { strip.restoreBackup() }
                }
                Button(L("Apple defaults", "إعداد Apple الافتراضي")) { strip.useAppleDefaults() }
            }
        }
        .padding(18)
    }
}

private struct StripColumn: View {
    @EnvironmentObject var strip: ControlStripStore
    let title: String
    let note: String
    @Binding var ids: [String]
    let forFull: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(note).font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(ids, id: \.self) { id in
                    let info = ControlStripStore.info(for: id)
                    HStack {
                        Image(systemName: info.symbol).frame(width: 22)
                        Text(info.name)
                        Spacer()
                        Button {
                            ids.removeAll { $0 == id }
                            strip.markChanged()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help(L("Remove from the bar", "حذف من الشريط"))
                    }
                }
                .onMove { from, to in
                    ids.move(fromOffsets: from, toOffset: to)
                    strip.markChanged()
                }
            }
            .frame(minHeight: 250)
            Menu {
                ForEach(strip.available(forFull: forFull)) { info in
                    Button {
                        ids.append(info.id)
                        strip.markChanged()
                    } label: {
                        Label(info.name, systemImage: info.symbol)
                    }
                }
            } label: {
                Label(L("Add system item", "إضافة عنصر نظام"), systemImage: "plus")
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Settings

private struct SettingsTab: View {
    @EnvironmentObject var store: ConfigStore
    let showBar: () -> Void
    @State private var trusted = KeySender.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section(L("General", "عام")) {
                Picker(L("Language", "اللغة"), selection: $store.config.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle(L("Enable the MedoTouchPar bar", "تفعيل شريط MedoTouchPar"), isOn: $store.config.enabled)
                Toggle(L("Launch at login", "التشغيل تلقائيًا عند تسجيل الدخول"),
                       isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Toggle(L("Show icon in the menu bar", "إظهار الأيقونة في شريط القوائم"), isOn: $store.config.showMenuBarIcon)
                if !store.config.showMenuBarIcon {
                    Text(L("Open MedoTouchPar again from Applications or Spotlight to get back here.",
                           "افتح MedoTouchPar مرة أخرى من التطبيقات أو Spotlight للرجوع لهذه النافذة."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L("Touch Bar behavior", "سلوك شريط اللمس")) {
                Toggle(L("Restore my bar automatically after Touch ID, lock, sleep or fn",
                         "إرجاع شريطي تلقائيًا بعد البصمة أو القفل أو السكون أو fn"), isOn: $store.config.autoRestore)
                Toggle(L("After ✕ or the hide button, bring my bar back when I switch apps",
                         "بعد ✕ أو زر الإخفاء، يرجع شريطي عند الانتقال لتطبيق آخر"), isOn: $store.config.returnAfterAppSwitch)
                Toggle(L("Hide the system items (Control Strip)", "إخفاء عناصر النظام (Control Strip)"),
                       isOn: $store.config.hideControlStrip)
                Button(L("Show the bar now", "إظهار الشريط الآن"), action: showBar)
            }

            Section(L("Apps & Dock", "التطبيقات والـ Dock")) {
                Picker(L("Badge refresh", "تحديث عدد الإشعارات"), selection: $store.config.refreshInterval) {
                    Text(L("Every second", "كل ثانية")).tag(1.0)
                    Text(L("Every 2 seconds (recommended)", "كل ثانيتين (موصى به)")).tag(2.0)
                    Text(L("Every 5 seconds (saves battery)", "كل 5 ثوانٍ (توفير البطارية)")).tag(5.0)
                }
                Toggle(L("Show Finder in the Dock item", "إظهار Finder في الـ Dock"), isOn: $store.config.showFinderInDock)
                Text(L("Opening, quitting and switching apps always update instantly.",
                       "فتح التطبيقات وإغلاقها والتنقل بينها يتحدث فورًا دائمًا."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Permissions", "الصلاحيات")) {
                if trusted {
                    Label(L("Accessibility permission granted", "صلاحية Accessibility مفعلة"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(L("Needed for shortcut, media and lock buttons", "مطلوبة لأزرار الاختصارات والوسائط وقفل الشاشة"),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button(L("Grant Accessibility…", "منح صلاحية Accessibility…")) { KeySender.requestTrust() }
                }
            }

            Section(L("About", "حول")) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MedoTouchPar").font(.title2.bold())
                        Text(L("Version \(AppInfo.version) · Free & open source (MIT)",
                               "الإصدار \(AppInfo.version) · مجاني ومفتوح المصدر (MIT)"))
                            .foregroundStyle(.secondary)
                        Text(AppInfo.madeBy).fontWeight(.semibold)
                    }
                    Spacer()
                    Link(destination: AppInfo.repository) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = KeySender.isTrusted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
