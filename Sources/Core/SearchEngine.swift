import Foundation

/// 查询解析：支持 "精确短语"、-排除词、/正则/、sender:号码
struct ParsedQuery {
    var must: [String] = []
    var mustNot: [String] = []
    var senderOnly: [String] = []
    var regexes: [NSRegularExpression] = []

    var isEmpty: Bool {
        must.isEmpty && mustNot.isEmpty && senderOnly.isEmpty && regexes.isEmpty
    }

    static func parse(_ raw: String) -> ParsedQuery {
        var q = ParsedQuery()
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return q }

        var i = s.startIndex
        var buffer = ""

        func flushBuffer() {
            defer { buffer = "" }
            guard !buffer.isEmpty else { return }
            if buffer.hasPrefix("sender:") {
                let v = String(buffer.dropFirst(7)).lowercased()
                if !v.isEmpty { q.senderOnly.append(v) }
            } else if buffer.hasPrefix("-"), buffer.count > 1 {
                q.mustNot.append(String(buffer.dropFirst()).lowercased())
            } else {
                q.must.append(buffer.lowercased())
            }
        }

        while i < s.endIndex {
            let ch = s[i]
            if ch == "\"" {
                flushBuffer()
                var j = s.index(after: i)
                var phrase = ""
                while j < s.endIndex && s[j] != "\"" {
                    phrase.append(s[j]); j = s.index(after: j)
                }
                if !phrase.isEmpty { q.must.append(phrase.lowercased()) }
                i = j < s.endIndex ? s.index(after: j) : j
                continue
            }
            if ch == "/" {
                flushBuffer()
                var j = s.index(after: i)
                var pattern = ""
                while j < s.endIndex && s[j] != "/" {
                    pattern.append(s[j]); j = s.index(after: j)
                }
                if !pattern.isEmpty,
                   let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    q.regexes.append(re)
                } else if !pattern.isEmpty {
                    q.must.append(pattern.lowercased())
                }
                i = j < s.endIndex ? s.index(after: j) : j
                continue
            }
            if ch == " " || ch == "\n" || ch == "\t" {
                flushBuffer()
                i = s.index(after: i)
                continue
            }
            buffer.append(ch)
            i = s.index(after: i)
        }
        flushBuffer()
        return q
    }
}

struct FilterOptions {
    var query = ""
    var categories: Set<Category> = []
    var range: TimeRange = .all
    var customFrom: Date? = nil
    var customTo: Date? = nil
    var unreadOnly = false
    var withAttachment = false
    var sort: SortMode = .newest
}

enum SearchEngine {

    static func apply(_ opts: FilterOptions, to all: [SMSMessage]) -> [SMSMessage] {
        let parsed = ParsedQuery.parse(opts.query)
        let cal = Calendar.current
        var lower: Date? = nil
        var upper: Date? = nil

        if let d = opts.range.days {
            let start = cal.startOfDay(for: Date())
            lower = cal.date(byAdding: .day, value: -d, to: start)
        } else if opts.range == .custom {
            lower = opts.customFrom
            upper = opts.customTo
        }
        if let u = upper { upper = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: u)) }

        var out: [SMSMessage] = []
        out.reserveCapacity(all.count)

        for m in all {
            if !opts.categories.isEmpty && !opts.categories.contains(m.category) { continue }
            if opts.unreadOnly && !m.isUnread { continue }
            if opts.withAttachment && m.attachments == 0 { continue }
            if let lo = lower, m.date < lo { continue }
            if let up = upper, m.date >= up { continue }

            if !parsed.isEmpty {
                let hay = m.searchText
                var ok = true
                for kw in parsed.must where !hay.contains(kw) { ok = false; break }
                if ok {
                    for kw in parsed.mustNot where hay.contains(kw) { ok = false; break }
                }
                if ok {
                    for sd in parsed.senderOnly where !m.sender.lowercased().contains(sd) {
                        ok = false; break
                    }
                }
                if ok && !parsed.regexes.isEmpty {
                    let ns = m.text as NSString
                    let range = NSRange(location: 0, length: ns.length)
                    for re in parsed.regexes where re.firstMatch(in: m.text, range: range) == nil {
                        ok = false; break
                    }
                }
                if !ok { continue }
            }
            out.append(m)
        }

        switch opts.sort {
        case .newest: out.sort { $0.date > $1.date }
        case .oldest: out.sort { $0.date < $1.date }
        case .longest: out.sort { $0.text.count > $1.text.count }
        case .sender: out.sort { ($0.sender, $1.date) < ($1.sender, $0.date) }
        }
        return out
    }
}
