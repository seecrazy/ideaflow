import Foundation
import SQLite3

/// 独立 FTS 索引库(DESIGN §6.2):SQLite FTS5 + 拼音表,经 ideaID 与 Core Data 关联。
/// CJK 处理:索引与查询两侧同步做 bigram 展开(unicode61 把连续汉字当单 token,
/// 不展开则"快捷"无法命中整句),英文保留整词。
final class SearchIndexDatabase {
    struct Hit {
        let ideaID: UUID
        let viaPinyin: Bool
    }

    private var db: OpaquePointer?
    private let lock = NSLock()
    private let url: URL

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            fatalError("cannot open search index at \(url.path)")
        }
        migrate()
    }

    deinit {
        if db != nil { sqlite3_close_v2(db) }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if db != nil {
            sqlite3_close_v2(db)
            db = nil
        }
    }

    var indexedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let stmt = prepare("SELECT COUNT(*) FROM idea_fts") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Schema

    private func migrate() {
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS idea_fts USING fts5(
            idea_id UNINDEXED,
            title,
            content,
            transcription,
            link_title,
            file_names,
            tokenize = 'unicode61'
        );
        CREATE TABLE IF NOT EXISTS idea_pinyin (
            idea_id TEXT PRIMARY KEY,
            full_pinyin TEXT NOT NULL,
            initials TEXT NOT NULL
        );
        """)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            assertionFailure("search index exec failed: \(message)")
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            assertionFailure("prepare failed: \(sql) — \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return stmt
    }

    // MARK: - Bigram 展开(CJK)

    static func expand(_ text: String) -> String {
        var tokens: [String] = []
        var latinRun = ""
        var hanRun = ""

        func flushLatin() {
            guard !latinRun.isEmpty else { return }
            tokens.append(latinRun)
            latinRun = ""
        }
        func flushHan() {
            guard !hanRun.isEmpty else { return }
            let chars = Array(hanRun)
            if chars.count == 1 {
                tokens.append(String(chars[0]))
            } else {
                for i in 0..<(chars.count - 1) {
                    tokens.append(String(chars[i]) + String(chars[i + 1]))
                }
            }
            hanRun = ""
        }

        for ch in text.lowercased() {
            if PinyinTransformer.isHan(ch) {
                flushLatin()
                hanRun.append(ch)
            } else if ch.isLetter || ch.isNumber {
                flushHan()
                latinRun.append(ch)
            } else {
                flushLatin()
                flushHan()
            }
        }
        flushLatin()
        flushHan()
        return tokens.joined(separator: " ")
    }

    /// FTS5 查询净化(Review Focus #1):逐 token 双引号包裹,内部引号翻倍转义,杜绝注入语法
    static func sanitizedMatchExpression(_ query: String) -> String {
        expand(query)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            .joined(separator: " ")
    }

    // MARK: - 写入

    func upsert(doc: IndexDocument) {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { return }
        exec("BEGIN IMMEDIATE TRANSACTION")
        bind.run("DELETE FROM idea_fts WHERE idea_id = ?") { sqlite3_bind_text($0, 1, doc.ideaID.uuidString, -1, Self.transient) }
        bind.run("""
            INSERT INTO idea_fts(idea_id, title, content, transcription, link_title, file_names)
            VALUES (?, ?, ?, ?, ?, ?)
        """) { stmt in
            sqlite3_bind_text(stmt, 1, doc.ideaID.uuidString, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, Self.expand(doc.title), -1, Self.transient)
            sqlite3_bind_text(stmt, 3, Self.expand(doc.content), -1, Self.transient)
            sqlite3_bind_text(stmt, 4, Self.expand(doc.transcription), -1, Self.transient)
            sqlite3_bind_text(stmt, 5, Self.expand(doc.linkTitle), -1, Self.transient)
            sqlite3_bind_text(stmt, 6, Self.expand(doc.fileNames), -1, Self.transient)
        }
        let pinyin = PinyinTransformer.analyze([doc.title, doc.content].joined(separator: " "))
        bind.run("INSERT OR REPLACE INTO idea_pinyin(idea_id, full_pinyin, initials) VALUES (?, ?, ?)") { stmt in
            sqlite3_bind_text(stmt, 1, doc.ideaID.uuidString, -1, Self.transient)
            sqlite3_bind_text(stmt, 2, pinyin.full, -1, Self.transient)
            sqlite3_bind_text(stmt, 3, pinyin.initials, -1, Self.transient)
        }
        exec("COMMIT")
    }

    func remove(ideaID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { return }
        bind.run("DELETE FROM idea_fts WHERE idea_id = ?") { sqlite3_bind_text($0, 1, ideaID.uuidString, -1, Self.transient) }
        bind.run("DELETE FROM idea_pinyin WHERE idea_id = ?") { sqlite3_bind_text($0, 1, ideaID.uuidString, -1, Self.transient) }
    }

    /// 全量重建(设置页入口);与增量 upsert 经同一把锁串行,交错不丢(Review Focus #5)
    func rebuild(with docs: [IndexDocument]) {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { return }
        exec("BEGIN IMMEDIATE TRANSACTION")
        exec("DELETE FROM idea_fts")
        exec("DELETE FROM idea_pinyin")
        let insertFTS = prepare("INSERT INTO idea_fts(idea_id, title, content, transcription, link_title, file_names) VALUES (?, ?, ?, ?, ?, ?)")
        let insertPinyin = prepare("INSERT OR REPLACE INTO idea_pinyin(idea_id, full_pinyin, initials) VALUES (?, ?, ?)")
        for doc in docs {
            if let stmt = insertFTS {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, doc.ideaID.uuidString, -1, Self.transient)
                sqlite3_bind_text(stmt, 2, Self.expand(doc.title), -1, Self.transient)
                sqlite3_bind_text(stmt, 3, Self.expand(doc.content), -1, Self.transient)
                sqlite3_bind_text(stmt, 4, Self.expand(doc.transcription), -1, Self.transient)
                sqlite3_bind_text(stmt, 5, Self.expand(doc.linkTitle), -1, Self.transient)
                sqlite3_bind_text(stmt, 6, Self.expand(doc.fileNames), -1, Self.transient)
                sqlite3_step(stmt)
            }
            if let stmt = insertPinyin {
                let pinyin = PinyinTransformer.analyze([doc.title, doc.content].joined(separator: " "))
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, doc.ideaID.uuidString, -1, Self.transient)
                sqlite3_bind_text(stmt, 2, pinyin.full, -1, Self.transient)
                sqlite3_bind_text(stmt, 3, pinyin.initials, -1, Self.transient)
                sqlite3_step(stmt)
            }
        }
        sqlite3_finalize(insertFTS)
        sqlite3_finalize(insertPinyin)
        exec("COMMIT")
    }

    // MARK: - 查询

    /// 返回 rank 序命中(FTS 优先,拼音命中追加在后,去重)
    func matchingIDs(query rawQuery: String) -> [UUID] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { return [] }

        var ordered: [UUID] = []
        var seen = Set<UUID>()

        let matchExpr = Self.sanitizedMatchExpression(query)
        if !matchExpr.isEmpty, let stmt = prepare("SELECT idea_id FROM idea_fts WHERE idea_fts MATCH ? ORDER BY rank") {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, matchExpr, -1, Self.transient)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let s = sqlite3_column_text(stmt, 0), let id = UUID(uuidString: String(cString: s)), seen.insert(id).inserted {
                    ordered.append(id)
                }
            }
        }

        // 拼音层:仅对拉丁字母/数字查询启用(中文查询 FTS 已覆盖)
        if query.allSatisfy({ $0.isLetter || $0.isNumber }) && !query.isEmpty {
            let pattern = "%\(Self.escapeLike(query.lowercased()))%"
            if let stmt = prepare("SELECT idea_id FROM idea_pinyin WHERE full_pinyin LIKE ? ESCAPE '\\' OR initials LIKE ? ESCAPE '\\'") {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, pattern, -1, Self.transient)
                sqlite3_bind_text(stmt, 2, pattern, -1, Self.transient)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let s = sqlite3_column_text(stmt, 0), let id = UUID(uuidString: String(cString: s)), seen.insert(id).inserted {
                        ordered.append(id)
                    }
                }
            }
        }
        return ordered
    }

    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // bind 辅助:prepare + bind + step + finalize
    private var bind: Binder { Binder(db: db) }

    private final class Binder {
        let db: OpaquePointer?
        init(db: OpaquePointer?) { self.db = db }

        func run(_ sql: String, _ bindBlock: (OpaquePointer) -> Void) {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                assertionFailure("prepare failed: \(sql)")
                return
            }
            defer { sqlite3_finalize(stmt) }
            bindBlock(stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                assertionFailure("step failed: \(sql) — \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
}
