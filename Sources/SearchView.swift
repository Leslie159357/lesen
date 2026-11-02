import SwiftUI

struct SearchHit: Identifiable {
    let id = UUID()
    let chapter: Int
    let title: String
    let snippet: String
}

/// In-book full-text search. Runs over the injected chapters (no index needed at
/// this size) and falls back to the lexicon when the query looks like a word.
struct SearchView: View {
    let payload: BookPayload
    let onSelect: (Int) -> Void

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var words: [WordEntry] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !words.isEmpty {
                    Section("词典") {
                        ForEach(words) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.word).font(.headline)
                                Text(entry.zh).font(.subheadline)
                                if let note = entry.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("正文（\(hits.count)）") {
                    ForEach(hits) { hit in
                        Button {
                            onSelect(hit.chapter)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.title).font(.caption).foregroundStyle(.secondary)
                                Text(hit.snippet).font(.callout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "词或句子")
            .onChange(of: query) { _, value in
                run(value)
            }
        }
    }

    private func run(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            hits = []
            words = []
            return
        }
        words = Array(LexiconStore.shared.search(q, limit: 12))
        var found: [SearchHit] = []
        for (index, chapter) in payload.chapters.enumerated() {
            let plain = Self.plainText(chapter.html)
            var searchRange = plain.startIndex..<plain.endIndex
            var emitted = 0
            while emitted < 5,
                  let range = plain.range(of: q, options: [.caseInsensitive, .diacriticInsensitive],
                                          range: searchRange) {
                let start = plain.index(range.lowerBound, offsetBy: -40, limitedBy: plain.startIndex) ?? plain.startIndex
                let end = plain.index(range.upperBound, offsetBy: 60, limitedBy: plain.endIndex) ?? plain.endIndex
                let snippet = plain[start..<end].replacingOccurrences(of: "\n", with: " ")
                found.append(SearchHit(chapter: index,
                                       title: "第 \(index + 1) 章 · \(Self.chapterTitle(chapter.html))",
                                       snippet: "…\(snippet)…"))
                emitted += 1
                searchRange = range.upperBound..<plain.endIndex
            }
        }
        hits = found
    }

    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text
    }

    static func chapterTitle(_ html: String) -> String {
        guard let range = html.range(of: "<title>([^<]*)</title>", options: .regularExpression) else {
            return "正文"
        }
        var raw = String(html[range])
        raw = raw.replacingOccurrences(of: "<title>", with: "")
        raw = raw.replacingOccurrences(of: "</title>", with: "")
        return raw.isEmpty ? "正文" : raw
    }
}
