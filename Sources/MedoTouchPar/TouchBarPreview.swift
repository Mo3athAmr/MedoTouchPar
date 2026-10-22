import SwiftUI

/// Life-size preview of the whole Touch Bar: the user's items on the left and
/// the system Control Strip on the right, with an overflow warning.
struct TouchBarPreview: View {
    let items: [TBItem]
    let controlStrip: [String]
    let hideControlStrip: Bool
    var includeFinder = true
    var showsUsage = true
    @Binding var selection: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let stripWidth = hideControlStrip ? 0 : TouchBarGeometry.controlStripWidth(itemCount: controlStrip.count)
            let available = TouchBarGeometry.totalWidth - 2 * TouchBarGeometry.edgeMargin
                - (hideControlStrip ? 0 : stripWidth + TouchBarGeometry.itemSpacing)
            let used = items.reduce(0) { $0 + estimatedWidth(of: $1) }
                + TouchBarGeometry.itemSpacing * CGFloat(max(items.count - 1, 0))
            let overflow = used > available

            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TouchBarGeometry.itemSpacing) {
                        HStack(spacing: TouchBarGeometry.itemSpacing) {
                            ForEach(items) { item in
                                chip(for: item)
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.accentColor, lineWidth: selection == item.id ? 2 : 0))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selection = item.id }
                            }
                        }
                        .frame(width: available, alignment: .leading)
                        .clipped()
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.red.opacity(overflow ? 0.9 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [4])))

                        if !hideControlStrip {
                            controlStripView(width: stripWidth)
                        }
                    }
                    .padding(.horizontal, TouchBarGeometry.edgeMargin)
                    .frame(width: TouchBarGeometry.totalWidth, height: 44)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black))
                }
                .environment(\.layoutDirection, .leftToRight)

                if showsUsage {
                HStack(spacing: 6) {
                    Image(systemName: overflow ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(overflow ? .red : .green)
                    Text(L("Space used: \(Int(used)) of \(Int(available)) pt", "المساحة المستخدمة \(Int(used)) من \(Int(available)) نقطة"))
                        .monospacedDigit()
                    if overflow {
                        Text(L("— items are wider than the bar, so macOS will hide some. Narrow them, remove items or hide the Control Strip.", "— العناصر أعرض من الشريط وسيخفي النظام بعضها. صغّر العرض أو احذف عناصر أو أخفِ Control Strip."))
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                }
            }
        }
    }

    private func estimatedWidth(of item: TBItem) -> CGFloat {
        let count = item.kind == .dock ? dockEntries(for: item).count : 0
        return item.estimatedWidth(dockCount: count)
    }

    private func dockEntries(for item: TBItem) -> [DockEntry] {
        DockSource.entries(includePinned: item.dockIncludePinned, includeFinder: includeFinder)
    }

    // MARK: Chips

    @ViewBuilder private func chip(for item: TBItem) -> some View {
        let width = estimatedWidth(of: item)
        switch item.kind {
        case .flexibleSpace:
            Rectangle().fill(Color.white.opacity(0.06)).frame(minWidth: 16, maxWidth: .infinity, maxHeight: 30)
        case .spacer:
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: width, height: 30)
        case .volume, .brightness:
            HStack(spacing: 6) {
                Image(systemName: item.kind == .volume ? "speaker.fill" : "sun.min.fill")
                Capsule().fill(Color.gray).frame(height: 4)
                Image(systemName: item.kind == .volume ? "speaker.wave.3.fill" : "sun.max.fill")
            }
            .modifier(Chip(color: nil, width: width))
        case .media:
            HStack(spacing: 14) {
                Image(systemName: "backward.fill")
                Image(systemName: "playpause.fill")
                Image(systemName: "forward.fill")
            }
            .modifier(Chip(color: nil, width: width))
        case .clock:
            let formatter: DateFormatter = {
                let f = DateFormatter()
                f.locale = L10n.locale
                f.dateFormat = item.clockFormat.isEmpty ? "HH:mm" : item.clockFormat
                return f
            }()
            label(symbol: item.symbol, title: formatter.string(from: Date()))
                .modifier(Chip(color: item.colorHex, width: width))
        case .battery:
            let status = Battery.status()
            label(symbol: status.map(Battery.symbol(for:)) ?? "battery.100",
                  title: status.map { "\($0.percent)%" } ?? "—")
                .modifier(Chip(color: item.colorHex, width: width))
        case .escape, .button, .hideBar:
            label(symbol: item.symbol, title: item.title)
                .modifier(Chip(color: item.colorHex, width: width))
        case .app:
            if item.actionValue.isEmpty {
                label(symbol: "app.dashed", title: "").modifier(Chip(color: nil, width: width))
            } else {
                let state = AppItemState.of(path: item.actionValue)
                AppTilePreview(path: item.actionValue, style: item.tileStyle, badge: state.badge,
                               running: state.isRunning, active: state.isFrontmost)
            }
        case .dock:
            HStack(spacing: 2) {
                ForEach(dockEntries(for: item)) { entry in
                    AppTilePreview(path: entry.url.path, style: item.tileStyle, badge: entry.badge,
                                   running: entry.isRunning, active: entry.isFrontmost)
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
        }
    }

    private func label(symbol: String, title: String) -> some View {
        HStack(spacing: 4) {
            if !symbol.isEmpty { Image(systemName: symbol) }
            if !title.isEmpty { Text(title).lineLimit(1) }
            if symbol.isEmpty && title.isEmpty { Text("·") }
        }
    }

    private func controlStripView(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "chevron.left")
                .frame(width: 28)
            ForEach(controlStrip, id: \.self) { id in
                Image(systemName: ControlStripStore.info(for: id).symbol)
                    .frame(width: 38, height: 30)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16)))
        .help(L("System items — edit them in the System Items tab", "عناصر النظام — عدّلها من تبويب «عناصر النظام»"))
    }
}

struct AppTilePreview: View {
    let path: String
    let style: TileStyle
    let badge: String?
    let running: Bool
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(style.highlightActive && active ? Color.white.opacity(0.18) : Color.clear)
            AppIconImage(path: path, side: min(style.iconSize, 30))
                .offset(y: style.showDot && style.iconSize < 28 ? -1.5 : 0)
            if style.showDot && running {
                Circle().fill(Color.white.opacity(0.85)).frame(width: 3, height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 0.5)
            }
            if style.showBadge, let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3.5)
                    .frame(minWidth: 13, minHeight: 13)
                    .background(Capsule().fill(Color.red))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: style.width, height: 30)
    }
}

private struct Chip: ViewModifier {
    var color: String?
    var width: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(width: width, height: 30)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(color.flatMap { NSColor(hex: $0) }.map { Color(nsColor: $0) } ?? Color(white: 0.24)))
    }
}
