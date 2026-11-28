import XCTest
import ComposableArchitecture
import OHHTTPStubs
import OHHTTPStubsSwift
import os
import UIKit
@testable import LANreader

final class ReaderSliderPreviewLayoutTests: LANreaderTestCase {
    func testSliderPreviewLayoutTracksReaderSize() {
        // A phone in portrait gets the standard bubble.
        XCTAssertEqual(
            ReaderPageLayout.sliderPreviewBubbleLayout(readerSize: CGSize(width: 390, height: 844)),
            ReaderPageLayout.SliderPreviewBubbleLayout(width: 176, imageHeight: 248, rowHeight: 300)
        )
        // On any screen the bubble fits beside the side margins, takes at most half the height and
        // keeps the page shape.
        let sizes = [
            CGSize(width: 320, height: 568), CGSize(width: 844, height: 390), CGSize(width: 382, height: 644),
            CGSize(width: 834, height: 1_194), CGSize(width: 1_366, height: 1_024), CGSize(width: 590, height: 790)
        ]
        for size in sizes {
            let layout = ReaderPageLayout.sliderPreviewBubbleLayout(readerSize: size)
            XCTAssertLessThanOrEqual(layout.width, size.width - 48, "\(size)")
            XCTAssertLessThanOrEqual(layout.imageHeight, size.height / 2 + 1, "\(size)")
            XCTAssertEqual(layout.imageHeight / layout.width, 248 / 176, accuracy: 0.02, "\(size)")
            XCTAssertEqual(layout.rowHeight, layout.imageHeight + 52, "\(size)")
        }
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
}

final class ReaderSliderPreviewTests: LANreaderTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try? FileManager.default.removeItem(at: sliderPreviewsDirectory())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sliderPreviewsDirectory())
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiApiKey)
        HTTPStubs.removeAllStubs()
        super.tearDown()
    }

    /// A Tankoubon page's preview is its source archive's own page thumbnail.
    @MainActor
    func testTankoubonSliderPreviewDownloadsTheSourceArchivePage() async throws {
        try await configureTestServer()
        let requestedPages = stubSliderPreviewThumbnails(archiveId: "source")
        var state = ReaderSliderPreviewFeature.State()
        state.readyThumbnailPages = [8]
        let store = makePreviewTestStore(
            archiveId: "TANK_preview",
            pages: [
                PageFeature.State(
                    archiveId: "TANK_preview", pageId: "8", pageNumber: 8,
                    sourceArchiveId: "source", sourcePageNumber: 4
                )
            ],
            initialState: state
        )

        await store.send(.sliderPreview(.dragStarted)) {
            $0.sliderPreview.dragging = true
            $0.sliderPreview.draftIndex = 0
            $0.sliderPreview.previewVisible = true
            $0.sliderPreview.previewPageIndex = 0
            $0.sliderPreview.previewLoading = true
            $0.sliderPreview.previewStatus = [8: .fetching]
        }
        await store.receive(.sliderPreview(.previewFetched(pageNumber: 8, .stored))) {
            $0.sliderPreview.previewStatus = [8: .stored]
            $0.sliderPreview.previewImageURL = sliderPreviewURL(archiveId: "TANK_preview", pageNumber: 8)
            $0.sliderPreview.previewLoading = false
        }
        XCTAssertEqual(requestedPages.withLock { $0 }, [4])
    }

    /// If checking a thumbnail job fails, the preview must stop waiting for it instead of spinning
    /// forever.
    @MainActor
    func testFailedThumbnailJobStopsTheSliderPreviewSpinner() async throws {
        try await configureTestServer()
        stub(condition: isHost("localhost") && isPath("/api/minion/42") && isMethodGET()) { @Sendable _ in
            HTTPStubsResponse(data: Data(), statusCode: 500, headers: nil)
        }
        var state = ReaderSliderPreviewFeature.State()
        state.thumbnailJobsById = [42: "archive"]
        state.previewVisible = true
        state.previewPageIndex = 1
        state.previewLoading = true
        let store = makePreviewTestStore(
            pages: makePreviewPages(count: 3),
            initialState: state
        ) {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sliderPreview(.pollThumbnailJob(42, archiveId: "archive")))
        await store.receive(\.sliderPreview.thumbnailPollingFailed) {
            $0.sliderPreview.thumbnailJobsById = [:]
            $0.sliderPreview.previewLoading = false
        }
        await store.finish()
    }

    @MainActor
    func testSliderPreviewQueuedResponseStoresJobId() async throws {
        try await configureFinishedThumbnailPolling(jobId: 42)
        stubSliderPreviewThumbnails()
        let store = makePreviewTestStore(pages: makePreviewPages(count: 4), currentPageIndex: 1)

        await store.send(.sliderPreview(.thumbnailsQueued([queuedThumbnailQueueResult()]))) {
            $0.sliderPreview.thumbnailJobsById = [42: "archive"]
        }
        await store.receive(.sliderPreview(.pollThumbnailJob(42, archiveId: "archive")))
        await store.receive(
            .sliderPreview(.thumbnailJobStatus(
                42,
                "archive",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [:],
                    error: ""
                )
            ))
        ) {
            $0.sliderPreview.thumbnailJobsById = [:]
            $0.sliderPreview.readyThumbnailPages = Set([1, 2, 3, 4])
            // A finished job starts the preview downloads.
            $0.sliderPreview.prefetchInFlight = true
        }
        await finishPreviewPrefetch(store)
    }

    @MainActor
    func testPrepareSliderPreviewThumbnailsUsesUniqueArchivePageCountWhenPagesAreSplit() async {
        var initialState = ReaderSliderPreviewFeature.State()
        initialState.readyThumbnailPages = Set([1, 2, 3])
        let store = makePreviewTestStore(
            pages: makeSplitPreviewPages(),
            currentPageIndex: 1,
            initialState: initialState
        )

        await store.send(.sliderPreview(.prepareThumbnails))
    }

    @MainActor
    func testSliderPreviewFinishedJobStatusUsesUniqueArchivePageCountWhenPagesAreSplit() async {
        var initialState = ReaderSliderPreviewFeature.State()
        initialState.thumbnailJobsById = [42: "archive"]
        // Background preview downloads are off, so the test sees only which pages become ready.
        initialState.prefetchStopped = true
        let store = makePreviewTestStore(
            pages: makeSplitPreviewPages(),
            currentPageIndex: 1,
            initialState: initialState
        )

        await store.send(
            .sliderPreview(.thumbnailJobStatus(
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
            ))
        ) {
            $0.sliderPreview.thumbnailJobsById = [:]
            $0.sliderPreview.readyThumbnailPages = Set([1, 2, 3])
        }
    }

    @MainActor
    func testSliderPreviewAlreadyGeneratedMarksAllPagesReady() async {
        var initialState = ReaderSliderPreviewFeature.State()
        // Background preview downloads are off, so the test sees only which pages become ready.
        initialState.prefetchStopped = true
        let store = makePreviewTestStore(
            pages: makePreviewPages(count: 4),
            currentPageIndex: 1,
            initialState: initialState
        )

        await store.send(.sliderPreview(.thumbnailsQueued([readyThumbnailQueueResult()]))) {
            $0.sliderPreview.readyThumbnailPages = Set([1, 2, 3, 4])
        }
    }

    @MainActor
    func testTankSliderPreviewJobStatusMapsSourcePagesToReaderPages() async {
        let tankId = "TANK_1783084742"
        var initialState = ReaderSliderPreviewFeature.State()
        initialState.thumbnailJobsById = [41: "first", 42: "second"]
        // Background preview downloads are off, so the test sees only which pages become ready.
        initialState.prefetchStopped = true
        let pages = [("first", 1), ("first", 2), ("second", 1), ("second", 2)].enumerated().map {
            PageFeature.State(
                archiveId: tankId, pageId: "\($0 + 1)", pageNumber: $0 + 1,
                sourceArchiveId: $1.0, sourcePageNumber: $1.1
            )
        }
        let store = makePreviewTestStore(
            archiveId: tankId,
            pages: pages,
            initialState: initialState
        )

        await store.send(
            .sliderPreview(.thumbnailJobStatus(
                42,
                "second",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "active",
                    notes: ["1": .string("processed")],
                    error: ""
                )
            ))
        ) {
            $0.sliderPreview.readyThumbnailPages = Set([3])
        }

        await store.send(
            .sliderPreview(.thumbnailJobStatus(
                42,
                "second",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: ["1": .string("processed")],
                    error: ""
                )
            ))
        ) {
            $0.sliderPreview.thumbnailJobsById = [41: "first"]
            $0.sliderPreview.readyThumbnailPages = Set([3, 4])
        }
    }

    @MainActor
    func testSliderDragChangedUpdatesPreviewStateWithoutJump() async {
        let store = makePreviewTestStore(pages: makePreviewPages(count: 4), currentPageIndex: 1)

        await store.send(.sliderPreview(.dragStarted)) {
            $0.sliderPreview.dragging = true
            $0.sliderPreview.draftIndex = 1
            $0.sliderPreview.previewVisible = true
            $0.sliderPreview.previewPageIndex = 1
        }

        await store.send(.sliderPreview(.dragChanged(3))) {
            $0.sliderPreview.draftIndex = 3
            $0.sliderPreview.previewPageIndex = 3
        }
    }

    @MainActor
    func testSliderDragEndedRequestsSliderJumpAndIgnoresTrailingDragChanges() async {
        var initialState = ReaderSliderPreviewFeature.State()
        initialState.draftIndex = 3
        initialState.dragging = true
        initialState.previewVisible = true
        initialState.previewPageIndex = 3
        let store = makePreviewTestStore(
            pages: makePreviewPages(count: 4),
            currentPageIndex: 1,
            initialState: initialState
        )

        await store.send(.sliderPreview(.dragEnded)) {
            $0.sliderPreview.draftIndex = nil
            $0.sliderPreview.dragging = false
            $0.sliderPreview.previewVisible = false
            $0.sliderPreview.previewPageIndex = nil
            $0.sliderPreview.previewImageURL = nil
            $0.sliderPreview.previewLoading = false
        }
        await store.receive(.requestJump(3, source: .slider)) {
            $0.scrollRequest = ScrollRequest(
                id: UUID(0),
                targetPageIndex: 3,
                source: .slider,
                animated: false
            )
        }
        await store.send(.sliderPreview(.dragChanged(3)))
    }

    /// After the reader opens, every page's preview is downloaded once, starting next to the page being
    /// read.
    @MainActor
    func testReaderDownloadsEveryPagePreviewOnceStartingNearTheCurrentPage() async throws {
        try await configureTestServer()
        let requestedPages = stubSliderPreviewThumbnails()
        let store = makePreviewTestStore(pages: makePreviewPages(count: 8), currentPageIndex: 5)

        XCTAssertEqual(ReaderSliderPreviewFeature.pageIndicesNearestFirst(from: 5, count: 8), [5, 6, 4, 7, 3, 2, 1, 0])

        await store.send(.sliderPreview(.thumbnailsQueued([readyThumbnailQueueResult()]))) {
            $0.sliderPreview.readyThumbnailPages = Set(1...8)
            $0.sliderPreview.prefetchInFlight = true
        }
        await finishPreviewPrefetch(store)

        XCTAssertFalse(store.state.sliderPreview.prefetchInFlight)
        XCTAssertEqual(
            store.state.sliderPreview.previewStatus,
            Dictionary(uniqueKeysWithValues: (1...8).map { ($0, .stored) })
        )
        XCTAssertEqual(requestedPages.withLock { $0 }.sorted(), Array(1...8))
        for pageNumber in 1...8 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: sliderPreviewURL(pageNumber: pageNumber).path))
        }
    }

    @MainActor
    func testSliderPreviewPrefetchPicksUpNewlyReadyPagesAfterActiveWaveFinishes() async throws {
        try await configureTestServer()
        let requestedPages = stubSliderPreviewThumbnails(delay: 0.05)
        var state = ReaderSliderPreviewFeature.State()
        state.thumbnailJobsById = [42: "archive"]
        let store = makePreviewTestStore(pages: makePreviewPages(count: 4), initialState: state)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .sliderPreview(.thumbnailJobStatus(
                42,
                "archive",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "active",
                    notes: ["1": .string("processed"), "2": .string("processed")],
                    error: ""
                )
            ))
        )
        XCTAssertTrue(store.state.sliderPreview.prefetchInFlight)

        await store.send(
            .sliderPreview(.thumbnailJobStatus(
                42,
                "archive",
                BasicJobStatus(
                    task: "generate_page_thumbnails",
                    state: "finished",
                    notes: [:],
                    error: ""
                )
            ))
        )
        XCTAssertTrue(store.state.sliderPreview.prefetchInFlight)

        await finishPreviewPrefetch(store)

        XCTAssertFalse(store.state.sliderPreview.prefetchInFlight)
        XCTAssertEqual(requestedPages.withLock { $0 }.sorted(), [1, 2, 3, 4])
        XCTAssertEqual(
            store.state.sliderPreview.previewStatus,
            Dictionary(uniqueKeysWithValues: (1...4).map { ($0, .stored) })
        )
    }

    /// A page whose preview is already on disk shows as soon as the slider reaches it, with no request.
    @MainActor
    func testSliderShowsAStoredPreviewImmediately() async throws {
        let previewURL = try writeSliderPreview(pageNumber: 2)
        let store = makePreviewTestStore(pages: makePreviewPages(count: 4), currentPageIndex: 1)

        // No server is configured, so any request fails the test.
        await store.send(.sliderPreview(.dragStarted)) {
            $0.sliderPreview.dragging = true
            $0.sliderPreview.draftIndex = 1
            $0.sliderPreview.previewVisible = true
            $0.sliderPreview.previewPageIndex = 1
            $0.sliderPreview.previewImageURL = previewURL
            $0.sliderPreview.previewStatus = [2: .stored]
        }
    }

    /// Moving onto a page whose preview is still downloading shows a spinner instead of the last page's
    /// image, and moves that page ahead of the background downloads.
    @MainActor
    func testSliderShowsASpinnerUntilTheNextPreviewArrives() async throws {
        try await configureTestServer()
        stubSliderPreviewThumbnails()
        let firstPreviewURL = try writeSliderPreview(pageNumber: 2)
        var state = ReaderSliderPreviewFeature.State()
        state.readyThumbnailPages = Set(1...4)
        let store = makePreviewTestStore(
            pages: makePreviewPages(count: 4),
            currentPageIndex: 1,
            initialState: state
        )

        await store.send(.sliderPreview(.dragStarted)) {
            $0.sliderPreview.dragging = true
            $0.sliderPreview.draftIndex = 1
            $0.sliderPreview.previewVisible = true
            $0.sliderPreview.previewPageIndex = 1
            $0.sliderPreview.previewImageURL = firstPreviewURL
            $0.sliderPreview.previewStatus = [2: .stored]
        }
        await store.send(.sliderPreview(.dragChanged(2))) {
            $0.sliderPreview.draftIndex = 2
            $0.sliderPreview.previewPageIndex = 2
            $0.sliderPreview.previewImageURL = nil
            $0.sliderPreview.previewLoading = true
            $0.sliderPreview.previewStatus = [2: .stored, 3: .fetching]
        }
        await store.receive(.sliderPreview(.previewFetched(pageNumber: 3, .stored))) {
            $0.sliderPreview.previewImageURL = sliderPreviewURL(pageNumber: 3)
            $0.sliderPreview.previewLoading = false
            $0.sliderPreview.previewStatus = [2: .stored, 3: .stored]
        }
    }

    /// The drag gesture reports every finger movement. Moving within one page must not restart that page's
    /// download: a cancelled download used to be saved as half an image.
    @MainActor
    func testFingerMovementWithinOnePageDownloadsItsPreviewOnce() async throws {
        try await configureTestServer()
        let requestedPages = stubSliderPreviewThumbnails(delay: 1)
        var state = ReaderSliderPreviewFeature.State()
        state.readyThumbnailPages = Set(1...4)
        let store = makePreviewTestStore(pages: makePreviewPages(count: 4), initialState: state)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sliderPreview(.dragStarted))
        for _ in 0..<5 {
            await store.send(.sliderPreview(.dragChanged(2)))
        }
        await finishPreviewPrefetch(store)

        XCTAssertEqual(requestedPages.withLock { $0 }.sorted(), [1, 3])
        XCTAssertEqual(store.state.sliderPreview.previewImageURL, sliderPreviewURL(pageNumber: 3))
        XCTAssertFalse(store.state.sliderPreview.previewLoading)
    }

    /// In Low Data Mode the background downloads stop, but the page under the slider is still fetched.
    @MainActor
    func testLowDataModeStopsBackgroundPreviewDownloadsButNotThePageUnderTheSlider() async throws {
        try await configureTestServer()
        let imageData = makeCacheTestImageData()
        let blockedRequests = OSAllocatedUnfairLock(initialState: 0)
        stub(condition: isHost("localhost")
                && isPath("/api/archives/archive/thumbnail")
                && isMethodGET()) { @Sendable request in
            guard request.allowsConstrainedNetworkAccess else {
                blockedRequests.withLock { $0 += 1 }
                return HTTPStubsResponse(error: URLError(
                    .notConnectedToInternet,
                    userInfo: [
                        NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.constrained.rawValue
                    ]
                ))
            }
            return HTTPStubsResponse(data: imageData, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
        }
        let store = makePreviewTestStore(pages: makePreviewPages(count: 6))
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.sliderPreview(.thumbnailsQueued([readyThumbnailQueueResult()])))
        await finishPreviewPrefetch(store)
        XCTAssertTrue(store.state.sliderPreview.prefetchStopped)
        XCTAssertEqual(store.state.sliderPreview.previewStatus, [:])
        XCTAssertEqual(blockedRequests.withLock { $0 }, 3)

        await store.send(.sliderPreview(.dragStarted))
        await store.receive(.sliderPreview(.previewFetched(pageNumber: 1, .stored)))
        XCTAssertEqual(store.state.sliderPreview.previewStatus, [1: .stored])
        XCTAssertEqual(store.state.sliderPreview.previewImageURL, sliderPreviewURL(pageNumber: 1))
        XCTAssertEqual(blockedRequests.withLock { $0 }, 3)
    }

    /// A cached archive makes its previews from the downloaded pages, without the server.
    @MainActor
    func testCachedStartPrefetchGeneratesPreviewsFromCachedPagesOffline() async throws {
        let id = "cachedChildPreviewArchive"
        let cacheFolder = LANraragiService.cachePath!.appendingPathComponent(id, conformingTo: .folder)
        try? FileManager.default.removeItem(at: cacheFolder)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: cacheFolder)
        }
        for page in 1...3 {
            try makeCacheTestImageData().write(to: cacheFolder.appendingPathComponent("\(page).jpg"))
        }
        let store = makePreviewTestStore(
            archiveId: id,
            cached: true,
            pages: makePreviewPages(count: 3, archiveId: id, cached: true)
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        // No server is configured, so any request fails the test.
        await store.send(.sliderPreview(.startPrefetchIfNeeded))
        await finishPreviewPrefetch(store)

        XCTAssertEqual(store.state.sliderPreview.previewStatus, [1: .stored, 2: .stored, 3: .stored])
        for pageNumber in 1...3 {
            let previewPath = sliderPreviewURL(archiveId: id, pageNumber: pageNumber).path
            XCTAssertNotNil(UIImage(contentsOfFile: previewPath))
        }
    }
}

