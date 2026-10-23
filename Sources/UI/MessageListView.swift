import SwiftUI
import AppKit

struct MessageListView: View {
    @EnvironmentObject var state: AppState

    private var visibleMessages: [SMSMessage] {
        Array(state.filtered.prefix(state.listLimit))
    }

    private var hasMore: Bool { state.filtered.count > state.listLimit }


    var body: some View {
        VStack(spacing: 0) {
            FilterBar()
            messageList
            if !state.selection.isEmpty {
                SelectionBar()
            }
        }
        .navigationTitle("")
        .toolbar { toolbarContent }
        .searchable(text: $state.query, placement: .toolbar,
                    prompt: L.t("搜索内容、号码，支持 \"短语\" -排除 /正则/"))
        .onChange(of: state.query) { _, _ in state.refilter() }
        .onSubmit(of: .search) { state.refilter() }
    }

    private var messageList: some View {
        ZStack {
            List {
                ForEach(visibleMessages) { msg in
                    MessageRow(message: msg, query: state.query,
                               isSelected: state.selection.contains(msg.id),
                               onToggle: { state.toggleSelection(msg.id) })
                        .listRowInsets(EdgeInsets(top: 0, leading: 6,
                                                  bottom: 0, trailing: 8))
                        .listRowBackground(
                            state.selection.contains(msg.id)
                                ? Color.accentColor.opacity(0.13)
                                : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.handleRowClick(msg.id, in: state.filtered)
                        }
                        .pointingCursor()
                        .contextMenu {
                            Button(L.t("删除这条短信…"), role: .destructive) {
                                state.requestDelete([msg.id])
                            }
                            if let code = msg.code {
                                Button(L.t("复制验证码 %@", code)) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                    state.toast = L.t("验证码已复制")
                                }
                            }
                            Button("复制全文") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(msg.text, forType: .string)
                                state.toast = L.t("已复制")
                            }
                            Divider()
                            Button("标记为已读") { state.markRead([msg.id]) }
                            Menu("导出为") {
                                ForEach(ExportFormat.allCases) { f in
                                    Button(f.title) {
                                        let target = state.selection.isEmpty
                                            ? [msg]
                                            : state.filtered.filter {
                                                state.selection.contains($0.id)
                                            }
                                        _ = state.export(target, format: f)
                                    }
                                }
                            }
                        }
                }

                if hasMore {
                    HStack {
                        Spacer()
                        Button(L.t("显示更多（还有 %d 条）", state.filtered.count - state.listLimit)) {
                            state.listLimit += 300
                        }
                        .buttonStyle(.link)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)

            if state.filtered.isEmpty && !state.loadStatus.isLoading {
                EmptyListView()
            }
        }
    }

