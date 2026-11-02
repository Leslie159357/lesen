import Foundation

/// Books live in Documents/Books/<uuid>/ with the unpacked EPUB inside.
final class LibraryStore: ObservableObject {
    @Published var books: [LibraryBook] = []
    @Published var lastError: String?

    private let root: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        var found: [LibraryBook] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let folders = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                   includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        for folder in folders where folder.hasDirectoryPath {
            let metaURL = folder.appendingPathComponent("book.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let added = (try? folder.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? Date()
            found.append(LibraryBook(id: folder.lastPathComponent,
                                     title: meta["title"] as? String ?? folder.lastPathComponent,
                                     author: meta["author"] as? String ?? "",
                                     coverPath: meta["cover"] as? String,
                                     folder: folder,
                                     added: added))
        }
        books = found.sorted { $0.added > $1.added }
    }

    /// Imports an .epub: unpack → parse → write book.json.
    func importBook(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let id = UUID().uuidString
        let folder = root.appendingPathComponent(id, isDirectory: true)
        do {
            try EPUBParser.unpack(epub: url, to: folder)
            let payload = try EPUBParser.parse(bookRoot: folder)
            let meta: [String: Any] = ["title": payload.title,
                                        "author": payload.author,
                                        "cover": ""]
            let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
            try data.write(to: folder.appendingPathComponent("book.json"))
            // cache the parse result so the reader opens instantly next time
            let encoded = try JSONEncoder().encode(payload)
            try encoded.write(to: folder.appendingPathComponent("payload.json"))
            reload()
        } catch {
            try? FileManager.default.removeItem(at: folder)
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    func payload(for book: LibraryBook) throws -> BookPayload {
        let cached = book.folder.appendingPathComponent("payload.json")
        if let data = try? Data(contentsOf: cached),
           let payload = try? JSONDecoder().decode(BookPayload.self, from: data) {
            return payload
        }
        let payload = try EPUBParser.parse(bookRoot: book.folder)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cached)
        }
        return payload
    }

    func delete(_ book: LibraryBook) {
        try? FileManager.default.removeItem(at: book.folder)
        reload()
    }
}
