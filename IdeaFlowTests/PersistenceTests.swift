import XCTest
import CoreData
@testable import IdeaFlow

final class PersistenceTests: XCTestCase {
    var sut: PersistenceController!

    override func setUp() {
        super.setUp()
        sut = PersistenceController(inMemory: true)
    }

    func testCreateIdeaWithRelationships() throws {
        let ctx = sut.viewContext
        let idea = Idea.create(in: ctx, title: "标题", content: "正文", status: .draft)
        let tag = Tag.findOrCreate(named: "产品", in: ctx)
        idea.tags = [tag]
        let log = StatusLog.create(in: ctx, idea: idea, from: .draft, to: .pending, source: .manual)
        try ctx.save()

        XCTAssertEqual(idea.title, "标题")
        XCTAssertEqual(idea.status, .draft)
        XCTAssertEqual(tag.ideas.count, 1)
        XCTAssertEqual(log.idea, idea)
        XCTAssertEqual(log.from, .draft)
        XCTAssertEqual(log.to, .pending)
        XCTAssertNotNil(idea.createdAt)
        XCTAssertNotNil(idea.updatedAt)
        XCTAssertNil(idea.deletedAt)
    }

    func testDeleteIdeaCascadesAttachmentsAndLogsButKeepsTags() throws {
        let ctx = sut.viewContext
        let idea = Idea.create(in: ctx, title: nil, content: "x", status: .draft)
        let tag = Tag.findOrCreate(named: "保留", in: ctx)
        idea.tags = [tag]
        _ = StatusLog.create(in: ctx, idea: idea, from: .draft, to: .pending, source: .manual)
        let att = Attachment.create(in: ctx, idea: idea, kind: .image)
        att.fileName = "a.jpg"
        try ctx.save()

        ctx.delete(idea)
        try ctx.save()

        XCTAssertEqual(try ctx.count(for: Attachment.fetchRequest()), 0, "附件应级联删除")
        XCTAssertEqual(try ctx.count(for: StatusLog.fetchRequest()), 0, "状态日志应级联删除")
        XCTAssertEqual(try ctx.count(for: Tag.fetchRequest()), 1, "标签不应被删除")
    }

    func testIdeaIDUniqueConstraintConflictResolvesToSingleRow() throws {
        // 唯一约束在 SQLite 层生效;viewContext 的属性胜出合并策略(DESIGN §11.2)
        // 会自动消解约束冲突:保留内存侧对象、删除旧行,而非向用户抛错。
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ideaflow-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let sut = PersistenceController(tempSQLiteURL: url)
        let ctx = sut.viewContext
        let a = Idea.create(in: ctx, title: nil, content: "a", status: .draft)
        try ctx.save()
        let entity = Idea.entityDescription(in: ctx)
        let b = Idea(entity: entity, insertInto: ctx)
        b.id = a.id   // 故意重复
        b.content = "b"
        b.createdAt = Date()
        b.updatedAt = Date()
        b.statusChangedAt = Date()
        try ctx.save()   // 合并策略消解冲突,不抛错
        let all = try ctx.fetch(Idea.fetchRequest())
        XCTAssertEqual(all.count, 1, "重复 id 冲突应消解为一行")
        XCTAssertEqual(all.first?.content, "b", "属性胜出:内存侧新值存活")
    }

    func testTagNameFindOrCreateIdempotent() throws {
        let ctx = sut.viewContext
        let t1 = Tag.findOrCreate(named: "设计", in: ctx)
        let t2 = Tag.findOrCreate(named: "设计", in: ctx)
        try ctx.save()
        XCTAssertEqual(t1.objectID, t2.objectID)
        XCTAssertEqual(try ctx.count(for: Tag.fetchRequest()), 1)
    }

    func testAttachmentKinds() throws {
        let ctx = sut.viewContext
        let idea = Idea.create(in: ctx, title: nil, content: "x", status: .draft)
        XCTAssertEqual(Attachment.create(in: ctx, idea: idea, kind: .image).kind, .image)
        XCTAssertEqual(Attachment.create(in: ctx, idea: idea, kind: .audio).kind, .audio)
        XCTAssertEqual(Attachment.create(in: ctx, idea: idea, kind: .video).kind, .video)
        XCTAssertEqual(Attachment.create(in: ctx, idea: idea, kind: .file).kind, .file)
        XCTAssertEqual(Attachment.create(in: ctx, idea: idea, kind: .link).kind, .link)
        XCTAssertEqual(AttachmentKind(rawValue: 2), .video)
        XCTAssertNil(AttachmentKind(rawValue: 9))
    }

    func testIdeaStatusRoundtrip() throws {
        let ctx = sut.viewContext
        let idea = Idea.create(in: ctx, title: nil, content: "x", status: .rejected)
        XCTAssertEqual(idea.statusRaw, 3)
        XCTAssertEqual(idea.status, .rejected)
    }
}

