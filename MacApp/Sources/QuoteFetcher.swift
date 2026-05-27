import Foundation

enum QuoteFetchError: Error {
    case invalidURL
    case decodeFailed
}

/// 通用行情拉取。先为每个用户输入生成候选 symbol，再批量请求新浪接口，选第一个有效候选。
enum QuoteFetcher {
    static func fetch(items: [WatchedItem]) async throws -> [UUID: Quote] {
        let plans = items.map { item -> (item: WatchedItem, candidates: [SymbolResolver.Candidate]) in
            let candidates: [SymbolResolver.Candidate]
            if let market = item.marketOverride {
                candidates = [SymbolResolver.Candidate(symbol: market.apiSymbol(rawCode: item.rawCode), market: market)]
            } else if let symbol = item.resolvedSymbol, let market = item.resolvedMarket {
                candidates = [SymbolResolver.Candidate(symbol: symbol, market: market)] +
                    SymbolResolver.candidates(for: item.rawCode).filter { $0.symbol != symbol }
            } else {
                candidates = SymbolResolver.candidates(for: item.rawCode)
            }
            return (item, candidates)
        }

        let symbols = unique(plans.flatMap(\.candidates).map(\.symbol))
        guard !symbols.isEmpty else { return [:] }
        guard let url = URL(string: "https://hq.sinajs.cn/list=" + symbols.joined(separator: ",")) else {
            throw QuoteFetchError.invalidURL
        }

        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: req)
        let body = decodeSinaBody(data)
        let payloads = responsePayloads(body)

