import Foundation
import CoreData

/// 程序化 Core Data 模型(DESIGN §10):不依赖 .xcdatamodeld,测试可注入 in-memory。
enum ManagedObjectModel {
    static let shared: NSManagedObjectModel = build()

    private static func build() -> NSManagedObjectModel {
        let idea = NSEntityDescription.name("Idea").cls(Idea.self).attributes { e in
            e.uuid("id", optional: false)
            e.string("title")
            e.string("content")
            e.int16("statusRaw", default: 0)
            e.date("createdAt", optional: false)
            e.date("updatedAt", optional: false)
            e.date("statusChangedAt", optional: false)
            e.bool("isPinned", default: false)
            e.int32("sortOrder", default: 0)
            e.date("deletedAt")
        }
        idea.uniquenessConstraints = [["id"]]
        idea.indexes = [
            NSFetchIndexDescription(name: "byStatusAndCreated", elements: [
                NSFetchIndexElementDescription(property: idea.attribute("statusRaw"), collationType: .binary),
                NSFetchIndexElementDescription(property: idea.attribute("createdAt"), collationType: .binary),
            ]),
            NSFetchIndexDescription(name: "byDeletedAt", elements: [
                NSFetchIndexElementDescription(property: idea.attribute("deletedAt"), collationType: .binary),
            ]),
        ]

        let attachment = NSEntityDescription.name("Attachment").cls(Attachment.self).attributes { e in
            e.uuid("id", optional: false)
            e.int16("typeRaw", default: 0)
            e.string("fileName")
            e.string("localPath")
            e.string("remoteAssetID")
            e.int64("fileSize", default: 0)
            e.string("mimeType")
            e.string("linkURL")
            e.string("linkTitle")
            e.string("linkSummary")
            e.string("thumbnailPath")
            e.string("transcription")
            e.double("duration")
            e.date("createdAt", optional: false)
            e.int16("syncStateRaw", default: 0)
        }
        attachment.uniquenessConstraints = [["id"]]

        let tag = NSEntityDescription.name("Tag").cls(Tag.self).attributes { e in
            e.uuid("id", optional: false)
            e.string("name", optional: false)
            e.string("colorHex")
        }
        tag.uniquenessConstraints = [["name"]]
        tag.indexes = [
            NSFetchIndexDescription(name: "byName", elements: [
                NSFetchIndexElementDescription(property: tag.attribute("name"), collationType: .binary),
            ]),
        ]

        let statusLog = NSEntityDescription.name("StatusLog").cls(StatusLog.self).attributes { e in
            e.uuid("id", optional: false)
            e.int16("fromRaw", default: 0)
            e.int16("toRaw", default: 0)
            e.date("timestamp", optional: false)
            e.string("note")
            e.int16("sourceRaw", default: 0)
        }
        statusLog.uniquenessConstraints = [["id"]]

        let savedFilter = NSEntityDescription.name("SavedFilter").cls(SavedFilter.self).attributes { e in
            e.uuid("id", optional: false)
            e.string("name", optional: false)
            e.binary("filterJSON", optional: false)
            e.int16("sortIndex", default: 0)
        }
        savedFilter.uniquenessConstraints = [["id"]]

        // 关系:删 Idea 级联删附件与日志;标签双向多对多 nullify 保留;层级父子 nullify
        Relationship.connect("tags", idea, sourceIsMany: true, tag, targetIsMany: true, .nullify, inverseName: "ideas")
        Relationship.connect("attachments", idea, sourceIsMany: true, attachment, targetIsMany: false, .cascade, inverseName: "idea")
        Relationship.connect("statusLogs", idea, sourceIsMany: true, statusLog, targetIsMany: false, .cascade, inverseName: "idea")
        Relationship.connect("children", tag, sourceIsMany: true, tag, targetIsMany: false, .nullify, inverseName: "parent")

        let model = NSManagedObjectModel()
        model.entities = [idea, attachment, tag, statusLog, savedFilter]
        return model
    }
}

// MARK: - 构建辅助

private enum DeleteRuleKind {
    case nullify
    case cascade
}

private enum Relationship {
    /// 建立 bidirectional 关系。many 标记各自方向;删除规则作用于 source→target 方向,反向一律 nullify。
    static func connect(_ name: String, _ source: NSEntityDescription, sourceIsMany: Bool,
                        _ target: NSEntityDescription, targetIsMany: Bool,
                        _ rule: DeleteRuleKind, inverseName: String) {
        let rel = NSRelationshipDescription()
        rel.name = name
        rel.destinationEntity = target
        rel.minCount = 0
        rel.maxCount = sourceIsMany ? 0 : 1
        rel.deleteRule = rule == .cascade ? .cascadeDeleteRule : .nullifyDeleteRule
        rel.isOptional = true

        let inv = NSRelationshipDescription()
        inv.name = inverseName
        inv.destinationEntity = source
        inv.minCount = 0
        inv.maxCount = targetIsMany ? 0 : 1
        inv.deleteRule = .nullifyDeleteRule
        inv.isOptional = true

        rel.inverseRelationship = inv
        inv.inverseRelationship = rel
        source.properties.append(rel)
        target.properties.append(inv)
    }
}

private extension NSEntityDescription {
    static func name(_ name: String) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        return e
    }

    func cls(_ type: AnyClass) -> NSEntityDescription {
        managedObjectClassName = NSStringFromClass(type)
        return self
    }

    func attributes(_ build: (EntityAttributeBuilder) -> Void) -> NSEntityDescription {
        let builder = EntityAttributeBuilder(entity: self)
        build(builder)
        return self
    }

    func attribute(_ name: String) -> NSAttributeDescription {
        properties.compactMap { $0 as? NSAttributeDescription }.first { $0.name == name }!
    }
}

private final class EntityAttributeBuilder {
    let entity: NSEntityDescription

    init(entity: NSEntityDescription) {
        self.entity = entity
    }

    private func add(_ attr: NSAttributeDescription) {
        entity.properties.append(attr)
    }

    private func make(_ name: String, _ type: NSAttributeType, optional: Bool, defaultValue: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        if let d = defaultValue { a.defaultValue = d }
        return a
    }

    func uuid(_ name: String, optional: Bool) {
        add(make(name, .UUIDAttributeType, optional: optional))
    }

    func string(_ name: String, optional: Bool = true) {
        add(make(name, .stringAttributeType, optional: optional))
    }

    func date(_ name: String, optional: Bool = true) {
        add(make(name, .dateAttributeType, optional: optional))
    }

    func bool(_ name: String, default def: Bool) {
        add(make(name, .booleanAttributeType, optional: false, defaultValue: def))
    }

    func int16(_ name: String, default def: Int16) {
        add(make(name, .integer16AttributeType, optional: false, defaultValue: def))
    }

    func int32(_ name: String, default def: Int32) {
        add(make(name, .integer32AttributeType, optional: false, defaultValue: def))
    }

    func int64(_ name: String, default def: Int64) {
        add(make(name, .integer64AttributeType, optional: false, defaultValue: def))
    }

    func double(_ name: String, optional: Bool = true) {
        add(make(name, .doubleAttributeType, optional: optional))
    }

    func binary(_ name: String, optional: Bool) {
        add(make(name, .binaryDataAttributeType, optional: optional))
    }
}
