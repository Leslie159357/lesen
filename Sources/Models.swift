import Foundation
import SwiftUI

@main
struct LesenApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
        }
    }
}

/// A book that has been unpacked to disk.
struct LibraryBook: Identifiable, Hashable {
    let id: String          // folder name (uuid)
    let title: String
    let author: String
    let coverPath: String?
    let folder: URL
    let added: Date
}

/// Parsed EPUB content handed to the web reader.
struct BookPayload: Codable {
    let title: String
    let author: String
    let chapters: [ChapterPayload]
    let overlays: [OverlayEntry]
    let audio: [String]      // audio paths relative to book root
}

struct ChapterPayload: Codable {
    let href: String
    let html: String
}

struct OverlayEntry: Codable {
    let chapter: String      // chapter href
    let textId: String       // fragment id inside the chapter
    let audio: String        // audio href relative to book root
    let begin: Double
    let end: Double
}

/// One dictionary entry shipped in the demo lexicon.
struct WordEntry: Codable, Identifiable {
    var id: String { word }
    let word: String
    let pos: String?
    let zh: String
    let note: String?
}
