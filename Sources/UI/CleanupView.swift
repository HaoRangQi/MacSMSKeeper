import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("智能清理"))
                        .font(.system(size: Typo.s(22), weight: .bold))
                    Text(L.t("先预览命中数量，确认后再执行。每次删除都会自动整库备份，并可在回收站还原。"))
                        .font(.system(size: Typo.s(12)))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 292), spacing: 12)],
                          spacing: 12) {
                    ForEach(CleanupRule.allCases) { rule in
                        RuleCard(rule: rule)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle(L.t("智能清理"))
    }
}

// MARK: - 卡片模型

final class RuleCardModel: ObservableObject {
    @Published var days: Int
    @Published var keep: Set<Category> = [.code, .bank, .person]
    @Published var hitCount: Int? = nil
    @Published var preview: RulePreview? = nil
    @Published var confirmApply = false
    @Published var working = false

    init(days: Int) { self.days = days }
}

struct RuleCard: View {
    @EnvironmentObject var state: AppState
    let rule: CleanupRule
    @StateObject private var model: RuleCardModel

    init(rule: CleanupRule) {
        self.rule = rule
        _model = StateObject(wrappedValue:
            RuleCardModel(days: rule.defaultDays == 0 ? 7 : rule.defaultDays))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rule.symbol)
                    .font(.system(size: Typo.s(13)))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.title)
                        .font(.system(size: Typo.s(13), weight: .semibold))
                    Text(rule.detail)
                        .font(.system(size: Typo.s(11.5)))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if rule.usesDays {
                HStack(spacing: 6) {
                    Text(L.t("删除"))
                        .font(.system(size: Typo.s(11.5)))
                        .foregroundStyle(.secondary)
                    TextField("", value: $model.days, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                        .multilineTextAlignment(.center)
                    Text(L.t("天前的"))
                        .font(.system(size: Typo.s(11.5)))
                        .foregroundStyle(.secondary)
                    Stepper("", value: $model.days, in: 0...3650)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .onChange(of: model.days) { _, _ in model.hitCount = nil }
            }

            if rule.usesKeep {
                HStack(spacing: 10) {
                    Text(L.t("保留"))
                        .font(.system(size: Typo.s(11.5)))
                        .foregroundStyle(.secondary)
                    ForEach([Category.code, .bank, .person]) { c in
                        Toggle(c.label, isOn: Binding(
                            get: { model.keep.contains(c) },
                            set: { on in
                                if on { model.keep.insert(c) } else { model.keep.remove(c) }
                                model.hitCount = nil
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: Typo.s(11.5)))
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    model.preview = RulePreview(
                        rule: rule,
                        messages: state.preview(rule: rule, days: model.days, keep: model.keep))
                } label: {
                    Text(L.t("预览"))
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    model.confirmApply = true
                } label: {
                    Text(model.working ? L.t("删除中…") : L.t("执行删除"))
                }
                .controlSize(.small)
                .disabled(model.hitCount == 0 || model.working)

                Spacer()

                if let n = model.hitCount {
                    Text(L.t("命中 %d 条", n))
                        .font(.system(size: Typo.s(11)).monospacedDigit())
                        .foregroundStyle(n == 0 ? Color.secondary.opacity(0.7) : Color.red)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .sheet(item: $model.preview) { p in
            RulePreviewSheet(preview: p) { n in model.hitCount = n }
        }
        .alert(L.t("执行「%@」？", rule.title), isPresented: $model.confirmApply) {
            Button(L.t("取消"), role: .cancel) {}
            Button(L.t("删除"), role: .destructive) {
                model.working = true
                Task {
                    _ = await state.applyRule(rule, days: model.days, keep: model.keep)
                    model.hitCount = nil
                    model.working = false
                }
            }
        } message: {
            let n = state.preview(rule: rule, days: model.days, keep: model.keep).count
            Text(L.t("将删除 %d 条短信。删除前会自动备份整库，可在回收站还原。", n))
        }
    }
}

struct RulePreview: Identifiable {
    let id = UUID()
    let rule: CleanupRule
    let messages: [SMSMessage]
}

final class PreviewModel: ObservableObject {
    @Published var confirm = false
}

struct RulePreviewSheet: View {
    @EnvironmentObject var state: AppState
    let preview: RulePreview
    var onCount: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PreviewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.rule.title)
                        .font(.system(size: Typo.s(15), weight: .semibold))
                    Text(L.t("命中 %d 条", preview.messages.count))
                        .font(.system(size: Typo.s(12)))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L.t("关闭")) { dismiss() }
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            if preview.messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: Typo.s(26), weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L.t("没有命中任何短信"))
                        .font(.system(size: Typo.s(12)))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(preview.messages.prefix(80)) { m in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(m.category.color)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.snippet)
                                        .font(.system(size: Typo.s(11.5)))
                                        .lineLimit(2)
                                    Text("\(m.sender) · \(Fmt.relative.string(from: m.date))")
                                        .font(.system(size: Typo.s(10)))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 30)
                        }
                        if preview.messages.count > 80 {
                            Text(L.t("仅显示前 80 条，实际将删除 %d 条", preview.messages.count))
                                .font(.system(size: Typo.s(11)))
                                .foregroundStyle(.tertiary)
                                .padding(16)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(L.t("删除前会自动备份整库，可在回收站整批还原。"))
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.t("取消")) { dismiss() }
                Button(L.t("删除 %d 条", preview.messages.count), role: .destructive) {
                    model.confirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(preview.messages.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 560, height: 520)
        .task { onCount(preview.messages.count) }
        .alert(L.t("确认删除？"), isPresented: $model.confirm) {
            Button(L.t("取消"), role: .cancel) {}
            Button(L.t("删除"), role: .destructive) {
                let ids = Set(preview.messages.map(\.id))
                Task {
                    _ = await state.delete(ids: ids, source: "rule",
                                           ruleName: preview.rule.title)
                    onCount(0)
                    dismiss()
                }
            }
        } message: {
            Text(L.t("将永久删除 %d 条短信，可从回收站还原。", preview.messages.count))
        }
    }
}
