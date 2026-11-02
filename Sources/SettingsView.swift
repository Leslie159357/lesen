import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("ai.baseURL") private var baseURL = "https://api.openai.com/v1"
    @AppStorage("ai.apiKey") private var apiKey = ""
    @AppStorage("ai.model") private var model = "gpt-4o-mini"
    @AppStorage("ai.ttsModel") private var ttsModel = "gpt-4o-mini-tts"
    @AppStorage("ai.ttsVoice") private var ttsVoice = "alloy"
    @AppStorage("ai.targetLang") private var targetLang = "中文"
    @AppStorage("ai.useCloudTTS") private var useCloudTTS = false

    @State private var importing = false
    @State private var notice = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 接口（OpenAI 兼容）") {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("对话模型", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("译文语言", text: $targetLang)
                }

                Section("云 TTS") {
                    Toggle("使用云端音色（离线发音仍可用）", isOn: $useCloudTTS)
                    TextField("TTS 模型", text: $ttsModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("音色", text: $ttsVoice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("词典") {
                    LabeledContent("词条数", value: "\(LexiconStore.shared.count())")
                    Button("导入自定义词表（CSV/TSV）") { importing = true }
                    Text("格式：word,词性,释义,备注 —— 备注列可写变形，用逗号分隔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("状态") {
                    LabeledContent("接口", value: AISettings.shared.isConfigured ? "已配置" : "未配置")
                    LabeledContent("词典引擎", value: "SQLite FTS5")
                    if !notice.isEmpty {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importCSV(url)
                case .failure(let error):
                    notice = error.localizedDescription
                }
            }
        }
    }

    private func importCSV(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            notice = "读不到文件内容"
            return
        }
        let added = LexiconStore.shared.importRows(text)
        notice = added > 0 ? "已导入 \(added) 条" : "没有可导入的行（需要 word,pos,zh,note）"
    }
}
