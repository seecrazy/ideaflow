import Foundation
import LinkPresentation

/// 链接元数据抓取(DESIGN §4.4):LinkPresentation,5s 超时降级为"仅 URL + host 标题"。
struct LinkMeta: Equatable {
    let url: URL
    let title: String
    let summary: String?
}

final class LinkMetadataService {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    func fetchMetadata(for url: URL) async -> LinkMeta {
        do {
            let metadata = try await withTimeout(seconds: timeout) {
                try await LPMetadataProvider().startFetchingMetadata(for: url)
            }
            let title = metadata.title ?? url.host ?? url.absoluteString
            let summary = metadata.value(forKey: "summary") as? String
            return LinkMeta(url: url, title: title, summary: (summary?.isEmpty ?? true) ? nil : summary)
        } catch {
            // 失败:仅存 URL + host(DESIGN §4.4 链接收藏降级路径)
            return LinkMeta(url: url, title: url.host ?? url.absoluteString, summary: nil)
        }
    }

    private func withTimeout<T: Any>(seconds: TimeInterval, _ work: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return first
        }
    }
}
