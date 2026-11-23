import XCTest
import CoreData
@testable import IdeaFlow

// MARK: - 拼音(零第三方依赖:CFStringTransform)

final class PinyinTransformerTests: XCTestCase {
    func testPureChinese() {
        XCTAssertEqual(PinyinTransformer.full("微信读书"), "weixindushu")
        XCTAssertEqual(PinyinTransformer.initials("微信读书"), "wxds")
    }

    func testPunctuationSkipped() {
        XCTAssertEqual(PinyinTransformer.full("你好,世界!"), "nihaoshijie")
        XCTAssertEqual(PinyinTransformer.initials("你好,世界!"), "nhsj")
    }

    // Review Focus #3:混合中英文,英文单词保留原字母小写
    func testMixedChineseEnglish() {
        XCTAssertEqual(PinyinTransformer.full("微信Read笔记"), "weixinreadbiji")
        XCTAssertEqual(PinyinTransformer.initials("微信Read笔记"), "wxreadbj")
    }

    func testPureEnglishPassesThrough() {
        XCTAssertEqual(PinyinTransformer.full("Hello World"), "helloworld")
        XCTAssertEqual(PinyinTransformer.initials("Hello World"), "helloworld")
    }

    func testDigitsKept() {
        XCTAssertEqual(PinyinTransformer.initials("产品v2上线"), "cpv2sx")
    }
}

// MARK: - FTS5 索引库

final class SearchIndexDatabaseTests: XCTestCase {
    var db: SearchIndexDatabase!
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx-test-\(UUID().uuidString)", isDirectory: true)
        db = SearchIndexDatabase(url: dir.appendingPathComponent("SearchIndex.sqlite"))
    }

    override func tearDown() {
        db.close()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func doc(_ id: String, title: String = "", content: String = "",
                     transcription: String = "", linkTitle: String = "", fileNames: String = "") -> IndexDocument {
        IndexDocument(ideaID: UUID(uuidString: id)!, title: title, content: content,
                      transcription: transcription, linkTitle: linkTitle, fileNames: fileNames)
    }

    func testMatchAcrossAllFields() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "支付流程优化", content: "", transcription: "", linkTitle: "", fileNames: ""))
        db.upsert(doc: IndexDocument(ideaID: b, title: "", content: "正文里提到支付失败", transcription: "", linkTitle: "", fileNames: ""))
        db.upsert(doc: IndexDocument(ideaID: c, title: "", content: "", transcription: "语音转写:支付体验差", linkTitle: "", fileNames: ""))
        db.upsert(doc: IndexDocument(ideaID: d, title: "", content: "", transcription: "", linkTitle: "支付周刊", fileNames: ""))
        db.upsert(doc: IndexDocument(ideaID: e, title: "", content: "", transcription: "", linkTitle: "", fileNames: "支付截图.png"))
        let ids = Set(db.matchingIDs(query: "支付"))
        XCTAssertEqual(ids, [a, b, c, d, e], "标题/正文/转写/链接标题/文件名五个字段都应命中")
    }

    // Review Focus #1:查询串含引号/连字符不得让 MATCH 语法崩溃
    func testQueryWithQuotesAndHyphenDoesNotCrash() {
        let a = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "won't stop me now", content: "3-2 defense", transcription: "", linkTitle: "", fileNames: ""))
        XCTAssertEqual(Set(db.matchingIDs(query: "won't")), [a])
        XCTAssertEqual(Set(db.matchingIDs(query: "\"quoted\"")), [])
        XCTAssertEqual(Set(db.matchingIDs(query: "3-2")), [a])
        XCTAssertNoThrow(_ = db.matchingIDs(query: "\" OR 1=1 --"))
    }

    func testRemoveDeletesFromIndex() {
        let a = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "目标", content: "", transcription: "", linkTitle: "", fileNames: ""))
        db.remove(ideaID: a)
        XCTAssertTrue(db.matchingIDs(query: "目标").isEmpty)
    }

    func testUpsertDoesNotDuplicate() {
        let a = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "重复", content: "", transcription: "", linkTitle: "", fileNames: ""))
        db.upsert(doc: IndexDocument(ideaID: a, title: "重复", content: "", transcription: "", linkTitle: "", fileNames: ""))
        XCTAssertEqual(db.matchingIDs(query: "重复").count, 1)
    }

    // Review Focus #5:重建与增量 upsert 交错不丢数据
    func testRebuildThenUpsertKeepsBoth() {
        let a = UUID(), b = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "苹果", content: "", transcription: "", linkTitle: "", fileNames: ""))
        db.rebuild(with: [IndexDocument(ideaID: b, title: "香蕉", content: "", transcription: "", linkTitle: "", fileNames: "")])
        XCTAssertEqual(Set(db.matchingIDs(query: "香蕉")), [b])
        XCTAssertTrue(db.matchingIDs(query: "苹果").isEmpty, "重建后旧内容应清空")
        db.upsert(doc: IndexDocument(ideaID: a, title: "苹果", content: "", transcription: "", linkTitle: "", fileNames: ""))
        XCTAssertEqual(Set(db.matchingIDs(query: "苹果")), [a], "重建后增量 upsert 不丢")
    }

    func testPinyinLookup() {
        let a = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "微信读书", content: "", transcription: "", linkTitle: "", fileNames: ""))
        XCTAssertEqual(Set(db.matchingIDs(query: "wxds")), [a], "拼音首字母命中")
        XCTAssertEqual(Set(db.matchingIDs(query: "weixin")), [a], "全拼命中")
        XCTAssertEqual(Set(db.matchingIDs(query: "wxs")), [], "错误首字母不命中")
    }

    func testFTSChineseWordSegmentation() {
        let a = UUID()
        db.upsert(doc: IndexDocument(ideaID: a, title: "做一个语音速记的快捷方式", content: "", transcription: "", linkTitle: "", fileNames: ""))
        XCTAssertEqual(Set(db.matchingIDs(query: "语音速记")), [a])
        XCTAssertEqual(Set(db.matchingIDs(query: "快捷")), [a])
    }
}

