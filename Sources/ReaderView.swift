import SwiftUI

struct ReaderView: View {
    let book: LibraryBook
    let payload: BookPayload

    @StateObject private var reader = WebReader()
    @StateObject private var audio = AudioEngine()
    @StateObject private var speaker = Speaker()

    @State private var overlayIndex = 0
    @State private var tapped = ""
    @State private var tappedSentence = ""
    @State private var showCard = false
    @State private var rate: Float = 1.0
    @State private var chapter = 0
    @State private var statusLine = ""

    private var overlays: [OverlayEntry] { payload.overlays }
    private var hasAudio: Bool { !payload.audio.isEmpty }
    private var audioURL: URL? {
        guard let first = payload.audio.first else { return nil }
        return book.folder.appendingPathComponent(first)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ReaderWebView(reader: reader)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                if showCard { dictionaryCard }
                controlBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .navigationTitle(payload.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("下一章") { nextChapter() }
                    Button("字号 +") { reader.setFontScale(1.15) }
                    Button("字号 −") { reader.setFontScale(0.87) }
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .onAppear(perform: setup)
        .onChange(of: reader.isReady) { _, ready in
            if ready { reader.open(payload) }
        }
        .onChange(of: reader.tappedWord) { _, word in
            present(word: word, sentence: reader.tappedSentence)
        }
    }

    // MARK: - setup

    private func setup() {
        if let url = audioURL {
            audio.load(url: url)
            audio.setRate(rate)
            audio.onTick = { time in syncHighlight(at: time) }
        }
        statusLine = overlays.isEmpty
            ? (hasAudio ? "无 SMIL 时间轴：音频可播，逐句高亮不可用" : "本书没有音频")
            : "SMIL 时间轴 \(overlays.count) 段"
    }

    private func syncHighlight(at time: Double) {
        guard !overlays.isEmpty else { return }
        guard let idx = overlays.firstIndex(where: { time >= $0.begin && time < $0.end }) else { return }
        guard idx != overlayIndex else { return }
        overlayIndex = idx
        let entry = overlays[idx]
        reader.highlight(chapter: entry.chapter, id: entry.textId)
    }

    // MARK: - actions

    private func present(word: String, sentence: String) {
        tapped = word
        tappedSentence = sentence
        withAnimation(.easeOut(duration: 0.15)) { showCard = true }
    }

    private func step(_ delta: Int) {
        guard !overlays.isEmpty else { return }
        let next = max(0, min(overlays.count - 1, overlayIndex + delta))
        overlayIndex = next
        let entry = overlays[next]
        audio.seek(entry.begin)
        reader.highlight(chapter: entry.chapter, id: entry.textId)
    }

    private func nextChapter() {
        chapter = min(payload.chapters.count - 1, chapter + 1)
        reader.goToChapter(chapter)
    }

    // MARK: - views

    private var dictionaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tapped).font(.title3.weight(.semibold))
                Button {
                    speaker.speak(tapped)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    withAnimation { showCard = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            if let entry = Dictionary.shared.lookup(tapped) {
                Text(entry.zh).font(.body)
                if let pos = entry.pos {
                    Text(pos).font(.caption).foregroundStyle(.secondary)
                }
                if let note = entry.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("本地词库没有这条（P0 只带 \(Dictionary.shared.count) 条演示词）")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !tappedSentence.isEmpty {
                Divider()
                HStack(alignment: .top) {
                    Text(tappedSentence).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    Spacer()
                    Button {
                        speaker.speak(tappedSentence)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var controlBar: some View {
        VStack(spacing: 6) {
            if !statusLine.isEmpty {
                Text(statusLine).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button { step(-1) } label: { Image(systemName: "backward.end.fill") }
                Button {
                    if audio.duration == 0, let url = audioURL {
                        audio.load(url: url)
                        audio.setRate(rate)
                        audio.play()
                    } else {
                        audio.toggle()
                    }
                } label: {
                    Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                }
                Button { step(1) } label: { Image(systemName: "forward.end.fill") }
                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { value in
                        Button(String(format: "%.2fx", value)) {
                            rate = Float(value)
                            audio.setRate(Float(value))
                        }
                    }
                } label: {
                    Text(String(format: "%.2fx", rate)).font(.footnote)
                }
            }
            .buttonStyle(.borderless)
            .disabled(!hasAudio)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: Capsule())
    }
}