private func makePreviewPages(
    count: Int,
    archiveId: String = "archive",
    cached: Bool = false
) -> [PageFeature.State] {
    (1...count).map { pageNumber in
        PageFeature.State(
            archiveId: archiveId,
            pageId: "\(pageNumber)",
            pageNumber: pageNumber,
            sourceArchiveId: archiveId,
            sourcePageNumber: pageNumber,
            cached: cached
        )
    }
}

private func makeSplitPreviewPages(
    archiveId: String = "archive"
) -> [PageFeature.State] {
    [
        PageFeature.State(archiveId: archiveId, pageId: "1", pageNumber: 1),
        PageFeature.State(archiveId: archiveId, pageId: "2", pageNumber: 2, pageMode: .left),
        PageFeature.State(archiveId: archiveId, pageId: "2", pageNumber: 2, pageMode: .right),
        PageFeature.State(archiveId: archiveId, pageId: "3", pageNumber: 3)
    ]
}

@MainActor
private func makePreviewTestStore(
    archiveId: String = "archive",
    cached: Bool = false,
    pages: [PageFeature.State] = [],
    currentPageIndex: Int = 0,
    initialState: ReaderSliderPreviewFeature.State = ReaderSliderPreviewFeature.State(),
    configureDependencies: ((inout DependencyValues) -> Void)? = nil
) -> TestStoreOf<ArchiveReaderFeature> {
    var state = ArchiveReaderFeature.State(
        currentArchiveId: archiveId,
        allArchives: [],
        cached: cached
    )
    state.pages = IdentifiedArray(uniqueElements: pages)
    state.currentPageIndex = currentPageIndex
    state.sliderPreview = initialState
    let store = TestStore(initialState: state) {
        ArchiveReaderFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        configureDependencies?(&$0)
    }
    store.timeout = .seconds(5)
    return store
}

