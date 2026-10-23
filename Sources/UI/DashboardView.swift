import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    private var stats: Stats { state.stats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statGrid
                dailyChart
                HStack(alignment: .top, spacing: 14) {
                    categoryBreakdown
                    topSenders
                }
                if state.isDemo {
                    demoNotice
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle(L.t("概览"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("概览"))
                .font(.system(size: Typo.s(22), weight: .bold))
            Text(subtitle)
                .font(.system(size: Typo.s(12)))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        guard let first = stats.firstDate, let last = stats.lastDate else {
            return L.t("暂无数据")
        }
        return L.t("%@ 至 %@ · 共 %d 条短信", Fmt.short.string(from: first), Fmt.short.string(from: last), stats.total)
    }

    private var statGrid: some View {
        HStack(spacing: 12) {
            StatTile(title: L.t("短信总量"), value: "\(stats.total)",
                     subtitle: L.t("来自 %d 个发件人", stats.topSenders.count),
                     color: .accentColor, prominent: true)
            StatTile(title: L.t("验证码"), value: "\(stats.byCategory[.code] ?? 0)",
                     subtitle: L.t("%d 条可提取验证码", stats.withCode),
                     color: Category.code.color)
            StatTile(title: L.t("快递物流"), value: "\(stats.byCategory[.express] ?? 0)",
                     subtitle: L.t("签收后无保留价值"),
                     color: Category.express.color)
            StatTile(title: L.t("建议清理"),
                     value: "\((stats.byCategory[.code] ?? 0) + (stats.byCategory[.promo] ?? 0))",
                     subtitle: L.t("验证码 + 营销推广"),
                     color: .red)
        }
    }

    private var dailyChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L.t("每日短信量"))
                        .font(.system(size: Typo.s(13), weight: .semibold))
                    Spacer()
                    Text(L.t("近 60 天"))
                        .font(.system(size: Typo.s(11)))
                        .foregroundStyle(.tertiary)
                }
                DailyBars(daily: stats.daily)
                    .frame(height: 130)
            }
        }
    }

    private var categoryBreakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("类型分布"))
                    .font(.system(size: Typo.s(13), weight: .semibold))
                let total = max(stats.total, 1)
                ForEach([Category.code, .express, .bank, .promo, .notice, .person, .other]) { c in
                    let n = stats.byCategory[c] ?? 0
                    HStack(spacing: 8) {
                        Image(systemName: c.symbol)
                            .font(.system(size: Typo.s(10)))
                            .foregroundStyle(c.color)
                            .frame(width: 14)
                        Text(c.label)
                            .font(.system(size: Typo.s(11.5)))
                            .frame(width: 58, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.1))
                                Capsule()
                                    .fill(c.color.opacity(0.85))
                                    .frame(width: max(2, geo.size.width * CGFloat(n) / CGFloat(total)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(n)")
                            .font(.system(size: Typo.s(11)).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(height: 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topSenders: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("最吵的发件人"))
                    .font(.system(size: Typo.s(13), weight: .semibold))
                if stats.topSenders.isEmpty {
                    Text(L.t("暂无数据"))
                        .font(.system(size: Typo.s(12)))
                        .foregroundStyle(.tertiary)
                } else {
                    let maxCount = max(stats.topSenders.first?.count ?? 1, 1)
                    ForEach(Array(stats.topSenders.prefix(7).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Text(item.sender)
                                .font(.system(size: Typo.s(11.5)))
                                .lineLimit(1)
                                .frame(width: 108, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.1))
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.75))
                                        .frame(width: max(2, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                                }
                            }
                            .frame(height: 6)
                            Text("\(item.count)")
                                .font(.system(size: Typo.s(11)).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .frame(height: 16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var demoNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.orange)
            Text(L.t("当前显示的是演示数据。要管理真实短信，请在「设置与诊断」中授予完全磁盘访问权限后连接系统短信库。"))
                .font(.system(size: Typo.s(11.5)))
                .foregroundStyle(.secondary)
            Spacer()
            Button(L.t("去设置")) {
                state.selectSidebar(.settings)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - 组件

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: Typo.s(11.5)))
                .foregroundStyle(prominent ? Color.white.opacity(0.75) : Color.secondary)
            Text(value)
                .font(.system(size: Typo.s(26), weight: .semibold).monospacedDigit())
                .foregroundStyle(prominent ? Color.white : Color.primary)
            Text(subtitle)
                .font(.system(size: Typo.s(10.5)))
                .foregroundStyle(prominent ? Color.white.opacity(0.65) : Color.secondary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TileSurface(prominent: prominent))
    }
}

struct TileSurface: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.background(
                LinearGradient(colors: [Color(hex: 0x5B54E8), Color(hex: 0x3F38B8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12)
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
}

/// 近 60 天柱状图
struct DailyBars: View {
    let daily: [(day: Date, count: Int)]

    private var series: [(Date, Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let map = Dictionary(daily.map { (cal.startOfDay(for: $0.day), $0.count) },
                             uniquingKeysWith: +)
        return (0..<60).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (d, map[d] ?? 0)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let items = series
            let maxCount = max(items.map(\.1).max() ?? 1, 1)
            let barW = geo.size.width / CGFloat(max(items.count, 1))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(item.1 == 0
                                  ? AnyShapeStyle(Color.secondary.opacity(0.12))
                                  : AnyShapeStyle(LinearGradient(
                                        colors: [Color(hex: 0x6D6AF0), Color(hex: 0xA5B4FC)],
                                        startPoint: .top, endPoint: .bottom)))
                            .frame(width: max(barW - 2, 1.5),
                                   height: max(CGFloat(item.1) / CGFloat(maxCount) * (geo.size.height - 14), 1.5))
                    }
                    .frame(width: barW)
                    .help("\(Fmt.short.string(from: item.0)) · \(item.1) 条")
                }
            }
        }
    }
}
