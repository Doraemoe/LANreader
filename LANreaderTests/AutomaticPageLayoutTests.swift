import ComposableArchitecture
import XCTest
@testable import LANreader

final class AutomaticPageLayoutTests: XCTestCase {
    func testAutomaticLayoutUsesFittedPageWidthAndHysteresis() {
        for (size, enabled) in [
            (CGSize(width: 382, height: 644), false),
            (CGSize(width: 466, height: 562), true),
            (CGSize(width: 440, height: 900), false),
            (CGSize(width: 896, height: 414), true),
            (CGSize(width: 896, height: 280), false),
            (CGSize(width: 834, height: 1_194), true)
        ] {
            XCTAssertEqual(
                ReaderPageLayout.automaticDoublePageLayout(readerSize: size, currentlyEnabled: false),
                enabled, "\(size)"
            )
        }
        let betweenThresholds = CGSize(width: 450, height: 700)
        XCTAssertFalse(ReaderPageLayout.automaticDoublePageLayout(
            readerSize: betweenThresholds, currentlyEnabled: false
        ))
        XCTAssertTrue(ReaderPageLayout.automaticDoublePageLayout(
            readerSize: betweenThresholds, currentlyEnabled: true
        ))
        XCTAssertFalse(ReaderPageLayout.automaticDoublePageLayout(
            readerSize: CGSize(width: 440, height: 700), currentlyEnabled: true
        ))
    }

    @MainActor
    func testExistingPreferencesStayManualUntilAutomaticIsSelected() {
        for enabled in [false, true] {
            let suite = "AutomaticPageLayoutTests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(enabled, forKey: SettingsKey.doublePageLayout)
            let state = withDependencies {
                $0.defaultAppStorage = defaults
            } operation: {
                ArchiveReaderFeature.State(currentArchiveId: "fixture", allArchives: [])
            }
            XCTAssertEqual(state.doublePageLayout, enabled)
            XCTAssertEqual(state.pageLayoutMode, enabled ? .double : .single)
            XCTAssertFalse(state.automaticPageLayout)
        }
    }

    @MainActor
    func testSettingsAutomaticPreservesManualPreferenceAndSplitSetting() async {
        let state = ReadSettingsFeature.State()
        state.$doublePageLayout = Shared(value: true)
        state.$automaticPageLayout = Shared(value: false)
        state.$splitWideImage = Shared(value: false)
        let store = TestStore(initialState: state) { ReadSettingsFeature() }
        await store.send(.pageLayoutModeChanged(.automatic)) {
            $0.$automaticPageLayout.withLock { $0 = true }
        }
        await store.send(.splitWideImageChanged(true)) {
            $0.$splitWideImage.withLock { $0 = true }
            $0.$doublePageLayout.withLock { $0 = false }
        }
        XCTAssertTrue(store.state.automaticPageLayout)
        await store.send(.pageLayoutModeChanged(.double))
    }

    @MainActor
    func testAutomaticRoundTripPreservesPageAndPreferencesInBothDirections() async {
        for direction in [ReadDirection.leftRight, .rightLeft] {
            let store = makeAutomaticReaderStore(direction: direction)
            store.send(.readerSizeChanged(CGSize(width: 466, height: 562)))
            await Task.yield()
            XCTAssertTrue(store.doublePageLayout)
            XCTAssertEqual(store.scrollRequest?.targetPageIndex, 14)
            XCTAssertEqual(store.spreadPairingOffset, 1)
            store.send(.visiblePageChanged(14))
            store.send(.scrollRequestHandled(store.scrollRequest!.id))

            store.send(.readerSizeChanged(CGSize(width: 382, height: 644)))
            await Task.yield()
            XCTAssertFalse(store.doublePageLayout)
            XCTAssertEqual(store.scrollRequest?.targetPageIndex, 13)
            XCTAssertTrue(store.automaticPageLayout)
            XCTAssertFalse(store.manualDoublePageLayout)
        }
    }

    @MainActor
    func testAutomaticPreservesPendingInitialRestore() async {
        let store = makeAutomaticReaderStore()
        store.send(.requestJump(19, source: .initialRestore))
        store.send(.readerSizeChanged(CGSize(width: 466, height: 562)))
        await Task.yield()
        XCTAssertEqual(store.scrollRequest?.targetPageIndex, 20)
        XCTAssertEqual(store.spreadPairingOffset, 1)
    }

