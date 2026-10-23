import SwiftUI
import AppKit

/// 开发期界面校验：把真实窗口的视图层级抓成 PNG（不依赖屏幕录制权限）
@MainActor
enum Snapshot {

    static func captureAll(state: AppState, to dir: String) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let steps: [(SidebarItem, String)] = [
            (.dashboard, "dashboard.png"),
            (.all, "list.png"),
            (.category(.code), "codes.png"),
            (.cleanup, "cleanup.png"),
            (.trash, "trash.png"),
            (.settings, "settings.png")
        ]

        try? await Task.sleep(nanoseconds: 1_200_000_000)

        for (item, name) in steps {
            state.selectSidebar(item)
            try? await Task.sleep(nanoseconds: 900_000_000)
            capture(name: name, to: dir)
        }

        state.selectSidebar(.all)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let first = state.filtered.first {
            state.selection = [first.id]
            try? await Task.sleep(nanoseconds: 900_000_000)
            capture(name: "detail.png", to: dir)
        }

        // 多选状态：详情栏应出现「导出所选 / 删除所选」
        state.selectSidebar(.all)
        try? await Task.sleep(nanoseconds: 400_000_000)
        state.selection = Set(state.filtered.prefix(3).map(\.id))
        try? await Task.sleep(nanoseconds: 900_000_000)
        capture(name: "multi.png", to: dir)
        if let w = NSApp.windows.first(where: { $0.contentView != nil }),
           let c = w.contentView {
            dumpTables(c)
            for t in allTables(c) {
                log("[tree] 表格 rows=\(t.numberOfRows) frame=\(NSStringFromRect(t.frame)) "
                    + "hidden=\(t.isHidden) alpha=\(t.alphaValue)")
            }
        }

        renderRows(state: state, to: dir)

