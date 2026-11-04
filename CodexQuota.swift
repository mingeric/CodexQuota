import AppKit
import SwiftUI
import Darwin
import UniformTypeIdentifiers

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
    @Published var systemMemoryLabel = "内存读取中"
    private var memoryTimer: Timer?
    func start() {
        Task { await refresh() }
        updateMemory()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMemory() }
        }
    }

    private func updateMemory() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = UInt64(vm_page_size)
        let usedPages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let usedGB = Double(usedPages * pageSize) / 1_073_741_824
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        systemMemoryLabel = String(format: "内存 %.1f / %.0f GB", usedGB, totalGB)
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
    let onClose: () -> Void
    @AppStorage("panelBackgroundHex") private var savedBackgroundHex = "17212B"
    @AppStorage("panelBackgroundOpacity") private var savedBackgroundOpacity = 0.38
    @AppStorage("accentHex") private var savedAccentHex = "8CD1FC"
    @AppStorage("panelCornerRadius") private var savedCornerRadius = 15.0
    @AppStorage("skinImagePath") private var skinImagePath = ""
    @State private var draftBackgroundHex = "17212B"
    @State private var draftAccentHex = "8CD1FC"
    @State private var draftOpacity = 0.38
    @State private var draftCornerRadius = 15.0
    @State private var skinImage: NSImage?
    @State private var showingSkinEditor = false

    private var savedBackground: Color { Color(hex: savedBackgroundHex) }
    private var accent: Color { Color(hex: savedAccentHex) }
    private var textColor: Color {
        let color = NSColor(savedBackground).usingColorSpace(.deviceRGB) ?? .black
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance > 0.5 ? .black : .white
    }
    private var draftBackgroundBinding: Binding<String> {
        Binding(get: { draftBackgroundHex }, set: { draftBackgroundHex = cleanHex($0) })
    }
    private var draftAccentBinding: Binding<String> {
        Binding(get: { draftAccentHex }, set: { draftAccentHex = cleanHex($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .bold)).foregroundStyle(textColor.opacity(0.55))
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
                    .frame(width: 17, height: 17).clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Codex 额度").font(.system(size: 13, weight: .semibold))
            }
            .overlay(WindowDragHandle().accessibilityHidden(true))
            .help("拖动这里移动面板")

            HStack(spacing: 8) {
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(textColor.opacity(0.75)).help("立即刷新")
                Button {
                    draftBackgroundHex = savedBackgroundHex
                    draftAccentHex = savedAccentHex
                    draftOpacity = savedBackgroundOpacity
                    draftCornerRadius = savedCornerRadius
                    showingSkinEditor.toggle()
                } label: { Image(systemName: "paintpalette") }
                    .buttonStyle(.plain).foregroundStyle(textColor.opacity(0.75)).help("编辑背景皮肤")
                    .popover(isPresented: $showingSkinEditor, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("背景皮肤").font(.system(size: 13, weight: .semibold))
                            ColorPicker("背景颜色", selection: Binding(
                                get: { Color(hex: draftBackgroundHex) },
                                set: { draftBackgroundHex = $0.hexString }
                            ), supportsOpacity: false)
                            HStack {
                                Text("背景 HEX")
                                Spacer()
                                Text("#")
                                TextField("RRGGBB", text: draftBackgroundBinding)
                                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).frame(width: 92)
                            }
                            ColorPicker("强调色", selection: Binding(
                                get: { Color(hex: draftAccentHex) },
                                set: { draftAccentHex = $0.hexString }
                            ), supportsOpacity: false)
                            HStack {
                                Text("强调 HEX")
                                Spacer()
                                Text("#")
                                TextField("RRGGBB", text: draftAccentBinding)
                                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).frame(width: 92)
                            }
                            HStack {
                                Button("导入图片皮肤…", action: importSkin)
                                if !skinImagePath.isEmpty {
                                    Button("移除图片") { skinImagePath = ""; skinImage = nil }
                                }
                            }.font(.system(size: 11))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("透明度")
                                    Spacer()
                                    Text("\(Int(draftOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary)
                                }
                                Slider(value: $draftOpacity, in: 0.28...0.85)
                            }.font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("圆角")
                                    Spacer()
                                    Text("\(Int(draftCornerRadius)) pt").monospacedDigit().foregroundStyle(.secondary)
                                }
                                Slider(value: $draftCornerRadius, in: 4...32)
                            }.font(.system(size: 12))
                            HStack {
                                Button("默认") {
                                    draftBackgroundHex = "17212B"
                                    draftAccentHex = "8CD1FC"
                                    draftOpacity = 0.38
                                    draftCornerRadius = 15
                                }
                                Spacer()
                                Button("保存并覆盖当前皮肤") {
                                    savedBackgroundHex = draftBackgroundHex
                                    savedAccentHex = draftAccentHex
                                    savedBackgroundOpacity = draftOpacity
                                    savedCornerRadius = draftCornerRadius
                                    showingSkinEditor = false
                                }.buttonStyle(.borderedProminent)
                                    .disabled(draftBackgroundHex.count != 6 || draftAccentHex.count != 6)
                            }
                        }
                        .padding(16).frame(width: 275)
                    }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(textColor.opacity(0.65)).help("隐藏面板（可从菜单栏图标重新打开）")
            }
            if model.windows.isEmpty {
                Text(model.status).font(.system(size: 11)).foregroundStyle(textColor.opacity(0.72)).lineLimit(2)
            } else {
                ForEach(model.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.label).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(window.remaining.rounded()))% 剩余").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(textColor)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(textColor.opacity(0.16))
                                Capsule().fill(accent).frame(width: geo.size.width * window.remaining / 100)
                            }
                        }.frame(height: 4)
                        if let reset = window.resetAt {
                            Text("重置于 \(reset, style: .relative)").font(.system(size: 10)).foregroundStyle(textColor.opacity(0.68))
                        }
                    }
                }
                Text("\(model.updatedAt.map { "更新于 \($0.formatted(date: .omitted, time: .shortened))" } ?? model.status) · 手动刷新").font(.system(size: 9)).foregroundStyle(textColor.opacity(0.58))
            }
            Text(model.systemMemoryLabel)
                .font(.system(size: 9, design: .rounded)).foregroundStyle(textColor.opacity(0.65))
        }
        .foregroundStyle(textColor)
        .padding(14).frame(width: 250)
        .background {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: savedCornerRadius, style: .continuous).fill(.ultraThinMaterial)
                    if let skinImage {
                        Image(nsImage: skinImage).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        savedBackground.opacity(savedBackgroundOpacity)
                    } else {
                        savedBackground.opacity(savedBackgroundOpacity)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: savedCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: savedCornerRadius, style: .continuous).stroke(textColor.opacity(0.16), lineWidth: 1))
        .onAppear {
            loadSkinImage()
            if savedBackgroundOpacity < 0.28 { savedBackgroundOpacity = 0.48 }
        }
    }

    private func importSkin() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let source = picker.url else { return }
        do {
            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CodexQuota/Skins", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: destination)
            skinImagePath = destination.path
            skinImage = NSImage(contentsOf: destination)
        } catch {
            model.status = "导入图片失败：\(error.localizedDescription)"
        }
    }

    private func loadSkinImage() {
        skinImage = skinImagePath.isEmpty ? nil : NSImage(contentsOfFile: skinImagePath)
    }

    private func cleanHex(_ value: String) -> String {
        String(value.uppercased().filter(\.isHexDigit).prefix(6))
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x17212B
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        return String(format: "%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private let model = QuotaModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSApp.applicationIconImage
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = false
            button.toolTip = "CodexQuota · 打开额度面板"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示额度面板", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 CodexQuota", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.identifier = NSUserInterfaceItemIdentifier("CodexQuotaPanel")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: QuotaView(model: model, onClose: { [weak self] in self?.panel.orderOut(nil) }))
        positionPanel()
        panel.orderFrontRegardless()
        model.start()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18))
    }

    @objc private func showPanel() {
        panel.orderFrontRegardless()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct CodexQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}
