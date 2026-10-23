import Foundation

/// 分类引擎：打分制，阈值 0.34，并输出命中理由
enum Classifier {

    // MARK: 词表

    private static let codeStrong = [
        "验证码", "校验码", "动态码", "确认码", "verification code", "otp", "动态密码"
    ]
    private static let codeWords = [
        "验证码", "校验码", "动态码", "确认码", "激活码", "动态密码", "安全码",
        "验证代码", "短信密码", "一次性密码", "登录码", "授权码", "口令",
        "verification code", "security code", "one-time", "otp", "passcode",
        "auth code", "code is", "your code", "验证身份"
    ]
    private static let expressStrong = [
        "取件码", "驿站", "丰巢", "菜鸟", "快递柜", "签收", "派送", "取货码"
    ]
    private static let expressWords = [
        "快递", "包裹", "快件", "取件", "取货", "取件码", "驿站", "丰巢", "菜鸟",
        "代收", "签收", "派送", "派件", "揽收", "派送员", "快递柜", "自提柜",
        "运单", "单号", "物流", "已到达", "待领取", "超时", "暂存",
        "顺丰", "京东物流", "中通", "圆通", "申通", "韵达", "极兔", "德邦",
        "邮政", "ems", "宅急送", "百世", "安能", "优速",
        "sf express", "delivery", "parcel", "courier"
    ]
    private static let bankStrong = [
        "信用卡", "储蓄卡", "还款", "可用额度", "尾号", "入账", "扣款", "余额"
    ]
    private static let bankWords = [
        "银行", "信用卡", "储蓄卡", "借记卡", "账单", "还款", "消费", "支出",
        "入账", "转入", "转出", "余额", "可用额度", "交易", "尾号", "分期",
        "扣款", "工资", "到账", "退款", "手续费", "年费", "征信", "贷款",
        "支付宝", "微信支付", "银联", "云闪付", "花呗", "借呗", "理财",
        "工商", "建设", "农业", "中国银行", "招商", "交通银行", "浦发", "中信",
        "民生", "兴业", "光大", "平安银行", "广发", "华夏"
    ]
    private static let promoStrong = [
        "退订", "优惠券", "限时", "抢购", "秒杀", "满减", "抽奖", "红包", "促销"
    ]
    private static let promoWords = [
        "优惠", "折扣", "促销", "活动", "领取", "限时", "抢购", "特价", "秒杀",
        "满减", "优惠券", "红包", "福利", "抽奖", "中奖", "免费", "0元", "低至",
        "会员", "积分", "兑换", "退订", "回t退订", "回复td", "td退订", "n退订",
        "点击", "链接", "官网", "下载app", "首单", "立减", "包邮", "大促",
        "双11", "618", "黑五", "周年庆", "新用户", "专享", "内购", "清仓",
        "promotion", "sale", "discount", "unsubscribe", "offer"
    ]
    private static let noticeWords = [
        "预约", "挂号", "航班", "车次", "登机", "订单", "发货", "审核", "注册",
        "登录", "密码", "认证", "提醒", "通知", "会议", "考试", "成绩", "社保",
        "公积金", "水电", "话费", "流量", "停机", "欠费", "缴费", "保险", "体检",
        "面试", "笔试", "录用", "排班", "值班", "签到", "打卡", "天气", "预警",
        "台风", "暴雨", "地震", "停电", "检修", "升级", "维护", "预约成功",
        "医院", "门诊", "取号", "就诊", "复诊", "检票", "候车", "车厢", "座位",
        "值机", "登机牌", "延误", "改签", "退票", "物业", "快递员",
        "机场", "起飞", "降落", "航空公司", "铁路", "12306"
    ]

    // 关键词以字节形式缓存：Data.range(of:) 走 memmem，比 String.contains
    // 的字符簇比较快一个数量级以上（1 万条短信实测 11s -> 亚秒）
    private static let codeWordsD = codeWords.map { ($0, Data($0.utf8)) }
    private static let expressWordsD = expressWords.map { ($0, Data($0.utf8)) }
    private static let bankWordsD = bankWords.map { ($0, Data($0.utf8)) }
    private static let promoWordsD = promoWords.map { ($0, Data($0.utf8)) }
    private static let noticeWordsD = noticeWords.map { ($0, Data($0.utf8)) }

    // MARK: 提取验证码

    static func extractCode(_ text: String) -> String? {
        let low = text.lowercased()
        return extractCode(low: low, hay: Data(low.utf8))
    }

