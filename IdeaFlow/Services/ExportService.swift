import Foundation

/// 导出(DESIGN §9.5):Markdown / JSON,写入 Documents/Exports/
enum ExportService {
    struct AttachmentDTO: Codable {
        let kind: String
        let fileName: String?
        let linkURL: String?
        let transcription: String?
        let duration: Double?
    }

    struct IdeaDTO: Codable {
        let id: UUID
        let title: String?
        let content: String?
        let status: String
        let createdAt: Date
        let updatedAt: Date
        let tags: [String]
        let attachments: [AttachmentDTO]
    }

    static func markdown(ideas: [Idea]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var out = "# 灵感集导出\n\n"
        for idea in ideas {
            out += "## \(idea.displayTitle)\n\n"
            out += "- 状态:\(idea.status.displayName)\n"
            out += "- 创建:\(df.string(from: idea.createdAt))\n"
            if !idea.tags.isEmpty {
                out += "- 标签:\(idea.tags.map { "#\($0.name)" }.sorted().joined(separator: " "))\n"
            }
            out += "\n"
            if let content = idea.content, !content.isEmpty {
                out += content + "\n\n"
            }
            for att in idea.attachments.sorted(by: { $0.createdAt < $1.createdAt }) {
                switch att.kind {
                case .link:
                    out += "- 🔗 [\(att.linkTitle ?? att.linkURL ?? "链接")](\(att.linkURL ?? ""))\n"
                case .audio:
                    let seconds = att.duration > 0 ? String(format: "%.0fs", att.duration) : "?"
                    out += "- 🎤 语音 \(seconds)\n"
                    if let t = att.transcription, !t.isEmpty { out += "  > \(t)\n" }
                default:
                    out += "- 📎 \(att.fileName ?? "附件")\n"
                }
            }
            out += "\n---\n\n"
        }
        return out
    }

    static func exportJSON(ideas: [Idea], directory: URL? = nil) throws -> URL {
        let dtos = ideas.map(dto)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dtos)
        let dir = try exportDirectory(directory)
        let url = dir.appendingPathComponent("ideaflow-\(stamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportMarkdown(ideas: [Idea], directory: URL? = nil) throws -> URL {
        let dir = try exportDirectory(directory)
        let url = dir.appendingPathComponent("ideaflow-\(stamp()).md")
        try markdown(ideas: ideas).data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    static func dto(_ idea: Idea) -> IdeaDTO {
        IdeaDTO(
            id: idea.id,
            title: idea.title ?? idea.displayTitle,   // 零必填:导出补齐自动标题
            content: idea.content,
            status: idea.status.shortKey,
            createdAt: idea.createdAt,
            updatedAt: idea.updatedAt,
            tags: idea.tags.map(\.name).sorted(),
            attachments: idea.attachments.sorted { $0.createdAt < $1.createdAt }.map {
                AttachmentDTO(kind: $0.kind.shortKey, fileName: $0.fileName,
                              linkURL: $0.linkURL, transcription: $0.transcription,
                              duration: $0.duration > 0 ? $0.duration : nil)
            }
        )
    }

    private static func exportDirectory(_ override: URL?) throws -> URL {
        let dir: URL
        if let override {
            dir = override
        } else {
            dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Exports", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func stamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }
}

extension IdeaStatus {
    var shortKey: String {
        switch self {
        case .draft: return "draft"
        case .pending: return "pending"
        case .adopted: return "adopted"
        case .rejected: return "rejected"
        case .abandoned: return "abandoned"
        case .archived: return "archived"
        }
    }
}

extension AttachmentKind {
    var shortKey: String {
        switch self {
        case .image: return "image"
        case .audio: return "audio"
        case .video: return "video"
        case .file: return "file"
        case .link: return "link"
        }
    }
}
