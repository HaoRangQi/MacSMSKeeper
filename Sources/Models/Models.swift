import Foundation
import SwiftUI

// MARK: - 分类

enum Category: String, CaseIterable, Codable, Hashable, Identifiable {
    case code, express, bank, promo, notice, person, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .code: return L.t("验证码")
        case .express: return L.t("快递物流")
        case .bank: return L.t("银行账单")
        case .promo: return L.t("营销推广")
        case .notice: return L.t("通知服务")
        case .person: return L.t("个人对话")
        case .other: return L.t("其他")
        }
    }

    var color: Color {
        switch self {
        case .code: return Color(hex: 0x2563EB)
        case .express: return Color(hex: 0xEA580C)
        case .bank: return Color(hex: 0x059669)
        case .promo: return Color(hex: 0x9333EA)
        case .notice: return Color(hex: 0x0891B2)
        case .person: return Color(hex: 0x6B7280)
        case .other: return Color(hex: 0x9CA3AF)
        }
    }

    var symbol: String {
        switch self {
        case .code: return "lock.shield"
        case .express: return "shippingbox"
        case .bank: return "creditcard"
        case .promo: return "tag"
        case .notice: return "bell"
        case .person: return "person"
        case .other: return "circle.dashed"
        }
    }
}

// MARK: - 消息

struct SMSMessage: Identifiable, Hashable {
    let id: Int64
    var guid: String
    var text: String
    var date: Date
    var isFromMe: Bool
    var isRead: Bool
    var service: String
    var sender: String
    var chatIDs: [Int64]
    var attachments: Int
    var category: Category = .other
    var score: Double = 0
    var reasons: [String] = []
    var code: String? = nil
    var searchText: String = ""   // 小写缓存，避免每次筛选重复转换

    var isUnread: Bool { !isRead && !isFromMe }

    var snippet: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "（无正文）" : t.replacingOccurrences(of: "\n", with: " ")
    }

    static func == (lhs: SMSMessage, rhs: SMSMessage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 时间范围

enum TimeRange: String, CaseIterable, Identifiable {
    case all, today, d7, d30, d90, d365, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L.t("全部时间")
        case .today: return L.t("今天")
        case .d7: return L.t("近 7 天")
        case .d30: return L.t("近 30 天")
        case .d90: return L.t("近 90 天")
        case .d365: return L.t("近一年")
        case .custom: return L.t("自定义…")
        }
    }
    var days: Int? {
        switch self {
        case .today: return 0
        case .d7: return 7
        case .d30: return 30
        case .d90: return 90
        case .d365: return 365
        default: return nil
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case newest, oldest, longest, sender
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest: return L.t("最新优先")
        case .oldest: return L.t("最早优先")
        case .longest: return L.t("内容最长")
        case .sender: return L.t("按发件人")
        }
    }
}

// MARK: - 侧边栏

enum SidebarItem: Hashable {
    case dashboard
    case all
    case category(Category)
    case cleanup
    case trash
    case settings

    var title: String {
        switch self {
        case .dashboard: return L.t("概览")
        case .all: return L.t("全部短信")
        case .category(let c): return c.label
        case .cleanup: return L.t("智能清理")
        case .trash: return L.t("回收站")
        case .settings: return L.t("设置与诊断")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .all: return "tray.full"
        case .category(let c): return c.symbol
        case .cleanup: return "wand.and.stars"
        case .trash: return "trash"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - 颜色扩展

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 格式化

enum Fmt {
    private static let relativeZh: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    private static let relativeEn: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    static var relative: DateFormatter { L.code == "en" ? relativeEn : relativeZh }

    private static let fullZh: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return f
    }()

    private static let fullEn: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy HH:mm:ss"
        return f
    }()

    static var full: DateFormatter { L.code == "en" ? fullEn : fullZh }

    static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 给 CSV 用：可排序、Excel 能识别成日期
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    // 列表里每行都会调用，格式化器必须复用，否则滚动会明显卡顿
    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let md: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let ymdSlash: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    static func listTime(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return hhmm.string(from: d) }
        if cal.component(.year, from: d) == cal.component(.year, from: Date()) {
            return md.string(from: d)
        }
        return ymdSlash.string(from: d)
    }
}
