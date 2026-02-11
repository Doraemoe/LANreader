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
    private let fullVisibilityThreshold: CGFloat = 0.98
    private var isProgrammaticPaging = false

    let store: StoreOf<ArchiveReaderFeature>
    var collectionView: UICollectionView!
    var lastPageIndexPath: IndexPath?

    var dataSource: UICollectionViewDiffableDataSource<Section, StoreOf<PageFeature>>!
    var didInitialJump = false
    private var lastSnapshotPageIds: [String] = []

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Pull Navigation
    private enum PullEdge {
        case previous, next
    }
    private let pullThreshold: CGFloat = 80
    private var pullEdge: PullEdge?
    private var pullProgress: CGFloat = 0 // 0..1
    private var pullActive: Bool = false
    private var pullIndicatorContainer: UIView = UIView()
    private var pullArrowView: UIImageView = UIImageView()
    private var pullStatusLabel: UILabel = UILabel()
    private var pullStatusBackground: UIVisualEffectView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemMaterial)
    )
    private var lastReportedProgressBucket: Int = -1 // for throttled updates
    private var pullThresholdCrossedHapticsFired = false

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
        let widthDimension =
        store.readDirection != ReadDirection.upDown.rawValue && store.doublePageLayout
        ? NSCollectionLayoutDimension.fractionalWidth(0.5)
        : NSCollectionLayoutDimension.fractionalWidth(1)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: widthDimension,
            heightDimension: heightDimension
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: heightDimension
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: store.readDirection != ReadDirection.upDown.rawValue && store.doublePageLayout ? 2 : 1
        )

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
        // Enable bounces so user can pull at first/last page for navigation UI
        collectionView.bounces = true
        if store.readDirection == ReadDirection.upDown.rawValue {
            collectionView.alwaysBounceVertical = true
        } else {
            collectionView.alwaysBounceHorizontal = true
        }
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
                let useAspectHeight = self?.store.readDirection == ReadDirection.upDown.rawValue
                cell.configure(with: pageStore, useAspectHeight: useAspectHeight)
                if self?.store.readDirection != ReadDirection.upDown.rawValue {
                    cell.setAnimationActive(false)
                }
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

    // swiftlint:disable function_body_length
    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            guard !store.pages.isEmpty else { return }
            let pageIds = store.pages.map(\.id)
            if pageIds != lastSnapshotPageIds {
                var snapshot = NSDiffableDataSourceSnapshot<
                    Section, StoreOf<PageFeature>
                >()
                snapshot.appendSections([.main])
                snapshot.appendItems(
                    Array(store.scope(state: \.pages, action: \.page)))
                dataSource.apply(snapshot, animatingDifferences: false)
                lastSnapshotPageIds = pageIds
                DispatchQueue.main.async { [weak self] in
                    self?.updateAnimatedPlaybackForVisibleCells()
                }
            }
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
                updateAnimatedPlaybackForVisibleCells()
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
                updateAnimatedPlaybackForVisibleCells()
            }
            .store(in: &cancellables)

        store.publisher.autoDate
            .dropFirst()
            .sink { [weak self] _ in
                self?.handleTapAction(action: PageControl.next.rawValue)
            }
            .store(in: &cancellables)
    }
    // swiftlint:enable function_body_length

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

        setupPullNavigationUI()

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
        updateAnimatedPlaybackForVisibleCells()
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
        guard store.readDirection != ReadDirection.upDown.rawValue && store.doublePageLayout else { return indexPath }
        let row = indexPath.row % 2 == 0 ? indexPath.row : indexPath.row - 1
        return IndexPath(row: row, section: indexPath.section)
    }

    private func resnap(to indexPath: IndexPath?) {
        guard collectionView != nil else { return }
        guard store.readDirection != ReadDirection.upDown.rawValue else { return }
        guard let indexPath else { return }
        let numberOfItems = collectionView.numberOfItems(inSection: indexPath.section)
        guard indexPath.row < numberOfItems else { return }
        // Scroll without animation to avoid intermediate half pages
        collectionView.scrollToItem(at: indexPath, at: .left, animated: false)
    }

    private func updateAnimatedPlaybackForVisibleCells() {
        guard collectionView != nil else { return }
        guard store.readDirection != ReadDirection.upDown.rawValue else { return }

        guard isPagingSettled() else {
            for case let pageCell as UIPageCell in collectionView.visibleCells {
                pageCell.setAnimationActive(false)
            }
            return
        }

        let activeIndexPaths = fullyVisibleHorizontalPageIndexPaths()
        for case let pageCell as UIPageCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: pageCell) else { continue }
            pageCell.setAnimationActive(activeIndexPaths.contains(indexPath))
        }
    }

    private func isPagingSettled() -> Bool {
        !collectionView.isDragging && !collectionView.isDecelerating && !isProgrammaticPaging
    }

    private func fullyVisibleHorizontalPageIndexPaths() -> Set<IndexPath> {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems.sorted()
        guard !visibleIndexPaths.isEmpty else { return [] }

        let fullyVisible = visibleIndexPaths.filter { indexPath in
            visibleRatio(for: indexPath) >= fullVisibilityThreshold
        }
        guard !fullyVisible.isEmpty else { return [] }

        guard store.doublePageLayout else {
            guard let target = fullyVisible.last else { return [] }
            return [target]
        }

        let grouped = Dictionary(grouping: fullyVisible) { indexPath in
            startOfGroupIndexPath(for: indexPath)
        }
        let sortedStarts = grouped.keys.sorted()
        for start in sortedStarts.reversed() {
            guard let groupItems = grouped[start] else { continue }
            let itemCount = collectionView.numberOfItems(inSection: start.section)
            let remaining = max(0, itemCount - start.row)
            let expectedCount = min(2, remaining)
            if groupItems.count == expectedCount {
                return Set(groupItems)
            }
        }

        return []
    }

    private func visibleRatio(for indexPath: IndexPath) -> CGFloat {
        guard let attrs = collectionView.layoutAttributesForItem(at: indexPath) else { return 0 }
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let intersection = attrs.frame.intersection(visibleRect)
        guard !intersection.isNull else { return 0 }
        let totalArea = attrs.frame.width * attrs.frame.height
        guard totalArea > 0 else { return 0 }
        return (intersection.width * intersection.height) / totalArea
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
            isProgrammaticPaging = true
            updateAnimatedPlaybackForVisibleCells()
            collectionView.scrollToItem(at: indexPath, at: .left, animated: true)
        case PageControl.previous.rawValue:
            let row = store.doublePageLayout ? store.sliderIndex.int - 2 : store.sliderIndex.int - 1
            guard row >= 0 else { break }
            let indexPath = IndexPath(row: row, section: 0)
            isProgrammaticPaging = true
            updateAnimatedPlaybackForVisibleCells()
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

// MARK: - Pull Navigation UI Logic
extension UIPageCollectionController {
    private func setupPullNavigationUI() {
        // Arrow container (initially hidden)
        pullIndicatorContainer.isHidden = true
        pullIndicatorContainer.clipsToBounds = false
        view.addSubview(pullIndicatorContainer)

        pullArrowView.contentMode = .scaleAspectFit
        pullArrowView.tintColor = .secondaryLabel
        pullIndicatorContainer.addSubview(pullArrowView)

        pullStatusLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        pullStatusLabel.textColor = .label
        pullStatusLabel.textAlignment = .center
        pullStatusLabel.numberOfLines = 1
        pullStatusLabel.isHidden = true

        pullStatusBackground.isHidden = true
        pullStatusBackground.clipsToBounds = true
        pullStatusBackground.layer.cornerRadius = 14
        pullStatusBackground.layer.cornerCurve = .continuous
        // Add label inside contentView
        pullStatusBackground.contentView.addSubview(pullStatusLabel)
        view.addSubview(pullStatusBackground)
    }

    private func isAtFirstVisualPage() -> Bool {
        if store.readDirection == ReadDirection.upDown.rawValue {
            // For vertical reading rely on scroll position for accuracy; allow small epsilon
            return collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
        } else if store.doublePageLayout {
            return store.sliderIndex.int <= 1
        }
        return store.sliderIndex.int <= 0
    }

    private func isAtLastVisualPage() -> Bool {
        let lastIndex = store.pages.count - 1
        if store.readDirection == ReadDirection.upDown.rawValue {
            // Check if we've scrolled to (or beyond) bottom
            let maxOffset = max(
                0,
                collectionView.contentSize.height -
                collectionView.bounds.height +
                collectionView.adjustedContentInset.bottom
            )
            return collectionView.contentOffset.y >= maxOffset - 1
        } else if store.doublePageLayout {
            // For double page layout treat last pair as last visual page
            return store.sliderIndex.int >= lastIndex - 1
        } else {
            return store.sliderIndex.int >= lastIndex
        }
    }

    private struct ScrollMetrics {
        let offset: CGFloat
        let maxOffset: CGFloat
        let axis: NSLayoutConstraint.Axis
    }

    private func currentScrollMetrics() -> ScrollMetrics? {
        guard let collectionView else { return nil }
        let axis: NSLayoutConstraint.Axis = store.readDirection == ReadDirection.upDown.rawValue ?
            .vertical : .horizontal
        if axis == .horizontal {
            let maxOffset = max(0, collectionView.contentSize.width - collectionView.bounds.width)
            return ScrollMetrics(offset: collectionView.contentOffset.x, maxOffset: maxOffset, axis: axis)
        } else {
            let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
            return ScrollMetrics(offset: collectionView.contentOffset.y, maxOffset: maxOffset, axis: axis)
        }
    }

    private func updatePullState(scroll metrics: ScrollMetrics) {
        let atFirst = isAtFirstVisualPage()
        let atLast = isAtLastVisualPage()
        guard atFirst || atLast else {
            endPullInteraction()
            return
        }

        let offset = metrics.offset
        let maxOffset = metrics.maxOffset
        var overscroll: CGFloat = 0
        if offset < 0 && atFirst {
            overscroll = -offset
            pullEdge = .previous
        } else if offset > maxOffset && atLast {
            overscroll = offset - maxOffset
            pullEdge = .next
        } else {
            endPullInteraction()
            return
        }

        pullActive = overscroll > 0
        pullProgress = min(1, overscroll / pullThreshold)
        // Throttle UI updates to avoid excessive layout work (bucket by 5%)
        let bucket = Int(pullProgress * 20) // 0..20
        guard bucket != lastReportedProgressBucket else { return }
        lastReportedProgressBucket = bucket
        layoutPullIndicator(overscroll: overscroll, axis: metrics.axis)
        updatePullViews()
    }

    // swiftlint:disable function_body_length
    private func layoutPullIndicator(overscroll: CGFloat, axis: NSLayoutConstraint.Axis) {
        guard let edge = pullEdge else { return }
        let maxVisualWidth: CGFloat = min(overscroll, pullThreshold * 1.25)
        let arrowSize: CGFloat = 32

        if axis == .horizontal {
            let isRTLReading = store.readDirection == ReadDirection.rightLeft.rawValue
            let containerFrame: CGRect
            if isRTLReading {
                switch edge {
                case .previous:
                    containerFrame = CGRect(
                        x: view.bounds.width - maxVisualWidth,
                        y: 0,
                        width: maxVisualWidth,
                        height: view.bounds.height
                    )
                case .next:
                    containerFrame = CGRect(x: 0, y: 0, width: maxVisualWidth, height: view.bounds.height)
                }
            } else {
                switch edge {
                case .previous:
                    containerFrame = CGRect(x: 0, y: 0, width: maxVisualWidth, height: view.bounds.height)
                case .next:
                    containerFrame = CGRect(
                        x: view.bounds.width - maxVisualWidth,
                        y: 0,
                        width: maxVisualWidth,
                        height: view.bounds.height
                    )
                }
            }
            pullIndicatorContainer.frame = containerFrame
            pullArrowView.frame = CGRect(
                x: (containerFrame.width - arrowSize) / 2,
                y: (containerFrame.height - arrowSize) / 2,
                width: arrowSize,
                height: arrowSize
            )
        } else {
            let containerFrame: CGRect
            switch edge {
            case .previous:
                containerFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: maxVisualWidth)
            case .next:
                containerFrame = CGRect(
                    x: 0,
                    y: view.bounds.height - maxVisualWidth,
                    width: view.bounds.width,
                    height: maxVisualWidth
                )
            }
            pullIndicatorContainer.frame = containerFrame
            pullArrowView.frame = CGRect(
                x: (containerFrame.width - arrowSize) / 2,
                y: (containerFrame.height - arrowSize) / 2,
                width: arrowSize,
                height: arrowSize
            )
        }
    }
    // swiftlint:enable function_body_length

    private func layoutStatusLabel() {
        let maxWidth = min(view.bounds.width * 0.7, 360)
        pullStatusLabel.sizeToFit()
        let intrinsic = pullStatusLabel.bounds.size
        let paddedWidth = min(maxWidth, intrinsic.width + 32)
        let height: CGFloat = max(40, intrinsic.height + 16)
        pullStatusBackground.frame = CGRect(
            x: (view.bounds.width - paddedWidth)/2,
            y: view.bounds.midY - height/2,
            width: paddedWidth,
            height: height
        )
        pullStatusLabel.frame = CGRect(
            x: 0,
            y: (height - pullStatusLabel.font.lineHeight)/2 - 1,
            width: paddedWidth,
            height: pullStatusLabel.font.lineHeight + 2
        )
    }

    private func symbolName(for edge: PullEdge, axis: NSLayoutConstraint.Axis, flipped: Bool) -> String {
        let isRTLReading = store.readDirection == ReadDirection.rightLeft.rawValue
        if axis == .horizontal {
            if isRTLReading {
                switch edge {
                case .previous: return flipped ? "arrow.right" : "arrow.left"
                case .next:     return flipped ? "arrow.left"  : "arrow.right"
                }
            } else {
                switch edge {
                case .previous: return flipped ? "arrow.left" : "arrow.right"
                case .next:     return flipped ? "arrow.right" : "arrow.left"
                }
            }
        } else {
            switch edge {
            case .previous: return flipped ? "arrow.up" : "arrow.down"
            case .next:     return flipped ? "arrow.down" : "arrow.up"
            }
        }
    }

    private func isAtFirstArchive() -> Bool {
        guard let first = store.allArchives.first else { return false }
        return store.currentArchiveId == first.wrappedValue.id
    }

    private func isAtLastArchive() -> Bool {
        guard let last = store.allArchives.last else { return false }
        return store.currentArchiveId == last.wrappedValue.id
    }

    private func updatePullViews() {
        guard pullActive, let edge = pullEdge, let metrics = currentScrollMetrics() else { return }
        pullIndicatorContainer.isHidden = false
        pullStatusBackground.isHidden = false
        pullStatusLabel.isHidden = false
        let atArchiveBoundary = (edge == .previous && isAtFirstArchive()) || (edge == .next && isAtLastArchive())
        let flipped = !atArchiveBoundary && pullProgress >= 1
        pullArrowView.image = UIImage(systemName: symbolName(for: edge, axis: metrics.axis, flipped: flipped))

        if atArchiveBoundary {
            if edge == .previous {
                pullStatusLabel.text = String(localized: "archive.read.first")
            } else {
                pullStatusLabel.text = String(localized: "archive.read.last")
            }
        } else if flipped {
            pullStatusLabel.text = String(localized: "archive.read.load")
        } else {
            switch edge {
            case .previous: pullStatusLabel.text = String(localized: "archive.read.previous")
            case .next: pullStatusLabel.text = String(localized: "archive.read.next")
            }
        }
        layoutStatusLabel()
        if flipped && !pullThresholdCrossedHapticsFired {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            pullThresholdCrossedHapticsFired = true
        } else if !flipped {
            pullThresholdCrossedHapticsFired = false
        }
        let alpha = min(1, 0.3 + pullProgress * 0.7)
        pullArrowView.alpha = alpha
        pullStatusLabel.alpha = alpha
        pullStatusBackground.alpha = alpha
    }

    private func endPullInteraction() {
        pullActive = false
        pullEdge = nil
        pullProgress = 0
        lastReportedProgressBucket = -1
        pullIndicatorContainer.isHidden = true
        pullStatusLabel.isHidden = true
        pullStatusBackground.isHidden = true
        pullThresholdCrossedHapticsFired = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        guard let metrics = currentScrollMetrics() else { return }
        updatePullState(scroll: metrics)
        updateAnimatedPlaybackForVisibleCells()
    }

    func resetCollectionView() {
        let snapshot = NSDiffableDataSourceSnapshot<
            Section, StoreOf<PageFeature>
        >()
        dataSource.apply(snapshot, animatingDifferences: false)
        lastSnapshotPageIds = []
        collectionView.setContentOffset(.zero, animated: false)
        lastPageIndexPath = nil
        didInitialJump = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === collectionView else { return }
        if pullActive && pullProgress >= 1, let edge = pullEdge {
            let atArchiveBoundary = (edge == .previous && isAtFirstArchive()) || (edge == .next && isAtLastArchive())
            if !atArchiveBoundary {
                resetCollectionView()
                switch edge {
                case .previous:
                    store.send(.loadPreviousArchive)
                case .next:
                    store.send(.loadNextArchive)
                }
                let successGen = UINotificationFeedbackGenerator()
                successGen.prepare()
                successGen.notificationOccurred(.success)
            }
        }

        endPullInteraction()
        if !decelerate {
            isProgrammaticPaging = false
            updateAnimatedPlaybackForVisibleCells()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        isProgrammaticPaging = false
        updateAnimatedPlaybackForVisibleCells()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        isProgrammaticPaging = false
        updateAnimatedPlaybackForVisibleCells()
    }
}

extension UIPageCollectionController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        if let pageCell = cell as? UIPageCell {
            if let pageStore = pageCell.store,
                pageStore.pageMode == .loading || !pageStore.imageLoaded {
                Task {
                    await pageStore.send(.load(false)).finish()
                    if store.readDirection == ReadDirection.upDown.rawValue {
                        collectionView.performBatchUpdates { }
                    }
                }
            }
            updateAnimatedPlaybackForVisibleCells()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        indexPaths.forEach { path in
            if let pageStore = dataSource.itemIdentifier(for: path) {
                if pageStore.pageMode == .loading || !pageStore.imageLoaded {
                    Task {
                        await pageStore.send(.load(false)).finish()
                    }
                }
            }
        }
    }
}
