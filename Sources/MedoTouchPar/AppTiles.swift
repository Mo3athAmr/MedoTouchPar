import AppKit

/// Red Dock-style badge ("3", "99+", "•").
final class BadgeView: NSView {
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .bold),
        .foregroundColor: NSColor.white,
    ]

    var text = "" {
        didSet {
            guard text != oldValue else { return }
            isHidden = text.isEmpty
            needsDisplay = true
        }
    }

    var preferredSize: NSSize {
        let width = (text as NSString).size(withAttributes: Self.attributes).width
        return NSSize(width: max(13, ceil(width) + 7), height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = (text as NSString).size(withAttributes: Self.attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: Self.attributes)
    }
}

/// One app in the Touch Bar: its real icon, badge, optional running dot and
/// an active-app highlight. Tapping it behaves like clicking it in the Dock.
final class AppTileView: NSButton {
    static let height: CGFloat = 30

    let url: URL
    private let style: TileStyle
    private let iconView = NSImageView()
    private let badge = BadgeView()
    private let dot = NSView()

    init(url: URL, style: TileStyle) {
        self.url = url
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: style.width, height: Self.height))
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        action = #selector(tapped)
        wantsLayer = true
        layer?.cornerRadius = 6

        let side = min(style.iconSize, Self.height)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: side, height: side)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        dot.layer?.cornerRadius = 1.5
        dot.isHidden = true
        addSubview(dot)

        badge.isHidden = true
        addSubview(badge)

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: style.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        toolTip = AppCatalog.displayName(atPath: url.path)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: style.width, height: Self.height) }

    // Taps on the icon or badge belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // NSButton is flipped (y grows downward), so "top" and "bottom" swap.
        let h = bounds.height
        func fromBottom(_ y: CGFloat, height: CGFloat) -> CGFloat { isFlipped ? h - y - height : y }

        let side = min(style.iconSize, h)
        // Leave room for the running dot only when it is shown.
        let lift: CGFloat = style.showDot && side < h - 2 ? 1.5 : 0
        let iconFrame = NSRect(x: (bounds.width - side) / 2, y: fromBottom((h - side) / 2 + lift, height: side),
                               width: side, height: side)
        iconView.frame = iconFrame
        dot.frame = NSRect(x: bounds.midX - 1.5, y: fromBottom(0.5, height: 3), width: 3, height: 3)
        let size = badge.preferredSize
        badge.frame = NSRect(x: min(bounds.width - size.width, iconFrame.maxX - size.width * 0.7),
                             y: fromBottom(h - size.height, height: size.height),
                             width: size.width, height: size.height)
    }

    func update(badge text: String?, running: Bool, active: Bool) {
        badge.text = style.showBadge ? (text ?? "") : ""
        dot.isHidden = !(style.showDot && running)
        layer?.backgroundColor = style.highlightActive && active
            ? NSColor.white.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        needsLayout = true
    }

    @objc private func tapped() {
        AppLauncher.open(url)
    }
}

/// Horizontally scrollable strip of running (optionally pinned) apps.
///
/// AppKit never shrinks custom Touch Bar views: when the items don't fit it
/// hides the whole item (this happens when another app is frontmost and the
/// system adds its ✕ close box). So the strip measures the space the bar
/// actually has and sizes itself to fit; the remaining apps scroll.
final class DockStripView: NSScrollView {
    private let content = NSView()
    private var tiles: [AppTileView] = []
    private var widthConstraint: NSLayoutConstraint!
    private var contentWidth: CGFloat = 0
    private weak var observedBar: NSView?
    private let maxWidth: CGFloat
    private let includePinned: Bool
    private let includeFinder: Bool
    private let style: TileStyle
    private static let spacing: CGFloat = 2
    private static let itemSpacing: CGFloat = 8

    private var slot: CGFloat { style.width + Self.spacing }

    init(maxWidth: CGFloat, includePinned: Bool, includeFinder: Bool, style: TileStyle) {
        self.maxWidth = maxWidth
        self.includePinned = includePinned
        self.includeFinder = includeFinder
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: maxWidth, height: AppTileView.height))
        hasHorizontalScroller = false
        hasVerticalScroller = false
        drawsBackground = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        documentView = content
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: style.width)
        NSLayoutConstraint.activate([widthConstraint, heightAnchor.constraint(equalToConstant: AppTileView.height)])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToBar()
    }

    /// Rebuilds tiles when the app list changes; otherwise updates badges/state.
    func refresh() {
        let entries = DockSource.entries(includePinned: includePinned, includeFinder: includeFinder)
        if entries.map(\.url) != tiles.map(\.url) {
            rebuildTiles(for: entries)
        }
        for (tile, entry) in zip(tiles, entries) {
            tile.update(badge: entry.badge, running: entry.isRunning, active: entry.isFrontmost)
        }
        attachToBar()
        fitToBar()
    }

    var debugDescriptionLine: String {
        "tiles=\(tiles.count) content=\(Int(contentWidth)) width=\(Int(widthConstraint.constant)) available=\(availableWidth().map { String(Int($0)) } ?? "?")"
    }

    private func rebuildTiles(for entries: [DockEntry]) {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = entries.enumerated().map { index, entry in
            let tile = AppTileView(url: entry.url, style: style)
            tile.translatesAutoresizingMaskIntoConstraints = true
            tile.frame = NSRect(x: CGFloat(index) * slot, y: 0, width: style.width, height: AppTileView.height)
            content.addSubview(tile)
            return tile
        }
        contentWidth = max(style.width, CGFloat(entries.count) * slot - Self.spacing)
        content.frame = NSRect(x: 0, y: 0, width: contentWidth, height: AppTileView.height)
    }

    // MARK: Fitting

    /// The NSTouchBarView that lays out all items (container › bar view).
    private var barView: NSView? { superview?.superview }

    private func attachToBar() {
        guard let bar = barView, bar !== observedBar else { return }
        if let old = observedBar {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: old)
        }
        observedBar = bar
        bar.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(barFrameChanged),
                                               name: NSView.frameDidChangeNotification, object: bar)
    }

    @objc private func barFrameChanged() {
        DispatchQueue.main.async { [weak self] in self?.fitToBar() }
    }

    /// Bar width minus what every other item needs (their fitting sizes, so
    /// flexible spaces count as zero) and the gaps between items.
    private func availableWidth() -> CGFloat? {
        guard let container = superview, let bar = barView, bar.bounds.width > 0 else { return nil }
        let others = bar.subviews.filter { $0 !== container }
        let needed = others.reduce(CGFloat(0)) { sum, sibling in
            sum + (sibling.subviews.first?.fittingSize.width ?? sibling.fittingSize.width)
        }
        return bar.bounds.width - needed - Self.itemSpacing * CGFloat(others.count)
    }

    private func fitToBar() {
        var target = min(contentWidth, maxWidth)
        if let available = availableWidth() {
            target = min(target, max(available, min(contentWidth, slot * 2)))
        }
        target = floor(max(target, style.width))
        guard abs(widthConstraint.constant - target) > 0.5 else { return }
        widthConstraint.constant = target
        barView?.needsLayout = true
    }
}
