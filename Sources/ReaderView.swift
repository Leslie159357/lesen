import SwiftUI

struct ReaderView: View {
    let book: LibraryBook
    let payload: BookPayload

    @StateObject private var reader = WebReader()
    @StateObject private var audio = AudioEngine()
    @StateObject private var speaker = Speaker()

    @AppStorage("reader.fontScale") private var fontScale: Double = 1.0
    @AppStorage("reader.pageMode") private var pageMode: Bool = false

    @State private var overlayIndex = 0
    @State private var tapped = ""
    @State private var tappedSentence = ""
    @State private var showCard = false
    @State private var rate: Float = 1.0
    @State private var chapter = 0
    @State private var statusLine = ""
    @State private var savedNotice = ""

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
                if !savedNotice.isEmpty {
                    Text(savedNotice)
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
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
                    Button(pageMode ? "切换为滚动" : "切换为分页") {
                        pageMode.toggle()
                        reader.setPageMode(pageMode)
                    }
                    Divider()
                    Button("字号 +") { adjustFont(1.15) }
                    Button("字号 −") { adjustFont(0.87) }
                    Divider()
                    Button("下一章") { nextChapter() }
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: persist)
        .onChange(of: reader.isReady) { _, ready in
            guard ready else { return }
            reader.open(payload)
            reader.setPageMode(pageMode)
            reader.setFontScale(fontScale)
            if let progress = LexiconStore.shared.loadProgress(book: book.id) {
                reader.restore(position: progress.chapter, percent: progress.percent)
            }
        }
        .onChange(of: reader.tappedWord) { _, word in
            present(word: word, sentence: reader.tappedSentence)
        }
    }

    // MARK: - lifecycle

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

    private func persist() {
        LexiconStore.shared.saveProgress(book: book.id,
                                         chapter: reader.progressChapter,
                                         percent: reader.progressPercent)
    }

    private func adjustFont(_ factor: Double) {
        fontScale = min(1.8, max(0.7, fontScale * factor))
        reader.setFontScale(factor)
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

    private func addToVocabulary() {
        LexiconStore.shared.addToVocabulary(word: tapped, sentence: tappedSentence, book: book.id)
        savedNotice = "已加入生词本（\(LexiconStore.shared.vocabularyCount()) 条）"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            savedNotice = ""
        }
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
            if let entry = LexiconStore.shared.lookup(tapped) {
                Text(entry.zh).font(.body)
                HStack(spacing: 8) {
                    if let pos = entry.pos { Text(pos) }
                    if let note = entry.note { Text(note) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("词库里没有这条（当前 \(LexiconStore.shared.count()) 条）")
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
            Button {
                addToVocabulary()
            } label: {
                Label("加入生词本", systemImage: "bookmark")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var controlBar: some View {
        VStack(spacing: 6) {
            if !statusLine.isEmpty {
                Text(statusLine).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Button { step(-1) } label: { Image(systemName: "backward.end.fill") }
                    .disabled(overlays.isEmpty)
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
                .disabled(!hasAudio)
                Button { step(1) } label: { Image(systemName: "forward.end.fill") }
                    .disabled(overlays.isEmpty)

                if pageMode {
                    Button { reader.turnPage(-1) } label: { Image(systemName: "chevron.left") }
                    Button { reader.turnPage(1) } label: { Image(systemName: "chevron.right") }
                }

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
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: Capsule())
    }
}
