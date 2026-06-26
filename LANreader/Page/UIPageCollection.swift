import ComposableArchitecture
import SwiftUI
import UIKit

// swiftlint:disable file_length

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
    let store: StoreOf<ArchiveReaderFeature>
    var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Section, String>!
    private var lastReportedVisiblePageIndex: Int?
    private var appliedPageIds: [String] = []
    private var isApplyingSnapshot = false
    private var activeAnimatedScrollTargetPageId: String?

    private struct SnapshotAnchor {
        let pageId: String
        let offsetFromViewportOrigin: CGPoint
        let resolvesAnimatedScroll: Bool
    }

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
    private var pullProgressView: UIProgressView = UIProgressView(progressViewStyle: .default)
    private var pullStatusBackground: UIVisualEffectView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterial)
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

        section.visibleItemsInvalidationHandler = { [weak self] _, _, _ in
            guard let self else { return }
            self.reportVisiblePageIfNeeded()
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
            .CellRegistration<UIPageCell, String> { [weak self] cell, _, pageId in
                guard let self, let pageStore = self.pageStore(id: pageId) else { return }
                cell.configure(with: pageStore)
            }

        dataSource = UICollectionViewDiffableDataSource<Section, String>(
            collectionView: collectionView
        ) { collectionView, indexPath, pageId in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: pageId
            )
        }
    }

    private func pageStore(id pageId: String) -> StoreOf<PageFeature>? {
        Array(store.scope(\.pages, action: \.page)).first { $0.id == pageId }
    }

    private func pageStore(at indexPath: IndexPath) -> StoreOf<PageFeature>? {
        guard let pageId = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return pageStore(id: pageId)
    }

    private var resolvedReadDirection: ReadDirection {
        ReadDirection(rawValue: store.readDirection) ?? .leftRight
    }
    private func scrollPosition(for request: ScrollRequest) -> UICollectionView.ScrollPosition {
        switch request.source {
        case .initialRestore, .slider:
            return .centeredHorizontally
        case .tap, .keyboard, .autoPage:
            return .left
        }
    }

    private func scrollToPage(for request: ScrollRequest) -> Bool {
        guard collectionView.numberOfSections > 0 else { return false }
        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        guard numberOfItems > 0 else { return false }
        let idx = ReaderPositioning.scrollAnchorIndex(
            forPageIndex: request.targetPageIndex,
            pageCount: numberOfItems,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout
        )
        let indexPath = IndexPath(row: idx, section: 0)
        collectionView.layoutIfNeeded()
        guard let attr = collectionView.layoutAttributesForItem(at: indexPath) else {
            return false
        }
        activeAnimatedScrollTargetPageId = request.animated ? dataSource.itemIdentifier(for: indexPath) : nil
        if request.animated {
            store.send(.collectionScrollStarted)
        }
        if store.readDirection == ReadDirection.upDown.rawValue {
            collectionView.scrollRectToVisible(attr.frame, animated: request.animated)
        } else {
            collectionView.scrollToItem(at: indexPath, at: scrollPosition(for: request), animated: request.animated)
        }
        if !request.animated {
            DispatchQueue.main.async { [weak self] in
                self?.reportVisiblePageIfNeeded()
            }
        }
        return true
    }
    private func consumePendingScrollRequestIfPossible() {
        guard let scrollRequest = store.scrollRequest else { return }
        guard scrollToPage(for: scrollRequest) else { return }
        store.send(.scrollRequestHandled(scrollRequest.id))
    }
    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            guard !store.pages.isEmpty else { return }
            let pageIds = store.pages.map(\.id)
            guard pageIds != appliedPageIds else { return }
            let snapshotAnchor = currentSnapshotAnchor()
            appliedPageIds = pageIds

            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            snapshot.appendSections([.main])
            snapshot.appendItems(pageIds)
            isApplyingSnapshot = true
            UIView.performWithoutAnimation {
                dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                    guard let self else { return }
                    self.restoreSnapshotAnchor(snapshotAnchor)
                    self.consumePendingScrollRequestIfPossible()
                    self.isApplyingSnapshot = false
                }
                collectionView.layoutIfNeeded()
                restoreSnapshotAnchor(snapshotAnchor)
            }
        }
        observe { [weak self] in
            guard let self else { return }
            guard store.scrollRequest != nil else { return }
            consumePendingScrollRequestIfPossible()
        }
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
        consumePendingScrollRequestIfPossible()
    }

    private func reportVisiblePageIfNeeded() {
        guard !isApplyingSnapshot else { return }
        guard let visibleIndex = currentVisibleItemIndex() else { return }
        let pageIndex = ReaderPositioning.canonicalPageIndex(
            forVisibleIndex: visibleIndex,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout
        )

        guard pageIndex != lastReportedVisiblePageIndex else { return }
        lastReportedVisiblePageIndex = pageIndex
        store.send(.visiblePageChanged(pageIndex))
    }

    private func currentVisibleItemIndex() -> Int? {
        guard collectionView != nil else { return nil }
        let visibleRect = CGRect(
            origin: collectionView.contentOffset,
            size: collectionView.bounds.size
        )
        let visibleAttributes = (
            collectionView.collectionViewLayout.layoutAttributesForElements(in: visibleRect) ?? []
        )
            .filter { $0.representedElementCategory == .cell }
        guard !visibleAttributes.isEmpty else { return nil }

        if store.readDirection == ReadDirection.upDown.rawValue || store.doublePageLayout {
            return visibleAttributes.map(\.indexPath.row).max()
        }

        let viewportCenter = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        return visibleAttributes.min { lhs, rhs in
            distanceSquared(from: lhs.center, to: viewportCenter)
                < distanceSquared(from: rhs.center, to: viewportCenter)
        }?.indexPath.row
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return (deltaX * deltaX) + (deltaY * deltaY)
    }

    private func currentSnapshotAnchor() -> SnapshotAnchor? {
        if let activeAnimatedScrollTargetPageId,
           store.pages.contains(where: { $0.id == activeAnimatedScrollTargetPageId }) {
            return SnapshotAnchor(
                pageId: activeAnimatedScrollTargetPageId,
                offsetFromViewportOrigin: .zero,
                resolvesAnimatedScroll: true
            )
        }

        if let visibleIndex = currentVisibleItemIndex() {
            let indexPath = IndexPath(row: visibleIndex, section: 0)
            guard let pageId = dataSource.itemIdentifier(for: indexPath),
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                return nil
            }

            return SnapshotAnchor(
                pageId: pageId,
                offsetFromViewportOrigin: CGPoint(
                    x: attributes.frame.minX - collectionView.contentOffset.x,
                    y: attributes.frame.minY - collectionView.contentOffset.y
                ),
                resolvesAnimatedScroll: false
            )
        }

        guard appliedPageIds.isEmpty else { return nil }
        let anchorIndex = ReaderPositioning.scrollAnchorIndex(
            forPageIndex: store.currentPageIndex,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout
        )
        guard store.pages.indices.contains(anchorIndex) else { return nil }
        return SnapshotAnchor(
            pageId: store.pages[anchorIndex].id,
            offsetFromViewportOrigin: .zero,
            resolvesAnimatedScroll: false
        )
    }

    private func restoreSnapshotAnchor(_ anchor: SnapshotAnchor?) {
        guard let anchor,
              let pageIndex = store.pages.firstIndex(where: { $0.id == anchor.pageId }) else {
            return
        }

        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(row: pageIndex, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

        let proposedOffset = CGPoint(
            x: attributes.frame.minX - anchor.offsetFromViewportOrigin.x,
            y: attributes.frame.minY - anchor.offsetFromViewportOrigin.y
        )
        collectionView.setContentOffset(clampedContentOffset(proposedOffset), animated: false)
        if anchor.resolvesAnimatedScroll {
            activeAnimatedScrollTargetPageId = nil
        }
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let inset = collectionView.adjustedContentInset
        let minimumX = -inset.left
        let minimumY = -inset.top
        let maximumX = max(minimumX, collectionView.contentSize.width - collectionView.bounds.width + inset.right)
        let maximumY = max(minimumY, collectionView.contentSize.height - collectionView.bounds.height + inset.bottom)

        return CGPoint(
            x: min(max(offset.x, minimumX), maximumX),
            y: min(max(offset.y, minimumY), maximumY)
        )
    }

    // Returns index path representing the start of the current visual page (accounts for double page layout)
    private func currentVisualPageIndexPath() -> IndexPath? {
        guard let visibleIndex = currentVisibleItemIndex() else { return nil }
        return startOfGroupIndexPath(for: IndexPath(row: visibleIndex, section: 0))
    }

    // For double page layout treat a pair of items as one visual page; return left item index path
    private func startOfGroupIndexPath(for indexPath: IndexPath) -> IndexPath {
        guard store.readDirection != ReadDirection.upDown.rawValue,
              store.doublePageLayout else { return indexPath }
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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                switch key.keyCode {
                case .keyboardLeftArrow:
                    handleKeyboardAction(action: store.tapRight)
                case .keyboardRightArrow:
                    handleKeyboardAction(action: store.tapLeft)
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
        handleTapInRegion(region)
    }

    private func handleTapInRegion(_ region: TapRegion) {
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
            store.send(.navigate(.next, source: .tap))
        case PageControl.previous.rawValue:
            store.send(.navigate(.previous, source: .tap))
        case PageControl.navigation.rawValue:
            store.send(.toggleControlUi(nil))
        default:
            // This should not happen
            break
        }
    }

    private func handleKeyboardAction(action: String) {
        switch action {
        case PageControl.next.rawValue:
            store.send(.navigate(.next, source: .keyboard))
        case PageControl.previous.rawValue:
            store.send(.navigate(.previous, source: .keyboard))
        case PageControl.navigation.rawValue:
            store.send(.toggleControlUi(nil))
        default:
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
        pullStatusBackground.isHidden = true
        pullStatusBackground.clipsToBounds = true
        pullStatusBackground.layer.cornerRadius = 24
        pullStatusBackground.layer.cornerCurve = .continuous
        pullStatusBackground.layer.borderWidth = 1
        pullStatusBackground.layer.borderColor = UIColor.separator.withAlphaComponent(0.16).cgColor
        view.addSubview(pullStatusBackground)

        pullIndicatorContainer.clipsToBounds = true
        pullIndicatorContainer.layer.cornerRadius = 18
        pullIndicatorContainer.layer.cornerCurve = .continuous
        pullIndicatorContainer.backgroundColor = UIColor.secondarySystemFill
        pullStatusBackground.contentView.addSubview(pullIndicatorContainer)

        pullArrowView.contentMode = .scaleAspectFit
        pullArrowView.tintColor = .secondaryLabel
        pullArrowView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        pullIndicatorContainer.addSubview(pullArrowView)

        pullStatusLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        pullStatusLabel.adjustsFontForContentSizeCategory = true
        pullStatusLabel.textColor = .label
        pullStatusLabel.textAlignment = .natural
        pullStatusLabel.numberOfLines = 1
        pullStatusLabel.isHidden = true
        pullStatusBackground.contentView.addSubview(pullStatusLabel)

        pullProgressView.trackTintColor = UIColor.separator.withAlphaComponent(0.14)
        pullProgressView.progressTintColor = .systemBlue
        pullProgressView.layer.cornerRadius = 1.5
        pullProgressView.clipsToBounds = true
        pullStatusBackground.contentView.addSubview(pullProgressView)
    }

    private func isAtFirstVisualPage() -> Bool {
        guard !store.pages.isEmpty else { return true }
        if store.readDirection == ReadDirection.upDown.rawValue {
            // For vertical reading rely on scroll position for accuracy; allow small epsilon
            return collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
        }

        return store.currentPageIndex <= ReaderPositioning.firstVisualPageIndex(
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout
        )
    }

    private func isAtLastVisualPage() -> Bool {
        guard !store.pages.isEmpty else { return true }
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
        }

        return store.currentPageIndex >= lastIndex
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
        updatePullViews(overscroll: overscroll, axis: metrics.axis)
    }

    private func layoutPullIndicator(overscroll: CGFloat, axis: NSLayoutConstraint.Axis) {
        guard let edge = pullEdge else { return }
        let iconSize: CGFloat = 36
        let cardHeight: CGFloat = 52
        let horizontalPadding: CGFloat = 12
        let spacing: CGFloat = 10
        let cardWidth = pullCardWidth(
            iconSize: iconSize,
            horizontalPadding: horizontalPadding,
            spacing: spacing
        )
        let progress = min(1, overscroll / pullThreshold)
        let edgeInset = 16 + progress * 14
        pullStatusBackground.frame = pullCardFrame(
            edge: edge,
            axis: axis,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            edgeInset: edgeInset
        )
        pullStatusBackground.layer.cornerRadius = cardHeight / 2
        layoutPullCardContent(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            iconSize: iconSize,
            horizontalPadding: horizontalPadding,
            spacing: spacing
        )
    }

    private func pullCardWidth(iconSize: CGFloat, horizontalPadding: CGFloat, spacing: CGFloat) -> CGFloat {
        let maxWidth = max(min(view.bounds.width - 32, 360), 0)
        pullStatusLabel.sizeToFit()
        let labelAvailableWidth = max(maxWidth - iconSize - spacing - horizontalPadding * 2, 0)
        let labelWidth = min(
            labelAvailableWidth,
            pullStatusLabel.bounds.width
        )
        let minimumWidth = min(172, maxWidth)
        return min(maxWidth, max(minimumWidth, iconSize + spacing + labelWidth + horizontalPadding * 2))
    }

    private func pullCardFrame(
        edge: PullEdge,
        axis: NSLayoutConstraint.Axis,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        edgeInset: CGFloat
    ) -> CGRect {
        if axis == .horizontal {
            let isRTLReading = store.readDirection == ReadDirection.rightLeft.rawValue
            let showOnLeft = (edge == .previous && !isRTLReading) || (edge == .next && isRTLReading)
            let xPosition = showOnLeft ? edgeInset : view.bounds.width - cardWidth - edgeInset
            return CGRect(x: xPosition, y: view.bounds.midY - cardHeight / 2, width: cardWidth, height: cardHeight)
        }

        let safeArea = view.safeAreaInsets
        let yPosition = edge == .previous
            ? safeArea.top + edgeInset
            : view.bounds.height - safeArea.bottom - cardHeight - edgeInset
        return CGRect(x: (view.bounds.width - cardWidth) / 2, y: yPosition, width: cardWidth, height: cardHeight)
    }

    private func layoutPullCardContent(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        iconSize: CGFloat,
        horizontalPadding: CGFloat,
        spacing: CGFloat
    ) {
        pullIndicatorContainer.frame = CGRect(
            x: horizontalPadding,
            y: (cardHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        pullArrowView.frame = pullIndicatorContainer.bounds.insetBy(dx: 8, dy: 8)
        let labelX = horizontalPadding + iconSize + spacing
        pullStatusLabel.frame = CGRect(
            x: labelX,
            y: (cardHeight - pullStatusLabel.font.lineHeight) / 2 - 1,
            width: cardWidth - labelX - horizontalPadding,
            height: pullStatusLabel.font.lineHeight + 2
        )
        pullProgressView.frame = CGRect(
            x: horizontalPadding + 2,
            y: cardHeight - 5,
            width: cardWidth - (horizontalPadding + 2) * 2,
            height: 3
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

    private func updatePullViews(overscroll: CGFloat, axis: NSLayoutConstraint.Axis) {
        guard pullActive, let edge = pullEdge else { return }
        pullIndicatorContainer.isHidden = false
        pullStatusBackground.isHidden = false
        pullStatusLabel.isHidden = false
        let atArchiveBoundary = (edge == .previous && isAtFirstArchive()) || (edge == .next && isAtLastArchive())
        let flipped = !atArchiveBoundary && pullProgress >= 1
        pullArrowView.image = UIImage(systemName: symbolName(for: edge, axis: axis, flipped: flipped))

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
        layoutPullIndicator(overscroll: overscroll, axis: axis)
        updatePullStyle(atArchiveBoundary: atArchiveBoundary, releaseReady: flipped)
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
        pullStatusBackground.transform = CGAffineTransform(
            scaleX: 0.96 + pullProgress * 0.04,
            y: 0.96 + pullProgress * 0.04
        )
    }

    private func updatePullStyle(atArchiveBoundary: Bool, releaseReady: Bool) {
        let tintColor: UIColor = if atArchiveBoundary {
            .tertiaryLabel
        } else if releaseReady {
            .systemBlue
        } else {
            .secondaryLabel
        }
        pullArrowView.tintColor = tintColor
        pullStatusLabel.textColor = atArchiveBoundary ? .secondaryLabel : .label
        pullIndicatorContainer.backgroundColor = tintColor.withAlphaComponent(releaseReady ? 0.18 : 0.10)
        pullStatusBackground.layer.borderColor = tintColor.withAlphaComponent(releaseReady ? 0.34 : 0.14).cgColor
        pullProgressView.progressTintColor = tintColor
        pullProgressView.setProgress(Float(pullProgress), animated: false)
    }

    private func endPullInteraction() {
        pullActive = false
        pullEdge = nil
        pullProgress = 0
        lastReportedProgressBucket = -1
        pullIndicatorContainer.isHidden = true
        pullStatusLabel.isHidden = true
        pullStatusBackground.isHidden = true
        pullStatusBackground.transform = .identity
        pullProgressView.setProgress(0, animated: false)
        pullThresholdCrossedHapticsFired = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        guard let metrics = currentScrollMetrics() else { return }
        updatePullState(scroll: metrics)
        if store.readDirection == ReadDirection.upDown.rawValue {
            reportVisiblePageIfNeeded()
        }
    }

    func resetCollectionView() {
        let snapshot = NSDiffableDataSourceSnapshot<
            Section, String
        >()
        appliedPageIds = []
        activeAnimatedScrollTargetPageId = nil
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.setContentOffset(.zero, animated: false)
        lastReportedVisiblePageIndex = nil
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        activeAnimatedScrollTargetPageId = nil
        store.send(.collectionScrollStarted)
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
            store.send(.collectionScrollEnded)
            reportVisiblePageIfNeeded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        store.send(.collectionScrollEnded)
        reportVisiblePageIfNeeded()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        store.send(.collectionScrollEnded)
        reportVisiblePageIfNeeded()
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
            if let pageStore = pageStore(at: path) {
                if pageStore.pageMode == .loading {
                    Task {
                        await pageStore.send(.load(false)).finish()
                    }
                }
            }
        }
    }
}
