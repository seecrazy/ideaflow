import Foundation
import CoreData

/// Core Data 栈。本地库开文件保护;测试用 in-memory。
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "IdeaFlow", managedObjectModel: ManagedObjectModel.shared)
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("missing persistent store description")
        }
        if inMemory {
            description.type = NSInMemoryStoreType
        } else {
            // DESIGN §14:本地加密,FileProtection complete
            description.setOption(FileProtectionType.complete as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
        }
        load(description)
    }

    /// 临时 SQLite store:唯一约束等仅 SQLite 生效的行为,测试用它对齐生产
    init(tempSQLiteURL url: URL) {
        container = NSPersistentContainer(name: "IdeaFlow", managedObjectModel: ManagedObjectModel.shared)
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("missing persistent store description")
        }
        description.url = url
        load(description)
    }

    private func load(_ description: NSPersistentStoreDescription) {
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data store failed to load: \(error)")
            }
        }
        // CloudKit 前置:对象侧胜出的字段级合并策略,离线编辑不覆盖
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    func saveIfNeeded(_ ctx: NSManagedObjectContext) throws {
        guard ctx.hasChanges else { return }
        try ctx.save()
    }

    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