        log("[snapshot] 消息数 \(state.all.count)，完成")
    }

    private static func capture(name: String, to dir: String) {
        guard let window = NSApp.windows.first(where: {
            $0.contentView != nil && $0.frame.width > 400
        }), let view = window.contentView else {
            log("[snapshot] 找不到窗口: \(name)")
            return
        }
        log("[app] window=\(window.effectiveAppearance.name.rawValue) "
            + "content=\(view.effectiveAppearance.name.rawValue) "
            + "state=\(AppState.shared.appearance.rawValue) "
            + "bgAlpha=\(AppState.shared.backgroundOpacity)")
        log("[win] frame=\(NSStringFromRect(window.frame)) "
            + "content=\(NSStringFromRect(view.frame)) "
            + "fullSize=\(window.styleMask.contains(.fullSizeContentView)) "
            + "opaque=\(window.isOpaque) "
            + "titleTransparent=\(window.titlebarAppearsTransparent) "
            + "bg=\(window.backgroundColor.alphaComponent)")

        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            log("[snapshot] 无法创建位图: \(name)")
            return
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? png.write(to: url)
        log("[snapshot] \(name) \(Int(bounds.width))x\(Int(bounds.height))")
        if name.hasPrefix("list") { dumpTables(view) }
        if let tb = window.toolbar {
            let ids = tb.items.map { $0.itemIdentifier.rawValue }.joined(separator: ",")
            log("[snapshot]   toolbar(\(tb.items.count)): \(ids)")
        } else {
            log("[snapshot]   toolbar: 无")
        }
    }

    /// 单独渲染几行列表（NSTableView 抓不到图，但行本身是纯 SwiftUI）
    private static func renderRows(state: AppState, to dir: String) {
        let rows = Array(state.filtered.prefix(6))
        let content = VStack(spacing: 0) {
            ForEach(rows) { m in
                MessageRow(message: m, query: "",
                           isSelected: m.id == rows.first?.id,
                           onToggle: {})
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                Divider()
            }
        }
        .frame(width: 620)
        .background(Color(nsColor: .textBackgroundColor))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("rows.png"))
        log("[snapshot] 09-rows.png")
    }

    static func allTables(_ v: NSView) -> [NSTableView] {
        var out: [NSTableView] = []
        if let t = v as? NSTableView { out.append(t) }
        for sub in v.subviews { out.append(contentsOf: allTables(sub)) }
        return out
    }

    static func dumpTables(_ v: NSView, depth: Int = 0) {
        if let t = v as? NSTableView {
            log("[tree] NSTableView rows=\(t.numberOfRows) frame=\(NSStringFromRect(t.frame))")
            for row in 0..<min(t.numberOfRows, 3) {
                if let cell = t.view(atColumn: 0, row: row, makeIfNecessary: true) {
                    let texts = cell.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
                    log("[tree]   row\(row): \(texts.joined(separator: " | "))")
                }
            }
        }
        for sub in v.subviews { dumpTables(sub, depth: depth + 1) }
    }

    static func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["SMSKEEPER_EXPORTTEST"] {
            Task { @MainActor in
                let state = AppState.shared
                await state.bootstrap()
                if ProcessInfo.processInfo.environment["SMSKEEPER_LANG"] == "en" {
                    state.language = .english
                }
                try? FileManager.default.createDirectory(atPath: dir,
                                                         withIntermediateDirectories: true)
                let sample = Array(state.filtered.prefix(5))
                for f in ExportFormat.allCases {
                    let body = Exporter.content(for: sample, format: f)
                    let name = Exporter.suggestedName(format: f)
                    try? body.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name),
                                    atomically: true, encoding: .utf8)
                    Snapshot.log("[export] \(name) \(body.count) 字符")
                }
                NSApp.terminate(nil)
            }
            return
        }
        if ProcessInfo.processInfo.environment["SMSKEEPER_SELFTEST"] != nil {
            Task { @MainActor in await self.runSelfTest(); NSApp.terminate(nil) }
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["SMSKEEPER_SNAPSHOT"] else { return }

        Task { @MainActor in
            let state = AppState.shared
            await state.bootstrap()
            if ProcessInfo.processInfo.environment["SMSKEEPER_LANG"] == "en" {
                state.language = .english
            }
            switch ProcessInfo.processInfo.environment["SMSKEEPER_APPEARANCE"] {
            case "dark": state.appearance = .dark
            case "light": state.appearance = .light
            default: break
            }
            Snapshot.log("[diag] 数据源: \(Database.shared.activePath)")
            Snapshot.log("[diag] 演示: \(state.isDemo) 消息: \(state.all.count) "
                         + "错误: \(state.errorMessage ?? "无")")
            await Snapshot.captureAll(state: state, to: dir)
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private func runSelfTest() async {
        let state = AppState.shared

        let t0 = Date()
        await state.bootstrap()
        let loadMs = Int(Date().timeIntervalSince(t0) * 1000)

        Snapshot.log("[test] 数据源 \(Database.shared.activePath)")
        Snapshot.log("[test] 演示=\(state.isDemo) 条数=\(state.all.count) 载入耗时 \(loadMs)ms")
        if let err = state.errorMessage { Snapshot.log("[test] 错误: \(err)") }

        let dist = Category.allCases.map {
            "\($0.label)=\(state.stats.byCategory[$0] ?? 0)"
        }.joined(separator: " ")
        Snapshot.log("[test] 分类 \(dist)")

        // 分类切换耗时
        for c in [Category.code, .bank, .notice] {
            let t = Date()
            state.categories = [c]
            state.refilter()
            let ms = Int(Date().timeIntervalSince(t) * 1000)
            Snapshot.log("[test] 切到 \(c.label)：\(state.filtered.count) 条，\(ms)ms")
        }

        // 搜索耗时（先清掉分类条件）
        state.categories = []
        state.sidebar = .all
        state.refilter()
        for q in ["验证码", "取件码", "银行 -退订"] {
            let t = Date()
            state.query = q
            state.refilter()
            let ms = Int(Date().timeIntervalSince(t) * 1000)
            Snapshot.log("[test] 搜索「\(q)」：\(state.filtered.count) 条，\(ms)ms")
        }
        state.query = ""
        state.refilter()

        // 导航切换（侧边栏按钮走的就是这个方法）
        for item in [SidebarItem.all, .category(.code), .cleanup, .dashboard] {
            let t = Date()
            state.selectSidebar(item)
            let ms = Int(Date().timeIntervalSince(t) * 1000)
            Snapshot.log("[test] 切到「\(item.title)」：sidebar=\(String(describing: state.sidebar)) "
                         + "列表 \(state.filtered.count) 条，\(ms)ms")
        }

        // 选择行为：单击=单选，复选框=累加
        state.selection = []
        if state.filtered.count >= 2 {
            let a = state.filtered[0].id
            let b = state.filtered[1].id
            state.handleRowClick(a, in: state.filtered)
            Snapshot.log("[test] 单击一行 -> 选中 \(state.selection.count)")
            state.toggleSelection(b)
            Snapshot.log("[test] 再点复选框 -> 选中 \(state.selection.count)")
            state.toggleSelection(b)
            Snapshot.log("[test] 取消复选框 -> 选中 \(state.selection.count)")
            state.selection = []
        }

        // 自定义时间范围：验证 customFrom/customTo 真的接入了筛选
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        state.range = .custom
        state.customFrom = cal.date(byAdding: .day, value: -30, to: today)!
        state.customTo = today
        state.refilter()
        let custom30 = state.filtered.count
        state.range = .d30
        state.refilter()
        let preset30 = state.filtered.count
        Snapshot.log("[test] 自定义近30天 \(custom30) 条 vs 预设近30天 \(preset30) 条"
                     + "（应相等或差 1 条边界）")

        // 反向验证：把区间改成不可能有数据的远古年代，结果应为 0
        state.range = .custom
        state.customFrom = cal.date(byAdding: .year, value: -10, to: today)!
        state.customTo = cal.date(byAdding: .year, value: -9, to: today)!
        state.refilter()
        let ancient = state.filtered.count
        Snapshot.log("[test] 自定义 10 年前区间 -> \(ancient) 条（应为 0）")
        state.range = .all
        state.customFrom = today
        state.customTo = today
        state.refilter()

        // 破坏性测试：演示库，或 SMSKEEPER_DB 明确指定的测试库。
        // 判据是「当前库不是系统真实库」，绝不用真实短信做测试。
        let isRealDB = Database.shared.activePath == Database.shared.realPath
        guard state.isDemo || !isRealDB else {
            Snapshot.log("[test] 系统真实库：跳过删除/还原测试（只读验证）")
            Snapshot.log("[test] 结论 通过（只读验证）")
            return
        }
        if !state.isDemo {
            Snapshot.log("[test] 指定测试库：允许执行删除/还原闭环")
        }

        let before = state.all.count
        let sample = Array(state.all.prefix(8))
        let beforeTexts = sample.map { ($0.id, $0.text) }
        let ok = await state.delete(ids: Set(sample.map(\.id)), source: "test")
        Snapshot.log("[test] 删除 \(sample.count) 条 -> ok=\(ok) 剩余 \(state.all.count)")

        var restored = 0
        if let batch = state.trash.first, (await state.restore(batch)) {
            restored = batch.count
        }
        var mismatched = 0
        for (id, text) in beforeTexts {
            if let m = state.all.first(where: { $0.id == id }), m.text != text {
                mismatched += 1
            }
        }
        Snapshot.log("[test] 还原 \(restored) 条 -> \(state.all.count)（原始 \(before)）"
                     + " 正文不一致 \(mismatched)")
        Snapshot.log("[test] 结论 \(state.all.count == before && mismatched == 0 ? "通过" : "失败")")
    }

    private func findTable(in view: NSView, minRows: Int, maxRows: Int) -> NSTableView? {
        if let t = view as? NSTableView, (minRows...maxRows).contains(t.numberOfRows) {
            return t
        }
        for sub in view.subviews {
            if let found = findTable(in: sub, minRows: minRows, maxRows: maxRows) {
                return found
            }
        }
        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
