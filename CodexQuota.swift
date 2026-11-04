import AppKit
import SwiftUI

struct QuotaWindow: Identifiable {
    let id: String
    let label: String
    let remaining: Double
    let resetAt: Date?
}

@MainActor
final class QuotaModel: ObservableObject {
    @Published var windows: [QuotaWindow] = []
    @Published var status = "正在读取额度…"
    @Published var updatedAt: Date?
    func start() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
            let auth = try JSONSerialization.jsonObject(with: Data(contentsOf: authURL)) as? [String: Any] ?? [:]
            let tokens = auth["tokens"] as? [String: Any] ?? [:]
            guard let token = tokens["access_token"] as? String, !token.isEmpty else {
                status = "请先登录 Codex"
                windows = []
                return
            }
            let account = (tokens["account_id"] as? String) ?? (auth["account_id"] as? String)
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
            request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
            if let account { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw NSError(domain: "CodexQuota", code: code, userInfo: [NSLocalizedDescriptionKey: code == 401 || code == 403 ? "登录已过期，请重新登录 Codex" : "额度接口返回错误（\(code)）"])
            }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let rate = (root["rate_limit"] as? [String: Any]) ?? (root["rate_limits"] as? [String: Any]) ?? root
            var parsed: [QuotaWindow] = []
            let candidates: [(String, Any?)] = [
                ("five_hour", rate["five_hour"]), ("weekly", rate["weekly"]),
                ("primary_window", rate["primary_window"]), ("secondary_window", rate["secondary_window"]),
                ("primary", rate["primary"]), ("secondary", rate["secondary"])
            ]
            for (fallback, value) in candidates {
                guard let window = value as? [String: Any] else { continue }
                let duration = number(window["limit_window_seconds"]) ?? (fallback == "weekly" || fallback == "secondary_window" ? 604800 : 18000)
                let label = duration >= 172800 ? "一周" : "5 小时"
                let used = number(window["used_percent"]) ?? (100 - (number(window["percent_left"]) ?? 100))
                let reset = resetDate(window)
                let id = label
                if !parsed.contains(where: { $0.id == id }) {
                    parsed.append(QuotaWindow(id: id, label: label, remaining: max(0, min(100, 100 - used)), resetAt: reset))
                }
            }
            windows = parsed.sorted { $0.label == "5 小时" && $1.label != "5 小时" }
            updatedAt = Date()
            status = parsed.isEmpty ? "当前账号暂未返回额度窗口" : "额度查询成功 · 手动刷新"
        } catch {
            status = error.localizedDescription
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func resetDate(_ window: [String: Any]) -> Date? {
        if let n = number(window["reset_at"]) { return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n) }
        if let n = number(window["reset_time_ms"]) { return Date(timeIntervalSince1970: n / 1000) }
        if let n = number(window["reset_after_seconds"]) { return Date().addingTimeInterval(n) }
        if let s = window["reset_at"] as? String { return ISO8601DateFormatter().date(from: s) }
        return nil
    }
}

struct QuotaView: View {
    @ObservedObject var model: QuotaModel
    private let accent = Color(red: 0.55, green: 0.82, blue: 0.99)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(accent)
                Text("Codex 额度").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).help("立即刷新")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.55)).help("退出")
            }
            if model.windows.isEmpty {
                Text(model.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
            } else {
                ForEach(model.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.label).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(window.remaining.rounded()))% 剩余").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.13))
                                Capsule().fill(accent).frame(width: geo.size.width * window.remaining / 100)
                            }
                        }.frame(height: 4)
                        if let reset = window.resetAt {
                            Text("重置于 \(reset, style: .relative)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                Text("\(model.updatedAt.map { "更新于 \($0.formatted(date: .omitted, time: .shortened))" } ?? model.status) · 手动刷新").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14).frame(width: 230)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.13), lineWidth: 1))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private let model = QuotaModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: QuotaView(model: model))
        positionPanel()
        panel.orderFrontRegardless()
        model.start()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CodexQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}
