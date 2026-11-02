import AVFoundation
import Foundation

/// One audio track for the currently open book, with a 0.25 s tick for sync.
final class AudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Float = 1.0

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// Called on the main queue roughly four times a second while playing.
    var onTick: ((Double) -> Void)?

    func load(url: URL) {
        stopTicker()
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.enableRate = true
        player?.rate = rate
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        current = 0
        isPlaying = false
    }

    func play() {
        guard let player else { return }
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        player.play()
        isPlaying = true
        startTicker()
        tick()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(_ time: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(time, max(0, player.duration - 0.05)))
        current = player.currentTime
        tick()
    }

    func setRate(_ value: Float) {
        rate = value
        player?.rate = value
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let player else { return }
        current = player.currentTime
        onTick?(current)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        stopTicker()
    }
}
