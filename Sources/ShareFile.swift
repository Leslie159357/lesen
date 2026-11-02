import SwiftUI
import UniformTypeIdentifiers

/// Turns a generated text into a shareable file (CSV for the vocabulary list).
struct ShareFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try item.text.data(using: .utf8)?.write(to: url)
            return SentTransferredFile(url)
        }
    }
}
