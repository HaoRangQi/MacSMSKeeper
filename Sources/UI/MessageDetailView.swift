import SwiftUI
import AppKit

struct MessageDetailView: View {
    @EnvironmentObject var state: AppState
    let message: SMSMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text(message.text.isEmpty ? L.t("（无正文）") : message.text)
                    .font(.system(size: Typo.s(13)))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial,
                                in: RoundedRectangle(cornerRadius: 8))

                if let code = message.code {
                    codeCard(code)
                }

                if !message.reasons.isEmpty {
                    reasonsCard
                }

                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        state.requestDelete([message.id])
                    } label: {
                        Label(L.t("删除这条"), systemImage: "trash")
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        state.toast = L.t("已复制全文")
                    } label: {
                        Label(L.t("复制全文"), systemImage: "doc.on.doc")
                    }

                    Menu {
                        ForEach(ExportFormat.allCases) { f in
                            Button {
                                _ = state.export([message], format: f)
                            } label: {
                                Label(f.title, systemImage: f.symbol)
                            }
                        }
                    } label: {
                        Label(L.t("导出"), systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .controlSize(.regular)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(message.category.label, systemImage: message.category.symbol)
                    .font(.system(size: Typo.s(11), weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(message.category.color.opacity(0.14), in: Capsule())
                    .foregroundStyle(message.category.color)

                Spacer()

                Text(L.t("置信度 %d%%", Int(message.score * 100)))
                    .font(.system(size: Typo.s(11)))
                    .foregroundStyle(.tertiary)
            }

            Text(message.sender.isEmpty ? L.t("未知发件人") : message.sender)
                .font(.system(size: Typo.s(15), weight: .semibold))
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 4) {
                infoRow(L.t("时间"), Fmt.full.string(from: message.date))
                infoRow(L.t("通道"), message.service)
                infoRow(L.t("状态"), message.isFromMe ? L.t("由我发出")
                        : (message.isRead ? L.t("已读") : L.t("未读")))
                if message.attachments > 0 {
                    infoRow(L.t("附件"), L.t("%d 个", message.attachments))
                }
            }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k)
                .font(.system(size: Typo.s(11.5)))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(v)
                .font(.system(size: Typo.s(11.5)))
                .textSelection(.enabled)
        }
    }

    private func codeCard(_ code: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("提取到的验证码"))
                    .font(.system(size: Typo.s(10.5)))
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(size: Typo.s(22), weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                state.toast = L.t("验证码已复制")
            } label: {
                Label(L.t("复制"), systemImage: "doc.on.clipboard")
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.2))
        )
    }

    private var reasonsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("分类依据"))
                .font(.system(size: Typo.s(11)))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 5) {
                ForEach(message.reasons, id: \.self) { r in
                    Text(r)
                        .font(.system(size: Typo.s(11)))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 简单流式布局

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
