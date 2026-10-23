import Foundation
import UniformTypeIdentifiers

// MARK: - 导出格式

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown, text, csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .text: return L.t("纯文本 (.txt)")
        case .csv: return L.t("CSV 表格 (.csv)")
        }
    }

    var shortTitle: String {
        switch self {
        case .markdown: return "Markdown"
        case .text: return L.t("纯文本")
        case .csv: return "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .text: return "txt"
        case .csv: return "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .text: return .plainText
        case .csv: return .commaSeparatedText
        }
    }

    var symbol: String {
        switch self {
        case .markdown: return "text.document"
        case .text: return "doc.plaintext"
        case .csv: return "tablecells"
        }
    }
}

// MARK: - 内容生成

enum Exporter {

    /// 默认文件名：短信导出-20261023-101818.md
    static func suggestedName(format: ExportFormat, at date: Date = Date()) -> String {
        "短信导出-\(Fmt.stamp.string(from: date)).\(format.fileExtension)"
    }

    static func content(for messages: [SMSMessage], format: ExportFormat,
                        generatedAt: Date = Date()) -> String {
        switch format {
        case .csv: return csv(messages)
        case .text: return plainText(messages, generatedAt: generatedAt)
        case .markdown: return markdown(messages, generatedAt: generatedAt)
        }
    }

    // MARK: CSV

    private static func csv(_ messages: [SMSMessage]) -> String {
        var lines = [L.t("时间,发件人,分类,验证码,内容")]
        for m in messages {
            let text = m.text
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            lines.append("\(Fmt.iso.string(from: m.date)),\"\(m.sender)\","
                         + "\"\(m.category.label)\",\"\(m.code ?? "")\",\"\(text)\"")
        }
        // 加 BOM，Excel 打开中文不乱码
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }

    // MARK: 纯文本

    private static func plainText(_ messages: [SMSMessage], generatedAt: Date) -> String {
        var out = L.t("短信导出") + "\n"
            + L.t("导出时间：%@", Fmt.full.string(from: generatedAt)) + "\n"
            + L.t("共 %d 条", messages.count) + "\n"
            + "============================\n\n"
        for m in messages {
            out += "\(Fmt.full.string(from: m.date))  |  \(m.sender)  |  \(m.category.label)\n"
            out += (m.text.isEmpty ? L.t("（无正文）") : m.text) + "\n"
            if let code = m.code {
                out += L.t("验证码：%@", code) + "\n"
            }
            out += "----------------------------\n"
        }
        return out
    }

    // MARK: Markdown

    private static func markdown(_ messages: [SMSMessage], generatedAt: Date) -> String {
        var out = "# " + L.t("短信导出") + "\n\n"
            + "- " + L.t("导出时间：%@", Fmt.full.string(from: generatedAt)) + "\n"
            + "- " + L.t("条数：%d", messages.count) + "\n"
            + "- " + L.t("分类分布：%@", categorySummary(messages)) + "\n\n"
            + "| " + L.t("时间") + " | " + L.t("发件人") + " | " + L.t("分类")
            + " | " + L.t("验证码") + " | " + L.t("内容") + " |\n"
            + "| --- | --- | --- | --- | --- |"
        for m in messages {
            let text = m.text
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\r\n", with: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
            let sender = m.sender.replacingOccurrences(of: "|", with: "\\|")
            out += "\n| \(Fmt.full.string(from: m.date)) | \(sender) | "
                + "\(m.category.label) | \(m.code ?? "") | \(text.isEmpty ? L.t("（无正文）") : text) |"
        }
        out += "\n"
        return out
    }

    private static func categorySummary(_ messages: [SMSMessage]) -> String {
        var counts: [Category: Int] = [:]
        for m in messages { counts[m.category, default: 0] += 1 }
        let parts = Category.allCases.compactMap { c -> String? in
            guard let n = counts[c], n > 0 else { return nil }
            return "\(c.label) \(n)"
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
