import SwiftUI
import CoreData
import PhotosUI

/// 详情页(DESIGN 9.2):状态胶囊流转、标题/正文编辑、附件区、标签、状态日志。
struct DetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var idea: Idea
    @StateObject private var audioPlayer = AudioPlayerService()

    @State private var titleText: String = ""
    @State private var contentText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var logsExpanded = false
    @State private var newTagName = ""
    @State private var transitionNoteTarget: IdeaStatus?
    @State private var noteText = ""
    @State private var showDetailVoice = false
    @State private var showDetailLink = false
    @State private var showDocPicker = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusBar
                titleEditor
                contentEditor
                attachmentSection
                tagSection
                logSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("点子详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .confirmationDialog("转\(transitionNoteTarget?.displayName ?? "")", isPresented: Binding(
            get: { transitionNoteTarget != nil },
            set: { if !$0 { transitionNoteTarget = nil; noteText = "" } }
        ), titleVisibility: .visible) {
            TextField("备注(可选,为什么改状态)", text: $noteText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("确认流转") {
                if let target = transitionNoteTarget {
                    _ = env.store.transition(idea, to: target, note: noteText.isEmpty ? nil : noteText)
                }
                transitionNoteTarget = nil
                noteText = ""
            }
            Button("取消", role: .cancel) { transitionNoteTarget = nil }
        }
        .onAppear {
            titleText = idea.title ?? ""
            contentText = idea.content ?? ""
        }
        .sheet(isPresented: $showDetailVoice) {
            VoiceCaptureSheet { pending in
                guard let pending else { return }
                if case .audio(let url, let duration, let transcription) = pending.kind {
                    _ = try? env.store.addAudio(at: url, to: idea, duration: duration,
                                                 transcription: transcription, media: env.mediaStore)
                }
            }
            .presentationDetents([.medium])
            .environmentObject(env)
        }
        .sheet(isPresented: $showDetailLink) {
            LinkCaptureSheet(linkService: env.linkService) { meta in
                env.store.addLink(meta, to: idea)
            }
            .presentationDetents([.height(240)])
        }
        .sheet(isPresented: $showDocPicker) {
            DocumentPickerSheet { urls in
                for url in urls {
                    _ = try? env.store.addFile(at: url, to: idea, media: env.mediaStore)
                }
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            let current = items
            photoItems = []
            Task {
                for item in current {
                    if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                        _ = try? env.store.addImage(data, to: idea, media: env.mediaStore)
                    }
                }
            }
        }
    }

    // MARK: - 状态胶囊

    private var statusBar: some View {
        HStack {
            Menu {
                ForEach(idea.status.allowedTransitions, id: \.self) { target in
                    Button {
                        transitionNoteTarget = target
                    } label: {
                        Label("转\(target.displayName)", systemImage: target.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(idea.status.swiftUIColor).frame(width: 8, height: 8)
                    Text(idea.status.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(idea.status.swiftUIColor.opacity(0.14)))
                .foregroundStyle(idea.status.swiftUIColor)
            }
            .accessibilityIdentifier("status_capsule")

            Text("创建于 \(RelativeTime.string(from: idea.createdAt))")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - 编辑

    private var titleEditor: some View {
        TextField("标题(留空自动取首行)", text: $titleText, axis: .vertical)
            .font(.system(size: 20, weight: .semibold))
            .textFieldStyle(.plain)
            .onChange(of: titleText) { _, _ in scheduleSave() }
            .accessibilityIdentifier("detail_title")
    }

    private var contentEditor: some View {
        TextEditor(text: $contentText)
            .font(.system(size: 16))
            .frame(minHeight: 120, alignment: .topLeading)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            .onChange(of: contentText) { _, _ in scheduleSave() }
            .accessibilityIdentifier("detail_content")
    }

    private func remainingDays() -> Int {
        let retention = UserDefaults.standard.integer(forKey: "recycleRetentionDays")
        return retention > 0 ? retention : 30
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let title = titleText
        let content = contentText
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            env.store.updateContent(idea, title: title, content: content)
        }
    }

    // MARK: - 附件区

    @ViewBuilder
    private var attachmentSection: some View {
        let images = idea.attachments.filter { $0.kind == .image }.sorted { $0.createdAt < $1.createdAt }
        let audios = idea.attachments.filter { $0.kind == .audio }.sorted { $0.createdAt < $1.createdAt }
        let links = idea.attachments.filter { $0.kind == .link }.sorted { $0.createdAt < $1.createdAt }
        let files = idea.attachments.filter { $0.kind == .file || $0.kind == .video }.sorted { $0.createdAt < $1.createdAt }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "paperclip", title: "附件 (\(idea.attachments.count))", trailing: {
                addAttachmentMenu
            })
                if !images.isEmpty { imageGrid(images) }
                ForEach(audios, id: \.objectID) { audio in
                    AudioRow(att: audio, player: audioPlayer)
                }
                ForEach(links, id: \.objectID) { link in
                    LinkCard(att: link)
                        .attachmentRemoval(link, env: env)
                }
            ForEach(files, id: \.objectID) { file in
                FileRow(att: file)
                    .attachmentRemoval(file, env: env)
            }
        }
    }

    private func imageGrid(_ images: [Attachment]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(images, id: \.objectID) { att in
                ThumbnailView(att: att)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .attachmentRemoval(att, env: env)
            }
        }
    }

    /// 附件追加菜单:语音 / 图片 / 链接 / 文件(DESIGN §8 附件管理)
    private var addAttachmentMenu: some View {
        Menu {
            Button {
                showDetailVoice = true
            } label: {
                Label("录语音", systemImage: "mic.fill")
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                Label("拍照或相册", systemImage: "camera.fill")
            }
            Button {
                showDetailLink = true
            } label: {
                Label("链接", systemImage: "link")
            }
            Button {
                showDocPicker = true
            } label: {
                Label("文件 / PDF", systemImage: "doc.fill")
            }
        } label: {
            Label("添加", systemImage: "plus.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(env.appTint))
        }
    }

    // MARK: - 标签

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "tag", title: "标签")
            FlowTags(tags: idea.tags.sorted { $0.name < $1.name }, onRemove: { tag in
                idea.tags.remove(tag)
                try? env.persistence.saveIfNeeded(env.store.ctx)
            })
            HStack {
                TextField("新标签", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("new_tag_field")
                Button("添加") {
                    let name = newTagName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    env.store.batchAddTag([idea], tagName: name)
                    newTagName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - 状态日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { logsExpanded.toggle() }
            } label: {
                SectionHeader(icon: "clock.arrow.circlepath", title: "状态变更日志 (\(idea.statusLogs.count))") {
                    Image(systemName: logsExpanded ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)
            if logsExpanded {
                let logs = idea.statusLogs.sorted { $0.timestamp > $1.timestamp }
                if logs.isEmpty {
                    Text("暂无流转记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                ForEach(logs, id: \.objectID) { log in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(log.to.swiftUIColor).frame(width: 6, height: 6).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(log.from.displayName) → \(log.to.displayName)")
                                .font(.system(size: 13, weight: .medium))
                            HStack(spacing: 6) {
                                Text(RelativeTime.string(from: log.timestamp))
                                Text("· \(log.source.displayName)")
                                if let note = log.note, !note.isEmpty {
                                    Text("· \(note)")
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    env.store.togglePin(idea)
                } label: {
                    Label(idea.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                }
                ShareLink(item: ExportService.markdown(ideas: [idea]),
                          subject: Text(idea.displayTitle)) {
                    Label("分享(Markdown)", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    env.recycleToast = RecycleToast(
                        message: "已移到回收站,\(remainingDays()) 天内可恢复",
                        objectIDs: [idea.objectID]
                    )
                    Haptics.warning()
                    try? env.store.softDelete(idea)
                    dismiss()   // 删除必须可见:立刻回到列表看到它消失
                } label: {
                    Label("移到回收站", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多操作")
        }
    }
}

// MARK: - 子组件

struct SectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let trailing: Trailing

    init(icon: String, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            trailing
        }
        .foregroundStyle(.secondary)
    }
}

struct ThumbnailView: View {
    @ObservedObject var att: Attachment
    @State private var ui: UIImage?

    var body: some View {
        Group {
            if let ui {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color(.tertiarySystemFill))
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
        }
        .task(id: att.objectID) {
            // 后台解码,主线程只收结果(DESIGN §12;终审 #7)
            guard let thumb = att.thumbnailPath else { return }
            let abs = AttachmentFiles().absoluteURL(for: thumb).path
            ui = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.image(atPath: abs)
            }.value
        }
    }
}

struct AudioRow: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var att: Attachment
    @ObservedObject var player: AudioPlayerService
    @State private var expandedTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    player.toggle(att)
                } label: {
                    Image(systemName: player.playingAttachmentID == att.id ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color(env.appTint))
                }
                .accessibilityLabel(player.playingAttachmentID == att.id ? "暂停" : "播放")

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "语音 %.0f 秒", max(1, att.duration)))
                        .font(.system(size: 14, weight: .medium))
                    if player.playingAttachmentID == att.id {
                        ProgressView(value: player.progress)
                            .tint(Color(env.appTint))
                    }
                }
                Spacer()
                if att.transcription != nil {
                    Button(expandedTranscript ? "收起" : "转写") {
                        withAnimation { expandedTranscript.toggle() }
                    }
                    .font(.system(size: 13))
                }
            }
            if expandedTranscript, let t = att.transcription {
                Text(t)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct LinkCard: View {
    @ObservedObject var att: Attachment

    var body: some View {
        Group {
            if let urlString = att.linkURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    linkBody
                }
                .buttonStyle(.plain)
            } else {
                linkBody
            }
        }
    }

    private var linkBody: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(att.linkTitle ?? att.linkURL ?? "链接")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if let host = URL(string: att.linkURL ?? "")?.host {
                    Text(host)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// 标签流式布局:横向滚动
struct FlowTags: View {
    let tags: [Tag]
    var onRemove: (Tag) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.objectID) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag.name)")
                            .font(.system(size: 13, weight: .medium))
                        Button {
                            onRemove(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .accessibilityLabel("删除标签 \(tag.name)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
            }
        }
    }
}

/// 文件附件行
struct FileRow: View {
    @ObservedObject var att: Attachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(att.fileName ?? "文件")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: att.fileSize, countStyle: .file))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// 附件移除:长按菜单(网格/卡片内 swipe 不可用)
struct AttachmentRemovalModifier: ViewModifier {
    @ObservedObject var att: Attachment
    let env: AppEnvironment

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(role: .destructive) {
                env.store.removeAttachment(att)
            } label: {
                Label("移除附件", systemImage: "trash")
            }
        }
    }
}

extension View {
    func attachmentRemoval(_ att: Attachment, env: AppEnvironment) -> some View {
        modifier(AttachmentRemovalModifier(att: att, env: env))
    }
}

/// UIDocumentPickerViewController 桥:选文件以副本导入
struct DocumentPickerSheet: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
