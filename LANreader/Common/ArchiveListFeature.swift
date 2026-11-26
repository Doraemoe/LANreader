import ComposableArchitecture
import Foundation
import Logging
import OrderedCollections
import SwiftUI

// swiftlint:disable type_body_length
@Reducer public struct ArchiveListFeature: Sendable {
    private let logger = Logger(label: "ArchiveListFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @SharedReader(.appStorage(SettingsKey.searchSortCustom)) var searchSortCustom = ""
        @Shared(.appStorage(SettingsKey.hideRead)) var hideRead = false
        @Shared(.appStorage(SettingsKey.paginateArchiveList)) var paginateArchiveList = false
        @Shared(.appStorage(SettingsKey.searchSort)) var searchSort = SearchSort.dateAdded.rawValue
        @Shared(.appStorage(SettingsKey.searchSortOrder)) var searchSortOrder = SearchSortOrder.asc.rawValue
        @Shared(.appStorage(SettingsKey.lastTagRefresh)) var lastTagRefresh = 0.0

        let searchCancellationID = UUID()
        var selectMode: EditMode = .inactive
        var selected: OrderedSet<String> = .init()
        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var filter: SearchFilter
        var loadOnAppear = true
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var batchActionInProgress = false
        var total: Int = 0
        var errorMessage = ""
        var successMessage = ""
        var cachingArchiveIds: Set<String> = []
        var batchCachingArchiveIds: Set<String> = []
        var batchCacheHadSuccess = false
        var batchCacheErrors: Set<String> = []
        var preserveSelectionOnNextPopulate = false
        var currentTab: TabName

        var archivesToDisplay: IdentifiedArrayOf<GridFeature.State> = []

        /// Zero-based index of the page currently shown in pagination mode.
        var currentPage = 0
        var pendingPage: Int?
        /// Items returned per request. LANraragi has no page-size parameter, so this is
        /// discovered from a page-zero response rather than chosen by the app.
        var serverPageSize = 0

        var pageCount: Int {
            PaginationPositioning.pageCount(total: total, pageSize: serverPageSize)
        }

        // Library/category can load an unfiltered list; Search treats an empty filter as no query yet.
        var canLoadArchives: Bool {
            currentTab != .search || hasSearchFilter
        }

        var showsReadFilterEmptyState: Bool {
            hideRead && !loading && !archives.isEmpty && archivesToDisplay.isEmpty
                && (paginationActive || archives.count >= total)
        }

        var canStartBatchAction: Bool {
            !loading && !batchActionInProgress && !selected.isEmpty
                && !selected.contains(where: cachingArchiveIds.contains)
        }

        private var hasSearchFilter: Bool {
            guard currentTab == .search else { return true }
            if filter.category != nil {
                return true
            }
            return filter.filter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    public enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case loadCategory
        case tagsRefreshed
        case populateCategory([CategoryItem])
        case addArchivesToCategory(String)
        case addArchivesToCategoryFinished(String, Set<String>, Bool)
        case createTankoubon(String)
        case createTankoubonSucceeded
        case createTankoubonFailed(String)
        case reloadFromFirstPage
        case load
        case populateArchives([ArchiveItem], Int, Bool)
        case refreshThumbnail(String)
        case appendArchives(String)
        case cacheArchive(String)
        case cacheSelected
        case toggleSelectionMode
        case cacheArchiveFinished(String)
        case cacheArchiveFailed(String, String)
        case setErrorMessage(String)
        case setSuccessMessage(String)
        case addSelect(String)
        case removeSelect(String)
        case refreshDisplayArchives

        case setSearchSortOrder(String)
        case setSearchSort(String)
        case toggleHideRead
        case goToPage(Int)

        case confirmDelete
        case deleteFinished(Set<String>, Bool)
        case confirmRemoveFromCategory
        case removeFromCategoryFinished(String, Set<String>, Bool)
        case openReader(archiveId: String, fromStart: Bool)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .tagsRefreshed:
                state.$lastTagRefresh.withLock { $0 = Date().timeIntervalSince1970 }
                return .none
            case .toggleSelectionMode:
                guard !state.batchActionInProgress else { return .none }
                if state.selectMode != .active && state.loading {
                    guard !state.archivesToDisplay.isEmpty else { return .none }
                    state.loading = false
                    state.pendingPage = nil
                    state.selectMode = .active
                    state.selected.removeAll()
                    return .cancel(id: state.searchCancellationID)
                }
                state.selectMode = state.selectMode == .active ? .inactive : .active
                state.selected.removeAll()
                return .none
            case .cacheSelected:
                guard state.canStartBatchAction else { return .none }
                let ids = state.selected.sorted()
                let previous = state.cachingArchiveIds
                let effects = ids.map { cacheArchive(state: &state, id: $0) }
                state.batchCachingArchiveIds.formUnion(state.cachingArchiveIds.subtracting(previous))
                state.selected.formIntersection(state.batchCachingArchiveIds)
                return .merge(effects)
            case .reloadFromFirstPage:
                resetArchives(state: &state)
                guard state.canLoadArchives else {
                    clearArchives(state: &state)
                    return .cancel(id: state.searchCancellationID)
                }
                return loadArchives(state: &state, page: 0)
            case .load:
                guard state.canLoadArchives else {
                    clearArchives(state: &state)
                    return .none
                }
                guard state.loading == false else {
                    return .none
                }
                // A reload keeps the page the user is on, so pull-to-refresh reloads what is on
                // screen. Every path that means "start over" sends `reloadFromFirstPage` instead,
                // which is what puts the pager back on the first page.
                let page = state.paginationActive
                    ? PaginationPositioning.clampedPage(state.currentPage, pageCount: state.pageCount)
                    : 0
                return loadArchives(state: &state, page: page)
            case let .appendArchives(start):
                guard state.canLoadArchives, state.selectMode != .active else {
                    return .none
                }
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                let sortby = state.searchSort
                let order = state.searchSortOrder
                return self.search(
                    searchFilter: state.filter,
                    sort: (by: sortby, order: order),
                    start: start,
                    append: true,
                    cancellationID: state.searchCancellationID
                )
            case let .populateArchives(archives, total, append):
                archives.forEach { item in
                    state.$archiveItems.withLock {
                        _ = $0.updateOrAppend(item)
                    }
                }
                let gridFeatureState = archives.compactMap { item in
                    Shared(state.$archiveItems[id: item.id])
                }.map {
                    GridFeature.State(archive: $0)
                }
                if let pendingPage = state.pendingPage {
                    state.currentPage = pendingPage
                    state.pendingPage = nil
                }
                if !append {
                    state.archives = .init()
                    state.archivesToDisplay = .init()
                    state.total = 0
                }
                let visibleCountBefore = state.archivesToDisplay.count
                state.archives.append(contentsOf: gridFeatureState)

                // LANraragi exposes no page-size parameter, so the size is inferred from a
                // full page-zero response. Later pages can be short, which is why only page
                // zero is trusted to define it.
                if !append, state.currentPage == 0, !archives.isEmpty {
                    state.serverPageSize = archives.count
                }

                if state.hideRead {
                    let result = state.archives.filter {
                        $0.archive.pagecount != $0.archive.progress
                    }
                    state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
                } else {
                    state.archivesToDisplay = state.archives
                }

                state.total = total
                state.loading = false

                // Archives removed elsewhere can shrink the list past the page being reloaded.
                // Fall back to the last valid page instead of leaving an empty grid behind.
                if !append, state.paginationActive, state.pageCount > 0, state.currentPage >= state.pageCount {
                    state.currentPage = PaginationPositioning.clampedPage(
                        state.currentPage, pageCount: state.pageCount
                    )
                    return .send(.load)
                }
                if state.preserveSelectionOnNextPopulate {
                    state.preserveSelectionOnNextPopulate = false
                } else {
                    state.selected.formIntersection(state.archivesToDisplay.ids)
                }
                if !archives.isEmpty, state.archivesToDisplay.count == visibleCountBefore,
                   state.canAppendHiddenArchives {
                    return .send(.appendArchives(String(state.archives.count)))
                }
                return .none
            case let .refreshThumbnail(archiveId):
                if state.archivesToDisplay.contains(where: { $0.id == archiveId }) {
                    return .send(.grid(.element(id: archiveId, action: .load(true))))
                } else {
                    return .none
                }
            case let .cacheArchive(id):
                return cacheArchive(state: &state, id: id)
            case let .cacheArchiveFinished(id):
                state.cachingArchiveIds.remove(id)
                finishCaching(state: &state, id: id, succeeded: true)
                return .none
            case let .cacheArchiveFailed(id, message):
                state.cachingArchiveIds.remove(id)
                finishCaching(state: &state, id: id, succeeded: false, error: message)
                return .none
            case let .setErrorMessage(message):
                guard !message.isEmpty else {
                    state.errorMessage = ""
                    return .none
                }
                state.loading = false
                state.pendingPage = nil
                state.preserveSelectionOnNextPopulate = false
                state.errorMessage = message
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            case .grid:
                return .none
            case let .addSelect(id):
                guard !state.loading, state.selectMode == .active,
                      state.archivesToDisplay[id: id] != nil else { return .none }
                state.selected.append(id)
                return .none
            case let .removeSelect(id):
                guard !state.loading else { return .none }
                state.selected.remove(id)
                return .none
            case .refreshDisplayArchives:
                let before = state.archives.count
                let filteredGridFeatureState = state.archives.filter { gridState in
                    state.archiveItems[id: gridState.archive.id] != nil
                }
                let after = filteredGridFeatureState.count
                let diff = before - after
                state.total -= diff

                state.archives = filteredGridFeatureState

                if state.hideRead {
                    let result = state.archives.filter {
                        $0.archive.pagecount != $0.archive.progress
                    }
                    state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
                } else {
                    state.archivesToDisplay = state.archives
                }

                state.selected.formIntersection(state.archivesToDisplay.ids)
                return .none
            case .confirmRemoveFromCategory:
                guard state.canStartBatchAction,
                      let categoryId = state.currentStaticCategoryId else { return .none }
                state.loading = true
                state.batchActionInProgress = true
                let selected = state.selected
                return .run { send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in selected.sorted() {
                        do {
                            let response = try await service.removeArchiveFromCategory(
                                categoryId: categoryId, archiveId: archiveId
                            ).value
                            if response.success == 1 {
                                successIds.insert(archiveId)
                            } else {
                                errorIds.insert(archiveId)
                            }
                        } catch {
                            logger.error(
                                """
                                failed to remove archive from category.
                                categoryId=\(categoryId), archiveId=\(archiveId) \(error)
                                """
                            )
                            errorIds.insert(archiveId)
                        }

                    }
                    await send(.removeFromCategoryFinished(categoryId, successIds, !errorIds.isEmpty))
                }
            case let .removeFromCategoryFinished(categoryId, archiveIds, hadErrors):
                state.$categoryItems.withLock {
                    $0[id: categoryId]?.archives.removeAll(where: archiveIds.contains)
                }
                archiveIds.forEach { id in
                    state.selected.remove(id)
                    state.archivesToDisplay.remove(id: id)
                    state.archives.remove(id: id)
                }
                state.loading = false
                state.batchActionInProgress = false
                if hadErrors {
                    state.errorMessage = String(localized: "archive.selected.category.remove.error")
                } else {
                    state.successMessage = String(localized: "archive.selected.category.remove.success")
                }
                return reloadPageAfterRemoval(state: &state, removedCount: archiveIds.count)
            case .confirmDelete:
                guard state.canStartBatchAction else { return .none }
                state.loading = true
                state.batchActionInProgress = true
                return deleteSelected(state)
            case let .setSearchSortOrder(order):
                state.$searchSortOrder.withLock {
                    $0 = order
                }
                return .none
            case let .setSearchSort(sort):
                state.$searchSort.withLock {
                    $0 = sort
                }
                return .none
            case .toggleHideRead:
                state.selected.removeAll()
                state.$hideRead.withLock {
                    $0.toggle()
                }
                if state.hideRead {
                    let result = state.archives.filter {
                        $0.archive.pagecount != $0.archive.progress
                    }
                    state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
                } else {
                    state.archivesToDisplay = state.archives
                }
                if state.archivesToDisplay.count < state.archives.count, state.canAppendHiddenArchives {
                    return .send(.appendArchives(String(state.archives.count)))
                }
                return .none
            case let .goToPage(page):
                guard state.canLoadArchives, state.paginationActive else { return .none }
                guard state.loading == false else { return .none }
                let targetPage = PaginationPositioning.clampedPage(page, pageCount: state.pageCount)
                guard targetPage != state.currentPage else { return .none }

                state.selected.removeAll()
                state.loading = true
                state.pendingPage = targetPage
                let start = PaginationPositioning.itemOffset(
                    page: targetPage,
                    pageSize: state.serverPageSize
                )
                return self.search(
                    searchFilter: state.filter,
                    sort: (by: state.searchSort, order: state.searchSortOrder),
                    start: String(start),
                    append: false,
                    cancellationID: state.searchCancellationID
                )
            case let .deleteFinished(archiveIds, hadErrors):
                state.batchActionInProgress = false
                archiveIds.forEach { id in
                    state.selected.remove(id)
                    state.archivesToDisplay.remove(id: id)
                    state.archives.remove(id: id)
                    state.$archiveItems.withLock {
                        _ = $0.remove(id: id)
                    }
                }
                state.$categoryItems.withLock { categories in
                    for index in categories.indices {
                        categories[index].archives.removeAll(where: archiveIds.contains)
                    }
                }
                state.loading = false
                if hadErrors {
                    state.errorMessage = String(localized: "archive.selected.delete.error")
                } else {
                    state.successMessage = String(localized: "archive.selected.delete.success")
                }
                if archiveIds.contains(where: \.isTankoubonArchiveId) {
                    state.preserveSelectionOnNextPopulate = true
                    let page = state.paginationActive
                        ? PaginationPositioning.clampedPage(state.currentPage, pageCount: state.pageCount)
                        : 0
                    return loadArchives(state: &state, page: page)
                }
                return reloadPageAfterRemoval(state: &state, removedCount: archiveIds.count)
            case .loadCategory:
                return .run { send in
                    let categories = try await service.retrieveCategories().value
                    let items = categories.map { $0.toCategoryItem() }
                        .sorted { $0.pinned == "1" && $1.pinned != "1" }
                    await send(.populateCategory(items))
                } catch: { error, send in
                    logger.error("failed to load category. \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .populateCategory(items):
                state.$categoryItems.withLock {
                    $0 = IdentifiedArray(uniqueElements: items)
                }
                return .none
            case let .addArchivesToCategory(categoryId):
                guard state.canStartBatchAction,
                      state.categoryItems[id: categoryId] != nil else { return .none }
                state.loading = true
                state.batchActionInProgress = true
                let selected = state.selected
                return .run { send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in selected.sorted() {
                        do {
                            let response = try await service.addArchiveToCategory(
                                categoryId: categoryId, archiveId: archiveId
                            ).value
                            if response.success == 1 {
                                successIds.insert(archiveId)
                            } else {
                                errorIds.insert(archiveId)
                            }
                        } catch {
                            logger.error(
                                """
                                failed to add archive to category.
                                categoryId=\(categoryId), archiveId=\(archiveId) \(error)
                                """
                            )
                            errorIds.insert(archiveId)
                        }
                    }
                    await send(.addArchivesToCategoryFinished(categoryId, successIds, !errorIds.isEmpty))
                }
            case let .addArchivesToCategoryFinished(categoryId, archiveIds, hadErrors):
                state.$categoryItems.withLock {
                    for archiveId in archiveIds where $0[id: categoryId]?.archives.contains(archiveId) == false {
                        $0[id: categoryId]?.archives.append(archiveId)
                    }
                }
                archiveIds.forEach { id in
                    state.selected.remove(id)
                }
                state.loading = false
                state.batchActionInProgress = false
                if hadErrors {
                    state.errorMessage = String(localized: "archive.selected.category.add.error")
                } else {
                    state.successMessage = String(localized: "archive.selected.category.add.success")
                }
                return .none
            case let .createTankoubon(name):
                guard state.canStartBatchAction else { return .none }
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    state.errorMessage = String(localized: "archive.selected.tankoubon.name.required")
                    return .none
                }
                guard !state.selected.contains(where: \.isTankoubonArchiveId) else {
                    state.errorMessage = String(localized: "archive.selected.tankoubon.nested.error")
                    return .none
                }
                state.loading = true
                state.batchActionInProgress = true
                let archives = Array(state.selected)
                return .run { send in
                    var createdTankoubon = false
                    do {
                        let created = try await service.createTankoubon(name: name).value
                        guard created.success == 1, let id = created.tankoubonId, !id.isEmpty else {
                            await send(.createTankoubonFailed(
                                String(localized: "archive.selected.tankoubon.create.error")
                            ))
                            return
                        }
                        createdTankoubon = true
                        let updated = try await service.updateTankoubon(id: id, archives: archives).value
                        guard updated.success == 1 else {
                            await send(.createTankoubonFailed(
                                String(localized: "archive.selected.tankoubon.contents.error")
                            ))
                            return
                        }
                        await send(.createTankoubonSucceeded)
                    } catch {
                        logger.error("failed to create or populate Tankoubon. \(error)")
                        await send(.createTankoubonFailed(
                            String(localized: createdTankoubon
                                ? "archive.selected.tankoubon.contents.error"
                                : "archive.selected.tankoubon.create.error")
                        ))
                    }
                }
            case .createTankoubonSucceeded:
                state.loading = false
                state.batchActionInProgress = false
                state.successMessage = String(localized: "archive.selected.tankoubon.create.success")
                return .send(.reloadFromFirstPage)
            case let .createTankoubonFailed(message):
                state.loading = false
                state.batchActionInProgress = false
                state.errorMessage = message
                return .none
            case .openReader:
                return .none
            }
        }
        .forEach(\.archivesToDisplay, action: \.grid) {
            GridFeature()
        }
    }
}
// swiftlint:enable type_body_length

