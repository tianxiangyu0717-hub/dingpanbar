import AppKit

struct SparklinePoint: Codable, Equatable {
    let price: Double
}

struct SparklineSeries: Codable, Equatable {
    let points: [SparklinePoint]

    var prices: [Double] { points.map(\.price).filter { $0.isFinite && $0 > 0 } }
}

enum SparklineFetcher {
    static func fetch(quotes: [UUID: Quote]) async -> [UUID: SparklineSeries] {
        await withTaskGroup(of: (UUID, SparklineSeries?).self) { group in
            for (id, quote) in quotes {
                group.addTask {
                    if let series = try? await fetch(quote: quote), series.prices.count >= 2 {
                        return (id, series)
                    }
                    return (id, nil)
                }
            }

            var result: [UUID: SparklineSeries] = [:]
            for await (id, series) in group {
                if let series {
                    result[id] = series
                }
            }
            return result
        }
    }

    private static func fetch(quote: Quote) async throws -> SparklineSeries? {
        guard let url = url(for: quote) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: req)
        let body = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .isoLatin1) ?? ""
        let prices = parsePrices(body: body, market: quote.market)
        guard prices.count >= 2 else { return nil }
        return SparklineSeries(points: prices.map { SparklinePoint(price: $0) })
    }

    private static func url(for quote: Quote) -> URL? {
        switch quote.market {
        case .stockA:
            return URL(string: "https://quotes.sina.cn/cn/api/jsonp_v2.php/var%20_\(quote.symbol)_1=/CN_MarketDataService.getKLineData?symbol=\(quote.symbol)&scale=1&ma=no&datalen=242")
        case .stockHK:
            let code = quote.symbol.replacingOccurrences(of: "hk", with: "")
            return URL(string: "https://quotes.sina.cn/hk/api/openapi.php/HK_MinlineService.getMinline?symbol=\(code)")
        case .stockUS:
            let code = usMinuteSymbol(for: quote.symbol)
            return URL(string: "https://stock.finance.sina.com.cn/usstock/api/jsonp.php/var%20\(quote.symbol)=/US_MinKService.getMinK?symbol=\(code)&type=1")
        case .goldSGE:
            let code = quote.symbol.replacingOccurrences(of: "gds_", with: "").uppercased()
            return URL(string: "https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=118.\(code)&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11&fields2=f51,f52,f53,f54,f55,f56,f57,f58&iscr=0&ndays=1")
        case .fund:
            guard let symbol = exchangeFundSymbol(for: quote.symbol) else { return nil }
            return URL(string: "https://quotes.sina.cn/cn/api/jsonp_v2.php/var%20_\(symbol)_1=/CN_MarketDataService.getKLineData?symbol=\(symbol)&scale=1&ma=no&datalen=242")
        case .future:
            let code = futureMinuteSymbol(for: quote.symbol)
            return URL(string: "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var%20t1\(quote.symbol)=/InnerFuturesNewService.getFewMinLine?symbol=\(code)&type=1")
        }
    }

    private static func parsePrices(body: String, market: Market) -> [Double] {
        switch market {
        case .stockA:
            return parseLatestObjectRows(body: body, dateKey: "day", priceKey: "close")
        case .stockHK:
            return parseHKLatestTradingDayPrices(body)
        case .stockUS:
            return parseLatestObjectRows(body: body, dateKey: "d", priceKey: "c")
        case .goldSGE:
            return parseEastMoneyTrendPrices(body)
        case .fund:
            return parseLatestObjectRows(body: body, dateKey: "day", priceKey: "close")
        case .future:
            return parseLatestObjectRows(body: body, dateKey: "d", priceKey: "c")
        }
    }

    private static func matches(_ text: String, pattern: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return Double(ns.substring(with: m.range(at: 1)))
        }
    }

    private static func usMinuteSymbol(for symbol: String) -> String {
        let raw = symbol.replacingOccurrences(of: "gb_", with: "").uppercased()
        switch raw {
        case "NDX": return ".NDX"
        case "IXIC": return ".IXIC"
        case "DJI": return ".DJI"
        case "INX", "SPX", "GSPC": return ".INX"
        default: return raw
        }
    }

    private static func futureMinuteSymbol(for symbol: String) -> String {
        if let underscore = symbol.firstIndex(of: "_") {
            return String(symbol[symbol.index(after: underscore)...]).uppercased()
        }
        return symbol.uppercased()
    }

    private static func exchangeFundSymbol(for symbol: String) -> String? {
        let code = symbol.replacingOccurrences(of: "fu_", with: "")
                         .replacingOccurrences(of: "f_", with: "")
                         .uppercased()
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
        if code.hasPrefix("5") {
            return "sh" + code
        }
        if code.hasPrefix("1") {
            return "sz" + code
        }
        return nil
    }

    /// 新浪分钟接口常返回多个交易日；状态栏只画当日/最近交易日，不跨日拼接。
    private static func parseLatestObjectRows(body: String, dateKey: String, priceKey: String) -> [Double] {
        let pattern = #"\{[^{}]*""# + dateKey + #""\s*:\s*"([^"]+)"[^{}]*""# + priceKey + #""\s*:\s*"([0-9.]+)"[^{}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return matches(body, pattern: #"""# + priceKey + #""\s*:\s*"([0-9.]+)""#)
        }
        let ns = body as NSString
        let rows = regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m -> (String, Double)? in
            guard m.numberOfRanges > 2,
                  let price = Double(ns.substring(with: m.range(at: 2))) else { return nil }
            let datetime = ns.substring(with: m.range(at: 1))
            return (tradingDatePrefix(datetime), price)
        }
        guard let latestDate = rows.last?.0 else { return rows.map(\.1) }
        return rows.filter { $0.0 == latestDate }.map(\.1)
    }

    /// 东方财富趋势接口 trends: ["yyyy-MM-dd HH:mm,open,close,high,low,..."]。
    /// 上金所夜盘会自然跨日，ndays=1 已经代表一个交易日，因此这里不按自然日截断。
    private static func parseEastMoneyTrendPrices(_ body: String) -> [Double] {
        let pattern = #""\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2},[0-9.]+,([0-9.]+),[0-9.]+,[0-9.]+"#
        return matches(body, pattern: pattern)
    }

    private static func tradingDatePrefix(_ datetime: String) -> String {
        String(datetime.prefix(10))
    }

    /// 港股分钟接口会返回多个交易日的二维数组：
    /// data: [[{date: day1, ...}, ...], [{date: day2, ...}, ...]]
    /// 状态栏要展示"当日 / 上个交易日 1d"，因此只取最后一个带 date 的交易日片段。
    private static func parseHKLatestTradingDayPrices(_ body: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\s*\{\s*"date"\s*:"#) else {
            return matches(body, pattern: #""price"\s*:\s*"([0-9.]+)""#)
        }
        let ns = body as NSString
        let hits = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        guard let last = hits.last else {
            return matches(body, pattern: #""price"\s*:\s*"([0-9.]+)""#)
        }
        let latestSlice = ns.substring(from: last.range.location)
        return matches(latestSlice, pattern: #""price"\s*:\s*"([0-9.]+)""#)
    }
}

enum SparklineRenderer {
    static let size = NSSize(width: 40, height: 14)

    static func attachment(for series: SparklineSeries,
                           isUpFromOpen: Bool,
                           colorMode: TrendColorMode,
                           appearance: NSAppearance?) -> NSAttributedString {
        let image = image(for: series,
                          isUpFromOpen: isUpFromOpen,
                          colorMode: colorMode,
                          appearance: appearance)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: size.width, height: size.height)
        return NSAttributedString(attachment: attachment)
    }

    static func image(for series: SparklineSeries,
                      isUpFromOpen: Bool,
                      colorMode: TrendColorMode,
                      appearance: NSAppearance?) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let draw: () -> Void = {
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()

            let prices = series.prices
            guard prices.count >= 2 else { return }
            let minV = prices.min() ?? 0
            let maxV = prices.max() ?? 0
            let span = max(maxV - minV, max(maxV, 1) * 0.002)
            let insetX: CGFloat = 1.5
            let insetY: CGFloat = 2
            let w = size.width - insetX * 2
            let h = size.height - insetY * 2

            let path = NSBezierPath()
            for (idx, price) in prices.enumerated() {
                let x = insetX + CGFloat(idx) / CGFloat(max(prices.count - 1, 1)) * w
                let y = insetY + CGFloat((price - minV) / span) * h
                let p = NSPoint(x: x, y: y)
                if idx == 0 {
                    path.move(to: p)
                } else {
                    path.line(to: p)
                }
            }

            NSColor.labelColor.withAlphaComponent(0.92).setStroke()
            path.lineWidth = 1.15
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            let lastY = insetY + CGFloat(((prices.last ?? minV) - minV) / span) * h
            let dot = NSRect(x: size.width - 3.5, y: lastY - 1.5, width: 3, height: 3)
            colorMode.color(isUp: isUpFromOpen).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        if let appearance {
            appearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        return image
    }
}
