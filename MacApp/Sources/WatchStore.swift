import Foundation
import SwiftUI

/// 监控列表的持久化和增删改。
/// 首次启动给 5 个跨市场头部市值股票作为示例，让用户开箱即用，无需先去配置。
final class WatchStore: ObservableObject {
    static let maxItems = 30
    private let key = "WatchedItems.v2"
    private let legacyKey = "WatchedItems.v1"

    /// 首次启动的默认监控项（跨 A 股 / 港股 / 美股，各市场头部市值代表）。
    /// 用户进入"设置…"后可任意增删，删除全部后下次启动**不会**再回填（持久化为空数组而非 nil）。
    private static let defaultItems: [WatchedItem] = [
        WatchedItem(rawCode: "600519"),   // 贵州茅台
        WatchedItem(rawCode: "300750"),   // 宁德时代
        WatchedItem(rawCode: "00700"),    // 腾讯控股
        WatchedItem(rawCode: "00005"),    // 汇丰控股
        WatchedItem(rawCode: "AAPL"),     // 苹果
    ]

    @Published var items: [WatchedItem] = [] {
        didSet { save() }
    }

    init() {
        // 仅在 UserDefaults 中**完全不存在 key** 时才回填默认值。
        // 用户清空列表后，存的是空数组（key 存在但值为 []），不会再被覆盖。
        if UserDefaults.standard.data(forKey: key) == nil,
           UserDefaults.standard.data(forKey: legacyKey) == nil {
            items = Self.defaultItems
        } else {
            load()
        }
    }

    // MARK: - 持久化

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WatchedItem].self, from: data) {
            items = decoded
            return
        }
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode([WatchedItem].self, from: data) {
            items = decoded
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - 增删改

    func add(rawCode: String = "") {
        guard items.count < Self.maxItems else { return }
        items.insert(WatchedItem(rawCode: rawCode), at: 0)
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func markResolved(itemId: UUID, quote: Quote) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        var item = items[idx]
        let changed = item.resolvedSymbol != quote.symbol ||
            item.resolvedMarket != quote.market ||
            item.resolvedName != quote.name ||
            item.resolutionFailed
        guard changed else { return }
        item.resolvedSymbol = quote.symbol
        item.resolvedMarket = quote.market
        item.resolvedName = quote.name
        item.resolvedAt = Date()
        item.resolutionFailed = false
        items[idx] = item
    }

    func markUnresolved(itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        var item = items[idx]
        guard !item.rawCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.resolutionFailed || item.resolvedSymbol != nil || item.resolvedMarket != nil else { return }
        item.resolvedSymbol = nil
        item.resolvedMarket = nil
        item.resolvedName = nil
        item.resolvedAt = Date()
        item.resolutionFailed = true
        items[idx] = item
    }
}
