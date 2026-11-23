import SwiftUI
import PhotosUI

/// 待提交附件:保存时经 capture 管道一起落盘
struct PendingAttachment: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case image(Data)
        case audio(URL, duration: Double, transcription: String?)
        case link(LinkMeta)
    }

    var label: String {
        switch kind {
        case .image: return "📷 图片"
        case .audio(_, let duration, let transcription):
            return transcription == nil ? "🎤 \(Int(duration))s" : "🎤 \(Int(duration))s·已转写"
        case .link(let meta): return "🔗 \(meta.title)"
        }
    }
}

/// 纯附件保存的零必填占位:语音/图片用速记名,链接用其标题
enum QuickCapture {
    static func placeholderText(for pendings: [PendingAttachment]) -> String {
        for pending in pendings {
            if case .link(let meta) = pending.kind, !meta.title.isEmpty {
                return meta.title
            }
        }
        if pendings.contains(where: { if case .image = $0.kind { return true }; return false }) {
            return "图片速记"
        }
        if pendings.contains(where: { if case .audio = $0.kind { return true }; return false }) {
            return "语音速记"
        }
        return ""
    }
}

/// 首页常驻入口条(捕捉隐喻,非聊天框):点文本区开速记面板;
/// 🎤 直达录音、录完进面板预挂;📷 相册选完进面板预挂;🔗 进面板直弹链接输入。
struct QuickEntryBar: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var showCapture = false
    @State private var entryAttachments: [PendingAttachment] = []
    @State private var entryAction: QuickCaptureSheet.EntryAction = .none
    @State private var showVoice = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Button {
                    openCapture([], action: .none)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16))
                        Text("记点什么…")
                            .font(.system(size: 16))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .accessibilityIdentifier("quick_entry_bar")
                .buttonStyle(.plain)

                Button {
                    showVoice = true
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 28))
                }
                .foregroundStyle(Color(env.appTint))
                .accessibilityLabel("语音速记")

                PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 28))
                }
                .foregroundStyle(Color(env.appTint))
                .accessibilityLabel("拍照速记")

                Button {
                    openCapture([], action: .link)
                } label: {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 28))
                }
                .foregroundStyle(Color(env.appTint))
                .accessibilityLabel("收藏链接")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(isPresented: $showVoice) {
            VoiceCaptureSheet { pending in
                guard let pending else { return }
                openCapture([pending], action: .none)
            }
            .presentationDetents([.medium])
            .environmentObject(env)
        }
        .sheet(isPresented: $showCapture) {
            QuickCaptureSheet(entryAttachments: entryAttachments, entryAction: entryAction)
                .environmentObject(env)
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            let current = items
            photoItems = []
            Task {
                var images: [PendingAttachment] = []
                for item in current {
                    if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                        images.append(PendingAttachment(kind: .image(data)))
                    }
                }
                guard !images.isEmpty else { return }
                await MainActor.run {
                    openCapture(images, action: .none)
                }
            }
        }
    }

    private func openCapture(_ attachments: [PendingAttachment],
                             action: QuickCaptureSheet.EntryAction) {
        entryAttachments = attachments
        entryAction = action
        showCapture = true
    }
}


// MARK: - 语音录制 Sheet

struct VoiceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var recorder = AudioRecorderService()
    @StateObject private var speech = SpeechTranscriptionService()
    @State private var stoppedURL: URL?
    @State private var stoppedDuration: Double = 0
    @State private var transcription: String?
    @State private var transcribing = false
    @State private var levels: [Float] = Array(repeating: -60, count: 24)

    var onDone: (PendingAttachment?) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 10)

            if recorder.state == .recording {
                Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .font(.system(size: 40, weight: .medium, design: .monospaced))
                waveform
            } else if let stoppedURL {
                Text(String(format: "已录制 %.0f 秒", max(1, stoppedDuration)))
                    .font(.headline)
                if let transcription {
                    Text(transcription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.horizontal)
                }
                transcribeButton
            } else {
                Text("语音速记")
                    .font(.headline)
                Text("点击开始,说话即可;支持稍后转写")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            controls
        }
        .frame(maxWidth: .infinity)
        .onReceive(recorder.$averagePower) { power in
            levels.removeFirst()
            levels.append(power)
        }
        .onAppear {
            recorder.onFinished = { url, duration in
                stoppedURL = url
                stoppedDuration = duration
            }
        }
        .interactiveDismissDisabled(recorder.state == .recording)
    }

    private var waveform: some View {
        let tint = Color(env.appTintForShared).opacity(0.85)
        return HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                WaveBar(level: levels[i], tint: tint)
            }
        }
        .frame(height: 50)
    }

    private var transcribeButton: some View {
        Button {
            guard let url = stoppedURL else { return }
            transcribing = true
            speech.transcribe(fileURL: url) { text in
                transcribing = false
                transcription = text
            }
        } label: {
            Label(transcription == nil ? "转写为文字" : "重新转写",
                  systemImage: "text.bubble")
                .font(.subheadline)
        }
        .disabled(transcribing)
        .overlay { if transcribing { ProgressView().scaleEffect(0.7) } }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button(role: .destructive) {
                recorder.cancel()
                onDone(nil)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.red.opacity(0.85))
            }
            .accessibilityLabel("取消录音")

            if recorder.state != .recording {
                Button {
                    Task {
                        await recorder.requestPermissionAndStart()
                    }
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color(env.appTintForShared))
                }
                .accessibilityLabel("开始录音")
            } else {
                Button {
                    recorder.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("停止录音")
            }

            if stoppedURL != nil {
                Button {
                    recorder.cancel()
                    onDone(PendingAttachment(kind: .audio(stoppedURL!, duration: stoppedDuration, transcription: transcription)))
                    dismiss()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("使用这段录音")
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 链接收藏 Sheet

struct LinkCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var loading = false

    let linkService: LinkMetadataService
    var onDone: (LinkMeta) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 10)
            Text("收藏链接").font(.headline)

            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.tertiary)
                TextField("粘贴或输入网址", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("link_url_field")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))

            if loading {
                ProgressView("正在抓取标题…")
            }

            Button {
                guard let url = normalizedURL() else { return }
                loading = true
                Task {
                    let meta = await linkService.fetchMetadata(for: url)
                    await MainActor.run {
                        loading = false
                        onDone(meta)
                        dismiss()
                    }
                }
            } label: {
                Text("收藏")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(normalizedURL() == nil || loading)

            if let pasted = UIPasteboard.general.string, let url = URL(string: pasted), url.scheme?.hasPrefix("http") == true {
                Button("使用剪贴板:\(url.host ?? "")") {
                    urlText = pasted
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    private func normalizedURL() -> URL? {
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://" + text
        }
        return URL(string: text).flatMap { $0.host != nil ? $0 : nil }
    }
}

extension AppEnvironment {
    var appTintForShared: UIColor { appTint }
}

/// 单根波形条:电平(dB)映射到 4–46pt 高度
struct WaveBar: View {
    let level: Float
    let tint: Color

    var height: CGFloat {
        let clamped = max(-60, min(0, level))
        return CGFloat(4 + (clamped + 60) * 0.7)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(tint)
            .frame(width: 5, height: height)
    }
}
