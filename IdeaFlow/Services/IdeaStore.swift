import Foundation
import CoreData

/// 服务层单通道:所有记录形态收敛到 capture();所有状态变更强制经 transition() 写审计;
/// 回收站软删除 + 保留期清理(DESIGN §4/§5/§13)。
@MainActor
final class IdeaStore: ObservableObject {
    let persistence: PersistenceController
    var ctx: NSManagedObjectContext { persistence.viewContext }

    /// 搜索索引挂钩:保存/编辑/删除后回调,SearchService 注入(Task 6 接线)
    var onIdeaChanged: ((Idea, ChangeKind) -> Void)?
    var onIdeaRemoved: ((UUID) -> Void)?

    enum ChangeKind {
        case created
        case updated
        case statusChanged
    }

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    // MARK: - 记录管道(零必填)

    @discardableResult
    func capture(text: String, tagNames: [String] = [], status: IdeaStatus = .draft) -> Idea? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let idea = Idea.create(in: ctx, title: nil, content: text, status: status)
        applyTags(tagNames, to: idea)
        saveOrRollback()
        onIdeaChanged?(idea, .created)
        return idea
    }

    func updateContent(_ idea: Idea, title: String?, content: String?) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        idea.title = (trimmedTitle?.isEmpty ?? true) ? nil : trimmedTitle
        if let content { idea.content = content }
        idea.updatedAt = Date()
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
    }

    private func applyTags(_ names: [String], to idea: Idea) {
        var seen = Set<String>()
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            idea.tags.insert(Tag.findOrCreate(named: name, in: ctx))
        }
    }

    // MARK: - 状态流转(DESIGN 5.4/5.6:非法流转拒绝,合法流转强制写日志)

    @discardableResult
    func transition(_ idea: Idea, to target: IdeaStatus,
                    source: StatusChangeSource = .manual, note: String? = nil) -> Bool {
        guard idea.status.canTransition(to: target) else { return false }
        let from = idea.status
        idea.status = target
        idea.statusChangedAt = Date()
        idea.updatedAt = Date()
        _ = StatusLog.create(in: ctx, idea: idea, from: from, to: target, source: source, note: note)
        saveOrRollback()
        onIdeaChanged?(idea, .statusChanged)
        return true
    }

    // MARK: - 批量操作(DESIGN 5.7)

    func batchTransition(_ ideas: [Idea], to target: IdeaStatus) {
        for idea in ideas {
            guard idea.status.canTransition(to: target) else { continue }
            let from = idea.status
            idea.status = target
            idea.statusChangedAt = Date()
            idea.updatedAt = Date()
            _ = StatusLog.create(in: ctx, idea: idea, from: from, to: target, source: .batch)
            onIdeaChanged?(idea, .statusChanged)
        }
        saveOrRollback()
    }

    func batchAddTag(_ ideas: [Idea], tagName: String) {
        let tag = Tag.findOrCreate(named: tagName, in: ctx)
        for idea in ideas where !idea.tags.contains(tag) {
            idea.tags.insert(tag)
            idea.updatedAt = Date()
            onIdeaChanged?(idea, .updated)
        }
        saveOrRollback()
    }

    // MARK: - 回收站(DESIGN §13:软删除,30 天清理)

    func softDelete(_ idea: Idea) {
        idea.deletedAt = Date()
        idea.updatedAt = Date()
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
    }

    func restore(_ idea: Idea) {
        idea.deletedAt = nil
        idea.updatedAt = Date()
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
    }

    /// 清理超过保留期的回收站条目,返回清理数量。附件文件一并物理删除。
    @discardableResult
    func purgeExpired(retentionDays: Int = 30, files: AttachmentFiles = AttachmentFiles()) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        let req = Idea.fetchRequest()
        req.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", cutoff as NSDate)
        let expired = try ctx.fetch(req)
        for idea in expired {
            files.removeFiles(for: idea.id)
            ctx.delete(idea)
            onIdeaRemoved?(idea.id)
        }
        saveOrRollback()
        return expired.count
    }

    func destroyNow(_ idea: Idea, files: AttachmentFiles = AttachmentFiles()) {
        files.removeFiles(for: idea.id)
        let id = idea.id
        ctx.delete(idea)
        saveOrRollback()
        onIdeaRemoved?(id)
    }

    // MARK: - 附件挂载(capture 管道收尾:先 capture 得 Idea,再把各形态附件落盘+建实体)

    @discardableResult
    func addImage(_ data: Data, to idea: Idea, media: MediaStore = MediaStore()) throws -> Attachment {
        let saved = try media.saveImage(data, ideaID: idea.id)
        let att = Attachment.create(in: ctx, idea: idea, kind: .image)
        att.localPath = saved.relativePath
        att.thumbnailPath = saved.thumbRelativePath
        att.fileSize = saved.fileSize
        att.mimeType = "image/jpeg"
        att.fileName = (saved.relativePath as NSString).lastPathComponent
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
        return att
    }

    @discardableResult
    func addAudio(at tempURL: URL, to idea: Idea, duration: Double?,
                  transcription: String? = nil, media: MediaStore = MediaStore()) throws -> Attachment {
        let saved = try media.saveAudio(at: tempURL, ideaID: idea.id)
        let att = Attachment.create(in: ctx, idea: idea, kind: .audio)
        att.localPath = saved.relativePath
        att.fileSize = saved.fileSize
        att.duration = saved.duration ?? duration ?? 0
        att.transcription = transcription
        att.mimeType = "audio/mp4"
        att.fileName = (saved.relativePath as NSString).lastPathComponent
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
        return att
    }

    @discardableResult
    func addLink(_ meta: LinkMeta, to idea: Idea) -> Attachment {
        let att = Attachment.create(in: ctx, idea: idea, kind: .link)
        att.linkURL = meta.url.absoluteString
        att.linkTitle = meta.title
        att.linkSummary = meta.summary
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
        return att
    }

    /// 文件/PDF 导入:复制进附件目录(DESIGN §4.4 文件附件)
    @discardableResult
    func addFile(at srcURL: URL, to idea: Idea, media: MediaStore = MediaStore()) throws -> Attachment {
        let secured = srcURL.startAccessingSecurityScopedResource()
        defer { if secured { srcURL.stopAccessingSecurityScopedResource() } }

        let dir = try media.files.ensureDirectory(for: idea.id)
        let dest = dir.appendingPathComponent(srcURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: srcURL, to: dest)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0

        let att = Attachment.create(in: ctx, idea: idea, kind: .file)
        att.localPath = "\(idea.id.uuidString)/\(dest.lastPathComponent)"
        att.fileName = dest.lastPathComponent
        att.fileSize = size ?? 0
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
        return att
    }

    /// 移除附件:实体+物理文件一起删
    func removeAttachment(_ att: Attachment, files: AttachmentFiles = AttachmentFiles()) {
        let idea = att.idea
        if let relative = att.localPath {
            try? FileManager.default.removeItem(at: files.absoluteURL(for: relative))
        }
        ctx.delete(att)
        saveOrRollback()
        if let idea {
            onIdeaChanged?(idea, .updated)
        }
    }

    // MARK: - 置顶与查询

    func togglePin(_ idea: Idea) {
        idea.isPinned.toggle()
        idea.updatedAt = Date()
        saveOrRollback()
        onIdeaChanged?(idea, .updated)
    }

    func fetch(status: IdeaStatus?, limit: Int = 30) throws -> [Idea] {
        try ctx.fetch(Idea.homeFetchRequest(status: status, limit: limit))
    }

    func deletedIdeas() throws -> [Idea] {
        let req = Idea.fetchRequest()
        req.predicate = NSPredicate(format: "deletedAt != nil")
        req.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]
        return try ctx.fetch(req)
    }

    func ideas(matchingIDs ids: [UUID]) throws -> [Idea] {
        guard !ids.isEmpty else { return [] }
        let req = Idea.fetchRequest()
        req.predicate = NSPredicate(format: "id IN %@", ids)
        req.fetchLimit = ids.count
        return try ctx.fetch(req)
    }

    private func saveOrRollback() {
        do {
            try persistence.saveIfNeeded(ctx)
        } catch {
            ctx.rollback()
            assertionFailure("IdeaStore save failed: \(error)")
        }
    }
}