extension ArchiveListFeature {
    private func deleteSelected(_ state: State) -> EffectOf<Self> {
        return .run { [state] send in
            var successIds: Set<String> = .init()
            var errorIds: Set<String> = .init()

            for archiveId in state.selected.sorted() {
                do {
                    let request = if archiveId.isTankoubonArchiveId {
                        await service.deleteTankoubon(id: archiveId)
                    } else {
                        await service.deleteArchive(id: archiveId)
                    }
                    let response = try await request.value
                    if response.success == 1 {
                        successIds.insert(archiveId)
                    } else {
                        errorIds.insert(archiveId)
                    }
                } catch {
                    logger.error("failed to delete archive id=\(archiveId) \(error)")
                    errorIds.insert(archiveId)
                }
            }

            await send(.deleteFinished(successIds, !errorIds.isEmpty))
        }
    }

}

extension ArchiveListFeature {
    private func finishCaching(state: inout State, id: String, succeeded: Bool, error: String? = nil) {
        guard state.batchCachingArchiveIds.remove(id) != nil else {
            if succeeded { state.successMessage = String(localized: "archive.cache.added") }
            if let error { state.errorMessage = error }
            return
        }
        if let error {
            state.batchCacheErrors.insert(error)
        }
        if succeeded { state.selected.remove(id) }
        state.batchCacheHadSuccess = state.batchCacheHadSuccess || succeeded
        guard state.batchCachingArchiveIds.isEmpty else { return }
        if !state.batchCacheErrors.isEmpty {
            state.errorMessage = state.batchCacheErrors.sorted().joined(separator: "\n")
        } else if state.batchCacheHadSuccess {
            state.successMessage = String(localized: "archive.cache.added")
        }
        state.batchCacheErrors.removeAll()
        state.batchCacheHadSuccess = false
    }

