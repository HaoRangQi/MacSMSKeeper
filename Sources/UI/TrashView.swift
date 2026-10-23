import SwiftUI

final class TrashModel: ObservableObject {
    @Published var confirmRestore: TrashBatch? = nil
    @Published var confirmPurge: TrashBatch? = nil
    @Published var busy = false
}

struct TrashView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = TrashModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.trash.isEmpty {
                empty
            } else {
                List {
                    ForEach(state.trash) { batch in
                        TrashRowView(batch: batch,
                                     onRestore: { model.confirmRestore = batch },
                                     onPurge: { model.confirmPurge = batch })
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(L.t("回收站"))
        .alert(L.t("还原这批短信？"), isPresented: Binding(
            get: { model.confirmRestore != nil },
            set: { if !$0 { model.confirmRestore = nil } }
        )) {
            Button(L.t("取消"), role: .cancel) { model.confirmRestore = nil }
            Button("还原") {
                guard let b = model.confirmRestore else { return }
                model.confirmRestore = nil
                model.busy = true
                Task {
                    _ = await state.restore(b)
                    model.busy = false
                }
            }
        } message: {
            Text(L.t("将把 %d 条短信写回系统数据库。还原前同样会先备份。", model.confirmRestore?.count ?? 0))
        }
        .alert(L.t("彻底删除这批记录？"), isPresented: Binding(
            get: { model.confirmPurge != nil },
            set: { if !$0 { model.confirmPurge = nil } }
        )) {
            Button(L.t("取消"), role: .cancel) { model.confirmPurge = nil }
            Button(L.t("彻底删除"), role: .destructive) {
                if let b = model.confirmPurge { state.purge(b) }
                model.confirmPurge = nil
            }
        } message: {
            Text(L.t("仅删除回收站里的存档记录，不影响短信本身。此操作不可撤销。"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L.t("回收站"))
                    .font(.system(size: Typo.s(22), weight: .bold))
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
            }
            Text(L.t("每次批量删除都会把原始记录完整存档，可整批还原到系统数据库。"))
                .font(.system(size: Typo.s(12)))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: Typo.s(32), weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.t("回收站是空的"))
                .font(.system(size: Typo.s(13), weight: .medium))
            Text(L.t("执行删除后，这里会保留可还原的记录"))
                .font(.system(size: Typo.s(11.5)))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TrashRowView: View {
    let batch: TrashBatch
    var onRestore: () -> Void
    var onPurge: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: Typo.s(14)))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(batch.time)
                        .font(.system(size: Typo.s(12.5), weight: .medium))
                    Text(L.t("删除 %d 条", batch.count))
                        .font(.system(size: Typo.s(11)))
                        .foregroundStyle(.secondary)
                    Text(batch.source == "rule" ? (batch.ruleName ?? L.t("规则清理")) : L.t("手动删除"))
                        .font(.system(size: Typo.s(10)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                    if batch.isDemo {
                        Text(L.t("演示"))
                            .font(.system(size: Typo.s(10)))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(batch.rows.prefix(3).map { $0.text ?? L.t("（无正文）") }.joined(separator: "  ·  "))
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(L.t("还原"), action: onRestore)
                    .controlSize(.small)
                Button(L.t("彻底删除"), action: onPurge)
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
