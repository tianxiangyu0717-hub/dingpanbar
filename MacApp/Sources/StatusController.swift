import AppKit
import Combine

/// 状态栏控制器：
/// - 内容视图根据设置在 RotatingStatusView（纵向切换）/ HorizontalScrollStatusView（横向滚动）之间切换
/// - 60s 刷新（可调）；纵向模式多项时按"轮播间隔"上滑切换；横向模式无间隔参数
/// - 轮播优先级：先轮播交易中的项；全部休市时才轮播全部
/// - 价格穿越触发提醒（所有监控项均生效）
/// - "心跳"脉冲 + 陈旧降色，告诉用户数据还在刷
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    /// 当前活跃的内容视图（两种实现之一）。
    private var contentView: (NSView & StatusContentDisplay)!

    let alerts = AlertStore()
    let watch = WatchStore()
    let settings = SettingsStore()

    private var refreshTimer: Timer?
    private var rotationTimer: Timer?
    private var quotes: [UUID: Quote] = [:]
    private var sparklines: [UUID: SparklineSeries] = [:]
    private var displayPairs: [(item: WatchedItem, quote: Quote)] = []
    private var lastSuccessAt: Date?

    private var alertsWindow: AlertsWindowController?
    private var popups: [AlertPopupWindow] = []
    private var cancellables = Set<AnyCancellable>()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
        }

        installContentView(for: settings.rotationMode)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // 占位：未拿到数据前先显示一个占位串，避免状态栏空着
        contentView.setItems([NSAttributedString(string: "Au …")])
        statusItem.length = 60

        Task { await refresh() }
        scheduleRefreshTimer(interval: settings.refreshInterval)
        scheduleRotationTimerIfNeeded()

        // 设置变化
        settings.$refreshInterval
            .dropFirst().removeDuplicates()
            .sink { [weak self] v in self?.scheduleRefreshTimer(interval: v) }
            .store(in: &cancellables)
        settings.$rotationInterval
            .dropFirst().removeDuplicates()
            .sink { [weak self] _ in self?.scheduleRotationTimerIfNeeded() }
            .store(in: &cancellables)
        settings.$rotationMode
            .dropFirst().removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                self.installContentView(for: mode)
                self.scheduleRotationTimerIfNeeded()
                self.updateDisplay()
            }
            .store(in: &cancellables)
        settings.$trendColorMode
            .dropFirst().removeDuplicates()
            .sink { [weak self] _ in self?.updateDisplay() }
            .store(in: &cancellables)

        // 监控列表变化 → 重新拉取（debounce 防止用户连续编辑频繁打 API）
        watch.$items
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }
            .store(in: &cancellables)
    }

    // MARK: - 内容视图切换

    private func installContentView(for mode: RotationMode) {
        // 移除旧的
        contentView?.removeFromSuperview()

        let frame = NSRect(x: 0, y: 0, width: 80, height: 22)
        let view: NSView & StatusContentDisplay
        switch mode {
        case .vertical:   view = RotatingStatusView(frame: frame)
        case .horizontal: view = HorizontalScrollStatusView(frame: frame)
        }
        contentView = view

        guard let button = statusItem.button else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    // MARK: - 定时器

    private func scheduleRefreshTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// 仅纵向模式需要 rotationTimer；横向模式连续滚动，由 view 自己驱动。
    private func scheduleRotationTimerIfNeeded() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard settings.rotationMode == .vertical else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: settings.rotationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                (self?.contentView as? RotatingStatusView)?.slideToNext()
            }
        }
    }

    // MARK: - 数据刷新

    func refresh() async {
        let items = watch.items
        guard !items.isEmpty else {
            quotes = [:]
            updateDisplay()
            return
        }
        do {
            let map = try await QuoteFetcher.fetch(items: items)
            // 合并：先清掉已不在 list 里的，再覆盖新拿到的
            let live = Set(items.map(\.id))
            quotes = quotes.filter { live.contains($0.key) }
            sparklines = sparklines.filter { live.contains($0.key) }
            for (k, v) in map { quotes[k] = v }
            for item in items {
                if let quote = map[item.id] {
                    watch.markResolved(itemId: item.id, quote: quote)
                } else {
                    watch.markUnresolved(itemId: item.id)
                }
            }
            let newSparklines = await SparklineFetcher.fetch(quotes: map)
            for id in map.keys {
                sparklines[id] = nil
            }
            for (k, v) in newSparklines { sparklines[k] = v }
            lastSuccessAt = Date()
            updateDisplay()

            // 价格提醒：遍历所有监控项，每项独立检测穿越
            var popupOffset = 0
            for item in items {
                guard let quote = map[item.id] else { continue }
                let fires = alerts.checkCrossings(itemId: item.id,
                                                  newPrice: quote.price,
                                                  isTrading: quote.isTrading)
                for (i, alert) in fires.enumerated() {
                    showPopup(for: alert,
                              itemName: quote.name,
                              currentPrice: quote.price,
                              indexOffset: popupOffset + i)
                }
                popupOffset += fires.count
            }
            playRefreshPulse()
        } catch {
            // 拉失败保留旧值，可能进入陈旧状态
            applyAlpha()
        }
    }

    // MARK: - 显示更新

    private func updateDisplay() {
        let previousCurrentID: UUID?
        if let rotating = contentView as? RotatingStatusView,
           displayPairs.indices.contains(rotating.currentIndex) {
            previousCurrentID = displayPairs[rotating.currentIndex].item.id
        } else {
            previousCurrentID = nil
        }

        // 按 watch.items 顺序生成 (item, quote) 对；无论是否休市都展示所有项
        let pairs: [(WatchedItem, Quote)] = watch.items.compactMap { item in
            guard let q = quotes[item.id] else { return nil }
            return (item, q)
        }
        displayPairs = pairs

        let attrs = displayPairs.map { makeTitle(item: $0.item,
                                                 quote: $0.quote,
                                                 sparkline: sparklines[$0.item.id]) }

        if attrs.isEmpty {
            contentView.setItems([NSAttributedString(string: "无数据")])
            statusItem.length = 60
        } else {
            // 状态栏宽度固定到所有项里最宽那个，避免轮播时菜单栏抖动
            let maxW = attrs.map { ceil($0.size().width) }.max() ?? 60
            statusItem.length = maxW + 18
            contentView.setItems(attrs)
            if let previousCurrentID,
               let nextIndex = displayPairs.firstIndex(where: { $0.item.id == previousCurrentID }) {
                contentView.setCurrentIndex(nextIndex)
            }
        }
        applyAlpha()
    }

    /// 名称 9pt + 价格菜单栏字号 + ▲/▼涨跌幅 + (休市 9pt)。
    /// - ▲/▼ 表示涨跌方向（不再表示交易状态）；涨跌幅取绝对值，1 位小数。
    /// - 交易中状态不带额外指示；休市时在末尾追加小字"休市"。
    /// - 休市时仍展示截止收盘的涨跌幅（基于 price - prevClose 计算）。
    private func makeTitle(item: WatchedItem, quote: Quote, sparkline: SparklineSeries?) -> NSAttributedString {
        let nameFont  = NSFont.systemFont(ofSize: 9, weight: .regular)
        let priceFont = NSFont.menuBarFont(ofSize: 0)
        // 用 labelColor，由 HorizontalScrollStatusView 在栅格化时按当前菜单栏外观解析
        // （深色菜单栏 → 接近白色；浅色菜单栏 → 接近黑色）
        let color: NSColor = .labelColor

        let arrow = quote.isUp ? "▲" : "▼"
        let pctAbs = abs(quote.changePercent)

        let result = NSMutableAttributedString()
        // 名称（小字，轻微上抬）。【名称】与【价格】之间留 2 个 nameFont 空格（较默认 1 个空格扩大 1 倍）
        result.append(NSAttributedString(string: quote.name + "  ", attributes: [
            .font: nameFont,
            .foregroundColor: color,
            .baselineOffset: 1.5,
        ]))
        // 价格 + 方向箭头 + 涨跌幅。【价格】与【三角箭头】之间留 2 个 priceFont 空格（扩大 1 倍）
        result.append(NSAttributedString(
            string: String(format: "%.2f  %@%.1f%%", quote.price, arrow, pctAbs),
            attributes: [
                .font: priceFont,
                .foregroundColor: color,
            ]
        ))
        result.append(NSAttributedString(string: "  ", attributes: [
            .font: nameFont,
            .foregroundColor: color,
            .baselineOffset: 1.5,
        ]))
        if let sparkline {
            result.append(SparklineRenderer.attachment(for: sparkline,
                                                       isUpFromOpen: quote.open > 0 ? quote.price >= quote.open : quote.isUp,
                                                       colorMode: settings.trendColorMode,
                                                       appearance: statusItem.button?.effectiveAppearance))
        }
        // 休市标签（小字，与名称同款样式）。【涨跌幅】与【休市】间距 = 2 个 nameFont 空格，与【名称】—【价格】一致
        if !quote.isTrading {
            result.append(NSAttributedString(string: "  休市", attributes: [
                .font: nameFont,
                .foregroundColor: color,
                .baselineOffset: 1.5,
            ]))
        }
        return result
    }

    // MARK: - 视觉"还在刷"信号

    private var isStale: Bool {
        guard let last = lastSuccessAt else { return true }
        return Date().timeIntervalSince(last) > settings.refreshInterval * 2
    }

    private func applyAlpha() {
        // 用 CATransaction 关闭隐式动画：陈旧/恢复的 alpha 切换瞬时完成，
        // 不与刷新时的"呼吸脉冲"叠加，保证脉动仅由 playRefreshPulse() 触发。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        statusItem.button?.alphaValue = isStale ? 0.5 : 1.0
        CATransaction.commit()
    }

    private func playRefreshPulse() {
        guard let button = statusItem.button, !isStale else { return }
        button.layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().alphaValue = 0.3
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.5
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    button.animator().alphaValue = self.isStale ? 0.5 : 1.0
                }
            }
        })
    }

    // MARK: - 菜单（弹出瞬间重建）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        if watch.items.isEmpty {
            menu.addItem(disabled("监控列表为空，点「设置…」添加"))
        } else {
            // 列出所有 watch item 的当前行情
            for item in watch.items {
                if let q = quotes[item.id] {
                    menu.addItem(quoteMenuItem(for: item, quote: q))
                } else {
                    let prefix = item.resolvedMarket?.label ?? "未识别"
                    menu.addItem(disabled("\(prefix) · \(item.fallbackName)  ——"))
                }
            }
            menu.addItem(.separator())
            menu.addItem(disabled(localRefreshLine()))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let intv = NSMenuItem(title: "刷新间隔：\(SettingsStore.format(settings.refreshInterval))",
                              action: nil, keyEquivalent: "")
        intv.submenu = intervalSubmenu(values: SettingsStore.presets,
                                       current: settings.refreshInterval,
                                       action: #selector(setRefreshFromMenu(_:)))
        menu.addItem(intv)

        // 轮播间隔仅在纵向模式下生效，横向模式（连续滚动）下不展示
        if settings.rotationMode == .vertical {
            let rot = NSMenuItem(title: "轮播间隔：\(SettingsStore.format(settings.rotationInterval))",
                                 action: nil, keyEquivalent: "")
            rot.submenu = intervalSubmenu(values: SettingsStore.rotationPresets,
                                          current: settings.rotationInterval,
                                          action: #selector(setRotationFromMenu(_:)))
            menu.addItem(rot)
        }

        let setup = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        setup.target = self
        menu.addItem(setup)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func quoteMenuItem(for item: WatchedItem, quote q: Quote) -> NSMenuItem {
        let title = quoteMenuTitle(for: item, quote: q)
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = quoteDetailMenu(for: item, quote: q)
        return menuItem
    }

    private func quoteMenuTitle(for item: WatchedItem, quote q: Quote) -> String {
        let arrow = q.isUp ? "▲" : "▼"
        let tag = q.isTrading ? "" : " · 休市"
        return String(format: "%@ · %@  %.2f  %@%.1f%%%@",
                      q.market.label, q.name, q.price,
                      arrow, abs(q.changePercent), tag)
    }

    private func quoteDetailMenu(for item: WatchedItem, quote q: Quote) -> NSMenu {
        let menu = NSMenu(title: q.name)
        menu.addItem(panelItem("数据面板", weight: .semibold))
        menu.addItem(.separator())

        if let note = item.nameOverride?.nilIfEmpty {
            menu.addItem(panelItem("备注：\(note)"))
            menu.addItem(.separator())
        }

        for (sectionIndex, section) in q.detailSections.enumerated() {
            if sectionIndex > 0 { menu.addItem(.separator()) }
            menu.addItem(sectionHeader(section.title))
            for row in section.rows {
                menu.addItem(panelItem("\(row.label)：\(row.value)"))
            }
        }

        menu.addItem(.separator())
        menu.addItem(panelItem(localRefreshLine()))
        return menu
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: "［\(title)］", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: "［\(title)］", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        item.isEnabled = true
        return item
    }

    private func panelItem(_ title: String, weight: NSFont.Weight = .regular) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ])
        item.isEnabled = true
        return item
    }

    private func intervalSubmenu(values: [TimeInterval], current: TimeInterval, action: Selector) -> NSMenu {
        let sub = NSMenu()
        for v in values {
            let it = NSMenuItem(title: SettingsStore.format(v), action: action, keyEquivalent: "")
            it.target = self
            it.representedObject = v
            if abs(current - v) < 0.5 { it.state = .on }
            sub.addItem(it)
        }
        if !values.contains(where: { abs($0 - current) < 0.5 }) {
            sub.addItem(.separator())
            let cur = NSMenuItem(title: "当前：\(SettingsStore.format(current))", action: nil, keyEquivalent: "")
            cur.state = .on; cur.isEnabled = false
            sub.addItem(cur)
        }
        sub.addItem(.separator())
        let custom = NSMenuItem(title: "自定义…", action: #selector(openSettings), keyEquivalent: "")
        custom.target = self
        sub.addItem(custom)
        return sub
    }

    private func localRefreshLine() -> String {
        guard let at = lastSuccessAt else { return "本地刷新  ——（尚未成功）" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let elapsed = Int(Date().timeIntervalSince(at).rounded())
        let rel: String
        if elapsed < 60 { rel = "\(elapsed) 秒前" }
        else if elapsed < 3600 { rel = "\(elapsed / 60) 分钟前" }
        else { rel = "\(elapsed / 3600) 小时前" }
        let staleTag = isStale ? "  ⚠ 已陈旧" : ""
        return "本地刷新  \(fmt.string(from: at))（\(rel)）\(staleTag)"
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshNow() { Task { await refresh() } }

    @objc private func setRefreshFromMenu(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? TimeInterval else { return }
        settings.refreshInterval = v
    }

    @objc private func setRotationFromMenu(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? TimeInterval else { return }
        settings.rotationInterval = v
    }

    @objc private func openSettings() {
        if alertsWindow == nil {
            alertsWindow = AlertsWindowController(alerts: alerts, settings: settings, watch: watch)
        }
        alertsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 浮层

    private func showPopup(for alert: PriceAlert, itemName: String, currentPrice: Double, indexOffset: Int) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let frameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let popup = AlertPopupWindow(alert: alert,
                                     itemName: itemName,
                                     currentPrice: currentPrice,
                                     colorMode: settings.trendColorMode,
                                     anchor: frameOnScreen,
                                     verticalOffset: CGFloat(indexOffset) * 8)
        popup.onClose = { [weak self, weak popup] in
            guard let self, let popup else { return }
            self.popups.removeAll { $0 === popup }
        }
        popups.append(popup)
        popup.present()
    }
}