    private func cacheArchive(state: inout State, id: String) -> EffectOf<Self> {
        guard !state.cachingArchiveIds.contains(id),
              let archive = state.archives[id: id]?.archive else {
            return .none
        }
        if (try? database.existCache(id)) == true {
            return .none
        }
        state.cachingArchiveIds.insert(id)
        return .run(priority: .utility) { send in
            let extraction = try await service.extractArchiveForReading(id: id)
            guard !extraction.pages.isEmpty else {
                await send(.cacheArchiveFailed(id, String(localized: "error.page.empty")))
                return
            }

            try await service.saveAndCacheArchive(
                archive,
                pages: extraction.pages,
                toc: extraction.tankoubonDetails?.toc,
                database: database
            )
            await send(.cacheArchiveFinished(id))
        } catch: { error, send in
            logger.error("failed to cache archive. id=\(id) \(error)")
            await send(.cacheArchiveFailed(id, error.localizedDescription))
        }
    }

    private func resetArchives(state: inout State) {
        state.selected.removeAll()
        state.preserveSelectionOnNextPopulate = false
        state.archivesToDisplay = .init()
        state.archives = .init()
        state.currentPage = 0
        state.pendingPage = nil
    }

    private func loadArchives(state: inout State, page: Int) -> EffectOf<Self> {
        state.loading = true
        state.currentPage = page
        let start = PaginationPositioning.itemOffset(page: page, pageSize: state.serverPageSize)
        return .merge(
            populateTags(state: state),
            search(
                searchFilter: state.filter,
                sort: (by: state.searchSort, order: state.searchSortOrder),
                start: String(start),
                append: false,
                cancellationID: state.searchCancellationID
            )
        )
    }

