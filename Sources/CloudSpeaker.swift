import AVFoundation
import Foundation

/// Plays cloud TTS audio (mp3 bytes from an OpenAI-compatible /audio/speech).
final class CloudSpeaker: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isBusy = false
    @Published var errorText: String?

    private var player: AVAudioPlayer?

    func speak(_ text: String, settings: AISettings = .shared) {
        guard !text.isEmpty else { return }
        isBusy = true
        errorText = nil
        Task { @MainActor in
            do {
                let data = try await settings.synthesize(text)
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player?.stop()
                self.player = player
                player.play()
                self.isBusy = false
            } catch {
                self.errorText = error.localizedDescription
                self.isBusy = false
            }
        }
    }

    func stop() {
        player?.stop()
        isBusy = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isBusy = false
    }
}
