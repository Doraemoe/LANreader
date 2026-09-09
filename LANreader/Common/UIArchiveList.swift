// swiftlint:disable file_length
import ComposableArchitecture
import OrderedCollections
import SwiftUI
import UIKit
import Logging
import NotificationBannerSwift

// swiftlint:disable type_body_length
@Reducer public struct ArchiveListFeature: Sendable {
    private let logger = Logger(label: "ArchiveListFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        @Presents var alert: AlertState<Action.Alert>?

        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @SharedReader(.appStorage(SettingsKey.searchSortCustom)) var searchSortCustom = ""
        @Shared(.appStorage(SettingsKey.hideRead)) var hideRead = false
        @Shared(.appStorage(SettingsKey.paginateArchiveList)) var paginateArchiveList = false
        @Shared(.appStorage(SettingsKey.searchSort)) var searchSort = SearchSort.dateAdded.rawValue
        @Shared(.appStorage(SettingsKey.searchSortOrder)) var searchSortOrder = SearchSortOrder.asc.rawValue
        @Shared(.appStorage(SettingsKey.lastTagRefresh)) var lastTagRefresh = 0.0

        var selectMode: EditMode = .inactive
        var selected: OrderedSet<String> = .init()
        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var filter: SearchFilter
        var loadOnAppear = true
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var batchActionInProgress = false
        var showLoading: Bool = false
        var total: Int = 0
        var errorMessage = ""
        var successMessage = ""
        var cachingArchiveIds: Set<String> = []
        var batchCachingArchiveIds: Set<String> = []
        var batchCacheHadSuccess = false
        var batchCacheErrors: Set<String> = []
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
        case alert(PresentationAction<Alert>)
        case grid(IdentifiedActionOf<GridFeature>)
        case loadCategory
        case populateCategory([CategoryItem])
        case addArchivesToCategory(String)
        case addArchivesToCategoryFinished(String, Set<String>, Bool)
        case createTankoubon(String)
        case createTankoubonSucceeded
        case createTankoubonFailed(String)
        case setFilter(SearchFilter)
        case resetArchives
        case reloadFromFirstPage
        case load(Bool)
        case populateArchives([ArchiveItem], Int, Bool)
        case refreshThumbnail(String)
        case appendArchives(String)
        case removeArchive(String)
        case cacheArchive(String)
        case cacheSelected
        case toggleSelectionMode
        case cacheArchiveFinished(String)
        case cacheArchiveFailed(String, String)
        case setErrorMessage(String)
        case setSuccessMessage(String)
        case cancelSearch
        case addSelect(String)
        case removeSelect(String)
        case refreshDisplayArchives

        case setSearchSortOrder(String)
        case setSearchSort(String)
        case toggleHideRead
        case goToPage(Int)

        case deleteButtonTapped
        case deleteSuccess(Set<String>)
        case removeFromCategoryButtonTapped
        case removeFromCategoryFinished(String, Set<String>, Bool)
        public enum Alert: Sendable {
            case confirmDelete
            case confirmRemoveFromCategory
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    enum CancelId { case search }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleSelectionMode:
                guard !state.batchActionInProgress,
                      state.selectMode == .active || !state.loading else { return .none }
                state.selectMode = state.selectMode == .active ? .inactive : .active
                state.selected.removeAll()
                return .none
            case .cacheSelected:
                guard !state.loading else { return .none }
                let ids = state.selected.sorted()
                let previous = state.cachingArchiveIds
                let effects = ids.map { cacheArchive(state: &state, id: $0) }
                state.batchCachingArchiveIds.formUnion(state.cachingArchiveIds.subtracting(previous))
                state.selected.formIntersection(state.batchCachingArchiveIds)
                return .merge(effects)
            case let .setFilter(filter):
                if state.filter != filter { state.selected.removeAll() }
                state.filter = filter
                return .none
            case .resetArchives:
                resetArchives(state: &state)
                return .none
            case .reloadFromFirstPage:
                resetArchives(state: &state)
                guard state.canLoadArchives else {
                    clearArchives(state: &state)
                    return .cancel(id: CancelId.search)
                }
                return loadArchives(state: &state, page: 0, showLoading: true)
            case let .load(showLoading):
                guard state.canLoadArchives else {
                    clearArchives(state: &state)
                    return .none
                }
                guard state.loading == false else {
                    return .none
                }
                // A reload keeps the page the user is on, so pull-to-refresh reloads what is on
                // screen. Every path that means "start over" sends `resetArchives` first, which
                // is what puts the pager back on the first page.
                let page = state.paginationActive
                    ? PaginationPositioning.clampedPage(state.currentPage, pageCount: state.pageCount)
                    : 0
                return loadArchives(state: &state, page: page, showLoading: showLoading)
            case let .appendArchives(start):
                guard state.canLoadArchives else {
                    return .none
                }
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = true
                let sortby = state.searchSort
                let order = state.searchSortOrder
                return self.search(
                    searchFilter: state.filter, sortby: sortby, start: start, order: order, append: true
                )
            case let .removeArchive(id):
                state.selected.remove(id)
                state.archivesToDisplay.remove(id: id)
                state.archives.remove(id: id)
                state.$archiveItems.withLock {
                    _ = $0.remove(id: id)
                }
                return reloadPageAfterRemoval(state: &state, removedCount: 1)
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

                state.selected.formIntersection(state.archivesToDisplay.ids)
                state.total = total
                state.loading = false
                state.showLoading = false

                // Archives removed elsewhere can shrink the list past the page being reloaded.
                // Fall back to the last valid page instead of leaving an empty grid behind.
                if !append, state.paginationActive, state.pageCount > 0, state.currentPage >= state.pageCount {
                    state.currentPage = PaginationPositioning.clampedPage(
                        state.currentPage, pageCount: state.pageCount
                    )
                    return .send(.load(false))
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
                state.showLoading = false
                state.pendingPage = nil
                state.errorMessage = message
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            case .grid:
                return .none
            case .cancelSearch:
                state.pendingPage = nil
                if state.loading {
                    state.loading = false
                    state.showLoading = false
                    return .cancel(id: CancelId.search)
                }
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
            case .alert(.dismiss):
                return .none
            case .alert(.presented(.confirmRemoveFromCategory)):
                guard !state.loading, !state.selected.isEmpty,
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
            case .alert(.presented(.confirmDelete)):
                guard !state.loading, !state.selected.isEmpty else { return .none }
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
                return .none
            case let .goToPage(page):
                guard state.canLoadArchives, state.paginationActive else { return .none }
                guard state.loading == false else { return .none }
                let targetPage = PaginationPositioning.clampedPage(page, pageCount: state.pageCount)
                guard targetPage != state.currentPage else { return .none }

                state.selected.removeAll()
                state.loading = true
                state.showLoading = true
                state.pendingPage = targetPage
                let start = PaginationPositioning.itemOffset(
                    page: targetPage,
                    pageSize: state.serverPageSize
                )
                return self.search(
                    searchFilter: state.filter,
                    sortby: state.searchSort,
                    start: String(start),
                    order: state.searchSortOrder,
                    append: false
                )
            case .deleteButtonTapped:
                guard !state.loading, !state.selected.isEmpty else { return .none }
                state.alert = AlertState {
                    TextState("archive.selected.delete")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case .removeFromCategoryButtonTapped:
                guard !state.loading, !state.selected.isEmpty,
                      state.currentStaticCategoryId != nil else { return .none }
                state.alert = AlertState {
                    TextState("archive.selected.category.remove")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmRemoveFromCategory) {
                        TextState("remove")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case let .deleteSuccess(archiveIds):
                state.batchActionInProgress = false
                archiveIds.forEach { id in
                    state.selected.remove(id)
                    state.archivesToDisplay.remove(id: id)
                    state.archives.remove(id: id)
                    state.$archiveItems.withLock {
                        _ = $0.remove(id: id)
                    }
                }
                state.loading = false
                return reloadPageAfterRemoval(state: &state, removedCount: archiveIds.count)
            case .loadCategory:
                return .run { send in
                    let categories = try await service.retrieveCategories().value
                    let items = categories.map { item in
                        item.toCategoryItem()
                    }.sorted { first, second in
                        if first.pinned != "1" && second.pinned == "1" {
                            return false
                        } else {
                            return true
                        }
                    }
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
                guard !state.loading, !state.selected.isEmpty,
                      let currentCategory = state.categoryItems[id: categoryId] else { return .none }
                state.loading = true
                state.batchActionInProgress = true
                let selected = state.selected
                return .run { send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in selected.sorted() {
                        if currentCategory.archives.contains(archiveId) {
                            successIds.insert(archiveId)
                        } else {
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
                guard !state.loading, !state.selected.isEmpty else { return .none }
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
            }
        }
        .forEach(\.archivesToDisplay, action: \.grid) {
            GridFeature()
        }
        .ifLet(\.$alert, action: \.alert)
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

            if !errorIds.isEmpty {
                await send(.setErrorMessage(
                    String(localized: "archive.selected.delete.error")
                ))
            } else {
                await send(.setSuccessMessage(
                    String(localized: "archive.selected.delete.success")
                ))
            }
            await send(.deleteSuccess(successIds))
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

            var requested = Set<String>()
            for (index, page) in extraction.pages.enumerated() {
                let pageId = String(page.path.dropFirst(1))
                if requested.insert(pageId).inserted {
                    await service.backgroupFetchArchivePage(
                        page: pageId,
                        archiveId: id,
                        pageNumber: index + 1
                    )
                }
            }

            var cache = ArchiveCache(
                id: id,
                title: archive.name,
                tags: archive.tags,
                thumbnail: Data(),
                cached: false,
                totalPages: requested.count,
                toc: extraction.tankoubonDetails?.toc ?? archive.toc,
                lastUpdate: Date(),
                progress: archive.progress
            )
            try database.saveCache(&cache)
            await send(.cacheArchiveFinished(id))
        } catch: { error, send in
            logger.error("failed to cache archive. id=\(id) \(error)")
            await send(.cacheArchiveFailed(id, error.localizedDescription))
        }
    }

    private func resetArchives(state: inout State) {
        state.selected.removeAll()
        state.archivesToDisplay = .init()
        state.archives = .init()
        state.currentPage = 0
        state.pendingPage = nil
    }

    private func loadArchives(
        state: inout State,
        page: Int,
        showLoading: Bool
    ) -> EffectOf<Self> {
        state.loading = true
        if showLoading {
            state.showLoading = true
        }
        state.currentPage = page
        let start = PaginationPositioning.itemOffset(page: page, pageSize: state.serverPageSize)
        populateTags(state: &state)
        return search(
            searchFilter: state.filter,
            sortby: state.searchSort,
            start: String(start),
            order: state.searchSortOrder,
            append: false
        )
    }

    func clearArchives(state: inout State) {
        state.selected.removeAll()
        state.archivesToDisplay = .init()
        state.archives = .init()
        state.total = 0
        state.currentPage = 0
        state.pendingPage = nil
        state.loading = false
        state.showLoading = false
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
        return .send(.load(false))
    }

    func populateTags(state: inout State) {
        let currentTime = Date().timeIntervalSince1970
        let lastUpdateTime = state.lastTagRefresh
        let excludeTags = ["date_added", "source"]
        // refresh only after 1 day
        if currentTime - lastUpdateTime > 86400 {
            state.$lastTagRefresh.withLock {
                $0 = Date().timeIntervalSince1970
            }
            Task.detached(priority: .utility) {
                do {
                    let response = try await service.databaseStats().value
                    _ = try database.deleteAllTag()
                    response.forEach { tag in
                        if !excludeTags.contains(tag.namespace) {
                            let count = Int(tag.weight) ?? 1
                            var tagItem = if tag.namespace.isEmpty {
                                TagItem(tag: tag.text, count: count)
                            } else {
                                TagItem(tag: "\(tag.namespace):\(tag.text)", count: count)
                            }
                            try? database.saveTag(tagItem: &tagItem)
                        }
                    }
                } catch {
                    logger.error("failed to refresh tags. \(error)")
                    UserDefaults.standard.set(lastUpdateTime, forKey: SettingsKey.lastTagRefresh)
                }
            }
        }
    }

    func search(
        searchFilter: SearchFilter,
        sortby: String,
        start: String,
        order: String,
        append: Bool
    ) -> EffectOf<ArchiveListFeature> {
        return .run { send in
            do {
                if sortby == SearchSort.random.rawValue {
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
                        sortby: sortby,
                        order: order
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
        .cancellable(id: CancelId.search, cancelInFlight: true)
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
}

// swiftlint:disable:next type_body_length
class UIArchiveListViewController: UIViewController {
    let store: StoreOf<ArchiveListFeature>
    @Dependency(\.appDatabase) private var database

    var collectionView: UICollectionView!
    var dataSource:
        UICollectionViewDiffableDataSource<Section, StoreOf<GridFeature>>!
    var isLoading = false

    private let refreshControl = UIRefreshControl()
    private var lastObservedLanraragiUrl: String?
    private var lastObservedSearchSort: String?
    private var lastObservedSearchSortOrder: String?
    private var lastObservedFilter: SearchFilter?
    private var lastObservedPaginateArchiveList: Bool?
    private let paginationBar = PaginationBar()
    private lazy var readFilterEmptyView: UIContentUnavailableView = {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "checkmark.circle")
        configuration.text = String(localized: "archive.list.hideRead.empty.title")
        configuration.secondaryText = String(localized: "archive.list.hideRead.empty.message")
        return UIContentUnavailableView(configuration: configuration)
    }()

    init(store: StoreOf<ArchiveListFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupCollectionView() {
        let layout = makeCollectionViewLayout()
        view.backgroundColor = .systemGroupedBackground
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupPaginationBar() {
        paginationBar.translatesAutoresizingMaskIntoConstraints = false
        paginationBar.isHidden = true
        view.addSubview(paginationBar)

        // Soft side margins: the strip is sized by its content, so on the narrowest phone
        // with the largest text these would be unsatisfiable rather than compressing it.
        let leading = paginationBar.leadingAnchor.constraint(
            greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12
        )
        let trailing = paginationBar.trailingAnchor.constraint(
            lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12
        )
        leading.priority = .defaultHigh
        trailing.priority = .defaultHigh

        NSLayoutConstraint.activate([
            paginationBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            paginationBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12
            ),
            leading,
            trailing
        ])
    }

    /// Keeps the last row scrollable clear of the floating bar instead of hiding under it.
    private func updateContentInsetForPaginationBar() {
        let inset = paginationBar.isHidden ? 0 : paginationBar.bounds.height + 24
        guard collectionView.contentInset.bottom != inset else { return }
        collectionView.contentInset.bottom = inset
        collectionView.verticalScrollIndicatorInsets.bottom = inset
    }

    private func makeCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, layoutEnvironment -> NSCollectionLayoutSection? in
            Self.makeArchiveGridSection(layoutEnvironment: layoutEnvironment)
        }
    }

    private static func makeArchiveGridSection(
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let containerWidth = layoutEnvironment.container.effectiveContentSize.width
        let sideInset: CGFloat = 12.0
        let interItemSpacing: CGFloat = 12.0
        let contentWidth = max(containerWidth - sideInset * 2, 1)
        let columns = max(Int(contentWidth / 172), 1)
        let totalSpacing = CGFloat(columns - 1) * interItemSpacing
        let cellWidth = (contentWidth - totalSpacing) / CGFloat(columns)
        let cellHeight = cellWidth / ArchiveGridMetrics.coverAspectRatio + 4.0

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = makeArchiveGridGroup(
            item: item,
            columns: columns,
            cellHeight: cellHeight,
            interItemSpacing: interItemSpacing
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: sideInset,
            bottom: 20,
            trailing: sideInset
        )
        section.interGroupSpacing = interItemSpacing
        section.boundarySupplementaryItems = [makeArchiveGridFooter()]
        return section
    }

    private static func makeArchiveGridGroup(
        item: NSCollectionLayoutItem,
        columns: Int,
        cellHeight: CGFloat,
        interItemSpacing: CGFloat
    ) -> NSCollectionLayoutGroup {
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(cellHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(interItemSpacing)
        return group
    }

    private static func makeArchiveGridFooter() -> NSCollectionLayoutBoundarySupplementaryItem {
        let footerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(80)
        )
        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: footerSize,
            elementKind: UICollectionView.elementKindSectionFooter,
            alignment: .bottom
        )
    }

    func setupRefresh() {
        refreshControl.addTarget(
            self, action: #selector(didPullToRefresh(_:)), for: .valueChanged)
        collectionView.alwaysBounceVertical = true
        collectionView.refreshControl = refreshControl
    }

    func setupCell() {
        collectionView.register(
            UIArchiveCell.self, forCellWithReuseIdentifier: "Archive")
        collectionView.register(
            LoadingReusableView.self,
            forSupplementaryViewOfKind: UICollectionView
                .elementKindSectionFooter,
            withReuseIdentifier: LoadingReusableView.reuseIdentifier)

        let cellRegistration = UICollectionView.CellRegistration<
            UIArchiveCell, StoreOf<GridFeature>
        > { [weak self] cell, _, itemStore in
            guard let self else { return }
            cell.configure(
                with: itemStore, database: database, selecting: store.selectMode == .active,
                selected: store.selected.contains(itemStore.id)
            )
        }

        dataSource = UICollectionViewDiffableDataSource<
            Section, StoreOf<GridFeature>
        >(collectionView: collectionView) { collectionView, indexPath, itemStore in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: itemStore
            )
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionFooter else { return nil }
            let footer =
                collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: LoadingReusableView.reuseIdentifier,
                    for: indexPath) as? LoadingReusableView
            if self?.isLoading == true {
                footer?.startAnimation()
            } else {
                footer?.stopAnimation()
            }
            return footer
        }
    }

    private func goToPage(_ page: Int) {
        let target = PaginationPositioning.clampedPage(page, pageCount: store.pageCount)
        guard store.paginationActive, store.loading == false, target != store.currentPage else { return }
        beginRefreshingAtTop()
        store.send(.goToPage(target))
    }

    private func renderPaginationBar() {
        paginationBar.isHidden = !store.showsPager
        if store.showsPager {
            paginationBar.configure(
                currentPage: store.currentPage,
                pageCount: store.pageCount,
                onSelectPage: { [weak self] page in
                    self?.goToPage(page)
                },
                onRequestPageInput: { [weak self] in
                    self?.presentPageInput()
                }
            )
            paginationBar.layoutIfNeeded()
        }
        updateContentInsetForPaginationBar()
    }

    private func presentPageInput() {
        let pageCount = store.pageCount
        guard pageCount > 1 else { return }

        let alert = UIAlertController(
            title: String(localized: "archive.list.page.jump.title"),
            message: String(
                format: String(localized: "archive.list.page.jump.message %lld"), Int64(pageCount)
            ),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.textAlignment = .center
            field.text = String(self.store.currentPage + 1)
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        let goAction = UIAlertAction(
            title: String(localized: "archive.list.page.jump.go"), style: .default
        ) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text,
                  let requested = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
            // Displayed page numbers are one-based; the reducer works in zero-based pages.
            goToPage(requested - 1)
        }
        alert.addAction(goAction)
        present(alert, animated: true)
    }

    // swiftlint:disable function_body_length
    func setupToolbar() {
        if store.selectMode == .active {
            parent?.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: String(localized: "done"), primaryAction: UIAction { [weak self] _ in
                    self?.store.send(.toggleSelectionMode)
                }
            )
            parent?.navigationItem.rightBarButtonItem?.isEnabled = !store.batchActionInProgress
            return
        }
        let actions = SearchSort.allCases.filter { $0 != SearchSort.random }.map { sort in
            let localizedKey = "settings.archive.list.order.\(sort)"
            let label = NSLocalizedString(localizedKey, comment: "")
            let image: UIImage? =
                if store.searchSort == sort.rawValue
                    || (store.searchSort == store.searchSortCustom
                        && sort == SearchSort.custom) {
                    if store.searchSortOrder == "asc" {
                        UIImage(systemName: "arrow.up")
                    } else {
                        UIImage(systemName: "arrow.down")
                    }
                } else {
                    UIImage(systemName: "checkmark")?.withTintColor(.clear, renderingMode: .alwaysOriginal)
                }
            return UIAction(title: label, image: image) { [weak self] _ in
                guard let self else { return }
                if store.searchSort == sort.rawValue
                    || (store.searchSort == store.searchSortCustom
                        && sort == SearchSort.custom) {
                    if store.searchSortOrder == "asc" {
                        store.send(.setSearchSortOrder("desc"))
                    } else {
                        store.send(.setSearchSortOrder("asc"))
                    }
                } else {
                    if sort == SearchSort.custom {
                        store.send(.setSearchSort(store.searchSortCustom))
                    } else {
                        store.send(.setSearchSort(sort.rawValue))
                    }
                }
            }
        }
        let sortGroup = UIMenu(
            title: "", options: .displayInline, children: actions)

        let randomAction = UIAction(
            title: String(localized: "settings.archive.list.order.random"),
            image: store.searchSort == SearchSort.random.rawValue ?
            UIImage(systemName: "checkmark") :
                UIImage(systemName: "checkmark")?.withTintColor(.clear, renderingMode: .alwaysOriginal)
        ) { [weak self] _ in
            guard let self else { return }
            store.send(.setSearchSort(SearchSort.random.rawValue))
        }

        let hideReadAction = UIAction(
            title: String(localized: "settings.view.hideRead"),
            image: store.hideRead ?
            UIImage(systemName: "checkmark") :
                UIImage(systemName: "checkmark")?.withTintColor(.clear, renderingMode: .alwaysOriginal)
        ) { [weak self] _ in
            guard let self else { return }
            store.send(.toggleHideRead)
        }

        let otherGroup = UIMenu(
            title: "", options: .displayInline, children: [randomAction, hideReadAction]
        )

        // Create a menu with the actions
        var groups: [UIMenuElement] = [sortGroup, otherGroup]
        groups.append(UIAction(
            title: String(localized: "select"),
            image: UIImage(systemName: "checkmark")?.withTintColor(.clear, renderingMode: .alwaysOriginal)
        ) { [weak self] _ in
            guard let self else { return }
            store.send(.toggleSelectionMode)
            if store.selectMode == .active && store.categoryItems.isEmpty {
                store.send(.loadCategory)
            }
        })
        let menu = UIMenu(title: "", children: groups)
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.circle"), menu: menu
        )
        parent?.navigationItem.rightBarButtonItem = menuButton
    }
    // swiftlint:enable function_body_length

    // swiftlint:disable function_body_length
    func setupObserve() {
        lastObservedLanraragiUrl = store.lanraragiUrl
        lastObservedSearchSort = store.searchSort
        lastObservedSearchSortOrder = store.searchSortOrder
        lastObservedFilter = store.filter

        observe { [weak self] in
            guard let self else { return }
            let selecting = store.selectMode == .active
            let selected = store.selected
            setupToolbar()
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let item = dataSource.itemIdentifier(for: indexPath),
                      let cell = collectionView.cellForItem(at: indexPath) as? UIArchiveCell else { continue }
                cell.configure(
                    with: item, database: database, selecting: selecting, selected: selected.contains(item.id)
                )
            }
            let count = UIBarButtonItem.selectionCount(selected.count)
            let categoryAction: UIBarButtonItem
            if store.currentStaticCategoryId != nil {
                categoryAction = UIBarButtonItem(
                    image: UIImage(systemName: "folder.badge.minus"), style: .plain,
                    target: self, action: #selector(confirmBatchCategoryRemoval(_:))
                )
                categoryAction.accessibilityLabel = String(localized: "remove")
                categoryAction.isEnabled = !selected.isEmpty && !store.loading
            } else {
                let categoryActions = store.categoryItems.filter { $0.search.isEmpty }.map { category in
                    UIAction(title: category.name) { [weak self] _ in
                        self?.store.send(.addArchivesToCategory(category.id))
                    }
                }
                categoryAction = UIBarButtonItem(
                    image: UIImage(systemName: "folder.badge.plus"),
                    menu: UIMenu(
                        title: String(localized: "archive.selected.category.add"),
                        children: categoryActions
                    )
                )
                categoryAction.accessibilityLabel = String(localized: "archive.selected.category.add")
                categoryAction.isEnabled = !selected.isEmpty && !store.loading && !categoryActions.isEmpty
            }
            let createTankoubon = UIBarButtonItem(
                image: UIImage(systemName: "book.badge.plus"), style: .plain,
                target: self, action: #selector(promptForTankoubonName(_:))
            )
            createTankoubon.accessibilityLabel = String(localized: "archive.selected.tankoubon.create")
            createTankoubon.isEnabled = !selected.isEmpty && !store.loading
            let download = UIBarButtonItem(
                image: UIImage(systemName: "tray.and.arrow.down"),
                primaryAction: UIAction { [weak self] _ in
                    self?.store.send(.cacheSelected)
                }
            )
            download.accessibilityLabel = String(localized: "archive.cache.add")
            download.isEnabled = !selected.isEmpty && !store.loading
            let delete = UIBarButtonItem(
                image: UIImage(systemName: "trash"), style: .plain,
                target: self, action: #selector(confirmBatchDeletion(_:))
            )
            delete.accessibilityLabel = String(localized: "archive.delete")
            delete.isEnabled = !selected.isEmpty && !store.loading
            parent?.toolbarItems = [count, .flexibleSpace(), categoryAction, createTankoubon, download, delete]
            updateSelectionToolbarAppearance()
            delete.tintColor = .systemRed
            updateSelectionBarVisibility()
        }

        observe { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<
                Section, StoreOf<GridFeature>
            >()
            snapshot.appendSections([.main])
            snapshot.appendItems(
                Array(store.scope(\.archivesToDisplay, action: \.grid)))
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        observe { [weak self] in
            guard let self else { return }
            collectionView.backgroundView = store.showsReadFilterEmptyState
                ? readFilterEmptyView
                : nil
        }

        observe { [weak self] in
            guard let self else { return }
            if !store.loading {
                refreshControl.endRefreshing()
            }
        }

        observe { [weak self] in
            guard let self else { return }
            // `observe` only re-runs when the state read here changes, and rendering the bar
            // is idempotent, so no change tracking of its own is needed.
            renderPaginationBar()
        }

        observe { [weak self] in
            guard let self else { return }
            let lanraragiUrl = store.lanraragiUrl
            defer { lastObservedLanraragiUrl = lanraragiUrl }

            guard lanraragiUrl != lastObservedLanraragiUrl, !lanraragiUrl.isEmpty else { return }
            reloadFromFirstPage()
        }

        observe { [weak self] in
            guard let self else { return }
            let searchSort = store.searchSort
            defer { lastObservedSearchSort = searchSort }

            guard searchSort != lastObservedSearchSort else { return }
            reloadFromFirstPage()
        }

        observe { [weak self] in
            guard let self else { return }
            let searchSortOrder = store.searchSortOrder
            defer { lastObservedSearchSortOrder = searchSortOrder }

            guard searchSortOrder != lastObservedSearchSortOrder else { return }
            reloadFromFirstPage()
        }

        observe { [weak self] in
            guard let self else { return }
            let paginate = store.paginateArchiveList
            let previous = lastObservedPaginateArchiveList
            defer { lastObservedPaginateArchiveList = paginate }

            // The two modes hold different slices of the result set, so reload from the top.
            guard let previous, previous != paginate else { return }
            reloadFromFirstPage()
        }

        observe { [weak self] in
            guard let self else { return }
            let filter = store.filter
            let previousFilter = lastObservedFilter
            defer { lastObservedFilter = filter }

            guard filter.filter?.isEmpty == false else { return }
            guard previousFilter?.filter != filter.filter else { return }
            reloadFromFirstPage()
        }

        observe { [weak self] in
            guard let self else { return }
            let message = store.errorMessage
            guard !message.isEmpty else { return }
            NotificationBanner(
                title: String(localized: "error"),
                subtitle: message,
                style: .danger
            ).show()
            store.send(.setErrorMessage(""))
        }

        observe { [weak self] in
            guard let self else { return }
            let message = store.successMessage
            guard !message.isEmpty else { return }
            NotificationBanner(
                title: String(localized: "success"),
                subtitle: message,
                style: .success
            ).show()
            store.send(.setSuccessMessage(""))
        }
    }
    // swiftlint:enable function_body_length

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        setupRefresh()
        setupCell()
        setupPaginationBar()
        setupObserve()
        parent?.registerForTraitChanges(
            [UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]
        ) { [weak self] (_: UIViewController, _) in
            self?.updateSelectionToolbarAppearance()
        }

        collectionView.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if store.lanraragiUrl.isEmpty == false && store.archives.isEmpty
            && store.loadOnAppear {
            manualTriggerPullToRefresh()
        } else if !store.archivesToDisplay.isEmpty {
            store.send(.refreshDisplayArchives)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSelectionToolbarAppearance()
        updateSelectionBarVisibility()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTabBarVisibility()
    }

    @objc
    private func didPullToRefresh(_ sender: Any) {
        store.send(.load(true))
    }

    private func manualTriggerPullToRefresh() {
        guard collectionView.refreshControl?.isRefreshing == false else { return }
        beginRefreshingAtTop()
        collectionView.refreshControl?.sendActions(for: .valueChanged)
    }

    private func beginRefreshingAtTop() {
        collectionView.refreshControl?.beginRefreshing()
        let offsetPoint = CGPoint(x: 0, y: -collectionView.adjustedContentInset.top - refreshControl.frame.height)
        collectionView.setContentOffset(offsetPoint, animated: true)
    }

    private func reloadFromFirstPage() {
        beginRefreshingAtTop()
        store.send(.reloadFromFirstPage)
    }

    enum Section {
        case main
    }
}

extension UIArchiveListViewController: UICollectionViewDelegate {
    private func updateSelectionToolbarAppearance() {
        let foreground = UIColor.label.resolvedColor(with: parent?.traitCollection ?? traitCollection)
        parent?.toolbarItems?.dropLast().forEach { $0.tintColor = foreground }
    }

    private func updateSelectionBarVisibility() {
        guard let navigationController, navigationController.topViewController === parent else { return }
        let selecting = store.selectMode == .active
        parent?.navigationItem.setHidesBackButton(selecting, animated: false)
        navigationController.setToolbarHidden(!selecting, animated: false)
        updateTabBarVisibility()
    }

    private func updateTabBarVisibility() {
        guard let navigationController, navigationController.topViewController === parent else { return }
        let hideTabs = store.selectMode == .active || navigationController.viewControllers.first !== parent
        if #available(iOS 18.0, *) {
            if tabBarController?.isTabBarHidden != hideTabs {
                tabBarController?.setTabBarHidden(hideTabs, animated: false)
            }
        } else {
            tabBarController?.tabBar.isHidden = hideTabs
        }
    }

    @objc func confirmBatchDeletion(_ sender: UIBarButtonItem) {
        guard !store.loading, !store.selected.isEmpty else { return }
        store.send(.deleteButtonTapped)
        let confirmation = UIAlertController(
            title: String(localized: "archive.selected.delete"), message: nil, preferredStyle: .actionSheet
        )
        confirmation.addAction(UIAlertAction(
            title: String(localized: "delete"), style: .destructive
        ) { [weak self] _ in
            self?.store.send(.alert(.presented(.confirmDelete)))
        })
        confirmation.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { [weak self] _ in
            self?.store.send(.alert(.dismiss))
        })
        confirmation.popoverPresentationController?.barButtonItem = sender
        present(confirmation, animated: true)
    }

    @objc func promptForTankoubonName(_: UIBarButtonItem) {
        guard !store.loading, !store.selected.isEmpty else { return }
        guard !store.selected.contains(where: \.isTankoubonArchiveId) else {
            store.send(.setErrorMessage(String(localized: "archive.selected.tankoubon.nested.error")))
            return
        }
        let alert = UIAlertController(
            title: String(localized: "archive.selected.tankoubon.create"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "archive.selected.tankoubon.name")
        }
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: String(localized: "archive.selected.tankoubon.create"), style: .default
        ) { [weak self, weak alert] _ in
            self?.store.send(.createTankoubon(alert?.textFields?.first?.text ?? ""))
        })
        present(alert, animated: true)
    }

    @objc func confirmBatchCategoryRemoval(_ sender: UIBarButtonItem) {
        guard !store.loading, !store.selected.isEmpty,
              store.currentStaticCategoryId != nil else { return }
        store.send(.removeFromCategoryButtonTapped)
        let confirmation = UIAlertController(
            title: String(localized: "archive.selected.category.remove"),
            message: nil,
            preferredStyle: .actionSheet
        )
        confirmation.addAction(UIAlertAction(
            title: String(localized: "remove"), style: .destructive
        ) { [weak self] _ in
            self?.store.send(.alert(.presented(.confirmRemoveFromCategory)))
        })
        confirmation.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { [weak self] _ in
            self?.store.send(.alert(.dismiss))
        })
        confirmation.popoverPresentationController?.barButtonItem = sender
        present(confirmation, animated: true)
    }
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        if indexPath.item == collectionView.numberOfItems(inSection: 0) - 1 {
            if store.paginationActive == false
                && store.searchSort != SearchSort.random.rawValue
                && store.loading == false
                && store.archives.count < store.total {
                Task {
                    self.isLoading = true
                    collectionView.performBatchUpdates { }
                    await store.send(
                        .appendArchives(String(store.archives.count))
                    ).finish()
                    self.isLoading = false
                    collectionView.performBatchUpdates { }
                }
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
    ) {
        guard let selectedItemStore = dataSource.itemIdentifier(for: indexPath)
        else { return }
        if store.selectMode == .active {
            store.send(store.selected.contains(selectedItemStore.id)
                ? .removeSelect(selectedItemStore.id) : .addSelect(selectedItemStore.id))
        } else {
            openReader(for: selectedItemStore)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard store.selectMode != .active,
              let itemStore = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let readFromStart = UIAction(
                title: String(localized: "archive.read.fromStart"),
                image: UIImage(systemName: "arrow.left.to.line.compact")
            ) { [weak self] _ in
                self?.openReader(for: itemStore, fromStart: true)
            }
            var actions: [UIMenuElement] = [readFromStart]
            if (try? self.database.existCache(itemStore.id)) != true,
               !self.store.cachingArchiveIds.contains(itemStore.id) {
                let cacheArchive = UIAction(
                    title: String(localized: "archive.cache.add"),
                    image: UIImage(systemName: "tray.and.arrow.down")
                ) { [weak self] _ in
                    self?.store.send(.cacheArchive(itemStore.id))
                }
                actions.append(cacheArchive)
            }
            return UIMenu(title: "", children: actions)
        }
    }

    private func openReader(for itemStore: StoreOf<GridFeature>, fromStart: Bool = false) {
        let allArchives = dataSource.snapshot().itemIdentifiers(inSection: .main).map { $0.$archive }
        let readerStore = Store(
            initialState: ArchiveReaderFeature.State.init(
                currentArchiveId: itemStore.archive.id,
                allArchives: allArchives,
                fromStart: fromStart
            )
        ) {
            ArchiveReaderFeature()
        }
        let readerController = UIArchiveReaderController(store: readerStore)
        navigationController?.pushViewController(
            readerController, animated: true)
    }
}

class LoadingReusableView: UICollectionReusableView {
    static let reuseIdentifier = "LoadingReusableView"

    let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimation() {
        activityIndicator.startAnimating()
    }

    func stopAnimation() {
        activityIndicator.stopAnimating()
    }
}
// swiftlint:enable file_length
