import Foundation
import AppKit

/// 调试日志。默认关闭，在「设置与诊断 › 诊断」里打开。
///
/// 隐私红线（写进代码，不靠自觉）：
/// - 只接受**元数据**：条数、ROWID、表名、SQL 模板、错误码、耗时、阶段名。
/// - 绝不允许记录短信正文、验证码、发件人号码、guid 内容。
///   `Log` 内部有最后一道防线：命中黑名单的 key 一律替换为占位符，
///   超长值截断。即使将来有人误传，也落不下去盘。
///
/// 日志位置：~/Library/Logs/SMSKeeper/smskeeper-YYYY-MM-DD.log
enum Log {
    private static let lock = NSLock()
    private static var cachedEnabled = false
    private static var cachedDate = ""

    /// UserDefaults key，设置页的开关直接改这里
    static let enabledKey = "SMSKeeper.debugLog"

    static var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedEnabled
    }

    /// 语言/开关变化时刷新缓存（避免每次写日志都读 UserDefaults）
    ///
    /// 说明：直接跑 Mach-O 二进制时没有 bundle id，UserDefaults 会落到另一个
    /// domain，所以额外认一个环境变量 SMSKEEPER_FORCELOG，供命令行/自检排查用。
    /// 正常用户走设置页开关，两者取或。
    static func refresh() {
        lock.lock(); defer { lock.unlock() }
        cachedEnabled = UserDefaults.standard.bool(forKey: enabledKey)
            || ProcessInfo.processInfo.environment["SMSKEEPER_FORCELOG"] != nil
    }

    // MARK: 隐私防线

    /// 这些 key 一律不记录值。覆盖短信内容、发件人、验证码等一切用户数据。
    private static let forbiddenKeys: Set<String> = [
        "text", "body", "attributedbody", "sender", "guid", "content",
        "handle", "handleid", "message", "phone", "number", "code",
        "address", "email", "account", "chatid", "rowtext", "payload",
    ]

    private static let maxValueLength = 160

    private static func sanitize(key: String, value: String) -> String {
        if forbiddenKeys.contains(key.lowercased()) {
            return "[按隐私策略省略]"
        }
        if value.count > maxValueLength {
            return String(value.prefix(maxValueLength)) + "…[截断]"
        }
        return value
    }

    // MARK: 写入

    private static var logDir: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SMSKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var logFileURL: URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return logDir.appendingPathComponent("smskeeper-\(fmt.string(from: Date())).log")
    }

    /// 打开日志所在目录（访达）
    static func revealInFinder() {
        NSWorkspace.shared.open(logDir)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logDir)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    /// 记一条事件。fields 只放元数据，见文件头隐私说明。
    ///
    ///     Log.event("delete.begin", "count", "8", "source", "rule", "rule", "promo_all")
    static func event(_ name: String, _ fields: String...) {
        guard isEnabled else { return }
        var parts: [String] = []
        var i = 0
        while i + 1 < fields.count {
            parts.append("\(fields[i])=\(sanitize(key: fields[i], value: fields[i + 1]))")
            i += 2
        }
        write(name, parts.joined(separator: " "))
    }

    /// 记一条错误。msg 允许包含 SQLite 的原始错误文本（不含用户数据）。
    static func error(_ name: String, code: Int, msg: String, extra: [String: String] = [:]) {
        guard isEnabled else { return }
        var parts = ["code=\(code)", "msg=\"\(sanitize(key: "msg", value: msg))\""]
        for (k, v) in extra { parts.append("\(k)=\(sanitize(key: k, value: v))") }
        write(name, parts.joined(separator: " "))
    }

    private static func write(_ name: String, _ body: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let line = "\(fmt.string(from: Date())) [\(name)] \(body)\n"

        lock.lock(); defer { lock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        let url = logFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
