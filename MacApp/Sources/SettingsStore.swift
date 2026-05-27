import Foundation
import AppKit
import SwiftUI

/// 状态栏轮播显示方式。
enum RotationMode: String, Codable, CaseIterable, Identifiable {
    case vertical    // 纵向上滑切换，按"轮播间隔"步进
    case horizontal  // 横向连续滚动，首尾渐隐，无间隔参数
    var id: String { rawValue }
    var label: String {
        switch self {
        case .vertical:   return "纵向切换"
        case .horizontal: return "横向滚动"
        }
    }
}

/// 涨跌颜色偏好。中国市场默认红涨绿跌；也支持国际常见的绿涨红跌。
enum TrendColorMode: String, Codable, CaseIterable, Identifiable {
    case redUpGreenDown
    case greenUpRedDown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .redUpGreenDown: return "红涨绿跌"
        case .greenUpRedDown: return "红跌绿涨"
        }
    }

    func color(isUp: Bool) -> NSColor {
        switch self {
        case .redUpGreenDown:
            return isUp ? .systemRed : .systemGreen
        case .greenUpRedDown:
            return isUp ? .systemGreen : .systemRed
        }
    }
}

/// 全局设置：刷新间隔 + 轮播间隔 + 轮播方式。
final class SettingsStore: ObservableObject {
    // 刷新间隔（秒）
    static let minInterval: TimeInterval = 5
    static let maxInterval: TimeInterval = 3600
    static let presets: [TimeInterval] = [30, 60, 120, 300, 600]

    // 轮播间隔（秒）：纵向切换时步进间隔
    static let minRotation: TimeInterval = 1
    static let maxRotation: TimeInterval = 30
    static let rotationPresets: [TimeInterval] = [1, 2, 3, 5, 10]

    private let key = "Settings.v2"

    @Published var refreshInterval: TimeInterval = 60 {
        didSet {
            let v = min(max(refreshInterval, Self.minInterval), Self.maxInterval)
            if v != refreshInterval { refreshInterval = v; return }
            save()
        }
    }

    @Published var rotationInterval: TimeInterval = 3 {
        didSet {
            let v = min(max(rotationInterval, Self.minRotation), Self.maxRotation)
            if v != rotationInterval { rotationInterval = v; return }
            save()
        }
    }

    @Published var rotationMode: RotationMode = .horizontal {
        didSet { save() }
    }

    @Published var trendColorMode: TrendColorMode = .redUpGreenDown {
        didSet { save() }
    }

    init() { load() }

    // 用自定义 init(from:) 让缺失字段使用默认值，避免增字段时旧 JSON 解码失败。
    private struct Storage: Codable {
        var refreshInterval: TimeInterval
        var rotationInterval: TimeInterval
        var rotationMode: RotationMode
        var trendColorMode: TrendColorMode

        init(refreshInterval: TimeInterval,
             rotationInterval: TimeInterval,
             rotationMode: RotationMode,
             trendColorMode: TrendColorMode) {
            self.refreshInterval = refreshInterval
            self.rotationInterval = rotationInterval
            self.rotationMode = rotationMode
            self.trendColorMode = trendColorMode
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            refreshInterval  = try c.decode(TimeInterval.self, forKey: .refreshInterval)
            rotationInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .rotationInterval) ?? 3
            rotationMode     = try c.decodeIfPresent(RotationMode.self, forKey: .rotationMode) ?? .horizontal
            trendColorMode   = try c.decodeIfPresent(TrendColorMode.self, forKey: .trendColorMode) ?? .redUpGreenDown
        }
    }

    private func load() {
        // v2
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Storage.self, from: data) {
            refreshInterval  = s.refreshInterval
            rotationInterval = s.rotationInterval
            rotationMode     = s.rotationMode
            trendColorMode   = s.trendColorMode
            return
        }
        // v1 升级
        if let data = UserDefaults.standard.data(forKey: "Settings.v1") {
            struct V1: Codable { var refreshInterval: TimeInterval }
            if let s = try? JSONDecoder().decode(V1.self, from: data) {
                refreshInterval = s.refreshInterval
                save()
            }
        }
    }

    private func save() {
        let s = Storage(refreshInterval: refreshInterval,
                        rotationInterval: rotationInterval,
                        rotationMode: rotationMode,
                        trendColorMode: trendColorMode)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) 秒" }
        if s % 60 == 0 { return "\(s / 60) 分钟" }
        return "\(s) 秒"
    }
}
