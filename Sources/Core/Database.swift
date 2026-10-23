import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - 轻量 SQLite 封装

final class SQLiteDB {
    private(set) var handle: OpaquePointer?
    let path: String

    init(path: String, readOnly: Bool) throws {
        self.path = path
        var h: OpaquePointer?
        let flags = readOnly
            ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX)
        let rc = sqlite3_open_v2(path, &h, flags, nil)
        guard rc == SQLITE_OK, h != nil else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close(h)
            throw DBError.open(msg)
        }
        handle = h
        sqlite3_busy_timeout(h, 3000)
    }

    deinit { if handle != nil { sqlite3_close(handle) } }

    func close() {
        if handle != nil { sqlite3_close(handle); handle = nil }
    }

    func exec(_ sql: String) throws {
        guard let h = handle else { throw DBError.open("连接已关闭") }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(h, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "SQL 执行失败"
            sqlite3_free(err)
            throw DBError.sql(msg)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let h = handle else { throw DBError.open("连接已关闭") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK, stmt != nil else {
            throw DBError.sql(String(cString: sqlite3_errmsg(h)))
        }
        return stmt!
    }


    // MARK: macOS 私有 SQL 函数的兼容

    /// 「信息」App 打开 chat.db 时会用 sqlite3_create_function 注册一批私有函数，
    /// 库里的触发器在增删消息时调用它们。我们的连接没有这些函数，
    /// DELETE / INSERT 就会失败，例如：
    ///     no such function: after_delete_message_plugin
    ///     no such function: before_delete_attachment_path
    ///
    /// 命名规律没有统一格式（*_plugin、before_delete_* 都见过），所以不靠猜：
    /// 扫描全部触发器，把其中调用的函数名逐个探测，SQLite 里不存在的才注册空实现。
    /// 已存在的（内置函数）绝不动，避免覆盖真实行为。
    ///
    /// 这些私有函数在「信息」App 内部大概是维护索引/缓存，
    /// 而我们要求「信息」App 退出后才写库，跳过它们无副作用。

    /// 已知的私有函数名。扫描是主路径，这里只是兜底
    /// （万一触发器不在 sqlite_master 里，或命名被混淆）。
    private static let knownPrivateFuncs = [
        "after_delete_message_plugin",
        "after_insert_message_plugin",
        "after_update_message_plugin",
        "before_delete_message_plugin",
        "before_insert_message_plugin",
        "before_update_message_plugin",
        "before_delete_attachment_path",
        "after_delete_attachment_path",
        "before_insert_attachment_path",
        "after_insert_attachment_path",
    ]

    /// SQLite 内置函数。命中就跳过，不做探测也不注册。
    /// 探测本身已经能识别内置函数，这份清单只是省掉无用的 prepare。
    private static let builtinFuncs: Set<String> = [
        // 核心
        "abs","changes","char","coalesce","concat","concat_ws","format","glob",
        "hex","ifnull","iif","instr","last_insert_rowid","length","like",
        "likelihood","likely","load_extension","lower","ltrim","max","min",
        "nullif","octet_length","printf","quote","random","randomblob","replace",
        "round","rtrim","sign","soundex","sqlite_compileoption_get",
        "sqlite_compileoption_used","sqlite_offset","sqlite_source_id",
        "sqlite_version","substr","substring","total_changes","trim","typeof",
        "unhex","unicode","unlikely","upper","zeroblob",
        // 数学（需 SQLITE_ENABLE_MATH_FUNCTIONS）
        "acos","acosh","asin","asinh","atan","atan2","atanh","ceil","ceiling",
        "cos","cosh","degrees","exp","floor","ln","log","log10","log2","mod",
        "pi","pow","power","radians","sin","sinh","sqrt","tan","tanh","trunc",
        // 日期时间
        "date","time","datetime","julianday","unixepoch","strftime","timediff",
        // 聚合与窗口
        "avg","count","group_concat","sum","total","string_agg",
        "row_number","rank","dense_rank","percent_rank","cume_dist","ntile",
        "lag","lead","first_value","last_value","nth_value",
        // JSON
        "json","json_array","json_array_length","json_each","json_extract",
        "json_group_array","json_group_object","json_insert","json_object",
        "json_patch","json_quote","json_remove","json_replace","json_set",
        "json_tree","json_type","json_valid","json_error_position",
        // SQL 语法里会跟着括号的关键字，避免误当函数
        "values","cast","exists","in","not","and","or","case","when","then",
        "raise","collate","filter","over","partition","current_date",
        "current_time","current_timestamp",
    ]

    /// 从 SQL 里提取所有「标识符(」形式的函数调用名
    private static func calledFuncs(in sql: String) -> [String] {
        var out: [String] = []
        var rest = sql
        let pattern = #"([A-Za-z_][A-Za-z0-9_]*)\s*\("#
        while let r = rest.range(of: pattern, options: .regularExpression) {
            let name = String(rest[r])
                .replacingOccurrences(of: "(", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !builtinFuncs.contains(name.lowercased()), !out.contains(name) {
                out.append(name)
            }
            rest = String(rest[r.upperBound...])
        }
        return out
    }

    /// 探测某个函数名在当前连接上是否已存在。
    /// 做法是尝试 prepare 一条 `SELECT name()`：
    ///   - prepare 成功            → 存在
    ///   - 报错但不是 no such function（如参数个数不匹配）→ 也存在
    ///   - 报 no such function      → 不存在，需要注册
    private func funcExists(_ name: String) -> Bool {
        guard let h = handle else { return true }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(h, "SELECT \(name)()", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        if rc == SQLITE_OK { return true }
        let msg = String(cString: sqlite3_errmsg(h))
        return !msg.contains("no such function")
    }

    /// 给连接注册所有私有函数的空实现，返回实际注册的名字（供日志记录）
    @discardableResult
    func registerPluginShims() -> [String] {
        guard let h = handle else { return [] }

        var candidates = Set<String>(Self.knownPrivateFuncs)

        // 扫描全部触发器，收集其中调用的函数名
        if let stmt = try? prepare("SELECT sql FROM sqlite_master WHERE type='trigger'") {
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let sql = String(cString: c)
                    candidates.formUnion(Self.calledFuncs(in: sql))
                }
            }
        }

        var registered: [String] = []
        for name in candidates.sorted() {
            // 只补 SQLite 里没有的，绝不覆盖内置函数
            if funcExists(name) { continue }
            // nArg = -1 表示任意参数个数
            let rc = sqlite3_create_function(h, name, -1, SQLITE_UTF8, nil,
                                             noopSQLFunc, nil, nil)
            if rc == SQLITE_OK { registered.append(name) }
        }
        return registered
    }
    /// 执行一条返回单行单列的整数 SQL
    func scalarInt(_ sql: String) -> Int? {
        guard let stmt = try? prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// SQLite 的原始错误文本（比「删除消息失败」有用得多）
    func lastError() -> String {
        guard let h = handle else { return "连接已关闭" }
        return String(cString: sqlite3_errmsg(h))
    }
    func columns(of table: String) -> Set<String> {
        var out = Set<String>()
        guard let stmt = try? prepare("PRAGMA table_info(\(table))") else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) {
                out.insert(String(cString: c))
            }
        }
        return out
    }

    func hasTable(_ name: String) -> Bool {
        guard let stmt = try? prepare(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?") else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}

enum DBError: LocalizedError {
    case open(String)
    case sql(String)
    case permission

    var errorDescription: String? {
        switch self {
        case .open(let m): return "无法打开数据库：\(m)"
        case .sql(let m): return "数据库错误：\(m)"
        case .permission: return "没有读取「信息」数据库的权限"
        }
    }
}

// MARK: - 数据访问

final class Database {
    static let shared = Database()

    let realPath = NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath
    private(set) var activePath: String
    private(set) var isDemo = false

    /// 测试用：通过环境变量指定数据库路径
    private static let overridePath = ProcessInfo.processInfo.environment["SMSKEEPER_DB"]

    private init() {
        if let o = Database.overridePath, !o.isEmpty {
            activePath = o
            isDemo = true
        } else {
            activePath = realPath
        }
    }

    // MARK: 权限

    /// 返回 (是否可读, 说明)
    func checkAccess() -> (Bool, String) {
        if isDemo { return (true, "演示数据") }
        let dir = (realPath as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: realPath) else {
            return (false, L.t("找不到 ~/Library/Messages/chat.db，请确认这台 Mac 已启用「信息」"))
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: dir)
        } catch {
            return (false, L.t("系统拒绝访问 ~/Library/Messages，需要「完全磁盘访问权限」"))
        }
        do {
            let db = try SQLiteDB(path: realPath, readOnly: true)
            defer { db.close() }
            _ = try db.prepare("SELECT 1 FROM message LIMIT 1")
            return (true, L.t("权限正常"))
        } catch {
            return (false, L.t("读取失败：%@", error.localizedDescription))
        }
    }

    /// 只检查系统真实库的权限（不受演示模式影响）
    func checkRealAccess() -> (Bool, String) {
        let dir = (realPath as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: realPath) else {
            return (false, L.t("找不到 ~/Library/Messages/chat.db"))
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: dir)
        } catch {
            return (false, L.t("系统拒绝访问 ~/Library/Messages，需要「完全磁盘访问权限」"))
        }
        do {
            let db = try SQLiteDB(path: realPath, readOnly: true)
            defer { db.close() }
            _ = try db.prepare("SELECT 1 FROM message LIMIT 1")
            return (true, L.t("权限正常"))
        } catch {
            return (false, L.t("读取失败：%@", error.localizedDescription))
        }
    }

    // MARK: 读取

    func loadMessages() throws -> [SMSMessage] {
        let source = try resolveReadablePath()
        let db = try SQLiteDB(path: source, readOnly: true)
        defer { db.close() }

        let cols = db.columns(of: "message")
        let hasBody = cols.contains("attributedBody")
        let hasAtt = cols.contains("cache_has_attachments")

        func buildSQL(attExpr: String, joinHandle: Bool) -> String {
            let handleJoin = joinHandle
                ? "LEFT JOIN handle h ON h.ROWID = m.handle_id" : ""
            let handleCol = joinHandle ? "h.id" : "NULL"
            let whereClause = cols.contains("item_type")
                ? "WHERE (m.item_type IS NULL OR m.item_type = 0)" : ""
            return """
            SELECT m.ROWID, m.guid, m.text,
                   \(hasBody ? "m.attributedBody" : "NULL"),
                   m.date, m.is_from_me, m.is_read, m.service,
                   \(hasAtt ? "m.cache_has_attachments" : "0"),
                   \(handleCol),
                   \(attExpr)
            FROM message m
            \(handleJoin)
            \(whereClause)
            """
        }

        // 不同 macOS 版本的表结构有差异，按兼容性依次降级尝试
        let hasJoinTable = db.hasTable("message_attachment_join")
        var candidates: [String] = []
        if hasJoinTable {
            candidates.append(buildSQL(
                attExpr: "(SELECT COUNT(1) FROM message_attachment_join x WHERE x.message_id = m.ROWID)",
                joinHandle: true))
        }
        candidates.append(buildSQL(attExpr: "0", joinHandle: true))
        candidates.append(buildSQL(attExpr: "0", joinHandle: false))

        var stmt: OpaquePointer? = nil
        var lastError = ""
        for sql in candidates {
            if let s = try? db.prepare(sql) { stmt = s; break }
            lastError = "查询失败"
        }
        guard let stmt = stmt else { throw DBError.sql(lastError) }
        defer { sqlite3_finalize(stmt) }

        var out: [SMSMessage] = []
        out.reserveCapacity(4096)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rid = sqlite3_column_int64(stmt, 0)
            let guid = textAt(stmt, 1) ?? ""
            var body = textAt(stmt, 2) ?? ""
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let blob = blobAt(stmt, 3) {
                    body = AttributedBody.extract(blob)
                }
            }
            let rawDate = sqlite3_column_int64(stmt, 4)
            let date = AppleTime.toDate(rawDate)
            let fromMe = sqlite3_column_int(stmt, 5) != 0
            let read = sqlite3_column_int(stmt, 6) != 0
            let service = textAt(stmt, 7) ?? "SMS"
            let att = max(Int(sqlite3_column_int(stmt, 8)), Int(sqlite3_column_int(stmt, 10)))
            let sender = textAt(stmt, 9) ?? ""

            out.append(SMSMessage(
                id: rid, guid: guid, text: body, date: date,
                isFromMe: fromMe, isRead: read, service: service,
                sender: sender, chatIDs: [], attachments: att
            ))
        }
        return out
    }

    /// 直连失败时（例如 WAL 只读受限），复制一份到临时目录再读
    private func resolveReadablePath() throws -> String {
        if isDemo { return activePath }
        do {
            let db = try SQLiteDB(path: activePath, readOnly: true)
            db.close()
            return activePath
        } catch {
            let tmp = NSTemporaryDirectory() + "smskeeper-read-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let src = activePath + suffix
                if FileManager.default.fileExists(atPath: src) {
                    try FileManager.default.copyItem(atPath: src, toPath: tmp + "/chat.db" + suffix)
                }
            }
            return tmp + "/chat.db"
        }
    }

    // MARK: 写入（删除 / 恢复）

    func writeConnection() throws -> SQLiteDB {
        let db = try SQLiteDB(path: activePath, readOnly: false)
        let shims = db.registerPluginShims()
        Log.event("db.write_connection", "path", (activePath as NSString).lastPathComponent,
                  "shims", shims.joined(separator: ","))
        return db
    }

    func chatIDs(for ids: [Int64]) -> [Int64: [Int64]] {
        var out: [Int64: [Int64]] = [:]
        guard let db = try? SQLiteDB(path: activePath, readOnly: true) else { return out }
        defer { db.close() }
        guard db.hasTable("chat_message_join") else { return out }
        let stmt = try? db.prepare("SELECT message_id, chat_id FROM chat_message_join")
        guard let s = stmt else { return out }
        defer { sqlite3_finalize(s) }
        while sqlite3_step(s) == SQLITE_ROW {
            let mid = sqlite3_column_int64(s, 0)
            let cid = sqlite3_column_int64(s, 1)
            out[mid, default: []].append(cid)
        }
        return out
    }

    /// 取指定消息的 attributedBody（正文只存在于二进制里的情况，还原时必须带上）
    func attributedBodies(for ids: [Int64]) -> [Int64: Data] {
        var out: [Int64: Data] = [:]
        guard !ids.isEmpty,
              let db = try? SQLiteDB(path: activePath, readOnly: true) else { return out }
        defer { db.close() }
        guard db.columns(of: "message").contains("attributedBody") else { return out }
        for chunk in ids.chunked(400) {
            let ph = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            guard let stmt = try? db.prepare(
                "SELECT ROWID, attributedBody FROM message WHERE ROWID IN (\(ph))") else { continue }
            defer { sqlite3_finalize(stmt) }
            for (i, v) in chunk.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), v) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rid = sqlite3_column_int64(stmt, 0)
                if let blob = blobAt(stmt, 1) { out[rid] = blob }
            }
        }
        return out
    }

    func totalCount() -> Int {
        guard let db = try? SQLiteDB(path: activePath, readOnly: true) else { return 0 }
        defer { db.close() }
        guard let s = try? db.prepare("SELECT COUNT(1) FROM message") else { return 0 }
        defer { sqlite3_finalize(s) }
        return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int64(s, 0)) : 0
    }

    func sizeMB() -> Double {
        let attrs = try? FileManager.default.attributesOfItem(atPath: activePath)
        let bytes = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
        return (bytes / 1_048_576 * 10).rounded() / 10
    }

    func switchToDemo() {
        isDemo = true
        activePath = Database.overridePath?.isEmpty == false
            ? Database.overridePath! : DemoData.demoPath
    }
    func switchToReal() { isDemo = false; activePath = realPath }
}