    /// 工具栏上显示的时间范围文案。自定义时显示具体日期区间
    private var rangeLabel: String {
        switch state.range {
        case .all: return L.t("时间")
        case .custom:
            return "\(Fmt.short.string(from: state.customFrom)) – \(Fmt.short.string(from: state.customTo))"
        default: return state.range.label
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // 时间范围。注意：DatePicker 不能放进 Menu —— macOS 会把菜单里的
            // 日期选择器渲染成禁用状态（点了没反应）。所以"自定义…"走 popover。
            Menu {
                ForEach(TimeRange.allCases) { r in
                    if r == .custom {
                        Divider()
                        Button {
                            state.range = .custom
                            state.showCustomRange = true
                        } label: {
                            if state.range == .custom {
                                Label(r.label, systemImage: "checkmark")
                            } else {
                                Text(r.label)
                            }
                        }
                    } else {
                        Button {
                            state.range = r
                            state.refilter()
                        } label: {
                            if state.range == r {
                                Label(r.label, systemImage: "checkmark")
                            } else {
                                Text(r.label)
                            }
                        }
                    }
                }
            } label: {
                Label(rangeLabel, systemImage: "calendar")
            }
            .popover(isPresented: $state.showCustomRange) {
                CustomRangePanel()
            }

            Menu {
                Picker(L.t("排序"), selection: $state.sort) {
                    ForEach(SortMode.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(L.t("排序"), systemImage: "arrow.up.arrow.down")
            }
            .onChange(of: state.sort) { _, _ in state.refilter() }

            Toggle(isOn: $state.unreadOnly) {
                Label(L.t("仅未读"), systemImage: "circle.fill")
            }
            .toggleStyle(.button)
            .onChange(of: state.unreadOnly) { _, _ in state.refilter() }

            Menu {
                ForEach(ExportFormat.allCases) { f in
                    Button {
                        _ = state.export(state.exportTargets, format: f)
                    } label: {
                        Label(f.title, systemImage: f.symbol)
                    }
                }
            } label: {
                Label(L.t("导出"), systemImage: "square.and.arrow.up")
            }
            .help(L.t("导出当前筛选结果或所选短信 (⌘E)"))

            Button {
                Task { await state.load() }
            } label: {
                Label(L.t("刷新"), systemImage: "arrow.clockwise")
            }
            .help(L.t("重新读取数据库 (⌘R)"))
        }
    }
}

// MARK: - 筛选条

struct FilterBar: View {
    @EnvironmentObject var state: AppState

    private var hasFilter: Bool {
        !state.query.isEmpty || !state.categories.isEmpty || state.range != .all
            || state.unreadOnly || state.withAttachment
    }

    private var allSelected: Bool {
        !state.filtered.isEmpty && state.selection.count >= state.filtered.count
    }

    private var someSelected: Bool {
        !state.selection.isEmpty && !allSelected
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if allSelected {
                    state.selection.removeAll()
                } else {
                    state.selection = Set(state.filtered.map(\.id))
                }
            } label: {
                CheckCircle(state: allSelected ? .on : (someSelected ? .mixed : .off))
            }
            .buttonStyle(.plain)
            .help(allSelected ? L.t("取消全选") : L.t("全选 %d 条", state.filtered.count))

            Text("\(state.filtered.count)")
                .font(.system(size: Typo.s(12), weight: .semibold).monospacedDigit())
            Text(L.t("条结果"))
                .font(.system(size: Typo.s(12)))
                .foregroundStyle(.secondary)

            if state.filtered.count > state.listLimit {
                Text(L.t("· 已显示 %d", state.listLimit))
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.tertiary)
            }

            if !state.selection.isEmpty {
                Text(L.t("· 已选 %d", state.selection.count))
                    .font(.system(size: Typo.s(12)))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(isOn: $state.withAttachment) {
                Label(L.t("含附件"), systemImage: "paperclip")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .onChange(of: state.withAttachment) { _, _ in state.refilter() }

            if hasFilter {
                Button {
                    state.resetFilters()
                } label: {
                    Label(L.t("清除筛选"), systemImage: "xmark.circle")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - 行

struct MessageRow: View {
    let message: SMSMessage
    let query: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Button(action: onToggle) {
                CheckCircle(state: isSelected ? .on : .off)
            }
            .buttonStyle(.plain)
            .help(isSelected ? L.t("取消选择") : L.t("选择这条"))

            Circle()
                .fill(message.category.color)
                .frame(width: 8, height: 8)
                .help(message.category.label)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.sender.isEmpty ? L.t("未知") : message.sender)
                        .font(.system(size: Typo.s(12),
                                      weight: message.isUnread ? .semibold : .regular))
                        .lineLimit(1)

                    if message.service == "iMessage" {
                        Text("iM")
                            .font(.system(size: Typo.s(9), weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.secondary)
                    }
                    if message.attachments > 0 {
                        Image(systemName: "paperclip")
                            .font(.system(size: Typo.s(9)))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 4)

                    Text(Fmt.listTime(message.date))
                        .font(.system(size: Typo.s(11)).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(highlighted(message.snippet, query: query))
                    .font(.system(size: Typo.s(12)))
                    .foregroundStyle(message.isUnread ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// 把搜索命中词高亮成黄底
func highlighted(_ text: String, query: String) -> AttributedString {
    var attr = AttributedString(text)
    let terms = query
        .replacingOccurrences(of: "\"", with: " ")
        .split(whereSeparator: { $0 == " " })
        .map(String.init)
        .filter { $0.count > 1 && !$0.hasPrefix("-") && !$0.hasPrefix("/") }
        .prefix(6)
    guard !terms.isEmpty else { return attr }

    for term in terms {
        var searchStart = attr.startIndex
        var guardCount = 0
        while searchStart < attr.endIndex, guardCount < 200 {
            guardCount += 1
            guard let r = attr[searchStart...].range(of: term,
                                                     options: [.caseInsensitive]) else { break }
            attr[r].backgroundColor = Color.yellow.opacity(0.38)
            searchStart = r.upperBound
        }
    }
    return attr
}

// MARK: - 底部选择条

struct SelectionBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Text(L.t("已选 %d 条", state.selection.count))
                .font(.system(size: Typo.s(12), weight: .medium))

            Spacer()

            Button {
                state.markRead(state.selection)
            } label: {
                Label(L.t("标记已读"), systemImage: "envelope.open")
            }
            .controlSize(.small)

            Button {
                state.selection = Set(state.filtered.map(\.id))
            } label: {
                Text(L.t("全选结果"))
            }
            .controlSize(.small)

            Menu {
                ForEach(ExportFormat.allCases) { f in
                    Button {
                        _ = state.export(state.exportTargets, format: f)
                    } label: {
                        Label(f.title, systemImage: f.symbol)
                    }
                }
            } label: {
                Label(L.t("导出"), systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)

            Button(role: .destructive) {
                state.requestDelete(state.selection)
            } label: {
                Label(L.t("删除"), systemImage: "trash")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(.accentColor.opacity(0.12)),
                     in: .rect(cornerRadius: 13))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

// MARK: - 空状态

struct EmptyListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Typo.s(30), weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.t("没有匹配的短信"))
                .font(.system(size: Typo.s(13), weight: .medium))
            Text(L.t("换个关键词，或清除筛选条件试试"))
                .font(.system(size: Typo.s(12)))
                .foregroundStyle(.secondary)
            if !state.query.isEmpty || !state.categories.isEmpty {
                Button(L.t("清除筛选")) { state.resetFilters() }
                    .controlSize(.small)
            }
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}


// MARK: - 复选框

enum CheckState { case off, on, mixed }

struct CheckCircle: View {
    let state: CheckState

    var body: some View {
        ZStack {
            Circle()
                .fill(state == .off ? Color.clear : Color.accentColor)
                .overlay(
                    Circle().strokeBorder(
                        state == .off ? Color.secondary.opacity(0.45) : Color.accentColor,
                        lineWidth: 1.3)
                )
                .frame(width: 15, height: 15)

            switch state {
            case .on:
                Image(systemName: "checkmark")
                    .font(.system(size: Typo.s(8), weight: .bold))
                    .foregroundStyle(.white)
            case .mixed:
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 7, height: 1.8)
            case .off:
                EmptyView()
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Circle())
    }
}

// MARK: - 自定义时间范围面板

/// 独立 popover，不用 Menu —— 菜单里的 DatePicker 会被系统渲染成禁用状态。
/// 日期改动即实时筛选（内存操作，9 千条实测毫秒级）。
struct CustomRangePanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var invalid: Bool { state.customFrom > state.customTo }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("自定义时间范围"))
                .font(.system(size: Typo.s(13), weight: .semibold))

            DatePicker(L.t("从"), selection: $state.customFrom, displayedComponents: .date)
            DatePicker(L.t("到"), selection: $state.customTo, displayedComponents: .date)

            if invalid {
                Label(L.t("开始日期晚于结束日期"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button(L.t("最近一年")) {
                    state.range = .d365
                    dismiss()
                }
                .controlSize(.small)

                Spacer()

                Button(L.t("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onChange(of: state.customFrom) { _, _ in state.refilter() }
        .onChange(of: state.customTo) { _, _ in state.refilter() }
    }
}
