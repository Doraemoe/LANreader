// swiftlint:disable file_length
import Combine
import ComposableArchitecture
import SwiftUI
import UIKit
import Logging

@Reducer public struct ArchiveListFeature {
    private let logger = Logger(label: "ArchiveListFeature")

    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        @SharedReader(.appStorage(SettingsKey.lanraragiUrl)) var lanraragiUrl = ""
        @SharedReader(.appStorage(SettingsKey.searchSortCustom)) var searchSortCustom = ""
        @Shared(.appStorage(SettingsKey.hideRead)) var hideRead = false
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

        case deleteButtonTapped
        case deleteSuccess(Set<String>)
        case removeFromCategoryButtonTapped
        case removeFromCategorySuccess(Set<String>)
        public enum Alert {
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
                state.archivesToDisplay = .init()
                state.archives = .init()
                return .none
            case let .load(showLoading):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                if showLoading {
                    state.showLoading = showLoading
                }
                let sortby = state.searchSort
                let order = state.searchSortOrder
                self.populateTags(state: &state)
                return self.search(
                    searchFilter: state.filter, sortby: sortby, start: "0", order: order, append: false
                )
            case let .appendArchives(start):
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
                return .none
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
                if !append {
                    state.archives = .init()
                    state.archivesToDisplay = .init()
                    state.total = 0
                }
                state.archives.append(contentsOf: gridFeatureState)

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
                state.errorMessage = message
                return .none
            case let .setSuccessMessage(message):
                state.successMessage = message
                return .none
            case .grid:
                return .none
            case .cancelSearch:
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
                return .none
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
                return .none
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
    ) -> Effect<Action> {
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
        .cancellable(id: CancelId.search)
    }
}

class UIArchiveListViewController: UIViewController {
    let store: StoreOf<ArchiveListFeature>

    var collectionView: UICollectionView!
    var dataSource:
        UICollectionViewDiffableDataSource<Section, StoreOf<GridFeature>>!
    var isLoading = false

    private let refreshControl = UIRefreshControl()
    private var cancellables: Set<AnyCancellable> = []

    init(store: StoreOf<ArchiveListFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment -> NSCollectionLayoutSection? in
            let containerWidth = layoutEnvironment.container.effectiveContentSize.width
            let columns = max(Int(containerWidth / 180), 1)
            let interItemSpacing: CGFloat = 8.0
            let totalSpacing = CGFloat(columns - 1) * interItemSpacing

            let availableWidth = containerWidth - totalSpacing
            let cellWidth = availableWidth / CGFloat(columns)
            let cellHeight = (cellWidth / 2.0 * 3.0) + 10.0

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .fractionalHeight(1.0)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)

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

            let section = NSCollectionLayoutSection(group: group)

            let footerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(80)
            )
            let footer = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: footerSize,
                elementKind: UICollectionView.elementKindSectionFooter,
                alignment: .bottom
            )
            section.boundarySupplementaryItems = [footer]

            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
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

        let otherGroup = UIMenu(title: "", options: .displayInline, children: [randomAction, hideReadAction])

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
        observe { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<
                Section, StoreOf<GridFeature>
            >()
            snapshot.appendSections([.main])
            snapshot.appendItems(
                Array(store.scope(state: \.archivesToDisplay, action: \.grid)))
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        observe { [weak self] in
            guard let self else { return }
            guard !store.archives.isEmpty else { return }
            setupToolbar()
        }

        store.publisher.lanraragiUrl
            .scan((previous: nil as String?, current: nil as String?)) { tuple, newValue in
                (previous: tuple.current, current: newValue)
            }
            .dropFirst()
            .sink { [weak self] (previous, current) in
                guard let self else { return }
                if previous != current && current?.isEmpty == false {
                    store.send(.cancelSearch)
                    store.send(.resetArchives)
                    manualTriggerPullToRefresh()
                }
            }
            .store(in: &cancellables)

        store.publisher.searchSort
            .scan((previous: nil as String?, current: nil as String?)) { tuple, newValue in
                (previous: tuple.current, current: newValue)
            }
            .dropFirst()
            .sink { [weak self] (previous, current) in
                guard let self else { return }
                if previous != current {
                    store.send(.cancelSearch)
                    store.send(.resetArchives)
                    manualTriggerPullToRefresh()
                }
            }
            .store(in: &cancellables)

        store.publisher.searchSortOrder
            .scan((previous: nil as String?, current: nil as String?)) { tuple, newValue in
                (previous: tuple.current, current: newValue)
            }
            .dropFirst()
            .sink { [weak self] (previous, current) in
                guard let self else { return }
                if previous != current {
                    store.send(.cancelSearch)
                    store.send(.resetArchives)
                    manualTriggerPullToRefresh()
                }
            }
            .store(in: &cancellables)

        store.publisher[dynamicMember: \ArchiveListFeature.State.filter]
            .scan((previous: nil as SearchFilter?, current: nil as SearchFilter?)) { tuple, newValue in
                (previous: tuple.current, current: newValue as SearchFilter?)
            }
            .dropFirst()
            .sink { [weak self] (previous, current) in
                guard let self else { return }
                guard current?.filter?.isEmpty == false else { return }
                if previous?.filter != current?.filter {
                    store.send(.cancelSearch)
                    store.send(.resetArchives)
                    manualTriggerPullToRefresh()
                }
            }
            .store(in: &cancellables)
    }
    // swiftlint:enable function_body_length

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        setupRefresh()
        setupCell()
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
        Task {
            await store.send(.load(true)).finish()
            refreshControl.endRefreshing()
        }
    }

    private func manualTriggerPullToRefresh() {
        guard collectionView.refreshControl?.isRefreshing == false else { return }
        collectionView.refreshControl?.beginRefreshing()
        let offsetPoint = CGPoint(x: 0, y: -collectionView.adjustedContentInset.top - refreshControl.frame.height)
        collectionView.setContentOffset(offsetPoint, animated: true)
        collectionView.refreshControl?.sendActions(for: .valueChanged)
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
            if store.searchSort != SearchSort.random.rawValue
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
        let allArchives = dataSource.snapshot().itemIdentifiers(inSection: .main).map { $0.$archive }
        let readerStore = Store(
            initialState: ArchiveReaderFeature.State.init(
                currentArchiveId: selectedItemStore.archive.id,
                allArchives: allArchives
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
