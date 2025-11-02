import Combine
import ComposableArchitecture
import SwiftUI
import UIKit
import Logging

public struct UIPageCollection: UIViewControllerRepresentable {
    let store: StoreOf<ArchiveReaderFeature>

    public init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        return UIPageCollectionController(store: store)
    }

    public func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        // Nothing to do
    }
}

class UIPageCollectionController: UIViewController, UICollectionViewDelegate {
    private let logger = Logger(label: "UIPageCollectionController")

    let store: StoreOf<ArchiveReaderFeature>
    var collectionView: UICollectionView!
    var lastPageIndexPath: IndexPath?

    var dataSource:
        UICollectionViewDiffableDataSource<Section, StoreOf<PageFeature>>!
    var didInitialJump = false

    private var cancellables: Set<AnyCancellable> = []

    init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        let heightDimension =
            store.readDirection == ReadDirection.upDown.rawValue
        ? NSCollectionLayoutDimension.estimated(UIScreen.main.bounds.height)
            : NSCollectionLayoutDimension.fractionalHeight(1)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: NSCollectionLayoutDimension.fractionalWidth(store.doublePageLayout ? 0.5 : 1),
            heightDimension: heightDimension
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: heightDimension
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize, repeatingSubitem: item, count: store.doublePageLayout ? 2 : 1)

        let section = NSCollectionLayoutSection(group: group)

        section.visibleItemsInvalidationHandler = { [weak self] items, _, _ in
            guard let self else { return }
            if let idx = items.last?.indexPath, self.lastPageIndexPath != idx {
                self.store.send(.setSliderIndex(Double(idx.row)))
                store.send(.updateProgress(dataSource.itemIdentifier(for: idx)?.pageNumber ?? 1))
                self.lastPageIndexPath = items.last?.indexPath
            }
        }

        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = store.readDirection == ReadDirection.upDown.rawValue ? .vertical : .horizontal
        let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        if store.readDirection != ReadDirection.upDown.rawValue {
            collectionView.showsHorizontalScrollIndicator = false
            collectionView.isPagingEnabled = true
        }
        view.addSubview(collectionView)
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
            UIPageCell.self, forCellWithReuseIdentifier: "Page"
        )

        let cellRegistration = UICollectionView
            .CellRegistration<UIPageCell, StoreOf<PageFeature>> { [weak self] cell, _, pageStore in
            guard self != nil else { return }
            cell.configure(with: pageStore)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, StoreOf<PageFeature>>(
            collectionView: collectionView
        ) { collectionView, indexPath, pageStore in
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
            guard !store.pages.isEmpty else { return }
            var snapshot = NSDiffableDataSourceSnapshot<
                Section, StoreOf<PageFeature>
            >()
            snapshot.appendSections([.main])
            snapshot.appendItems(
                Array(store.scope(state: \.pages, action: \.page)))
            dataSource.apply(snapshot, animatingDifferences: false)
            if !didInitialJump, let idx = store.jumpIndex {
                let indexPath = IndexPath(row: idx, section: 0)
                if store.readDirection == ReadDirection.upDown.rawValue {
                    if let attr = collectionView.layoutAttributesForItem(at: indexPath) {
                        collectionView.scrollRectToVisible(attr.frame, animated: false)
                    }
                } else {
                    collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
                }
                didInitialJump = true
                store.send(.setJumpIndex(nil))
            }
        }

        store.publisher.jumpIndex
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] idx in
                guard let self else { return }
                guard collectionView.numberOfSections > 0 else { return }
                let numberOfItems = collectionView.numberOfItems(inSection: 0)
                guard idx < numberOfItems else { return }
                let indexPath = IndexPath(row: idx, section: 0)
                if store.readDirection == ReadDirection.upDown.rawValue {
                    if let attr = collectionView.layoutAttributesForItem(at: indexPath) {
                        collectionView.scrollRectToVisible(attr.frame, animated: false)
                    }
                } else {
                    collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
                }
                store.send(.setJumpIndex(nil))
            }
            .store(in: &cancellables)

        store.publisher.autoDate
            .dropFirst()
            .sink { [weak self] _ in
                self?.handleTapAction(action: PageControl.next.rawValue)
            }
            .store(in: &cancellables)
    }

    private func setupGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        collectionView.addGestureRecognizer(tapGesture)
        tapGesture.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupCollectionView()
        setupCell()
        setupObserve()
        setupGesture()

        collectionView.delegate = self
        collectionView.prefetchDataSource = self

        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    // MARK: - Rotation / Size Change Handling
    private var pendingResnap = false

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard collectionView != nil else { return }
        // Capture current visual page index before transition
        let indexPathToRestore = currentVisualPageIndexPath()
        pendingResnap = true
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: { _ in
            // On completion ensure we snap exactly to the intended page
            self.resnap(to: indexPathToRestore)
            self.pendingResnap = false
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Safety snap if layout changed and coordinator completion hasn't fired yet
        if pendingResnap {
            resnap(to: currentVisualPageIndexPath())
            pendingResnap = false
        }
    }

    // Returns index path representing the start of the current visual page (accounts for double page layout)
    private func currentVisualPageIndexPath() -> IndexPath? {
        guard collectionView != nil else { return nil }
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return nil }
        // Use the last (right-most) visible item for consistency with existing slider logic
        let sorted = visible.sorted()
        return startOfGroupIndexPath(for: sorted.last!)
    }

    // For double page layout treat a pair of items as one visual page; return left item index path
    private func startOfGroupIndexPath(for indexPath: IndexPath) -> IndexPath {
        guard store.doublePageLayout else { return indexPath }
        let row = indexPath.row % 2 == 0 ? indexPath.row : indexPath.row - 1
        return IndexPath(row: row, section: indexPath.section)
    }

    private func resnap(to indexPath: IndexPath?) {
        guard collectionView != nil else { return }
        guard store.readDirection != ReadDirection.upDown.rawValue else { return } // Only horizontal paging needs resnap
        guard let indexPath else { return }
        let numberOfItems = collectionView.numberOfItems(inSection: indexPath.section)
        guard indexPath.row < numberOfItems else { return }
        // Scroll without animation to avoid intermediate half pages
        collectionView.scrollToItem(at: indexPath, at: .left, animated: false)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                switch key.keyCode {
                case .keyboardLeftArrow:
                    handleTapAction(action: store.tapRight)
                case .keyboardRightArrow:
                    handleTapAction(action: store.tapLeft)
                default:
                    super.pressesBegan(presses, with: event)
                }
            }
        }
    }

    enum Section {
        case main
    }
}

