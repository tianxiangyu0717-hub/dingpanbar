import Foundation

/// 提醒方向：≥阈值（涨到）/ ≤阈值（跌到）。
enum AlertDirection: String, Codable, CaseIterable, Identifiable {
    case above   // 涨到 ≥
    case below   // 跌到 ≤
    var id: String { rawValue }
    var label: String {
        switch self {
        case .above: return "≥ 涨到"
        case .below: return "≤ 跌到"
        }
    }
    var symbol: String {
        switch self {
        case .above: return "≥"
        case .below: return "≤"
        }
    }
}

/// 触发模式：单次（触发后自动删除）/ 重复（每次穿越都触发）。
enum AlertRepeat: String, Codable, CaseIterable, Identifiable {
    case once
    case repeated
    var id: String { rawValue }
    var label: String {
        switch self {
        case .once: return "单次"
        case .repeated: return "重复"
        }
    }
}

/// 价格提醒。每条绑定到某个监控项（itemId 关联 WatchedItem.id）。
struct PriceAlert: Codable, Identifiable, Equatable {
    let id: UUID
    var itemId: UUID
    var direction: AlertDirection
    var threshold: Double
    var repeatMode: AlertRepeat
    var enabled: Bool

    init(id: UUID = UUID(),
         itemId: UUID,
         direction: AlertDirection = .above,
         threshold: Double = 1000,
         repeatMode: AlertRepeat = .once,
         enabled: Bool = true) {
        self.id = id
        self.itemId = itemId
        self.direction = direction
        self.threshold = threshold
        self.repeatMode = repeatMode
        self.enabled = enabled
    }
}
