//
// Created on 3/10/20.
//

import Foundation
import Combine
import Logging

class ArchiveDetailsModel: ObservableObject {
    private static let logger = Logger(label: "ArchiveDetailsModel")

    @Published var title = ""
    @Published var tags = ""

    @Published var loading = false
    @Published var successMessage = ""
    @Published var errorMessage = ""

    @Published private(set) var categoryItems = [String: CategoryItem]()

    private let store = AppStore.shared
    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    private var cancellables: Set<AnyCancellable> = []

    init() {
        connectStore()
    }

    func connectStore() {
        categoryItems = store.state.category.categoryItems

        store.state.category.$categoryItems.receive(on: DispatchQueue.main)
                .assign(to: \.categoryItems, on: self)
                .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
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

    func load(title: String, tags: String) {
        self.title = title
        self.tags = tags
    }

    func reset() {
        successMessage = ""
        errorMessage = ""
    }

    @MainActor
    func updateArchive(archive: ArchiveItem) async -> Bool {
        loading = true

        do {
            _ = try await service.updateArchive(archive: archive).value
            do {
                var archiveDto = archive.toArchive()
                try database.saveArchive(&archiveDto)
            } catch {
                ArchiveDetailsModel.logger.error("failed to save archive. id=\(archive.id) \(error)")
            }
            loading = false
            return true
        } catch {
            ArchiveDetailsModel.logger.error("failed to update archive. id=\(archive.id) \(error)")
            loading = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func deleteArchive(id: String) async -> Bool {
        loading = true

        do {
            let response = try await service.deleteArchive(id: id).value
            if response.success == 1 {
                do {
                    let success = try database.deleteArchive(id)
                    if success {
                        _ = try? database.deleteArchiveThumbnail(id)
                    }
                    else {
                        ArchiveDetailsModel.logger.error("failed to delete archive from db. id=\(id)")
                    }
                } catch {
                    ArchiveDetailsModel.logger.error("failed to delete archive from db. id=\(id) \(error)")
                }
                loading = false
                return true
            } else {
                errorMessage = NSLocalizedString("error.archive.delete", comment: "error")
                loading = false
                return false
            }
        } catch {
            ArchiveDetailsModel.logger.error("failed to delete archive. id=\(id) \(error)")
            loading = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func addArchiveToCategory(categoryId: String, archiveId: String) async {
        loading = true
        let currentCategory = categoryItems[categoryId]!

        if currentCategory.archives.contains(archiveId) {
            return
        }

        var success = false

        do {
            let response = try await service.addArchiveToCategory(categoryId: categoryId, archiveId: archiveId).value
            if response.success == 1 {
                success = true
            }
        } catch {
            ArchiveDetailsModel.logger.error(
                "failed to add archive to category categoryId=\(categoryId), archiveId=\(archiveId) \(error)"
            )
        }

        var currentArchives = currentCategory.archives
        currentArchives.append(archiveId)
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

        if success {
            successMessage = NSLocalizedString("archive.category.add.success", comment: "success")
        } else {
            errorMessage = NSLocalizedString("archive.category.add.error", comment: "error")
        }
        loading = false
    }

    @MainActor
    func removeArchiveToCategory(categoryId: String, archiveId: String) async {
        loading = true
        let currentCategory = categoryItems[categoryId]!

        if !currentCategory.archives.contains(archiveId) {
            return
        }

        var success = false

        do {
            let response = try await service.removeArchiveFromCategory(
                categoryId: categoryId,
                archiveId: archiveId
            ).value
            if response.success == 1 {
                success = true
            }
        } catch {
            ArchiveDetailsModel.logger.error(
                "failed to remove archive from category categoryId=\(categoryId), archiveId=\(archiveId) \(error)"
            )
        }

        var currentArchives = currentCategory.archives
        currentArchives.removeAll(where: { id in
            id == archiveId
        })
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

        if success {
            successMessage = NSLocalizedString("archive.category.remove.success", comment: "success")
        } else {
            errorMessage = NSLocalizedString("archive.category.remove.error", comment: "error")
        }
        loading = false
    }
}