@MainActor
private func finishPreviewPrefetch(_ store: TestStoreOf<ArchiveReaderFeature>) async {
    let exhaustivity = store.exhaustivity
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.finish(timeout: .seconds(15))
    await store.skipReceivedActions(strict: false)
    store.exhaustivity = exhaustivity
}

private func sliderPreviewsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("LANreader", isDirectory: true)
        .appendingPathComponent("slider-previews", isDirectory: true)
}

private func sliderPreviewURL(archiveId: String = "archive", pageNumber: Int) -> URL {
    sliderPreviewsDirectory()
        .appendingPathComponent(archiveId, isDirectory: true)
        .appendingPathComponent("\(pageNumber).jpg", isDirectory: false)
}

@discardableResult
private func writeSliderPreview(archiveId: String = "archive", pageNumber: Int) throws -> URL {
    let url = sliderPreviewURL(archiveId: archiveId, pageNumber: pageNumber)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try makeCacheTestImageData().write(to: url)
    return url
}

private func makeCacheTestImageData() -> Data {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    return image.jpegData(compressionQuality: 0.9)!
}

@discardableResult
private func stubSliderPreviewThumbnails(
    archiveId: String = "archive",
    delay: TimeInterval = 0
) -> OSAllocatedUnfairLock<[Int]> {
    let requestedPages = OSAllocatedUnfairLock(initialState: [Int]())
    let imageData = makeCacheTestImageData()
    stub(condition: isHost("localhost")
            && isPath("/api/archives/\(archiveId)/thumbnail")
            && isMethodGET()
            && hasHeaderNamed("Authorization", value: "Bearer YXBpS2V5")) { @Sendable request in
        let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "page" }?.value
        requestedPages.withLock { $0.append(page.flatMap(Int.init) ?? -1) }
        return HTTPStubsResponse(data: imageData, statusCode: 200, headers: ["Content-Type": "image/jpeg"])
            .requestTime(delay, responseTime: 0)
    }
    return requestedPages
}

private func readyThumbnailQueueResult(archiveId: String = "archive") -> SliderPreviewThumbnailQueueResult {
    SliderPreviewThumbnailQueueResult(
        archiveId: archiveId,
        response: PageThumbnailQueueResponse(
            job: nil,
            message: "No job queued, all thumbnails already exist.",
            operation: "generate_page_thumbnails",
            success: "1"
        )
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

private func configureFinishedThumbnailPolling(jobId: Int) async throws {
    try await configureTestServer()

    stub(condition: isHost("localhost")
            && isPath("/api/minion/\(jobId)")
            && isMethodGET()) { @Sendable _ in
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
