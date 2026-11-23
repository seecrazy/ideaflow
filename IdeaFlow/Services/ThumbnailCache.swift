import UIKit

/// 缩略图缓存(DESIGN §12):NSCache 内存层 + 磁盘层,主线程只取缓存
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, UIImage>

    init() {
        cache = NSCache()
        cache.totalCostLimit = 50 * 1024 * 1024   // 50MB
    }

    func image(atPath path: String) -> UIImage? {
        let key = path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let ui = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(ui, forKey: key, cost: ui.pngData()?.count ?? 0)
        return ui
    }

    func removeAll() { cache.removeAllObjects() }
}
