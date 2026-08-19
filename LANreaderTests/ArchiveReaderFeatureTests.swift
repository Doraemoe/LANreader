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
        UserDefaults.standard.removeObject(forKey: SettingsKey.fitPageWidth)
        UserDefaults.standard.removeObject(forKey: SettingsKey.autoPageInterval)
        UserDefaults.standard.removeObject(forKey: SettingsKey.splitWideImage)
        UserDefaults.standard.removeObject(forKey: SettingsKey.splitPiorityLeft)
        UserDefaults.standard.removeObject(forKey: SettingsKey.restartFinished)
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

    @MainActor
    func testUIPageCellFitWidthAspectRatio() {
        XCTAssertEqual(
            UIPageCell.fitWidthAspectRatio(for: CGSize(width: 1_000, height: 1_500)),
            1.5
        )
        XCTAssertNil(UIPageCell.fitWidthAspectRatio(for: CGSize(width: 0, height: 1_500)))
    }

    func testReaderPageLayoutValidatedAspectRatio() {
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(nil), ReaderPageLayout.defaultAspectRatio)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(0), ReaderPageLayout.defaultAspectRatio)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(-1), ReaderPageLayout.defaultAspectRatio)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(.nan), ReaderPageLayout.defaultAspectRatio)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(.infinity), ReaderPageLayout.defaultAspectRatio)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(0.01), 0.01)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(100), 100)
        XCTAssertEqual(ReaderPageLayout.validatedAspectRatio(1.6), 1.6)
    }

    func testReaderPageLayoutAspectRatioForSize() {
        XCTAssertEqual(ReaderPageLayout.aspectRatio(for: CGSize(width: 1_000, height: 1_400)), 1.4)
        XCTAssertNil(ReaderPageLayout.aspectRatio(for: CGSize(width: 0, height: 1_400)))
        XCTAssertNil(ReaderPageLayout.aspectRatio(for: CGSize(width: 1_000, height: 0)))
    }

    func testReaderPageLayoutSplitAspectRatioDoublesSource() {
        // A split page shows half the source width at the same height.
        XCTAssertEqual(ReaderPageLayout.splitAspectRatio(for: 0.7), 1.4)
    }

    func testReaderPageLayoutMedianAspectRatio() {
        XCTAssertNil(ReaderPageLayout.medianAspectRatio([]))
        XCTAssertNil(ReaderPageLayout.medianAspectRatio([0, -1, .nan]))
        XCTAssertEqual(ReaderPageLayout.medianAspectRatio([1.5]), 1.5)
        XCTAssertEqual(ReaderPageLayout.medianAspectRatio([1.8, 1.2, 1.5]), 1.5)
        XCTAssertEqual(ReaderPageLayout.medianAspectRatio([1.0, 2.0, 1.4, 1.6]), 1.6)
    }

    func testReaderPageLayoutItemHeight() {
        XCTAssertEqual(ReaderPageLayout.itemHeight(width: 100, aspectRatio: 1.4), 140)
        XCTAssertEqual(ReaderPageLayout.itemHeight(width: 100, aspectRatio: 1.406), 141)
        // Long-strip webtoon pages must keep their full-width rendered height.
        XCTAssertEqual(ReaderPageLayout.itemHeight(width: 100, aspectRatio: 20), 2_000)
        // Unmeasured pages fall back to the default ratio rather than collapsing to zero height.
        XCTAssertEqual(ReaderPageLayout.itemHeight(width: 100, aspectRatio: nil), 140)
        XCTAssertEqual(ReaderPageLayout.itemHeight(width: 0, aspectRatio: 1.4), 0)
    }

    func testReaderPositioningFinishedMath() {
        // Progress is one-based, so an archive counts as finished only at the last page.
        XCTAssertTrue(ReaderPositioning.isFinished(progress: 5, archivePageCount: 5))
        XCTAssertFalse(ReaderPositioning.isFinished(progress: 4, archivePageCount: 5))
        XCTAssertFalse(ReaderPositioning.isFinished(progress: 6, archivePageCount: 5))
        XCTAssertFalse(ReaderPositioning.isFinished(progress: 0, archivePageCount: 0))
    }

    func testReaderPositioningRestartFinishedMath() {
        // Finished archive restarts when the setting is on.
        XCTAssertEqual(
            ReaderPositioning.initialPageIndex(
                progress: 5,
                pageCount: 5,
                fromStart: false,
                restartFinishedArchive: true,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            0
        )
        // Partially read archive still resumes where it left off.
        XCTAssertEqual(
            ReaderPositioning.initialPageIndex(
                progress: 4,
                pageCount: 5,
                fromStart: false,
                restartFinishedArchive: false,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            3
        )
        // Setting off keeps the existing resume behaviour for a finished archive.
        XCTAssertEqual(
            ReaderPositioning.initialPageIndex(
                progress: 5,
                pageCount: 5,
                fromStart: false,
                restartFinishedArchive: false,
                readDirection: .leftRight,
                doublePageLayout: false
            ),
            4
        )
        // Restarting still honours double-page spread alignment.
        XCTAssertEqual(
            ReaderPositioning.initialPageIndex(
                progress: 6,
                pageCount: 6,
                fromStart: false,
                restartFinishedArchive: true,
                readDirection: .rightLeft,
                doublePageLayout: true
            ),
            1
        )
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

    func testSliderPreviewPositioningAccountsForChapterMenuInset() {
        XCTAssertEqual(
            SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: 2,
                pageCount: 5,
                track: SliderPreviewTrackGeometry(
                    rowWidth: 320,
                    sliderHorizontalPadding: 16,
                    bubbleWidth: 100,
                    leadingInset: 54
                ),
                isRightToLeft: false
            ),
            137,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: 2,
                pageCount: 5,
                track: SliderPreviewTrackGeometry(
                    rowWidth: 320,
                    sliderHorizontalPadding: 16,
                    bubbleWidth: 100,
                    trailingInset: 54
                ),
                isRightToLeft: true
            ),
            83,
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

        await store.send(.finishExtracting(makeExtractedPages(count: 5), nil)) {
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
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingRestoresSavedProgressAndQueuesInitialScroll() async throws {
        configureReaderDefaults()
        try await configureReadyThumbnailQueue()
        let store = makeTestStore(initialState: makeState(progress: 3))

        await store.send(.finishExtracting(makeExtractedPages(count: 5), nil)) {
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
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingFromStartStartsAtFirstPage() async throws {
        configureReaderDefaults()
        try await configureReadyThumbnailQueue()
        let store = makeTestStore(initialState: makeState(progress: 4, fromStart: true))

        await store.send(.finishExtracting(makeExtractedPages(count: 5), nil)) {
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
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingRestartsFinishedArchiveWhenSettingEnabled() async throws {
        configureReaderDefaults(restartFinished: true)
        try await configureReadyThumbnailQueue()
        let store = makeTestStore(
            initialState: makeState(progress: 5, archivePageCount: 5, restartFinished: true)
        )

        await store.send(.finishExtracting(makeExtractedPages(count: 5), nil)) {
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
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingUsesArchiveMetadataToDetermineFinishedState() async throws {
        configureReaderDefaults(restartFinished: true)
        try await configureReadyThumbnailQueue()
        let store = makeTestStore(initialState: makeState(progress: 5, restartFinished: true))

        await store.send(.finishExtracting(makeExtractedPages(count: 5), nil)) {
            $0.pages = makePageStates(count: 5)
            $0.currentPageIndex = 4
            $0.controlUiHidden = true
        }
        await store.receive(.requestJump(4, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 4,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingKeepsFinishedProgressWhenRestartDisabled() async throws {
        configureReaderDefaults()
        try await configureReadyThumbnailQueue()
        let store = makeTestStore(initialState: makeState(progress: 5, archivePageCount: 5))

        await store.send(.finishExtracting(makeExtractedPages(count: 5), nil)) {
            $0.pages = makePageStates(count: 5)
            $0.currentPageIndex = 4
            $0.controlUiHidden = true
        }
        await store.receive(.requestJump(4, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 4,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4, 5])
        }
    }

    @MainActor
    func testFinishExtractingClampsOutOfRangeProgress() async throws {
        configureReaderDefaults(restartFinished: true)
        try await configureReadyThumbnailQueue()
        let store = makeTestStore(initialState: makeState(progress: 99, restartFinished: true))

        await store.send(.finishExtracting(makeExtractedPages(count: 4), nil)) {
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
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testExtractTankoubonExtractsUnderlyingArchivesAndAggregatesManualAndDefaultChapters() async throws {
        configureReaderDefaults()
        try await configureVerifiedClient()

        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives(secondPageCount: 2)
        let extractedPages = makeExtractedPages(sourceArchives: sourceArchives)
        let chapterFixture = makeTankoubonChapterFixture(tankId: tankId)

        stubTankoubonReader(
            tankId: tankId,
            sourceArchives: sourceArchives,
            sourceTOCs: chapterFixture.sourceTOCs
        )

        let database = try makeInMemoryDatabase()
        let store = makeTestStore(initialState: makeState(archiveId: tankId, progress: 2)) {
            $0.appDatabase = database
        }

        await store.send(.extractArchive) {
            $0.extracting = true
        }
        await store.receive(
            .finishExtracting(
                extractedPages,
                chapterFixture.metadata
            )
        ) {
            $0.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
            $0.currentPageIndex = 1
            $0.controlUiHidden = true
            $0.extracting = false
            $0.currentTankoubonDetails = chapterFixture.metadata
            $0.allArchives[id: tankId]?.withLock {
                $0.toc = chapterFixture.expectedChapters
            }
        }
        XCTAssertEqual(store.state.chapters, chapterFixture.expectedChapters)
        await store.receive(.requestJump(1, source: .initialRestore)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 1,
                source: .initialRestore,
                animated: false
            )
        }
        await store.receive(.primePageAspectRatios)
        await store.receive(.prepareSliderPreviewThumbnails)
        await store.receive(
            .sliderPreviewThumbnailsQueued(readyThumbnailQueueResults(for: sourceArchives))
        ) {
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
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
            .sliderPreviewThumbnailsQueued(readyThumbnailQueueResults(for: sourceArchives))
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
    func testVisiblePageChangedUpdatesProgressAndClearsNewFlag() async throws {
        configureReaderDefaults()
        let database = try makeInMemoryDatabase()
        var cache = ArchiveCache(
            id: "archive",
            title: "Archive",
            tags: "",
            thumbnail: nil,
            cached: true,
            totalPages: 3,
            toc: nil,
            lastUpdate: Date(timeIntervalSince1970: 1)
        )
        try database.saveCache(&cache)
        var initialState = makeState(progress: 0, cached: true, isNew: true)
        initialState.pages = makePageStates(count: 3)
        let store = makeTestStore(initialState: initialState) {
            $0.appDatabase = database
        }

        await store.send(.visiblePageChanged(1)) {
            $0.currentPageIndex = 1
            $0.allArchives[id: "archive"]?.withLock {
                $0.progress = 2
                $0.isNew = false
            }
        }
        await store.finish()

        XCTAssertEqual(try database.readCache("archive")?.progress, 2)
    }

    @MainActor
    func testVisiblePageChangedDoesNotClearNewFlagForTankArchive() async throws {
        configureReaderDefaults()

        let tankId = "TANK_1783084742"
        let sourceArchives = makeTankSourceArchives()
        let database = try makeInMemoryDatabase()
        var cache = ArchiveCache(
            id: tankId,
            title: "Tank",
            tags: "",
            thumbnail: nil,
            cached: true,
            totalPages: 3,
            toc: nil,
            lastUpdate: Date(timeIntervalSince1970: 1)
        )
        try database.saveCache(&cache)
        var initialState = makeState(archiveId: tankId, progress: 0, cached: true, isNew: true)
        initialState.pages = makePageStates(archiveId: tankId, sourceArchives: sourceArchives)
        let store = makeTestStore(initialState: initialState) {
            $0.appDatabase = database
        }

        await store.send(.visiblePageChanged(1)) {
            $0.currentPageIndex = 1
            $0.allArchives[id: tankId]?.withLock {
                $0.progress = 2
            }
        }
        await store.finish()

        XCTAssertEqual(try database.readCache(tankId)?.progress, 2)
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
    func testNavigateNextAtFinalEvenSpreadDoesNothing() async {
        configureReaderDefaults(doublePageLayout: true)
        var initialState = makeState(
            progress: 6,
            readDirection: .leftRight,
            doublePageLayout: true
        )
        initialState.pages = makePageStates(count: 6)
        initialState.currentPageIndex = 5
        let store = makeTestStore(initialState: initialState)

        await store.send(.navigate(.next, source: .tap))

        XCTAssertNil(store.state.scrollRequest)
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
    func testStaleScrollRequestAcknowledgementKeepsNewerRequest() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.currentPageIndex = 1
        let store = makeTestStore(initialState: initialState)
        let firstRequest = makeScrollRequest(
            id: 0,
            targetPageIndex: 1,
            source: .slider,
            animated: false
        )
        let newerRequest = makeScrollRequest(
            id: 1,
            targetPageIndex: 2,
            source: .chapter,
            animated: false
        )

        await store.send(.requestJump(1, source: .slider)) {
            $0.scrollRequest = firstRequest
        }
        await store.send(.requestJump(2, source: .chapter)) {
            $0.scrollRequest = newerRequest
        }

        await store.send(.scrollRequestHandled(incrementingUUID(0)))
        XCTAssertEqual(store.state.scrollRequest, newerRequest)

        await store.send(.scrollRequestHandled(incrementingUUID(1))) {
            $0.scrollRequest = nil
        }
    }

    @MainActor
    func testChapterSelectionJumpsToOneBasedPageAfterSplitInsertion() async {
        configureReaderDefaults()
        let chapters = [
            ArchiveChapter(name: "Opening", page: 1),
            ArchiveChapter(name: "Second chapter", page: 3)
        ]
        var initialState = makeState(
            allArchives: [makeArchive(toc: chapters)]
        )
        initialState.pages = makeSplitPageStates()
        let store = makeTestStore(initialState: initialState)

        XCTAssertEqual(store.state.chapters, chapters)

        await store.send(.chapterSelected(3))
        await store.receive(.requestJump(3, source: .chapter)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .chapter,
                animated: false
            )
        }
    }

    @MainActor
    func testCachedTankoubonReaderUsesPersistedChaptersWithoutTankMetadata() async {
        configureReaderDefaults()
        let tankId = "TANK_1783084742"
        let chapters = [
            ArchiveChapter(name: "Opening", page: 1),
            ArchiveChapter(name: "Second chapter", page: 3)
        ]
        var initialState = makeState(
            archiveId: tankId,
            cached: true,
            allArchives: [makeArchive(id: tankId, toc: chapters)]
        )
        initialState.pages = makeSplitPageStates(archiveId: tankId)
        let store = makeTestStore(initialState: initialState)

        XCTAssertNil(store.state.currentTankoubonDetails)
        XCTAssertEqual(store.state.chapters, chapters)

        await store.send(.chapterSelected(3))
        await store.receive(.requestJump(3, source: .chapter)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .chapter,
                animated: false
            )
        }
    }

    @MainActor
    func testLoadCachedRestoresPersistedProgress() async throws {
        configureReaderDefaults()
        let id = "cachedRestoreArchive"
        let cacheFolder = LANraragiService.cachePath!.appendingPathComponent(id, conformingTo: .folder)
        try? FileManager.default.removeItem(at: cacheFolder)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheFolder)
        }
        for page in 1...5 {
            FileManager.default.createFile(
                atPath: cacheFolder.appendingPathComponent("\(page)").path,
                contents: Data()
            )
        }

        let initialState = makeState(archiveId: id, progress: 3, cached: true)
        let store = makeTestStore(initialState: initialState)

        let expectedPages = IdentifiedArray(uniqueElements: (1...5).map {
            PageFeature.State(archiveId: id, pageId: "\($0)", pageNumber: $0, cached: true)
        })

        await store.send(.loadCached) {
            $0.pages = expectedPages
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
        await store.receive(.primePageAspectRatios)
    }

    @MainActor
    func testLoadCachedFromStartIgnoresPersistedProgress() async throws {
        configureReaderDefaults()
        let id = "cachedFromStartArchive"
        let cacheFolder = LANraragiService.cachePath!.appendingPathComponent(id, conformingTo: .folder)
        try? FileManager.default.removeItem(at: cacheFolder)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheFolder)
        }
        for page in 1...5 {
            FileManager.default.createFile(
                atPath: cacheFolder.appendingPathComponent("\(page)").path,
                contents: Data()
            )
        }

        let initialState = makeState(archiveId: id, progress: 3, fromStart: true, cached: true)
        let store = makeTestStore(initialState: initialState)

        let expectedPages = IdentifiedArray(uniqueElements: (1...5).map {
            PageFeature.State(archiveId: id, pageId: "\($0)", pageNumber: $0, cached: true)
        })

        await store.send(.loadCached) {
            $0.pages = expectedPages
            $0.currentPageIndex = 0
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
        await store.receive(.primePageAspectRatios)
    }

    @MainActor
    func testLoadCachedRestartsFinishedArchiveWhenSettingEnabled() async throws {
        configureReaderDefaults(restartFinished: true)
        let id = "cachedRestartFinishedArchive"
        let cacheFolder = LANraragiService.cachePath!.appendingPathComponent(id, conformingTo: .folder)
        try? FileManager.default.removeItem(at: cacheFolder)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheFolder)
        }
        for page in 1...5 {
            FileManager.default.createFile(
                atPath: cacheFolder.appendingPathComponent("\(page)").path,
                contents: Data()
            )
        }

        let initialState = makeState(
            archiveId: id,
            progress: 5,
            cached: true,
            archivePageCount: 5,
            restartFinished: true
        )
        let store = makeTestStore(initialState: initialState)

        let expectedPages = IdentifiedArray(uniqueElements: (1...5).map {
            PageFeature.State(archiveId: id, pageId: "\($0)", pageNumber: $0, cached: true)
        })

        await store.send(.loadCached) {
            $0.pages = expectedPages
            $0.currentPageIndex = 0
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
        await store.receive(.primePageAspectRatios)
    }

    func testArchiveCachePersistsChapters() throws {
        let chapters = [
            ArchiveChapter(name: "Opening", page: 1),
            ArchiveChapter(name: "Second chapter", page: 3)
        ]
        let database = try makeInMemoryDatabase()
        var cache = ArchiveCache(
            id: "archive",
            title: "Archive",
            tags: "artist:test",
            thumbnail: nil,
            cached: true,
            totalPages: 5,
            toc: chapters,
            lastUpdate: Date(timeIntervalSince1970: 1)
        )

        try database.saveCache(&cache)

        XCTAssertEqual(try database.readCache(cache.id)?.toc, chapters)
    }

    @MainActor
    func testCachedReadUpdatesCacheGridProgress() async throws {
        configureReaderDefaults()
        let id = "cachedGridProgressArchive"
        let cacheFolder = LANraragiService.cachePath!.appendingPathComponent(id, conformingTo: .folder)
        try? FileManager.default.removeItem(at: cacheFolder)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheFolder)
        }
        for page in 1...5 {
            FileManager.default.createFile(
                atPath: cacheFolder.appendingPathComponent("\(page)").path,
                contents: Data()
            )
        }
        let database = try makeInMemoryDatabase()
        var cache = ArchiveCache(
            id: id,
            title: "Archive",
            tags: "",
            thumbnail: nil,
            cached: true,
            totalPages: 5,
            toc: nil,
            lastUpdate: Date(timeIntervalSince1970: 1)
        )
        try database.saveCache(&cache)
        let cacheStore = TestStore(initialState: CacheFeature.State()) {
            CacheFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = TestClock()
        }
        cacheStore.exhaustivity = .off
        await cacheStore.send(.load)

        let sharedArchive = try XCTUnwrap(cacheStore.state.archives[id: id]?.$archive)
        let readerStore = makeTestStore(
            initialState: ArchiveReaderFeature.State(
                currentArchiveId: id,
                allArchives: [sharedArchive],
                cached: true
            )
        ) {
            $0.appDatabase = database
        }
        readerStore.exhaustivity = .off

        await readerStore.send(.loadCached)
        await readerStore.send(.visiblePageChanged(3))
        await readerStore.finish()

        XCTAssertEqual(try database.readCache(id)?.progress, 4)
        XCTAssertEqual(cacheStore.state.archives[id: id]?.archive.progress, 4)
    }

    @MainActor
    func testCacheFeatureLoadRestoresChapters() async throws {
        let chapters = [
            ArchiveChapter(name: "Opening", page: 1),
            ArchiveChapter(name: "Second chapter", page: 3)
        ]
        let database = try makeInMemoryDatabase()
        var cache = ArchiveCache(
            id: "archive",
            title: "Archive",
            tags: "artist:test",
            thumbnail: nil,
            cached: true,
            totalPages: 5,
            toc: chapters,
            lastUpdate: Date(timeIntervalSince1970: 1)
        )
        try database.saveCache(&cache)
        let clock = TestClock()
        let store = TestStore(initialState: CacheFeature.State()) {
            CacheFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = clock
        }

        await store.send(.load) {
            $0.archives = [
                GridFeature.State(
                    archive: Shared(value: cache.toArchiveItem()),
                    cached: true
                )
            ]
        }
        await store.receive(.refreshProgress)
        await clock.advance(by: .seconds(2))
        await store.finish()
    }

    @MainActor
    func testPageAspectRatiosPrimedAssignsRatiosAndMedianEstimate() async {
        configureReaderDefaults(readDirection: .upDown)
        var initialState = makeState(readDirection: .upDown)
        initialState.pages = makePageStates(count: 3)
        let store = makeTestStore(initialState: initialState)

        await store.send(.pageAspectRatiosPrimed([1: 1.2, 2: 1.5, 3: 1.8])) {
            $0.pages[0].imageAspectRatio = 1.2
            $0.pages[1].imageAspectRatio = 1.5
            $0.pages[2].imageAspectRatio = 1.8
            $0.estimatedPageAspectRatio = 1.5
        }
    }

    @MainActor
    func testPageAspectRatiosPrimedLeavesAlreadyMeasuredPagesUntouched() async {
        configureReaderDefaults(readDirection: .upDown)
        var initialState = makeState(readDirection: .upDown)
        initialState.pages = makePageStates(count: 2)
        initialState.pages[0].imageAspectRatio = 2.0
        let store = makeTestStore(initialState: initialState)

        await store.send(.pageAspectRatiosPrimed([1: 1.2, 2: 1.4])) {
            $0.pages[1].imageAspectRatio = 1.4
            $0.estimatedPageAspectRatio = 2.0
        }
    }

    @MainActor
    func testPrimePageAspectRatiosWithoutPagesDoesNothing() async {
        configureReaderDefaults(readDirection: .upDown)
        let store = makeTestStore(initialState: makeState(readDirection: .upDown))

        await store.send(.primePageAspectRatios)
    }

    @MainActor
    func testSplitPageResolutionCopiesAspectRatioToInsertedSibling() async {
        configureReaderDefaults(splitWideImage: true)
        var initialState = makeState(progress: 1)
        initialState.$splitImage = SharedReader(value: true)
        initialState.pages = makePageStates(count: 2)
        initialState.pages[0].imageAspectRatio = 0.7
        initialState.currentPageIndex = 0
        let splittingPageId = initialState.pages[0].id
        let store = makeTestStore(initialState: initialState)

        await store.send(.page(.element(
            id: splittingPageId,
            action: .storedImageResolved(shouldDisplayAsSplitPages: true)
        ))) {
            $0.pages[0].pageMode = .right
            $0.pages[0].imageLoaded = true
            var sibling = loadedPageState(
                archiveId: "archive",
                pageId: "1",
                pageNumber: 1,
                pageMode: .left
            )
            sibling.imageAspectRatio = 0.7
            $0.pages.insert(sibling, at: 1)
            $0.estimatedPageAspectRatio = 0.7
        }

        // A split page shows half the source width, so it renders twice as tall relative to its width.
        XCTAssertEqual(store.state.pages[0].displayAspectRatio, 1.4)
        XCTAssertEqual(store.state.pages[1].displayAspectRatio, 1.4)
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
        await waitForScrollRequestToFinish(store)

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
    func testUIPageCollectionShiftsSpreadItemsWhenToggledFromSecondPage() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 1
        let expectedItems = [ReaderCollectionItem.spreadPlaceholder]
            + initialState.pages.map { ReaderCollectionItem.page($0.id) }

        let store = Store(initialState: initialState) {
            ArchiveReaderFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }
        let controller = UIPageCollectionController(store: store)

        controller.loadViewIfNeeded()
        await Task.yield()
        await store.send(.toggleDoublePageLayout).finish()
        await Task.yield()
        await Task.yield()
        await waitForScrollRequestToFinish(store)

        XCTAssertEqual(store.spreadPairingOffset, 1)
        let collectionItems = controller.dataSource.snapshot().itemIdentifiers
        XCTAssertEqual(collectionItems, expectedItems)
        XCTAssertEqual(collectionItems[2], .page(initialState.pages[1].id))
        XCTAssertEqual(collectionItems[3], .page(initialState.pages[2].id))
        XCTAssertNil(store.scrollRequest)
    }

    @MainActor
    func testUIPageCollectionRepeatedDoublePageTogglesStayAlignedToSpreadBoundary() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 1

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

        store.send(.toggleDoublePageLayout)
        store.send(.toggleDoublePageLayout)
        store.send(.toggleDoublePageLayout)
        await Task.yield()
        await Task.yield()
        await Task.yield()
        await waitForScrollRequestToFinish(store)
        controller.collectionView.layoutIfNeeded()

        let viewportWidth = controller.collectionView.bounds.width
        let remainder = controller.collectionView.contentOffset.x
            .truncatingRemainder(dividingBy: viewportWidth)
        XCTAssertEqual(remainder, 0, accuracy: 1)
        XCTAssertNil(store.scrollRequest)
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
            .sliderPreviewThumbnailsQueued([queuedThumbnailQueueResult()])
        ) {
            $0.sliderThumbnailJobsById = [42: "archive"]
        }
        await store.receive(.pollSliderPreviewThumbnailJob(42, archiveId: "archive"))
        await store.receive(
            .sliderPreviewThumbnailJobStatus(
                42,
                "archive",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [:],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobsById = [:]
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
            .sliderPreviewThumbnailsQueued([queuedThumbnailQueueResult()])
        ) {
            $0.sliderThumbnailJobsById = [42: "archive"]
        }
        await store.receive(.pollSliderPreviewThumbnailJob(42, archiveId: "archive"))
        await store.receive(
            .sliderPreviewThumbnailJobStatus(
                42,
                "archive",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [:],
                    error: ""
                )
            )
        ) {
            $0.sliderThumbnailJobsById = [:]
            $0.sliderReadyThumbnailPages = Set([1, 2, 3])
        }
    }

    @MainActor
    func testSliderPreviewFinishedJobStatusMarksReadyPages() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makePageStates(count: 4)
        initialState.sliderThumbnailJobsById = [42: "archive"]
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailJobStatus(
                42,
                "archive",
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
            $0.sliderThumbnailJobsById = [:]
            $0.sliderReadyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testSliderPreviewFinishedJobStatusUsesUniqueArchivePageCountWhenPagesAreSplit() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 2)
        initialState.pages = makeSplitPageStates()
        initialState.sliderThumbnailJobsById = [42: "archive"]
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailJobStatus(
                42,
                "archive",
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
            $0.sliderThumbnailJobsById = [:]
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
            .sliderPreviewThumbnailsQueued([readyThumbnailQueueResult()])
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
        initialState.sliderThumbnailJobsById = [
            41: "first",
            42: "second"
        ]
        let store = makeTestStore(initialState: initialState)

        await store.send(
            .sliderPreviewThumbnailJobStatus(
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
            .sliderPreviewThumbnailJobStatus(
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
        state.spreadPairingOffset = 1
        state.fromStart = true
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
        state.sliderThumbnailJobsById = [42: "archive"]
        state.sliderReadyThumbnailPages = Set([1, 2])

        ArchiveReaderFeature().resetState(state: &state)

        XCTAssertTrue(state.pages.isEmpty)
        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertEqual(state.spreadPairingOffset, 0)
        XCTAssertFalse(state.fromStart)
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
        XCTAssertTrue(state.sliderThumbnailJobsById.isEmpty)
        XCTAssertTrue(state.sliderReadyThumbnailPages.isEmpty)
    }

    @MainActor
    func testToggleDoublePageLayoutEnablesLayoutAndJumpsToSpreadCanonicalPage() async {
        configureReaderDefaults()
        var initialState = makeState(progress: 3)
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 2
        let store = makeTestStore(initialState: initialState)

        await store.send(.toggleDoublePageLayout) {
            $0.$doublePageLayout.withLock { $0 = true }
        }
        await store.receive(.requestJump(3, source: .layoutChange)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 3,
                source: .layoutChange,
                animated: false
            )
        }
    }

    @MainActor
    func testToggleDoublePageLayoutMakesCurrentLTRPageStartOfShiftedSpread() async {
        configureReaderDefaults(readDirection: .leftRight)
        var initialState = makeState(progress: 2, readDirection: .leftRight)
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 1
        let store = makeTestStore(initialState: initialState)

        await store.send(.toggleDoublePageLayout) {
            $0.spreadPairingOffset = 1
            $0.$doublePageLayout.withLock { $0 = true }
        }
        await store.receive(.requestJump(2, source: .layoutChange)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 2,
                source: .layoutChange,
                animated: false
            )
        }
    }

    @MainActor
    func testToggleDoublePageLayoutMakesCurrentRTLPageStartOfShiftedSpread() async {
        configureReaderDefaults(readDirection: .rightLeft)
        var initialState = makeState(progress: 2, readDirection: .rightLeft)
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 1
        let store = makeTestStore(initialState: initialState)

        await store.send(.toggleDoublePageLayout) {
            $0.spreadPairingOffset = 1
            $0.$doublePageLayout.withLock { $0 = true }
        }
        await store.receive(.requestJump(2, source: .layoutChange)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 2,
                source: .layoutChange,
                animated: false
            )
        }
    }

    @MainActor
    func testToggleDoublePageLayoutDisablesLayoutAndKeepsCurrentPage() async {
        configureReaderDefaults(doublePageLayout: true)
        var initialState = makeState(progress: 3, doublePageLayout: true)
        initialState.pages = makePageStates(count: 5)
        initialState.currentPageIndex = 2
        initialState.spreadPairingOffset = 1
        let store = makeTestStore(initialState: initialState)

        await store.send(.toggleDoublePageLayout) {
            $0.spreadPairingOffset = 0
            $0.$doublePageLayout.withLock { $0 = false }
        }
        await store.receive(.requestJump(2, source: .layoutChange)) {
            $0.scrollRequest = makeScrollRequest(
                id: 0,
                targetPageIndex: 2,
                source: .layoutChange,
                animated: false
            )
        }
    }

    @MainActor
    func testToggleDoublePageLayoutIgnoredInVerticalModeAndWhenSplitEnabled() async {
        configureReaderDefaults(readDirection: .upDown)
        var verticalState = makeState(readDirection: .upDown)
        verticalState.pages = makePageStates(count: 4)
        let verticalStore = makeTestStore(initialState: verticalState)
        await verticalStore.send(.toggleDoublePageLayout)

        configureReaderDefaults(splitWideImage: true)
        var splitState = makeState()
        splitState.pages = makePageStates(count: 4)
        splitState.$splitImage = SharedReader(value: true)
        let splitStore = makeTestStore(initialState: splitState)
        await splitStore.send(.toggleDoublePageLayout)
    }
}

@MainActor
private func waitForScrollRequestToFinish(_ store: StoreOf<ArchiveReaderFeature>) async {
    for _ in 0..<100 where store.scrollRequest != nil {
        try? await Task<Never, Never>.sleep(for: .milliseconds(10))
    }
}

private func configureReaderDefaults(
    readDirection: ReadDirection = .leftRight,
    doublePageLayout: Bool = false,
    autoPageInterval: Double = 5,
    splitWideImage: Bool = false,
    splitPiorityLeft: Bool = false,
    restartFinished: Bool = false
) {
    UserDefaults.standard.set(readDirection.rawValue, forKey: SettingsKey.readDirection)
    UserDefaults.standard.set(doublePageLayout, forKey: SettingsKey.doublePageLayout)
    UserDefaults.standard.set(autoPageInterval, forKey: SettingsKey.autoPageInterval)
    UserDefaults.standard.set(splitWideImage, forKey: SettingsKey.splitWideImage)
    UserDefaults.standard.set(splitPiorityLeft, forKey: SettingsKey.splitPiorityLeft)
    UserDefaults.standard.set(restartFinished, forKey: SettingsKey.restartFinished)
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

private func readyThumbnailQueueResult(archiveId: String = "archive") -> SliderPreviewThumbnailQueueResult {
    SliderPreviewThumbnailQueueResult(
        archiveId: archiveId,
        response: readyThumbnailQueueResponse()
    )
}

private func queuedThumbnailQueueResult(
    archiveId: String = "archive",
    jobId: Int = 42
) -> SliderPreviewThumbnailQueueResult {
    SliderPreviewThumbnailQueueResult(
        archiveId: archiveId,
        response: PageThumbnailQueueResponse(
            job: jobId,
            message: nil,
            operation: "generate_page_thumbnails",
            success: "1"
        )
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
    autoPageInterval: Double = 5,
    archivePageCount: Int = 10,
    restartFinished: Bool = false
) -> ArchiveReaderFeature.State {
    let archives = allArchives ?? [
        makeArchive(id: archiveId, progress: progress, isNew: isNew, pageCount: archivePageCount)
    ]
    let state = ArchiveReaderFeature.State(
        currentArchiveId: archiveId,
        allArchives: archives.map { Shared(value: $0) },
        fromStart: fromStart,
        cached: cached
    )
    state.$readDirection = SharedReader(value: readDirection.rawValue)
    state.$doublePageLayout = Shared(value: doublePageLayout)
    state.$autoPageInterval = SharedReader(value: autoPageInterval)
    state.$restartFinished = SharedReader(value: restartFinished)
    return state
}

private func makeArchive(
    id: String = "archive",
    progress: Int = 0,
    isNew: Bool = false,
    pageCount: Int = 10,
    toc: [ArchiveChapter]? = nil
) -> ArchiveItem {
    ArchiveItem(
        id: id,
        name: "Archive \(id)",
        extension: "zip",
        tags: "",
        isNew: isNew,
        progress: progress,
        pagecount: pageCount,
        dateAdded: nil,
        toc: toc
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
        readyThumbnailQueueResult(archiveId: $0.id)
    }
}

private func stubReadyThumbnailQueues(for sourceArchives: [SourceArchiveFixture]) {
    for sourceArchive in sourceArchives {
        stubReadyThumbnailQueue(archiveId: sourceArchive.id)
    }
}

private func stubExtractArchives(for sourceArchives: [SourceArchiveFixture]) {
    for sourceArchive in sourceArchives {
        stubExtractArchive(archiveId: sourceArchive.id, pages: sourceArchive.pages)
    }
}

private func stubTankoubonReader(
    tankId: String,
    sourceArchives: [SourceArchiveFixture],
    sourceTOCs: [[ArchiveChapter]?]
) {
    stubTankoubonFull(
        tankId: tankId,
        archiveIds: sourceArchives.map(\.id),
        tags: "artist:tank",
        fullDataTags: ["artist:first,series:one", "artist:second,series:one"],
        fullDataTOCs: sourceTOCs
    )
    stubExtractArchives(for: sourceArchives)
    stubReadyThumbnailQueues(for: sourceArchives)
}

private func makeTankoubonDetailsMetadata(
    tankId: String,
    toc: [ArchiveChapter]? = nil
) -> TankoubonDetailsMetadata {
    var metadata = TankoubonDetailsMetadata(
        id: tankId,
        name: "Tank",
        tags: "artist:tank",
        includedArchiveTags: "artist:first,series:one,artist:second"
    )
    metadata.toc = toc
    return metadata
}

private struct TankoubonChapterFixture {
    let sourceTOCs: [[ArchiveChapter]?]
    let expectedChapters: [ArchiveChapter]
    let metadata: TankoubonDetailsMetadata
}

private func makeTankoubonChapterFixture(tankId: String) -> TankoubonChapterFixture {
    let sourceTOCs: [[ArchiveChapter]?] = [
        [
            ArchiveChapter(name: "Opening", page: 1),
            ArchiveChapter(name: "First ending", page: 2)
        ],
        [
            ArchiveChapter(name: "Bonus", page: 2),
            ArchiveChapter(name: "Out of range", page: 3)
        ]
    ]
    let expectedChapters = [
        ArchiveChapter(name: "Opening", page: 1),
        ArchiveChapter(name: "First ending", page: 2),
        ArchiveChapter(name: "Source 1", page: 3),
        ArchiveChapter(name: "Bonus", page: 4)
    ]
    return TankoubonChapterFixture(
        sourceTOCs: sourceTOCs,
        expectedChapters: expectedChapters,
        metadata: makeTankoubonDetailsMetadata(tankId: tankId, toc: expectedChapters)
    )
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

private func stubTankoubonFull(
    tankId: String,
    archiveIds: [String],
    tags: String? = nil,
    fullDataTags: [String] = [],
    fullDataTOCs: [[ArchiveChapter]?] = []
) {
    let data = makeTankoubonFullResponseData(
        tankId: tankId,
        archiveIds: archiveIds,
        tags: tags,
        fullDataTags: fullDataTags,
        fullDataTOCs: fullDataTOCs
    )

    stub(condition: isHost("localhost")
            && isPath("/api/tankoubons/\(tankId)/full")
            && isMethodGET()) { _ in
        HTTPStubsResponse(
            data: data,
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
    }
}

private func makeTankoubonFullResponseData(
    tankId: String,
    archiveIds: [String],
    tags: String?,
    fullDataTags: [String],
    fullDataTOCs: [[ArchiveChapter]?]
) -> Data {
    var result: [String: Any] = [
        "id": tankId,
        "name": "Tank",
        "archives": archiveIds
    ]
    if let tags {
        result["tags"] = tags
    }
    if !fullDataTags.isEmpty || !fullDataTOCs.isEmpty {
        result["full_data"] = archiveIds.enumerated().map { index, archiveId in
            makeTankoubonArchiveMetadata(
                id: archiveId,
                index: index,
                tags: fullDataTags,
                tocs: fullDataTOCs
            )
        }
    }
    let response: [String: Any] = [
        "result": result,
        "total": archiveIds.count,
        "filtered": archiveIds.count
    ]
    return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
}

private func makeTankoubonArchiveMetadata(
    id: String,
    index: Int,
    tags: [String],
    tocs: [[ArchiveChapter]?]
) -> [String: Any] {
    var metadata: [String: Any] = [
        "arcid": id,
        "extension": ".zip",
        "isnew": "false",
        "tags": tags.indices.contains(index) ? tags[index] : "",
        "title": "Source \(index)",
        "pagecount": 1,
        "progress": 0
    ]
    if tocs.indices.contains(index), let toc = tocs[index] {
        metadata["toc"] = toc.map { chapter in
            ["name": chapter.name, "page": chapter.page] as [String: Any]
        }
    }
    return metadata
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
