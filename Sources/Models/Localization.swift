import Foundation

// MARK: - 语言

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese, english

    var id: String { rawValue }

    /// 语言名用自身语言显示，不翻译
    var label: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

// MARK: - 本地化

/// 以中文原文为 key：缺翻译时自动回落中文，不会出现空白文案。
enum L {

    /// 由 AppState 在语言变化时写入；用非隔离静态量，
    /// 这样 Category.label 这类非 MainActor 的计算属性也能安全读取。
    nonisolated(unsafe) static var code: String = "zh"

    static func resolve(_ language: AppLanguage) -> String {
        switch language {
        case .chinese: return "zh"
        case .english: return "en"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
            return preferred.lowercased().hasPrefix("en") ? "en" : "zh"
        }
    }

    static func t(_ zh: String) -> String {
        guard code == "en" else { return zh }
        return english[zh] ?? zh
    }

    static func t(_ zh: String, _ args: CVarArg...) -> String {
        let template = code == "en" ? (english[zh] ?? zh) : zh
        return String(format: template, arguments: args)
    }

    // MARK: 英文词条

    private static let english: [String: String] = [
        // 导航
        "概览": "Overview",
        "全部短信": "All Messages",
        "验证码": "Codes",
        "快递物流": "Deliveries",
        "银行账单": "Banking",
        "营销推广": "Promotions",
        "通知服务": "Notifications",
        "个人对话": "Personal",
        "其他": "Other",
        "智能清理": "Cleanup",
        "回收站": "Trash",
        "设置与诊断": "Settings",
        "总览": "OVERVIEW",
        "按类型": "BY CATEGORY",
        "清理": "CLEANUP",
        "其它": "OTHER",
        "演示数据": "Demo data",
        "系统短信库": "System messages",

        // 通用按钮
        "取消": "Cancel",
        "删除": "Delete",
        "还原": "Restore",
        "彻底删除": "Delete Permanently",
        "关闭": "Close",
        "好": "OK",
        "预览": "Preview",
        "执行删除": "Delete",
        "删除中…": "Deleting…",
        "刷新": "Refresh",
        "导出": "Export",
        "导出为": "Export As",
        "复制": "Copy",
        "复制全文": "Copy Text",
        "标记已读": "Mark as Read",
        "标记为已读": "Mark as Read",
        "全选结果": "Select All",
        "删除所选": "Delete Selected",
        "导出所选": "Export Selected",
        "去设置": "Open Settings",
        "在访达中显示": "Show in Finder",
        "使用演示数据": "Use Demo Data",
        "连接系统短信库": "Connect to Messages",
        "打开系统设置": "Open System Settings",
        "打开完全磁盘访问设置": "Open Full Disk Access Settings",
        "连接中…": "Connecting…",

        // 时间与排序
        "全部时间": "All Time",
        "今天": "Today",
        "近 7 天": "Last 7 Days",
        "近 30 天": "Last 30 Days",
        "近 90 天": "Last 90 Days",
        "近一年": "Last Year",
        "自定义…": "Custom…",
        "最新优先": "Newest First",
        "最早优先": "Oldest First",
        "内容最长": "Longest First",
        "按发件人": "By Sender",
        "时间": "Time",
        "排序": "Sort",
        "仅未读": "Unread",
        "含附件": "Attachments",

        // 列表
        "条结果": "results",
        "清除筛选": "Clear Filters",
        "显示更多（还有 %d 条）": "Show more (%d left)",
        "没有匹配的短信": "No matching messages",
        "换个关键词，或清除筛选条件试试": "Try another keyword, or clear the filters",
        "选择这条": "Select",
        "取消选择": "Deselect",
        "全选 %d 条": "Select all %d",
        "取消全选": "Deselect all",
        "已选 %d 条": "%d selected",
        "删除这条短信…": "Delete This Message…",
        "复制验证码 %@": "Copy Code %@",
        "验证码已复制": "Code copied",
        "已复制": "Copied",
        "已复制全文": "Text copied",
        // 详情
        "未知发件人": "Unknown Sender",
        "未知": "Unknown",
        "通道": "Service",
        "状态": "Status",
        "附件": "Attachments",
        "已读": "Read",
        "未读": "Unread",
        "由我发出": "Sent by me",
        "提取到的验证码": "Extracted code",
        "分类依据": "Why this category",
        "删除这条": "Delete",
        "置信度 %d%%": "%d%% confidence",
        "%d 个": "%d",
        "（无正文）": "(no text)",
        "选择一条短信查看详情": "Select a message to see details",
        "已选择 %d 条短信": "%d messages selected",

        // 概览
        "%@ 至 %@ · 共 %d 条短信": "%@ – %@ · %d messages",
        "暂无数据": "No data",
        "短信总量": "Total",
        "来自 %d 个发件人": "from %d senders",
        "%d 条可提取验证码": "%d with codes",
        "签收后无保留价值": "No value after delivery",
        "建议清理": "To Clean",
        "验证码 + 营销推广": "Codes + promotions",
        "每日短信量": "Daily Volume",
        "近 60 天": "Last 60 days",
        "类型分布": "By Category",
        "最吵的发件人": "Top Senders",
        "当前显示的是演示数据。要管理真实短信，请在「设置与诊断」中授予完全磁盘访问权限后连接系统短信库。":
            "Showing demo data. To manage real messages, grant Full Disk Access in Settings, then connect to Messages.",

        // 清理规则
        "重复验证码去重": "Remove Duplicate Codes",
        "同一发件人同一天的多条验证码，只保留最新一条。":
            "Keep only the newest code per sender per day.",
        "过期验证码": "Expired Codes",
        "验证码有效期只有几分钟，超过设定天数的没有保留价值。":
            "Codes expire in minutes; anything older has no value.",
        "已读验证码": "Read Codes",
        "只清理已读验证码，未读的保留，避免误删还没用的码。":
            "Only delete codes you have already read.",
        "全部验证码": "All Codes",
        "一次性清空所有验证码短信，建议先预览。":
            "Delete every verification code. Preview first.",
        "过期快递通知": "Old Delivery Notices",
        "超过设定天数的快递、驿站、取件码通知。":
            "Delivery and pickup notices older than the given days.",
        "全部快递通知": "All Delivery Notices",
        "清空所有快递物流类短信。": "Delete every delivery message.",
        "营销推广短信": "Promotional Messages",
        "促销、优惠券、退订类短信，通常占比最大。":
            "Promotions and coupons — usually the largest group.",
        "一键清理低价值": "Clear Low-Value Messages",
        "营销推广 + 空消息 + 重复验证码，一次清掉最没用的部分。":
            "Promotions, empty messages and duplicate codes in one go.",
        "旧银行账单": "Old Bank Notices",
        "超过设定天数的银行消费、还款提醒。":
            "Bank and repayment notices older than the given days.",
        "未读营销与通知": "Unread Promotions",
        "从没点开过的推广和通知短信。": "Promotions and notices you never opened.",
        "无正文消息": "Messages Without Text",
        "只有附件或表情、没有文字的消息。": "Attachment or emoji only.",
        "按时间批量清理": "Bulk Delete by Age",
        "删除设定天数之前的全部短信，可保留指定类型。":
            "Delete everything older than the given days, keeping chosen types.",
        "保留": "Keep",
        "命中 %d 条": "%d matched",
        "执行「%@」？": "Run \"%@\"?",
        "将删除 %d 条短信。删除前会自动备份整库，可在回收站还原。":
            "This will delete %d messages. A full backup is made first and can be restored from Trash.",
        "没有命中任何短信": "Nothing matched",
        "仅显示前 80 条，实际将删除 %d 条": "Showing first 80 of %d",
        "删除 %d 条": "Delete %d",
        "确认删除？": "Delete?",
        "将永久删除 %d 条短信，可从回收站还原。":
            "%d messages will be deleted. You can restore them from Trash.",
        "先预览命中数量，确认后再执行。每次删除都会自动整库备份，并可在回收站还原。":
            "Preview first, then confirm. Every delete is backed up and can be restored.",

        // 回收站
        "每次批量删除都会把原始记录完整存档，可整批还原到系统数据库。":
            "Every deletion is archived and can be restored to the database.",
        "回收站是空的": "Trash is empty",
        "执行删除后，这里会保留可还原的记录":
            "Deleted messages will appear here and can be restored",
        "手动删除": "Manual",
        "规则清理": "Rule",
        "演示": "Demo",
        "还原这批短信？": "Restore this batch?",
        "将把 %d 条短信写回系统数据库。还原前同样会先备份。":
            "%d messages will be written back. A backup is made first.",
        "彻底删除这批记录？": "Delete this archive?",
        "仅删除回收站里的存档记录，不影响短信本身。此操作不可撤销。":
            "This only removes the archive, not the messages. It cannot be undone.",

        // 设置
        "读取系统短信库需要「完全磁盘访问权限」，数据全程留在本机。":
            "Reading Messages requires Full Disk Access. All data stays on this Mac.",
        "磁盘访问权限": "Disk Access",
        "已授权": "Granted",
        "未授权": "Not granted",
        "演示模式": "Demo mode",
        "权限状态": "Permission",
        "已获得完全磁盘访问权限": "Full Disk Access granted",
        "「信息」App": "Messages app",
        "正在运行（删除前会自动请求退出）": "Running (will be asked to quit before deleting)",
        "已退出": "Not running",
        "如何授权": "How to grant access",
        "点下方按钮打开「系统设置 › 隐私与安全性 › 完全磁盘访问权限」":
            "Click below to open System Settings › Privacy & Security › Full Disk Access",
        "点 + ，把「短信管家.app」加入列表": "Click + and add SMS Keeper.app",
        "打开右侧开关，然后完全退出本 App 并重新打开":
            "Turn on the switch, then quit and reopen this app",
        "回到这里点「连接系统短信库」": "Come back and click Connect to Messages",
        "数据源": "Data Source",
        "演示数据（不会影响真实短信）": "Demo data (never touches real messages)",
        "%d 条": "%d messages",
        "数据库备份": "Backups",
        "保留最近 20 份": "Last 20 kept",
        "暂无备份。每次删除或还原前会自动生成一份。":
            "No backups yet. One is created before each delete or restore.",
        "备份目录：%@": "Backup folder: %@",
        "关于": "About",
        "短信管家 1.0 · 原生 SwiftUI 版本": "SMS Keeper 1.0 · native SwiftUI",
        "所有数据只在本机处理，不联网、不上传。软件仅监听本地数据库，不会修改未选中的短信。":
            "Everything is processed locally. No network, no uploads.",

        // 外观
        "跟随系统": "System",
        "浅色": "Light",
        "深色": "Dark",
        "背景不透明度": "Background Opacity",
        "切换主题": "Switch theme",
        "外观": "Appearance",
        "语言": "Language",
        "界面语言": "Interface Language",
        "更改后立即生效，无需重启。": "Takes effect immediately.",

        // 弹窗
        "确认删除 %d 条短信？": "Delete %d messages?",
        "删除前会自动备份整个数据库，被删记录可在「回收站」整批还原。\n若「信息」App 正在运行，会先请求它退出。":
            "A full backup is made first, and deleted messages can be restored from Trash.\nIf Messages is running, it will be asked to quit.",
        "出错了": "Something went wrong",
        "正在载入…": "Loading…",
        "正在读取数据库…": "Reading database…",
        "正在分析短信类型…": "Analyzing messages…",
        "正在整理索引…": "Building index…",
        "没有可导出的短信": "Nothing to export",
        "已导出 %d 条到 %@": "Exported %d to %@",
        "导出失败：%@": "Export failed: %@",

        // 导出文件
        "短信导出": "SMS Export",
        "导出时间：%@": "Exported: %@",
        "共 %d 条": "%d messages",
        "条数：%d": "Messages: %d",
        "分类分布：%@": "Categories: %@",
        "内容": "Content",
        "发件人": "Sender",
        "分类": "Category",
        "验证码：%@": "Code: %@",
        "从": "From",
        "到": "To",
        "主题": "Theme",
        "导出当前筛选结果或所选短信 (⌘E)": "Export results or selection (⌘E)",
        "重新读取数据库 (⌘R)": "Reload database (⌘R)",
        "· 已显示 %d": "· showing %d",
        "· 已选 %d": "· %d selected",
        "天前的": "days old",
        "删除前会自动备份整库，可在回收站整批还原。": "A full backup is made first; restore from Trash.",
        "纯文本 (.txt)": "Plain Text (.txt)",
        "CSV 表格 (.csv)": "CSV (.csv)",
        "纯文本": "Plain Text",
        "时间,发件人,分类,验证码,内容": "Time,Sender,Category,Code,Content",
        "短信": "Messages",
        "刷新数据": "Refresh Data",
        "删除所选…": "Delete Selected…",
        "导出当前结果…": "Export Results…",
        "全选筛选结果": "Select All Results",
        "搜索内容、号码，支持 \"短语\" -排除 /正则/": "Search text or number — \"phrase\", -exclude, /regex/",
        "已删除 %d 条，备份 %@": "Deleted %d · backup %@",
        "已还原 %d 条短信": "Restored %d messages",
        "导出短信": "Export Messages",
        "权限正常": "Access granted",
        "系统拒绝访问 ~/Library/Messages，需要「完全磁盘访问权限」":
            "Access to ~/Library/Messages denied — Full Disk Access required",
        "找不到 ~/Library/Messages/chat.db，请确认这台 Mac 已启用「信息」":
            "~/Library/Messages/chat.db not found. Make sure Messages is set up on this Mac.",
        "找不到 ~/Library/Messages/chat.db": "~/Library/Messages/chat.db not found",
        "读取失败：%@": "Read failed: %@",
        "诊断日志": "Diagnostics Log",
        "出问题时打开此开关，重现一次操作，再把日志文件发给开发者。": "Turn this on when something goes wrong, reproduce the issue, then send the log file.",
        "只记录操作步骤、错误信息和条数，绝不记录短信内容、号码或验证码。": "Records steps, errors and counts only — never message content, numbers or codes.",
        "清空日志": "Clear Log",
        "日志已清空": "Log cleared",
        "诊断日志已开启，路径：~/Library/Logs/SMSKeeper": "Diagnostics log on · ~/Library/Logs/SMSKeeper",
        "诊断日志已关闭": "Diagnostics log off",
        "这是「信息」App 的私有数据库函数缺失，通常是系统版本变化导致的。数据未受影响。请到「设置与诊断 › 诊断日志」打开开关，重现一次操作，把日志文件发给开发者即可定位。": "A private Messages database function is missing, usually after a macOS update. Your data is unaffected. Enable Diagnostics Log in Settings, reproduce the issue, and send the log file to the developer.",
        "数据库被占用。请确认「信息」App 已完全退出后重试。": "Database is locked. Make sure the Messages app has fully quit, then retry.",
        "数据库只读。请检查「设置与诊断」中的权限状态。": "Database is read-only. Check the permission status in Settings & Diagnostics.",
        "自定义时间范围": "Custom Range",
        "开始日期晚于结束日期": "Start date is after end date",
        "完成": "Done",
        "最近一年": "Last Year",
        "已删除 %d 条 · 库内剩余 %d 条": "Deleted %d · %d remaining in database",
        "删除后校验失败：预期剩余 %d 条，实际 %d 条。可能有其它程序（如 iCloud 同步）把数据写回了。": "Post-delete check failed: expected %d remaining, found %d. Another process (e.g. iCloud sync) may have written the data back.",
    ]
}
