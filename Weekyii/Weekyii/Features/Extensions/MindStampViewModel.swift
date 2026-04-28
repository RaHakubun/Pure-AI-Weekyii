import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MindStampViewModel {
    private let modelContext: ModelContext

    var stamps: [MindStampItem] = []
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Refresh

    func refresh() {
        errorMessage = nil
        let descriptor = FetchDescriptor<MindStampItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        stamps = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Create

    @discardableResult
    func createStamp(text: String, imageBlob: Data?) -> MindStampItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageBlob != nil else {
            errorMessage = String(localized: "mindstamp.error.empty")
            return nil
        }

        let item = MindStampItem(text: trimmed, imageBlob: imageBlob)
        modelContext.insert(item)

        do {
            try modelContext.save()
            refresh()
            return item
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Update

    func updateStamp(_ item: MindStampItem, text: String, imageBlob: Data?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageBlob != nil else {
            errorMessage = String(localized: "mindstamp.error.empty")
            return
        }

        item.text = trimmed
        item.imageBlob = imageBlob

        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    func deleteStamp(_ item: MindStampItem) {
        modelContext.delete(item)
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Random Stamp for Ritual

    func randomStamp() -> MindStampItem? {
        stamps.randomElement()
    }
}
