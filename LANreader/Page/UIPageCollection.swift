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

// swiftlint:disable type_body_length
class UIPageCollectionController: UIViewController, UICollectionViewDelegate {
    let store: StoreOf<ArchiveReaderFeature>
    var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Section, ReaderCollectionItem>!
    private var lastReportedVisiblePageIndex: Int?
    private var appliedCollectionItems: [ReaderCollectionItem] = []
    private var appliedPageIds: [String] {
        appliedCollectionItems.compactMap {
            guard case let .page(id) = $0 else { return nil }
            return id
        }
    }
    private var appliedDoublePageLayout: Bool?
    private var appliedAspectRatios: [Double] = []
    private var isApplyingSnapshot = false
    private var snapshotGeneration = 0
    private var activeAnimatedScrollTargetPageId: String?

    private struct SnapshotAnchor {
        let pageId: String
        let offsetFromViewportOrigin: CGPoint
        let resolvesAnimatedScroll: Bool
    }

    private let pullNavigationOverlay = ReaderPullNavigationOverlay()
    private var wasInNavigationStack = false

    init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeLayout() -> UICollectionViewLayout {
        ReaderCollectionLayoutBuilder.makeLayout(
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout
        ) { [weak self] in
            self?.reportVisiblePageIfNeeded()
        }
    }

    private func setupLayout() {
        appliedDoublePageLayout = store.doublePageLayout
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        if store.readDirection != ReadDirection.upDown.rawValue {
            collectionView.showsHorizontalScrollIndicator = false
            collectionView.isPagingEnabled = true
        }
        view.addSubview(collectionView)
    }

