import SwiftUI

@main
struct GoldPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            PhoneContentView()
        }
    }
}

/// iPhone 主界面：打开时每 60 秒实时刷新 AU9999。
/// 这个 iOS App 同时作为手表 App / 表盘复杂功能的“载体”——
/// 装到 iPhone 后，手表 App 会通过 iPhone 的「Watch」App 自动安装到手表。
struct PhoneContentView: View {
    @State private var quote: GoldQuote?
    @State private var errorText: String?
    @State private var loading = false

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            Text("AU9999 上海金")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let q = quote {
                Text(q.priceText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(q.isUp ? .red : .green)
                Text(q.changeText)
                    .font(.title3)
                    .foregroundStyle(q.isUp ? .red : .green)

                Divider().padding(.vertical, 4)

                VStack(spacing: 8) {
                    row("今开", fmt(q.open), "昨收", fmt(q.prevClose))
                    row("最高", fmt(q.high), "最低", fmt(q.low))
                    HStack {
                        Text("更新").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(q.date) \(q.time)").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(.horizontal)
            } else if let e = errorText {
                Text(e).foregroundStyle(.orange)
            } else {
                ProgressView()
            }

            Button {
                Task { await refresh() }
            } label: {
                Label(loading ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading)
            .padding(.top, 6)
        }
        .padding()
        .task { await refresh() }
        .onReceive(timer) { _ in Task { await refresh() } }
    }

    private func row(_ a: String, _ av: String, _ b: String, _ bv: String) -> some View {
        HStack {
            Text(a).foregroundStyle(.secondary)
            Text(av).bold()
            Spacer()
            Text(b).foregroundStyle(.secondary)
            Text(bv).bold()
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            quote = try await GoldFetcher.fetch()
            errorText = nil
        } catch {
            if quote == nil { errorText = "获取失败，点刷新重试" }
        }
    }
}
