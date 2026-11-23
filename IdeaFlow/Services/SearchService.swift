import Foundation
import CoreData

/// 索引文档:五字段全文(DESIGN §6.2)
struct IndexDocument {
    let ideaID: UUID
    let title: String
    let content: String
    let transcription: String
    let linkTitle: String
    let fileNames: String
    var tagNames: String = ""

    init(ideaID: UUID, title: String, content: String, transcription: String,
         linkTitle: String, fileNames: String, tagNames: String = "") {
        self.ideaID = ideaID
        self.title = title
        self.content = content
        self.transcription = transcription
        self.linkTitle = linkTitle
        self.fileNames = fileNames
        self.tagNames = tagNames
    }
}

/// 组合筛选(AND 语义;Codable 供 SavedFilter 智能视图持久化)
struct SearchFilter: Codable, Equatable {
    var status: IdeaStatus?
    var kinds: Set<AttachmentKind>
    var tagNames: [String]
    var from: Date?
    var to: Date?

    init(status: IdeaStatus? = nil, kinds: Set<AttachmentKind> = [], tagNames: [String] = [], from: Date? = nil, to: Date? = nil) {
        self.status = status
        self.kinds = kinds
        self.tagNames = tagNames
        self.from = from
        self.to = to
    }

    var isEmpty: Bool {
        status == nil && kinds.isEmpty && tagNames.isEmpty && from == nil && to == nil
    }

    func predicate() -> NSPredicate? {
        var subs = [NSPredicate(format: "deletedAt == nil")]
        if let s = status {
            subs.append(NSPredicate(format: "statusRaw == %d", s.rawValue))
        }
        if !kinds.isEmpty {
            let raws = kinds.map(\.rawValue)
            subs.append(NSPredicate(format: "ANY attachments.typeRaw IN %@", raws))
        }
        if !tagNames.isEmpty {
            subs.append(NSPredicate(format: "ANY tags.name IN %@", tagNames))
        }
        if let from { subs.append(NSPredicate(format: "createdAt >= %@", from as NSDate)) }
        if let to { subs.append(NSPredicate(format: "createdAt <= %@", to as NSDate)) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: subs)
    }
}

/// 搜索门面(DESIGN §6):NSPredicate 结构化层 + FTS5/拼音索引层;
/// 索引更新经 IdeaStore 钩子串行异步;历史最多 10 条。
@MainActor
final class SearchService: ObservableObject {
    struct SearchHit {
        let idea: Idea
        let snippet: String
    }

    let index: SearchIndexDatabase
    let queue = DispatchQueue(label: "ideaflow.search.index")
    weak var store: IdeaStore?
    private let defaults: UserDefaults

    private static let historyKey = "ideaflow.search.history"

    init(index: SearchIndexDatabase, defaults: UserDefaults = .standard) {
        self.index = index
        self.defaults = defaults
    }

    // MARK: - 接线:Core Data 变更 → 索引更新

    func attach(to store: IdeaStore) {
        self.store = store
        store.onIdeaChanged = { [weak self] idea, _ in
            guard let self else { return }
            let doc = Self.document(for: idea)
            self.queue.async { self.index.upsert(doc: doc) }
        }
        store.onIdeaRemoved = { [weak self] id in
            guard let self else { return }
            self.queue.async { self.index.remove(ideaID: id) }
        }
    }

    static func document(for idea: Idea) -> IndexDocument {
        let transcriptions = idea.attachments.compactMap(\.transcription).joined(separator: " ")
        let linkTitles = idea.attachments.filter { $0.kind == .link }.compactMap(\.linkTitle).joined(separator: " ")
        let fileNames = idea.attachments.compactMap(\.fileName).joined(separator: " ")
        return IndexDocument(
            ideaID: idea.id,
            title: idea.displayTitle,
            content: idea.content ?? "",
            transcription: transcriptions,
            linkTitle: linkTitles,
            fileNames: fileNames,
            tagNames: idea.tags.map(\.name).joined(separator: " ")
        )
    }

    /// 排空索引队列(测试与"重建索引"后调用;生产搜索自带 250ms 防抖,无需主动调)
    func flushIndex() {
        queue.sync {}
    }

    // MARK: - 搜索

    func search(query rawQuery: String, filter: SearchFilter? = nil) throws -> [SearchHit] {
        guard let ctx = store?.ctx else { return [] }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty || !(filter?.isEmpty ?? true) else { return [] }

        let rankedIDs: [UUID]
        if query.isEmpty {
            rankedIDs = []
        } else {
            rankedIDs = index.matchingIDs(query: query)
        }

        let req = Idea.fetchRequest()
        var subs = [NSPredicate(format: "deletedAt == nil")]
        if !query.isEmpty {
            if rankedIDs.isEmpty { return [] }   // 文本查询零命中,不必进 Core Data
            subs.append(NSPredicate(format: "id IN %@", rankedIDs))
        }
        if let filter, !filter.isEmpty, let p = filter.predicate() {
            subs.append(p)
        }
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subs)

        let ideas = try ctx.fetch(req)
        guard !query.isEmpty else {
            // 纯结构化筛选:按时间倒序
            return ideas
                .sorted { $0.createdAt > $1.createdAt }
                .map { SearchHit(idea: $0, snippet: $0.displayTitle) }
        }
        // 相关度(rank 序)优先
        let order = Dictionary(uniqueKeysWithValues: rankedIDs.enumerated().map { ($1, $0) })
        return ideas
            .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
            .map { SearchHit(idea: $0, snippet: Self.snippet(for: $0, query: query)) }
    }

    /// Swift 侧摘要:取首个命中字段的命中位置前后约 30 字
    static func snippet(for idea: Idea, query: String) -> String {
        let fields: [String] = [
            idea.content ?? "",
            idea.attachments.compactMap(\.transcription).joined(separator: " "),
            idea.attachments.filter { $0.kind == .link }.compactMap(\.linkTitle).joined(separator: " "),
        ]
        for field in fields where !field.isEmpty {
            if let range = field.range(of: query, options: .caseInsensitive) {
                let start = field.index(range.lowerBound, offsetBy: -12, limitedBy: field.startIndex) ?? field.startIndex
                let end = field.index(range.upperBound, offsetBy: 18, limitedBy: field.endIndex) ?? field.endIndex
                let prefix = start > field.startIndex ? "…" : ""
                let suffix = end < field.endIndex ? "…" : ""
                return prefix + field[start..<end] + suffix
            }
        }
        return idea.displayTitle
    }

    // MARK: - 搜索历史(最多 10 条,新搜索置顶去重)

    func history() -> [String] {
        defaults.stringArray(forKey: Self.historyKey) ?? []
    }

    func recordHistory(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var list = history().filter { $0 != q }
        list.insert(q, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        defaults.set(list, forKey: Self.historyKey)
    }

    func removeHistory(_ query: String) {
        defaults.set(history().filter { $0 != query }, forKey: Self.historyKey)
    }

    func clearHistory() {
        defaults.removeObject(forKey: Self.historyKey)
    }
}
