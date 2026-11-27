import ComposableArchitecture
import Foundation
import Logging
import OrderedCollections
import SwiftUI

@Reducer public struct ArchiveListFeature: Sendable {
    let logger = Logger(label: "ArchiveListFeature")

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
                return handleToggleSelectionMode(state: &state)
            case .cacheSelected:
                return handleCacheSelected(state: &state)
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
                guard state.loading == false else { return .none }
                // A reload keeps the page the user is on, so pull-to-refresh reloads what is on
                // screen. Every path that means "start over" sends `reloadFromFirstPage` instead,
                // which is what puts the pager back on the first page.
                let page = state.paginationActive
                    ? PaginationPositioning.clampedPage(state.currentPage, pageCount: state.pageCount)
                    : 0
                return loadArchives(state: &state, page: page)
            case let .appendArchives(start):
                guard state.canLoadArchives, state.selectMode != .active, state.loading == false else {
                    return .none
                }
                state.loading = true
                return search(
                    searchFilter: state.filter,
                    sort: (by: state.searchSort, order: state.searchSortOrder),
                    start: start,
                    append: true,
                    cancellationID: state.searchCancellationID
                )
            case let .populateArchives(archives, total, append):
                return handlePopulateArchives(archives, total: total, append: append, state: &state)
            case let .refreshThumbnail(archiveId):
                guard state.archivesToDisplay.contains(where: { $0.id == archiveId }) else { return .none }
                return .send(.grid(.element(id: archiveId, action: .load(true))))
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
                return handleRefreshDisplayArchives(state: &state)
            case .confirmRemoveFromCategory:
                return handleConfirmRemoveFromCategory(state: &state)
            case let .removeFromCategoryFinished(categoryId, archiveIds, hadErrors):
                return handleRemoveFromCategoryFinished(
                    categoryId: categoryId, archiveIds: archiveIds, hadErrors: hadErrors, state: &state
                )
            case .confirmDelete:
                return handleConfirmDelete(state: &state)
            case let .setSearchSortOrder(order):
                state.$searchSortOrder.withLock { $0 = order }
                return .none
            case let .setSearchSort(sort):
                state.$searchSort.withLock { $0 = sort }
                return .none
            case .toggleHideRead:
                return handleToggleHideRead(state: &state)
            case let .goToPage(page):
                return handleGoToPage(page, state: &state)
            case let .deleteFinished(archiveIds, hadErrors):
                return handleDeleteFinished(archiveIds: archiveIds, hadErrors: hadErrors, state: &state)
            case .loadCategory:
                return handleLoadCategory()
            case let .populateCategory(items):
                state.$categoryItems.withLock { $0 = IdentifiedArray(uniqueElements: items) }
                return .none
            case let .addArchivesToCategory(categoryId):
                return handleAddArchivesToCategory(categoryId, state: &state)
            case let .addArchivesToCategoryFinished(categoryId, archiveIds, hadErrors):
                return handleAddArchivesToCategoryFinished(
                    categoryId: categoryId, archiveIds: archiveIds, hadErrors: hadErrors, state: &state
                )
            case let .createTankoubon(name):
                return handleCreateTankoubon(name, state: &state)
            case .createTankoubonSucceeded:
                return handleCreateTankoubonSucceeded(state: &state)
            case let .createTankoubonFailed(message):
                return handleCreateTankoubonFailed(message, state: &state)
            case .openReader:
                return .none
            }
        }
        .forEach(\.archivesToDisplay, action: \.grid) { GridFeature() }
    }
}

private extension ArchiveListFeature {
    func handleToggleSelectionMode(state: inout State) -> EffectOf<Self> {
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
    }

    func handlePopulateArchives(
        _ archives: [ArchiveItem],
        total: Int,
        append: Bool,
        state: inout State
    ) -> EffectOf<Self> {
        archives.forEach { item in
            state.$archiveItems.withLock { _ = $0.updateOrAppend(item) }
        }
        let gridFeatureState = archives.compactMap { item in
            Shared(state.$archiveItems[id: item.id])
        }.map { GridFeature.State(archive: $0) }
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
        // LANraragi exposes no page-size parameter, so the size is inferred from a full
        // page-zero response. Later pages can be short, which is why only page zero defines it.
        if !append, state.currentPage == 0, !archives.isEmpty {
            state.serverPageSize = archives.count
        }
        applyReadFilter(state: &state)
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
    }

    func handleRefreshDisplayArchives(state: inout State) -> EffectOf<Self> {
        let before = state.archives.count
        let filteredGridFeatureState = state.archives.filter { gridState in
            state.archiveItems[id: gridState.archive.id] != nil
        }
        state.total -= before - filteredGridFeatureState.count
        state.archives = filteredGridFeatureState
        applyReadFilter(state: &state)
        state.selected.formIntersection(state.archivesToDisplay.ids)
        return .none
    }

    func handleToggleHideRead(state: inout State) -> EffectOf<Self> {
        state.selected.removeAll()
        state.$hideRead.withLock { $0.toggle() }
        applyReadFilter(state: &state)
        if state.archivesToDisplay.count < state.archives.count, state.canAppendHiddenArchives {
            return .send(.appendArchives(String(state.archives.count)))
        }
        return .none
    }

    func handleGoToPage(_ page: Int, state: inout State) -> EffectOf<Self> {
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
        return search(
            searchFilter: state.filter,
            sort: (by: state.searchSort, order: state.searchSortOrder),
            start: String(start),
            append: false,
            cancellationID: state.searchCancellationID
        )
    }

    func handleLoadCategory() -> EffectOf<Self> {
        .run { send in
            let categories = try await service.retrieveCategories().value
            let items = categories.map { $0.toCategoryItem() }
                .sorted { $0.pinned == "1" && $1.pinned != "1" }
            await send(.populateCategory(items))
        } catch: { error, send in
            logger.error("failed to load category. \(error)")
            await send(.setErrorMessage(error.localizedDescription))
        }
    }

    func applyReadFilter(state: inout State) {
        if state.hideRead {
            let result = state.archives.filter {
                $0.archive.pagecount != $0.archive.progress
            }
            state.archivesToDisplay = IdentifiedArray(uniqueElements: result)
        } else {
            state.archivesToDisplay = state.archives
        }
    }
}

extension ArchiveListFeature {
    func resetArchives(state: inout State) {
        state.selected.removeAll()
        state.preserveSelectionOnNextPopulate = false
        state.archivesToDisplay = .init()
        state.archives = .init()
        state.currentPage = 0
        state.pendingPage = nil
    }

    func loadArchives(state: inout State, page: Int) -> EffectOf<Self> {
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

    func reloadPageAfterRemoval(
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
                    let archives = response.data.map { $0.toArchiveItem() }
                    await send(.populateArchives(archives, 100, false))
                } else {
                    let response = try await service.searchArchive(
                        category: searchFilter.category,
                        filter: searchFilter.filter,
                        start: start,
                        sortby: sort.by,
                        order: sort.order
                    ).value
                    let archives = response.data.map { $0.toArchiveItem() }
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
