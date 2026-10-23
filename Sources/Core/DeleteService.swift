import Foundation
import AppKit
import SQLite3

// MARK: - 回收站数据结构

struct TrashRow: Codable {
    var rowid: Int64
    var guid: String?
    var text: String?
    var bodyB64: String?
    var date: Int64
    var isFromMe: Int
    var isRead: Int
    var service: String?
    var handleId: Int64
    var hasAtt: Int
    var chats: [Int64]
}

struct TrashBatch: Codable, Identifiable {
    var id: String
    var time: String
    var count: Int
    var source: String      // manual | rule
    var ruleName: String?
    var isDemo: Bool
    var rows: [TrashRow]
}

struct BackupFile: Identifiable {
    var id: String { name }
    var name: String
    var path: String
    var sizeMB: Double
    var date: Date
}

// MARK: - 清理规则

enum CleanupRule: String, CaseIterable, Identifiable {
    case codeDup, codeOld, codeRead, codeAll
    case expressOld, expressAll, promoAll, lowValue
    case bankOld, unreadPromo, empty, olderAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codeDup: return L.t("重复验证码去重")
        case .codeOld: return L.t("过期验证码")
        case .codeRead: return L.t("已读验证码")
        case .codeAll: return L.t("全部验证码")
        case .expressOld: return L.t("过期快递通知")
        case .expressAll: return L.t("全部快递通知")
        case .promoAll: return L.t("营销推广短信")
        case .lowValue: return L.t("一键清理低价值")
        case .bankOld: return L.t("旧银行账单")
        case .unreadPromo: return L.t("未读营销与通知")
        case .empty: return L.t("无正文消息")
        case .olderAll: return L.t("按时间批量清理")
        }
    }

    var detail: String {
        switch self {
        case .codeDup: return L.t("同一发件人同一天的多条验证码，只保留最新一条。")
        case .codeOld: return L.t("验证码有效期只有几分钟，超过设定天数的没有保留价值。")
        case .codeRead: return L.t("只清理已读验证码，未读的保留，避免误删还没用的码。")
        case .codeAll: return L.t("一次性清空所有验证码短信，建议先预览。")
        case .expressOld: return L.t("超过设定天数的快递、驿站、取件码通知。")
        case .expressAll: return L.t("清空所有快递物流类短信。")
        case .promoAll: return L.t("促销、优惠券、退订类短信，通常占比最大。")
        case .lowValue: return L.t("营销推广 + 空消息 + 重复验证码，一次清掉最没用的部分。")
        case .bankOld: return L.t("超过设定天数的银行消费、还款提醒。")
        case .unreadPromo: return L.t("从没点开过的推广和通知短信。")
        case .empty: return L.t("只有附件或表情、没有文字的消息。")
        case .olderAll: return L.t("删除设定天数之前的全部短信，可保留指定类型。")
        }
    }

    var symbol: String {
        switch self {
        case .codeDup: return "doc.on.doc"
        case .codeOld: return "clock.badge.xmark"
        case .codeRead: return "checkmark.circle"
        case .codeAll: return "lock.shield"
        case .expressOld: return "shippingbox"
        case .expressAll: return "shippingbox.fill"
        case .promoAll: return "tag"
        case .lowValue: return "wand.and.stars"
        case .bankOld: return "creditcard"
        case .unreadPromo: return "bell.badge"
        case .empty: return "rectangle.dashed"
        case .olderAll: return "calendar"
        }
    }

    var defaultDays: Int {
        switch self {
        case .codeOld: return 7
        case .expressOld: return 30
        case .bankOld: return 365
        case .olderAll: return 180
        default: return 0
        }
    }

    var usesDays: Bool { defaultDays > 0 }
    var usesKeep: Bool { self == .olderAll }
}

// MARK: - 删除服务

@MainActor
final class DeleteService {
    static let shared = DeleteService()

    private let fm = FileManager.default

