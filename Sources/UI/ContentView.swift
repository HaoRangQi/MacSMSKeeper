import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var systemScheme

    private var effectiveScheme: ColorScheme {
        state.appearance.colorScheme ?? systemScheme
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 212, ideal: 226, max: 280)
            } detail: {
                detailArea
            }
            .background(Color.clear)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AppearanceControls()
                }
            }
        }
        .containerBackground(for: .window) {
            AppBackground(opacity: state.backgroundOpacity)
        }
        .preferredColorScheme(state.appearance.colorScheme)
        .environment(\.colorScheme, effectiveScheme)
        .background(WindowConfigurator(appearance: state.appearance))
        .onChange(of: state.sidebar) { _, newValue in
            state.sidebarChanged(newValue)
        }
        .overlay { LoadOverlayContainer(status: state.loadStatus) }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Text(toast)
                    .font(.system(size: Typo.s(12.5)))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.tint(.black.opacity(0.45)), in: .capsule)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { state.toast = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
        .alert(L.t("确认删除 %d 条短信？", state.pendingDeleteIDs?.count ?? 0),
               isPresented: Binding(
                get: { state.pendingDeleteIDs != nil },
                set: { if !$0 { state.pendingDeleteIDs = nil } }
               )) {
            Button(L.t("取消"), role: .cancel) { state.pendingDeleteIDs = nil }
            Button(L.t("删除"), role: .destructive) {
                let ids = state.pendingDeleteIDs ?? []
                state.pendingDeleteIDs = nil
                Task { _ = await state.delete(ids: ids) }
            }
        } message: {
            Text(L.t("删除前会自动备份整个数据库，被删记录可在「回收站」整批还原。\n若「信息」App 正在运行，会先请求它退出。"))
        }
        .alert(L.t("出错了"), isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button(L.t("好")) { state.errorMessage = nil }
            if !state.realPermissionOK {
                Button(L.t("打开完全磁盘访问设置")) {
                    state.openFullDiskAccessSettings()
                    state.errorMessage = nil
                }
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private func isListMode(_ item: SidebarItem?) -> Bool {
        switch item {
        case .dashboard, .cleanup, .trash, .settings, .none: return false
        default: return true
        }
    }

    @ViewBuilder
    private var detailArea: some View {
        if isListMode(state.sidebar) {
            HSplitView {
                MessageListView()
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                DetailPane()
                    .frame(minWidth: 300, idealWidth: 370, maxWidth: 620,
                           maxHeight: .infinity)
            }
            .background(Color.clear)
        } else {
            pageColumn
        }
    }

    @ViewBuilder
    private var pageColumn: some View {
        switch state.sidebar {
        case .cleanup:
            CleanupView()
        case .trash:
            TrashView()
        case .settings:
            SettingsView()
        default:
            DashboardView()
        }
    }
}

// MARK: - 侧边栏（自绘行，保证点击一定生效）

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                    groupLabel(L.t("总览"))
                    row(.dashboard)
                    row(.all, count: state.stats.total)

                    groupLabel(L.t("按类型"))
                    ForEach([Category.code, .express, .bank, .promo, .notice, .person]) { c in
                        row(.category(c), tint: c.color,
                            count: state.stats.byCategory[c] ?? 0)
                    }

                    groupLabel(L.t("清理"))
                    row(.cleanup)
                    row(.trash, count: state.trash.isEmpty ? nil : state.trash.count)

                    groupLabel(L.t("其它"))
                    row(.settings)
                }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Spacer(minLength: 0)
            DataSourceBadge()
        }
        .background(.clear)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Typo.s(10.5), weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    private func row(_ item: SidebarItem, tint: Color? = nil,
                     count: Int? = nil) -> some View {
        SidebarRow(
            title: item.title,
            symbol: item.symbol,
            tint: tint ?? .secondary,
            count: count,
            selected: state.sidebar == item
        ) {
            state.selectSidebar(item)
        }
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    @StateObject private var hover = HoverBox()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: Typo.s(12)))
                    .foregroundStyle(selected ? Color.white : tint)
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(.system(size: Typo.s(12.5), weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let c = count {
                    Text("\(c)")
                        .font(.system(size: Typo.s(10.5)).monospacedDigit())
                        .foregroundStyle(selected ? Color.white.opacity(0.85)
                                                  : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover.on = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var background: Color {
        if selected { return .accentColor }
        return hover.on ? Color.primary.opacity(0.07) : .clear
    }
}

final class HoverBox: ObservableObject {
    @Published var on = false
}

struct DataSourceBadge: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isDemo ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(state.isDemo ? L.t("演示数据") : L.t("系统短信库"))
                .font(.system(size: Typo.s(11)))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(state.all.count)")
                .font(.system(size: Typo.s(11)).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

// MARK: - 详情栏

struct DetailPane: View {
    @EnvironmentObject var state: AppState

    private var selected: SMSMessage? {
        guard state.selection.count == 1, let id = state.selection.first else { return nil }
        return state.all.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let msg = selected {
                MessageDetailView(message: msg)
            } else if state.selection.count > 1 {
                MultiSelectionPane(count: state.selection.count)
            } else {
                EmptyPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct EmptyPane: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: Typo.s(34), weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.t("选择一条短信查看详情"))
                .font(.system(size: Typo.s(12.5)))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MultiSelectionPane: View {
    @EnvironmentObject var state: AppState
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: Typo.s(34), weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.t("已选择 %d 条短信", count))
                .font(.system(size: Typo.s(13), weight: .medium))
            HStack(spacing: 10) {
                Menu {
                    ForEach(ExportFormat.allCases) { f in
                        Button {
                            let target = state.filtered.filter {
                                state.selection.contains($0.id)
                            }
                            _ = state.export(target, format: f)
                        } label: {
                            Label(f.title, systemImage: f.symbol)
                        }
                    }
                } label: {
                    Label(L.t("导出所选"), systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.large)

                Button(role: .destructive) {
                    state.requestDelete(state.selection)
                } label: {
                    Label(L.t("删除所选"), systemImage: "trash")
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 交互辅助

struct PointingCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    /// 悬停时切换成手型光标，明确「这里可以点」
    func pointingCursor() -> some View { modifier(PointingCursor()) }
}

// MARK: - 载入遮罩

/// 单独观察 LoadStatus，进度刷新只重绘这一层
struct LoadOverlayContainer: View {
    @ObservedObject var status: LoadStatus

    var body: some View {
        if status.isLoading {
            LoadOverlay(phase: status.phase, progress: status.progress)
        }
    }
}

struct LoadOverlay: View {
    let phase: String
    let progress: Double

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
            VStack(spacing: 12) {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 280)
                HStack(spacing: 8) {
                    Text(phase.isEmpty ? L.t("正在载入…") : phase)
                        .font(.system(size: Typo.s(12)))
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: Typo.s(12)).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }
}