// MARK: - SearchService(组合查询 + 历史)

@MainActor
final class SearchServiceTests: XCTestCase {
    var persistence: PersistenceController!
    var store: IdeaStore!
    var service: SearchService!
    var dir: URL!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        store = IdeaStore(persistence: persistence)
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svc-test-\(UUID().uuidString)", isDirectory: true)
        service = SearchService(index: SearchIndexDatabase(url: dir.appendingPathComponent("SearchIndex.sqlite")),
                                defaults: UserDefaults(suiteName: "search-hist-\(UUID().uuidString)")!)
        service.attach(to: store)
    }

    override func tearDown() {
        service.index.close()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testSearchFindsCapturedIdeaWithSnippet() throws {
        _ = store.capture(text: "支付流程优化方案\n提升转化率")
        service.flushIndex()
        let hits = try service.search(query: "支付")
        XCTAssertEqual(hits.count, 1)
        XCTAssertNotNil(hits.first?.idea)
        XCTAssertTrue(hits.first?.snippet.contains("支付") ?? false, "摘要应包含关键词")
    }

    func testStructuredFilterWithoutQuery() throws {
        let adopted = store.capture(text: "已被采纳的灵感")!
        _ = store.capture(text: "还是草稿")
        store.transition(adopted, to: .pending)
        store.transition(adopted, to: .adopted)

        service.flushIndex()
        let filter = SearchFilter(status: .adopted, kinds: [], tagNames: [], from: nil, to: nil)
        let hits = try service.search(query: "", filter: filter)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.idea.content, "已被采纳的灵感")
    }

    func testEmptyQueryEmptyFilterReturnsNothingNotEverything() throws {
        _ = store.capture(text: "x")
        XCTAssertTrue(try service.search(query: "", filter: nil).isEmpty)
    }

    func testFilterByTagAndKind() throws {
        let idea = store.capture(text: "带标签的", tagNames: ["读书"])!
        let att = Attachment.create(in: persistence.viewContext, idea: idea, kind: .audio)
        att.fileName = "voice.m4a"
        try persistence.viewContext.save()
        service.flushIndex()

        let hit1 = try service.search(query: "", filter: SearchFilter(status: nil, kinds: [.audio], tagNames: [], from: nil, to: nil))
        XCTAssertEqual(hit1.count, 1)
        let hit2 = try service.search(query: "", filter: SearchFilter(status: nil, kinds: [], tagNames: ["读书"], from: nil, to: nil))
        XCTAssertEqual(hit2.count, 1)
        let hit3 = try service.search(query: "", filter: SearchFilter(status: nil, kinds: [.image], tagNames: [], from: nil, to: nil))
        XCTAssertTrue(hit3.isEmpty)
    }

    func testSoftDeletedExcludedFromSearch() throws {
        let idea = store.capture(text: "要被删除的支付灵感")!
        service.flushIndex()
        try store.softDelete(idea)
        XCTAssertTrue(try service.search(query: "支付").isEmpty)
    }

    // MARK: 搜索历史(最多 10 条,新搜索置顶去重)

    func testHistoryRecordAndCap() {
        for i in 0..<12 { service.recordHistory("词\(i)") }
        var hist = service.history()
        XCTAssertEqual(hist.count, 10)
        XCTAssertEqual(hist.first, "词11", "最新在前")
        service.recordHistory("词5")
        hist = service.history()
        XCTAssertEqual(hist.filter { $0 == "词5" }.count, 1, "重复搜索去重并置顶")
        XCTAssertEqual(hist.first, "词5")
    }

    // MARK: 性能(DESIGN 验收 5:1 万条 ≤ 200ms,3 次取最小)

    func testSearchTenThousandRecordsUnder200ms() throws {
        var docs: [IndexDocument] = []
        docs.reserveCapacity(10_000)
        for i in 0..<10_000 {
            let target = (i % 1000 == 0) ? "支付风控" : "普通内容"
            docs.append(IndexDocument(ideaID: UUID(), title: "灵感\(i) \(target)",
                                     content: "正文内容\(i)", transcription: "", linkTitle: "", fileNames: ""))
        }
        service.index.rebuild(with: docs)
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            let t0 = Date()
            _ = service.index.matchingIDs(query: "支付风控")
            best = min(best, Date().timeIntervalSince(t0))
        }
        XCTAssertLessThan(best, 0.2, "1 万条 FTS 搜索应 ≤ 200ms,实测 \(best * 1000)ms")
    }
}

