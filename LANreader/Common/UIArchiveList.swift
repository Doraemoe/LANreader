import ComposableArchitecture
import OrderedCollections
import SwiftUI
import UIKit

class UIArchiveListViewController: UIViewController {
    let store: StoreOf<ArchiveListFeature>
    @Dependency(\.appDatabase) var database

    var renderedSelectionToolbarState: ArchiveListSelectionToolbarState?
    var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Section, StoreOf<GridFeature>>!
    var isLoading = false

    private let refreshControl = UIRefreshControl()
    private var lastObservedLanraragiUrl: String?
    private var lastObservedSearchSort: String?
    private var lastObservedSearchSortOrder: String?
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
        let layout = ArchiveListLayoutBuilder.makeCollectionViewLayout()
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

    func setupRefresh() {
        refreshControl.addTarget(
            self, action: #selector(didPullToRefresh(_:)), for: .valueChanged
        )
        collectionView.alwaysBounceVertical = true
        collectionView.refreshControl = refreshControl
    }

    func setupCell() {
        collectionView.register(UIArchiveCell.self, forCellWithReuseIdentifier: "Archive")
        collectionView.register(
            LoadingReusableView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: LoadingReusableView.reuseIdentifier
        )

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
                using: cellRegistration, for: indexPath, item: itemStore
            )
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionFooter else { return nil }
            let footer = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: LoadingReusableView.reuseIdentifier,
                for: indexPath
            ) as? LoadingReusableView
            if self?.isLoading == true {
                footer?.startAnimation()
            } else {
                footer?.stopAnimation()
            }
            return footer
        }
    }

    func goToPage(_ page: Int) {
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
                onSelectPage: { [weak self] page in self?.goToPage(page) },
                onRequestPageInput: { [weak self] in self?.presentPageInput() }
            )
            paginationBar.layoutIfNeeded()
        }
        updateContentInsetForPaginationBar()
    }

    func setupObserve() {
        lastObservedLanraragiUrl = store.lanraragiUrl
        lastObservedSearchSort = store.searchSort
        lastObservedSearchSortOrder = store.searchSortOrder

        observeListContentAndDisplay()
        observeReloadTriggers()
        observeStatusBanners()
    }

    private func observeListContentAndDisplay() {
        observe { [weak self] in
            self?.setupToolbar()
        }
        observe { [weak self] in
            self?.renderSelectionToolbarIfNeeded()
        }
        observe { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<Section, StoreOf<GridFeature>>()
            snapshot.appendSections([.main])
            snapshot.appendItems(Array(store.scope(\.archivesToDisplay, action: \.grid)))
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        observe { [weak self] in
            guard let self else { return }
            collectionView.backgroundView = store.showsReadFilterEmptyState ? readFilterEmptyView : nil
        }
        observe { [weak self] in
            guard let self else { return }
            if store.loading {
                if store.archives.isEmpty, view.window != nil,
                   !refreshControl.isRefreshing, !store.batchActionInProgress {
                    beginRefreshingAtTop()
                }
            } else {
                refreshControl.endRefreshing()
            }
        }
        observe { [weak self] in
            // `observe` only re-runs when the state read here changes, and rendering the bar
            // is idempotent, so no change tracking of its own is needed.
            self?.renderPaginationBar()
        }
    }

    private func observeReloadTriggers() {
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
    }

    private func observeStatusBanners() {
        observe { [weak self] in
            guard let self else { return }
            let message = store.errorMessage
            guard !message.isEmpty else { return }
            showNotificationBanner(title: String(localized: "error"), subtitle: message, style: .danger)
            store.send(.setErrorMessage(""))
        }
        observe { [weak self] in
            guard let self else { return }
            let message = store.successMessage
            guard !message.isEmpty else { return }
            showNotificationBanner(title: String(localized: "success"), subtitle: message, style: .success)
            store.send(.setSuccessMessage(""))
        }
    }

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
        if navigationController?.topViewController === parent,
           navigationController?.isNavigationBarHidden == true {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
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
        store.send(.load)
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
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard indexPath.item == collectionView.numberOfItems(inSection: 0) - 1,
              store.paginationActive == false,
              store.selectMode != .active,
              store.searchSort != SearchSort.random.rawValue,
              store.loading == false,
              store.archives.count < store.total else {
            return
        }
        Task {
            self.isLoading = true
            collectionView.performBatchUpdates { }
            await store.send(.appendArchives(String(store.archives.count))).finish()
            self.isLoading = false
            collectionView.performBatchUpdates { }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let selectedItemStore = dataSource.itemIdentifier(for: indexPath) else { return }
        if store.selectMode == .active {
            store.send(
                store.selected.contains(selectedItemStore.id)
                    ? .removeSelect(selectedItemStore.id)
                    : .addSelect(selectedItemStore.id)
            )
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
        store.send(.openReader(archiveId: itemStore.archive.id, fromStart: fromStart))
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
