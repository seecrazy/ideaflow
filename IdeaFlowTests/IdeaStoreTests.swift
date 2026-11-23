import XCTest
import AVFoundation
import CoreData
@testable import IdeaFlow

@MainActor
final class IdeaStoreTests: XCTestCase {
    var sut: IdeaStore!
    var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        sut = IdeaStore(persistence: persistence)
    }

    // MARK: - capture(Review Focus #2:空白拒绝)

    func testCaptureRejectsBlankInput() throws {
        XCTAssertNil(sut.capture(text: "   \n\t "))
        XCTAssertNil(sut.capture(text: ""))
        XCTAssertEqual(try persistence.viewContext.count(for: Idea.fetchRequest()), 0)
    }

    func testCaptureCreatesDraftWithTags() throws {
        let idea = sut.capture(text: "支付流程优化\n正文", tagNames: ["产品", "支付"])
        XCTAssertNotNil(idea)
        XCTAssertEqual(idea?.status, .draft)
        XCTAssertEqual(idea?.tags.map(\.name).sorted(), ["产品", "支付"])
        XCTAssertEqual(idea?.title, nil, "零必填:不落显式标题,展示时自动取首行")
        XCTAssertEqual(idea?.statusChangedAt, idea?.createdAt)
        XCTAssertEqual(try persistence.viewContext.count(for: Idea.fetchRequest()), 1)
    }

    // MARK: - transition(审计)

    func testLegalTransitionWritesAuditLog() throws {
        let idea = sut.capture(text: "x")!
        XCTAssertTrue(sut.transition(idea, to: .pending, source: .manual, note: "整理好了"))
        XCTAssertEqual(idea.status, .pending)
        let logs = idea.statusLogs.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.from, .draft)
        XCTAssertEqual(logs.first?.to, .pending)
        XCTAssertEqual(logs.first?.source, .manual)
        XCTAssertEqual(logs.first?.note, "整理好了")
        XCTAssertGreaterThan(idea.statusChangedAt, idea.createdAt)
    }

    func testIllegalTransitionRejectedAndNoLog() throws {
        let idea = sut.capture(text: "x")!
        XCTAssertFalse(sut.transition(idea, to: .adopted), "草稿不能直接采纳")
        XCTAssertEqual(idea.status, .draft)
        XCTAssertTrue(idea.statusLogs.isEmpty)
    }

    func testSelfTransitionRejected() throws {
        let idea = sut.capture(text: "x")!
        XCTAssertFalse(sut.transition(idea, to: .draft))
    }

    // MARK: - 批量(DESIGN 5.7:source = batch)

    func testBatchTransitionLogsBatchSourcePerIdea() throws {
        let a = sut.capture(text: "a")!
        let b = sut.capture(text: "b")!
        sut.batchTransition([a, b], to: .pending)
        for idea in [a, b] {
            XCTAssertEqual(idea.status, .pending)
            XCTAssertEqual(idea.statusLogs.first?.source, .batch)
        }
    }

    func testBatchTransitionSkipsIllegalAndContinues() throws {
        let a = sut.capture(text: "a")!
        let b = sut.capture(text: "b")!
        sut.transition(a, to: .pending)   // a: pending
        // b 仍为 draft;目标 adopted 对两者都不合法(pending 可,draft 不可)
        sut.batchTransition([a, b], to: .adopted)
        XCTAssertEqual(a.status, .adopted, "pending → adopted 合法")
        XCTAssertEqual(b.status, .draft, "draft → adopted 非法,保持原状态且无日志")
        XCTAssertTrue(b.statusLogs.isEmpty)
    }

    func testBatchAddTag() throws {
        let a = sut.capture(text: "a")!
        let b = sut.capture(text: "b")!
        sut.batchAddTag([a, b], tagName: "灵感")
        XCTAssertEqual(a.tags.first?.name, "灵感")
        XCTAssertEqual(b.tags.first?.name, "灵感")
        let tags = try persistence.viewContext.fetch(Tag.fetchRequest())
        XCTAssertEqual(tags.count, 1, "同名标签复用")
    }

    // MARK: - 回收站(软删除/恢复/过期清理)

    func testSoftDeleteAndRestore() throws {
        let idea = sut.capture(text: "x")!
        try sut.softDelete(idea)
        XCTAssertNotNil(idea.deletedAt)
        XCTAssertEqual(try sut.fetch(status: nil, limit: 30).count, 0, "软删除后不在首页")

        try sut.restore(idea)
        XCTAssertNil(idea.deletedAt)
        XCTAssertEqual(try sut.fetch(status: nil, limit: 30).count, 1)
    }

    func testPurgeExpiredDeletesIdeasAndAttachmentFiles() throws {
        // 借临时目录模拟附件目录布局 Attachments/{ideaID}/
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let media = AttachmentFiles(root: docs)

        let old = sut.capture(text: "old")!
        let fresh = sut.capture(text: "fresh")!
        let attDir = media.directory(for: old.id)
        try FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)
        let file = attDir.appendingPathComponent("a.jpg")
        try Data([0xFF, 0xD8]).write(to: file)

        try sut.softDelete(old)
        try sut.softDelete(fresh)
        // 把 old 的删除时间拨回 31 天前
        old.deletedAt = Date().addingTimeInterval(-31 * 86400)

        let purged = try sut.purgeExpired(retentionDays: 30, files: media)
        XCTAssertEqual(purged, 1)
        XCTAssertEqual(try persistence.viewContext.count(for: Idea.fetchRequest()), 1, "仅剩 fresh")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "附件文件应被物理删除")
        XCTAssertEqual(try sut.deletedIdeas().count, 1)
    }

    // MARK: - 置顶

    func testTogglePinAndHomeOrder() throws {
        let a = sut.capture(text: "a")!
        _ = sut.capture(text: "b")!
        try sut.togglePin(a)
        let home = try sut.fetch(status: nil, limit: 30)
        XCTAssertEqual(home.first, a, "置顶优先于时间排序")
        try sut.togglePin(a)
        XCTAssertEqual(try sut.fetch(status: nil, limit: 30).first?.content, "b")
    }

    func testFetchRespectsStatusFilterAndLimit() throws {
        for i in 0..<40 { _ = sut.capture(text: "idea \(i)") }
        let idea = try sut.fetch(status: nil, limit: 30)
        XCTAssertEqual(idea.count, 30, "fetchLimit 生效")
        XCTAssertEqual(try sut.fetch(status: .draft, limit: 30).count, 30)
    }
}

