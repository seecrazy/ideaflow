import SwiftUI
import CoreData

/// 首页(DESIGN 9.1):状态筛选 Chips + 卡片流 + 草稿恢复条 + 底部常驻输入条;
/// 左滑快捷操作;长按进入多选批量。
struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedStatus: IdeaStatus?
    @State private var ideas: [Idea] = []
    @State private var limit = 30
    @State private var multiSelectActive = false
    @State private var selectedIDs: Set<NSManagedObjectID> = []
    private final class ObserverBox { var token: NSObjectProtocol? }
    @State private var observerBox = ObserverBox()
    @State private var autoPushDetail = ProcessInfo.processInfo.arguments.contains("-openDetail")
    @State private var showDraftCapture = false
    @State private var voiceTargetIdea: Idea?
    @State private var autoPushRecycle = ProcessInfo.processInfo.arguments.contains("-openRecycle")

    private let pageSize = 30

    var body: some View {
        Group {
            if multiSelectActive {
                multiSelectList
            } else {
                normalList
            }
        }
        .navigationTitle("灵感集")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !multiSelectActive {
                QuickEntryBar()
            } else {
                MultiSelectBar(selectedCount: selectedIDs.count,
                               statusMenu: AnyView(batchStatusMenu),
                               onDone: { exitMultiSelect() },
                               onDelete: { batchDelete() })
            }
        }
        .toolbar {
            if multiSelectActive {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { exitMultiSelect() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selectedIDs.count == visibleCount ? "取消全选" : "全选") {
                        if selectedIDs.count == visibleCount {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(ideas.map(\.objectID))
                        }
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { RecycleBinView() } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("回收站")
                }
            }
        }
        .onAppear {
            refresh()
            installSaveObserver()
        }
        .navigationDestination(isPresented: $autoPushDetail) {
            // 截图/演示:优先推附件最丰富的条目,展示附件区与日志
            if let richest = ideas.first(where: { !$0.attachments.isEmpty }) ?? ideas.first {
                DetailView(idea: richest)
            } else {
                Text("暂无数据")
            }
        }
        .navigationDestination(isPresented: $autoPushRecycle) {
            RecycleBinView()
        }
        .sheet(isPresented: $showDraftCapture) {
            QuickCaptureSheet(entryAttachments: [], entryAction: .none)
                .environmentObject(env)
        }
        .sheet(item: $voiceTargetIdea) { idea in
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
        .onDisappear {
            if let token = observerBox.token {
                NotificationCenter.default.removeObserver(token)
            }
            observerBox.token = nil   // 置空,onAppear 的 guard 才能重装
        }
    }

    // MARK: - 常规列表

    private var normalList: some View {
        List {
            if let draft = env.pendingDraftText {
                DraftBanner(text: draft) {
                    env.currentInputText = draft
                    env.pendingDraftText = nil
                    showDraftCapture = true
                } onDiscard: {
                    env.draftService.clear()
                    env.pendingDraftText = nil
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }

            chipsRow

            if ideas.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
            } else {
                ForEach(ideas, id: \.objectID) { idea in
                    NavigationLink {
                        DetailView(idea: idea)
                    } label: {
                        IdeaCardView(idea: idea)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            swipeDelete(idea)
                        } label: { Label("删除", systemImage: "trash") }
                        if idea.status == .draft {
                            Button {
                                voiceTargetIdea = idea
                            } label: {
                                Label("补语音", systemImage: "mic.badge.plus")
                            }
                            .tint(Color(env.appTint))
                        }
                        quickAction(for: idea)
                    }
                    .contextMenu {
                        Button {
                            env.store.togglePin(idea)
                            refresh()
                        } label: {
                            Label(idea.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                        }
                        Button {
                            Haptics.tap()
                            multiSelectActive = true
                            selectedIDs = [idea.objectID]
                        } label: {
                            Label("多选", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            swipeDelete(idea)
                        } label: {
                            Label("移到回收站", systemImage: "trash")
                        }
                    }
                    .accessibilityIdentifier("idea_card_\(idea.id.uuidString)")
                    .onAppear {
                        if idea == ideas.last { loadMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("home_idea_list")
    }

    // MARK: - 多选列表

    private var multiSelectList: some View {
        List(ideas, id: \.objectID) { idea in
            Button {
                if selectedIDs.contains(idea.objectID) {
                    selectedIDs.remove(idea.objectID)
                } else {
                    selectedIDs.insert(idea.objectID)
                }
            } label: {
                IdeaCardView(idea: idea, isInMultiSelect: true,
                             isSelected: selectedIDs.contains(idea.objectID))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private var visibleCount: Int { ideas.count }

    private func exitMultiSelect() {
        multiSelectActive = false
        selectedIDs.removeAll()
    }

    private func selectedIdeas() -> [Idea] {
        ideas.filter { selectedIDs.contains($0.objectID) }
    }

    private func batchDelete() {
        let targets = selectedIdeas()
        Haptics.warning()
        for idea in targets {
            try? env.store.softDelete(idea)
        }
        if !targets.isEmpty {
            env.recycleToast = RecycleToast(
                message: "已删除 \(targets.count) 条,可撤销",
                objectIDs: targets.map(\.objectID)
            )
        }
        exitMultiSelect()
        withAnimation(.spring(response: 0.3)) { refresh() }
    }

    private func swipeDelete(_ idea: Idea) {
        env.recycleToast = RecycleToast(
            message: "已移到回收站,可撤销",
            objectIDs: [idea.objectID]
        )
        try? env.store.softDelete(idea)
        withAnimation(.spring(response: 0.3)) { refresh() }
    }

    @ViewBuilder
    private var batchStatusMenu: some View {
        Menu {
            ForEach(IdeaStatus.allCases, id: \.self) { status in
                Button(status.displayName) {
                    env.store.batchTransition(selectedIdeas(), to: status)
                    exitMultiSelect()
                    refresh()
                }
            }
        } label: {
            Label("改状态", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - 筛选 Chips(DESIGN 9.1)

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", selected: selectedStatus == nil) {
                    selectedStatus = nil; refresh()
                }
                ForEach([IdeaStatus.draft, .pending, .adopted, .rejected, .abandoned], id: \.self) { status in
                    chip(title: status.displayName, selected: selectedStatus == status) {
                        selectedStatus = status; refresh()
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("status_chips")
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Color(env.appTint) : Color(.tertiarySystemFill))
                )
                .foregroundStyle(selected ? Color.white : Color(.label))
        }
        .accessibilityIdentifier("chip_\(title)")
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("还没有灵感")
                .font(.headline)
            Text("在下方输入条随手记一条吧")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func quickAction(for idea: Idea) -> some View {
        // 左滑快捷:当前状态最高频的下一跳(DESIGN 5.5)
        let target: IdeaStatus
        switch idea.status {
        case .draft: target = .pending
        case .pending: target = .adopted
        case .adopted: target = .archived
        case .rejected: target = .draft
        case .abandoned: target = .pending
        case .archived: target = .draft
        }
        return Button {
            _ = env.store.transition(idea, to: target, source: .quickAction)
            refresh()
        } label: {
            Label("转\(target.displayName)", systemImage: target.iconName)
        }
        .tint(target.swiftUIColor)
    }

    // MARK: - 数据

    private func refresh() {
        ideas = (try? env.store.fetch(status: selectedStatus, limit: limit)) ?? []
    }

    private func loadMore() {
        guard ideas.count >= limit else { return }
        limit += pageSize
        refresh()
    }

    private func installSaveObserver() {
        guard observerBox.token == nil else { return }
        observerBox.token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: env.persistence.viewContext,
            queue: .main
        ) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.3)) {
                    self.refresh()
                }
            }
        }
    }
}

/// 草稿恢复条(DESIGN §4.3)
struct DraftBanner: View {
    let text: String
    var onContinue: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.and.list.clipboard")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("有未完成的记录")
                    .font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("继续", action: onContinue)
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.bordered)
            Button("放弃", action: onDiscard)
                    .font(.system(size: 14))
                    .buttonStyle(.bordered)
                    .tint(.red)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        .accessibilityIdentifier("draft_banner")
    }
}

/// 多选工具栏(DESIGN 5.7)
struct MultiSelectBar: View {
    let selectedCount: Int
    var statusMenu: AnyView
    var onDone: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Text("已选 \(selectedCount) 项")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            statusMenu
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
            .disabled(selectedCount == 0)
            Button("完成", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityIdentifier("multi_select_bar")
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
