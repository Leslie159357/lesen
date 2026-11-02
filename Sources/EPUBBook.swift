import Foundation
import ZIPFoundation

/// Minimal EPUB 3 reader: unzip → container.xml → OPF → chapters + media overlays.
/// Deliberately regex-based: OPF/SMIL are flat XML and this keeps the parser
/// dependency-free (no third-party XML stack in the build).
enum EPUBError: LocalizedError {
    case notAnEPUB
    case missingContainer
    case missingOPF
    case emptySpine

    var errorDescription: String? {
        switch self {
        case .notAnEPUB: return "压缩包里没有 META-INF/container.xml，不是合法 EPUB"
        case .missingContainer: return "container.xml 解析失败"
        case .missingOPF: return "找不到 OPF 包文件"
        case .emptySpine: return "书脊为空，无法排版"
        }
    }
}

struct EPUBParser {

    // MARK: - attribute helpers

    static func attributes(in tag: String) -> [String: String] {
        var out: [String: String] = [:]
        let pattern = "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*\"([^\"]*)\""
        guard let re = try? NSRegularExpression(pattern: pattern) else { return out }
        let ns = tag as NSString
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            if m.numberOfRanges == 3 {
                out[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
            }
        }
        return out
    }

    static func match(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: - unpack

    /// Unzips an .epub into `folder` and returns the OPF path relative to the book root.
    static func unpack(epub: URL, to folder: URL) throws {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("inflate-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.unzipItem(at: epub, to: dest)
        // move contents (not the wrapper dir) into folder
        let items = try FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
        for item in items {
            try FileManager.default.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: dest)
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("META-INF/container.xml").path) else {
            throw EPUBError.notAnEPUB
        }
    }

    // MARK: - parse

    static func parse(bookRoot: URL) throws -> BookPayload {
        let containerURL = bookRoot.appendingPathComponent("META-INF/container.xml")
        guard let container = try? String(contentsOf: containerURL, encoding: .utf8),
              let opfRel = firstGroup("<rootfile[^>]*full-path\\s*=\\s*\"([^\"]+)\"", in: container) else {
            throw EPUBError.missingContainer
        }
        let opfURL = bookRoot.appendingPathComponent(opfRel)
        let opfDir = opfURL.deletingLastPathComponent()
        guard let opf = try? String(contentsOf: opfURL, encoding: .utf8) else { throw EPUBError.missingOPF }

        let title = firstGroup("<dc:title[^>]*>([^<]*)</dc:title>", in: opf) ?? "未命名"
        let author = firstGroup("<dc:creator[^>]*>([^<]*)</dc:creator>", in: opf) ?? ""

        // manifest
        struct Item { let id: String; let href: String; let type: String; let overlay: String?; let properties: String }
        var items: [String: Item] = [:]
        for tag in match("<item\\b[^>]*/?>", in: opf) {
            let a = attributes(in: tag)
            guard let id = a["id"], let href = a["href"] else { continue }
            items[id] = Item(id: id, href: href, type: a["media-type"] ?? "",
                             overlay: a["media-overlay"], properties: a["properties"] ?? "")
        }

        // spine
        var spine: [String] = []
        let spineBlock = firstGroup("<spine\\b[^>]*>(.*?)</spine>", in: opf) ?? ""
        for tag in match("<itemref\\b[^>]*/?>", in: spineBlock) {
            let a = attributes(in: tag)
            if a["linear"] == "no" { continue }
            if let idref = a["idref"], items[idref] != nil { spine.append(idref) }
        }
        guard !spine.isEmpty else { throw EPUBError.emptySpine }

        // stylesheets (inlined into the reader so nothing is fetched at runtime)
        var cssBundle = ""
        for item in items.values where item.type.contains("css") {
            if let css = try? String(contentsOf: opfDir.appendingPathComponent(item.href), encoding: .utf8) {
                cssBundle += "\n/* \(item.href) */\n" + css
            }
        }

        var chapters: [ChapterPayload] = []
        for idref in spine {
            guard let item = items[idref] else { continue }
            let fileURL = opfDir.appendingPathComponent(item.href)
            var html = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            html = inlineImages(html: html, base: fileURL.deletingLastPathComponent())
            html = stripActiveContent(html)
            chapters.append(ChapterPayload(href: item.href, html: html))
        }

        // media overlays (EPUB 3 SMIL)
        var overlays: [OverlayEntry] = []
        var audioFiles = Set<String>()
        for item in items.values {
            guard let overlayId = item.overlay, let smilItem = items[overlayId] else { continue }
            let smilURL = opfDir.appendingPathComponent(smilItem.href)
            guard let smil = try? String(contentsOf: smilURL, encoding: .utf8) else { continue }
            for par in match("<par\\b[^>]*>.*?</par>", in: smil) {
                guard let textTag = match("<text\\b[^>]*/?>", in: par).first,
                      let audioTag = match("<audio\\b[^>]*/?>", in: par).first else { continue }
                let t = attributes(in: textTag)
                let a = attributes(in: audioTag)
                guard let src = t["src"], let audio = a["src"] else { continue }
                let pieces = src.split(separator: "#", maxSplits: 1)
                let chapterHref = String(pieces[0])
                let textId = pieces.count > 1 ? String(pieces[1]) : ""
                let begin = parseTime(a["clipBegin"] ?? "0")
                let end = parseTime(a["clipEnd"] ?? "0")
                audioFiles.insert(audio)
                overlays.append(OverlayEntry(chapter: chapterHref, textId: textId,
                                             audio: audio, begin: begin, end: end))
            }
        }

        // no SMIL: treat every audio file in the manifest as a track we can still play
        if overlays.isEmpty {
            for item in items.values where item.type.hasPrefix("audio/") {
                audioFiles.insert(item.href)
            }
        }

        return BookPayload(title: title, author: author, chapters: chapters,
                           overlays: overlays, audio: Array(audioFiles).sorted())
    }

    /// "0:01:02.500" / "62.5s" / "62.5" → seconds
    static func parseTime(_ raw: String) -> Double {
        let s = raw.trimmingCharacters(in: CharacterSet(charactersIn: "s"))
        let parts = s.split(separator: ":")
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let sec = Double(parts[2]) ?? 0
            return h * 3600 + m * 60 + sec
        }
        if parts.count == 2 {
            return (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0)
        }
        return Double(s) ?? 0
    }

    /// Rewrites <img src> to data: URIs so the WebView never needs file access.
    static func inlineImages(html: String, base: URL) -> String {
        guard let re = try? NSRegularExpression(pattern: "(<img\\b[^>]*?src\\s*=\\s*\")([^\"]+)(\")",
                                               options: [.caseInsensitive]) else { return html }
        let ns = html as NSString
        var out = html
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            guard m.numberOfRanges == 4 else { continue }
            let rel = ns.substring(with: m.range(at: 2))
            if rel.hasPrefix("data:") { continue }
            let fileURL = base.appendingPathComponent(rel.removingPercentEncoding ?? rel)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let mime: String
            switch fileURL.pathExtension.lowercased() {
            case "png": mime = "image/png"
            case "gif": mime = "image/gif"
            case "svg": mime = "image/svg+xml"
            case "webp": mime = "image/webp"
            default: mime = "image/jpeg"
            }
            let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
            if let range = Range(m.range, in: out) {
                out.replaceSubrange(range, with: "<img src=\"\(dataURI)\"")
            }
        }
        return out
    }

    static func stripActiveContent(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<iframe[^>]*>.*?</iframe>", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "on[a-z]+\\s*=\\s*\"[^\"]*\"", with: "", options: [.regularExpression, .caseInsensitive])
        return s
    }
}
