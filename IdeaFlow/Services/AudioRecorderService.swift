import Foundation
import AVFoundation

/// 录音服务(DESIGN §4.4):AVAudioRecorder + 电平回调;来电等中断时保存已录部分(DESIGN §13)。
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case paused
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var averagePower: Float = -60   // dB,驱动波形动画
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var currentURL: URL?

    var onFinished: ((URL, TimeInterval) -> Void)?

    private static func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ideaflow-rec-\(UUID().uuidString).m4a")
    }

    func requestPermissionAndStart() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        let granted = await withCheckedContinuation { cont in
            session.requestRecordPermission { ok in cont.resume(returning: ok) }
        }
        guard granted else { return false }
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let url = Self.tempFileURL()
            let recorder = try AVAudioRecorder(url: url, settings: MediaStore.audioSettings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
            self.currentURL = url
            state = .recording
            startLevelTimer()
            return true
        } catch {
            stopTracking()
            return false
        }
    }

    /// 停止并回调已录音频(中断/正常停止共用;DESIGN §13 来电中断保存已录部分)
    func stop() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        let duration = recorder.currentTime
        finish(with: url, duration: duration)
    }

    func cancel() {
        recorder?.stop()
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
        }
        stopTracking()
    }

    private func finish(with url: URL, duration: TimeInterval) {
        let callback = onFinished
        stopTracking()
        callback?(url, max(0, duration))
    }

    private func stopTracking() {
        levelTimer?.invalidate()
        levelTimer = nil
        recorder = nil
        currentURL = nil
        state = .idle
        elapsed = 0
        averagePower = -60
    }

    private func startLevelTimer() {
        levelTimer?.invalidate()
        let start = Date()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.averagePower = recorder.averagePower(forChannel: 0)
                self.elapsed = -start.timeIntervalSinceNow
            }
        }
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard flag else {
                // 异常结束:保留已录部分
                self.finish(with: recorder.url, duration: recorder.currentTime)
                return
            }
        }
    }
}
