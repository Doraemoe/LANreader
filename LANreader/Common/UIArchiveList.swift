// swiftlint:disable file_length
import ComposableArchitecture
import SwiftUI
import UIKit
import Logging

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
        var selected: Set<String> = .init()
        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []
        @Shared(.category) var categoryItems: IdentifiedArrayOf<CategoryItem> = []
        var filter: SearchFilter
        var loadOnAppear = true
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var showLoading: Bool = false
        var total: Int = 0
        var errorMessage = ""
        var successMessage = ""
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
        case updateLocalCategory(String, Set<String>)
        case setFilter(SearchFilter)
        case resetArchives
        case reloadFromFirstPage
        case load(Bool)
        case populateArchives([ArchiveItem], Int, Bool)
        case refreshThumbnail(String)
        case appendArchives(String)
        case removeArchive(String)
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
        case removeFromCategorySuccess(Set<String>)
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
            case let .setFilter(filter):
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
            case let .setErrorMessage(message):
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
                state.selected.insert(id)
                return .none
            case let .removeSelect(id):
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

                return .none
            case .alert(.dismiss):
                return .none
            case .alert(.presented(.confirmRemoveFromCategory)):
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in state.selected {
                        do {
                            let response = try await service.removeArchiveFromCategory(
                                categoryId: state.filter.category!, archiveId: archiveId
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
                                categoryId=\(state.filter.category ?? ""), archiveId=\(archiveId) \(error)
                                """
                            )
                            errorIds.insert(archiveId)
                        }

                    }

                    if !errorIds.isEmpty {
                        await send(.setErrorMessage(
                            String(localized: "archive.selected.category.remove.error")
                        ))
                    } else {
                        await send(.setSuccessMessage(
                            String(localized: "archive.selected.category.remove.success")
                        ))
                    }
                    await send(.removeFromCategorySuccess(successIds))
                }
            case let .removeFromCategorySuccess(archiveIds):
                archiveIds.forEach { id in
                    state.selected.remove(id)
                    state.archivesToDisplay.remove(id: id)
                    state.archives.remove(id: id)
                }
                state.loading = false
                return reloadPageAfterRemoval(state: &state, removedCount: archiveIds.count)
            case .alert(.presented(.confirmDelete)):
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()

                    for archiveId in state.selected {
                        do {
                            let response = try await service.deleteArchive(id: archiveId).value
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
                state.loading = true
                return .run { [state] send in
                    var successIds: Set<String> = .init()
                    var errorIds: Set<String> = .init()
                    let currentCategory = state.$categoryItems.withLock { $0[id: categoryId]! }

                    for archiveId in state.selected {
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
                    if !errorIds.isEmpty {
                        await send(.setErrorMessage(
                            String(localized: "archive.selected.category.add.error")
                        ))
                    } else {
                        await send(.setSuccessMessage(
                            String(localized: "archive.selected.category.add.success")
                        ))
                    }
                    await send(.updateLocalCategory(categoryId, successIds))
                }
            case let .updateLocalCategory(categoryId, archiveIds):
                state.$categoryItems.withLock {
                    $0[id: categoryId]?.archives.append(contentsOf: archiveIds)
                }
                archiveIds.forEach { id in
                    state.selected.remove(id)
                }
                state.loading = false
                return .none
            }
        }
        .forEach(\.archivesToDisplay, action: \.grid) {
            GridFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

extension ArchiveListFeature {
    private func resetArchives(state: inout State) {
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
    /// Random sort is served by an endpoint that has no offset paging, so the pager
    /// stays hidden there even when the mode is enabled.
    var paginationActive: Bool {
        paginateArchiveList && searchSort != SearchSort.random.rawValue
    }

    var showsPager: Bool {
        paginationActive && pageCount > 1
    }
}

class UIArchiveListViewController: UIViewController {
    let store: StoreOf<ArchiveListFeature>

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
            guard self != nil else { return }
            cell.configure(with: itemStore)
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
        let menu = UIMenu(title: "", children: [sortGroup, otherGroup])
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
            guard !store.archives.isEmpty else { return }
            setupToolbar()
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
    }
    // swiftlint:enable function_body_length

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        setupRefresh()
        setupCell()
        setupPaginationBar()
        setupObserve()

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
        openReader(for: selectedItemStore)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let itemStore = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let readFromStart = UIAction(
                title: String(localized: "archive.read.fromStart"),
                image: UIImage(systemName: "arrow.left.to.line.compact")
            ) { _ in
                self?.openReader(for: itemStore, fromStart: true)
            }
            return UIMenu(title: "", children: [readFromStart])
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
