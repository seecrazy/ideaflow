import SwiftUI
import PhotosUI

/// 半屏速记面板:点首页入口条弹出,所有记录形态在此完成。
/// 标题可选;正文多行;待提交附件横排;底部工具行 📷 🎤 🔗 📎 常驻 + 保存。
struct QuickCaptureSheet: View {
    enum EntryAction {
        case none, link
    }

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    /// 打开面板时预挂的附件(入口条 🎤/📷 采集完直通)
    var entryAttachments: [PendingAttachment] = []
    var entryAction: EntryAction = .none

    @State private var titleText = ""
    @State private var contentText = ""
    @State private var pendings: [PendingAttachment] = []
    @State private var saving = false
    @State private var saveError: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var showVoice = false
    @State private var showLink = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var contentFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 10)

            TextField("标题(可选)", text: $titleText)
                .font(.system(size: 18, weight: .semibold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 18)
                .accessibilityIdentifier("capture_title")

            TextEditor(text: $contentText)
                .focused($contentFocused)
                .font(.system(size: 16))
                .frame(minHeight: 120, alignment: .topLeading)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
                .accessibilityIdentifier("capture_content")
                .onChange(of: contentText) { _, text in
                    env.currentInputText = text
                    scheduleDraftSave(text)
                }

            if !pendings.isEmpty { pendingRow }

            toolBar

            if saveError != nil {
                Text(saveError!)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(saving)
        .onAppear {
            contentText = env.currentInputText
            pendings.append(contentsOf: entryAttachments)
            switch entryAction {
            case .link:
                showLink = true
            case .none:
                contentFocused = true
            }
        }
        .onDisappear {
            flushDraft()
        }
        .sheet(isPresented: $showVoice) {
            VoiceCaptureSheet { pending in
                if let pending { pendings.append(pending) }
            }
            .presentationDetents([.medium])
            .environmentObject(env)
        }
        .sheet(isPresented: $showLink) {
            LinkCaptureSheet(linkService: env.linkService) { meta in
                pendings.append(PendingAttachment(kind: .link(meta)))
            }
            .presentationDetents([.height(240)])
        }
        .alert("保存提示", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - 待提交附件(灵感本体的一部分,不是消息附件)

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
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 工具行(常驻:这不是聊天发送器,是灵感捕捉台)

    private var toolBar: some View {
        HStack(spacing: 22) {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "camera.fill").font(.system(size: 20))
            }
            .accessibilityLabel("添加图片")

            Button { showVoice = true } label: {
                Image(systemName: "mic.fill").font(.system(size: 20))
            }
            .accessibilityLabel("录语音")

            Button { showLink = true } label: {
                Image(systemName: "link").font(.system(size: 20))
            }
            .accessibilityLabel("收藏链接")

            Spacer()

            Button(action: save) {
                if saving {
                    ProgressView().frame(width: 22, height: 22)
                } else {
                    Text("保存")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(canSave ? Color(env.appTint) : Color(.tertiarySystemFill)))
                        .foregroundStyle(canSave ? Color.white : Color(.tertiaryLabel))
                }
            }
            .disabled(!canSave || saving)
            .accessibilityIdentifier("capture_save")
        }
        .foregroundStyle(Color(env.appTint))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
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
            }
        }
    }

    private var canSave: Bool {
        !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendings.isEmpty
    }

    // MARK: - 保存(零必填 + 失败保留)

    private func save() {
        guard canSave, !saving else { return }
        saving = true
        var text = [titleText.trimmingCharacters(in: .whitespacesAndNewlines),
                    contentText].filter { !$0.isEmpty }.joined(separator: "\n")
        let toAttach = pendings
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
            env.currentInputText = ""
            env.draftService.clear()
            draftTask?.cancel()
            env.pendingDraftText = nil
            dismiss()
        } else {
            pendings = failed
            saveError = "有 \(failed.count) 个附件保存失败,已保留在待提交区,可重试"
        }
    }

    // MARK: - 草稿(500ms 节流 + 面板关闭即存)

    private func scheduleDraftSave(_ text: String) {
        draftTask?.cancel()
        draftTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            env.draftService.save(text: text)
        }
    }

    private func flushDraft() {
        draftTask?.cancel()
        env.draftService.save(text: contentText.isEmpty ? env.currentInputText : contentText)
    }
}
