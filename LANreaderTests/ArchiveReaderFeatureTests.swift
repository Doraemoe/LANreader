import XCTest
import ComposableArchitecture
@testable import LANreader

final class ArchiveReaderFeatureTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.readDirection)
        UserDefaults.standard.removeObject(forKey: SettingsKey.doublePageLayout)
        UserDefaults.standard.removeObject(forKey: SettingsKey.autoPageInterval)
        super.tearDown()
    }

    func testReaderPositioningSinglePageMath() {
        XCTAssertEqual(
            ReaderPositioning.initialPageIndex(
                progress: 3,
                pageCount: 5,
                fromStart: false,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            2
        )
        XCTAssertEqual(
            ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: 2,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: false
            ),
            2
        )
        XCTAssertEqual(
            ReaderPositioning.scrollAnchorIndex(
                forPageIndex: 2,
                pageCount: 5,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            2
        )
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: 2,
                direction: .next,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: false
            ),
            3
        )
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: 2,
                direction: .previous,
                pageCount: 5,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            1
        )
    }

    func testReaderPositioningDoublePageCanonicalAndAnchorMath() {
        XCTAssertEqual(
            ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: 0,
                pageCount: 5,
                readDirection: .leftRight,
                doublePageLayout: true
            ),
            1
        )
        XCTAssertEqual(
            ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: 2,
                pageCount: 5,
                readDirection: .rightLeft,
                doublePageLayout: true
            ),
            3
        )
        XCTAssertEqual(
            ReaderPositioning.scrollAnchorIndex(
                forPageIndex: 1,
                pageCount: 5,
                readDirection: .leftRight,
                doublePageLayout: true
            ),
            0
        )
        XCTAssertEqual(
            ReaderPositioning.scrollAnchorIndex(
                forPageIndex: 4,
                pageCount: 5,
                readDirection: .rightLeft,
                doublePageLayout: true
            ),
            4
        )
    }

    func testReaderPositioningDoublePageAdjacentMath() {
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: 1,
                direction: .next,
                pageCount: 5,
                readDirection: .leftRight,
                doublePageLayout: true
            ),
            3
        )
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: 4,
                direction: .previous,
                pageCount: 5,
                readDirection: .rightLeft,
                doublePageLayout: true
            ),
            3
        )
        XCTAssertNil(
            ReaderPositioning.adjacentPageIndex(
                from: 1,
                direction: .previous,
                pageCount: 5,
                readDirection: .leftRight,
                doublePageLayout: true
            )
        )
    }

    func testReaderPositioningVerticalModeMath() {
        // In vertical (upDown) mode double-page layout has no effect on positioning math
        XCTAssertEqual(
            ReaderPositioning.initialPageIndex(
                progress: 3,
                pageCount: 5,
                fromStart: false,
                readDirection: .upDown,
                doublePageLayout: false
            ),
            2
        )
        XCTAssertEqual(
            ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: 2,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: true
            ),
            2
        )
        XCTAssertEqual(
            ReaderPositioning.scrollAnchorIndex(
                forPageIndex: 3,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: true
            ),
            3
        )
    }

    func testReaderPositioningVerticalModeAdjacentMath() {
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: 2,
                direction: .next,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: true
            ),
            3
        )
        XCTAssertEqual(
            ReaderPositioning.adjacentPageIndex(
                from: 2,
                direction: .previous,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: true
            ),
            1
        )
        XCTAssertNil(
            ReaderPositioning.adjacentPageIndex(
                from: 0,
                direction: .previous,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: false
            )
        )
        XCTAssertNil(
            ReaderPositioning.adjacentPageIndex(
                from: 4,
                direction: .next,
                pageCount: 5,
                readDirection: .upDown,
                doublePageLayout: false
            )
        )
    }

    @MainActor
    func testFinishExtractingVerticalModeIgnoresDoublePageLayout() async {
        configureReaderDefaults(readDirection: .upDown, doublePageLayout: true)
        let store = TestStore(
            initialState: makeState(
                progress: 3,
                readDirection: .upDown,
                doublePageLayout: true
            )
        ) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.finishExtracting(makeExtractedPages(count: 5)))
        // Vertical mode should use simple index (progress 3 → index 2), ignoring double-page
        XCTAssertEqual(store.state.currentPageIndex, 2)

        await store.receive(.requestJump(2, source: .initialRestore))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 2)
    }

    @MainActor
    func testFinishExtractingRestoresSavedProgressAndQueuesInitialScroll() async {
        configureReaderDefaults()
        let store = TestStore(initialState: makeState(progress: 3)) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.finishExtracting(makeExtractedPages(count: 5)))
        XCTAssertEqual(store.state.pages.count, 5)
        XCTAssertEqual(store.state.currentPageIndex, 2)
        XCTAssertTrue(store.state.controlUiHidden)

        await store.receive(.requestJump(2, source: .initialRestore))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 2)
        XCTAssertEqual(store.state.scrollRequest?.source, .initialRestore)
        XCTAssertEqual(store.state.scrollRequest?.animated, false)
    }

    @MainActor
    func testFinishExtractingFromStartStartsAtFirstPage() async {
        configureReaderDefaults()
        let store = TestStore(initialState: makeState(progress: 4, fromStart: true)) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.finishExtracting(makeExtractedPages(count: 5)))
        XCTAssertEqual(store.state.currentPageIndex, 0)

        await store.receive(.requestJump(0, source: .initialRestore))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 0)
    }

    @MainActor
    func testFinishExtractingClampsOutOfRangeProgress() async {
        configureReaderDefaults()
        let store = TestStore(initialState: makeState(progress: 99)) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.finishExtracting(makeExtractedPages(count: 4)))
        XCTAssertEqual(store.state.currentPageIndex, 3)

        await store.receive(.requestJump(3, source: .initialRestore))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 3)
    }

    @MainActor
    func testVisiblePageChangedUpdatesProgressAndClearsNewFlag() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 0, cached: true, isNew: true)
        initialState.pages = makePageStates(count: 3)
        let store = TestStore(initialState: initialState) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.visiblePageChanged(1))
        XCTAssertEqual(store.state.currentPageIndex, 1)
        XCTAssertEqual(store.state.allArchives[id: "archive"]?.wrappedValue.progress, 2)
        XCTAssertEqual(store.state.allArchives[id: "archive"]?.wrappedValue.isNew, false)
    }

    @MainActor
    func testNavigateNextUsesCanonicalDoublePageIndex() async {
        configureReaderDefaults(doublePageLayout: true)
        var initialState = makeState(
            progress: 2,
            readDirection: .leftRight,
            doublePageLayout: true
        )
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 1
        let store = TestStore(initialState: initialState) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.navigate(.next, source: .tap))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 3)
        XCTAssertEqual(store.state.scrollRequest?.source, .tap)
        XCTAssertEqual(store.state.scrollRequest?.animated, true)
    }

    @MainActor
    func testNavigatePreviousUsesCanonicalDoublePageIndex() async {
        configureReaderDefaults(
            readDirection: .rightLeft,
            doublePageLayout: true
        )
        var initialState = makeState(
            progress: 4,
            readDirection: .rightLeft,
            doublePageLayout: true
        )
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 4
        let store = TestStore(initialState: initialState) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.navigate(.previous, source: .keyboard))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 3)
        XCTAssertEqual(store.state.scrollRequest?.source, .keyboard)
    }

    @MainActor
    func testRequestJumpToSamePageTwiceCreatesFreshScrollRequest() async throws {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 1
        let store = TestStore(initialState: initialState) {
            ArchiveReaderFeature()
        }
        store.exhaustivity = .off

        await store.send(.requestJump(1, source: .slider))
        let firstRequestId = try XCTUnwrap(store.state.scrollRequest?.id)

        await store.send(.scrollRequestHandled(firstRequestId))
        XCTAssertNil(store.state.scrollRequest)

        await store.send(.requestJump(1, source: .slider))
        let secondRequestId = try XCTUnwrap(store.state.scrollRequest?.id)

        XCTAssertNotEqual(firstRequestId, secondRequestId)
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 1)
    }

    @MainActor
    func testUIPageCollectionKeepsPendingScrollRequestWhenPagesAreNotLoaded() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.scrollRequest = ScrollRequest(targetPageIndex: 1, source: .slider, animated: false)

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        }
        let viewStore = ViewStore(store, observe: { $0 })
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        await Task.yield()

        XCTAssertNotNil(viewStore.scrollRequest)
    }

    @MainActor
    func testUIPageCollectionConsumesPendingScrollRequestAfterPagesLoad() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.scrollRequest = ScrollRequest(targetPageIndex: 1, source: .slider, animated: false)

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        }
        let viewStore = ViewStore(store, observe: { $0 })
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        await Task.yield()
        await Task.yield()

        XCTAssertNil(viewStore.scrollRequest)
    }

    @MainActor
    func testAutoPageTickRequestsNextPage() async {
        configureReaderDefaults(autoPageInterval: 1)
        let clock = TestClock()
        var initialState = makeState(progress: 2, autoPageInterval: 1)
        initialState.pages = makePageStates(count: 3)
        initialState.currentPageIndex = 1
        initialState.pages[1].imageLoaded = true
        let store = TestStore(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.autoPageTick)
        await clock.advance(by: .seconds(1))

        await store.receive(.navigate(.next, source: .autoPage))
        XCTAssertEqual(store.state.scrollRequest?.targetPageIndex, 2)

        await store.receive(.setLastAutoPageIndex(1))
        await store.receive(.autoPageTick)
        await store.send(.toggleControlUi(false))
    }

    func testLoadNextArchiveResetsStateBeforeLoading() {
        configureReaderDefaults()
        var state = makeState(
            archiveId: "one",
            progress: 2,
            allArchives: [
                makeArchive(id: "one", progress: 2),
                makeArchive(id: "two", progress: 4)
            ]
        )
        state.pages = makePageStates(count: 3, archiveId: "one")
        state.currentPageIndex = 2
        state.scrollRequest = ScrollRequest(targetPageIndex: 2, source: .slider, animated: false)
        state.inCache = true
        state.errorMessage = "error"
        state.successMessage = "success"

        _ = ArchiveReaderFeature().reduce(into: &state, action: .loadNextArchive)

        XCTAssertEqual(state.currentArchiveId, "two")
        XCTAssertTrue(state.pages.isEmpty)
        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertNil(state.scrollRequest)
        XCTAssertFalse(state.inCache)
        XCTAssertEqual(state.errorMessage, "")
        XCTAssertEqual(state.successMessage, "")
    }

    private func configureReaderDefaults(
        readDirection: ReadDirection = .leftRight,
        doublePageLayout: Bool = false,
        autoPageInterval: Double = 5
    ) {
        UserDefaults.standard.set(readDirection.rawValue, forKey: SettingsKey.readDirection)
        UserDefaults.standard.set(doublePageLayout, forKey: SettingsKey.doublePageLayout)
        UserDefaults.standard.set(autoPageInterval, forKey: SettingsKey.autoPageInterval)
    }

    private func makeState(
        archiveId: String = "archive",
        progress: Int = 0,
        fromStart: Bool = false,
        cached: Bool = false,
        isNew: Bool = false,
        allArchives: [ArchiveItem]? = nil,
        readDirection: ReadDirection = .leftRight,
        doublePageLayout: Bool = false,
        autoPageInterval: Double = 5
    ) -> ArchiveReaderFeature.State {
        let archives = allArchives ?? [makeArchive(id: archiveId, progress: progress, isNew: isNew)]
        var state = ArchiveReaderFeature.State(
            currentArchiveId: archiveId,
            allArchives: archives.map { Shared(value: $0) },
            fromStart: fromStart,
            cached: cached
        )
        state.$readDirection = SharedReader(value: readDirection.rawValue)
        state.$doublePageLayout = SharedReader(value: doublePageLayout)
        state.$autoPageInterval = SharedReader(value: autoPageInterval)
        return state
    }

    private func makeArchive(
        id: String = "archive",
        progress: Int = 0,
        isNew: Bool = false
    ) -> ArchiveItem {
        ArchiveItem(
            id: id,
            name: "Archive \(id)",
            extension: "zip",
            tags: "",
            isNew: isNew,
            progress: progress,
            pagecount: 10,
            dateAdded: nil
        )
    }

    private func makeExtractedPages(count: Int) -> [String] {
        (1...count).map { "p\($0)" }
    }

    private func makePageStates(
        count: Int,
        archiveId: String = "archive"
    ) -> IdentifiedArrayOf<PageFeature.State> {
        IdentifiedArray(
            uniqueElements: (1...count).map {
                PageFeature.State(
                    archiveId: archiveId,
                    pageId: "\($0)",
                    pageNumber: $0
                )
            }
        )
    }

}
