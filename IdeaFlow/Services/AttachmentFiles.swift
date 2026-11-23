import Foundation

/// 附件文件布局(DESIGN §10.2):Documents/Attachments/{ideaID}/…
/// 数据库只存相对路径,迁移/备份不失效。
struct AttachmentFiles {
    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Attachments", isDirectory: true)
        }
    }

    func directory(for ideaID: UUID) -> URL {
        root.appendingPathComponent(ideaID.uuidString, isDirectory: true)
    }

    /// 相对路径 → 绝对路径(容忍历史绝对路径)
    func absoluteURL(for relativePath: String) -> URL {
        if relativePath.hasPrefix("/") { return URL(fileURLWithPath: relativePath) }
        return root.appendingPathComponent(relativePath)
    }

    func ensureDirectory(for ideaID: UUID) throws -> URL {
        let dir = directory(for: ideaID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 删除该点子的全部附件文件;目录不存在时静默成功
    func removeFiles(for ideaID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: ideaID))
    }
}