// MARK: - 列值读取

func textAt(_ stmt: OpaquePointer, _ idx: Int32) -> String? {
    guard let c = sqlite3_column_text(stmt, idx) else { return nil }
    return String(cString: c)
}

func blobAt(_ stmt: OpaquePointer, _ idx: Int32) -> Data? {
    guard let bytes = sqlite3_column_blob(stmt, idx) else { return nil }
    let len = Int(sqlite3_column_bytes(stmt, idx))
    guard len > 0 else { return nil }
    return Data(bytes: bytes, count: len)
}

// MARK: - Apple 时间戳

enum AppleTime {
    static let epoch: TimeInterval = 978307200  // 2001-01-01 UTC

    static func toDate(_ raw: Int64) -> Date {
        var v = Double(raw)
        if v > 1e16 { v /= 1e9 }        // 纳秒
        else if v > 1e13 { v /= 1e6 }   // 微秒
        else if v > 1e11 { v /= 1e3 }   // 毫秒
        return Date(timeIntervalSince1970: epoch + v)
    }

    static func fromDate(_ d: Date) -> Int64 {
        Int64((d.timeIntervalSince1970 - epoch) * 1e9)
    }
}

// MARK: - attributedBody 文本提取

enum AttributedBody {
    /// typedstream 二进制里抢救正文：定位 NSString 段，在结构尾 \x86\x84 处截断
    static func extract(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let markers: [[UInt8]] = [
            Array("NSMutableString".utf8),
            Array("NSString".utf8)
        ]

        for marker in markers {
            guard let pos = find(bytes, marker) else { continue }
            var i = pos + marker.count
            // 找 '+' 作为内容起点标记
            while i < bytes.count && bytes[i] != UInt8(ascii: "+") { i += 1 }
            guard i < bytes.count else { continue }
            i += 1
            // 跳过 1~2 个不可打印的长度前缀
            var skipped = 0
            while i < bytes.count && skipped < 4 && bytes[i] < 0x20 { i += 1; skipped += 1 }
            var end = bytes.count
            // 结构尾标记
            let tails: [[UInt8]] = [[0x86, 0x84], [0x86, 0x85]]
            for tail in tails {
                if let t = find(bytes, tail, from: i) { end = min(end, t) }
            }
            if let t = find(bytes, Array("NSObject".utf8), from: i) { end = min(end, t) }
            if end > i {
                let slice = Data(bytes[i..<end])
                var s = String(decoding: slice, as: UTF8.self)
                s = s.filter { ch in
                    ch == "\u{FFFC}" || (ch.unicodeScalars.first?.value ?? 0) >= 0x20
                }
                s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }
        }
        return ""
    }

    private static func find(_ hay: [UInt8], _ needle: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        var i = from
        while i <= hay.count - needle.count {
            if hay[i] == needle[0] {
                var ok = true
                for j in 1..<needle.count where hay[i + j] != needle[j] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }
}

// MARK: - 私有 SQL 函数的空实现

/// 注册给 after_delete_message_plugin 等 macOS 私有函数用，直接返回不做事。
private let noopSQLFunc: @convention(c) (
    OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?
) -> Void = { _, _, _ in }
