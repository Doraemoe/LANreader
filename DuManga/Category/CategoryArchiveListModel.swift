//
// Created on 6/10/20.
//

import Foundation
import Combine

class CategoryArchiveListModel: ObservableObject {
    private static let newCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: true,
            initResult: [ArchiveItem]())
    private static let dynamicCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())
    private static let staticCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())

    @Published private(set) var loading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var dynamicCategoryKeys = [String]()
    @Published private(set) var errorCode: ErrorCode?
    @Published private(set) var filteredArchives: [ArchiveItem] = []

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState) {
        state.archive.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)

        state.archive.$dynamicCategoryKeys.receive(on: DispatchQueue.main)
                .assign(to: \.dynamicCategoryKeys, on: self)
                .store(in: &cancellable)

        state.archive.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }

    func filterArchives(categoryItem: CategoryItem) {
        if categoryItem.isNew {
            filteredArchives = CategoryArchiveListModel.newCategorySelector.select(
                    base: archiveItems,
                    filter: true,
                    selector: { (base, _) in
                        let filtered = base.filter { item in
                            item.value.isNew == true
                        }
                        return Array(filtered.values)
                    })
        } else if !categoryItem.search.isEmpty {
            filteredArchives = CategoryArchiveListModel.dynamicCategorySelector.select(
                    base: archiveItems,
                    filter: dynamicCategoryKeys,
                    selector: { (base, filter) in
                        let filtered = base.filter { item in
                            filter.contains(item.key)
                        }
                        return Array(filtered.values)
                    })

        } else {
            filteredArchives = CategoryArchiveListModel.staticCategorySelector.select(
                    base: archiveItems,
                    filter: categoryItem.archives,
                    selector: { (base, filter) in
                        let filtered = base.filter { item in
                            filter.contains(item.key)
                        }
                        return Array(filtered.values)
                    })
        }
    }
}
