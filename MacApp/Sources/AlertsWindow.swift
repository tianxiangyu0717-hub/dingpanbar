import AppKit
import SwiftUI

/// 综合设置窗口：刷新/轮播间隔 + 监控列表 + 价格提醒。
final class AlertsWindowController: NSWindowController, NSWindowDelegate {
    init(alerts: AlertStore, settings: SettingsStore, watch: WatchStore) {
        let root = RootView(alerts: alerts, settings: settings, watch: watch)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 680))
        window.minSize = NSSize(width: 580, height: 540)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 根视图

private struct RootView: View {
    @ObservedObject var alerts: AlertStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var watch: WatchStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSection(settings: settings)
                Divider()
                WatchListSection(watch: watch)
                Divider()
                AlertsSection(alerts: alerts, watch: watch)
            }
        }
    }
}

// MARK: - 设置：刷新间隔 + 轮播间隔

private struct SettingsSection: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    Text("🎆")
                        .font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("感谢支持，已解锁盯盘 Bar 永久使用权限")
                            .font(.system(size: 13, weight: .semibold))
                        Text("把你真正关心的行情留在菜单栏，其他噪音都先放一边。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))

            Text("通用设置").font(.system(size: 13, weight: .semibold))

            intervalBlock(
                title: "刷新间隔",
                hint: "拉取行情的频率",
                value: $settings.refreshInterval,
                presets: SettingsStore.presets,
                minValue: SettingsStore.minInterval,
                maxValue: SettingsStore.maxInterval,
                step: 5
            )

            // 轮播方式
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("轮播方式").font(.system(size: 12, weight: .medium))
                    Text(settings.rotationMode == .horizontal
                         ? "横向连续滚动，首尾渐隐"
                         : "纵向上滑切换，按间隔步进")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                }
                Picker("", selection: $settings.rotationMode) {
                    ForEach(RotationMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("涨跌颜色").font(.system(size: 12, weight: .medium))
                    Text("影响趋势图结尾圆点和到价提醒圆点")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                }
                Picker("", selection: $settings.trendColorMode) {
                    ForEach(TrendColorMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // 仅纵向模式下展示轮播间隔
            if settings.rotationMode == .vertical {
                intervalBlock(
                    title: "轮播间隔",
                    hint: "状态栏切换显示多个监控项的频率",
                    value: $settings.rotationInterval,
                    presets: SettingsStore.rotationPresets,
                    minValue: SettingsStore.minRotation,
                    maxValue: SettingsStore.maxRotation,
                    step: 1
                )
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func intervalBlock(title: String, hint: String,
                               value: Binding<TimeInterval>,
                               presets: [TimeInterval],
                               minValue: TimeInterval, maxValue: TimeInterval,
                               step: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(hint).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text("当前：\(SettingsStore.format(value.wrappedValue))")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { p in
                    PresetButton(label: SettingsStore.format(p),
                                 isSelected: abs(p - value.wrappedValue) < 0.5) {
                        value.wrappedValue = p
                    }
                }
                Spacer()
                CustomStepper(value: value, lo: Int(minValue), hi: Int(maxValue), step: step)
            }
        }
    }
}

private struct CustomStepper: View {
    @Binding var value: TimeInterval
    let lo: Int
    let hi: Int
    let step: Int
    @State private var input: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Text("自定义").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", value: $input, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .onSubmit { apply() }
            Stepper("", value: $input, in: lo...hi, step: step).labelsHidden()
            Text("秒").font(.system(size: 11)).foregroundColor(.secondary)
            Button("应用") { apply() }
                .controlSize(.small)
                .disabled(TimeInterval(input) == value)
        }
        .onAppear { input = Int(value) }
        .onChange(of: value) { newValue in input = Int(newValue) }
    }

    private func apply() {
        let v = max(lo, min(hi, input))
        input = v
        value = TimeInterval(v)
    }
}

