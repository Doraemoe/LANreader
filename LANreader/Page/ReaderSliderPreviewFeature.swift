import ComposableArchitecture
import CoreGraphics
import Foundation
import Logging
import OrderedCollections

public struct SliderPreviewThumbnailQueueResult: Equatable, Sendable {
    public let archiveId: String
    public let response: PageThumbnailQueueResponse

    public init(archiveId: String, response: PageThumbnailQueueResponse) {
        self.archiveId = archiveId
        self.response = response
    }
}

/// Where a page's slider preview stands.
public enum SliderPreviewStatus: Equatable, Sendable {
    case fetching
    case stored
    case failed
}

public enum SliderPreviewFetchResult: Equatable, Sendable {
    case stored
    case failed
    /// Low Data Mode blocked a background download.
    case networkConstrained
}

public struct ReaderSliderPreviewPage: Equatable, Sendable {
    public let pageNumber: Int
    public let sourceArchiveId: String
    public let sourcePageNumber: Int

    public init(pageNumber: Int, sourceArchiveId: String, sourcePageNumber: Int) {
        self.pageNumber = pageNumber
        self.sourceArchiveId = sourceArchiveId
        self.sourcePageNumber = sourcePageNumber
    }

    init(page: PageFeature.State) {
        self.pageNumber = page.pageNumber
        self.sourceArchiveId = page.sourceArchiveId
        self.sourcePageNumber = page.sourcePageNumber
    }
}

public struct ReaderSliderPreviewState: Equatable, Sendable {
    var draftIndex: Int?
    var dragging = false
    var previewVisible = false
    var previewPageIndex: Int?
    var previewImageURL: URL?
    var previewLoading = false
    var thumbnailJobsById: [Int: String] = [:]
    var readyThumbnailPages: Set<Int> = []
    /// Keyed by reader page number. A page with no entry has not been tried yet.
    var previewStatus: [Int: SliderPreviewStatus] = [:]
    /// Set once Low Data Mode blocks a background preview download. After that, only the page
    /// under the slider is fetched.
    var prefetchStopped = false
    var prefetchInFlight = false

    public init() {}

    mutating func resetDisplayState() {
        draftIndex = nil
        dragging = false
        previewVisible = false
        previewPageIndex = nil
        previewImageURL = nil
        previewLoading = false
    }

    mutating func resetArchiveState() {
        resetDisplayState()
        thumbnailJobsById = [:]
        readyThumbnailPages = []
        previewStatus = [:]
        prefetchStopped = false
        prefetchInFlight = false
    }
}

private struct SliderPreviewTarget: Sendable {
    let pageNumber: Int
    let sourceArchiveId: String
    let sourcePageNumber: Int
}