    var supportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SMSKeeper", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var backupDir: URL {
        let d = supportDir.appendingPathComponent("backups", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    var trashDir: URL {
        let d = supportDir.appendingPathComponent("trash", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: 进程

    var messagesRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.MobileSMS").isEmpty
    }

    @discardableResult
    func quitMessages(timeout: TimeInterval = 10) -> Bool {
        guard messagesRunning else { return true }
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.MobileSMS")
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !messagesRunning { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !messagesRunning
    }

    // MARK: 备份

    func createBackup(tag: String) throws -> BackupFile {
        let name = "chat-\(Fmt.stamp.string(from: Date()))-\(tag).db"
        let dst = backupDir.appendingPathComponent(name)
        let src = Database.shared.activePath

        var copied = false
        if let db = try? SQLiteDB(path: src, readOnly: true) {
            defer { db.close() }
            let escaped = dst.path.replacingOccurrences(of: "'", with: "''")
            if (try? db.exec("VACUUM INTO '\(escaped)'")) != nil,
               fm.fileExists(atPath: dst.path) {
                copied = true
            }
        }
        if !copied {
            try? fm.removeItem(at: dst)
            try fm.copyItem(atPath: src, toPath: dst.path)
        }
        pruneBackups()
        let attrs = try? fm.attributesOfItem(atPath: dst.path)
        let bytes = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
        return BackupFile(name: name, path: dst.path,
                          sizeMB: (bytes / 1_048_576 * 10).rounded() / 10,
                          date: Date())
    }

    private func pruneBackups() {
        guard let files = try? fm.contentsOfDirectory(atPath: backupDir.path) else { return }
        let sorted = files.filter { $0.hasSuffix(".db") }.sorted()
        if sorted.count > 20 {
            for name in sorted.prefix(sorted.count - 20) {
                try? fm.removeItem(at: backupDir.appendingPathComponent(name))
            }
        }
    }

    func listBackups() -> [BackupFile] {
        guard let files = try? fm.contentsOfDirectory(atPath: backupDir.path) else { return [] }
        return files.filter { $0.hasSuffix(".db") }.compactMap { name -> BackupFile? in
            let url = backupDir.appendingPathComponent(name)
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let bytes = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
            let date = (attrs?[.modificationDate] as? Date) ?? Date()
            return BackupFile(name: name, path: url.path,
                              sizeMB: (bytes / 1_048_576 * 10).rounded() / 10, date: date)
        }.sorted { $0.name > $1.name }
    }

    // MARK: 删除

    struct DeleteResult {
        var deleted: Int
        var backupName: String
        var batchID: String
        var remaining: Int = 0      // 删除后读回的库内实际条数
    }

    func delete(messages: [SMSMessage], source: String,
                ruleName: String? = nil) throws -> DeleteResult {
        guard !messages.isEmpty else {
            return DeleteResult(deleted: 0, backupName: "", batchID: "")
        }
        Log.event("delete.begin", "count", "\(messages.count)", "source", source,
                  "rule", ruleName ?? "-",
                  "mode", Database.shared.isDemo ? "demo" : "real")
        if !Database.shared.isDemo {
            Log.event("delete.quit_messages", "running",
                      DeleteService.shared.messagesRunning ? "1" : "0")
            guard quitMessages() else {
                Log.error("delete.quit_messages_failed", code: 2, msg: "信息 App 未能退出")
                throw NSError(domain: "SMSKeeper", code: 1, userInfo: [
                    NSLocalizedDescriptionKey:
                        "「信息」App 仍在运行，为避免数据库损坏已中止。请先退出「信息」后再试。"
                ])
            }
            Log.event("delete.quit_messages", "result", "ok")
        }

        let backup = try createBackup(tag: "before-delete")
        Log.event("delete.backup", "name", backup.name, "mb", "\(backup.sizeMB)")

        // 删除前的库内条数，供删除后校验用
        let beforeCount: Int = {
            guard let db = try? Database.shared.writeConnection() else { return -1 }
            defer { db.close() }
            return db.scalarInt("SELECT COUNT(*) FROM message") ?? -1
        }()
        let ids = messages.map(\.id)

        // 先把原始行写入回收站
        let chatMap = Database.shared.chatIDs(for: ids)
        let bodies = Database.shared.attributedBodies(for: ids)
        let byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        let rows: [TrashRow] = ids.compactMap { rid in
            guard let m = byID[rid] else { return nil }
            return TrashRow(
                rowid: rid, guid: m.guid, text: m.text,
                bodyB64: bodies[rid]?.base64EncodedString(),
                date: AppleTime.fromDate(m.date),
                isFromMe: m.isFromMe ? 1 : 0, isRead: m.isRead ? 1 : 0,
                service: m.service, handleId: 0, hasAtt: m.attachments,
                chats: chatMap[rid] ?? []
            )
        }
        let batchID = Fmt.stamp.string(from: Date())
        let batch = TrashBatch(id: batchID, time: Fmt.full.string(from: Date()),
                               count: rows.count, source: source, ruleName: ruleName,
                               isDemo: Database.shared.isDemo, rows: rows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(batch)
        try data.write(to: trashDir.appendingPathComponent("batch-\(batchID).json"))

        // 执行删除
        let db = try Database.shared.writeConnection()
        var deleted = 0
        let t0 = Date()
        do {
            try db.exec("BEGIN IMMEDIATE")
            Log.event("delete.txn", "state", "begin")
            for (ci, chunk) in ids.chunked(400).enumerated() {
                let ph = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let stmt = try db.prepare("DELETE FROM message WHERE ROWID IN (\(ph))")
                for (i, v) in chunk.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), v) }
                if sqlite3_step(stmt) != SQLITE_DONE {
                    let msg = db.lastError()
                    sqlite3_finalize(stmt)
                    Log.error("delete.stmt_failed", code: 1, msg: msg,
                              extra: ["table": "message", "chunk": "\(ci)",
                                      "size": "\(chunk.count)",
                                      "sql": "DELETE FROM message WHERE ROWID IN (\(ph))"])
                    throw DBError.sql(msg)
                }
                deleted += Int(sqlite3_changes(db.handle))
                sqlite3_finalize(stmt)

                for table in ["chat_message_join", "message_attachment_join"] where db.hasTable(table) {
                    let s2 = try db.prepare("DELETE FROM \(table) WHERE message_id IN (\(ph))")
                    for (i, v) in chunk.enumerated() { sqlite3_bind_int64(s2, Int32(i + 1), v) }
                    if sqlite3_step(s2) != SQLITE_DONE {
                        let msg = db.lastError()
                        sqlite3_finalize(s2)
                        Log.error("delete.child_failed", code: 1, msg: msg,
                                  extra: ["table": table, "chunk": "\(ci)"])
                        throw DBError.sql(msg)
                    }
                    sqlite3_finalize(s2)
                }
                Log.event("delete.chunk", "index", "\(ci)", "rows", "\(chunk.count)")
            }
            try db.exec("COMMIT")
            Log.event("delete.commit", "rows", "\(deleted)",
                      "ms", "\(Int(Date().timeIntervalSince(t0) * 1000))")
            try? db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        } catch {
            try? db.exec("ROLLBACK")
            Log.event("delete.rollback", "rows_deleted_so_far", "\(deleted)")
            db.close()
            throw error
        }
        db.close()
        Log.event("delete.done", "deleted", "\(deleted)", "backup", backup.name)

        // 读回校验：确认库内条数真的减少了。
        // 防止"界面显示成功但库里没变"的情况（例如被外部进程回写）。
        let remaining: Int = {
            guard let db = try? Database.shared.writeConnection() else { return -1 }
            defer { db.close() }
            return db.scalarInt("SELECT COUNT(*) FROM message") ?? -1
        }()
        let expected = beforeCount >= 0 ? beforeCount - deleted : -1
        Log.event("delete.verify", "expected", "\(expected)", "actual", "\(remaining)",
                  "before", "\(beforeCount)")
        if expected >= 0, remaining >= 0, remaining != expected {
            Log.error("delete.verify_failed", code: 3,
                      msg: "删除后库内条数与预期不符",
                      extra: ["expected": "\(expected)", "actual": "\(remaining)"])
            throw NSError(domain: "SMSKeeper", code: 3, userInfo: [
                NSLocalizedDescriptionKey: String(
                    format: L.t("删除后校验失败：预期剩余 %d 条，实际 %d 条。可能有其它程序（如 iCloud 同步）把数据写回了。"),
                    expected, remaining)
            ])
        }

        return DeleteResult(deleted: deleted, backupName: backup.name,
                            batchID: batchID, remaining: remaining)
    }

    // MARK: 回收站

    func listTrash() -> [TrashBatch] {
        guard let files = try? fm.contentsOfDirectory(atPath: trashDir.path) else { return [] }
        let decoder = JSONDecoder()
        return files.filter { $0.hasPrefix("batch-") && $0.hasSuffix(".json") }
            .compactMap { name -> TrashBatch? in
                let url = trashDir.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TrashBatch.self, from: data)
            }
            .sorted { $0.id > $1.id }
    }

