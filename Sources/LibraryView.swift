import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var importing = false
    @State private var openBook: LibraryBook?
    @State private var openPayload: BookPayload?
    @State private var errorText: String?

    private var epubType: UTType {
        UTType(filenameExtension: "epub") ?? .data
    }

    var body: some View {
        NavigationStack {
            List {
                if store.books.isEmpty {
                    Section {
                        Text("还没有书。点右上角 + 导入一本 EPUB。")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(store.books) { book in
                    Button {
                        open(book)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.headline)
                            if !book.author.isEmpty {
                                Text(book.author).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet { store.delete(store.books[i]) }
                }
            }
            .navigationTitle("精读")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [epubType],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    store.importBook(from: url)
                    if let message = store.lastError { errorText = message }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .onChange(of: store.lastError) { _, message in
                if let message { errorText = message }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .navigationDestination(item: $openBook) { book in
                if let payload = openPayload {
                    ReaderView(book: book, payload: payload)
                } else {
                    ProgressView()
                }
            }
        }
    }

    private func open(_ book: LibraryBook) {
        do {
            openPayload = try store.payload(for: book)
            openBook = book
        } catch {
            errorText = error.localizedDescription
        }
    }
}
