import Foundation
import SwiftUI

/// 持久化提醒列表 + 穿越触发检测。
/// "穿越触发" = 仅当价格从阈值另一侧跨过来时才算触发，避免阈值附近抖动反复弹。
final class AlertStore: ObservableObject {
    static let maxAlerts = 10
    private let key = "PriceAlerts.v1"

    @Published var alerts: [PriceAlert] = [] {
        didSet { save() }
    }

    /// 各 item 上次看到的价格（key = WatchedItem.id）。
    /// 首次拿到某 item 的价格时只记录，不触发——避免重启后误触发。
    private var lastPrices: [UUID: Double] = [:]

    init() { load() }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data) else { return }
        // 用 didSet 会写回去；这里直接绕过避免冗余写。
        self.alerts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - 增删改

    func add(itemId: UUID) {
        guard alerts.count < Self.maxAlerts else { return }
        alerts.append(PriceAlert(itemId: itemId))
    }

    func remove(_ id: UUID) {
        alerts.removeAll { $0.id == id }
    }

    // MARK: - 穿越触发

    /// 针对某个监控项检测穿越，返回此刻应当触发的提醒。单次提醒会被自动移除。
    /// 休市时段不触发（避免半夜推送，且休市数据是上次收盘价没意义）。
    func checkCrossings(itemId: UUID, newPrice: Double, isTrading: Bool) -> [PriceAlert] {
        defer { lastPrices[itemId] = newPrice }
        guard isTrading, let last = lastPrices[itemId] else { return [] }
        // 价格没动也不算穿越
        guard last != newPrice else { return [] }

        var triggered: [PriceAlert] = []
        for alert in alerts where alert.enabled && alert.itemId == itemId {
            switch alert.direction {
            case .above:
                // 从下方穿过阈值（last<threshold, new>=threshold）
                if last < alert.threshold && newPrice >= alert.threshold {
                    triggered.append(alert)
                }
            case .below:
                // 从上方穿过阈值（last>threshold, new<=threshold）
                if last > alert.threshold && newPrice <= alert.threshold {
                    triggered.append(alert)
                }
            }
        }
        // 单次提醒：触发即移除
        if !triggered.isEmpty {
            let onceIds = Set(triggered.filter { $0.repeatMode == .once }.map(\.id))
            if !onceIds.isEmpty {
                alerts.removeAll { onceIds.contains($0.id) }
            }
        }
        return triggered
    }
}
