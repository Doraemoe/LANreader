import Foundation
import Combine
import Logging

class ArchiveSelectionModel: ObservableObject {
    private static let logger = Logger(label: "ArchiveSelectionModel")

    @Published var loading = false
    @Published var errorMessage = ""

    private var randomSeed: UInt64 = 1
    private var cancellables: Set<AnyCancellable> = []

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private let store = AppStore.shared

    init() {
        connectStore()
    }

    func connectStore() {
        randomSeed = store.state.archive.randomOrderSeed

        store.state.archive.$randomOrderSeed.receive(on: DispatchQueue.main)
                .assign(to: \.randomSeed, on: self)
                .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
    }

    func reset() {
        errorMessage = ""
    }

    func processArchives(archives: [ArchiveItem], sortOrder: String) -> [ArchiveItem] {
        var archivesToProcess = archives

        if sortOrder == ArchiveListOrder.name.rawValue {
            archivesToProcess = archivesToProcess.sorted(by: { $0.name < $1.name })
        } else if sortOrder == ArchiveListOrder.dateAdded.rawValue {
            archivesToProcess = archivesToProcess.sorted { item, item2 in
                let dateAdded1 = item.dateAdded
                let dateAdded2 = item2.dateAdded
                if dateAdded1 != nil && dateAdded2 != nil {
                    return dateAdded1! > dateAdded2!
                } else if dateAdded1 != nil {
                    return true
                } else if dateAdded2 != nil {
                    return false
                } else {
                    return item.name < item2.name
                }
            }

        } else if sortOrder == ArchiveListOrder.random.rawValue {
            var generator = FixedRandomGenerator(seed: randomSeed)
            archivesToProcess = archivesToProcess.shuffled(using: &generator)
        }

        var seenId = Set<String>()
        var distinctArchives = [ArchiveItem]()
        archivesToProcess.forEach { item in
            let (success, _) = seenId.insert(item.id)
            if success {
                distinctArchives.append(item)
            }
        }
        return distinctArchives
    }

    @MainActor
    func deleteArchives(ids: Set<String>) async -> Set<String> {
        loading = true
        var successIds: Set<String> = .init()
        var errorIds: Set<String> = .init()

        for id in ids {
            do {
                let response = try await service.deleteArchive(id: id).value
                if response.success == 1 {
                    _ = try? database.deleteArchive(id)
                    _ = try? database.deleteArchiveThumbnail(id)
                    store.dispatch(.archive(action: .removeDeletedArchive(id: id)))
                    successIds.insert(id)
                } else {
                    errorIds.insert(id)
                }
            } catch {
                ArchiveSelectionModel.logger.error("failed to delete archive id=\(id) \(error)")
                errorIds.insert(id)
            }
        }

        if !errorIds.isEmpty {
            ArchiveSelectionModel.logger.error("failed to delete some archive ids=\(errorIds)")
            errorMessage = NSLocalizedString("archive.selected.delete.error", comment: "error")
        }

        loading = false
        return successIds
    }
}
