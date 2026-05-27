import Foundation

/// 监控列表中的一项：用户输入代码 + 可选自定义名称 + 自动识别缓存。
struct WatchedItem: Codable, Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var rawCode: String
    var nameOverride: String?
    /// 用户手动指定市场；nil 表示自动识别。
    var marketOverride: Market?
    var resolvedSymbol: String?
    var resolvedMarket: Market?
    var resolvedName: String?
    var resolvedAt: Date?
    var resolutionFailed: Bool

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         rawCode: String,
         nameOverride: String? = nil,
         marketOverride: Market? = nil,
         resolvedSymbol: String? = nil,
         resolvedMarket: Market? = nil,
         resolvedName: String? = nil,
         resolvedAt: Date? = nil,
        resolutionFailed: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.rawCode = rawCode
        self.nameOverride = nameOverride
        self.marketOverride = marketOverride
        self.resolvedSymbol = resolvedSymbol
        self.resolvedMarket = resolvedMarket
        self.resolvedName = resolvedName
        self.resolvedAt = resolvedAt
        self.resolutionFailed = resolutionFailed
    }

    /// 兼容 v1：旧版本是 market + code，新版本只保留 rawCode。
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, rawCode, nameOverride, marketOverride, resolvedSymbol, resolvedMarket, resolvedName, resolvedAt, resolutionFailed
        case market, code
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        if let raw = try c.decodeIfPresent(String.self, forKey: .rawCode) {
            rawCode = raw
        } else {
            rawCode = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        }
        nameOverride = try c.decodeIfPresent(String.self, forKey: .nameOverride)
        marketOverride = try c.decodeIfPresent(Market.self, forKey: .marketOverride)
        resolvedSymbol = try c.decodeIfPresent(String.self, forKey: .resolvedSymbol)
        resolvedMarket = try c.decodeIfPresent(Market.self, forKey: .resolvedMarket)
        resolvedName = try c.decodeIfPresent(String.self, forKey: .resolvedName)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        resolutionFailed = try c.decodeIfPresent(Bool.self, forKey: .resolutionFailed) ?? false

        // v1 数据迁移时，优先把旧 market/code 立刻转为已解析缓存，避免用户第一眼看到"未识别"。
        if resolvedSymbol == nil,
           let oldMarket = try c.decodeIfPresent(Market.self, forKey: .market),
           let oldCode = try c.decodeIfPresent(String.self, forKey: .code),
           !oldCode.isEmpty {
            resolvedMarket = oldMarket
            resolvedSymbol = oldMarket.apiSymbol(rawCode: oldCode)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(rawCode, forKey: .rawCode)
        try c.encodeIfPresent(nameOverride, forKey: .nameOverride)
        try c.encodeIfPresent(marketOverride, forKey: .marketOverride)
        try c.encodeIfPresent(resolvedSymbol, forKey: .resolvedSymbol)
        try c.encodeIfPresent(resolvedMarket, forKey: .resolvedMarket)
        try c.encodeIfPresent(resolvedName, forKey: .resolvedName)
        try c.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try c.encode(resolutionFailed, forKey: .resolutionFailed)
    }

    var normalizedRawCode: String {
        rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 在 API 还没返回前的占位显示名。
    var fallbackName: String {
        if let n = nameOverride, !n.isEmpty { return n }
        if let n = resolvedName, !n.isEmpty { return n }
        return normalizedRawCode
    }

    var resolvedDescription: String? {
        guard let market = resolvedMarket, let symbol = resolvedSymbol else { return nil }
        let manual = marketOverride == nil ? "" : " · 手动"
        if let name = resolvedName, !name.isEmpty {
            return "\(market.label)\(manual) · \(name) · \(symbol)"
        }
        return "\(market.label)\(manual) · \(symbol)"
    }
}