    func restore(_ batch: TrashBatch) throws -> Int {
        if !Database.shared.isDemo {
            guard quitMessages() else {
                throw NSError(domain: "SMSKeeper", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "「信息」App 仍在运行，已中止恢复。"
                ])
            }
        }
        _ = try createBackup(tag: "before-restore")

        let db = try Database.shared.writeConnection()
        var restored = 0
        do {
            try db.exec("BEGIN IMMEDIATE")
            let cols = db.columns(of: "message")
            let hasBody = cols.contains("attributedBody")
            let sql = """
            INSERT OR REPLACE INTO message
              (ROWID, guid, text\(hasBody ? ", attributedBody" : ""),
               date, is_from_me, is_read, service, handle_id,
               cache_has_attachments, item_type)
            VALUES (?,?,?\(hasBody ? ",?" : ""),?,?,?,?,?,?,0)
            """
            let stmt = try db.prepare(sql)
            defer { sqlite3_finalize(stmt) }

            for row in batch.rows {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                var idx: Int32 = 1
                sqlite3_bind_int64(stmt, idx, row.rowid); idx += 1
                bindText(stmt, idx, row.guid); idx += 1
                bindText(stmt, idx, row.text); idx += 1
                if hasBody {
                    if let b64 = row.bodyB64, let data = Data(base64Encoded: b64) {
                        _ = data.withUnsafeBytes { buf in
                            sqlite3_bind_blob(stmt, idx, buf.baseAddress,
                                              Int32(data.count), SQLITE_TRANSIENT)
                        }
                    } else {
                        sqlite3_bind_null(stmt, idx)
                    }
                    idx += 1
                }
                sqlite3_bind_int64(stmt, idx, row.date); idx += 1
                sqlite3_bind_int(stmt, idx, Int32(row.isFromMe)); idx += 1
                sqlite3_bind_int(stmt, idx, Int32(row.isRead)); idx += 1
                bindText(stmt, idx, row.service); idx += 1
                sqlite3_bind_int64(stmt, idx, row.handleId); idx += 1
                sqlite3_bind_int(stmt, idx, Int32(row.hasAtt)); idx += 1

                if sqlite3_step(stmt) == SQLITE_DONE {
                    restored += 1
                } else {
                    Log.error("restore.row_failed", code: 1, msg: db.lastError(),
                              extra: ["row": "\(row.rowid)"])
                }
            }

            if db.hasTable("chat_message_join") {
                let cstmt = try db.prepare(
                    "INSERT OR IGNORE INTO chat_message_join (chat_id, message_id, message_date) VALUES (?,?,?)")
                defer { sqlite3_finalize(cstmt) }
                for row in batch.rows {
                    for cid in row.chats {
                        sqlite3_reset(cstmt)
                        sqlite3_clear_bindings(cstmt)
                        sqlite3_bind_int64(cstmt, 1, cid)
                        sqlite3_bind_int64(cstmt, 2, row.rowid)
                        sqlite3_bind_int64(cstmt, 3, row.date)
                        sqlite3_step(cstmt)
                    }
                }
            }
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            db.close()
            throw error
        }
        db.close()

