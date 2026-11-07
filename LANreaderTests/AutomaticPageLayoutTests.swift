import ComposableArchitecture
import XCTest
@testable import LANreader

final class AutomaticPageLayoutTests: LANreaderTestCase {
    func testAutomaticLayoutUsesFittedPageWidthAndHysteresis() {
        for (size, enabled) in [
            (CGSize(width: 382, height: 644), false),
            (CGSize(width: 466, height: 562), false),
            (CGSize(width: 562, height: 466), true),
            (CGSize(width: 734, height: 372), true),
            (CGSize(width: 440, height: 900), false),
            (CGSize(width: 896, height: 414), true),
            (CGSize(width: 896, height: 280), false),
            (CGSize(width: 834, height: 1_150), false),
            (CGSize(width: 1_032, height: 1_332), false),
            (CGSize(width: 1_194, height: 790), true),
            (CGSize(width: 590, height: 790), false),
            (CGSize(width: 800, height: 790), false)
        ] {
            XCTAssertEqual(
                ReaderPageLayout.automaticDoublePageLayout(readerSize: size, currentlyEnabled: false),
                enabled, "\(size)"
            )
        }
        for betweenThresholds in [CGSize(width: 450, height: 330), CGSize(width: 800, height: 800)] {
            XCTAssertFalse(ReaderPageLayout.automaticDoublePageLayout(
                readerSize: betweenThresholds, currentlyEnabled: false
            ), "\(betweenThresholds)")
            XCTAssertTrue(ReaderPageLayout.automaticDoublePageLayout(
                readerSize: betweenThresholds, currentlyEnabled: true
            ), "\(betweenThresholds)")
        }
        for belowThresholds in [CGSize(width: 440, height: 330), CGSize(width: 780, height: 800)] {
            XCTAssertFalse(ReaderPageLayout.automaticDoublePageLayout(
                readerSize: belowThresholds, currentlyEnabled: true
            ), "\(belowThresholds)")
        }
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
            store.send(.scrollRequestHandled(store.scrollRequest!.id))
            store.send(.readerSizeChanged(CGSize(width: 562, height: 466)))
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
    func testAutomaticRestoreShowsSavedPageAsTrailingPageAndKeepsItWhenNarrowing() async {
        let store = makeAutomaticReaderStore()
        store.send(.requestJump(19, source: .initialRestore))
        store.send(.readerSizeChanged(CGSize(width: 562, height: 466)))
        await Task.yield()
        // Spread [18, 19] keeps the saved page, so reopening does not move progress forward.
        XCTAssertEqual(store.scrollRequest?.targetPageIndex, 19)
        XCTAssertEqual(store.scrollRequest?.source, .initialRestore)
        XCTAssertEqual(store.spreadPairingOffset, 0)
        store.send(.scrollRequestHandled(store.scrollRequest!.id))
        store.send(.visiblePageChanged(19))

        store.send(.readerSizeChanged(CGSize(width: 382, height: 644)))
        await Task.yield()
        XCTAssertFalse(store.doublePageLayout)
        XCTAssertEqual(store.scrollRequest?.targetPageIndex, 19)
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
        store.send(.readerSizeChanged(CGSize(width: 562, height: 466)))
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
                await resizeReader(controller, to: CGSize(width: 562, height: 466))
                XCTAssertTrue(store.doublePageLayout)
                XCTAssertEqual(store.currentPageIndex, 14)
                XCTAssertEqual(controller.collectionView.contentOffset.x, 7 * 562, accuracy: 1)
            }
            await resizeReader(controller, to: CGSize(width: 382, height: 644))
            XCTAssertEqual(store.currentPageIndex, 13)
            XCTAssertEqual(controller.collectionView.contentOffset.x, 13 * 382, accuracy: 1)
            XCTAssertNil(store.scrollRequest)
        }
    }

    @MainActor
    func testAutomaticRemembersSizeBeforePagesArrive() async {
        let store = makeAutomaticReaderStore(archiveId: "TANK_fixture", pageCount: 0, savedProgress: 14)
        store.send(.readerSizeChanged(CGSize(width: 562, height: 466)))
        XCTAssertFalse(store.doublePageLayout)
        store.send(.finishExtracting((1...25).map {
            ReaderExtractedPage(archiveId: "source", path: "/fixture/\($0).jpg", archivePageNumber: $0)
        }, nil))
        // Spreads are decided from the remembered size as the pages arrive, before the restore.
        XCTAssertTrue(store.doublePageLayout)
        XCTAssertEqual(store.currentPageIndex, 13)
        for _ in 0..<5 where store.scrollRequest == nil { await Task.yield() }
        XCTAssertEqual(store.scrollRequest?.source, .initialRestore)
        XCTAssertEqual(store.scrollRequest?.targetPageIndex, 13)
        XCTAssertEqual(store.pages[13].sourceArchiveId, "source")
        XCTAssertEqual(store.pages[13].sourcePageNumber, 14)
    }

    @MainActor
    func testAutomaticUIKitReevaluatesSharedPreferenceWithoutResizing() async {
        let store = makeAutomaticReaderStore()
        store.$automaticPageLayout.withLock { $0 = false }
        let controller = UIPageCollectionController(store: store)
        controller.loadViewIfNeeded()
        await resizeReader(controller, to: CGSize(width: 562, height: 466))
        XCTAssertFalse(store.doublePageLayout)
        store.$automaticPageLayout.withLock { $0 = true }
        await resizeReader(controller, to: CGSize(width: 562, height: 466))
        XCTAssertTrue(store.doublePageLayout)
        store.$automaticPageLayout.withLock { $0 = false }
        await resizeReader(controller, to: CGSize(width: 562, height: 466))
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
        await resizeReader(controller, to: CGSize(width: 562, height: 466))
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
            await resizeReader(controller, to: CGSize(width: 562, height: 466))
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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 562, height: 466))
        let parent = UIViewController()
        window.rootViewController = parent
        parent.addChild(controller)
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)
        window.isHidden = false
        defer { window.isHidden = true }
        XCTAssertNotNil(controller.view.window)
        await resizeReader(controller, to: CGSize(width: 562, height: 400))
        XCTAssertTrue(store.doublePageLayout)
        await resizeReader(controller, to: CGSize(width: 562, height: 280))
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
    pageCount: Int = 25,
    savedProgress: Int? = nil
) -> StoreOf<ArchiveReaderFeature> {
    // An archive in the list is what lets `finishExtracting` restore saved progress.
    let archives = savedProgress.map { progress in
        [Shared(value: ArchiveItem(
            id: archiveId, name: "Fixture", extension: "zip", tags: "", isNew: false,
            progress: progress, pagecount: 25, dateAdded: nil
        ))]
    } ?? []
    var state = ArchiveReaderFeature.State(currentArchiveId: archiveId, allArchives: archives, cached: true)
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
