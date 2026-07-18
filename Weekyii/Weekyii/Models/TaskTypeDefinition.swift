import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskTypeDefinition {
    @Attribute(.unique) var idRaw: String
    var name: String
    var iconName: String
    var colorHex: String
    var baseKindRaw: String
    var sortOrder: Int
    var isBuiltIn: Bool
    var isArchived: Bool

    init(
        idRaw: String = UUID().uuidString,
        name: String,
        iconName: String,
        colorHex: String,
        baseKind: TaskType,
        sortOrder: Int,
        isBuiltIn: Bool = false,
        isArchived: Bool = false
    ) {
        self.idRaw = idRaw
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.baseKindRaw = baseKind.rawValue
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
        self.isArchived = isArchived
    }

    var baseKind: TaskType {
        get { TaskType(rawValue: baseKindRaw) ?? .regular }
        set { baseKindRaw = newValue.rawValue }
    }

    var color: Color {
        Color(hex: colorHex)
    }

    static func builtInDefinitions() -> [TaskTypeDefinition] {
        [
            TaskTypeDefinition(
                idRaw: TaskType.regular.rawValue,
                name: TaskType.regular.displayName,
                iconName: TaskType.regular.iconName,
                colorHex: "#4A90A4",
                baseKind: .regular,
                sortOrder: 0,
                isBuiltIn: true
            ),
            TaskTypeDefinition(
                idRaw: TaskType.ddl.rawValue,
                name: TaskType.ddl.displayName,
                iconName: TaskType.ddl.iconName,
                colorHex: "#C46A1A",
                baseKind: .ddl,
                sortOrder: 1,
                isBuiltIn: true
            ),
            TaskTypeDefinition(
                idRaw: TaskType.leisure.rawValue,
                name: TaskType.leisure.displayName,
                iconName: TaskType.leisure.iconName,
                colorHex: "#8B5A83",
                baseKind: .leisure,
                sortOrder: 2,
                isBuiltIn: true
            )
        ]
    }
}

struct TaskTypeCatalog {
    let definitions: [TaskTypeDefinition]

    var activeDefinitions: [TaskTypeDefinition] {
        definitions
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static var builtInFallback: TaskTypeDefinition {
        TaskTypeDefinition.builtInDefinitions()[0]
    }

    static func load(in context: ModelContext) throws -> TaskTypeCatalog {
        try seedBuiltInTypesIfNeeded(in: context)
        let descriptor = FetchDescriptor<TaskTypeDefinition>()
        return TaskTypeCatalog(definitions: try context.fetch(descriptor))
    }

    static func seedBuiltInTypesIfNeeded(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<TaskTypeDefinition>())
        let existingIds = Set(existing.map(\.idRaw))
        for definition in TaskTypeDefinition.builtInDefinitions() where !existingIds.contains(definition.idRaw) {
            context.insert(definition)
        }

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        for task in tasks where task.taskTypeIdRaw.isEmpty {
            task.taskTypeIdRaw = task.taskType.rawValue
        }

        let suspended = try context.fetch(FetchDescriptor<SuspendedTaskItem>())
        for task in suspended where task.taskTypeIdRaw.isEmpty {
            task.taskTypeIdRaw = task.taskType.rawValue
        }

        if context.hasChanges {
            try context.save()
        }
    }

    func definition(for idRaw: String) -> TaskTypeDefinition {
        definitions.first { $0.idRaw == idRaw } ?? definitions.first { $0.idRaw == TaskType.regular.rawValue } ?? Self.builtInFallback
    }

    func baseKind(for idRaw: String) -> TaskType {
        definition(for: idRaw).baseKind
    }
}

struct TaskTypePresentation {
    let name: String
    let iconName: String
    let color: Color
    let baseKind: TaskType

    init(definition: TaskTypeDefinition) {
        name = definition.name
        iconName = definition.iconName
        color = definition.color
        baseKind = definition.baseKind
    }

    init(fallback: TaskType) {
        name = fallback.displayName
        iconName = fallback.iconName
        color = fallback.color
        baseKind = fallback
    }
}

struct TaskTypePresentationCatalog {
    private let presentationsByID: [String: TaskTypePresentation]

    init(definitions: [TaskTypeDefinition] = []) {
        presentationsByID = definitions.reduce(into: [:]) { result, definition in
            result[definition.idRaw] = TaskTypePresentation(definition: definition)
        }
    }

    func resolve(idRaw: String, fallback: TaskType) -> TaskTypePresentation {
        presentationsByID[idRaw] ?? TaskTypePresentation(fallback: fallback)
    }
}

private struct TaskTypePresentationCatalogKey: EnvironmentKey {
    static let defaultValue = TaskTypePresentationCatalog()
}

extension EnvironmentValues {
    var taskTypePresentationCatalog: TaskTypePresentationCatalog {
        get { self[TaskTypePresentationCatalogKey.self] }
        set { self[TaskTypePresentationCatalogKey.self] = newValue }
    }
}
