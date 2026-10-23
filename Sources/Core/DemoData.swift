import Foundation
import SQLite3

/// 演示数据：在没有磁盘权限时，让界面依然可用、可试删除
enum DemoData {

    static var demoPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SMSKeeper/demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat.db").path
    }

    private static let schema = """
    CREATE TABLE handle (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE,
        country TEXT, service TEXT);
    CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE,
        text TEXT, handle_id INTEGER DEFAULT 0, attributedBody BLOB, date INTEGER,
        is_from_me INTEGER DEFAULT 0, is_read INTEGER DEFAULT 0, service TEXT,
        cache_has_attachments INTEGER DEFAULT 0, item_type INTEGER DEFAULT 0);
    CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER,
        message_date INTEGER DEFAULT 0, PRIMARY KEY (chat_id, message_id));
    CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER,
        PRIMARY KEY (message_id, attachment_id));
    """

    private static let shortcodes = ["1069031234567", "1065502088888", "95588", "95533", "1069000099"]
    private static let mobiles = ["+8613800138000", "+8613900139000", "+8618600138000"]

    private static let codeTemplates = [
        "【支付宝】验证码 %@，您正在登录支付宝，5分钟内有效。请勿向任何人透露。",
        "【美团】您的验证码是 %@，用于账号登录，10分钟内有效。",
        "【京东】验证码 %@，您正在进行身份验证，如非本人操作请忽略。",
        "【微信】%@ 是您的登录验证码，请于 5 分钟内填写。",
        "【招商银行】您正在进行快捷支付验证，验证码 %@，请勿泄露。",
        "【12306】您的登录验证码为 %@，30分钟内有效。",
        "【滴滴出行】验证码：%@，用于本次登录，请勿转发他人。",
        "【钉钉】%@ 为你的动态密码，有效期 3 分钟。",
        "Your Taobao verification code is %@. Do not share it with anyone."
    ]

    private static let expressTemplates = [
        "【顺丰速运】您的快递已到达【望京SOHO驿站】，取件码 3-2-%d，请及时领取。",
        "【菜鸟驿站】您的包裹已存放至 5 号楼丰巢柜，取件码 %d，超时 24 小时将退回。",
        "【中通快递】您的快件正在派送中，快递员 王师傅 138****%d，请保持电话畅通。",
        "【京东物流】您的订单已签收，如有问题请联系配送员。感谢使用京东。",
        "【丰巢】您的包裹已存入丰巢智能柜，取件码 %d，请在 18 小时内取件。",
        "【韵达快递】您的包裹已由本人签收，感谢使用韵达。"
    ]

    private static let bankTemplates = [
        "【中国银行】您尾号%d的储蓄卡于10月%d日消费人民币%d.%02d元，余额 %d.%02d元。",
        "【招商银行】您信用卡本期账单金额 %d.%02d 元，最后还款日 10月%d日，请按时还款。",
        "【工商银行】您尾号%d账户于10月%d日入账工资 %d.%02d 元。",
        "【建设银行】您尾号%d的信用卡可用额度 %d.%02d 元。"
    ]

    private static let promoTemplates = [
        "【天猫】双11预售开启！满300减50，叠加店铺券更划算，点击 t.cn/abc%d 领取。回TD退订",
        "【拼多多】限时秒杀！9.9元包邮抢纸巾，仅剩%d件，戳链接下单 回复TD退订",
        "【瑞幸咖啡】您有 1 张 3.8 折优惠券即将过期，点击领取。退订回T",
        "【美团外卖】新用户专享红包 %d 元，首单立减，点击领取 https://mt.cn/x%d",
        "【屈臣氏】会员日全场8折，积分兑换好礼，详情见门店。回T退订"
    ]

    private static let noticeTemplates = [
        "【北京协和医院】您已预约 10月%d日 上午 9:00 内科门诊，请提前 30 分钟取号。",
        "【南方航空】您乘坐的 CZ%d 航班 10月%d日 10:20 起飞，请提前 2 小时到达机场。",
        "【顺丰】您的订单 %d 已发货，预计 10月%d日 送达。",
        "【国家电网】您家电表余额不足，请及时缴费，欠费将影响供电。",
        "【中国移动】您的话费余额为 %d 元，为避免停机请及时充值。",
        "【社保局】您的社保缴费已到账，累计缴费 %d 个月。"
    ]

    private static let personTemplates = [
        "在吗？晚上一起吃饭？", "刚到家，路上有点堵", "会议改到三点了，记得带电脑",
        "照片我发你邮箱了", "好的，收到", "明天几点出发？",
        "这个方案我再改一版给你", "生日快乐！"
    ]

    static func buildIfNeeded(force: Bool = false) -> String {
        let path = demoPath
        if !force, FileManager.default.fileExists(atPath: path) { return path }
        try? FileManager.default.removeItem(atPath: path)

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let h = db else { return path }
        defer { sqlite3_close(h) }
        sqlite3_exec(h, schema, nil, nil, nil)

        // handle
        var handleIDs: [String: Int64] = [:]
        for (i, hid) in (shortcodes + mobiles).enumerated() {
            let sql = "INSERT INTO handle (ROWID, id, service) VALUES (?,?,?)"
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(h, sql, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(i + 1))
            sqlite3_bind_text(stmt, 2, hid, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, "SMS", -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            handleIDs[hid] = Int64(i + 1)
        }

        let now = Date()
        var records: [(String, String, String, Date, Bool)] = []

        for i in 0..<220 {
            let c = String(format: "%06d", Int.random(in: 100000...999999))
            let t = codeTemplates[i % codeTemplates.count]
            records.append(("code", String(format: t, c),
                            shortcodes[i % shortcodes.count],
                            now.addingTimeInterval(-Double.random(in: 0...190) * 86400),
                            Bool.random()))
        }
        for i in 0..<110 {
            let t = expressTemplates[i % expressTemplates.count]
            records.append(("express", String(format: t, Int.random(in: 1000...9999)),
                            shortcodes[(i + 1) % shortcodes.count],
                            now.addingTimeInterval(-Double.random(in: 0...190) * 86400),
                            Bool.random()))
        }
        for i in 0..<80 {
            let t = bankTemplates[i % bankTemplates.count]
            let args: [Int] = [Int.random(in: 1000...9999), Int.random(in: 1...28),
                               Int.random(in: 10...5000), Int.random(in: 10...99),
                               Int.random(in: 100...99999), Int.random(in: 10...99)]
            var s = String(format: t, args[0], args[1], args[2], args[3], args[4], args[5])
            s = s.replacingOccurrences(of: "%d", with: String(Int.random(in: 100...999)))
            records.append(("bank", s, ["95588", "95533", "1069000099"][i % 3],
                            now.addingTimeInterval(-Double.random(in: 0...190) * 86400),
                            Bool.random()))
        }
        for i in 0..<130 {
            let t = promoTemplates[i % promoTemplates.count]
            var s = String(format: t, Int.random(in: 1...999))
            if s.contains("%d") {
                s = s.replacingOccurrences(of: "%d", with: String(Int.random(in: 1...999)))
            }
            records.append(("promo", s, shortcodes[(i + 2) % shortcodes.count],
                            now.addingTimeInterval(-Double.random(in: 0...190) * 86400),
                            Bool.random()))
        }
        for i in 0..<50 {
            let t = noticeTemplates[i % noticeTemplates.count]
            var s = String(format: t, Int.random(in: 1...28))
            if s.contains("%d") {
                s = s.replacingOccurrences(of: "%d", with: String(Int.random(in: 100...999)))
            }
            records.append(("notice", s, ["1069000099", "95588"][i % 2],
                            now.addingTimeInterval(-Double.random(in: 0...190) * 86400),
                            Bool.random()))
        }
        for i in 0..<40 {
            records.append(("person", personTemplates[i % personTemplates.count],
                            mobiles[i % mobiles.count],
                            now.addingTimeInterval(-Double.random(in: 0...190) * 86400),
                            Bool.random()))
        }

        records.sort { $0.3 < $1.3 }

        let insert = """
        INSERT INTO message (guid, text, handle_id, attributedBody, date, is_from_me,
                             is_read, service, cache_has_attachments, item_type)
        VALUES (?,?,?,?,?,?,?,?,?,0)
        """
        let join = """
        INSERT OR IGNORE INTO chat_message_join (chat_id, message_id, message_date)
        VALUES (?,?,?)
        """

        for (idx, rec) in records.enumerated() {
            let (kind, text, sender, date, unread) = rec
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(h, insert, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, "demo-\(idx)", -1, SQLITE_TRANSIENT)

            // 每 7 条模拟一条 text 为空、正文在 attributedBody 里的情况
            let nullText = (kind == "code" && idx % 7 == 0)
            if nullText {
                sqlite3_bind_null(stmt, 2)
                let blob = makeAttributedBody(text)
                _ = blob.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, 4, buf.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_null(stmt, 4)
            }

            sqlite3_bind_int64(stmt, 3, handleIDs[sender] ?? 1)
            sqlite3_bind_int64(stmt, 5, AppleTime.fromDate(date))
            sqlite3_bind_int(stmt, 6, kind == "person" && Bool.random() ? 1 : 0)
            sqlite3_bind_int(stmt, 7, unread ? 0 : 1)
            sqlite3_bind_text(stmt, 8, "SMS", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 9, 0)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)

            let mid = sqlite3_last_insert_rowid(h)
            var cstmt: OpaquePointer?
            sqlite3_prepare_v2(h, join, -1, &cstmt, nil)
            sqlite3_bind_int64(cstmt, 1, handleIDs[sender] ?? 1)
            sqlite3_bind_int64(cstmt, 2, mid)
            sqlite3_bind_int64(cstmt, 3, AppleTime.fromDate(date))
            sqlite3_step(cstmt)
            sqlite3_finalize(cstmt)
        }

        sqlite3_exec(h, "PRAGMA journal_mode=WAL", nil, nil, nil)
        return path
    }

    /// 构造与真实 typedstream 结构一致的 blob，用于验证解析路径
    private static func makeAttributedBody(_ text: String) -> Data {
        var d = Data()
        d.append(contentsOf: [0x04, 0x0B, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D, 0x74, 0x79, 0x70, 0x65, 0x64])
        d.append(contentsOf: [0x81, 0xE0, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12])
        d.append(contentsOf: Array("NSAttributedString".utf8))
        d.append(contentsOf: [0x00, 0x84, 0x84, 0x08])
        d.append(contentsOf: Array("NSObject".utf8))
        d.append(contentsOf: [0x00, 0x85, 0x92, 0x84, 0x84, 0x84, 0x08])
        d.append(contentsOf: Array("NSString".utf8))
        d.append(contentsOf: [0x01, 0x94, 0x84, 0x01])
        d.append(contentsOf: Array("+".utf8))
        d.append(contentsOf: Array(text.utf8))
        d.append(contentsOf: [0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x10, 0x92, 0x84, 0x84, 0x84, 0x08])
        d.append(contentsOf: Array("NSObject".utf8))
        d.append(contentsOf: [0x00, 0x85, 0x92, 0x84, 0x84, 0x84, 0x08])
        d.append(contentsOf: Array("NSNumber".utf8))
        return d
    }
}
