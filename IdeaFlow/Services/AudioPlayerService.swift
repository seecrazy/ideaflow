import Foundation
import AVFoundation

/// 附件音频播放:单例式会话,播完即释放(DESIGN §12.4)
@MainActor
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingAttachmentID: UUID?
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var currentID: UUID?

    func toggle(_ attachment: Attachment, files: AttachmentFiles = AttachmentFiles()) {
        if playingAttachmentID == attachment.id {
            pause()
            return
        }
        pause()
        guard let path = attachment.localPath else { return }
        let url = files.absoluteURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            currentID = attachment.id
            playingAttachmentID = attachment.id
            startTimer()
        } catch {
            player = nil
            playingAttachmentID = nil
        }
    }

    func pause() {
        player?.pause()
        player = nil
        timer?.invalidate()
        timer = nil
        playingAttachmentID = nil
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.pause()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.progress = player.currentTime / player.duration
            }
        }
    }
}
