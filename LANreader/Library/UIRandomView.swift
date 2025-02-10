import ComposableArchitecture
import SwiftUI
import UIKit

class UIRandomViewController: UIViewController, UICollectionViewDelegate {
    
    let store: StoreOf<RandomFeature>
    private let refreshControl = UIRefreshControl()

    var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Section, StoreOf<GridFeature>>!
    
    init(store: StoreOf<RandomFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, layoutEnvironment -> NSCollectionLayoutSection? in
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
            section.interGroupSpacing = 8
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: 0,
                bottom: cellHeight * 0.4,
                trailing: 0
            )
            
            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        view.addSubview(collectionView)
    }
    
    private func configureDataSource() {
        collectionView.register(
            UIArchiveCell.self, forCellWithReuseIdentifier: "Archive")
        
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
    }
    
    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<
                Section, StoreOf<GridFeature>
            >()
            snapshot.appendSections([.main])
            snapshot.appendItems(
                Array(store.scope(state: \.archives, action: \.grid)))
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
    
    func setupRefresh() {
        refreshControl.addTarget(
            self, action: #selector(didPullToRefresh(_:)), for: .valueChanged)
        collectionView.alwaysBounceVertical = true
        collectionView.refreshControl = refreshControl
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupRefresh()
        configureDataSource()
        setupObserve()
        
        collectionView.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if store.archives.isEmpty {
            manualTriggerPullToRefresh()
        } else {
            store.send(.refreshDisplayArchives)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: false)
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
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
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
    
    enum Section {
        case main
    }
    
}
