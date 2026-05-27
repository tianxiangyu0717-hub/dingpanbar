import Foundation

struct QuoteDetailRow {
    let label: String
    let value: String
}

struct QuoteDetailSection {
    let title: String
    let rows: [QuoteDetailRow]
}

/// 通用行情数据。所有市场都映射到这个结构。
struct Quote {
    let symbol: String      // API symbol（如 sh600519、gds_AU9999）
    let market: Market      // 自动识别出的市场
    let name: String        // 名称（中文优先，否则英文，否则代码）
    let price: Double       // 现价
    let prevClose: Double   // 昨收
    let open: Double        // 今开
    let high: Double        // 最高
    let low: Double         // 最低
    let date: String        // 报价日期（API 那边）
    let time: String        // 报价时间（API 那边）
    let isTrading: Bool     // 当前是否在交易时段
    let detailSections: [QuoteDetailSection] // 菜单数据面板展示用的结构化详情

    var change: Double { price - prevClose }
    var changePercent: Double { prevClose > 0 ? change / prevClose * 100 : 0 }
    var isUp: Bool { change >= 0 }
}
