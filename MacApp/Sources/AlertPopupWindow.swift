import AppKit

/// 状态栏图标下方弹出的黑底浮层。文字居中，尺寸根据文案自适应，鼠标 hover 即消失。
/// 直接量测富文本所需宽高 + 内边距，避免固定尺寸带来的截断或留白。
final class AlertPopupWindow: NSWindow {
    var onClose: (() -> Void)?

    private static let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private static let bodyFont  = NSFont.systemFont(ofSize: 12)
    private static let horizontalPadding: CGFloat = 18
    private static let verticalPadding: CGFloat   = 14
    private static let lineSpacing: CGFloat       = 4
    private static let gapBelowStatusBar: CGFloat = 6

    init(alert: PriceAlert,
         itemName: String,
         currentPrice: Double,
         colorMode: TrendColorMode,
         anchor: NSRect,
         verticalOffset: CGFloat) {
        // ── 文案 ────────────────────────────────────────
        // 红涨绿跌：above=涨到=小红点，below=跌到=小绿点。
        // 用 ●（U+25CF）字符 + systemRed/systemGreen，跟着标题字号自适应缩放。
        let dotColor: NSColor = colorMode.color(isUp: alert.direction == .above)
        let action  = alert.direction == .above ? "涨过" : "跌破"
        let titleStr = String(format: "%@ 已%@ %@ ¥%.2f",
                              itemName, action, alert.direction.symbol, alert.threshold)
        let title = NSMutableAttributedString()
        title.append(NSAttributedString(string: "●  ", attributes: [
            .font: Self.titleFont,
            .foregroundColor: dotColor,
        ]))
        title.append(NSAttributedString(string: titleStr, attributes: [
            .font: Self.titleFont,
            .foregroundColor: NSColor.white,
        ]))

        let mode = alert.repeatMode == .once ? "单次（已自动移除）" : "重复提醒"
        let body = NSAttributedString(
            string: String(format: "现价 ¥%.2f · %@", currentPrice, mode),
            attributes: [
                .font: Self.bodyFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            ]
        )

        // ── 量尺寸 ──────────────────────────────────────
        let titleSize = title.size()
        let bodySize  = body.size()
        let contentW  = ceil(max(titleSize.width, bodySize.width))
        let contentH  = ceil(titleSize.height) + ceil(bodySize.height) + Self.lineSpacing
        let totalW    = contentW + Self.horizontalPadding * 2
        let totalH    = contentH + Self.verticalPadding * 2

        // ── 位置：状态栏图标正下方居中 ──────────────────
        let x = anchor.midX - totalW / 2
        let y = anchor.minY - totalH - Self.gapBelowStatusBar - verticalOffset
        let frame = NSRect(x: x, y: y, width: totalW, height: totalH)

        super.init(contentRect: frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .statusBar + 1
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.ignoresMouseEvents = false
        self.animationBehavior = .utilityWindow

        let content = PopupContentView(title: title, body: body, lineSpacing: Self.lineSpacing)
        content.onHover = { [weak self] in self?.dismiss() }
        self.contentView = content
    }

    /// 显示并接管：鼠标已在浮层位置上时延后 200ms 才允许 hover 关闭，避免一闪而过。
    func present() {
        self.orderFrontRegardless()
        let mouseAtStart = NSEvent.mouseLocation
        if self.frame.contains(mouseAtStart) {
            (self.contentView as? PopupContentView)?.armAfterDelay(0.2)
        } else {
            (self.contentView as? PopupContentView)?.armImmediately()
        }
    }

    func dismiss() {
        guard self.isVisible else { return }
        self.orderOut(nil)
        onClose?()
    }
}

// MARK: - 内容视图（黑底圆角 + 居中两行 + hover 关闭）

private final class PopupContentView: NSView {
    var onHover: (() -> Void)?
    private var armed = false
    private var trackingArea: NSTrackingArea?

    init(title: NSAttributedString, body: NSAttributedString, lineSpacing: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let titleLabel = NSTextField(labelWithAttributedString: title)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byClipping
        titleLabel.usesSingleLineMode = true

        let bodyLabel = NSTextField(labelWithAttributedString: body)
        bodyLabel.alignment = .center
        bodyLabel.maximumNumberOfLines = 1
        bodyLabel.lineBreakMode = .byClipping
        bodyLabel.usesSingleLineMode = true

        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = lineSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func armImmediately() { armed = true }
    func armAfterDelay(_ seconds: TimeInterval) {
        armed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.armed = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        guard armed else { return }
        onHover?()
    }
}
