import SwiftUI

struct ItemEditor: View {
    @Binding var item: TBItem
    var onDelete: () -> Void
    var onDuplicate: () -> Void
    @State private var showSymbols = false

    private var hasTitle: Bool { [.escape, .button, .hideBar].contains(item.kind) }
    private var hasSymbol: Bool { [.escape, .button, .hideBar, .clock].contains(item.kind) }
    private var hasColor: Bool { [.escape, .button, .hideBar, .clock, .battery].contains(item.kind) }
    private var hasWidth: Bool { ![.spacer, .flexibleSpace, .app].contains(item.kind) }

    var body: some View {
        Form {
            Section(L("Item", "العنصر")) {
                Picker(L("Type", "النوع"), selection: $item.kind) {
                    ForEach(ItemKind.allCases) { Text($0.displayName).tag($0) }
                }
                if hasTitle {
                    TextField(L("Text", "النص"), text: $item.title,
                              prompt: Text(L("Leave empty to show only the icon", "اتركه فارغًا لإظهار الأيقونة فقط")))
                }
                if hasSymbol {
                    HStack {
                        TextField(L("SF Symbol icon", "أيقونة SF Symbol"), text: $item.symbol,
                                  prompt: Text(L("e.g. star.fill", "مثال: star.fill")))
                        Image(systemName: item.symbol.isEmpty ? "questionmark" : item.symbol)
                            .frame(width: 24)
                        Button(L("Choose…", "اختر…")) { showSymbols.toggle() }
                            .popover(isPresented: $showSymbols) {
                                SymbolGrid(symbol: $item.symbol)
                            }
                    }
                }
                if hasColor {
                    Toggle(L("Background color", "لون خلفية"), isOn: Binding(
                        get: { item.colorHex != nil },
                        set: { item.colorHex = $0 ? (item.colorHex ?? "#0A84FF") : nil }))
                    if item.colorHex != nil {
                        ColorPicker(L("Color", "اللون"), selection: Binding(
                            get: { Color(nsColor: NSColor(hex: item.colorHex ?? "") ?? .systemBlue) },
                            set: { item.colorHex = NSColor($0).hexString }),
                            supportsOpacity: false)
                    }
                }
                if hasWidth {
                    Toggle(item.kind == .dock ? L("Limit Dock width", "تحديد أقصى عرض للـ Dock") : L("Fixed width", "عرض ثابت"),
                           isOn: Binding(
                            get: { item.width != nil },
                            set: { item.width = $0 ? (item.width ?? (item.kind == .dock ? 360 : 100)) : nil }))
                    if let width = item.width {
                        LabeledSlider(value: Binding(get: { width }, set: { item.width = $0.rounded() }),
                                      range: 30...(item.kind == .dock ? 900 : 400), unit: "pt")
                    }
                }
            }

            if item.kind == .app {
                Section(L("App", "التطبيق")) {
                    AppPickerField(path: $item.actionValue)
                    Text(L("Tapping opens the app, or switches to it if it is already open — exactly like the Dock.",
                           "اللمس يفتح التطبيق أو ينقلك إليه إن كان مفتوحًا — مثل الـ Dock تمامًا."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if item.kind == .dock {
                Section("Dock") {
                    Toggle(L("Also show apps pinned in the Dock (not only open ones)",
                             "إظهار التطبيقات المثبتة في Dock أيضًا (وليس المفتوحة فقط)"), isOn: $item.dockIncludePinned)
                    Text(L("Updates instantly when any app opens or quits, including web apps such as YouTube. Swipe the Touch Bar to scroll when there are many apps.",
                           "يتحدث فورًا عند فتح أو إغلاق أي تطبيق، ويشمل تطبيقات الويب مثل YouTube. إذا كثرت التطبيقات اسحب بإصبعك على الشريط للتمرير."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if item.kind.showsAppTiles {
                Section(L("Icon style", "شكل الأيقونات")) {
                    Toggle(L("Show notification badges (red circle)", "إظهار عدد الإشعارات (الدائرة الحمراء)"), isOn: $item.showBadge)
                    Toggle(L("Show the white dot under running apps", "إظهار النقطة البيضاء أسفل التطبيقات المفتوحة"), isOn: $item.showRunningDot)
                    Toggle(L("Gray background behind the active app", "خلفية رمادية خلف التطبيق النشط"), isOn: $item.highlightActive)
                    LabeledContent(L("Icon size", "حجم الأيقونة")) {
                        LabeledSlider(value: $item.iconSize, range: 16...30, unit: "pt")
                    }
                    LabeledContent(L("Space per app", "المساحة لكل تطبيق")) {
                        LabeledSlider(value: $item.tileWidth, range: 24...80, unit: "pt")
                    }
                    HStack {
                        Text(L("Presets:", "قوالب جاهزة:"))
                        Button(L("Small", "صغير")) { setTiles(icon: 22, width: 32, dot: true) }
                        Button(L("Regular", "عادي")) { setTiles(icon: 26, width: 38, dot: true) }
                        Button(L("Icon only (large)", "أيقونة فقط (كبير)")) {
                            setTiles(icon: 30, width: 44, dot: false)
                            item.highlightActive = false
                        }
                    }
                }
            }

            if item.kind == .clock {
                Section(L("Clock", "الساعة")) {
                    TextField(L("Time format", "صيغة الوقت"), text: $item.clockFormat)
                    Text(L("Examples: HH:mm  ·  h:mm a  ·  EEE d MMM  HH:mm", "أمثلة: HH:mm  ·  h:mm a  ·  EEE d MMM  HH:mm"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if item.kind.supportsAction {
                Section(L("On tap", "عند اللمس")) {
                    Picker(L("Action", "الإجراء"), selection: $item.actionType) {
                        ForEach(ActionType.allCases) { Text($0.displayName).tag($0) }
                    }
                    actionFields
                }
            }

            if item.kind == .hideBar {
                Section {
                    Text(L("Hides your bar and shows the current app's own Touch Bar. It comes back when you switch apps, or tap the MedoTouchPar icon in the Control Strip.",
                           "يخفي شريطك ويعرض شريط التطبيق الحالي. يرجع عند الانتقال لتطبيق آخر، أو بلمس أيقونة MedoTouchPar في Control Strip."))
                        .foregroundStyle(.secondary)
                }
            }
            if item.kind == .media {
                Section {
                    Text(L("Three buttons: previous · play/pause · next — works with Music, Spotify and YouTube.",
                           "ثلاثة أزرار: السابق · تشغيل/إيقاف · التالي — تعمل مع Music و Spotify و YouTube."))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button(role: .destructive, action: onDelete) {
                        Label(L("Remove this item from the bar", "حذف هذا العنصر من الشريط"), systemImage: "trash")
                    }
                    Spacer()
                    Button(action: onDuplicate) {
                        Label(L("Duplicate", "تكرار"), systemImage: "plus.square.on.square")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: item.kind) { kind in
            // actionValue holds an app path for .app; drop leftovers like "lockScreen".
            if kind == .app, !item.actionValue.hasPrefix("/") { item.actionValue = "" }
        }
        .onChange(of: item.actionType) { type in
            switch type {
            case .mediaKey where MediaKey(rawValue: item.actionValue) == nil:
                item.actionValue = MediaKey.playPause.rawValue
            case .system where SystemAction(rawValue: item.actionValue) == nil:
                item.actionValue = SystemAction.lockScreen.rawValue
            case .openApp, .openURL, .shell:
                if MediaKey(rawValue: item.actionValue) != nil || SystemAction(rawValue: item.actionValue) != nil {
                    item.actionValue = ""
                }
            default:
                break
            }
        }
    }

    private func setTiles(icon: Double, width: Double, dot: Bool) {
        item.iconSize = icon
        item.tileWidth = width
        item.showRunningDot = dot
    }

    @ViewBuilder private var actionFields: some View {
        switch item.actionType {
        case .none:
            EmptyView()
        case .shortcut:
            ShortcutRecorder(shortcut: $item.shortcut)
        case .openApp:
            AppPickerField(path: $item.actionValue)
        case .openURL:
            TextField(L("URL", "الرابط"), text: $item.actionValue, prompt: Text("https://…"))
        case .shell:
            TextEditor(text: $item.actionValue)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70)
                .environment(\.layoutDirection, .leftToRight)
        case .mediaKey:
            Picker(L("Key", "المفتاح"), selection: $item.actionValue) {
                ForEach(MediaKey.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
        case .system:
            Picker(L("Action", "الإجراء"), selection: $item.actionValue) {
                ForEach(SystemAction.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
        }
    }
}

struct LabeledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = ""

    var body: some View {
        HStack {
            Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
            Text("\(Int(value)) \(unit)").monospacedDigit().frame(width: 56)
        }
    }
}

// MARK: - Shortcut recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(recording ? L("Press the shortcut now…", "اضغط الاختصار الآن…") : (shortcut?.display ?? L("None", "لا يوجد")))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                .environment(\.layoutDirection, .leftToRight)
            Spacer()
            Button(recording ? L("Cancel", "إلغاء") : L("Record", "تسجيل")) { recording ? stop() : start() }
            if shortcut != nil, !recording {
                Button(L("Clear", "مسح")) { shortcut = nil }
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53, mods.isEmpty { // plain Esc cancels
                stop()
                return nil
            }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue,
                                display: Self.describe(keyCode: event.keyCode, modifiers: mods, characters: event.charactersIgnoringModifiers))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func describe(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let named: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "esc", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return text + (named[keyCode] ?? (characters ?? "?").uppercased())
    }
}

// MARK: - Symbol grid

struct SymbolGrid: View {
    @Binding var symbol: String
    @Environment(\.dismiss) private var dismiss

    private static let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "house.fill", "gearshape.fill",
        "magnifyingglass", "lock.fill", "camera.viewfinder", "terminal.fill", "globe", "safari",
        "folder.fill", "doc.fill", "trash.fill", "envelope.fill", "message.fill", "phone.fill",
        "music.note", "play.fill", "pause.fill", "playpause.fill", "backward.fill", "forward.fill",
        "speaker.wave.2.fill", "speaker.slash.fill", "mic.fill", "sun.max.fill", "moon.fill", "keyboard",
        "rectangle.3.group", "macwindow", "square.grid.2x2.fill", "display", "wifi", "power",
        "clock", "calendar", "alarm", "timer", "bell.fill", "bookmark.fill",
        "doc.on.clipboard", "scissors", "paintbrush.fill", "hammer.fill", "chevron.down.circle.fill", "face.smiling",
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                ForEach(Self.symbols, id: \.self) { name in
                    Button {
                        symbol = name
                        dismiss()
                    } label: {
                        Image(systemName: name)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(name == symbol ? Color.accentColor.opacity(0.3) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
            .padding(10)
        }
        .frame(width: 270, height: 300)
    }
}
