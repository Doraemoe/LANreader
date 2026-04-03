import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

// swiftlint:disable type_body_length file_length

final class ArchiveReaderFeatureTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.readDirection)
        UserDefaults.standard.removeObject(forKey: SettingsKey.doublePageLayout)
        UserDefaults.standard.removeObject(forKey: SettingsKey.autoPageInterval)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
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
        try? await configureVerifiedClient()
        stubPageThumbnailQueueAlreadyGenerated()
        let store = makeTestStore(
            initialState: makeState(
                progress: 3,
                readDirection: .upDown,
                doublePageLayout: true
            )
        )

        await store.send(.finishExtracting(makeExtractedPages(count: 5))) {
            $0.pages = makePageStates(count: 5)
            $0.currentPageIndex = 2
            $0.controlUiHidden = true
        }
        await store.receive(.requestJump(2, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 2,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailsQueued(makeAlreadyGeneratedThumbnailQueueResponse())) {
            $0.sliderThumbnailQueueing = false
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingRestoresSavedProgressAndQueuesInitialScroll() async {
        configureReaderDefaults()
        try? await configureVerifiedClient()
        stubPageThumbnailQueueAlreadyGenerated()
        let store = makeTestStore(initialState: makeState(progress: 3))

        await store.send(.finishExtracting(makeExtractedPages(count: 5))) {
            $0.pages = makePageStates(count: 5)
            $0.currentPageIndex = 2
            $0.controlUiHidden = true
        }
        await store.receive(.requestJump(2, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 2,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailsQueued(makeAlreadyGeneratedThumbnailQueueResponse())) {
            $0.sliderThumbnailQueueing = false
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingFromStartStartsAtFirstPage() async {
        configureReaderDefaults()
        try? await configureVerifiedClient()
        stubPageThumbnailQueueAlreadyGenerated()
        let store = makeTestStore(initialState: makeState(progress: 4, fromStart: true))

        await store.send(.finishExtracting(makeExtractedPages(count: 5))) {
            $0.pages = makePageStates(count: 5)
            $0.controlUiHidden = true
        }
        await store.receive(.requestJump(0, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 0,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailsQueued(makeAlreadyGeneratedThumbnailQueueResponse())) {
            $0.sliderThumbnailQueueing = false
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingClampsOutOfRangeProgress() async {
        configureReaderDefaults()
        try? await configureVerifiedClient()
        stubPageThumbnailQueueAlreadyGenerated()
        let store = makeTestStore(initialState: makeState(progress: 99))

        await store.send(.finishExtracting(makeExtractedPages(count: 4))) {
            $0.pages = makePageStates(count: 4)
            $0.currentPageIndex = 3
            $0.controlUiHidden = true
        }
        await store.receive(.requestJump(3, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailsQueued(makeAlreadyGeneratedThumbnailQueueResponse())) {
            $0.sliderThumbnailQueueing = false
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testVisiblePageChangedUpdatesProgressAndClearsNewFlag() async {
        configureReaderDefaults()
        let clock = TestClock()
        var initialState = makeState(progress: 0, cached: true, isNew: true)
        initialState.pages = makePageStates(count: 3)
        let store = makeTestStore(initialState: initialState) {
            $0.continuousClock = clock
        }

        await store.send(.visiblePageChanged(1)) {
            $0.currentPageIndex = 1
            $0.allArchives[id: "archive"]?.withLock {
                $0.progress = 2
                $0.isNew = false
            }
        }
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
        let store = makeTestStore(initialState: initialState)

        await store.send(.navigate(.next, source: .tap)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .tap,
                animated: true
            )
        }
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
        let store = makeTestStore(initialState: initialState)

        await store.send(.navigate(.previous, source: .keyboard)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .keyboard,
                animated: true
            )
        }
    }

    @MainActor
    func testRequestJumpToSamePageTwiceCreatesFreshScrollRequest() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 1
        let store = makeTestStore(initialState: initialState)

        await store.send(.requestJump(1, source: .slider)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 1,
                source: .slider,
                animated: false
            )
        }
        await store.send(.scrollRequestHandled(incrementingUUID(0))) {
            $0.scrollRequest = nil
        }
        await store.send(.requestJump(1, source: .slider)) {
            $0.scrollRequest = makeScrollRequest(
                id: 1,
                targetPageIndex: 1,
                source: .slider,
                animated: false
            )
        }
    }

    @MainActor
    func testUIPageCollectionKeepsPendingScrollRequestWhenPagesAreNotLoaded() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.scrollRequest = ScrollRequest(targetPageIndex: 1, source: .slider, animated: false)

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        await Task.yield()

        XCTAssertNotNil(store.scrollRequest)
    }

    @MainActor
    func testUIPageCollectionConsumesPendingScrollRequestAfterPagesLoad() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.scrollRequest = ScrollRequest(targetPageIndex: 1, source: .slider, animated: false)

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        await Task.yield()
        await Task.yield()

        XCTAssertNil(store.scrollRequest)
    }

    @MainActor
    func testAutoPageTickRequestsNextPage() async {
        configureReaderDefaults(autoPageInterval: 1)
        let clock = TestClock()
        var initialState = makeState(progress: 2, autoPageInterval: 1)
        initialState.pages = makePageStates(count: 3)
        initialState.currentPageIndex = 1
        initialState.pages[1].imageLoaded = true
        let store = makeTestStore(initialState: initialState) {
            $0.continuousClock = clock
        }

        await store.send(.autoPageTick)
        await clock.advance(by: .seconds(1))

        await store.receive(.navigate(.next, source: .autoPage)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 2,
                source: .autoPage,
                animated: true
            )
        }
        await store.receive(.setLastAutoPageIndex(1)) {
            $0.lastAutoPageIndex = 1
        }
        await store.receive(.autoPageTick)
        await store.send(.toggleControlUi(false)) {
            $0.lastAutoPageIndex = nil
        }
    }

    @MainActor
    func testSliderPreviewQueuedResponseStoresJobId() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: 42,
                    message: nil,
                    operation: "generate_page_thumbnails",
                    success: 1
                )
            )
        ) {
            $0.sliderThumbnailJobId = 42
        }
        await store.receive(.pollSliderPreviewThumbnailJob(42))
        await store.receive(.sliderPreviewThumbnailPollingFailed) {
            $0.sliderThumbnailJobId = nil
        }
    }

    @MainActor
    func testPrepareSliderPreviewThumbnailsUsesUniqueArchivePageCountWhenPagesAreSplit() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makeSplitPageStates()
        initialState.sliderReadyThumbnailPages = Set([1, 2, 3])
        let store = makeTestStore(initialState: initialState)

        await store.send(.prepareSliderPreviewThumbnails)
    }

    @MainActor
    func testSliderPreviewQueuedResponseUsesUniqueArchivePageCountWhenPagesAreSplit() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makeSplitPageStates()
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: 42,
                    message: nil,
                    operation: "generate_page_thumbnails",
                    success: 1
                )
            )
        ) {
            $0.sliderThumbnailJobId = 42
        }
        await store.receive(.pollSliderPreviewThumbnailJob(42))
        await store.receive(.sliderPreviewThumbnailPollingFailed) {
            $0.sliderThumbnailJobId = nil
        }
    }

    @MainActor
    func testSliderPreviewFinishedJobStatusMarksReadyPages() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderThumbnailJobId = 42
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailJobStatus(
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [
                        "1": .string("processed"),
                        "2": .string("processed"),
                        "3": .string("processed"),
                        "4": .string("processed"),
                        "total_pages": .int(4)
                    ],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobId = nil
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testSliderPreviewFinishedJobStatusUsesUniqueArchivePageCountWhenPagesAreSplit() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makeSplitPageStates()
        initialState.sliderThumbnailJobId = 42
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailJobStatus(
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [
                        "1": .string("processed"),
                        "2": .string("processed")
                    ],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobId = nil
            $0.sliderReadyThumbnailPages = Set([1, 2, 3])
        }
    }

    @MainActor
    func testSliderPreviewInactiveJobStatusStopsPollingAndClearsJobId() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderThumbnailJobId = 42
        initialState.sliderPreviewLoading = true
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailJobStatus(
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "inactive",
                    notes: [
                        "1": .string("processed")
                    ],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobId = nil
            $0.sliderReadyThumbnailPages = Set([1])
            $0.sliderPreviewLoading = false
        }
    }

    @MainActor
    func testSliderPreviewAlreadyGeneratedMarksAllPagesReady() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: nil,
                    message: "No job queued, all thumbnails already exist.",
                    operation: "generate_page_thumbnails",
                    success: 1
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testSliderPreviewQueueFailureAllowsLaterRetry() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()
        stubPageThumbnailQueueFailure()

        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderPreviewVisible = true
        initialState.sliderPreviewPageIndex = 1
        let store = makeTestStore(initialState: initialState)

        await store.send(.loadSliderPreview(1)) {
            $0.sliderPreviewImageURL = nil
            $0.sliderPreviewLoading = true
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailQueueFailed) {
            $0.sliderThumbnailQueueing = false
            $0.sliderPreviewLoading = false
        }

        await store.send(.loadSliderPreview(1)) {
            $0.sliderPreviewImageURL = nil
            $0.sliderPreviewLoading = true
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailQueueFailed) {
            $0.sliderThumbnailQueueing = false
            $0.sliderPreviewLoading = false
        }
    }

    @MainActor
    func testSliderDragChangedUpdatesPreviewStateWithoutJump() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 1
        let store = makeTestStore(initialState: initialState)

        await store.send(.sliderDragStarted) {
            $0.sliderDragging = true
            $0.sliderDraftIndex = 1
            $0.sliderPreviewVisible = true
            $0.sliderPreviewPageIndex = 1
        }
        await store.receive(.loadSliderPreview(1)) {
            $0.sliderPreviewLoading = true
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailQueueFailed) {
            $0.sliderThumbnailQueueing = false
            $0.sliderPreviewLoading = false
        }

        await store.send(.sliderDragChanged(3)) {
            $0.sliderDraftIndex = 3
            $0.sliderPreviewPageIndex = 3
        }
        await store.receive(.loadSliderPreview(3)) {
            $0.sliderPreviewLoading = true
        }
        await store.receive(.prepareSliderPreviewThumbnails) {
            $0.sliderThumbnailQueueing = true
        }
        await store.receive(.sliderPreviewThumbnailQueueFailed) {
            $0.sliderThumbnailQueueing = false
            $0.sliderPreviewLoading = false
        }
    }

    @MainActor
    func testSliderDragEndedQueuesSliderJumpAndClearsPreviewState() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderDraftIndex = 3
        initialState.sliderDragging = true
        initialState.sliderPreviewVisible = true
        initialState.sliderPreviewPageIndex = 3
        initialState.sliderPreviewLoading = true
        let store = makeTestStore(initialState: initialState)

        await store.send(.sliderDragEnded) {
            $0.sliderDraftIndex = nil
            $0.sliderDragging = false
            $0.sliderPreviewVisible = false
            $0.sliderPreviewPageIndex = nil
            $0.sliderPreviewImageURL = nil
            $0.sliderPreviewLoading = false
        }
        await store.receive(.requestJump(3, source: .slider)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .slider,
                animated: false
            )
        }
    }

    @MainActor
    func testSliderDragChangeAfterEndDoesNotReopenPreview() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderDraftIndex = 3
        initialState.sliderDragging = true
        initialState.sliderPreviewVisible = true
        initialState.sliderPreviewPageIndex = 3
        let store = makeTestStore(initialState: initialState)

        await store.send(.sliderDragEnded) {
            $0.sliderDraftIndex = nil
            $0.sliderDragging = false
            $0.sliderPreviewVisible = false
            $0.sliderPreviewPageIndex = nil
            $0.sliderPreviewImageURL = nil
            $0.sliderPreviewLoading = false
        }
        await store.receive(.requestJump(3, source: .slider)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .slider,
                animated: false
            )
        }

        await store.send(.sliderDragChanged(3))
    }

    @MainActor
    func testSliderPreviewFailedKeepsExistingPreviewFile() async throws {
        configureReaderDefaults()
        let archiveId = UUID().uuidString
        var initialState = makeState(archiveId: archiveId, progress: 2)
        initialState.pages = makePageStates(count: 4, archiveId: archiveId)
        initialState.sliderPreviewVisible = true
        initialState.sliderPreviewPageIndex = 1

        let previewDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANreader", isDirectory: true)
            .appendingPathComponent("reader-preview", isDirectory: true)
            .appendingPathComponent(archiveId, isDirectory: true)
        let previewURL = previewDirectory.appendingPathComponent("2.jpg", isDirectory: false)
        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: previewURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: previewDirectory)
        }

        let store = makeTestStore(initialState: initialState)

        await store.send(.sliderPreviewFailed(1)) {
            $0.sliderPreviewImageURL = previewURL
            $0.sliderPreviewLoading = false
        }
    }

    func testResetStateClearsTransientReaderState() {
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
        state.sliderDraftIndex = 1
        state.sliderDragging = true
        state.sliderPreviewVisible = true
        state.sliderPreviewPageIndex = 1
        state.sliderPreviewImageURL = URL(fileURLWithPath: "/tmp/preview.jpg")
        state.sliderPreviewLoading = true
        state.sliderThumbnailQueueing = true
        state.sliderThumbnailJobId = 42
        state.sliderReadyThumbnailPages = Set([1, 2])

        ArchiveReaderFeature().resetState(state: &state)

        XCTAssertTrue(state.pages.isEmpty)
        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertNil(state.scrollRequest)
        XCTAssertFalse(state.inCache)
        XCTAssertEqual(state.errorMessage, "")
        XCTAssertEqual(state.successMessage, "")
        XCTAssertNil(state.sliderDraftIndex)
        XCTAssertFalse(state.sliderDragging)
        XCTAssertFalse(state.sliderPreviewVisible)
        XCTAssertNil(state.sliderPreviewPageIndex)
        XCTAssertNil(state.sliderPreviewImageURL)
        XCTAssertFalse(state.sliderPreviewLoading)
        XCTAssertFalse(state.sliderThumbnailQueueing)
        XCTAssertNil(state.sliderThumbnailJobId)
        XCTAssertTrue(state.sliderReadyThumbnailPages.isEmpty)
    }
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

