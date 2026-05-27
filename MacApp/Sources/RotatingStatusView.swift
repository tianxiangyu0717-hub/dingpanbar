import AppKit

/// 状态栏内容视图共享接口：纵向切换 / 横向滚动两种实现都实现这个。
protocol StatusContentDisplay: AnyObject {
    func setItems(_ items: [NSAttributedString])
    func setCurrentIndex(_ index: Int)
}

extension StatusContentDisplay {
    func setCurrentIndex(_ index: Int) {}
}

/// 状态栏内的轮播视图：两个 NSTextField 交替播放，纵向上滑切换。
/// hitTest 返回 nil 让点击穿透到底层 NSStatusItem button，保留菜单弹出。
final class RotatingStatusView: NSView, StatusContentDisplay {
    private let labelA = makeLabel()
    private let labelB = makeLabel()
    private var showingA = true

    private var items: [NSAttributedString] = []
    private(set) var currentIndex = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true   // 滑出范围的部分要被裁掉
        addSubview(labelA)
        addSubview(labelB)
        layoutLabels()
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func makeLabel() -> NSTextField {
        // 用自定义 cell 让单行文字在固定高度容器里垂直居中
        let cell = VCentredCell(textCell: "")
        cell.alignment = .center
        cell.isScrollable = false
        cell.wraps = false
        cell.lineBreakMode = .byClipping
        cell.isEditable = false
        cell.isSelectable = false
        cell.isBordered = false
        cell.isBezeled = false
        cell.drawsBackground = false

        let label = NSTextField(frame: .zero)
        label.cell = cell
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        return label
    }

    private var currentLabel: NSTextField { showingA ? labelA : labelB }
    private var pendingLabel: NSTextField { showingA ? labelB : labelA }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLabels()
    }

    private func layoutLabels() {
        let w = bounds.width
        let h = bounds.height
        currentLabel.frame = NSRect(x: 0, y: 0, width: w, height: h)
        // pending 放在下方等待上滑
        pendingLabel.frame = NSRect(x: 0, y: -h, width: w, height: h)
    }

    /// 设置轮播内容。默认保留当前索引，避免刷新行情后回到第一个监控项。
    func setItems(_ newItems: [NSAttributedString]) {
        items = newItems
        currentIndex = min(currentIndex, max(newItems.count - 1, 0))
        if newItems.indices.contains(currentIndex) {
            currentLabel.attributedStringValue = newItems[currentIndex]
        } else {
            currentLabel.attributedStringValue = NSAttributedString(string: "")
        }
        layoutLabels()
    }

    func setCurrentIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        currentLabel.attributedStringValue = items[index]
        layoutLabels()
    }

    /// 切到下一项，向上滑动动画。少于 2 项时不动。
    func slideToNext() {
        guard items.count > 1 else { return }
        let next = (currentIndex + 1) % items.count
        let nextAttr = items[next]
        let h = bounds.height

        // 把下一项放到下方待命
        pendingLabel.attributedStringValue = nextAttr
        pendingLabel.frame.origin.y = -h

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            currentLabel.animator().frame.origin.y = h    // 滑出顶部
            pendingLabel.animator().frame.origin.y = 0     // 滑入正中
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.showingA.toggle()
                self.currentIndex = next
                self.layoutLabels()
            }
        })
    }

    /// 点击穿透到底层 status item button。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 垂直居中的 NSTextFieldCell

/// 将单行文字在 cell bounds 内垂直居中。
/// NSTextFieldCell 默认从顶部开始绘制，导致状态栏文字偏上。
/// 覆盖 drawingRect 将绘制区上移 (bounds.height - text.height) / 2，
/// titleRect 同步，让 -stringValue 也走同一偏移。
private final class VCentredCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let r = super.drawingRect(forBounds: rect)
        let textH = ceil(attributedStringValue.size().height)
        guard textH > 0, textH < r.height else { return r }
        // insetBy(dx:dy:) 从四边等量内缩，dy=(r.height-textH)/2 恰好使高度=textH 且垂直居中
        return r.insetBy(dx: 0, dy: (r.height - textH) / 2)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        drawingRect(forBounds: rect)
    }
}
