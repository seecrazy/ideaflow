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

/// 纯附件保存的零必填占位(终审 #1):语音/图片用速记名,链接用其标题
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

/// 底部常驻输入条(DESIGN §4.3):idle → focused → typing → saving → idle;
/// 500ms 节流草稿;工具条 🎤 📷 🔗;零必填,任何内容可直接保存。
struct QuickInputBar: View {
    @EnvironmentObject private var env: AppEnvironment
    @FocusState private var focused: Bool

    @State private var pendings: [PendingAttachment] = []
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var saving = false
    @State private var saveError: String?

    @State private var showVoiceSheet = false
    @State private var showLinkSheet = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                if !pendings.isEmpty { pendingRow }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("记点什么…", text: $env.currentInputText, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("quick_input_field")
                        .onSubmit(save)

                    if focused {
                        toolIcons
                    }
                    saveButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onChange(of: env.currentInputText) { _, text in
            scheduleDraftSave(text)
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { flushDraft() }
        }
        .sheet(isPresented: $showVoiceSheet) {
            VoiceCaptureSheet { pending in
                if let pending { pendings.append(pending) }
                focused = true
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLinkSheet) {
            LinkCaptureSheet(linkService: env.linkService) { meta in
                pendings.append(PendingAttachment(kind: .link(meta)))
                focused = true
            }
            .presentationDetents([.height(220)])
        }
        .alert("保存提示", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            let current = items
            photoItems = []
            Task {
                for item in current {
                    if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                        await MainActor.run { pendings.append(PendingAttachment(kind: .image(data))) }
                    }
                }
                await MainActor.run { focused = true }
            }
        }
    }

    private var pendingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendings) { pending in
                    HStack(spacing: 4) {
                        Text(pending.label)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Button {
                            pendings.removeAll { $0.id == pending.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityLabel("移除附件 \(pending.label)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
            }
        }
    }

    private var toolIcons: some View {
        HStack(spacing: 14) {
            Button { showVoiceSheet = true } label: {
                Image(systemName: "mic.fill").font(.system(size: 18))
            }
            .accessibilityLabel("语音记录")
            .accessibilityIdentifier("tool_mic")

            PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "camera.fill").font(.system(size: 18))
            }
            .accessibilityLabel("添加图片")
            .accessibilityIdentifier("tool_camera")

            Button { showLinkSheet = true } label: {
                Image(systemName: "link").font(.system(size: 18))
            }
            .accessibilityLabel("收藏链接")
            .accessibilityIdentifier("tool_link")
        }
        .foregroundStyle(Color(env.appTint))
        .padding(.bottom, 6)
    }

    private var saveButton: some View {
        Button(action: save) {
            if saving {
                ProgressView().frame(width: 20, height: 20)
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSave ? Color(env.appTint) : Color(.tertiaryLabel))
            }
        }
        .disabled(!canSave || saving)
        .accessibilityLabel("保存灵感")
        .accessibilityIdentifier("quick_save")
        .padding(.bottom, 2)
    }

    private var canSave: Bool {
        !env.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendings.isEmpty
    }

    private func save() {
        guard canSave, !saving else { return }
        saving = true
        var text = env.currentInputText
        let toAttach = pendings
        // 零必填(DESIGN §4.4):纯附件无文本时用占位,不许静默丢
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = QuickCapture.placeholderText(for: toAttach)
        }

        guard let idea = env.store.capture(text: text) else {
            saving = false
            return
        }
        var failed: [PendingAttachment] = []
        for pending in toAttach {
            switch pending.kind {
            case .image(let data):
                if (try? env.store.addImage(data, to: idea, media: env.mediaStore)) == nil {
                    failed.append(pending)
                }
            case .audio(let url, let duration, let transcription):
                if (try? env.store.addAudio(at: url, to: idea, duration: duration,
                                            transcription: transcription, media: env.mediaStore)) == nil {
                    failed.append(pending)
                }
            case .link(let meta):
                env.store.addLink(meta, to: idea)
            }
        }
        saving = false
        if failed.isEmpty {
            withAnimation(.spring(response: 0.25)) {
                env.currentInputText = ""
                pendings = []
                focused = false
            }
            env.draftService.clear()
            draftSaveTask?.cancel()
            env.pendingDraftText = nil
        } else {
            // 落盘失败:保留未成功附件与文本,明示用户(不许无声丢失)
            pendings = failed
            saveError = "有 \(failed.count) 个附件保存失败,已保留在待提交区,可重试"
        }
    }

    // MARK: - 草稿(DESIGN §4.3:500ms 节流 + 失焦立即)

    private func scheduleDraftSave(_ text: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            env.draftService.save(text: text)
        }
    }

    private func flushDraft() {
        draftSaveTask?.cancel()
        env.draftService.save(text: env.currentInputText)
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
