import AVFoundation
import Foundation

/// German TTS via the system voices (de-DE). No model download needed.
final class Speaker: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    @Published var lastError: String?

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = 0.46
        utterance.postUtteranceDelay = 0.05
        synth.speak(utterance)
        if AVSpeechSynthesisVoice.speechVoices().filter({ $0.language == "de-DE" }).isEmpty {
            lastError = "系统里没有德语语音，去 设置 → 辅助功能 → 朗读内容 下载一个"
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