    @MainActor
    func testAutomaticKeepsVerticalAndSplitReadersSingle() async {
        for (direction, split) in [(ReadDirection.upDown, false), (.leftRight, true)] {
            let store = makeAutomaticReaderStore(direction: direction, split: split)
            store.send(.readerSizeChanged(CGSize(width: 1_194, height: 834)))
            await Task.yield()
            XCTAssertFalse(store.doublePageLayout)
            XCTAssertEqual(store.scrollRequest?.source, .initialRestore)
            XCTAssertEqual(store.splitImage, split)
            XCTAssertEqual(store.resolvedReadDirection, direction)
            XCTAssertTrue(store.automaticPageLayout)
        }
    }

    @MainActor
    func testManualSelectionOverridesAutomaticUntilItIsSelectedAgain() async {
        let store = makeAutomaticReaderStore()
        store.send(.readerSizeChanged(CGSize(width: 466, height: 562)))
        await Task.yield()
        store.send(.pageLayoutModeChanged(.single))
        await Task.yield()
        store.send(.readerSizeChanged(CGSize(width: 1_194, height: 834)))
        XCTAssertFalse(store.doublePageLayout)
        XCTAssertFalse(store.automaticPageLayout)
        store.send(.pageLayoutModeChanged(.automatic))
        await Task.yield()
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertTrue(store.automaticPageLayout)
        store.send(.pageLayoutModeChanged(.double))
        store.send(.readerSizeChanged(CGSize(width: 382, height: 644)))
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertFalse(store.automaticPageLayout)
        XCTAssertTrue(store.manualDoublePageLayout)
    }

    @MainActor
    func testAutomaticUIKitResizeRoundTripsKeepThePage() async {
        for direction in [ReadDirection.leftRight, .rightLeft] {
            let store = makeAutomaticReaderStore(direction: direction)
            let controller = UIPageCollectionController(store: store)
            controller.loadViewIfNeeded()
            for _ in 0..<3 {
                await resizeReader(controller, to: CGSize(width: 382, height: 644))
                XCTAssertFalse(store.doublePageLayout)
                XCTAssertEqual(store.currentPageIndex, 13)
                await resizeReader(controller, to: CGSize(width: 466, height: 562))
                XCTAssertTrue(store.doublePageLayout)
                XCTAssertEqual(store.currentPageIndex, 14)
                XCTAssertEqual(controller.collectionView.contentOffset.x, 7 * 466, accuracy: 1)
            }
            await resizeReader(controller, to: CGSize(width: 382, height: 644))
            XCTAssertEqual(store.currentPageIndex, 13)
            XCTAssertEqual(controller.collectionView.contentOffset.x, 13 * 382, accuracy: 1)
            XCTAssertNil(store.scrollRequest)
        }
    }

    @MainActor
    func testAutomaticRemembersSizeBeforePagesArrive() async {
        let store = makeAutomaticReaderStore(archiveId: "TANK_fixture", pageCount: 0)
        store.send(.readerSizeChanged(CGSize(width: 466, height: 562)))
        XCTAssertFalse(store.doublePageLayout)
        store.send(.finishExtracting((1...25).map {
            ReaderExtractedPage(archiveId: "source", path: "/fixture/\($0).jpg", archivePageNumber: $0)
        }, nil))
        store.send(.readerSizeChanged(store.readerSize))
        await Task.yield()
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertEqual(store.pages[13].sourceArchiveId, "source")
        XCTAssertEqual(store.pages[13].sourcePageNumber, 14)
    }

    @MainActor
    func testAutomaticUIKitKeepsCachedTankoubonSourceIdentity() async {
        let store = makeAutomaticReaderStore(archiveId: "TANK_fixture")
        let controller = UIPageCollectionController(store: store)
        controller.loadViewIfNeeded()
        await resizeReader(controller, to: CGSize(width: 466, height: 562))
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertTrue(store.cached)
        XCTAssertEqual(store.pages[13].sourceArchiveId, "source")
        XCTAssertEqual(store.pages[13].sourcePageNumber, 14)
        await resizeReader(controller, to: CGSize(width: 382, height: 644))
        XCTAssertEqual(store.pages[13].sourceArchiveId, "source")
        XCTAssertEqual(store.currentPageIndex, 13)
    }

