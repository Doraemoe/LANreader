import Combine
import ComposableArchitecture
import SwiftUI
import UIKit

public struct UIPageCollection: UIViewControllerRepresentable {
    let store: StoreOf<ArchiveReaderFeature>
    let size: CGSize

    public init(store: StoreOf<ArchiveReaderFeature>, size: CGSize) {
        self.store = store
        self.size = size
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UIPageCollectionController(store: store, size: size)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
}

class UIPageCollectionController: UICollectionViewController {
    let store: StoreOf<ArchiveReaderFeature>
    let size: CGSize

    var dataSource:
        UICollectionViewDiffableDataSource<Section, StoreOf<PageFeature>>!

    private var cancellables: Set<AnyCancellable> = []

    init(store: StoreOf<ArchiveReaderFeature>, size: CGSize) {
        self.store = store
        self.size = size

        let heightDimension =
            store.readDirection == ReadDirection.upDown.rawValue
            ? NSCollectionLayoutDimension.estimated(size.height)
            : NSCollectionLayoutDimension.fractionalHeight(1)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: NSCollectionLayoutDimension.fractionalWidth(1),
            heightDimension: heightDimension
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: itemSize, repeatingSubitem: item, count: 1)

        let section = NSCollectionLayoutSection(group: group)
        if store.readDirection != ReadDirection.upDown.rawValue {
            section.orthogonalScrollingBehavior = .groupPaging
        }

        let layout = UICollectionViewCompositionalLayout(section: section)

        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCollectionView() {
        collectionView.bounces = false
        collectionView.backgroundColor = .systemBackground
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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

    private func setupCell() {
        collectionView.register(
            UIPageCell.self, forCellWithReuseIdentifier: "Page")
        let cellRegistration = UICollectionView.CellRegistration<
            UIPageCell, StoreOf<PageFeature>
        > { [weak self] cell, _, pageStore in
            guard self != nil else { return }
            cell.configure(with: pageStore, size: self?.size ?? .zero)
        }

        dataSource = UICollectionViewDiffableDataSource<
            Section, StoreOf<PageFeature>
        >(collectionView: collectionView) { collectionView, indexPath, pageStore in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: pageStore
            )
        }
    }

    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<
                Section, StoreOf<PageFeature>
            >()
            snapshot.appendSections([.main])
            snapshot.appendItems(
                Array(store.scope(state: \.pages, action: \.page)))
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupCell()
        setupObserve()

        collectionView.delegate = self
        collectionView.prefetchDataSource = self
    }

    enum Section {
        case main
    }
}

extension UIPageCollectionController: UICollectionViewDataSourcePrefetching,
    UICollectionViewDelegateFlowLayout {

    override func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        if let pageCell = cell as? UIPageCell {
            Task {
                await pageCell.load {
                    if self.store.readDirection == ReadDirection.upDown.rawValue {
                        collectionView.collectionViewLayout.invalidateLayout()
                    }
                }
            }
        }
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {

    }

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        indexPaths.forEach { path in
            if let pageStore = dataSource.itemIdentifier(for: path) {
                if pageStore.pageMode == .loading {
                    Task {
                        await pageStore.send(.load(false)).finish()
                        if self.store.readDirection
                            == ReadDirection.upDown.rawValue {
                            collectionView.collectionViewLayout
                                .invalidateLayout()
                        }
                    }
                }
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
    }
}