private struct PresetButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
        )
        .foregroundColor(isSelected ? .white : .primary)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(isSelected ? 0 : 0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - 监控列表

private struct WatchListSection: View {
    @ObservedObject var watch: WatchStore
    @State private var isEditing = false
    @State private var drafts: [WatchDraft] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("监控列表").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\((isEditing ? drafts.count : orderedItems.count)) / \(WatchStore.maxItems)")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if isEditing {
                    Button {
                        drafts.insert(WatchDraft(), at: 0)
                    } label: {
                        Label("添加", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.small)
                    .disabled(drafts.count >= WatchStore.maxItems)

                    Button("取消") {
                        isEditing = false
                        drafts = []
                    }
                    .controlSize(.small)

                    Button("保存") { saveDrafts() }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("编辑") {
                        drafts = orderedItems.map(WatchDraft.init(item:))
                        isEditing = true
                    }
                    .controlSize(.small)
                }
            }

            if currentCount == 0 {
                Text("空")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else if isEditing {
                VStack(spacing: 0) {
                    ForEach(Array($drafts.enumerated()), id: \.element.id) { idx, $draft in
                        WatchDraftRow(draft: $draft) {
                            drafts.removeAll { $0.id == draft.id }
                        }
                        if idx < drafts.count - 1 { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(orderedItems.enumerated()), id: \.element.id) { idx, item in
                        WatchReadRow(item: item)
                        if idx < orderedItems.count - 1 { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
            }
        }
        .padding(14)
        .onChange(of: watch.items) { newValue in
            guard isEditing else { return }
            let known = Dictionary(uniqueKeysWithValues: newValue.map { ($0.id, $0) })
            drafts = drafts.map { draft in
                guard let item = known[draft.id] else { return draft }
                return draft.withUpdatedOriginal(item)
            }
        }
    }

    private var currentCount: Int { isEditing ? drafts.count : orderedItems.count }

    private var orderedItems: [WatchedItem] {
        watch.items.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.createdAt
                let r = rhs.element.createdAt
                if l == r { return lhs.offset < rhs.offset }
                return l > r
            }
            .map(\.element)
    }

    private func saveDrafts() {
        let cleaned = drafts
            .map { $0.normalized() }
            .filter { !$0.rawCode.isEmpty }
            .prefix(WatchStore.maxItems)
            .map { $0.toWatchedItem() }
        watch.items = Array(cleaned)
        isEditing = false
        drafts = []
    }
}

private struct WatchDraft: Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var rawCode: String
    var nameOverride: String
    var selectedMarket: Market?
    var original: WatchedItem?

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         rawCode: String = "",
         nameOverride: String = "",
         selectedMarket: Market? = nil,
         original: WatchedItem? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.rawCode = rawCode
        self.nameOverride = nameOverride
        self.selectedMarket = selectedMarket
        self.original = original
    }

    init(item: WatchedItem) {
        self.init(id: item.id,
                  createdAt: item.createdAt,
                  rawCode: item.rawCode,
                  nameOverride: item.nameOverride ?? "",
                  selectedMarket: item.marketOverride,
                  original: item)
    }

    func normalized() -> WatchDraft {
        var copy = self
        copy.rawCode = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.nameOverride = nameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    func withUpdatedOriginal(_ item: WatchedItem) -> WatchDraft {
        var copy = self
        copy.original = item
        return copy
    }

    func toWatchedItem() -> WatchedItem {
        let n = normalized()
        guard var item = n.original else {
            return WatchedItem(id: n.id,
                               createdAt: n.createdAt,
                               rawCode: n.rawCode,
                               nameOverride: n.nameOverride.nilIfEmpty,
                               marketOverride: n.selectedMarket)
        }
        let changed = item.rawCode.trimmingCharacters(in: .whitespacesAndNewlines) != n.rawCode ||
            (item.nameOverride ?? "") != n.nameOverride ||
            item.marketOverride != n.selectedMarket

        item.createdAt = n.createdAt
        item.rawCode = n.rawCode
        item.nameOverride = n.nameOverride.nilIfEmpty
        item.marketOverride = n.selectedMarket
        if changed {
            item.resolvedSymbol = nil
            item.resolvedMarket = nil
            item.resolvedName = nil
            item.resolvedAt = nil
            item.resolutionFailed = false
        }
        return item
    }
}

private struct CodeSuggestion: Identifiable, Equatable {
    let id = UUID()
    let rawCode: String
    let market: Market
    let symbol: String
    let name: String
    let price: Double?
    let hasQuote: Bool

    var title: String { "\(rawCode) · \(name)" }
    var subtitle: String {
        if let price { return "\(market.label) · \(symbol) · \(String(format: "%.2f", price))" }
        return hasQuote ? "\(market.label) · \(symbol)" : "\(market.label) · \(symbol) · 候选"
    }
}

private struct WatchReadRow: View {
    let item: WatchedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.rawCode)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 140, alignment: .leading)
                Text(item.nameOverride?.nilIfEmpty ?? item.resolvedName ?? "未备注")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(item.resolvedMarket?.label ?? "待识别")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            recognitionLine
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var recognitionLine: some View {
        if let desc = item.resolvedDescription {
            Label("已识别：\(desc)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else if item.resolutionFailed {
            Label("未识别 / 无行情数据，编辑后重新保存", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
        } else if !item.rawCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("等待识别", systemImage: "clock")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

private struct WatchDraftRow: View {
    private struct SearchCandidate: Hashable {
        let candidate: SymbolResolver.Candidate
        let rawCode: String
        let name: String
        let requiresQuote: Bool
    }

    @Binding var draft: WatchDraft
    let onDelete: () -> Void
    @State private var suggestions: [CodeSuggestion] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextField("代码，如 600519 / 00700 / AAPL / AU9999", text: $draft.rawCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: draft.rawCode) { value in scheduleSearch(for: value) }

                    if !suggestions.isEmpty {
                        suggestionPopover
                            .offset(y: 30)
                            .zIndex(10)
                    }
                }
                .frame(width: 220, alignment: .topLeading)
                .zIndex(10)

                Text(draft.selectedMarket?.label ?? draft.original?.resolvedMarket?.label ?? "待识别")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 72, alignment: .leading)

                TextField("备注（可选）", text: $draft.nameOverride)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 6) {
                Image(systemName: isSearching ? "magnifyingglass" : "wand.and.stars")
                Text(statusText)
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .onDisappear { searchTask?.cancel() }
    }

    private var statusText: String {
        if isSearching { return "正在检索候选代码…" }
        if let market = draft.selectedMarket { return "已选择：\(market.label)，保存后按该市场搜索" }
        if let market = draft.original?.resolvedMarket { return "当前识别：\(market.label)" }
        return "输入代码后选择候选，保存后生效"
    }

    private var suggestionPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(10)) { suggestion in
                Button {
                    apply(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(suggestion.subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 300, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                if suggestion.id != suggestions.prefix(10).last?.id { Divider() }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        .shadow(radius: 8, y: 3)
    }

    private func scheduleSearch(for text: String) {
        draft.selectedMarket = nil
        searchTask?.cancel()
        suggestions = []
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            let result = await searchSuggestions(for: query)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = result
                isSearching = false
            }
        }
    }

    private func searchSuggestions(for query: String) async -> [CodeSuggestion] {
        let remote = await SinaSuggestFetcher.search(query: query).map {
            SearchCandidate(candidate: $0.candidate,
                            rawCode: $0.rawCode,
                            name: $0.name,
                            requiresQuote: false)
        }
        let candidates = Array(uniqueSearchCandidates(supplementalCandidates(for: query) + remote).prefix(20))
        guard !candidates.isEmpty else { return [] }

        let planned = candidates.map { candidate in
            (candidate, WatchedItem(rawCode: candidate.rawCode, marketOverride: candidate.candidate.market))
        }
        let quotes = (try? await QuoteFetcher.fetch(items: planned.map { $0.1 })) ?? [:]
        return Array(planned.compactMap { candidate, item -> CodeSuggestion? in
            if let quote = quotes[item.id] {
                return CodeSuggestion(rawCode: candidate.rawCode,
                                      market: candidate.candidate.market,
                                      symbol: quote.symbol,
                                      name: quote.name,
                                      price: quote.price,
                                      hasQuote: true)
            }
            guard !candidate.requiresQuote else { return nil }
            return CodeSuggestion(rawCode: candidate.rawCode,
                                  market: candidate.candidate.market,
                                  symbol: candidate.candidate.symbol,
                                  name: candidate.name,
                                  price: nil,
                                  hasQuote: false)
        }.prefix(10))
    }

    private func supplementalCandidates(for query: String) -> [SearchCandidate] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "GDS_", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return [] }

        var codes: [String] = []
        if normalized.allSatisfy(\.isNumber), (4...5).contains(normalized.count) {
            codes.append("AU" + normalized)
        } else if isExplicitSGECode(normalized) {
            codes.append(normalized)
        }

        return codes.map { code in
            let symbol = Market.goldSGE.apiSymbol(rawCode: code)
            return SearchCandidate(candidate: .init(symbol: symbol, market: .goldSGE),
                                   rawCode: code,
                                   name: "上金所",
                                   requiresQuote: true)
        }
    }

    private func isExplicitSGECode(_ code: String) -> Bool {
        code.hasPrefix("AU") || code.hasPrefix("AG") || code.hasPrefix("MAU") || code.hasPrefix("IAU")
    }

    private func uniqueSearchCandidates(_ candidates: [SearchCandidate]) -> [SearchCandidate] {
        var seen = Set<String>()
        var result: [SearchCandidate] = []
        for candidate in candidates {
            let key = candidate.candidate.symbol.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    private func apply(_ suggestion: CodeSuggestion) {
        draft.rawCode = suggestion.rawCode
        draft.selectedMarket = suggestion.market
        if draft.nameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.nameOverride = suggestion.name
        }
        suggestions = []
        searchTask?.cancel()
        isSearching = false
    }
}

