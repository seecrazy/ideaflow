import SwiftUI
import CoreData

/// 标签页(DESIGN §7/9.4):计数、重命名、删除、颜色、层级、进入标签下点子列表。
struct TagsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var tags: [Tag] = []
    @State private var editingTag: Tag?
    @State private var editName = ""
    @State private var editParentID: NSManagedObjectID?
    @State private var editColor: String?
    @State private var confirmDelete: Tag?

    static let palette: [(String, String)] = [
        ("橙", "#E8862E"), ("蓝", "#007AFF"), ("绿", "#34C759"), ("紫", "#AF52DE"),
        ("红", "#FF3B30"), ("灰", "#8E8E93"),
    ]

    var body: some View {
        Group {
            if tags.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("还没有标签").font(.headline)
                    Text("记录时输入 #标签 或在详情页添加").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedTags, id: \.objectID) { tag in
                        NavigationLink {
                            TagIdeasView(tag: tag)
                        } label: {
                            tagRow(tag)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                confirmDelete = tag
                            } label: { Label("删除", systemImage: "trash") }
                            Button {
                                beginEdit(tag)
                            } label: { Label("编辑", systemImage: "pencil") }
                            .tint(Color(env.appTint))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("标签")
        .onAppear { refresh() }
        .alert("编辑标签", isPresented: Binding(get: { editingTag != nil }, set: { if !$0 { editingTag = nil } })) {
            TextField("名称", text: $editName)
            Button("保存") {
                if let tag = editingTag {
                    tag.name = editName.trimmingCharacters(in: .whitespaces)
                    tag.colorHex = editColor
                    let parent = editParentID.flatMap { try? env.store.ctx.existingObject(with: $0) as? Tag }
                    tag.parent = parent
                    try? env.persistence.saveIfNeeded(env.store.ctx)
                    refresh()
                }
                editingTag = nil
            }
            Button("取消", role: .cancel) { editingTag = nil }
        }
        .confirmationDialog("删除标签「\(confirmDelete?.name ?? "")」?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除(点子保留)", role: .destructive) {
                if let tag = confirmDelete {
                    env.store.ctx.delete(tag)
                    try? env.persistence.saveIfNeeded(env.store.ctx)
                    refresh()
                }
                confirmDelete = nil
            }
        } message: {
            Text("标签会从所有点子上移除,点子本身不受影响")
        }
    }

    /// 层级排序:父标签先于子标签,子标签缩进
    private var sortedTags: [Tag] {
        let roots = tags.filter { $0.parent == nil }.sorted { $0.name < $1.name }
        var result: [Tag] = []
        for root in roots {
            result.append(root)
            result.append(contentsOf: root.children.sorted { $0.name < $1.name })
        }
        // 孤儿(父被删后引用悬挂)兜底平铺
        let seen = Set(result.map(\.objectID))
        result.append(contentsOf: tags.filter { !seen.contains($0.objectID) }.sorted { $0.name < $1.name })
        return result
    }

    private func tagRow(_ tag: Tag) -> some View {
        let depth = tag.parent == nil ? 0 : 1
        return HStack {
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Circle()
                .fill(tagColor(tag))
                .frame(width: 10, height: 10)
            Text(tag.name)
                .font(.system(size: 15, weight: depth == 0 ? .medium : .regular))
            Spacer()
            Text("\(tag.ideas.count)")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, depth == 0 ? 0 : 16)
    }

    private func tagColor(_ tag: Tag) -> Color {
        if let hex = tag.colorHex { return Color(hexString: hex) }
        return Color(.systemGray3)
    }

    private func beginEdit(_ tag: Tag) {
        editingTag = tag
        editName = tag.name
        editColor = tag.colorHex
        editParentID = tag.parent?.objectID
    }

    private func refresh() {
        let req = Tag.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        tags = (try? env.store.ctx.fetch(req)) ?? []
    }
}

/// 标签下的点子列表
struct TagIdeasView: View {
    @EnvironmentObject private var env: AppEnvironment
    let tag: Tag
    @State private var ideas: [Idea] = []

    var body: some View {
        List(ideas, id: \.objectID) { idea in
            NavigationLink { DetailView(idea: idea) } label: {
                IdeaCardView(idea: idea)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("#\(tag.name)")
        .onAppear {
            let req = Idea.fetchRequest()
            req.predicate = NSPredicate(format: "deletedAt == nil AND ANY tags.name == %@", tag.name)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            ideas = (try? env.store.ctx.fetch(req)) ?? []
        }
    }
}