@Reducer public struct ReaderSliderPreviewFeature: Sendable {
    private let logger = Logger(label: "ReaderSliderPreviewFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        var archiveId = ""
        var cached = false
        var pages: [ReaderSliderPreviewPage] = []
        var currentPageIndex = 0
        var draftIndex: Int?
        var dragging = false
        var previewVisible = false
        var previewPageIndex: Int?
        var previewImageURL: URL?
        var previewLoading = false
        var thumbnailJobsById: [Int: String] = [:]
        var readyThumbnailPages: Set<Int> = []
        /// Keyed by reader page number. A page with no entry has not been tried yet.
        var previewStatus: [Int: SliderPreviewStatus] = [:]
        /// Set once Low Data Mode blocks a background preview download. After that, only the page
        /// under the slider is fetched.
        var prefetchStopped = false
        var prefetchInFlight = false

        public init(
            archiveId: String = "",
            cached: Bool = false,
            pages: [ReaderSliderPreviewPage] = [],
            currentPageIndex: Int = 0,
            stored: ReaderSliderPreviewState = ReaderSliderPreviewState()
        ) {
            self.archiveId = archiveId
            self.cached = cached
            self.pages = pages
            self.currentPageIndex = currentPageIndex
            self.draftIndex = stored.draftIndex
            self.dragging = stored.dragging
            self.previewVisible = stored.previewVisible
            self.previewPageIndex = stored.previewPageIndex
            self.previewImageURL = stored.previewImageURL
            self.previewLoading = stored.previewLoading
            self.thumbnailJobsById = stored.thumbnailJobsById
            self.readyThumbnailPages = stored.readyThumbnailPages
            self.previewStatus = stored.previewStatus
            self.prefetchStopped = stored.prefetchStopped
            self.prefetchInFlight = stored.prefetchInFlight
        }

        var archivePageCount: Int {
            Set(pages.map(\.pageNumber)).count
        }

        var stored: ReaderSliderPreviewState {
            var snapshot = ReaderSliderPreviewState()
            snapshot.draftIndex = draftIndex
            snapshot.dragging = dragging
            snapshot.previewVisible = previewVisible
            snapshot.previewPageIndex = previewPageIndex
            snapshot.previewImageURL = previewImageURL
            snapshot.previewLoading = previewLoading
            snapshot.thumbnailJobsById = thumbnailJobsById
            snapshot.readyThumbnailPages = readyThumbnailPages
            snapshot.previewStatus = previewStatus
            snapshot.prefetchStopped = prefetchStopped
            snapshot.prefetchInFlight = prefetchInFlight
            return snapshot
        }

        mutating func resetDisplayState() {
            draftIndex = nil
            dragging = false
            previewVisible = false
            previewPageIndex = nil
            previewImageURL = nil
            previewLoading = false
        }
    }

    public enum Action: Equatable {
        case prepareThumbnails
        case thumbnailsQueued([SliderPreviewThumbnailQueueResult])
        case pollThumbnailJob(Int, archiveId: String)
        case thumbnailJobStatus(Int, String, BasicJobStatus)
        case thumbnailPollingFailed(Int, String)
        case dragStarted
        case dragChanged(Int)
        case dragEnded
        case previewFetched(pageNumber: Int, SliderPreviewFetchResult)
        case prefetchFinished
        case startPrefetchIfNeeded
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case jumpRequested(Int)
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.continuousClock) var clock

    public enum CancelId: Sendable {
        case thumbnailQueue
        case thumbnailPolling
        case fetch
        case prefetch
    }

    public static func cancelEffects<ParentAction>() -> Effect<ParentAction> {
        .merge(
            .cancel(id: CancelId.thumbnailQueue),
            .cancel(id: CancelId.thumbnailPolling),
            .cancel(id: CancelId.prefetch),
            .cancel(id: CancelId.fetch)
        )
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(state: &state, action: action)
        }
    }

    /// Page indices ordered by distance from `anchor`, with the later page first on a tie.
    static func pageIndicesNearestFirst(from anchor: Int, count: Int) -> [Int] {
        (0..<count).sorted { lhs, rhs in
            let lhsDistance = abs(lhs - anchor)
            let rhsDistance = abs(rhs - anchor)
            return lhsDistance == rhsDistance ? lhs > rhs : lhsDistance < rhsDistance
        }
    }
}