extension UIPageCollectionController: UIGestureRecognizerDelegate {
    enum TapRegion {
        case left
        case middle
        case right
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let width = view.bounds.width
        let locationInView = gesture.location(in: view)
        // Clamp just in case (e.g. during interactive transitions)
        let xAxis = max(0, min(width, locationInView.x))

        let region: TapRegion
        switch xAxis {
        case ..<(width / 3):
            region = .left
        case (width / 3)..<(2 * width / 3):
            region = .middle
        default:
            region = .right
        }

        // Handle the tap based on region
        handleTapInRegion(region, atLocation: locationInView)
    }

    private func handleTapInRegion(_ region: TapRegion, atLocation location: CGPoint) {
        // Handle tap in region but not on any cell
        if store.readDirection != ReadDirection.upDown.rawValue {
            switch region {
            case .left:
                handleTapAction(action: store.tapLeft)
            case .middle:
                handleTapAction(action: store.tapMiddle)
            case .right:
                handleTapAction(action: store.tapRight)
            }
        } else {
            store.send(.toggleControlUi(nil))
        }
    }

    private func handleTapAction(action: String) {
        switch action {
        case PageControl.next.rawValue:
            let row = store.sliderIndex.int + 1
            guard row < store.pages.count else { break }
            let indexPath = IndexPath(row: row, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .left, animated: true)
        case PageControl.previous.rawValue:
            let row = store.doublePageLayout ? store.sliderIndex.int - 2 : store.sliderIndex.int - 1
            guard row >= 0 else { break }
            let indexPath = IndexPath(row: row, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .left, animated: true)
        case PageControl.navigation.rawValue:
            store.send(.toggleControlUi(nil))
        default:
            // This should not happen
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if store.readDirection == ReadDirection.upDown.rawValue {
            if collectionView.isDragging || collectionView.isDecelerating {
                return false
            }
        } else {
            if let innerScrollView = collectionView.subviews.first(
                where: { $0 is UIScrollView && $0 != collectionView }
            ) as? UIScrollView {
                // Only allow the tap if the scroll view is not currently dragging.
                return innerScrollView.panGestureRecognizer.state != .began &&
                innerScrollView.panGestureRecognizer.state != .changed
            }
        }
        return true
    }
}

extension UIPageCollectionController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        if let pageCell = cell as? UIPageCell {
            Task {
                await pageCell.store?.send(.load(false)).finish()
                if store.readDirection == ReadDirection.upDown.rawValue {
                    collectionView.performBatchUpdates { }
                }
            }
        }
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
                    }
                }
            }
        }
    }
}
