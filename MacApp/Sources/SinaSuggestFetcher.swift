import Foundation

/// 新浪搜索建议接口。这里用于设置页候选列表，不参与已保存代码的行情轮询。
enum SinaSuggestFetcher {
    struct Match: Hashable {
        let candidate: SymbolResolver.Candidate
        let rawCode: String
        let name: String
    }

    static func search(query: String) async -> [Match] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        var components = URLComponents(string: "https://suggest3.sinajs.cn/suggest")
        components?.queryItems = [
            URLQueryItem(name: "type", value: ""),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "name", value: "suggestvalue"),
        ]
        guard let url = components?.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        return parse(decodeSinaBody(data))
    }

    private static func parse(_ body: String) -> [Match] {
        guard let open = body.firstIndex(of: "\""),
              let close = body.lastIndex(of: "\""),
              open < close else { return [] }
        let payload = String(body[body.index(after: open)..<close])
        guard !payload.isEmpty else { return [] }

        var matches: [Match] = []
        var seen = Set<String>()
        for row in payload.split(separator: ";").map(String.init) {
            let fields = row.components(separatedBy: ",")
            guard fields.count >= 5,
                  let market = market(forType: fields[1]) else { continue }
            let symbol = apiSymbol(fields: fields, market: market)
            guard !symbol.isEmpty, seen.insert(symbol.lowercased()).inserted else { continue }
            let rawCode = displayCode(fields: fields, symbol: symbol, market: market)
            let name = (fields[safe: 6]?.nilIfEmpty ?? fields[safe: 4]?.nilIfEmpty ?? rawCode)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            matches.append(Match(candidate: .init(symbol: symbol, market: market),
                                 rawCode: rawCode,
                                 name: name))
        }
        return matches
    }

    private static func market(forType type: String) -> Market? {
        switch type {
        case "11", "12": return .stockA
        case "31": return .stockHK
        case "41": return .stockUS
        case "21", "22", "23", "24", "25", "26", "201", "202": return .fund
        case "14", "87": return .future
        default: return nil
        }
    }

    private static func apiSymbol(fields: [String], market: Market) -> String {
        let code = fields[safe: 2] ?? ""
        let symbol = fields[safe: 3] ?? code
        switch market {
        case .stockA:
            if symbol.hasPrefix("sh") || symbol.hasPrefix("sz") { return symbol.lowercased() }
            return Market.stockA.apiSymbol(rawCode: code)
        case .stockHK:
            return Market.stockHK.apiSymbol(rawCode: code)
        case .stockUS:
            return Market.stockUS.apiSymbol(rawCode: symbol)
        case .fund:
            return symbol.lowercased()
        case .future:
            if symbol.uppercased().hasPrefix("NF_") { return Market.future.apiSymbol(rawCode: symbol) }
            return Market.future.apiSymbol(rawCode: symbol.uppercased())
        case .goldSGE:
            return Market.goldSGE.apiSymbol(rawCode: code)
        }
    }

    private static func displayCode(fields: [String], symbol: String, market: Market) -> String {
        let code = fields[safe: 2]?.nilIfEmpty ?? symbol
        switch market {
        case .stockA:
            return code.uppercased()
        case .stockHK:
            return code.uppercased()
        case .stockUS:
            return code.uppercased()
        case .fund:
            return symbol.lowercased()
        case .future:
            return code.uppercased()
        case .goldSGE:
            return symbol.replacingOccurrences(of: "gds_", with: "").uppercased()
        }
    }

    private static func decodeSinaBody(_ data: Data) -> String {
        let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        if let s = String(data: data, encoding: String.Encoding(rawValue: ns)) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