    /// 复用调用方已经算好的小写串，避免重复转换
    static func extractCode(low: String, hay: Data) -> String? {
        let bytes = [UInt8](hay)
        // 没有 ASCII 数字就不可能是验证码
        guard bytes.contains(where: { $0 >= 48 && $0 <= 57 }) else { return nil }

        let strong = codeStrong.contains { hay.range(of: Data($0.utf8)) != nil }

        // 手工扫描 4~8 位连续数字（整段连续的数字串直接跳过，
        // 这样手机号、订单号、年份天然被排除）
        var candidates: [String] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] >= 48, bytes[i] <= 57 {
                var j = i
                while j < bytes.count, bytes[j] >= 48, bytes[j] <= 57 { j += 1 }
                let len = j - i
                if len >= 4, len <= 8 {
                    candidates.append(String(decoding: bytes[i..<j], as: UTF8.self))
                }
                i = j
            } else {
                i += 1
            }
        }
        guard !candidates.isEmpty else { return nil }

        let weak = strong || codeWordsD.contains { hay.range(of: $0.1) != nil }
        guard weak else { return nil }

        func has(_ str: String) -> Bool { hay.range(of: Data(str.utf8)) != nil }

        for num in candidates {
            if num.count == 4, num.hasPrefix("20") { continue }
            if has("¥" + num) || has("￥" + num) || has("$" + num) { continue }
            if has(num + "元") || has(num + "块") || has(num + "万") { continue }
            if has("订单" + num) || has("单号" + num) || has("运单" + num) { continue }
            return num
        }
        return nil
    }

    // MARK: 分类

    static func classify(text: String, sender: String) -> (Category, Double, [String], String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return (.other, 0.3, ["空消息"], nil) }

        let low = t.lowercased()
        let hay = Data(low.utf8)
        var reasons: [String] = []
        var s: [Category: Double] = [:]
        for c in Category.allCases { s[c] = 0 }

        func add(_ c: Category, _ v: Double) { s[c, default: 0] += v }
        func hits(_ words: [(String, Data)]) -> [String] {
            var out: [String] = []
            for (w, d) in words where hay.range(of: d) != nil { out.append(w) }
            return out
        }

        // 验证码
        let code = extractCode(low: low, hay: hay)
        if let c = code {
            add(.code, 0.55)
            reasons.append("含验证码 \(c)")
        }
        let codeAll = hits(codeWordsD)
        let codeStrongHits = codeAll.filter { codeStrong.contains($0) }
        for w in codeStrongHits {
            add(.code, 0.28)
            reasons.append("关键词「\(w)」")
        }
        if let w = codeAll.first(where: { !codeStrong.contains($0) }) {
            add(.code, 0.14)
            reasons.append("关键词「\(w)」")
        }
        if code != nil && ["分钟内有效", "有效", "expires", "valid for", "请勿泄露", "不要告诉"]
            .contains(where: { low.contains($0) }) {
            add(.code, 0.12)
            reasons.append("含有效期/保密提示")
        }

        // 快递
        let expressAll = hits(expressWordsD)
        for w in expressAll where expressStrong.contains(w) {
            add(.express, 0.34)
            reasons.append("关键词「\(w)」")
        }
        for w in expressAll.filter({ !expressStrong.contains($0) }).prefix(3) {
            add(.express, 0.16)
            reasons.append("关键词「\(w)」")
        }
        if t.range(of: "\\d{1,2}[-－]\\d{1,2}[-－]\\d{3,4}", options: .regularExpression) != nil {
            add(.express, 0.18)
            reasons.append("含取件码格式")
        }

        // 银行
        let bankAll = hits(bankWordsD)
        for w in bankAll where bankStrong.contains(w) {
            add(.bank, 0.30)
            reasons.append("关键词「\(w)」")
        }
        for w in bankAll.filter({ !bankStrong.contains($0) }).prefix(3) {
            add(.bank, 0.14)
            reasons.append("关键词「\(w)」")
        }
        if t.contains("¥") || t.contains("￥") || t.contains("$")
            || t.contains("元") || t.contains("块") {
            add(.bank, 0.12)
            reasons.append("含金额")
        }

        // 营销
        let promoAll = hits(promoWordsD)
        for w in promoAll where promoStrong.contains(w) {
            add(.promo, 0.30)
            reasons.append("关键词「\(w)」")
        }
        for w in promoAll.filter({ !promoStrong.contains($0) }).prefix(4) {
            add(.promo, 0.12)
            reasons.append("关键词「\(w)」")
        }
        if low.contains("http") || low.contains("www.")
            || low.contains(".com") || low.contains(".cn") || low.contains(".net") {
            add(.promo, 0.08)
            reasons.append("含链接")
        }

        // 通知
        let nHits = hits(noticeWordsD)
        if !nHits.isEmpty {
            add(.notice, 0.34 + 0.16 * Double(min(nHits.count - 1, 2)))
            for w in nHits.prefix(3) { reasons.append("关键词「\(w)」") }
        }

        // 个人对话
        let bare = sender.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        let isPersonal = isMobileNumber(bare)
            || (sender.contains("@") && !isShortcode(sender))
        let strongCommercial = !codeStrongHits.isEmpty
            || expressAll.contains(where: { expressStrong.contains($0) })
            || bankAll.contains(where: { bankStrong.contains($0) })
            || promoAll.contains(where: { promoStrong.contains($0) })
        if isPersonal && !strongCommercial {
            s[.person] = max(s[.person] ?? 0, 0.88)
            reasons.append("来自个人号码且无商业特征")
        }

        if code != nil && codeStrong.contains(where: { low.contains($0) }) {
            add(.code, 0.35)
        }

        var best = Category.other
        var bestScore = -1.0
        for (cat, score) in s where score > bestScore {
            best = cat
            bestScore = score
        }
        if bestScore < 0.34 { best = .other }

        let final = best == .other ? 0.30 : min(bestScore, 1.0)
        return (best, (final * 100).rounded() / 100, Array(reasons.prefix(6)), code)
    }

    /// 手机号判定：纯字符比较，比正则快一个数量级
    static func isMobileNumber(_ raw: String) -> Bool {
        var d = raw
        if d.hasPrefix("+86") { d = String(d.dropFirst(3)) }
        else if d.hasPrefix("86"), d.count == 13 { d = String(d.dropFirst(2)) }
        guard d.count == 11 else { return false }
        let chars = Array(d)
        guard chars.allSatisfy({ $0.isNumber }) else { return false }
        return chars[0] == "1" && "3456789".contains(chars[1])
    }

    static func isShortcode(_ s: String) -> Bool {
        (3...8).contains(s.count) && s.allSatisfy({ $0.isNumber })
    }

    static func apply(to messages: inout [SMSMessage]) {
        for i in messages.indices {
            let (cat, score, reasons, code) =
                classify(text: messages[i].text, sender: messages[i].sender)
            messages[i].category = cat
            messages[i].score = score
            messages[i].reasons = reasons
            messages[i].code = code
        }
    }
}