private func configureVerifiedClient() async throws {
    let url = "https://localhost"
    let apiKey = "apiKey"
    UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
    UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)

    stub(condition: isHost("localhost")
            && isPath("/api/info")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "archives_per_page": 100,
              "debug_mode": false,
              "has_password": true,
              "motd": "",
              "name": "LANraragi",
              "nofun_mode": false,
              "server_tracks_progress": true,
              "version": "0.9.30",
              "version_name": "Law (Earthlings On Fire)"
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }

    _ = try await LANraragiService.shared.verifyClient(url: url, apiKey: apiKey)
}

private func stubPageThumbnailQueueAlreadyGenerated(archiveId: String = "archive") {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/files/thumbnails")
            && isMethodPOST()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "message": "No job queued, all thumbnails already exist.",
              "operation": "generate_page_thumbnails",
              "success": 1
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubPageThumbnailQueueFailure(archiveId: String = "archive") {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/files/thumbnails")
            && isMethodPOST()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data(),
            statusCode: 500,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func makeAlreadyGeneratedThumbnailQueueResponse() -> PageThumbnailQueueResponse {
    PageThumbnailQueueResponse(
        job: nil,
        message: "No job queued, all thumbnails already exist.",
        operation: "generate_page_thumbnails",
        success: 1
    )
}

@MainActor
private func makeTestStore(
    initialState: ArchiveReaderFeature.State,
    configureDependencies: ((inout DependencyValues) -> Void)? = nil
) -> TestStoreOf<ArchiveReaderFeature> {
    TestStore(initialState: initialState) {
        ArchiveReaderFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        configureDependencies?(&$0)
    }
}

private func makeScrollRequest(
    id: Int,
    targetPageIndex: Int,
    source: ReaderNavigationSource,
    animated: Bool
) -> ScrollRequest {
    ScrollRequest(
        id: incrementingUUID(id),
        targetPageIndex: targetPageIndex,
        source: source,
        animated: animated
    )
}

private func incrementingUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
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
    let state = ArchiveReaderFeature.State(
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

private func makeSplitPageStates(
    archiveId: String = "archive"
) -> IdentifiedArrayOf<PageFeature.State> {
    IdentifiedArray(
        uniqueElements: [
            PageFeature.State(
                archiveId: archiveId,
                pageId: "1",
                pageNumber: 1,
                pageMode: .normal
            ),
            PageFeature.State(
                archiveId: archiveId,
                pageId: "2",
                pageNumber: 2,
                pageMode: .left
            ),
            PageFeature.State(
                archiveId: archiveId,
                pageId: "2",
                pageNumber: 2,
                pageMode: .right
            ),
            PageFeature.State(
                archiveId: archiveId,
                pageId: "3",
                pageNumber: 3,
                pageMode: .normal
            )
        ]
    )
}
// swiftlint:enable type_body_length file_length