    func clearArchives(state: inout State) {
        state.selected.removeAll()
        state.preserveSelectionOnNextPopulate = false
        state.archivesToDisplay = .init()
        state.archives = .init()
        state.total = 0
        state.currentPage = 0
        state.pendingPage = nil
        state.loading = false
    }

    private func reloadPageAfterRemoval(
        state: inout State,
        removedCount: Int
    ) -> EffectOf<Self> {
        guard state.paginationActive, removedCount > 0 else { return .none }
        state.total = max(state.total - removedCount, 0)
        state.currentPage = PaginationPositioning.clampedPage(
            state.currentPage,
            pageCount: state.pageCount
        )
        return .send(.load)
    }

    func populateTags(state: State) -> EffectOf<Self> {
        // refresh only after 1 day
        guard Date().timeIntervalSince1970 - state.lastTagRefresh > 86400 else { return .none }
        return .run(priority: .utility) { send in
            do {
                let response = try await service.databaseStats().value
                let tags = response.filter { !["date_added", "source"].contains($0.namespace) }.map { tag in
                    TagItem(
                        tag: tag.namespace.isEmpty ? tag.text : "\(tag.namespace):\(tag.text)",
                        count: Int(tag.weight) ?? 1
                    )
                }
                try database.replaceTags(tags)
                await send(.tagsRefreshed)
            } catch {
                logger.error("failed to refresh tags. \(error)")
            }
        }
    }

