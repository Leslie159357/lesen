import SwiftUI

/// Saved words with a Leitner review loop.
struct VocabularyView: View {
    @State private var due: [(word: String, sentence: String, box: Int)] = []
    @State private var all: [(word: String, sentence: String, box: Int)] = []
    @State private var reviewing = false
    @State private var index = 0
    @State private var revealed = false
    @StateObject private var speaker = Speaker()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if reviewing {
                    reviewCard
                } else {
                    listView
                }
            }
            .navigationTitle(reviewing ? "复习" : "生词本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !all.isEmpty {
                        Button(reviewing ? "列表" : "复习 \(due.count)") {
                            if reviewing {
                                reviewing = false
                            } else {
                                reload()
                                index = 0
                                revealed = false
                                reviewing = true
                            }
                        }
                    }
                }
            }
            .onAppear(perform: reload)
        }
    }

    private var listView: some View {
        List {
            if all.isEmpty {
                Text("还没有生词。阅读时点任意单词，卡片里点「加入生词本」。")
                    .foregroundStyle(.secondary)
            }
            ForEach(all, id: \.word) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.word).font(.headline)
                        Spacer()
                        Text("box \(item.box)").font(.caption2).foregroundStyle(.secondary)
                        Button {
                            speaker.speak(item.word)
                        } label: { Image(systemName: "speaker.wave.2") }
                        .buttonStyle(.borderless)
                    }
                    if let entry = LexiconStore.shared.lookup(item.word) {
                        Text(entry.zh).font(.subheadline)
                    }
                    if !item.sentence.isEmpty {
                        Text(item.sentence).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .onDelete { set in
                for i in set {
                    LexiconStore.shared.removeFromVocabulary(all[i].word)
                }
                reload()
            }
        }
    }

    private var reviewCard: some View {
        VStack(spacing: 24) {
            Spacer()
            if index < due.count {
                let item = due[index]
                Text(item.word).font(.system(size: 40, weight: .semibold))
                Button {
                    speaker.speak(item.word)
                } label: { Image(systemName: "speaker.wave.2.fill") }
                .buttonStyle(.borderless)

                if revealed {
                    if let entry = LexiconStore.shared.lookup(item.word) {
                        Text(entry.zh).font(.title3)
                        if let note = entry.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !item.sentence.isEmpty {
                        Text(item.sentence)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    Text("先回忆，再点「看答案」").font(.footnote).foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    if revealed {
                        Button("忘了") { grade(item.word, remembered: false) }
                            .buttonStyle(.bordered)
                        Button("记住了") { grade(item.word, remembered: true) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("看答案") { revealed = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 8)
                Text("\(index + 1) / \(due.count)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("这一轮复习完了").font(.headline)
                Button("回到列表") { reviewing = false; reload() }
            }
            Spacer()
        }
        .padding()
    }

    private func grade(_ word: String, remembered: Bool) {
        LexiconStore.shared.review(word: word, remembered: remembered)
        index += 1
        revealed = false
    }

    private func reload() {
        due = LexiconStore.shared.vocabulary(dueOnly: true)
        all = LexiconStore.shared.vocabulary(dueOnly: false)
    }
}
