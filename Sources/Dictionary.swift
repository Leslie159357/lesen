import Foundation

/// Offline demo lexicon shipped inside the bundle (Web/de-zh-demo.json).
/// P0 deliberately keeps the data tiny; swapping in a full dictionary only
/// means replacing this file / backing it with SQLite.
final class Dictionary {
    static let shared = Dictionary()

    private var entries: [String: WordEntry] = [:]

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "de-zh-demo", withExtension: "json", subdirectory: "Web"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WordEntry].self, from: data) else { return }
        for e in list {
            entries[e.word.lowercased()] = e
        }
    }

    var count: Int { entries.count }

    /// Looks up a surface form, trying a few German inflection fallbacks.
    func lookup(_ raw: String) -> WordEntry? {
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
        guard !cleaned.isEmpty else { return nil }
        if let hit = entries[cleaned] { return hit }

        var candidates = [cleaned]
        // very small inflection table: plural/verb endings common in graded readers
        for suffix in ["n", "en", "e", "es", "er", "em", "s", "te", "test", "ten", "et", "est"] {
            if cleaned.hasSuffix(suffix) && cleaned.count > suffix.count + 2 {
                candidates.append(String(cleaned.dropLast(suffix.count)))
            }
        }
        for c in candidates {
            if let hit = entries[c] { return hit }
        }
        return nil
    }
}
