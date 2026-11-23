import XCTest
import UIKit
import AVFoundation
import CoreData
@testable import IdeaFlow

@MainActor
final class MediaExportTests: XCTestCase {
    var persistence: PersistenceController!
    var store: IdeaStore!
    var tmpRoot: URL!
    var media: MediaStore!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        store = IdeaStore(persistence: persistence)
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-test-\(UUID().uuidString)", isDirectory: true)
        media = MediaStore(files: AttachmentFiles(root: tmpRoot))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
        super.tearDown()
    }

    private func bigImageData(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.95)!
    }

    // DESIGN §12:原图最长边 2048 / JPEG 0.8;缩略图 400px / 0.7;布局 Attachments/{ideaID}/
    func testSaveImageCompressesAndLaysOut() throws {
        let ideaID = UUID()
        let saved = try media.saveImage(bigImageData(size: CGSize(width: 3000, height: 2000)), ideaID: ideaID)

        XCTAssertTrue(saved.relativePath.hasPrefix(ideaID.uuidString + "/"), "相对路径以 ideaID 目录开头")
        XCTAssertTrue(saved.relativePath.hasSuffix(".jpg"))

        let fullURL = AttachmentFiles(root: tmpRoot).absoluteURL(for: saved.relativePath)
        XCTAssertEqual(pixelSize(of: fullURL), CGSize(width: 2048, height: 1365), "原图最长边压到 2048")

        let thumbURL = AttachmentFiles(root: tmpRoot).absoluteURL(for: saved.thumbRelativePath)
        let thumbPixels = pixelSize(of: thumbURL)
        XCTAssertLessThanOrEqual(max(thumbPixels.width, thumbPixels.height), 400, "缩略图最长边 ≤ 400")

        XCTAssertGreaterThan(saved.fileSize, 0)
        let data = try Data(contentsOf: thumbURL)
        XCTAssertEqual(Data(data.prefix(2)), Data([0xFF, 0xD8]), "仍是 JPEG")
    }

    private func pixelSize(of url: URL) -> CGSize {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        let w = props[kCGImagePropertyPixelWidth] as! CGFloat
        let h = props[kCGImagePropertyPixelHeight] as! CGFloat
        return CGSize(width: w, height: h)
    }

    func testAudioSettingsAreAAC64kMono() {
        let settings = MediaStore.audioSettings
        XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 44100)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVEncoderBitRateKey as String] as? Int, 64_000)
    }

    // DESIGN §4.4:链接抓取失败 → 仅存 URL + host 兜底标题
    func testLinkMetadataFallbackToHost() async {
        let service = LinkMetadataService()
        let meta = await service.fetchMetadata(for: URL(string: "https://127.0.0.1:1/nothing")!)
        XCTAssertEqual(meta.title, "127.0.0.1", "失败时标题回退为 host")
        XCTAssertEqual(meta.url.absoluteString, "https://127.0.0.1:1/nothing")
    }

    // MARK: - 导出

    private func sampleIdea() throws -> Idea {
        let idea = store.capture(text: "导出测试\n正文内容", tagNames: ["产品"])!
        store.transition(idea, to: .pending)
        let att = Attachment.create(in: persistence.viewContext, idea: idea, kind: .link)
        att.linkURL = "https://example.com"
        att.linkTitle = "示例链接"
        try persistence.viewContext.save()
        return idea
    }

    func testExportMarkdown() throws {
        let idea = try sampleIdea()
        let md = ExportService.markdown(ideas: [idea])
        XCTAssertTrue(md.contains("导出测试"), "含标题")
        XCTAssertTrue(md.contains("正文内容"), "含正文")
        XCTAssertTrue(md.contains("待处理"), "含状态")
        XCTAssertTrue(md.contains("#产品"), "含标签")
        XCTAssertTrue(md.contains("https://example.com"), "含链接附件")
    }

    func testExportJSONRoundtrip() throws {
        let idea = try sampleIdea()
        let url = try ExportService.exportJSON(ideas: [idea], directory: tmpRoot)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dtos = try decoder.decode([ExportService.IdeaDTO].self, from: data)
        XCTAssertEqual(dtos.count, 1)
        XCTAssertEqual(dtos.first?.title, "导出测试")
        XCTAssertEqual(dtos.first?.status, "pending")
        XCTAssertEqual(dtos.first?.tags, ["产品"])
        XCTAssertEqual(dtos.first?.attachments.first?.linkURL, "https://example.com")
    }
}
