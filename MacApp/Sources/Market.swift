import Foundation

/// 支持的市场。每个市场对应不同的新浪 API 符号格式和交易时段。
enum Market: String, Codable, CaseIterable, Identifiable {
    case goldSGE = "gold"   // 上海黄金交易所贵金属现货（新浪 gds_AU9999 / gds_AG9999）
    case stockA  = "a"      // A 股（新浪 sh/sz 前缀）
    case stockHK = "hk"     // 港股（新浪 hk 前缀）
    case stockUS = "us"     // 美股（新浪 gb_ 前缀）
    case fund    = "fund"   // 基金（新浪 f_/fu_ 前缀）
    case future  = "future" // 期货（新浪 nf_/df_/sf_/cf_/ff_ 等前缀）

    var id: String { rawValue }

    var label: String {
        switch self {
        case .goldSGE: return "上金所"
        case .stockA:  return "A 股"
        case .stockHK: return "港股"
        case .stockUS: return "美股"
        case .fund:    return "基金"
        case .future:  return "期货"
        }
    }

    var codeHint: String {
        switch self {
        case .goldSGE: return "如 AU9999、AG9999"
        case .stockA:  return "如 600519、000001"
        case .stockHK: return "如 00700"
        case .stockUS: return "如 AAPL、TSLA"
        case .fund:    return "如 f_510300、fu_000001"
        case .future:  return "如 nf_AU0、nf_AG0"
        }
    }

    /// 把用户输入 code 转成新浪 API 用的 symbol。
    /// 兼容用户输入带/不带前缀（sh600519 / 600519 / SH600519 都接受）。
    func apiSymbol(rawCode: String) -> String {
        let cleaned = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch self {
        case .goldSGE:
            // 接受 AU9999 / GDS_AU9999
            let stripped = cleaned.replacingOccurrences(of: "GDS_", with: "")
            return "gds_" + stripped
        case .stockA:
            // 6/9 开头 → sh，0/3 开头 → sz；用户带前缀也兼容
            let digits = cleaned.replacingOccurrences(of: "SH", with: "")
                                .replacingOccurrences(of: "SZ", with: "")
            guard let first = digits.first else { return cleaned.lowercased() }
            let prefix = (first == "6" || first == "9") ? "sh" : "sz"
            return prefix + digits
        case .stockHK:
            // 用户可能输入 00700 / HK00700 / 700。统一补 0 到 5 位。
            let digits = cleaned.replacingOccurrences(of: "HK", with: "")
            let padded = String(repeating: "0", count: max(0, 5 - digits.count)) + digits
            return "hk" + padded
        case .stockUS:
            let stripped = cleaned.replacingOccurrences(of: "GB_", with: "")
                                  .replacingOccurrences(of: "$", with: "")
            return "gb_" + stripped.lowercased()
        case .fund:
            if cleaned.hasPrefix("F_") || cleaned.hasPrefix("FU_") || cleaned.hasPrefix("OF") {
                return cleaned.lowercased()
            }
            return "f_" + cleaned
        case .future:
            if cleaned.contains("_") {
                let parts = cleaned.split(separator: "_", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return cleaned }
                return parts[0].lowercased() + "_" + parts[1].uppercased()
            }
            return "nf_" + cleaned
        }
    }

    /// 当前是否处于交易时段。
    func isTradingNow(_ now: Date = Date()) -> Bool {
        switch self {
        case .goldSGE: return Self.inGoldSGEHours(now)
        case .stockA:  return Self.inSessions(now, tz: "Asia/Shanghai",  sessions: [(570, 690), (780, 900)])
        case .stockHK: return Self.inSessions(now, tz: "Asia/Hong_Kong", sessions: [(570, 720), (780, 960)])
        case .stockUS: return Self.inSessions(now, tz: "America/New_York", sessions: [(570, 960)])
        case .fund:    return Self.inSessions(now, tz: "Asia/Shanghai", sessions: [(570, 690), (780, 900)])
        case .future:  return Self.inFuturesHours(now)
        }
    }

    /// 通用：判断当前是否在某时区的若干交易时段（用分钟数 0..1440 表达半开区间）。
    /// 仅判断周一~周五，节假日检测不到（拿不到日历），但 API 返回的"报价时间"通常能反映。
    private static func inSessions(_ now: Date, tz: String, sessions: [(Int, Int)]) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? .current
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let dow = c.weekday ?? 0     // 1=Sun ... 7=Sat
        guard dow >= 2 && dow <= 6 else { return false }
        let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        for (start, end) in sessions where mins >= start && mins < end {
            return true
        }
        return false
    }

    /// SGE 黄金现货：日盘 09:00–15:30 + 夜盘 20:00–次日 02:30，周日全天休市。
    private static func inGoldSGEHours(_ now: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let dow = c.weekday ?? 0
        let hhmm = (c.hour ?? 0) * 100 + (c.minute ?? 0)
        if dow == 1 { return false } // 周日休市
        if dow >= 2 && dow <= 6 && hhmm >= 900  && hhmm < 1530 { return true } // 日盘
        if dow >= 2 && dow <= 6 && hhmm >= 2000 { return true }                 // 夜盘
        if dow >= 3 && dow <= 7 && hhmm < 230   { return true }                 // 夜盘跨午夜
        return false
    }

    /// 国内期货泛化交易时段：日盘 09:00–15:00，夜盘 21:00–次日 02:30。
    /// 不同品种夜盘略有差异；这里作为状态栏泛化展示，不替代交易所精确日历。
    private static func inFuturesHours(_ now: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let dow = c.weekday ?? 0
        let hhmm = (c.hour ?? 0) * 100 + (c.minute ?? 0)
        if dow == 1 { return false }
        if dow >= 2 && dow <= 6 && hhmm >= 900 && hhmm < 1500 { return true }
        if dow >= 2 && dow <= 6 && hhmm >= 2100 { return true }
        if dow >= 3 && dow <= 7 && hhmm < 230 { return true }
        return false
    }
}