// MARK: - 价格提醒

private struct AlertsSection: View {
    @ObservedObject var alerts: AlertStore
    @ObservedObject var watch: WatchStore

    /// 监控列表中有效（code 非空）的 item，用于提醒绑定
    private var validItems: [WatchedItem] {
        watch.items.filter { !$0.rawCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("价格提醒").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(alerts.alerts.count) / \(AlertStore.maxAlerts)")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text("为监控列表中的任意条目设置价格穿越提醒（交易时段内生效）。")
                .font(.system(size: 11)).foregroundColor(.secondary)

            if validItems.isEmpty && !alerts.alerts.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("监控列表为空，提醒已暂停。")
                        .font(.system(size: 12))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
            }

            if alerts.alerts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 24)).foregroundColor(.secondary)
                    Text("还没有提醒")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach($alerts.alerts) { $alert in
                        AlertRow(alert: $alert, items: validItems) {
                            alerts.remove(alert.id)
                        }
                    }
                }
            }

            HStack {
                Button {
                    // 默认绑定到第一个有效监控项
                    if let first = validItems.first {
                        alerts.add(itemId: first.id)
                    }
                } label: {
                    Label("添加提醒", systemImage: "plus.circle.fill")
                }
                .disabled(alerts.alerts.count >= AlertStore.maxAlerts || validItems.isEmpty)
                Spacer()
            }
        }
        .padding(14)
    }
}

