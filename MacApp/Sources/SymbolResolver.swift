import Foundation

/// 把用户输入的自由代码转成一组新浪行情候选 symbol。
enum SymbolResolver {
    struct Candidate: Hashable {
        let symbol: String
        let market: Market
    }

    static func candidates(for rawCode: String) -> [Candidate] {
        let cleaned = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty else { return [] }

        let upper = cleaned.uppercased()
        let lower = cleaned.lowercased()

        if upper.hasPrefix("GDS_") {
            return unique([Candidate(symbol: lower, market: .goldSGE)])
        }
        if upper.hasPrefix("SH") || upper.hasPrefix("SZ") {
            return unique([Candidate(symbol: lower, market: .stockA)])
        }
        if upper.hasPrefix("HK") {
            return unique([Candidate(symbol: Market.stockHK.apiSymbol(rawCode: upper), market: .stockHK)])
        }
        if upper.hasPrefix("GB_") {
            return unique([Candidate(symbol: lower, market: .stockUS)])
        }
        if upper.hasPrefix("F_") || upper.hasPrefix("FU_") {
            return unique([Candidate(symbol: lower, market: .fund)])
        }
        if upper.hasPrefix("NF_") || upper.hasPrefix("DF_") ||
           upper.hasPrefix("SF_") || upper.hasPrefix("CF_") ||
           upper.hasPrefix("FF_") {
            return unique([Candidate(symbol: lower, market: .future)])
        }

        if isPreciousMetalCode(upper) {
            return unique([Candidate(symbol: Market.goldSGE.apiSymbol(rawCode: upper), market: .goldSGE)])
        }

        if upper.allSatisfy(\.isNumber) {
            if upper.count == 6 {
                return unique([
                    Candidate(symbol: Market.stockA.apiSymbol(rawCode: upper), market: .stockA),
                    Candidate(symbol: Market.fund.apiSymbol(rawCode: upper), market: .fund),
                    Candidate(symbol: Market.stockHK.apiSymbol(rawCode: upper), market: .stockHK),
                ])
            }
            if upper.count <= 5 {
                return unique([
                    Candidate(symbol: Market.stockHK.apiSymbol(rawCode: upper), market: .stockHK),
                    Candidate(symbol: Market.stockA.apiSymbol(rawCode: upper), market: .stockA),
                ])
            }
        }

        if upper.range(of: #"^[A-Z][A-Z0-9.\-]{0,9}$"#, options: .regularExpression) != nil {
            return unique([Candidate(symbol: Market.stockUS.apiSymbol(rawCode: upper), market: .stockUS)])
        }

        return unique([
            Candidate(symbol: Market.goldSGE.apiSymbol(rawCode: upper), market: .goldSGE),
            Candidate(symbol: Market.stockUS.apiSymbol(rawCode: upper), market: .stockUS),
        ])
    }

    private static func isPreciousMetalCode(_ code: String) -> Bool {
        let known: Set<String> = [
            "AU9999", "AU9995", "AUTD", "AU_TD",
            "AG9999", "AGTD", "AG_TD",
            "MAUTD", "IAU9999",
        ]
        return known.contains(code)
    }

    private static func unique(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for c in candidates where !seen.contains(c.symbol) {
            seen.insert(c.symbol)
            result.append(c)
        }
        return result
    }
}
