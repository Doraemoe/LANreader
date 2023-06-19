import Foundation
import Combine
import Logging

class ArchiveSelectionModel: ObservableObject {
    private static let logger = Logger(label: "ArchiveSelectionModel")

    @Published private(set) var loading = false
    @Published private(set) var categoryItems = [String: CategoryItem]()
    @Published private(set) var successMessage = ""
    @Published private(set) var errorMessage = ""

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
        categoryItems = store.state.category.categoryItems

        store.state.archive.$randomOrderSeed.receive(on: DispatchQueue.main)
                .assign(to: \.randomSeed, on: self)
                .store(in: &cancellables)

        store.state.category.$categoryItems.receive(on: DispatchQueue.main)
                .assign(to: \.categoryItems, on: self)
                .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
    }

    func reset() {
        successMessage = ""
        errorMessage = ""
    }

    func fetchCategories() async {
        await store.dispatch(fetchCategory(fromServer: false))
    }

    func getStaticCategories() -> [CategoryItem] {
        var staticCategories = [CategoryItem]()
        categoryItems.forEach { (_, value) in
            if value.search.isEmpty {
                staticCategories.append(value)
            }
        }
        return staticCategories.sorted(by: { $0.name < $1.name })
    }

    @MainActor
    func addArchivesToCategory(categoryId: String, archiveIds: Set<String>) async -> Set<String> {
        loading = true
        var successIds: Set<String> = .init()
        var errorIds: Set<String> = .init()
        let currentCategory = categoryItems[categoryId]!

        for id in archiveIds {
            if currentCategory.archives.contains(id) {
                successIds.insert(id)
                continue
            }
            do {
                let response = try await service.addArchiveToCategory(categoryId: categoryId, archiveId: id).value
                if response.success == 1 {
                    successIds.insert(id)
                } else {
                    errorIds.insert(id)
                }
            } catch {
                ArchiveSelectionModel.logger.error(
                    "failed to add archive to category categoryId=\(categoryId), archiveId=\(id) \(error)"
                )
                errorIds.insert(id)
            }
        }

        var currentArchives = currentCategory.archives
        currentArchives.append(contentsOf: successIds)
        let newCategoryItem = CategoryItem(
            id: categoryId,
            name: currentCategory.name,
            archives: currentArchives,
            search: currentCategory.search,
            pinned: currentCategory.pinned
        )
        store.dispatch(.category(action: .updateCategory(category: newCategoryItem)))

        var category = newCategoryItem.toCategory()
        _ = try? database.saveCategory(&category)

        if !errorIds.isEmpty {
            ArchiveSelectionModel.logger.error("failed to add archives to category ids=\(errorIds)")
            errorMessage = NSLocalizedString("archive.selected.category.add.error", comment: "error")
        } else {
            successMessage = NSLocalizedString("archive.selected.category.add.success", comment: "success")
        }

        loading = false
        return successIds
    }

    @MainActor
    func removeArchivesFromCategory(categoryId: String, archiveIds: Set<String>) async -> Set<String> {
        loading = true
        var successIds: Set<String> = .init()
        var errorIds: Set<String> = .init()
        let currentCategory = categoryItems[categoryId]!

        for id in archiveIds {
            if !currentCategory.archives.contains(id) {
                successIds.insert(id)
                continue
            }
            do {
                let response = try await service.removeArchiveFromCategory(categoryId: categoryId, archiveId: id).value
                if response.success == 1 {
                    successIds.insert(id)
                } else {
                    errorIds.insert(id)
                }
            } catch {
                ArchiveSelectionModel.logger.error(
                    "failed to remove archive from category categoryId=\(categoryId), archiveId=\(id) \(error)"
                )
                errorIds.insert(id)
            }
        }

        var currentArchives = currentCategory.archives
        for id in successIds {
            currentArchives.removeAll { archiveId in
                id == archiveId
            }
        }
        let newCategoryItem = CategoryItem(
            id: categoryId,
            name: currentCategory.name,
            archives: currentArchives,
            search: currentCategory.search,
            pinned: currentCategory.pinned
        )
        store.dispatch(.category(action: .updateCategory(category: newCategoryItem)))

        var category = newCategoryItem.toCategory()
        _ = try? database.saveCategory(&category)

        if !errorIds.isEmpty {
            ArchiveSelectionModel.logger.error("failed to remove archives from category ids=\(errorIds)")
            errorMessage = NSLocalizedString("archive.selected.category.remove.error", comment: "error")
        } else {
            successMessage = NSLocalizedString("archive.selected.category.remove.success", comment: "success")
        }

        loading = false
        return successIds
    }

    func processArchives(archives: [ArchiveItem], sortOrder: String) -> [ArchiveItem] {
        var archivesToProcess = archives

        if sortOrder == ArchiveListOrder.name.rawValue {
            archivesToProcess = archivesToProcess.sorted(by: { $0.normalizedName < $1.normalizedName })
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
        } else {
            successMessage = NSLocalizedString("archive.selected.delete.success", comment: "success")
        }

        loading = false
        return successIds
    }
}
