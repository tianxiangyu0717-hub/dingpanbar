import SwiftUI

@main
struct GoldAU9999App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 手表 App 主界面：打开时每 60 秒实时刷新。
struct ContentView: View {
    @State private var quote: GoldQuote?
    @State private var errorText: String?
    @State private var loading = false

    // 交易时段内 60 秒刷新；非时段也刷新（拿到的是最后成交价）
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            Text("AU9999 上海金")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let q = quote {
                Text(q.priceText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(q.isUp ? .red : .green)
                Text(q.changeText)
                    .font(.caption)
                    .foregroundStyle(q.isUp ? .red : .green)
                Divider()
                Group {
                    Text("今开 \(fmt(q.open))   昨收 \(fmt(q.prevClose))")
                    Text("最高 \(fmt(q.high))   最低 \(fmt(q.low))")
                    Text("更新 \(q.time)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            } else if let e = errorText {
                Text(e).font(.footnote).foregroundStyle(.orange)
            } else {
                ProgressView()
            }

            Button {
                Task { await refresh() }
            } label: {
                Label(loading ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
                    .font(.caption2)
            }
            .disabled(loading)
            .padding(.top, 2)
        }
        .padding(.horizontal, 6)
        .task { await refresh() }
        .onReceive(timer) { _ in Task { await refresh() } }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            quote = try await GoldFetcher.fetch()
            errorText = nil
        } catch {
            if quote == nil { errorText = "获取失败，下拉/点刷新重试" }
        }
    }
}