// MARK: - 终审修复回归

final class SearchRegressionTests: XCTestCase {
    var dir: URL!
    var db: SearchIndexDatabase!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("idx-reg-\(UUID().uuidString)", isDirectory: true)
        db = SearchIndexDatabase(url: dir.appendingPathComponent("SearchIndex.sqlite"))
    }

    override func tearDown() {
        db.close()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // 终审 #6:spec 示例"chan pin you hua"带空格全拼应命中
    func testPinyinQueryWithSpacesMatches() {
        db.upsert(doc: IndexDocument(ideaID: UUID(), title: "产品优化", content: "", transcription: "", linkTitle: "", fileNames: ""))
        XCTAssertEqual(Set(db.matchingIDs(query: "chan pin")), Set(db.matchingIDs(query: "chanpin")), "带空格与连写应等效")
        XCTAssertFalse(db.matchingIDs(query: "chan pin").isEmpty)
    }
}

@MainActor
final class SearchTagRegressionTests: XCTestCase {
    var persistence: PersistenceController!
    var store: IdeaStore!
    var service: SearchService!
    var dir: URL!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        store = IdeaStore(persistence: persistence)
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svc-reg-\(UUID().uuidString)", isDirectory: true)
        service = SearchService(index: SearchIndexDatabase(url: dir.appendingPathComponent("SearchIndex.sqlite")))
        service.attach(to: store)
    }

    override func tearDown() {
        service.index.close()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // 终审 #8:spec §6.3 搜索范围含标签
    func testSearchByTagTextHitsIdea() throws {
        _ = store.capture(text: "只有正文没有关键词", tagNames: ["读书会"])
        service.flushIndex()
        let hits = try service.search(query: "读书会")
        XCTAssertEqual(hits.count, 1, "按标签词应命中")
    }
}

@MainActor
final class RecycleTagRegressionTests: XCTestCase {
    // 终审 #9(Review Focus #4):删除标签后恢复回收站点子
    func testRestoreAfterTagDeleted() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = IdeaStore(persistence: persistence)
        let idea = store.capture(text: "带标签的回收站条目", tagNames: ["即将删除"])!
        try store.softDelete(idea)
        let tag = idea.tags.first!
        persistence.viewContext.delete(tag)
        try persistence.viewContext.save()

        try store.restore(idea)
        XCTAssertTrue(idea.tags.isEmpty, "标签已删,恢复后标签集应为空而非悬挂")
        idea.content = "恢复后再编辑"
        try persistence.viewContext.save()   // 不崩
    }
}

final class ThumbnailCacheTests: XCTestCase {
    // 终审 #7:缩略图缓存命中(同一实例)
    func testCacheReturnsSameInstance() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("t.jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        try renderer.image { ctx in
            UIColor.systemBrown.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }.jpegData(compressionQuality: 0.8)!.write(to: url)

        let cache = ThumbnailCache()
        let a = cache.image(atPath: url.path)
        let b = cache.image(atPath: url.path)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "同路径二次加载应命中缓存")
        XCTAssertNil(cache.image(atPath: "/nonexistent/x.jpg"))
        try? FileManager.default.removeItem(at: dir)
    }
}

final class QuickCapturePlaceholderTests: XCTestCase {
    // 终审 #1:纯附件保存的占位文本(零必填)
    func testPlaceholderForAttachmentOnly() {
        let voice = PendingAttachment(kind: .audio(URL(fileURLWithPath: "/tmp/a.m4a"), duration: 12, transcription: nil))
        XCTAssertFalse(QuickCapture.placeholderText(for: [voice]).isEmpty, "纯语音应有占位标题")
        let link = PendingAttachment(kind: .link(LinkMeta(url: URL(string: "https://x.com")!, title: "外部链接标题", summary: nil)))
        XCTAssertEqual(QuickCapture.placeholderText(for: [link]), "外部链接标题", "链接附件用其标题")
        let img = PendingAttachment(kind: .image(Data([1])))
        XCTAssertEqual(QuickCapture.placeholderText(for: [img]), "图片速记")
        XCTAssertTrue(QuickCapture.placeholderText(for: []).isEmpty)
    }
}