private struct AlertRow: View {
    @Binding var alert: PriceAlert
    let items: [WatchedItem]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 绑定品种选择器（仅当有多个监控项时才显示，单项时省略）
            if items.count > 1 {
                Picker("", selection: $alert.itemId) {
                    ForEach(items) { item in
                        Text(item.nameOverride?.nilIfEmpty ?? item.fallbackName)
                            .tag(item.id)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            } else if let only = items.first {
                Text(only.nameOverride?.nilIfEmpty ?? only.fallbackName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                    .onAppear {
                        // 修复旧数据：如果 itemId 不匹配任何已知 item，自动更正
                        if !items.contains(where: { $0.id == alert.itemId }) {
                            alert.itemId = only.id
                        }
                    }
            }

            Picker("", selection: $alert.direction) {
                ForEach(AlertDirection.allCases) { d in
                    Text(d.label).tag(d)
                }
            }
            .labelsHidden().frame(width: 96)

            TextField("阈值", value: $alert.threshold,
                      format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)

            Picker("", selection: $alert.repeatMode) {
                ForEach(AlertRepeat.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .labelsHidden().frame(width: 80)

            Spacer(minLength: 0)

            Toggle("", isOn: $alert.enabled)
                .toggleStyle(.switch).controlSize(.small).labelsHidden()

            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
        .opacity(alert.enabled ? 1.0 : 0.55)
    }
}