        try? fm.removeItem(at: trashDir.appendingPathComponent("batch-\(batch.id).json"))
        return restored
    }

    func purge(_ batch: TrashBatch) {
        try? fm.removeItem(at: trashDir.appendingPathComponent("batch-\(batch.id).json"))
    }

    // MARK: 规则匹配

    func match(rule: CleanupRule, days: Int, keep: Set<Category>,
               in messages: [SMSMessage]) -> [SMSMessage] {
        let cutoff = Date().addingTimeInterval(-Double(max(0, days)) * 86400)

        switch rule {
        case .codeAll:
            return messages.filter { $0.category == .code }
        case .codeOld:
            return messages.filter { $0.category == .code && $0.date < cutoff }
        case .codeRead:
            return messages.filter { $0.category == .code && $0.isRead }
        case .codeDup:
            var groups: [String: [SMSMessage]] = [:]
            for m in messages where m.category == .code {
                let key = m.sender + "|" + Fmt.short.string(from: m.date)
                groups[key, default: []].append(m)
            }
            var out: [SMSMessage] = []
            for (_, g) in groups where g.count > 1 {
                let sorted = g.sorted { $0.date > $1.date }
                out.append(contentsOf: sorted.dropFirst())
            }
            return out
        case .expressAll:
            return messages.filter { $0.category == .express }
        case .expressOld:
            return messages.filter { $0.category == .express && $0.date < cutoff }
        case .promoAll:
            return messages.filter { $0.category == .promo }
        case .lowValue:
            var out = messages.filter { $0.category == .promo || $0.text.isEmpty }
            out.append(contentsOf: match(rule: .codeDup, days: 0, keep: [], in: messages))
            var seen = Set<Int64>()
            return out.filter { seen.insert($0.id).inserted }
        case .bankOld:
            return messages.filter { $0.category == .bank && $0.date < cutoff }
        case .unreadPromo:
            return messages.filter {
                ($0.category == .promo || $0.category == .notice) && $0.isUnread
            }
        case .empty:
            return messages.filter { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        case .olderAll:
            return messages.filter { $0.date < cutoff && !keep.contains($0.category) }
        }
    }
}

// MARK: - 辅助

func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) {
    if let v = value {
        sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
