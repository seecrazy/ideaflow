import Foundation
import SwiftUI
import CoreData

/// 组合根:一处装配全部服务,注入 environmentObject。
@MainActor
final class AppEnvironment: ObservableObject {
    let persistence: PersistenceController
    let store: IdeaStore
    let searchService: SearchService
    let draftService: DraftService
    let mediaStore: MediaStore
    let linkService: LinkMetadataService
    let appLock = AppLockService()

    /// 首页草稿恢复提示
    @Published var pendingDraftText: String?
    /// 输入条当前文本(退后台时立即落草稿用)
    @Published var currentInputText: String = ""
    /// 回收站删除反馈(撤销提示条)
    @Published var recycleToast: RecycleToast?

    init(persistence: PersistenceController = PersistenceController.shared) {
        self.persistence = persistence
        let store = IdeaStore(persistence: persistence)
        self.store = store
        let indexURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SearchIndex.sqlite")
        let search = SearchService(index: SearchIndexDatabase(url: indexURL))
        search.attach(to: store)
        self.searchService = search
        self.draftService = DraftService()
        self.mediaStore = MediaStore()
        self.linkService = LinkMetadataService()

        if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
            self.resetForUITests()
        }

        pendingDraftText = draftService.draft?.text

        // 回收站保留期清理(DESIGN §13:启动时清理)
        let retention = UserDefaults.standard.integer(forKey: "recycleRetentionDays")
        try? store.purgeExpired(retentionDays: retention > 0 ? retention : 30, files: AttachmentFiles())

        if ProcessInfo.processInfo.arguments.contains("-seedDemo") {
            DemoSeeder.seedIfNeeded(store: store)
            search.flushIndex()
        } else if search.index.indexedCount == 0 {
            // 老库升级(FTS 结构变更 DROP 后)/索引意外为空 → 全量重建
            let req = Idea.fetchRequest()
            req.predicate = NSPredicate(format: "deletedAt == nil")
            if ((try? store.ctx.fetch(req))?.isEmpty == false) {
                search.rebuildIndexFromStore()
                search.flushIndex()
            }
        }
    }
    /// UI 测试隔离:清空全部数据与草稿
    private func resetForUITests() {
        draftService.clear()
        UserDefaults.standard.removeObject(forKey: "ideaflow.search.history")
        searchService.index.rebuild(with: [])   // 索引随数据一并清空
        let coordinator = persistence.container.persistentStoreCoordinator
        for entity in ["StatusLog", "Attachment", "Idea", "Tag", "SavedFilter"] {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
            _ = try? coordinator.execute(delete, with: persistence.viewContext)
        }
        persistence.viewContext.reset()
    }
}

extension SearchService {
    /// 全量重建索引(设置页"重建搜索索引"与种子模式入口)
    func rebuildIndexFromStore() {
        guard let ctx = store?.ctx else { return }
        let req = Idea.fetchRequest()
        req.predicate = NSPredicate(format: "deletedAt == nil")
        let ideas = (try? ctx.fetch(req)) ?? []
        let docs = ideas.map { SearchService.document(for: $0) }
        queue.async { [index] in
            index.rebuild(with: docs)
        }
    }
}