// MARK: - 附件挂载(capture 管道收尾)

@MainActor
final class IdeaStoreAttachmentTests: XCTestCase {
    var sut: IdeaStore!
    var persistence: PersistenceController!
    var tmpRoot: URL!
    var media: MediaStore!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        sut = IdeaStore(persistence: persistence)
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-test-\(UUID().uuidString)", isDirectory: true)
        media = MediaStore(files: AttachmentFiles(root: tmpRoot))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
        super.tearDown()
    }

    private func pngData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60))
        return renderer.image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testAddImageCreatesAttachmentWithFiles() throws {
        let idea = sut.capture(text: "带图灵感")!
        let att = try sut.addImage(pngData(), to: idea, media: media)
        XCTAssertEqual(att.kind, .image)
        XCTAssertNotNil(att.localPath)
        let files = AttachmentFiles(root: tmpRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.absoluteURL(for: att.localPath!).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.absoluteURL(for: att.thumbnailPath ?? "").path))
        XCTAssertGreaterThan(att.fileSize, 0)
        XCTAssertEqual(att.idea, idea)
    }

    func testAddAudioMovesFileAndStoresTranscription() throws {
        let idea = sut.capture(text: "语音灵感")!
        let tmpAudio = tmpRoot.appendingPathComponent("tmp-rec.m4a")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        // 生成真实 AAC 文件:AVAsset 读假字节会抛 ObjC 异常
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: tmpAudio, settings: MediaStore.audioSettings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        try file.write(from: buffer)
        let att = try sut.addAudio(at: tmpAudio, to: idea, duration: 0.1,
                                   transcription: "转写文本", media: media)
        XCTAssertEqual(att.kind, .audio)
        XCTAssertEqual(att.transcription, "转写文本")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpAudio.path), "临时文件应被移走")
        let files = AttachmentFiles(root: tmpRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.absoluteURL(for: att.localPath!).path))
    }

    func testAddLinkStoresMeta() throws {
        let idea = sut.capture(text: "链接灵感")!
        let att = sut.addLink(LinkMeta(url: URL(string: "https://example.com/a")!,
                                       title: "示例", summary: "摘要"), to: idea)
        XCTAssertEqual(att.kind, .link)
        XCTAssertEqual(att.linkURL, "https://example.com/a")
        XCTAssertEqual(att.linkTitle, "示例")
        XCTAssertEqual(att.linkSummary, "摘要")
    }
}

// MARK: - 附件追加/移除(详情页补料)

@MainActor
final class IdeaStoreAttachmentEditTests: XCTestCase {
    var sut: IdeaStore!
    var persistence: PersistenceController!
    var tmpRoot: URL!
    var media: MediaStore!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        sut = IdeaStore(persistence: persistence)
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("attedit-\(UUID().uuidString)", isDirectory: true)
        media = MediaStore(files: AttachmentFiles(root: tmpRoot))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
        super.tearDown()
    }

    private func pngData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60))
        return renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testRemoveAttachmentDeletesEntityAndFile() throws {
        let idea = sut.capture(text: "要移除附件的灵感")!
        let att = try sut.addImage(pngData(), to: idea, media: media)
        let path = AttachmentFiles(root: tmpRoot).absoluteURL(for: att.localPath!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        sut.removeAttachment(att, files: AttachmentFiles(root: tmpRoot))
        XCTAssertEqual(idea.attachments.count, 0, "实体应移除")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), "文件应删除")
    }

    func testAddFileCopiesIntoAttachmentDirectory() throws {
        let idea = sut.capture(text: "带文件的灵感")!
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        let src = tmpRoot.appendingPathComponent("source-doc.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: src)

        let att = try sut.addFile(at: src, to: idea, media: media)
        XCTAssertEqual(att.kind, .file)
        XCTAssertEqual(att.fileName, "source-doc.pdf")
        XCTAssertGreaterThan(att.fileSize, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "导入是复制:源文件保留(文档选择器语义)")
        let dest = AttachmentFiles(root: tmpRoot).absoluteURL(for: att.localPath!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path), "文件应进入附件目录")
    }
}