private extension ReaderSliderPreviewFeature {
    func reduce(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .prepareThumbnails:
            return prepareThumbnails(state: &state)
        case let .thumbnailsQueued(results):
            return handleThumbnailsQueued(results, state: &state)
        case let .pollThumbnailJob(jobId, archiveId):
            return pollThumbnailJob(jobId: jobId, archiveId: archiveId)
        case let .thumbnailJobStatus(jobId, archiveId, status):
            return handleThumbnailJobStatus(jobId: jobId, archiveId: archiveId, status: status, state: &state)
        case let .thumbnailPollingFailed(jobId, _):
            state.thumbnailJobsById[jobId] = nil
            return advancePreviews(state: &state)
        case .dragStarted:
            return handleDragStarted(state: &state)
        case let .dragChanged(newValue):
            return handleDragChanged(newValue, state: &state)
        case .dragEnded:
            return handleDragEnded(state: &state)
        case let .previewFetched(pageNumber, result):
            return handlePreviewFetched(pageNumber: pageNumber, result: result, state: &state)
        case .prefetchFinished:
            state.prefetchInFlight = false
            return startPrefetchIfNeeded(state: &state)
        case .startPrefetchIfNeeded:
            return startPrefetchIfNeeded(state: &state)
        case .delegate:
            return .none
        }
    }

    func prepareThumbnails(state: inout State) -> Effect<Action> {
        guard !state.cached, !state.pages.isEmpty else { return .none }
        guard state.thumbnailJobsById.isEmpty,
              state.readyThumbnailPages.count < state.archivePageCount else {
            return .none
        }

        let sourceArchiveIds = Array(OrderedSet(state.pages.map(\.sourceArchiveId)))
        return .run { send in
            var results: [SliderPreviewThumbnailQueueResult] = []
            for archiveId in sourceArchiveIds {
                let response = try await service.queuePageThumbnails(id: archiveId).value
                results.append(
                    SliderPreviewThumbnailQueueResult(archiveId: archiveId, response: response)
                )
            }
            await send(.thumbnailsQueued(results))
        } catch: { [archiveId = state.archiveId] error, _ in
            logger.warning("failed to queue slider preview thumbnails. id=\(archiveId) \(error)")
        }
        .cancellable(id: CancelId.thumbnailQueue, cancelInFlight: true)
    }

    func handleThumbnailsQueued(
        _ results: [SliderPreviewThumbnailQueueResult],
        state: inout State
    ) -> Effect<Action> {
        state.thumbnailJobsById = [:]
        var effect: Effect<Action> = .none

        for result in results {
            if let jobId = result.response.job {
                state.thumbnailJobsById[jobId] = result.archiveId
                effect = .merge(
                    effect,
                    .send(.pollThumbnailJob(jobId, archiveId: result.archiveId))
                )
            } else {
                state.readyThumbnailPages.formUnion(
                    Self.readerPageNumbers(in: state.pages, sourceArchiveId: result.archiveId)
                )
            }
        }
        return .merge(effect, advancePreviews(state: &state))
    }

    func pollThumbnailJob(jobId: Int, archiveId: String) -> Effect<Action> {
        .run { send in
            while true {
                let status = try await service.checkBasicJobStatus(id: jobId).value
                await send(.thumbnailJobStatus(jobId, archiveId, status))
                if status.state == "finished" || status.state == "failed" {
                    return
                }
                try await clock.sleep(for: .seconds(1))
            }
        } catch: { error, send in
            logger.warning("failed to poll slider preview thumbnail job. id=\(archiveId) \(error)")
            await send(.thumbnailPollingFailed(jobId, archiveId))
        }
        .cancellable(id: CancelId.thumbnailPolling)
    }

    func handleThumbnailJobStatus(
        jobId: Int,
        archiveId: String,
        status: BasicJobStatus,
        state: inout State
    ) -> Effect<Action> {
        state.readyThumbnailPages.formUnion(
            Self.readerPageNumbers(
                in: state.pages,
                sourceArchiveId: archiveId,
                sourcePageNumbers: status.processedPages
            )
        )
        if status.state == "finished" {
            state.readyThumbnailPages.formUnion(
                Self.readerPageNumbers(in: state.pages, sourceArchiveId: archiveId)
            )
            state.thumbnailJobsById[jobId] = nil
        } else if status.state == "failed" {
            state.thumbnailJobsById[jobId] = nil
        }
        return advancePreviews(state: &state)
    }

    func handleDragStarted(state: inout State) -> Effect<Action> {
        state.dragging = true
        let previewIndex = ReaderPositioning.clampedPageIndex(
            state.draftIndex ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        state.previewVisible = !state.pages.isEmpty
        guard !state.pages.isEmpty else { return .none }
        return updatePreview(state: &state, pageIndex: previewIndex)
    }

    func handleDragChanged(_ newValue: Int, state: inout State) -> Effect<Action> {
        guard state.dragging, !state.pages.isEmpty else { return .none }
        let targetIndex = ReaderPositioning.clampedPageIndex(newValue, pageCount: state.pages.count)
        return updatePreview(state: &state, pageIndex: targetIndex)
    }

    func handleDragEnded(state: inout State) -> Effect<Action> {
        state.dragging = false
        guard !state.pages.isEmpty else {
            state.resetDisplayState()
            return .none
        }
        let targetIndex = ReaderPositioning.clampedPageIndex(
            state.draftIndex ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        state.resetDisplayState()
        return .send(.delegate(.jumpRequested(targetIndex)))
    }

    func handlePreviewFetched(
        pageNumber: Int,
        result: SliderPreviewFetchResult,
        state: inout State
    ) -> Effect<Action> {
        guard state.pages.contains(where: { $0.pageNumber == pageNumber }) else {
            return .none
        }
        switch result {
        case .stored:
            state.previewStatus[pageNumber] = .stored
        case .failed:
            if state.previewStatus[pageNumber] != .stored {
                state.previewStatus[pageNumber] = .failed
            }
        case .networkConstrained:
            if state.previewStatus[pageNumber] == .fetching {
                state.previewStatus[pageNumber] = nil
            }
            state.prefetchStopped = true
        }
        if result != .networkConstrained,
           state.previewVisible,
           let previewIndex = state.previewPageIndex,
           state.pages.indices.contains(previewIndex),
           state.pages[previewIndex].pageNumber == pageNumber {
            let stored = state.previewStatus[pageNumber] == .stored
            state.previewImageURL = stored
                ? Self.sliderPreviewFileURL(archiveId: state.archiveId, pageNumber: pageNumber)
                : nil
            state.previewLoading = false
        }
        return .none
    }

    static func readerPageNumbers(
        in pages: [ReaderSliderPreviewPage],
        sourceArchiveId: String,
        sourcePageNumbers: Set<Int>? = nil
    ) -> Set<Int> {
        Set(
            pages.compactMap { page in
                guard page.sourceArchiveId == sourceArchiveId else { return nil }
                if let sourcePageNumbers, !sourcePageNumbers.contains(page.sourcePageNumber) {
                    return nil
                }
                return page.pageNumber
            }
        )
    }

    func updatePreview(state: inout State, pageIndex: Int) -> Effect<Action> {
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: state.pages.count)
        guard clampedIndex < state.pages.count else {
            return .none
        }

        // The drag gesture reports every finger movement, so most calls land on the page already shown.
        let pageChanged = state.previewPageIndex != clampedIndex
        state.draftIndex = clampedIndex
        state.previewVisible = true
        state.previewPageIndex = clampedIndex
        guard pageChanged else { return .none }
        return showPreview(pageIndex: clampedIndex, state: &state)
    }

    /// Shows the page's preview if it is on disk. Otherwise the bubble shows a spinner and the page is
    /// fetched ahead of the background queue.
    func showPreview(pageIndex: Int, state: inout State) -> Effect<Action> {
        let page = state.pages[pageIndex]
        let fileURL = Self.sliderPreviewFileURL(archiveId: state.archiveId, pageNumber: page.pageNumber)
        if state.previewStatus[page.pageNumber] == nil, Self.fileExists(fileURL) {
            state.previewStatus[page.pageNumber] = .stored
        }

        let status = state.previewStatus[page.pageNumber]
        state.previewImageURL = status == .stored ? fileURL : nil
        switch status {
        case .stored:
            state.previewLoading = false
            return .none
        case .fetching:
            state.previewLoading = true
            return .none
        case .failed, nil:
            guard state.cached || state.readyThumbnailPages.contains(page.pageNumber) else {
                // The server has not generated this page's thumbnail yet.
                state.previewLoading = !state.thumbnailJobsById.isEmpty
                return .none
            }
            state.previewLoading = true
            return fetchForegroundPreview(page, state: &state)
        }
    }

    /// Runs after more thumbnails become available: fetches the page under the slider if it was waiting,
    /// and starts the background prefetch wave if none is active.
    func advancePreviews(state: inout State) -> Effect<Action> {
        var waitingPreview: Effect<Action> = .none
        if state.previewVisible,
           let previewIndex = state.previewPageIndex,
           state.pages.indices.contains(previewIndex),
           state.previewStatus[state.pages[previewIndex].pageNumber] == nil {
            waitingPreview = showPreview(pageIndex: previewIndex, state: &state)
        }
        return .merge(waitingPreview, startPrefetchIfNeeded(state: &state))
    }

    /// Starts one background prefetch wave for all ready, untried preview pages, nearest first.
    func startPrefetchIfNeeded(state: inout State) -> Effect<Action> {
        guard !state.prefetchStopped,
              !state.prefetchInFlight,
              !state.pages.isEmpty else {
            return .none
        }

        let targets = prefetchTargets(state: state)
        guard !targets.isEmpty else { return .none }

        state.prefetchInFlight = true
        let archiveId = state.archiveId
        let cached = state.cached
        let limit = cached ? Self.previewGenerationLimit : Self.previewDownloadLimit
        return .run(priority: .utility) { [targets] send in
            await runPrefetch(
                targets: targets,
                archiveId: archiveId,
                cached: cached,
                limit: limit,
                send: send
            )
        }
        .cancellable(id: CancelId.prefetch, cancelInFlight: true)
    }

    func prefetchTargets(state: State) -> [SliderPreviewTarget] {
        let anchor = ReaderPositioning.clampedPageIndex(
            (state.previewVisible ? state.previewPageIndex : nil) ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        var seenPages: Set<Int> = []
        var targets: [SliderPreviewTarget] = []
        for index in Self.pageIndicesNearestFirst(from: anchor, count: state.pages.count) {
            let page = state.pages[index]
            guard seenPages.insert(page.pageNumber).inserted else { continue }
            guard state.previewStatus[page.pageNumber] == nil,
                  state.cached || state.readyThumbnailPages.contains(page.pageNumber) else {
                continue
            }
            targets.append(
                SliderPreviewTarget(
                    pageNumber: page.pageNumber,
                    sourceArchiveId: page.sourceArchiveId,
                    sourcePageNumber: page.sourcePageNumber
                )
            )
        }
        return targets
    }

    func runPrefetch(
        targets: [SliderPreviewTarget],
        archiveId: String,
        cached: Bool,
        limit: Int,
        send: Send<Action>
    ) async {
        guard !Task.isCancelled else { return }
        await withTaskGroup(of: (Int, SliderPreviewFetchResult?).self) { group in
            var nextIndex = min(limit, targets.count)
            for target in targets.prefix(nextIndex) {
                addPrefetchTask(to: &group, target: target, archiveId: archiveId, cached: cached)
            }

            var constrained = false
            while let (pageNumber, result) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let result {
                    await send(.previewFetched(pageNumber: pageNumber, result))
                    if result == .networkConstrained {
                        constrained = true
                    }
                }
                if !constrained, nextIndex < targets.count, !Task.isCancelled {
                    addPrefetchTask(to: &group, target: targets[nextIndex], archiveId: archiveId, cached: cached)
                    nextIndex += 1
                }
            }
        }
        guard !Task.isCancelled else { return }
        await send(.prefetchFinished)
    }

    func addPrefetchTask(
        to group: inout TaskGroup<(Int, SliderPreviewFetchResult?)>,
        target: SliderPreviewTarget,
        archiveId: String,
        cached: Bool
    ) {
        group.addTask {
            let result = await fetchPreviewResult(
                target: target,
                archiveId: archiveId,
                cached: cached,
                background: true
            )
            return (target.pageNumber, result)
        }
    }

    func fetchForegroundPreview(
        _ page: ReaderSliderPreviewPage,
        state: inout State
    ) -> Effect<Action> {
        state.previewStatus[page.pageNumber] = .fetching
        let archiveId = state.archiveId
        let cached = state.cached
        let target = SliderPreviewTarget(
            pageNumber: page.pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        return .run(priority: .userInitiated) { send in
            guard let result = await fetchPreviewResult(
                target: target,
                archiveId: archiveId,
                cached: cached,
                background: false
            ), !Task.isCancelled else {
                return
            }
            await send(.previewFetched(pageNumber: target.pageNumber, result))
        }
        .cancellable(id: CancelId.fetch)
    }

    func fetchPreviewResult(
        target: SliderPreviewTarget,
        archiveId: String,
        cached: Bool,
        background: Bool
    ) async -> SliderPreviewFetchResult? {
        guard !Task.isCancelled else { return nil }
        let fileURL = Self.sliderPreviewFileURL(archiveId: archiveId, pageNumber: target.pageNumber)
        if Self.fileExists(fileURL) {
            return .stored
        }
        return cached
            ? generateCachedPreview(archiveId: archiveId, pageNumber: target.pageNumber, fileURL: fileURL)
            : await downloadPreview(target: target, fileURL: fileURL, background: background)
    }

    func generateCachedPreview(
        archiveId: String,
        pageNumber: Int,
        fileURL: URL
    ) -> SliderPreviewFetchResult? {
        var stored = false
        if let cacheFolder = LANraragiService.cachePath?.appendingPathComponent(archiveId),
           let sourceURL = imageService.storedImagePath(folderUrl: cacheFolder, pageNumber: "\(pageNumber)") {
            stored = imageService.generatePreviewImage(
                sourceUrl: sourceURL,
                destinationUrl: fileURL,
                maxPixelSize: Self.cachedPreviewMaxPixelSize
            )
        }
        guard !Task.isCancelled else { return nil }
        if !stored {
            logger.warning("failed to generate cached slider preview. id=\(archiveId) page=\(pageNumber)")
        }
        return stored ? .stored : .failed
    }

    func downloadPreview(
        target: SliderPreviewTarget,
        fileURL: URL,
        background: Bool
    ) async -> SliderPreviewFetchResult? {
        do {
            let thumbnailData = try await service.retrieveGeneratedArchiveThumbnail(
                id: target.sourceArchiveId,
                page: target.sourcePageNumber,
                cacheBust: Self.sliderPreviewCacheBust(pageNumber: target.sourcePageNumber),
                background: background
            )
            guard !Task.isCancelled else { return nil }
            let stored = thumbnailData.map {
                imageService.storePreviewImage(imageData: $0, destinationUrl: fileURL)
            } ?? false
            return stored ? .stored : .failed
        } catch {
            guard !Task.isCancelled else { return nil }
            if LANraragiService.isBlockedByLowDataMode(error) {
                return .networkConstrained
            }
            let message = "failed to fetch slider preview thumbnail. id=\(target.sourceArchiveId) "
                + "page=\(target.sourcePageNumber) \(error)"
            logger.warning("\(message)")
            return .failed
        }
    }

    /// Server thumbnails are at most 500 pixels wide; cached pages get previews of about the same size.
    static let cachedPreviewMaxPixelSize: CGFloat = 720
    /// Leaves the rest of the server's connections to the page images being read.
    static let previewDownloadLimit = 3
    static let previewGenerationLimit = 2

    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    static func sliderPreviewRootDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LANreader", isDirectory: true)
            .appendingPathComponent("slider-previews", isDirectory: true)
    }

    static func sliderPreviewDirectory(archiveId: String) -> URL {
        sliderPreviewRootDirectory().appendingPathComponent(archiveId, isDirectory: true)
    }

    static func sliderPreviewFileURL(archiveId: String, pageNumber: Int) -> URL {
        sliderPreviewDirectory(archiveId: archiveId)
            .appendingPathComponent("\(pageNumber).jpg", isDirectory: false)
    }

    static func sliderPreviewCacheBust(pageNumber: Int) -> Int {
        Int(Date().timeIntervalSince1970 * 1000) + pageNumber
    }
}
