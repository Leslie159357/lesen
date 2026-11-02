import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Local lexicon backed by SQLite + FTS5 (same shape OneBook uses).
/// The bundled JSON is only a seed: on first launch it is imported into the DB,
/// afterwards every lookup goes through SQL, so swapping in a real dictionary
/// means replacing the seed file, not touching the reader.
final class LexiconStore {
    static let shared = LexiconStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "lexicon.db")

    private init() {
        open()
        migrate()
        seedIfEmpty()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - setup

    private var dbURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("lexicon.sqlite")
    }

    private func open() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("[lexicon] open failed: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
        }
    }

    private func migrate() {
        exec("PRAGMA journal_mode=WAL;")
        exec("""
        CREATE TABLE IF NOT EXISTS entry(
            id INTEGER PRIMARY KEY,
            word TEXT NOT NULL UNIQUE,
            pos TEXT,
            zh TEXT NOT NULL,
            note TEXT
        );
        """)
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS entry_fts USING fts5(
            word, zh, content='entry', content_rowid='id', tokenize='unicode61'
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS vocab(
            word TEXT PRIMARY KEY,
            sentence TEXT,
            book TEXT,
            added REAL NOT NULL,
            due REAL NOT NULL,
            box INTEGER NOT NULL DEFAULT 0,
            reps INTEGER NOT NULL DEFAULT 0
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS progress(
            book TEXT PRIMARY KEY,
            chapter INTEGER NOT NULL DEFAULT 0,
            percent REAL NOT NULL DEFAULT 0,
            updated REAL NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS alias(
            word TEXT PRIMARY KEY,
            target TEXT NOT NULL
        );
        """)
    }

    private func seedIfEmpty() {
        guard scalarInt("SELECT COUNT(*) FROM entry") == 0 else { return }
        guard let url = Bundle.main.url(forResource: "de-zh-demo", withExtension: "json", subdirectory: "Web"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WordEntry].self, from: data) else { return }
        exec("BEGIN;")
        for e in list {
            insertEntry(e)
            seedInflections(for: e)
        }
        exec("COMMIT;")
        exec("INSERT INTO entry_fts(entry_fts) VALUES('rebuild');")
    }

    /// German text is heavily inflected: pull the forms we documented in `note`
    /// ("复数 Häuser", "spricht, sprach, gesprochen") into an alias table so a
    /// tap on "Häuser" still lands on "Haus".
    private func seedInflections(for entry: WordEntry) {
        guard let note = entry.note, !note.isEmpty, let db else { return }
        let stripped = note.replacingOccurrences(of: "复数", with: "")
        let tokens = stripped
            .split(whereSeparator: { ",、/;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil }
        for token in tokens {
            let form = token.lowercased()
            guard form != entry.word.lowercased(), form.count > 1 else { continue }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO alias(word, target) VALUES(?,?)", -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, form, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entry.word.lowercased(), -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    // MARK: - sqlite helpers

    private func exec(_ sql: String) {
        guard let db else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            print("[lexicon] sql error: \(String(cString: err))")
            sqlite3_free(err)
        }
    }

    private func scalarInt(_ sql: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    private func insertEntry(_ e: WordEntry) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "INSERT OR REPLACE INTO entry(word, pos, zh, note) VALUES(?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, e.word, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, e.pos ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, e.zh, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, e.note ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - lookup

    func count() -> Int { scalarInt("SELECT COUNT(*) FROM entry") }

    /// Exact → prefix → FTS → inflection fallback. Returns the first hit.
    func lookup(_ raw: String) -> WordEntry? {
        let base = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
        guard !base.isEmpty else { return nil }

        for candidate in candidates(for: base) {
            if let hit = query("SELECT word, pos, zh, note FROM entry WHERE lower(word)=? LIMIT 1", candidate) {
                return hit
            }
            if let target = aliasTarget(candidate),
               let hit = query("SELECT word, pos, zh, note FROM entry WHERE lower(word)=? LIMIT 1", target) {
                return WordEntry(word: hit.word, pos: hit.pos, zh: hit.zh,
                                 note: (hit.note ?? "") + "（\(candidate) 是其变形）")
            }
        }
        for candidate in candidates(for: base) where candidate.count >= 3 {
            if let hit = query("SELECT word, pos, zh, note FROM entry WHERE lower(word) LIKE ? || '%' LIMIT 1", candidate) {
                return hit
            }
        }
        if let hit = ftsLookup(base) { return hit }
        return nil
    }

    private func candidates(for word: String) -> [String] {
        var out = [word]
        let suffixes = ["ungen", "ung", "lich", "isch", "sten", "stem", "nen", "nem", "ner",
                        "tes", "ten", "tem", "ter", "est", "ete", "en", "es", "er", "em",
                        "e", "s", "n", "t"]
        for suffix in suffixes where word.hasSuffix(suffix) && word.count > suffix.count + 2 {
            out.append(String(word.dropLast(suffix.count)))
        }
        return out
    }

    private func aliasTarget(_ word: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT target FROM alias WHERE word=? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    private func query(_ sql: String, _ arg: String) -> WordEntry? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, arg, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return entryFrom(stmt)
    }

    private func ftsLookup(_ word: String) -> WordEntry? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT entry.word, entry.pos, entry.zh, entry.note
        FROM entry_fts JOIN entry ON entry.id = entry_fts.rowid
        WHERE entry_fts MATCH ? LIMIT 1
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, word + "*", -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return entryFrom(stmt)
    }

    private func entryFrom(_ stmt: OpaquePointer?) -> WordEntry? {
        guard let stmt else { return nil }
        func text(_ idx: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, idx) else { return "" }
            return String(cString: c)
        }
        let word = text(0)
        guard !word.isEmpty else { return nil }
        let note = text(3)
        return WordEntry(word: word,
                         pos: text(1).isEmpty ? nil : text(1),
                         zh: text(2),
                         note: note.isEmpty ? nil : note)
    }

    // MARK: - vocabulary

    func addToVocabulary(word: String, sentence: String, book: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        INSERT OR IGNORE INTO vocab(word, sentence, book, added, due, box, reps)
        VALUES(?,?,?,?,?,0,0)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        let now = Date().timeIntervalSince1970
        sqlite3_bind_text(stmt, 1, word.lowercased(), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sentence, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, book, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, now)
        sqlite3_bind_double(stmt, 5, now)
        sqlite3_step(stmt)
    }

    /// Leitner-style scheduling: box 0..5 → 0d, 1d, 2d, 4d, 8d, 16d.
    func review(word: String, remembered: Bool) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "UPDATE vocab SET box=?, reps=reps+1, due=? WHERE word=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        let current = boxFor(word: word)
        let next = remembered ? min(5, current + 1) : 0
        let interval = [0.0, 1, 2, 4, 8, 16][next] * 86400
        sqlite3_bind_int(stmt, 1, Int32(next))
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970 + interval)
        sqlite3_bind_text(stmt, 3, word.lowercased(), -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func boxFor(word: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT box FROM vocab WHERE word=? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_text(stmt, 1, word.lowercased(), -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    func vocabulary(dueOnly: Bool) -> [(word: String, sentence: String, box: Int)] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = dueOnly
            ? "SELECT word, sentence, box FROM vocab WHERE due <= ? ORDER BY due LIMIT 200"
            : "SELECT word, sentence, box FROM vocab ORDER BY added DESC LIMIT 500"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        if dueOnly {
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        }
        var out: [(word: String, sentence: String, box: Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let w = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let s = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            out.append((word: w, sentence: s, box: Int(sqlite3_column_int(stmt, 2))))
        }
        return out
    }

    func vocabularyCount() -> Int { scalarInt("SELECT COUNT(*) FROM vocab") }

    func removeFromVocabulary(_ word: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM vocab WHERE word=?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, word.lowercased(), -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - reading progress

    func saveProgress(book: String, chapter: Int, percent: Double) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        INSERT INTO progress(book, chapter, percent, updated) VALUES(?,?,?,?)
        ON CONFLICT(book) DO UPDATE SET chapter=excluded.chapter,
                                        percent=excluded.percent,
                                        updated=excluded.updated
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, book, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        sqlite3_bind_double(stmt, 3, percent)
        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    func loadProgress(book: String) -> (chapter: Int, percent: Double)? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT chapter, percent FROM progress WHERE book=? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, book, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return (Int(sqlite3_column_int(stmt, 0)), sqlite3_column_double(stmt, 1))
    }
}
