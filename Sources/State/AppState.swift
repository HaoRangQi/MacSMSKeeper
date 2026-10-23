import Foundation
import SwiftUI
import AppKit
import SQLite3
import UniformTypeIdentifiers

// MARK: - 统计

struct Stats {
    var total = 0
    var unread = 0
    var withCode = 0
    var byCategory: [Category: Int] = [:]
    var topSenders: [(sender: String, count: Int)] = []
    var daily: [(day: Date, count: Int)] = []
    var hours: [Int] = Array(repeating: 0, count: 24)
    var firstDate: Date? = nil
    var lastDate: Date? = nil
}

// MARK: - 载入状态（单独观察，避免进度刷新引起整页重绘）

final class LoadStatus: ObservableObject {
    @Published var isLoading = false
    @Published var phase = ""
    @Published var progress: Double = 0

    func begin(_ phase: String) {
        isLoading = true
        self.phase = phase
        progress = 0
    }

    func update(_ phase: String, _ p: Double) {
        self.phase = phase
        progress = p
    }

    func finish() {
        isLoading = false
        phase = ""
        progress = 0
    }
}

// MARK: - 应用状态

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var all: [SMSMessage] = []
    @Published var filtered: [SMSMessage] = []
    @Published var selection = Set<Int64>()

    @Published var sidebar: SidebarItem? = .dashboard
    @Published var visibility: NavigationSplitViewVisibility = .doubleColumn
    @Published var query = ""
    @Published var categories: Set<Category> = []
    @Published var range: TimeRange = .all
    @Published var customFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @Published var customTo = Date()
    @Published var unreadOnly = false
    @Published var withAttachment = false
    @Published var sort: SortMode = .newest

    @Published var isDemo = false
    @Published var listLimit = 200

    let loadStatus = LoadStatus()
    @Published var permissionOK = false
    @Published var permissionDetail = ""
    @Published var realPermissionOK = false
    @Published var realPermissionDetail = ""
    @Published var errorMessage: String?
    @Published var toast: String?

    @Published var trash: [TrashBatch] = []
    @Published var backups: [BackupFile] = []
    @Published var stats = Stats()

    let service = DeleteService.shared

    // MARK: 启动

    func bootstrap() async {
        L.code = L.resolve(language)
        let access = Database.shared.checkAccess()
        permissionOK = access.0
        permissionDetail = access.1
        let real = Database.shared.checkRealAccess()
        realPermissionOK = real.0
        realPermissionDetail = real.1

        if !permissionOK {
            // 没权限时自动进入演示模式，保证界面可用
            _ = DemoData.buildIfNeeded()
            Database.shared.switchToDemo()
            isDemo = true
        } else {
            isDemo = Database.shared.isDemo
        }
        await load()
        refreshTrash()
        refreshBackups()
    }

    private func plog(_ msg: String) {
        guard ProcessInfo.processInfo.environment["SMSKEEPER_PROFILE"] != nil else { return }
        FileHandle.standardError.write(Data(("[profile] " + msg + "\n").utf8))
    }

    func load() async {
        loadStatus.begin(L.t("正在读取数据库…"))
        errorMessage = nil
        let tRead0 = Date()

        let raw: [SMSMessage]
        do {
            raw = try await Task.detached(priority: .userInitiated) {
                try Database.shared.loadMessages()
            }.value
        } catch {
            all = []
            errorMessage = error.localizedDescription
            loadStatus.finish()
            return
        }

        let readMs = Int(Date().timeIntervalSince(tRead0) * 1000)
        let tClass0 = Date()

        // 分批分类，每批让出主线程；进度按百分比变化才刷新，避免频繁重绘
        loadStatus.update(L.t("正在分析短信类型…"), 0)
        var processed: [SMSMessage] = []
        processed.reserveCapacity(raw.count)
        let total = max(raw.count, 1)
        var done = 0
        var lastPercent = -1

        for chunk in raw.chunked(500) {
            var part = chunk
            Classifier.apply(to: &part)
            for i in part.indices {
                part[i].searchText =
                    (part[i].text + " " + part[i].sender).lowercased()
            }
            processed.append(contentsOf: part)
            done += part.count
            let pct = Int(Double(done) / Double(total) * 100)
            if pct != lastPercent {
                lastPercent = pct
                loadStatus.update(L.t("正在分析短信类型…"), Double(pct) / 100)
            }
            await Task.yield()
        }

        let classMs = Int(Date().timeIntervalSince(tClass0) * 1000)
        let tStat0 = Date()
        loadStatus.update(L.t("正在整理索引…"), 1)
        all = processed
        isDemo = Database.shared.isDemo
        computeStats()
        refilter()
        let statMs = Int(Date().timeIntervalSince(tStat0) * 1000)
        plog("条数=\(raw.count) 读取=\(readMs)ms 分类=\(classMs)ms 统计+筛选=\(statMs)ms")
        loadStatus.finish()
    }

    // MARK: 数据源切换

    func connectReal() async {
        let access = Database.shared.checkRealAccess()
        realPermissionOK = access.0
        realPermissionDetail = access.1
        permissionOK = access.0
        permissionDetail = access.1
        guard access.0 else {
            errorMessage = access.1
            return
        }
        Database.shared.switchToReal()
        isDemo = false
        await load()
        refreshTrash()
        refreshBackups()
    }

    func useDemo() async {
        _ = DemoData.buildIfNeeded()
        Database.shared.switchToDemo()
        isDemo = true
        await load()
        refreshTrash()
    }

    // MARK: 过滤

    func refilter(resetLimit: Bool = true) {
        var opts = FilterOptions()
        opts.query = query
        opts.categories = effectiveCategories
        opts.range = range
        opts.customFrom = customFrom
        opts.customTo = customTo
        opts.unreadOnly = unreadOnly
        opts.withAttachment = withAttachment
        opts.sort = sort
        filtered = SearchEngine.apply(opts, to: all)
        if resetLimit { listLimit = 200 }
        let ids = Set(filtered.map(\.id))
        selection = selection.intersection(ids)
    }

    var effectiveCategories: Set<Category> {
        if case .category(let c) = sidebar { return [c] }
        return categories
    }

    func selectSidebar(_ item: SidebarItem) {
        sidebar = item
        sidebarChanged(item)
    }

    /// List 的 selection 直接绑定 sidebar 后，副作用统一在这里处理
    func sidebarChanged(_ item: SidebarItem?) {
        guard let item else { return }
        switch item {
        case .category(let c): categories = [c]
        case .all: categories = []
        default: break
        }
        refilter()
    }

    /// 行点击：⌘ 切换、⇧ 连选、否则单选
    func handleRowClick(_ id: Int64, in list: [SMSMessage]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            toggleSelection(id)
        } else if flags.contains(.shift),
                  let anchor = anchorID,
                  let from = list.firstIndex(where: { $0.id == anchor }),
                  let to = list.firstIndex(where: { $0.id == id }) {
            let lo = min(from, to), hi = max(from, to)
            selection.formUnion(list[lo...hi].map(\.id))
        } else {
            selection = [id]
            anchorID = id
        }
    }

    func toggleSelection(_ id: Int64) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        anchorID = id
    }

    func toggleCategory(_ c: Category) {
        if categories.contains(c) { categories.remove(c) } else { categories.insert(c) }
        sidebar = .all
        refilter()
    }

    func resetFilters() {
        query = ""
        categories = []
        range = .all
        unreadOnly = false
        withAttachment = false
        sidebar = .all
        refilter()
    }

    // MARK: 统计

    func computeStats() {
        var s = Stats()
        s.total = all.count
        var senders: [String: Int] = [:]
        var days: [Int: Int] = [:]
        var dayIndex: [Int: Date] = [:]
        let cal = Calendar.current

        for m in all {
            s.byCategory[m.category, default: 0] += 1
            if m.isUnread { s.unread += 1 }
            if m.code != nil { s.withCode += 1 }
            if !m.sender.isEmpty { senders[m.sender, default: 0] += 1 }
            let d = cal.startOfDay(for: m.date)
            let key = Int(d.timeIntervalSince1970)   // 避免逐条调用 DateFormatter
            days[key, default: 0] += 1
            dayIndex[key] = d
            s.hours[cal.component(.hour, from: m.date)] += 1
            if s.firstDate == nil || m.date < s.firstDate! { s.firstDate = m.date }
            if s.lastDate == nil || m.date > s.lastDate! { s.lastDate = m.date }
        }

        s.topSenders = senders.sorted { $0.value > $1.value }.prefix(10)
            .map { (sender: $0.key, count: $0.value) }
        s.daily = days.keys.sorted().compactMap { key in
            guard let d = dayIndex[key] else { return nil }
            return (day: d, count: days[key] ?? 0)
        }
        stats = s
    }

    // MARK: 删除

    @Published var lastDeleteInfo: String?
    @Published var pendingDeleteIDs: Set<Int64>? = nil
    @Published var lastExportFormat: ExportFormat = .csv
    @Published var anchorID: Int64? = nil

    /// 外观：主题 + 背景不透明度
    @Published var appearance: AppearanceMode = .system {
        didSet { applyAppearance() }
    }
    @Published var backgroundOpacity: Double = 0.88
    @Published var language: AppLanguage = .system {
        didSet {
            L.code = L.resolve(language)
            // 权限说明是运行时生成的文案，切语言后需要重新取一次
            let real = Database.shared.checkRealAccess()
            realPermissionOK = real.0
            realPermissionDetail = real.1
        }
    }

    /// 由菜单 / 快捷键触发，交给界面弹确认框
    func requestDelete(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
    }

    func delete(ids: Set<Int64>, source: String = "manual",
                ruleName: String? = nil) async -> Bool {
        let targets = all.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return false }
        do {
            let res = try service.delete(messages: targets, source: source, ruleName: ruleName)
            let removed = Set(targets.map(\.id))
            all.removeAll { removed.contains($0.id) }
            selection.subtract(removed)
            computeStats()
            refilter()
            refreshTrash()
            refreshBackups()
            lastDeleteInfo = L.t("已删除 %d 条，备份 %@", res.deleted, res.backupName)
            toast = lastDeleteInfo
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore(_ batch: TrashBatch) async -> Bool {
        do {
            let n = try service.restore(batch)
            await load()
            refreshTrash()
            refreshBackups()
            toast = L.t("已还原 %d 条短信", n)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func purge(_ batch: TrashBatch) {
        service.purge(batch)
        refreshTrash()
    }

    func refreshTrash() { trash = service.listTrash() }
    func refreshBackups() { backups = service.listBackups() }

    // MARK: 规则

    func preview(rule: CleanupRule, days: Int, keep: Set<Category>) -> [SMSMessage] {
        service.match(rule: rule, days: days, keep: keep, in: all)
    }

    func applyRule(_ rule: CleanupRule, days: Int, keep: Set<Category>) async -> Bool {
        let targets = preview(rule: rule, days: days, keep: keep)
        guard !targets.isEmpty else { return false }
        return await delete(ids: Set(targets.map(\.id)), source: "rule", ruleName: rule.title)
    }

    // MARK: 其它

    func markRead(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        guard let db = try? Database.shared.writeConnection() else { return }
        defer { db.close() }
        for chunk in Array(ids).chunked(400) {
            let ph = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            guard let stmt = try? db.prepare("UPDATE message SET is_read=1 WHERE ROWID IN (\(ph))")
            else { continue }
            for (i, v) in chunk.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), v) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        for i in all.indices where ids.contains(all[i].id) { all[i].isRead = true }
        refilter()
        computeStats()
    }

    /// 只设 NSApp.appearance 对已存在的窗口无效，必须逐个窗口设
    func applyAppearance() {
        let target = appearance.nsAppearance
        NSApp.appearance = target
        for window in NSApp.windows {
            window.appearance = target
        }
    }

    func openFullDiskAccessSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// 有选中就导出所选，否则导出当前筛选结果
    var exportTargets: [SMSMessage] {
        selection.isEmpty
            ? filtered
            : filtered.filter { selection.contains($0.id) }
    }

    @discardableResult
    func export(_ messages: [SMSMessage], format: ExportFormat? = nil) -> URL? {
        guard !messages.isEmpty else {
            toast = L.t("没有可导出的短信")
            return nil
        }
        let fmt = format ?? lastExportFormat
        lastExportFormat = fmt

        let panel = NSSavePanel()
        panel.title = L.t("导出短信")
        panel.prompt = L.t("导出")
        panel.nameFieldStringValue = Exporter.suggestedName(format: fmt)
        panel.allowedContentTypes = [fmt.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let body = Exporter.content(for: messages, format: fmt, generatedAt: Date())
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            toast = L.t("已导出 %d 条到 %@", messages.count, url.lastPathComponent)
            return url
        } catch {
            errorMessage = L.t("导出失败：%@", error.localizedDescription)
            return nil
        }
    }

}