        var result: [UUID: Quote] = [:]
        for plan in plans {
            for candidate in plan.candidates {
                guard let fields = payloads[candidate.symbol.lowercased()], !fields.isEmpty else { continue }
                if let q = parse(fields: fields, candidate: candidate, item: plan.item) {
                    result[plan.item.id] = q
                    break
                }
            }
        }
        return result
    }

    // MARK: - Response

    private static func decodeSinaBody(_ data: Data) -> String {
        let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        if let s = String(data: data, encoding: String.Encoding(rawValue: ns)) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func responsePayloads(_ body: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        let lines = body.components(separatedBy: CharacterSet(charactersIn: "\n\r")).filter { !$0.isEmpty }
        for line in lines {
            guard let start = line.range(of: "var hq_str_"),
                  let eq = line[start.upperBound...].firstIndex(of: "="),
                  let openQ = line[eq...].firstIndex(of: "\""),
                  let closeQ = line.lastIndex(of: "\""),
                  openQ < closeQ else { continue }
            let symbol = String(line[start.upperBound..<eq])
            let payload = String(line[line.index(after: openQ)..<closeQ])
            guard !payload.isEmpty else { continue }
            result[symbol.lowercased()] = payload.components(separatedBy: ",")
        }
        return result
    }

    // MARK: - Parse

    private static func parse(fields f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        switch candidate.market {
        case .goldSGE: return parseGold(f, candidate: candidate, item: item)
        case .stockA:  return parseA(f, candidate: candidate, item: item)
        case .stockHK: return parseHK(f, candidate: candidate, item: item)
        case .stockUS: return parseUS(f, candidate: candidate, item: item)
        case .fund:    return parseFund(f, candidate: candidate, item: item)
        case .future:  return parseFuture(f, candidate: candidate, item: item)
        }
    }

    /// SGE 黄金/白银 gds_*：[0]现价 [4]最高 [5]最低 [6]时间 [7]昨收 [8]今开 [12]日期 [13]名称
    private static func parseGold(_ f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        guard f.count >= 13 else { return nil }
        let price = Double(f[0]) ?? 0
        guard price > 0 else { return nil }
        let apiName = f.count > 13 ? f[13].trimmingCharacters(in: .whitespaces) : ""
        let name = item.nameOverride?.nilIfEmpty ?? apiName.nilIfEmpty ?? item.normalizedRawCode
        let prevClose = Double(f[7]) ?? 0
        let open = Double(f[8]) ?? 0
        let high = Double(f[4]) ?? 0
        let low = Double(f[5]) ?? 0
        let date = f[12]
        let time = f[6]
        let isTrading = candidate.market.isTradingNow()
        let details = detailSections(symbol: candidate.symbol,
                                     market: candidate.market,
                                     name: name,
                                     price: price,
                                     prevClose: prevClose,
                                     open: open,
                                     high: high,
                                     low: low,
                                     date: date,
                                     time: time,
                                     isTrading: isTrading,
                                     extra: [
                                        QuoteDetailSection(title: "上金所", rows: compactRows([
                                            row("涨跌方向", f[safe: 1]),
                                            row("昨结/参考", f[safe: 2]),
                                            row("收盘/最新", f[safe: 3]),
                                            row("成交量", volumeString(f[safe: 9])),
                                            row("涨跌额", f[safe: 10]),
                                            row("持仓/参考", f[safe: 11]),
                                        ]))
                                     ],
                                     rawFields: f)
        return Quote(
            symbol: candidate.symbol,
            market: candidate.market,
            name: name,
            price: price,
            prevClose: prevClose,
            open: open,
            high: high,
            low: low,
            date: date,
            time: time,
            isTrading: isTrading,
            detailSections: details
        )
    }

    /// A 股 sh/sz：[0]name [1]open [2]prev [3]price [4]high [5]low ... [30]date [31]time
    private static func parseA(_ f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        guard f.count >= 32 else { return nil }
        let price = Double(f[3]) ?? 0
        guard price > 0 else { return nil }
        let name = item.nameOverride?.nilIfEmpty ?? f[0]
        let prevClose = Double(f[2]) ?? 0
        let open = Double(f[1]) ?? 0
        let high = Double(f[4]) ?? 0
        let low = Double(f[5]) ?? 0
        let date = f[30]
        let time = f[31]
        let isTrading = candidate.market.isTradingNow()
        let details = detailSections(symbol: candidate.symbol,
                                     market: candidate.market,
                                     name: name,
                                     price: price,
                                     prevClose: prevClose,
                                     open: open,
                                     high: high,
                                     low: low,
                                     date: date,
                                     time: time,
                                     isTrading: isTrading,
                                     extra: [
                                        QuoteDetailSection(title: "成交", rows: compactRows([
                                            row("成交量", volumeString(f[safe: 8])),
                                            row("成交额", amountString(f[safe: 9])),
                                        ])),
                                        QuoteDetailSection(title: "五档买盘", rows: levelRows(fields: f, start: 10, prefix: "买")),
                                        QuoteDetailSection(title: "五档卖盘", rows: levelRows(fields: f, start: 20, prefix: "卖")),
                                     ],
                                     rawFields: f)
        return Quote(
            symbol: candidate.symbol,
            market: candidate.market,
            name: name,
            price: price,
            prevClose: prevClose,
            open: open,
            high: high,
            low: low,
            date: date,
            time: time,
            isTrading: isTrading,
            detailSections: details
        )
    }

    /// 港股 hk：[0]英文名 [1]中文名 [2]open [3]prev [4]high [5]low [6]price ... [17]date [18]time
    private static func parseHK(_ f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        guard f.count >= 19 else { return nil }
        let price = Double(f[6]) ?? 0
        guard price > 0 else { return nil }
        let cn = f[1].trimmingCharacters(in: .whitespaces)
        let en = f[0].trimmingCharacters(in: .whitespaces)
        let name = item.nameOverride?.nilIfEmpty ?? (cn.isEmpty ? en : cn)
        let prevClose = Double(f[3]) ?? 0
        let open = Double(f[2]) ?? 0
        let high = Double(f[4]) ?? 0
        let low = Double(f[5]) ?? 0
        let date = f[17]
        let time = f[18]
        let isTrading = candidate.market.isTradingNow()
        let details = detailSections(symbol: candidate.symbol,
                                     market: candidate.market,
                                     name: name,
                                     price: price,
                                     prevClose: prevClose,
                                     open: open,
                                     high: high,
                                     low: low,
                                     date: date,
                                     time: time,
                                     isTrading: isTrading,
                                     extra: [
                                        QuoteDetailSection(title: "港股补充", rows: compactRows([
                                            row("英文名", en.nilIfEmpty),
                                            row("买入价", priceString(f[safe: 9])),
                                            row("卖出价", priceString(f[safe: 10])),
                                            row("成交额", amountString(f[safe: 11])),
                                            row("成交量", volumeString(f[safe: 12])),
                                            row("52 周最高", priceString(f[safe: 15])),
                                            row("52 周最低", priceString(f[safe: 16])),
                                        ]))
                                     ],
                                     rawFields: f)
        return Quote(
            symbol: candidate.symbol,
            market: candidate.market,
            name: name,
            price: price,
            prevClose: prevClose,
            open: open,
            high: high,
            low: low,
            date: date,
            time: time,
            isTrading: isTrading,
            detailSections: details
        )
    }

    /// 美股 gb_：[0]name [1]price [2]change_amount [3]"YYYY-MM-DD HH:mm:ss"
    private static func parseUS(_ f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        guard f.count >= 8 else { return nil }
        let price = Double(f[1]) ?? 0
        guard price > 0 else { return nil }
        var prev: Double = 0
        if f.count > 26, let v = Double(f[26]), v > 0 { prev = v }
        if prev == 0, let change = Double(f[2]) { prev = price - change }
        let dt = f[3].components(separatedBy: " ")
        let date = dt.first ?? ""
        let time = dt.count > 1 ? dt.dropFirst().joined(separator: " ") : ""
        let name = item.nameOverride?.nilIfEmpty ?? f[0]
        let open = Double(f[5]) ?? 0
        let high = Double(f[6]) ?? 0
        let low = Double(f[7]) ?? 0
        let isTrading = candidate.market.isTradingNow()
        let details = detailSections(symbol: candidate.symbol,
                                     market: candidate.market,
                                     name: name,
                                     price: price,
                                     prevClose: prev,
                                     open: open,
                                     high: high,
                                     low: low,
                                     date: date,
                                     time: time,
                                     isTrading: isTrading,
                                     extra: [
                                        QuoteDetailSection(title: "美股补充", rows: compactRows([
                                            row("涨跌额", signedPriceString(f[safe: 2])),
                                            row("涨跌幅", percentString(f[safe: 4])),
                                            row("52 周最高", priceString(f[safe: 8])),
                                            row("52 周最低", priceString(f[safe: 9])),
                                            row("成交量", volumeString(f[safe: 10])),
                                            row("平均成交量", volumeString(f[safe: 11])),
                                            row("市值", amountString(f[safe: 12])),
                                            row("市盈率/参考", f[safe: 14]),
                                            row("盘前/盘后价", priceString(f[safe: 21])),
                                            row("盘前/盘后涨跌幅", percentString(f[safe: 22])),
                                            row("盘前/盘后涨跌额", signedPriceString(f[safe: 23])),
                                            row("盘前/盘后时间", f[safe: 24]),
                                            row("常规收盘时间", f[safe: 25]),
                                            row("昨收", priceString(f[safe: 26])),
                                            row("盘前/盘后量", volumeString(f[safe: 27])),
                                        ]))
                                     ],
                                     rawFields: f)
        return Quote(
            symbol: candidate.symbol,
            market: candidate.market,
            name: name,
            price: price,
            prevClose: prev,
            open: open,
            high: high,
            low: low,
            date: date,
            time: time,
            isTrading: isTrading,
            detailSections: details
        )
    }

    /// 基金 f_/fu_：常见格式为 [0]名称 [1]时间 [2]估值/最新 [3]净值 [4]累计 [6]涨跌幅 [7]日期。
    private static func parseFund(_ f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        guard f.count >= 4 else { return nil }
        let price = Double(f[safe: 2] ?? "") ?? Double(f[safe: 3] ?? "") ?? 0
        guard price > 0 else { return nil }
        let pct = Double(f[safe: 6] ?? "") ?? 0
        let prev = pct == 0 ? price : price / (1 + pct / 100)
        let name = item.nameOverride?.nilIfEmpty ?? (f[safe: 0]?.nilIfEmpty ?? item.normalizedRawCode)
        let date = f[safe: 7] ?? f[safe: 4] ?? ""
        let time = f[safe: 1] ?? ""
        let isTrading = candidate.market.isTradingNow()
        let details = detailSections(symbol: candidate.symbol,
                                     market: candidate.market,
                                     name: name,
                                     price: price,
                                     prevClose: prev,
                                     open: prev,
                                     high: max(price, prev),
                                     low: min(price, prev),
                                     date: date,
                                     time: time,
                                     isTrading: isTrading,
                                     extra: [
                                        QuoteDetailSection(title: "基金补充", rows: compactRows([
                                            row("接口字段 1", f[safe: 1]),
                                            row("接口字段 2", f[safe: 2]),
                                            row("接口字段 3", f[safe: 3]),
                                            row("接口字段 4", f[safe: 4]),
                                            row("接口字段 5", f[safe: 5]),
                                            row("接口字段 6", f[safe: 6]),
                                        ]))
                                     ],
                                     rawFields: f)
        return Quote(
            symbol: candidate.symbol,
            market: candidate.market,
            name: name,
            price: price,
            prevClose: prev,
            open: prev,
            high: max(price, prev),
            low: min(price, prev),
            date: date,
            time: time,
            isTrading: isTrading,
            detailSections: details
        )
    }

    /// 期货 nf_/df_/sf_/cf_/ff_：新浪期货字段在不同交易所略有差异，这里做容错解析。
    /// 常见连续合约返回 [0]名称 [1]最新/开盘 [2]买/最新 [3]卖/最低 ... 日期时间位于尾部。
    private static func parseFuture(_ f: [String], candidate: SymbolResolver.Candidate, item: WatchedItem) -> Quote? {
        guard f.count >= 4 else { return nil }
        let numeric = f.dropFirst().compactMap { Double($0) }.filter { $0.isFinite && $0 > 0 }
        guard let price = numeric.first else { return nil }
        let prev = numeric.dropFirst().first ?? price
        let high = numeric.max() ?? price
        let low = numeric.min() ?? price
        let name = item.nameOverride?.nilIfEmpty ?? (f[safe: 0]?.nilIfEmpty ?? item.normalizedRawCode)
        let date = f.dropLast().last ?? ""
        let time = f.last ?? ""
        let isTrading = candidate.market.isTradingNow()
        let details = detailSections(symbol: candidate.symbol,
                                     market: candidate.market,
                                     name: name,
                                     price: price,
                                     prevClose: prev,
                                     open: prev,
                                     high: high,
                                     low: low,
                                     date: date,
                                     time: time,
                                     isTrading: isTrading,
                                     extra: [
                                        QuoteDetailSection(title: "期货补充", rows: compactRows([
                                            row("买价/参考", priceString(f[safe: 2])),
                                            row("卖价/参考", priceString(f[safe: 3])),
                                            row("昨结/参考", priceString(f[safe: 9])),
                                            row("最高/参考", priceString(f[safe: 10])),
                                            row("持仓/成交参考", volumeString(f[safe: 13])),
                                            row("成交量", volumeString(f[safe: 14])),
                                            row("交易所", f[safe: 15]),
                                            row("品种", f[safe: 16]),
                                            row("报价日期", f[safe: 17]),
                                        ]))
                                     ],
                                     rawFields: f)
        return Quote(
            symbol: candidate.symbol,
            market: candidate.market,
            name: name,
            price: price,
            prevClose: prev,
            open: prev,
            high: high,
            low: low,
            date: date,
            time: time,
            isTrading: isTrading,
            detailSections: details
        )
    }

    // MARK: - Detail panel

    private static func detailSections(symbol: String,
                                       market: Market,
                                       name: String,
                                       price: Double,
                                       prevClose: Double,
                                       open: Double,
                                       high: Double,
                                       low: Double,
                                       date: String,
                                       time: String,
                                       isTrading: Bool,
                                       extra: [QuoteDetailSection],
                                       rawFields: [String]) -> [QuoteDetailSection] {
        let change = price - prevClose
        let pct = prevClose > 0 ? change / prevClose * 100 : 0
        var sections: [QuoteDetailSection] = [
            QuoteDetailSection(title: "基础", rows: compactRows([
                row("名称", name),
                row("市场", market.label),
                row("API 代码", symbol),
                row("交易状态", isTrading ? "交易中" : "休市"),
            ])),
            QuoteDetailSection(title: "价格", rows: compactRows([
                row("最新价", fixed(price)),
                row("涨跌额", signedFixed(change)),
                row("涨跌幅", signedPercent(pct)),
                row("昨收", fixed(prevClose)),
                row("今开", fixed(open)),
                row("最高", fixed(high)),
                row("最低", fixed(low)),
            ])),
            QuoteDetailSection(title: "时间", rows: compactRows([
                row("报价日期", date),
                row("报价时间", time),
            ])),
        ]
        sections.append(contentsOf: extra.filter { !$0.rows.isEmpty })
        return sections.filter { !$0.rows.isEmpty }
    }

    private static func levelRows(fields f: [String], start: Int, prefix: String) -> [QuoteDetailRow] {
        var rows: [QuoteDetailRow] = []
        for level in 0..<5 {
            let volumeIndex = start + level * 2
            let priceIndex = volumeIndex + 1
            let name = "\(prefix)\(level + 1)"
            if let price = priceString(f[safe: priceIndex]), let volume = volumeString(f[safe: volumeIndex]) {
                rows.append(QuoteDetailRow(label: name, value: "\(price) / \(volume)"))
            }
        }
        return rows
    }

    private static func compactRows(_ rows: [QuoteDetailRow?]) -> [QuoteDetailRow] {
        rows.compactMap { $0 }
    }

    private static func row(_ label: String, _ value: String?) -> QuoteDetailRow? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return QuoteDetailRow(label: label, value: value)
    }

    private static func fixed(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.2f", value)
    }

    private static func signedFixed(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%@%.2f", value >= 0 ? "+" : "", value)
    }

    private static func signedPercent(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%@%.2f%%", value >= 0 ? "+" : "", value)
    }

    private static func priceString(_ value: String?) -> String? {
        guard let value, let n = Double(value), n.isFinite else { return nil }
        return fixed(n)
    }

    private static func signedPriceString(_ value: String?) -> String? {
        guard let value, let n = Double(value), n.isFinite else { return nil }
        return signedFixed(n)
    }

    private static func percentString(_ value: String?) -> String? {
        guard let value, let n = Double(value), n.isFinite else { return nil }
        return String(format: "%.2f%%", n)
    }

    private static func volumeString(_ value: String?) -> String? {
        guard let value, let n = Double(value), n.isFinite else { return nil }
        return NumberFormatter.integer.string(from: NSNumber(value: n.rounded()))
    }

    private static func amountString(_ value: String?) -> String? {
        guard let value, let n = Double(value), n.isFinite else { return nil }
        return NumberFormatter.decimal.string(from: NSNumber(value: n.rounded())) ?? fixed(n)
    }

    private static func unique(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for s in strings where !seen.contains(s) {
            seen.insert(s)
            result.append(s)
        }
        return result
    }
}

// MARK: - 小工具

extension String {
    /// 空串 → nil；非空 → 自身。让 `nameOverride?.nilIfEmpty ?? 默认` 在空串时也走默认。
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NumberFormatter {
    static let integer: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()
}
