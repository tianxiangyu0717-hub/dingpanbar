import AppKit
import QuartzCore

/// 状态栏内的横向滚动视图（GPU 合成版）。
///
/// 设计要点：
/// - 一轮内容（所有 item + 尾部分隔符）渲染为一张 CGImage，用两份 CALayer 首尾相接形成"无缝循环"。
/// - 滚动靠 CABasicAnimation 推 transform.translation.x，从 0 到 -cycleWidth，无限重复。
///   动画由 Core Animation 的 display link 驱动，独立于 NSEvent 运行循环，菜单弹出时也不卡。
/// - 左右两端 CAGradientLayer 渐隐遮罩。
/// - hitTest 返回 nil 让点击穿透到 NSStatusItem button。
final class HorizontalScrollStatusView: NSView, StatusContentDisplay {
    /// 滚动速度（点/秒）。
    private static let scrollSpeed: CGFloat = 30
    /// 渐隐遮罩宽度（点），左右各一份。
    private static let fadeWidth: CGFloat = 16

    private var items: [NSAttributedString] = []
    private let scrollLayer = CALayer()
    private var cycleWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        // 禁用 scrollLayer 的隐式动画，自己控制 explicit animation
        scrollLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "transform": NSNull(),
            "sublayers": NSNull(),
            "contents": NSNull(),
        ]
        layer?.addSublayer(scrollLayer)
        setupFadeMask()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 渐隐遮罩

    private func setupFadeMask() {
        let mask = CAGradientLayer()
        mask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor,
        ]
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint   = CGPoint(x: 1, y: 0.5)
        layer?.mask = mask
        updateMaskFrame()
    }

    private func updateMaskFrame() {
        guard let mask = layer?.mask as? CAGradientLayer, bounds.width > 0 else { return }
        let frac = min(0.45, Self.fadeWidth / bounds.width)
        mask.locations = [0, NSNumber(value: Double(frac)), NSNumber(value: 1 - Double(frac)), 1]
        // 禁用隐式动画，避免遮罩跟随 statusItem.length 变化做诡异 transition
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let prevH = bounds.height
        super.setFrameSize(newSize)
        updateMaskFrame()
        // 仅高度变化时才重建（垂直居中依赖 bounds.height）；
        // 宽度变化（statusItem.length 随刷新轻微调整）不触发重建，
        // 避免每次 refresh 都打断 CABasicAnimation 造成"呼吸"般的跳顿
        if !items.isEmpty && abs(newSize.height - prevH) > 0.5 {
            rebuildContent()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // 切换显示器导致 backingScaleFactor 变化时，重新栅格化以保持清晰度
        if !items.isEmpty {
            rebuildContent()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 深色/浅色菜单栏切换时，重新栅格化以让 labelColor 按新外观解析
        // （bitmap 内的像素颜色是在渲染时固化的，必须重画）
        if !items.isEmpty {
            rebuildContent()
        }
    }

    // MARK: - 内容

    /// 数据刷新主入口：
    /// - 若新 cycle 宽度与现有 cycle 宽度相同（价格小幅波动通常不会改变总字符宽度），
    ///   只替换底图 contents，**不重建 layers，不重启 animation**，滚动连续无停顿。
    /// - 否则（首次/项数变化/宽度跳变）才完全重建。
    func setItems(_ newItems: [NSAttributedString]) {
        items = newItems
        guard !items.isEmpty, bounds.height > 0 else {
            rebuildContent()
            return
        }

        let cycle = buildCycle()
        let cycleW = ceil(cycle.size().width)
        let subs = scrollLayer.sublayers ?? []

        // 快路径：仍是滚动模式 + 宽度未变化 → 只换底图，动画继续
        if subs.count == 2,
           abs(cycleW - self.cycleWidth) < 0.5,
           scrollLayer.animation(forKey: "scroll") != nil,
           let img = renderImage(cycle, width: cycleW, scale: backingScale) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            subs[0].contents = img
            subs[1].contents = img
            CATransaction.commit()
            return
        }

        rebuildContent()
    }

    private func rebuildContent() {
        // 清理旧的 sublayers + animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollLayer.removeAllAnimations()
        scrollLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        scrollLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        guard !items.isEmpty, bounds.height > 0 else { return }

        // 一轮内容（含尾部分隔符，保证循环回绕时间隙一致）
        let cycle = buildCycle()
        let cycleW = ceil(cycle.size().width)
        cycleWidth = cycleW

        let scale = backingScale

        // 单项 / 一轮已经短于视图：居中静止，不滚动
        if items.count <= 1 || cycleW <= bounds.width {
            let only = items.count <= 1 ? items[0] : cycle
            let w = ceil(only.size().width)
            guard let img = renderImage(only, width: w, scale: scale) else { return }
            let single = CALayer()
            single.contents = img
            single.contentsScale = scale
            single.frame = CGRect(
                x: floor((bounds.width - w) / 2), y: 0,
                width: w, height: bounds.height
            )
            scrollLayer.frame = bounds
            scrollLayer.addSublayer(single)
            return
        }

        // 多项：栅格化一份，两份 layer 首尾相接
        guard let img = renderImage(cycle, width: cycleW, scale: scale) else { return }
        let copy1 = CALayer()
        copy1.contents = img
        copy1.contentsScale = scale
        copy1.frame = CGRect(x: 0, y: 0, width: cycleW, height: bounds.height)
        let copy2 = CALayer()
        copy2.contents = img
        copy2.contentsScale = scale
        copy2.frame = CGRect(x: cycleW, y: 0, width: cycleW, height: bounds.height)

        scrollLayer.frame = CGRect(x: 0, y: 0, width: 2 * cycleW, height: bounds.height)
        scrollLayer.addSublayer(copy1)
        scrollLayer.addSublayer(copy2)

        // translateX 从 0 → -cycleW，线性、无限循环
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -cycleW
        anim.duration = TimeInterval(cycleW / Self.scrollSpeed)
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        scrollLayer.add(anim, forKey: "scroll")
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func buildCycle() -> NSAttributedString {
        let sepFont = NSFont.menuBarFont(ofSize: 0)
        let sep = makeSeparator(font: sepFont)
        let result = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            result.append(item)
            // 多项时每项后都加分隔符（含末尾），让循环回绕时首尾间隙一致
            if items.count > 1 || i < items.count - 1 {
                result.append(sep)
            }
        }
        return result
    }

    /// 3 个 "M" 字符宽度的透明间隔（M 是较宽的英文字符）。
    private func makeSeparator(font: NSFont) -> NSAttributedString {
        let mW = ("M" as NSString).size(withAttributes: [.font: font]).width
        let spaceW = (" " as NSString).size(withAttributes: [.font: font]).width
        return NSAttributedString(string: " ", attributes: [
            .font: font,
            .kern: mW * 3 - spaceW,
        ])
    }

    /// 把 attributed string 栅格化到 `CGImage`（按 retina scale），用作 CALayer.contents。
    /// 一次性 CPU 渲染，之后 GPU 合成。
    private func renderImage(_ attributed: NSAttributedString, width: CGFloat, scale: CGFloat) -> CGImage? {
        let h = bounds.height
        guard width > 0, h > 0 else { return nil }
        let pixelW = Int(ceil(width * scale))
        let pixelH = Int(ceil(h * scale))
        guard pixelW > 0, pixelH > 0,
              let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: pixelW, height: pixelH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        let prev = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = prev }

        let textH = attributed.size().height
        let origin = NSPoint(x: 0, y: floor((h - textH) / 2))
        // 用当前视图的 effectiveAppearance 作为绘制外观，
        // 这样 attributedString 里的 .labelColor 在解析时会取得对应模式的颜色
        // （状态栏外观≠系统外观，比如系统亮色但菜单栏暗色时，这里保证用菜单栏的）
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                attributed.draw(at: origin)
            }
        } else {
            let prevApp = NSAppearance.current
            NSAppearance.current = effectiveAppearance
            attributed.draw(at: origin)
            NSAppearance.current = prevApp
        }
        return ctx.makeImage()
    }

    /// 点击穿透到底层 status item button。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