    @MainActor
    func testAutomaticUIKitReevaluatesSharedPreferenceWithoutResizing() async {
        let store = makeAutomaticReaderStore()
        store.$automaticPageLayout.withLock { $0 = false }
        let controller = UIPageCollectionController(store: store)
        controller.loadViewIfNeeded()
        await resizeReader(controller, to: CGSize(width: 466, height: 562))
        XCTAssertFalse(store.doublePageLayout)
        store.$automaticPageLayout.withLock { $0 = true }
        await resizeReader(controller, to: CGSize(width: 466, height: 562))
        XCTAssertTrue(store.doublePageLayout)
        store.$automaticPageLayout.withLock { $0 = false }
        await resizeReader(controller, to: CGSize(width: 466, height: 562))
        XCTAssertFalse(store.doublePageLayout)
    }

    @MainActor
    func testAutomaticUIKitResizeEndsInterruptedScrolling() async {
        let store = makeAutomaticReaderStore()
        let controller = UIPageCollectionController(store: store)
        controller.loadViewIfNeeded()
        await resizeReader(controller, to: CGSize(width: 382, height: 644))
        controller.scrollViewWillBeginDragging(controller.collectionView)
        XCTAssertTrue(store.collectionScrolling)
        await resizeReader(controller, to: CGSize(width: 466, height: 562))
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertFalse(store.collectionScrolling)
        XCTAssertEqual(store.currentPageIndex, 14)
    }

    @MainActor
    func testAutomaticUIKitHandlesFinalAndSinglePages() async {
        for count in [1, 2, 25, 26] {
            let store = makeAutomaticReaderStore(pageCount: count)
            let controller = UIPageCollectionController(store: store)
            controller.loadViewIfNeeded()
            await resizeReader(controller, to: CGSize(width: 382, height: 644))
            store.send(.requestJump(count - 1, source: .slider))
            await resizeReader(controller, to: CGSize(width: 382, height: 644))
            await resizeReader(controller, to: CGSize(width: 466, height: 562))
            XCTAssertEqual(store.doublePageLayout, count > 1)
            XCTAssertEqual(store.currentPageIndex, count - 1)
            await resizeReader(controller, to: CGSize(width: 382, height: 644))
            XCTAssertEqual(store.currentPageIndex, count - 1)
            XCTAssertNil(store.scrollRequest)
        }
    }

    @MainActor
    func testAutomaticUIKitIgnoresTemporaryReaderHeightChanges() async {
        let store = makeAutomaticReaderStore()
        let controller = UIPageCollectionController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 562))
        let parent = UIViewController()
        window.rootViewController = parent
        parent.addChild(controller)
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)
        window.isHidden = false
        defer { window.isHidden = true }
        XCTAssertNotNil(controller.view.window)
        await resizeReader(controller, to: CGSize(width: 466, height: 400))
        XCTAssertTrue(store.doublePageLayout)
        await resizeReader(controller, to: CGSize(width: 466, height: 280))
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertEqual(store.currentPageIndex, 14)
        _ = window
    }
}

@MainActor
private func makeAutomaticReaderStore(
    direction: ReadDirection = .leftRight,
    split: Bool = false,
    archiveId: String = "automatic-layout-fixture",
    pageCount: Int = 25
) -> StoreOf<ArchiveReaderFeature> {
    var state = ArchiveReaderFeature.State(currentArchiveId: archiveId, allArchives: [], cached: true)
    state.$readDirection = SharedReader(value: direction.rawValue)
    state.$splitImage = SharedReader(value: split)
    state.$manualDoublePageLayout = Shared(value: false)
    state.$automaticPageLayout = Shared(value: true)
    state.doublePageLayout = false
    state.currentPageIndex = pageCount > 13 ? 13 : 0
    if pageCount > 0 {
        state.scrollRequest = ScrollRequest(
            targetPageIndex: state.currentPageIndex, source: .initialRestore, animated: false
        )
    }
    state.pages = IdentifiedArray(uniqueElements: (0..<pageCount).map { index in
        var page = PageFeature.State(
            archiveId: archiveId, pageId: "\(index + 1)", pageNumber: index + 1,
            sourceArchiveId: "source", sourcePageNumber: index + 1, pageMode: .normal, cached: true
        )
        page.imageLoaded = true
        return page
    })
    return Store(initialState: state) { ArchiveReaderFeature() } withDependencies: {
        $0.continuousClock = ImmediateClock()
        $0.uuid = .incrementing
    }
}

@MainActor
private func resizeReader(_ controller: UIPageCollectionController, to size: CGSize) async {
    controller.view.frame = CGRect(origin: .zero, size: size)
    controller.view.setNeedsLayout()
    for _ in 0..<8 {
        controller.view.layoutIfNeeded()
        try? await Task<Never, Never>.sleep(for: .milliseconds(10))
    }
}