    func search(
        searchFilter: SearchFilter,
        sort: (by: String, order: String),
        start: String,
        append: Bool,
        cancellationID: UUID
    ) -> EffectOf<ArchiveListFeature> {
        return .run { send in
            do {
                if sort.by == SearchSort.random.rawValue {
                    let response = try await service.randomArchives(
                        category: searchFilter.category,
                        filter: searchFilter.filter
                    ).value
                    let archives = response.data.map {
                        $0.toArchiveItem()
                    }
                    await send(.populateArchives(archives, 100, false))
                } else {
                    let response = try await service.searchArchive(
                        category: searchFilter.category,
                        filter: searchFilter.filter,
                        start: start,
                        sortby: sort.by,
                        order: sort.order
                    ).value
                    let archives = response.data.map {
                        $0.toArchiveItem()
                    }
                    await send(.populateArchives(archives, response.recordsFiltered, append))
                }
            } catch {
                logger.error("failed to load archives. \(error)")
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
        .cancellable(id: cancellationID, cancelInFlight: true)
    }
}

extension ArchiveListFeature.State {
    var currentStaticCategoryId: String? {
        guard let categoryId = filter.category,
              categoryItems[id: categoryId]?.search.isEmpty == true else { return nil }
        return categoryId
    }

    /// Random sort is served by an endpoint that has no offset paging, so the pager
    /// stays hidden there even when the mode is enabled.
    var paginationActive: Bool {
        paginateArchiveList && searchSort != SearchSort.random.rawValue
    }

    var showsPager: Bool {
        paginationActive && pageCount > 1
    }

    var canAppendHiddenArchives: Bool {
        hideRead && !paginationActive && searchSort != SearchSort.random.rawValue
            && selectMode != .active && archives.count < total
    }
}
