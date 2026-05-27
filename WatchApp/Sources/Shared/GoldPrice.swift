import Foundation

/// AU9999 行情数据模型
struct GoldQuote {
    let price: Double
    let prevClose: Double
    let high: Double
    let low: Double
    let open: Double
    let time: String   // HH:mm:ss
    let date: String   // yyyy-MM-dd

    var diff: Double { price - prevClose }
    var pct: Double { prevClose == 0 ? 0 : (price - prevClose) / prevClose * 100 }
    var isUp: Bool { diff >= 0 }

    /// "996.10"
    var priceText: String { String(format: "%.2f", price) }
    /// "-3.59 (-0.36%)"
    var changeText: String {
        let s = isUp ? "+" : ""
        return String(format: "%@%.2f (%@%.2f%%)", s, diff, s, pct)
    }
}

enum GoldError: Error { case network, parse }

/// 从新浪行情接口拉取上海金 Au99.99 实时价。
/// 接口返回 GBK 编码，但我们只解析数字字段，用 isoLatin1 解码即可避开中文乱码问题。
struct GoldFetcher {
    static func fetch() async throws -> GoldQuote {
        let url = URL(string: "https://hq.sinajs.cn/list=gds_AU9999")!
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let body = String(data: data, encoding: .isoLatin1) else {
            throw GoldError.network
        }

        // body 形如: var hq_str_gds_AU9999="996.10,0,...,2026-05-19,xx";
        guard let q1 = body.firstIndex(of: "\""),
              let q2 = body.lastIndex(of: "\""), q1 < q2 else {
            throw GoldError.parse
        }
        let fields = body[body.index(after: q1)..<q2]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)

        guard fields.count >= 13,
              let price = Double(fields[0]),
              let prev = Double(fields[7]) else {
            throw GoldError.parse
        }

        return GoldQuote(
            price: price,
            prevClose: prev,
            high: Double(fields[4]) ?? price,
            low: Double(fields[5]) ?? price,
            open: Double(fields[8]) ?? price,
            time: fields[6],
            date: fields[12]
        )
    }
}
