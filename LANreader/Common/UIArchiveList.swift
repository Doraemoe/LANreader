import Combine
import ComposableArchitecture
import SwiftUI
import UIKit

public struct UIArchiveList: UIViewControllerRepresentable {
    let store: StoreOf<ArchiveListFeature>

    public init(store: StoreOf<ArchiveListFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UIArchiveListViewController(store: store)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
}

class UIArchiveListViewController: UICollectionViewController {
    let store: StoreOf<ArchiveListFeature>

    var dataSource:
        UICollectionViewDiffableDataSource<Section, StoreOf<GridFeature>>!
    var isLoading = false

    private let refreshControl = UIRefreshControl()
    private var cancellables: Set<AnyCancellable> = []

    init(store: StoreOf<ArchiveListFeature>) {
        self.store = store
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupLayout() {
        guard
            let layout = collectionView.collectionViewLayout
                as? UICollectionViewFlowLayout
        else { return }

        layout.minimumInteritemSpacing = 5
        layout.sectionInset = UIEdgeInsets(
            top: 10, left: 10, bottom: 10, right: 10)

        if let viewWidth = parent?.view.bounds.width {
            if viewWidth / 3 < 160 {
                let width = viewWidth / 2 - 15
                layout.itemSize = CGSize(
                    width: width, height: width / 2 * 3 + 10)
            } else {
                layout.itemSize = CGSize(width: 190, height: 295)
            }
        } else {
            layout.itemSize = CGSize(width: 180, height: 270)
        }
    }

    func setupRefresh() {
        refreshControl.addTarget(
            self, action: #selector(didPullToRefresh(_:)), for: .valueChanged)
        collectionView.alwaysBounceVertical = true
        collectionView.refreshControl = refreshControl
    }

    func setupCollectionView() {
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .inline
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            collectionView.bottomAnchor.constraint(
                equalTo: self.view.bottomAnchor),
            collectionView.leadingAnchor.constraint(
                equalTo: self.view.leadingAnchor),
            collectionView.trailingAnchor.constraint(
                equalTo: self.view.trailingAnchor)

        ])
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

    func setupToolbar() {
        let actions = SearchSort.allCases.map { sort in
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
                    nil
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

        let hideReadAction = UIAction(
            title: String(localized: "settings.view.hideRead"),
            image: store.hideRead ? UIImage(systemName: "checkmark") : nil
        ) { [weak self] _ in
            guard let self else { return }
            store.send(.toggleHideRead)
        }

        // Create a menu with the actions
        let menu = UIMenu(title: "", children: [sortGroup, hideReadAction])
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.circle"), menu: menu
        )
        parent?.navigationItem.rightBarButtonItem = menuButton
    }

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

        setupLayout()
        setupRefresh()
        setupCollectionView()
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
        let offsetPoint = CGPoint.init(
            x: 0, y: -refreshControl.frame.size.height)
        collectionView.setContentOffset(offsetPoint, animated: true)
        collectionView.refreshControl?.sendActions(for: .valueChanged)
    }

    enum Section {
        case main
    }
}

extension UIArchiveListViewController: UICollectionViewDelegateFlowLayout {
    override func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        if indexPath.item == collectionView.numberOfItems(inSection: 0) - 1 {
            if store.loading == false && store.archives.count < store.total {
                Task {
                    self.isLoading = true
                    collectionView.collectionViewLayout.invalidateLayout()
                    await store.send(
                        .appendArchives(String(store.archives.count))
                    ).finish()
                    self.isLoading = false
                    collectionView.collectionViewLayout.invalidateLayout()
                }
            }
        }
    }

    override func collectionView(
        _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
    ) {
        guard let selectedItemStore = dataSource.itemIdentifier(for: indexPath)
        else { return }
        let readerStore = Store(
            initialState: ArchiveReaderFeature.State.init(
                archive: selectedItemStore.$archive)
        ) {
            ArchiveReaderFeature()
        }
        let readerController = UIArchiveReaderController(store: readerStore)
        readerController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(
            readerController, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int
    ) -> CGSize {
        return isLoading
            ? CGSize(width: collectionView.bounds.width, height: 80) : .zero
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