    private func applyDoublePageLayoutChange() {
        let snapshotWasInFlight = isApplyingSnapshot
        isApplyingSnapshot = true
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.layoutIfNeeded()
        isApplyingSnapshot = snapshotWasInFlight
        if store.collectionScrolling {
            activeAnimatedScrollTargetPageId = nil
            store.send(.collectionScrollEnded)
        }
        lastReportedVisiblePageIndex = nil
        if appliedCollectionItems == collectionItems() {
            consumePendingScrollRequestIfPossible()
        }
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
        let pageCellRegistration = UICollectionView
            .CellRegistration<UIPageCell, String> { [weak self] cell, _, pageId in
                guard let self, let pageStore = self.pageStore(id: pageId) else { return }
                cell.setAllowsStampCreation(self.store.canUseStamps)
                cell.configure(
                    with: pageStore,
                    fitPageWidth: self.usesFitPageWidth,
                    showsStamps: self.store.shouldShowStamps,
                    onCreateStamp: { [weak self] position in
                        guard let self, let page = self.store.pages[id: pageId] else { return }
                        let stampPage = ReaderStampPage(page: page, cached: self.store.cached || page.cached)
                        self.store.send(.stamp(.creationRequested(page: stampPage, position: position)))
                    },
                    onEditStamp: { [weak self] stamp in
                        guard let self, let page = self.store.pages[id: pageId] else { return }
                        let stampPage = ReaderStampPage(page: page, cached: self.store.cached || page.cached)
                        self.store.send(.stamp(.editingRequested(page: stampPage, stamp: stamp)))
                    }
                )
            }
        let placeholderCellRegistration = UICollectionView
            .CellRegistration<UICollectionViewCell, ReaderCollectionItem> { cell, _, _ in
                cell.contentView.backgroundColor = .clear
            }

        dataSource = UICollectionViewDiffableDataSource<Section, ReaderCollectionItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .spreadPlaceholder:
                return collectionView.dequeueConfiguredReusableCell(
                    using: placeholderCellRegistration,
                    for: indexPath,
                    item: item
                )
            case let .page(pageId):
                return collectionView.dequeueConfiguredReusableCell(
                    using: pageCellRegistration,
                    for: indexPath,
                    item: pageId
                )
            }
        }
    }

    private func pageStore(id pageId: String) -> StoreOf<PageFeature>? {
        Array(store.scope(\.pages, action: \.page)).first { $0.id == pageId }
    }

    private func pageStore(at indexPath: IndexPath) -> StoreOf<PageFeature>? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .page(pageId) = item else { return nil }
        return pageStore(id: pageId)
    }

    private func preloadFollowingPages(after pageIndex: Int) {
        guard let nextPageIndex = ReaderPositioning.adjacentPageIndex(
            from: pageIndex,
            direction: .next,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadOffset: store.spreadPairingOffset
        ) else { return }

        let firstIndex = ReaderPositioning.scrollAnchorIndex(
            forPageIndex: nextPageIndex,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadOffset: store.spreadPairingOffset
        )
        let pageCount = resolvedReadDirection != .upDown && store.doublePageLayout ? 2 : 1
        let lastIndex = min(firstIndex + pageCount, store.pages.count)

        for index in firstIndex..<lastIndex where store.pages[index].pageMode == .loading {
            let pageId = store.pages[index].id
            Task { [weak self] in
                await self?.pageStore(id: pageId)?.send(.load(false)).finish()
            }
        }
    }

    private var resolvedReadDirection: ReadDirection {
        ReadDirection(rawValue: store.readDirection) ?? .leftRight
    }
    private var usesFitPageWidth: Bool {
        resolvedReadDirection != .upDown && store.fitPageWidth
    }

    // MARK: - Vertical Item Sizing

    private func availableItemWidth() -> CGFloat {
        guard collectionView != nil else { return 0 }
        let insets = collectionView.adjustedContentInset
        return max(0, collectionView.bounds.width - insets.left - insets.right)
    }

    /// Aspect ratio a page renders at. Falls back to the archive's measured median while the page's
    /// own dimensions are still unknown, which keeps the first layout close enough that no
    /// correction is usually needed.
    private func effectiveAspectRatio(for page: PageFeature.State) -> Double {
        ReaderPageLayout.validatedAspectRatio(page.displayAspectRatio ?? store.estimatedPageAspectRatio)
    }

    private func currentAspectRatios() -> [Double] {
        store.pages.map { effectiveAspectRatio(for: $0) }
    }

    /// Applies a corrected page height without moving anything the reader can currently see.
    private func refreshVerticalItemHeights() {
        guard resolvedReadDirection == .upDown else { return }
        guard collectionView != nil, dataSource != nil else { return }
        guard !isApplyingSnapshot else { return }

        let anchor = currentSnapshotAnchor()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        restoreSnapshotAnchor(anchor)
    }

    private func scrollToPage(for request: ScrollRequest) -> Bool {
        guard collectionView.numberOfSections > 0 else { return false }
        guard !store.pages.isEmpty else { return false }
        guard let indexPath = indexPath(forPageIndex: request.targetPageIndex) else { return false }
        collectionView.layoutIfNeeded()
        guard collectionView.layoutAttributesForItem(at: indexPath) != nil else {
            return false
        }
        if request.animated,
           let item = dataSource.itemIdentifier(for: indexPath),
           case let .page(pageId) = item {
            activeAnimatedScrollTargetPageId = pageId
        } else {
            activeAnimatedScrollTargetPageId = nil
        }
        if request.animated {
            store.send(.collectionScrollStarted)
        }
        if store.readDirection == ReadDirection.upDown.rawValue {
            // Pages are now sized to their real height, so a minimal "make visible" scroll could
            // leave a short page parked at the bottom of the viewport. Always align it to the top.
            collectionView.scrollToItem(at: indexPath, at: .top, animated: request.animated)
        } else {
            collectionView.scrollToItem(
                at: indexPath,
                at: ReaderCollectionLayoutBuilder.scrollPosition(for: request.source),
                animated: request.animated
            )
        }
        preloadFollowingPages(after: request.targetPageIndex)
        if !request.animated {
            DispatchQueue.main.async { [weak self] in
                self?.reportVisiblePageIfNeeded()
            }
        }
        return true
    }
    private func observeLayoutPreferences() {
        observe { [weak self] in
            guard let self else { return }
            let key = LayoutPreferenceKey(
                manualDoublePageLayout: store.manualDoublePageLayout,
                automaticPageLayout: store.automaticPageLayout,
                readDirection: store.readDirection,
                splitImage: store.splitImage,
                pageCount: store.pages.count
            )
            guard key != lastLayoutPreferenceKey else { return }
            lastLayoutPreferenceKey = key
            lastReportedReaderSize = nil
            view.setNeedsLayout()
        }
    }

    private func setupObserve() {
        observe { [weak self] in
            guard let self else { return }
            let doublePageLayout = store.doublePageLayout
            guard appliedDoublePageLayout != doublePageLayout else { return }
            appliedDoublePageLayout = doublePageLayout
            guard resolvedReadDirection != .upDown else { return }
            applyDoublePageLayoutChange()
        }
        observe { [weak self] in
            guard let self else { return }
            guard !store.pages.isEmpty else { return }
            let items = collectionItems()
            guard items != appliedCollectionItems else { return }
            applyPageSnapshot(items: items)
        }
        observe { [weak self] in
            guard let self else { return }
            let aspectRatios = currentAspectRatios()
            let pageIds = store.pages.map(\.id)
            guard aspectRatios != appliedAspectRatios else { return }
            appliedAspectRatios = aspectRatios
            // The snapshot observer lays out fresh page sets, so only correct in-place changes here.
            guard pageIds == appliedPageIds else { return }
            refreshVerticalItemHeights()
        }
        observe { [weak self] in
            guard let self else { return }
            guard store.scrollRequest != nil else { return }
            consumePendingScrollRequestIfPossible()
        }
        observe { [weak self] in
            guard let self else { return }
            let fitPageWidth = usesFitPageWidth
            collectionView.visibleCells
                .compactMap { $0 as? UIPageCell }
                .forEach { $0.setFitPageWidth(fitPageWidth) }
        }
        observe { [weak self] in
            guard let self else { return }
            let allowsStampCreation = store.canUseStamps
            let showsStamps = store.shouldShowStamps
            collectionView.visibleCells
                .compactMap { $0 as? UIPageCell }
                .forEach {
                    $0.setAllowsStampCreation(allowsStampCreation)
                    $0.setShowsStamps(showsStamps)
                }
        }
    }

    private func applyPageSnapshot(items: [ReaderCollectionItem]) {
        let snapshotAnchor = currentSnapshotAnchor()
        appliedCollectionItems = items
        appliedAspectRatios = currentAspectRatios()
        snapshotGeneration += 1
        let generation = snapshotGeneration

        var snapshot = NSDiffableDataSourceSnapshot<Section, ReaderCollectionItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items)
        isApplyingSnapshot = true
        UIView.performWithoutAnimation {
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                guard self.snapshotGeneration == generation else { return }
                self.restoreSnapshotAnchor(snapshotAnchor)
                self.isApplyingSnapshot = false
                self.consumePendingScrollRequestIfPossible()
            }
            collectionView.layoutIfNeeded()
            restoreSnapshotAnchor(snapshotAnchor)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupCollectionView()
        setupCell()
        setupObserve()
        observeLayoutPreferences()
        setupGesture()

        collectionView.delegate = self
        collectionView.prefetchDataSource = self

        pullNavigationOverlay.install(in: view)

        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    private struct LayoutPreferenceKey: Equatable {
        let manualDoublePageLayout: Bool
        let automaticPageLayout: Bool
        let readDirection: String
        let splitImage: Bool
        let pageCount: Int
    }

    // MARK: - Rotation / Size Change Handling
    private var lastLayoutWidth: CGFloat?
    private var lastReportedReaderSize: CGSize?
    private var lastLayoutPreferenceKey: LayoutPreferenceKey?
    private var resizeRestoreTarget: ResizeRestoreTarget?

    private struct ResizeRestoreTarget {
        let pageIndex: Int
        let progressThroughPage: CGFloat
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard collectionView != nil else { return }
        resizeRestoreTarget = resizeRestoreTarget ?? currentResizeRestoreTarget()
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: { _ in
            self.restorePageAfterResize()
        })
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Width changes without a rotation, such as unfolding or a sidebar appearing, keep the old
        // content offset while every page changes size, so remember the page before layout moves it.
        let width = view.bounds.width
        if lastLayoutWidth != width, !appliedCollectionItems.isEmpty {
            resizeRestoreTarget = resizeRestoreTarget ?? currentResizeRestoreTarget()
            collectionView.collectionViewLayout.invalidateLayout()
        }
        lastLayoutWidth = width
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restorePageAfterResize()
        collectionView.layoutIfNeeded()
        // Window height stays stable when the reader's navigation controls appear or disappear.
        let height = view.window.map {
            $0.bounds.height - $0.safeAreaInsets.top - $0.safeAreaInsets.bottom
        } ?? view.bounds.height
        let readerSize = CGSize(width: availableItemWidth(), height: height)
        if !isDetachedFromNavigationStack, lastReportedReaderSize != readerSize {
            lastReportedReaderSize = readerSize
            store.send(.readerSizeChanged(readerSize))
        }
        consumePendingScrollRequestIfPossible()
    }

    private var isDetachedFromNavigationStack: Bool {
        guard let navigationController else { return wasInNavigationStack }
        wasInNavigationStack = true
        var current: UIViewController? = self
        while let controller = current {
            if navigationController.viewControllers.contains(where: { $0 === controller }) {
                return false
            }
            current = controller.parent
        }
        return true
    }

    // Vertical mode reports the lowest visible page, so keep the top page and how far it was read instead.
    private func currentResizeRestoreTarget() -> ResizeRestoreTarget {
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visibleTop = visibleRect.minY + collectionView.adjustedContentInset.top
        guard store.readDirection == ReadDirection.upDown.rawValue,
              let attributes = collectionView.collectionViewLayout.layoutAttributesForElements(in: visibleRect)?
                .filter({ $0.representedElementCategory == .cell && $0.frame.maxY > visibleTop })
                .min(by: { $0.indexPath.row < $1.indexPath.row }),
              attributes.frame.height > 0,
              let pageIndex = pageIndex(atCollectionItemIndex: attributes.indexPath.row) else {
            let animatedTarget = activeAnimatedScrollTargetPageId.flatMap { store.pages.index(id: $0) }
            return ResizeRestoreTarget(
                pageIndex: store.scrollRequest?.targetPageIndex ?? animatedTarget ?? store.currentPageIndex,
                progressThroughPage: 0
            )
        }
        let progress = (visibleTop - attributes.frame.minY) / attributes.frame.height
        return ResizeRestoreTarget(pageIndex: pageIndex, progressThroughPage: min(max(progress, 0), 1))
    }

    private func restorePageAfterResize() {
        guard let target = resizeRestoreTarget else { return }
        collectionView.layoutIfNeeded()
        let indexPath = indexPath(forPageIndex: target.pageIndex)
        resnap(to: indexPath)
        if target.progressThroughPage > 0, let indexPath,
           let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
            let top = attributes.frame.minY + attributes.frame.height * target.progressThroughPage
            let offsetY = top - collectionView.adjustedContentInset.top
            collectionView.setContentOffset(
                clampedContentOffset(CGPoint(x: collectionView.contentOffset.x, y: offsetY)), animated: false
            )
        }
        lastReportedVisiblePageIndex = store.currentPageIndex
        resizeRestoreTarget = nil
        reportVisiblePageIfNeeded()
        if store.collectionScrolling {
            activeAnimatedScrollTargetPageId = nil
            store.send(.collectionScrollEnded)
        }
    }

    private func indexPath(forPageIndex pageIndex: Int) -> IndexPath? {
        let anchorIndex = ReaderPositioning.scrollAnchorIndex(
            forPageIndex: pageIndex,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadOffset: store.spreadPairingOffset
        )
        guard store.pages.indices.contains(anchorIndex),
              let pageIndexPath = dataSource.indexPath(for: .page(store.pages[anchorIndex].id)) else {
            return nil
        }
        return ReaderCollectionLayoutBuilder.startOfGroupIndexPath(
            for: pageIndexPath,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout
        )
    }

    private func reportVisiblePageIfNeeded() {
        // A freshly created collection still has provisional geometry until its first parent layout.
        guard lastLayoutWidth != nil, !isApplyingSnapshot, resizeRestoreTarget == nil else { return }
        guard let visibleItemIndex = currentVisibleItemIndex(),
              let visiblePageIndex = pageIndex(atCollectionItemIndex: visibleItemIndex) else { return }
        let pageIndex = ReaderPositioning.canonicalPageIndex(
            forVisibleIndex: visiblePageIndex,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadOffset: store.spreadPairingOffset
        )

        guard pageIndex != lastReportedVisiblePageIndex else { return }
        lastReportedVisiblePageIndex = pageIndex
        store.send(.visiblePageChanged(pageIndex))
    }

    private func pageIndex(atCollectionItemIndex itemIndex: Int) -> Int? {
        let indexPath = IndexPath(row: itemIndex, section: 0)
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .page(pageId) = item else { return nil }
        return store.pages.index(id: pageId)
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
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  case let .page(pageId) = item,
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

        guard appliedCollectionItems.isEmpty else { return nil }
        let anchorIndex = ReaderPositioning.scrollAnchorIndex(
            forPageIndex: store.currentPageIndex,
            pageCount: store.pages.count,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadOffset: store.spreadPairingOffset
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
              let indexPath = dataSource.indexPath(for: .page(anchor.pageId)) else {
            return
        }

        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

        let proposedOffset = CGPoint(
            x: attributes.frame.minX - anchor.offsetFromViewportOrigin.x,
            y: attributes.frame.minY - anchor.offsetFromViewportOrigin.y
        )
        let targetOffset = clampedContentOffset(proposedOffset)
        // Writing an unchanged offset would cancel an in-flight deceleration, so only move when needed.
        if abs(targetOffset.x - collectionView.contentOffset.x) > 0.5
            || abs(targetOffset.y - collectionView.contentOffset.y) > 0.5 {
            collectionView.setContentOffset(targetOffset, animated: false)
        }
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

    private func resnap(to indexPath: IndexPath?) {
        guard collectionView != nil else { return }
        guard let indexPath else { return }
        let numberOfItems = collectionView.numberOfItems(inSection: indexPath.section)
        guard indexPath.row < numberOfItems else { return }
        // Scroll without animation to avoid intermediate half pages
        if store.readDirection == ReadDirection.upDown.rawValue {
            // Item heights are derived from the item width, so a width change invalidates the
            // current offset. Put the page the reader was on back at the top of the viewport.
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        } else {
            collectionView.scrollToItem(at: indexPath, at: .left, animated: false)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key, !handleKeyPress(key.keyCode) {
                super.pressesBegan(presses, with: event)
            }
        }
    }

    enum Section {
        case main
    }
}
// swiftlint:enable type_body_length

private extension UIPageCollectionController {
    func consumePendingScrollRequestIfPossible() {
        guard let scrollRequest = store.scrollRequest else { return }
        guard !isApplyingSnapshot else { return }
        guard appliedDoublePageLayout == store.doublePageLayout else { return }
        guard appliedCollectionItems == collectionItems() else { return }
        guard dataSource.snapshot().itemIdentifiers == appliedCollectionItems else { return }
        guard scrollToPage(for: scrollRequest) else { return }
        store.send(.scrollRequestHandled(scrollRequest.id))
    }

    func collectionItems() -> [ReaderCollectionItem] {
        ReaderCollectionLayoutBuilder.collectionItems(
            pageIds: store.pages.map(\.id),
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadPairingOffset: store.spreadPairingOffset
        )
    }

    var pullNavigationContext: ReaderPullNavigationContext {
        ReaderPullNavigationContext(
            pageCount: store.pages.count,
            currentPageIndex: store.currentPageIndex,
            readDirection: resolvedReadDirection,
            doublePageLayout: store.doublePageLayout,
            spreadPairingOffset: store.spreadPairingOffset,
            atFirstArchive: store.allArchives.first?.wrappedValue.id == store.currentArchiveId,
            atLastArchive: store.allArchives.last?.wrappedValue.id == store.currentArchiveId
        )
    }
}

extension UIPageCollectionController {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        pullNavigationOverlay.update(for: scrollView, in: view, context: pullNavigationContext)
        if store.readDirection == ReadDirection.upDown.rawValue {
            reportVisiblePageIfNeeded()
        }
    }

    func resetCollectionView() {
        let snapshot = NSDiffableDataSourceSnapshot<
            Section, ReaderCollectionItem
        >()
        appliedCollectionItems = []
        appliedAspectRatios = []
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
        if let triggeredEdge = pullNavigationOverlay.completeInteraction(context: pullNavigationContext) {
            resetCollectionView()
            switch triggeredEdge {
            case .previous:
                store.send(.loadPreviousArchive)
            case .next:
                store.send(.loadNextArchive)
            }
            let successGen = UINotificationFeedbackGenerator()
            successGen.prepare()
            successGen.notificationOccurred(.success)
        }

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

extension UIPageCollectionController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        guard !isDetachedFromNavigationStack else { return }
        if let pageCell = cell as? UIPageCell {
            Task { [weak self, weak pageCell] in
                guard let self, !self.isDetachedFromNavigationStack else { return }
                _ = pageCell?.store?.send(.load(false))
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = availableItemWidth()
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .page(pageId) = item,
              let page = store.pages[id: pageId] else {
            return CGSize(
                width: width,
                height: ReaderPageLayout.itemHeight(width: width, aspectRatio: store.estimatedPageAspectRatio)
            )
        }
        return CGSize(
            width: width,
            height: ReaderPageLayout.itemHeight(width: width, aspectRatio: effectiveAspectRatio(for: page))
        )
    }
}

extension UIPageCollectionController: UICollectionViewDataSourcePrefetching {
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
