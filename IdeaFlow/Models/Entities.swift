import Foundation
import CoreData

// MARK: - 附件形态

enum AttachmentKind: Int16, CaseIterable, Codable {
    case image = 0
    case audio = 1
    case video = 2
    case file  = 3
    case link  = 4

    var iconName: String {
        switch self {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "video"
        case .file:  return "doc"
        case .link:  return "link"
        }
    }
}

enum SyncState: Int16, Codable {
    case synced    = 0
    case pending   = 1
    case uploading = 2
    case failed    = 3
}

// MARK: - 实体(DESIGN 10.1)

@objc(Idea)
final class Idea: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String?
    @NSManaged var content: String?
    @NSManaged var statusRaw: Int16
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var statusChangedAt: Date
    @NSManaged var isPinned: Bool
    @NSManaged var sortOrder: Int32
    @NSManaged var deletedAt: Date?
    @NSManaged var tags: Set<Tag>
    @NSManaged var attachments: Set<Attachment>
    @NSManaged var statusLogs: Set<StatusLog>

    var status: IdeaStatus {
        get { IdeaStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    /// 首页/列表显示标题:显式标题 > 正文首行(≤20 字) > 时间兜底(DESIGN §4 零必填)
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let first = content?.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first, !first.isEmpty {
            return String(first.prefix(20))
        }
        return "未命名灵感 \(Self.fallbackFormatter.string(from: createdAt))"
    }

    private static let fallbackFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    static func create(in ctx: NSManagedObjectContext, title: String?, content: String?, status: IdeaStatus) -> Idea {
        let idea = Idea(entity: entityDescription(in: ctx), insertInto: ctx)
        let now = Date()
        idea.id = UUID()
        idea.title = title
        idea.content = content
        idea.status = status
        idea.createdAt = now
        idea.updatedAt = now
        idea.statusChangedAt = now
        idea.isPinned = false
        idea.sortOrder = 0
        return idea
    }

    static func entityDescription(in ctx: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "Idea", in: ctx)!
    }

    static func fetchRequest() -> NSFetchRequest<Idea> {
        NSFetchRequest<Idea>(entityName: "Idea")
    }

    /// 首页查询(DESIGN §4.2):limit 30 / batchSize 20,软删除排除,置顶优先
    static func homeFetchRequest(status: IdeaStatus?, limit: Int = 30) -> NSFetchRequest<Idea> {
        let req = fetchRequest()
        var predicates = [NSPredicate(format: "deletedAt == nil")]
        if let s = status {
            predicates.append(NSPredicate(format: "statusRaw == %d", s.rawValue))
        } else {
            predicates.append(NSPredicate(format: "statusRaw != %d", IdeaStatus.archived.rawValue))
        }
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        req.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
        req.fetchLimit = limit
        req.fetchBatchSize = 20
        return req
    }
}

@objc(Attachment)
final class Attachment: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var typeRaw: Int16
    @NSManaged var fileName: String?
    @NSManaged var localPath: String?
    @NSManaged var remoteAssetID: String?
    @NSManaged var fileSize: Int64
    @NSManaged var mimeType: String?
    @NSManaged var linkURL: String?
    @NSManaged var linkTitle: String?
    @NSManaged var linkSummary: String?
    @NSManaged var thumbnailPath: String?
    @NSManaged var transcription: String?
    @NSManaged var duration: Double
    @NSManaged var createdAt: Date
    @NSManaged var syncStateRaw: Int16
    @NSManaged var idea: Idea?

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: typeRaw) ?? .file }
        set { typeRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .pending }
        set { syncStateRaw = newValue.rawValue }
    }

    static func create(in ctx: NSManagedObjectContext, idea: Idea, kind: AttachmentKind) -> Attachment {
        let a = Attachment(entity: entityDescription(in: ctx), insertInto: ctx)
        a.id = UUID()
        a.kind = kind
        a.createdAt = Date()
        a.syncState = .pending
        a.idea = idea
        return a
    }

    static func entityDescription(in ctx: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "Attachment", in: ctx)!
    }

    static func fetchRequest() -> NSFetchRequest<Attachment> {
        NSFetchRequest<Attachment>(entityName: "Attachment")
    }
}

@objc(Tag)
final class Tag: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var colorHex: String?
    @NSManaged var parent: Tag?
    @NSManaged var children: Set<Tag>
    @NSManaged var ideas: Set<Idea>

    static func findOrCreate(named rawName: String, in ctx: NSManagedObjectContext) -> Tag {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "name == %@", name)
        if let tag = (try? ctx.fetch(req))?.first {
            return tag
        }
        let tag = Tag(entity: entityDescription(in: ctx), insertInto: ctx)
        tag.id = UUID()
        tag.name = name
        return tag
    }

    static func entityDescription(in ctx: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "Tag", in: ctx)!
    }

    static func fetchRequest() -> NSFetchRequest<Tag> {
        NSFetchRequest<Tag>(entityName: "Tag")
    }
}

@objc(StatusLog)
final class StatusLog: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var fromRaw: Int16
    @NSManaged var toRaw: Int16
    @NSManaged var timestamp: Date
    @NSManaged var note: String?
    @NSManaged var sourceRaw: Int16
    @NSManaged var idea: Idea?

    var from: IdeaStatus { IdeaStatus(rawValue: fromRaw) ?? .draft }
    var to: IdeaStatus { IdeaStatus(rawValue: toRaw) ?? .draft }
    var source: StatusChangeSource { StatusChangeSource(rawValue: sourceRaw) ?? .manual }

    static func create(in ctx: NSManagedObjectContext, idea: Idea,
                       from: IdeaStatus, to: IdeaStatus,
                       source: StatusChangeSource, note: String? = nil) -> StatusLog {
        let log = StatusLog(entity: entityDescription(in: ctx), insertInto: ctx)
        log.id = UUID()
        log.fromRaw = from.rawValue
        log.toRaw = to.rawValue
        log.timestamp = Date()
        log.sourceRaw = source.rawValue
        log.note = note
        log.idea = idea
        return log
    }

    static func entityDescription(in ctx: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "StatusLog", in: ctx)!
    }

    static func fetchRequest() -> NSFetchRequest<StatusLog> {
        NSFetchRequest<StatusLog>(entityName: "StatusLog")
    }
}

@objc(SavedFilter)
final class SavedFilter: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var filterJSON: Data
    @NSManaged var sortIndex: Int16

    static func entityDescription(in ctx: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "SavedFilter", in: ctx)!
    }

    static func fetchRequest() -> NSFetchRequest<SavedFilter> {
        NSFetchRequest<SavedFilter>(entityName: "SavedFilter")
    }
}
