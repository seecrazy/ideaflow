import Foundation
import Speech
import AVFoundation

/// 语音转写(DESIGN §4.4):Speech Framework,离线优先(iOS 17 on-device),失败降级保留音频。
@MainActor
final class SpeechTranscriptionService: ObservableObject {
    @Published private(set) var liveText: String = ""
    @Published private(set) var isTranscribing = false
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    /// 流式转写已有音频文件;completion 收到最终文本(失败为 nil,不抛错——保留音频可稍后重试)
    func transcribe(fileURL: URL, locale: Locale = Locale(identifier: "zh-CN"),
                    onUpdate: ((String) -> Void)? = nil,
                    completion: @escaping (String?) -> Void) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized || requestAuth() else {
            // 授权拿不到时同步返回;调用方保留音频
            completion(nil)
            return
        }
        isTranscribing = true
        task = Task { [weak self] in
            let result = await Self.transcribeAsync(fileURL: fileURL, locale: locale, onUpdate: onUpdate)
            await MainActor.run {
                self?.isTranscribing = false
                self?.liveText = result ?? ""
                completion(result)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTranscribing = false
    }

    private func requestAuth() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        SFSpeechRecognizer.requestAuthorization { status in
            ok = (status == .authorized)
            semaphore.signal()
        }
        semaphore.wait()
        return ok
    }

    private static func transcribeAsync(fileURL: URL, locale: Locale,
                                        onUpdate: ((String) -> Void)?) async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false   // 离线模型可用时系统自动走 on-device

        return await withCheckedContinuation { continuation in
            var finished = false
            var handler: SFSpeechRecognitionTask!
            handler = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    onUpdate?(text)
                    if result.isFinal && !finished {
                        finished = true
                        continuation.resume(returning: text)
                    }
                }
                if error != nil, !finished {
                    finished = true
                    continuation.resume(returning: nil)
                }
            }
            if Task.isCancelled {
                handler.cancel()
                if !finished {
                    finished = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
