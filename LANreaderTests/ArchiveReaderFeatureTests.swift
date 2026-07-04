import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
@testable import LANreader

// swiftlint:disable type_body_length file_length

final class ArchiveReaderFeatureTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.readDirection)
        UserDefaults.standard.removeObject(forKey: SettingsKey.doublePageLayout)
        UserDefaults.standard.removeObject(forKey: SettingsKey.autoPageInterval)
        UserDefaults.standard.removeObject(forKey: SettingsKey.splitWideImage)
        UserDefaults.standard.removeObject(forKey: SettingsKey.splitPiorityLeft)
        UserDefaults.standard.removeObject(forKey: SettingsKey.serverProgress)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
        super.tearDown()
    }

    @MainActor
    func testReadSettingsEnablingSplitDisablesDoublePageLayout() async {
        configureReaderDefaults(doublePageLayout: true)
        let store = TestStore(initialState: ReadSettingsFeature.State()) {
            ReadSettingsFeature()
        }

        await store.send(.splitWideImageChanged(true)) {
            $0.$splitWideImage.withLock { $0 = true }
            $0.$doublePageLayout.withLock { $0 = false }
        }
    }

    @MainActor
    func testReadSettingsEnablingDoublePageLayoutDisablesSplitAndKeepsPriority() async {
        configureReaderDefaults(
            splitWideImage: true,
            splitPiorityLeft: true
        )
        let store = TestStore(initialState: ReadSettingsFeature.State()) {
            ReadSettingsFeature()
        }

        await store.send(.doublePageLayoutChanged(true)) {
            $0.$splitWideImage.withLock { $0 = false }
            $0.$doublePageLayout.withLock { $0 = true }
        }
    }

    @MainActor
    func testReadSettingsDisablingSplitKeepsPriority() async {
        configureReaderDefaults(
            splitWideImage: true,
            splitPiorityLeft: true
        )
        let store = TestStore(initialState: ReadSettingsFeature.State()) {
            ReadSettingsFeature()
        }

        await store.send(.splitWideImageChanged(false)) {
            $0.$splitWideImage.withLock { $0 = false }
        }
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

    func testSliderPreviewPositioningMirrorsVisualNormalizedInRTL() {
        XCTAssertEqual(
            SliderPreviewPositioning.visualNormalized(
                pageIndex: 0,
                pageCount: 5,
                isRightToLeft: false
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SliderPreviewPositioning.visualNormalized(
                pageIndex: 0,
                pageCount: 5,
                isRightToLeft: true
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SliderPreviewPositioning.visualNormalized(
                pageIndex: 4,
                pageCount: 5,
                isRightToLeft: true
            ),
            0,
            accuracy: 0.001
        )
    }

    func testSliderPreviewPositioningClampsBubbleToRightEdgeInRTL() {
        XCTAssertEqual(
            SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: 0,
                pageCount: 5,
                track: SliderPreviewTrackGeometry(
                    rowWidth: 320,
                    sliderHorizontalPadding: 16,
                    bubbleWidth: 100
                ),
                isRightToLeft: true
            ),
            220,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: 0,
                pageCount: 5,
                track: SliderPreviewTrackGeometry(
                    rowWidth: 320,
                    sliderHorizontalPadding: 16,
                    bubbleWidth: 100
                ),
                isRightToLeft: false
            ),
            0,
            accuracy: 0.001
        )
    }

    func testSliderPreviewPositioningMapsRightEdgeToFirstPageInRTL() {
        XCTAssertEqual(
            SliderPreviewPositioning.pageIndex(
                at: 304,
                sliderWidth: 288,
                horizontalPadding: 16,
                sliderMaxIndex: 4,
                isRightToLeft: true
            ),
            0
        )
        XCTAssertEqual(
            SliderPreviewPositioning.pageIndex(
                at: 16,
                sliderWidth: 288,
                horizontalPadding: 16,
                sliderMaxIndex: 4,
                isRightToLeft: true
            ),
            4
        )
    }

    @MainActor
    func testFinishExtractingVerticalModeIgnoresDoublePageLayout() async throws {
        configureReaderDefaults(readDirection: .upDown, doublePageLayout: true)
        try await configureReadyThumbnailQueue()
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
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: nil,
                    message: "No job queued, all thumbnails already exist.",
                    operation: "generate_page_thumbnails",
                    success: "1"
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingRestoresSavedProgressAndQueuesInitialScroll() async throws {
        configureReaderDefaults()
        try await configureReadyThumbnailQueue()
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
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: nil,
                    message: "No job queued, all thumbnails already exist.",
                    operation: "generate_page_thumbnails",
                    success: "1"
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingFromStartStartsAtFirstPage() async throws {
        configureReaderDefaults()
        try await configureReadyThumbnailQueue()
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
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: nil,
                    message: "No job queued, all thumbnails already exist.",
                    operation: "generate_page_thumbnails",
                    success: "1"
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingClampsOutOfRangeProgress() async throws {
        configureReaderDefaults()
        try await configureReadyThumbnailQueue()
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
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: nil,
                    message: "No job queued, all thumbnails already exist.",
                    operation: "generate_page_thumbnails",
                    success: "1"
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testExtractTankoubonExtractsUnderlyingArchivesInOrder() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives()
        let extractedPages = makeExtractedPages(sourceArchives: sourceArchives)

        stubTankoubonFull(tankId: tankId, archiveIds: sourceArchives.map(\.id))
        for sourceArchive in sourceArchives {
            stubExtractArchive(archiveId: sourceArchive.id, pages: sourceArchive.pages)
            stubReadyThumbnailQueue(archiveId: sourceArchive.id)
        }

        let database = try makeInMemoryDatabase()
        let store = makeTestStore(initialState: makeState(archiveId: tankId, progress: 2)) {
            $0.appDatabase = database
        }

        await store.send(.extractArchive) {
            $0.extracting = true
        }
        await store.receive(.finishExtracting(extractedPages)) {
            $0.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
            $0.currentPageIndex = 1
            $0.controlUiHidden = true
            $0.extracting = false
        }
        await store.receive(.requestJump(1, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 1,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .tankSliderPreviewThumbnailsQueued(readyThumbnailQueueResults(for: sourceArchives))
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3])
        }
    }

    @MainActor
    func testPrepareTankSliderPreviewThumbnailsQueuesAllUnderlyingArchives() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives()
        stubReadyThumbnailQueues(for: sourceArchives)

        var initialState = makeState(archiveId: tankId, progress: 1)
        initialState.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
        let store = makeTestStore(initialState: initialState)

        await store.send(.prepareSliderPreviewThumbnails)
        await store.receive(
            .tankSliderPreviewThumbnailsQueued(readyThumbnailQueueResults(for: sourceArchives))
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3])
        }
    }

    @MainActor
    func testSetThumbnailUsesArchiveEndpointForNormalArchive() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let archiveId = "archive"
        let thumbnailData = Data([0xFF, 0xD8, 0xFF, 0xDB])
        stubArchiveThumbnailUpdate(archiveId: archiveId, page: 2)
        stubReaderArchiveThumbnail(archiveId: archiveId, data: thumbnailData)

        let database = try makeInMemoryDatabase()
        var initialState = makeState(archiveId: archiveId)
        initialState.pages = makePageStates(count: 3, archiveId: archiveId)
        initialState.currentPageIndex = 1
        let store = makeTestStore(initialState: initialState) {
            $0.appDatabase = database
        }

        await store.send(.setThumbnail) {
            $0.settingThumbnail = true
        }
        await store.receive(.setSuccess(String(localized: "archive.thumbnail.set"))) {
            $0.successMessage = String(localized: "archive.thumbnail.set")
        }
        await store.receive(.finishThumbnailLoading) {
            $0.settingThumbnail = false
            $0.allArchives[id: archiveId]?.withLock {
                $0.refresh = true
            }
        }

        let savedThumbnail = try database.readArchiveThumbnail(archiveId)
        XCTAssertEqual(savedThumbnail?.thumbnail, thumbnailData)
    }

    @MainActor
    func testSetThumbnailUsesTankoubonEndpointForTankArchive() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives()
        let thumbnailData = Data([0x89, 0x50, 0x4E, 0x47])
        stubTankoubonThumbnailUpdate(tankId: tankId, page: 3)
        stubReaderTankoubonThumbnail(tankId: tankId, data: thumbnailData)

        let database = try makeInMemoryDatabase()
        var initialState = makeState(archiveId: tankId)
        initialState.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
        initialState.currentPageIndex = 2
        let store = makeTestStore(initialState: initialState) {
            $0.appDatabase = database
        }

        await store.send(.setThumbnail) {
            $0.settingThumbnail = true
        }
        await store.receive(.setSuccess(String(localized: "archive.thumbnail.set"))) {
            $0.successMessage = String(localized: "archive.thumbnail.set")
        }
        await store.receive(.finishThumbnailLoading) {
            $0.settingThumbnail = false
            $0.allArchives[id: tankId]?.withLock {
                $0.refresh = true
            }
        }

        let savedThumbnail = try database.readArchiveThumbnail(tankId)
        XCTAssertEqual(savedThumbnail?.thumbnail, thumbnailData)
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
    func testVisiblePageChangedUsesArchiveProgressEndpointForNormalArchive() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let clock = TestClock()
        let progressUpdated = expectation(description: "archive progress updated")
        stubArchiveProgressUpdate(archiveId: "archive", progress: 3, expectation: progressUpdated)

        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 1
        initialState.$serverProgress = SharedReader(value: true)
        let store = makeTestStore(initialState: initialState) {
            $0.continuousClock = clock
        }

        await store.send(.visiblePageChanged(2)) {
            $0.currentPageIndex = 2
            $0.allArchives[id: "archive"]?.withLock {
                $0.progress = 3
            }
        }

        await Task.yield()
        await clock.advance(by: .seconds(1))
        await fulfillment(of: [progressUpdated], timeout: 1)
        await store.finish()
    }

    @MainActor
    func testVisiblePageChangedUsesGlobalTankProgressEndpointForTankArchive() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives(secondPageCount: 2)
        let clock = TestClock()
        let progressUpdated = expectation(description: "tank progress updated")
        stubTankoubonProgressUpdate(tankId: tankId, progress: 3, expectation: progressUpdated)

        var initialState = makeState(archiveId: tankId, progress: 2)
        initialState.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
        initialState.currentPageIndex = 1
        initialState.$serverProgress = SharedReader(value: true)
        let store = makeTestStore(initialState: initialState) {
            $0.continuousClock = clock
        }

        await store.send(.visiblePageChanged(2)) {
            $0.currentPageIndex = 2
            $0.allArchives[id: tankId]?.withLock {
                $0.progress = 3
            }
        }

        await Task.yield()
        await clock.advance(by: .seconds(1))
        await fulfillment(of: [progressUpdated], timeout: 1)
        await store.finish()
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
    func testNavigatePreviousSetsTrailingSplitModeForUnloadedTarget() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 3)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 2
        let store = makeTestStore(initialState: initialState)

        await store.send(.navigate(.previous, source: .tap)) {
            $0.pages[1].pendingSplitMode = .left
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 1,
                source: .tap,
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
    func testSplitPageResolutionBeforeCurrentPreservesVisiblePage() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 3)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 2
        let splittingPageId = initialState.pages[0].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pages[0].pageMode = .right
            $0.pages[0].imageLoaded = true
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "1",
                    pageNumber: 1,
                    pageMode: .left
                ),
                at: 1
            )
            $0.currentPageIndex = 3
        }
    }

    @MainActor
    func testSplitPageResolutionForCurrentPageDoesNotForceRescroll() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 3)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 2
        let splittingPageId = initialState.pages[2].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pages[2].pageMode = .right
            $0.pages[2].imageLoaded = true
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "3",
                    pageNumber: 3,
                    pageMode: .left
                ),
                at: 3
            )
        }
    }

    @MainActor
    func testSplitPageResolutionKeepsSiblingLoadedWhenSourcePageIsLoaded() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 3)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 4)
        initialState.pages[2].imageLoaded = true
        initialState.currentPageIndex = 2
        let splittingPageId = initialState.pages[2].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pages[2].pageMode = .right
            $0.pages[2].imageLoaded = true
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "3",
                    pageNumber: 3,
                    pageMode: .left
                ),
                at: 3
            )
        }
    }

    @MainActor
    func testSplitPageResolutionBeforeTrailingCurrentPreservesVisiblePage() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 2)
        initialState.$splitImage = SharedReader(value: true)
        var pages = makePageStates(count: 3)
        pages[1].pageMode = .left
        pages[1].imageLoaded = true
        initialState.pages = pages
        initialState.currentPageIndex = 1
        let splittingPageId = initialState.pages[1].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "2",
                    pageNumber: 2,
                    pageMode: .right
                ),
                at: 1
            )
            $0.currentPageIndex = 2
        }
    }

    @MainActor
    func testSplitPageResolutionUsesPendingTrailingModeForUnloadedCurrentPage() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 2)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 3)
        initialState.pages[1].pendingSplitMode = .left
        initialState.currentPageIndex = 1
        let splittingPageId = initialState.pages[1].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "2",
                    pageNumber: 2,
                    pageMode: .right
                ),
                at: 1
            )
            $0.pages[2].pageMode = .left
            $0.pages[2].pendingSplitMode = nil
            $0.pages[2].imageLoaded = true
            $0.currentPageIndex = 2
        }
    }

    @MainActor
    func testSplitPageResolutionQueuesWhileCollectionIsScrolling() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 2)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 3)
        initialState.currentPageIndex = 1
        initialState.collectionScrolling = true
        let splittingPageId = initialState.pages[1].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pendingSplitResolutions[splittingPageId] = true
        }
    }

    @MainActor
    func testQueuedSplitPageResolutionAppliesWhenCollectionStopsScrolling() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 2)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 3)
        initialState.currentPageIndex = 1
        let splittingPageId = initialState.pages[1].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.collectionScrollStarted) {
            $0.collectionScrolling = true
        }
        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pendingSplitResolutions[splittingPageId] = true
        }
        await store.send(.collectionScrollEnded) {
            $0.collectionScrolling = false
            $0.pendingSplitResolutions = [:]
            $0.pages[1].pageMode = .right
            $0.pages[1].imageLoaded = true
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "2",
                    pageNumber: 2,
                    pageMode: .left
                ),
                at: 2
            )
        }
    }

    @MainActor
    func testQueuedSplitPageResolutionPreservesVisiblePageAfterInsertionBeforeCurrent() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 3)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 2
        initialState.collectionScrolling = true
        let splittingPageId = initialState.pages[0].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pendingSplitResolutions[splittingPageId] = true
        }
        await store.send(.collectionScrollEnded) {
            $0.collectionScrolling = false
            $0.pendingSplitResolutions = [:]
            $0.pages[0].pageMode = .right
            $0.pages[0].imageLoaded = true
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "1",
                    pageNumber: 1,
                    pageMode: .left
                ),
                at: 1
            )
            $0.currentPageIndex = 3
        }
    }

    @MainActor
    func testVerticalSplitPageResolutionQueuesWhileCollectionIsScrolling() async {
        configureReaderDefaults(
            readDirection: .upDown,
            splitWideImage: true
        )
        var initialState = makeState(
            progress: 2,
            readDirection: .upDown
        )
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 3)
        initialState.currentPageIndex = 1
        initialState.collectionScrolling = true
        let splittingPageId = initialState.pages[1].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pendingSplitResolutions[splittingPageId] = true
        }
        await store.send(.collectionScrollEnded) {
            $0.collectionScrolling = false
            $0.pendingSplitResolutions = [:]
            $0.pages[1].pageMode = .right
            $0.pages[1].imageLoaded = true
            $0.pages.insert(
                loadedPageState(
                    archiveId: "archive",
                    pageId: "2",
                    pageNumber: 2,
                    pageMode: .left
                ),
                at: 2
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
    func testUIPageCollectionDoesNotOverwriteRestoredPageDuringInitialSnapshot() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 3)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 2

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.currentPageIndex, 2)
        XCTAssertEqual(store.allArchives[id: "archive"]?.wrappedValue.progress, 3)
    }

    @MainActor
    func testUIPageCollectionPreservesVisiblePageWhenSplitSiblingIsInsertedBeforeIt() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 2)
        initialState.$splitImage = SharedReader(value: true)
        var pages = makePageStates(count: 3)
        pages[1].pageMode = .left
        pages[1].imageLoaded = true
        initialState.pages = pages
        initialState.currentPageIndex = 1

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        controller.view.layoutIfNeeded()
        await Task.yield()
        await Task.yield()

        let pageWidth = controller.collectionView.bounds.width
        XCTAssertGreaterThan(pageWidth, 0)
        controller.collectionView.setContentOffset(CGPoint(x: pageWidth, y: 0), animated: false)
        controller.collectionView.layoutIfNeeded()

        let visiblePageId = store.pages[1].id
        store.send(.page(.element(
            id: visiblePageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        )))
        await Task.yield()
        await Task.yield()
        controller.collectionView.layoutIfNeeded()

        XCTAssertEqual(store.currentPageIndex, 2)
        XCTAssertEqual(controller.collectionView.contentOffset.x, pageWidth * 2, accuracy: 1)
    }

    @MainActor
    func testUIPageCollectionQueuesPriorityLeftBackwardSplitDuringAnimatedScroll() async {
        configureReaderDefaults(splitWideImage: true, splitPiorityLeft: true)
        var initialState = makeState(progress: 3)
        initialState.$splitImage = SharedReader(value: true)
        initialState.$piorityLeft = SharedReader(value: true)
        initialState.pages = makePageStates(count: 3)
        initialState.currentPageIndex = 2

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        controller.view.layoutIfNeeded()
        await Task.yield()
        await Task.yield()

        let pageWidth = controller.collectionView.bounds.width
        XCTAssertGreaterThan(pageWidth, 0)
        controller.collectionView.setContentOffset(CGPoint(x: pageWidth * 2, y: 0), animated: false)
        controller.collectionView.layoutIfNeeded()

        store.send(.navigate(.previous, source: .tap))
        await Task.yield()
        store.send(.collectionScrollStarted)
        controller.collectionView.setContentOffset(CGPoint(x: pageWidth * 1.5, y: 0), animated: false)
        XCTAssertTrue(store.collectionScrolling)

        let targetPageId = store.pages[1].id
        store.send(
            .page(
                .element(
                    id: targetPageId,
                    action: .setStoredImage(shouldDisplayAsSplitPages: true)
                )
            )
        )
        await Task.yield()
        await Task.yield()
        controller.collectionView.layoutIfNeeded()

        XCTAssertEqual(store.pendingSplitResolutions[targetPageId], true)
        XCTAssertEqual(store.pages.count, 3)
    }

    @MainActor
    func testUIArchiveReaderControllerObservesNavigationBarAfterLateNavigationAttachment() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        }
        let controller = UIArchiveReaderController(store: store)

        controller.loadViewIfNeeded()
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.loadViewIfNeeded()

        XCTAssertFalse(navigationController.isNavigationBarHidden)

        store.send(.toggleControlUi(true))
        await Task.yield()

        XCTAssertTrue(navigationController.isNavigationBarHidden)

        store.send(.toggleControlUi(false))
        await Task.yield()

        XCTAssertFalse(navigationController.isNavigationBarHidden)
    }

    @MainActor
    func testUIArchiveReaderControllerKeepsSliderPreviewStateWhenTemporarilyCovered() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderPreviewVisible = true
        initialState.sliderPreviewPageIndex = 1
        initialState.sliderPreviewImageURL = URL(fileURLWithPath: "/tmp/preview.jpg")
        initialState.sliderPreviewLoading = true
        initialState.sliderThumbnailJobId = 42
        initialState.sliderThumbnailJobsById = [42: "archive"]
        initialState.sliderReadyThumbnailPages = Set([1, 2])

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        }
        let controller = UIArchiveReaderController(store: store)

        controller.loadViewIfNeeded()
        controller.cleanupSliderPreviewResourcesIfNeeded(movingFromParent: false, beingDismissed: false)
        await Task.yield()

        XCTAssertTrue(store.sliderPreviewVisible)
        XCTAssertEqual(store.sliderPreviewPageIndex, 1)
        XCTAssertEqual(store.sliderPreviewImageURL, URL(fileURLWithPath: "/tmp/preview.jpg"))
        XCTAssertTrue(store.sliderPreviewLoading)
        XCTAssertEqual(store.sliderThumbnailJobId, 42)
        XCTAssertEqual(store.sliderThumbnailJobsById, [42: "archive"])
        XCTAssertEqual(store.sliderReadyThumbnailPages, Set([1, 2]))
    }

    @MainActor
    func testUIArchiveReaderControllerCleansSliderPreviewStateWhenDismissed() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderPreviewVisible = true
        initialState.sliderPreviewPageIndex = 1
        initialState.sliderPreviewImageURL = URL(fileURLWithPath: "/tmp/preview.jpg")
        initialState.sliderPreviewLoading = true
        initialState.sliderThumbnailJobId = 42
        initialState.sliderThumbnailJobsById = [42: "archive"]
        initialState.sliderReadyThumbnailPages = Set([1, 2])

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        }
        let controller = UIArchiveReaderController(store: store)

        controller.loadViewIfNeeded()
        controller.cleanupSliderPreviewResourcesIfNeeded(movingFromParent: true)
        await Task.yield()

        XCTAssertFalse(store.sliderPreviewVisible)
        XCTAssertNil(store.sliderPreviewPageIndex)
        XCTAssertNil(store.sliderPreviewImageURL)
        XCTAssertFalse(store.sliderPreviewLoading)
        XCTAssertNil(store.sliderThumbnailJobId)
        XCTAssertTrue(store.sliderThumbnailJobsById.isEmpty)
        XCTAssertTrue(store.sliderReadyThumbnailPages.isEmpty)
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
    func testSliderPreviewQueuedResponseStoresJobId() async throws {
        configureReaderDefaults()
        try await configureFinishedThumbnailPolling(jobId: 42)
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: 42,
                    message: nil,
                    operation: "generate_page_thumbnails",
                    success: "1"
                )
            )
        ) {
            $0.sliderThumbnailJobId = 42
        }
        await store.receive(.pollSliderPreviewThumbnailJob(42))
        await store.receive(
            .sliderPreviewThumbnailJobStatus(
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [:],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobId = nil
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
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
    func testSliderPreviewQueuedResponseUsesUniqueArchivePageCountWhenPagesAreSplit() async throws {
        configureReaderDefaults()
        try await configureFinishedThumbnailPolling(jobId: 42)
        var initialState = makeState(progress: 2)
        initialState.pages = makeSplitPageStates()
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailsQueued(
                PageThumbnailQueueResponse(
                    job: 42,
                    message: nil,
                    operation: "generate_page_thumbnails",
                    success: "1"
                )
            )
        ) {
            $0.sliderThumbnailJobId = 42
        }
        await store.receive(.pollSliderPreviewThumbnailJob(42))
        await store.receive(
            .sliderPreviewThumbnailJobStatus(
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [:],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobId = nil
            $0.sliderReadyThumbnailPages = Set([1, 2, 3])
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
                    success: "1"
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testTankSliderPreviewJobStatusMapsSourcePagesToReaderPages() async {
        configureReaderDefaults()
        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives(secondPageCount: 2)
        var initialState = makeState(archiveId: tankId, progress: 1)
        initialState.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
        initialState.sliderThumbnailJobId = 41
        initialState.sliderThumbnailJobsById = [
            41: "first",
            42: "second"
        ]
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .tankSliderPreviewThumbnailJobStatus(
                42,
                "second",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "active",
                    notes: [
                        "1": .string("processed")
                    ],
                    error: ""
                )
            )
        ) {
            $0.sliderReadyThumbnailPages = Set([3])
        }

        await store.send(
            .tankSliderPreviewThumbnailJobStatus(
                42,
                "second",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [
                        "1": .string("processed")
                    ],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobsById = [41: "first"]
            $0.sliderReadyThumbnailPages = Set([3, 4])
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
        await store.receive(.loadSliderPreview(1))

        await store.send(.sliderDragChanged(3)) {
            $0.sliderDraftIndex = 3
            $0.sliderPreviewPageIndex = 3
        }
        await store.receive(.loadSliderPreview(3))
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
        state.sliderThumbnailJobId = 42
        state.sliderThumbnailJobsById = [42: "archive"]
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
        XCTAssertNil(state.sliderThumbnailJobId)
        XCTAssertTrue(state.sliderThumbnailJobsById.isEmpty)
        XCTAssertTrue(state.sliderReadyThumbnailPages.isEmpty)
    }
}

private func configureReaderDefaults(
    readDirection: ReadDirection = .leftRight,
    doublePageLayout: Bool = false,
    autoPageInterval: Double = 5,
    splitWideImage: Bool = false,
    splitPiorityLeft: Bool = false
) {
    UserDefaults.standard.set(readDirection.rawValue, forKey: SettingsKey.readDirection)
    UserDefaults.standard.set(doublePageLayout, forKey: SettingsKey.doublePageLayout)
    UserDefaults.standard.set(autoPageInterval, forKey: SettingsKey.autoPageInterval)
    UserDefaults.standard.set(splitWideImage, forKey: SettingsKey.splitWideImage)
    UserDefaults.standard.set(splitPiorityLeft, forKey: SettingsKey.splitPiorityLeft)
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

private func configureReadyThumbnailQueue(
    archiveId: String = "archive"
) async throws {
    try await configureVerifiedClient()

    stubReadyThumbnailQueue(archiveId: archiveId)
}

private func readyThumbnailQueueResponse() -> PageThumbnailQueueResponse {
    PageThumbnailQueueResponse(
        job: nil,
        message: "No job queued, all thumbnails already exist.",
        operation: "generate_page_thumbnails",
        success: "1"
    )
}

private func stubReadyThumbnailQueue(
    archiveId: String = "archive"
) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/files/thumbnails")
            && isMethodPOST()) { _ in
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

private func configureFinishedThumbnailPolling(
    jobId: Int
) async throws {
    try await configureVerifiedClient()

    stub(condition: isHost("localhost")
            && isPath("/api/minion/\(jobId)")
            && isMethodGET()) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "task": "generate_page_thumbnails",
              "state": "finished",
              "notes": {},
              "error": ""
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubArchiveThumbnailUpdate(archiveId: String, page _: Int) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/thumbnail")
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: Data("OK".utf8), statusCode: 200, headers: nil)
    }
}

private func stubReaderArchiveThumbnail(archiveId: String, data: Data) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/thumbnail")
            && containsQueryParams(["no_fallback": "true", "page": "0"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: data, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
    }
}

private func stubTankoubonThumbnailUpdate(tankId: String, page: Int) {
    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(tankId)/thumbnail")
            && containsQueryParams(["page": "\(page)"])
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "operation": "update_tankoubon_thumbnail",
              "success": 1,
              "new_thumbnail": "thumb.jpg"
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubReaderTankoubonThumbnail(tankId: String, data: Data) {
    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(tankId)/thumbnail")
            && containsQueryParams(["no_fallback": "true"])
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        HTTPStubsResponse(data: data, statusCode: 200, headers: ["Content-Type": "image/png"])
    }
}

private func stubArchiveProgressUpdate(
    archiveId: String,
    progress: Int,
    expectation: XCTestExpectation
) {
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/progress/\(progress)")
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        expectation.fulfill()
        return HTTPStubsResponse(data: Data("OK".utf8), statusCode: 200, headers: nil)
    }
}

private func stubTankoubonProgressUpdate(
    tankId: String,
    progress: Int,
    expectation: XCTestExpectation
) {
    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(tankId)/progress/\(progress)")
            && isMethodPUT()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { _ in
        expectation.fulfill()
        return HTTPStubsResponse(
            data: Data("""
            {
              "id": "\(tankId)",
              "operation": "update_tank_progress",
              "page": \(progress),
              "lastreadtime": 123943543,
              "success": 1
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func makeInMemoryDatabase() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
}

@MainActor
private func makeTestStore(
    initialState: ArchiveReaderFeature.State,
    configureDependencies: ((inout DependencyValues) -> Void)? = nil
) -> TestStoreOf<ArchiveReaderFeature> {
    let store = TestStore(initialState: initialState) {
        ArchiveReaderFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        configureDependencies?(&$0)
    }
    store.timeout = .seconds(5)
    return store
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

private typealias SourceArchiveFixture = (id: String, pages: [String])

private func makeTankSourceArchives(secondPageCount: Int = 1) -> [SourceArchiveFixture] {
    [
        (
            id: "first",
            pages: [
                "./api/archives/first/page?path=first/001.jpg",
                "./api/archives/first/page?path=first/002.jpg"
            ]
        ),
        (
            id: "second",
            pages: Array([
                "./api/archives/second/page?path=second/001.jpg",
                "./api/archives/second/page?path=second/002.jpg"
            ].prefix(secondPageCount))
        )
    ]
}

private func readyThumbnailQueueResults(
    for sourceArchives: [SourceArchiveFixture]
) -> [SliderPreviewThumbnailQueueResult] {
    sourceArchives.map {
        SliderPreviewThumbnailQueueResult(
            archiveId: $0.id,
            response: readyThumbnailQueueResponse()
        )
    }
}

private func stubReadyThumbnailQueues(for sourceArchives: [SourceArchiveFixture]) {
    for sourceArchive in sourceArchives {
        stubReadyThumbnailQueue(archiveId: sourceArchive.id)
    }
}

private func makeExtractedPages(count: Int, archiveId: String = "archive") -> [ReaderExtractedPage] {
    (1...count).map {
        ReaderExtractedPage(archiveId: archiveId, path: "p\($0)", archivePageNumber: $0)
    }
}

private func makeExtractedPages(
    sourceArchives: [SourceArchiveFixture]
) -> [ReaderExtractedPage] {
    sourceArchives.flatMap { sourceArchive in
        sourceArchive.pages.enumerated().map { index, page in
            ReaderExtractedPage(
                archiveId: sourceArchive.id,
                path: page,
                archivePageNumber: index + 1
            )
        }
    }
}

private func stubTankoubonFull(tankId: String, archiveIds: [String]) {
    let archiveBody = archiveIds
        .map { "\"\($0)\"" }
        .joined(separator: ",")

    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(tankId)/full")
            && isMethodGET()) { _ in
        HTTPStubsResponse(
            data: Data("""
            {
              "result": {
                "id": "\(tankId)",
                "name": "Tank",
                "archives": [\(archiveBody)]
              },
              "total": \(archiveIds.count),
              "filtered": \(archiveIds.count)
            }
            """.utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func stubExtractArchive(archiveId: String, pages: [String]) {
    let pageBody = pages
        .map { "\"\($0)\"" }
        .joined(separator: ",")

    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/extract")
            && isMethodPOST()) { _ in
        HTTPStubsResponse(
            data: Data("{\"pages\":[\(pageBody)]}".utf8),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func loadedPageState(
    archiveId: String,
    pageId: String,
    pageNumber: Int,
    pageMode: PageMode
) -> PageFeature.State {
    var state = PageFeature.State(
        archiveId: archiveId,
        pageId: pageId,
        pageNumber: pageNumber,
        pageMode: pageMode
    )
    state.imageLoaded = true
    return state
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

private func makePageStates(
    archiveId: String,
    sourceArchives: [SourceArchiveFixture]
) -> IdentifiedArrayOf<PageFeature.State> {
    var globalPageNumber = 0
    let pageStates = sourceArchives.flatMap { sourceArchive in
        sourceArchive.pages.enumerated().map { index, page in
            globalPageNumber += 1
            return PageFeature.State(
                archiveId: archiveId,
                pageId: String(page.dropFirst(1)),
                pageNumber: globalPageNumber,
                sourceArchiveId: sourceArchive.id,
                sourcePageNumber: index + 1
            )
        }
    }
    return IdentifiedArray(uniqueElements: pageStates)
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
