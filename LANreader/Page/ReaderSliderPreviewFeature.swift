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

private struct SliderPreviewTarget: Sendable {
    let pageNumber: Int
    let sourceArchiveId: String
    let sourcePageNumber: Int

    init(page: PageFeature.State) {
        self.pageNumber = page.pageNumber
        self.sourceArchiveId = page.sourceArchiveId
        self.sourcePageNumber = page.sourcePageNumber
    }
}

public enum ReaderSliderPreviewFeature {
    fileprivate static let logger = Logger(label: "ReaderSliderPreviewFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
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

    @CasePathable
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
    }

    public enum CancelId: Sendable {
        case thumbnailQueue
        case thumbnailPolling
        case fetch
        case prefetch
    }

    public static func cancelEffects() -> Effect<ArchiveReaderFeature.Action> {
        .merge(
            .cancel(id: CancelId.thumbnailQueue),
            .cancel(id: CancelId.thumbnailPolling),
            .cancel(id: CancelId.prefetch),
            .cancel(id: CancelId.fetch)
        )
    }

    /// Page indices ordered by distance from `anchor`, with the later page first on a tie.
    static func pageIndicesNearestFirst(from anchor: Int, count: Int) -> [Int] {
        (0..<count).sorted { lhs, rhs in
            let lhsDistance = abs(lhs - anchor)
            let rhsDistance = abs(rhs - anchor)
            return lhsDistance == rhsDistance ? lhs > rhs : lhsDistance < rhsDistance
        }
    }

    /// Server thumbnails are at most 500 pixels wide; cached pages get previews of about the same size.
    fileprivate static let cachedPreviewMaxPixelSize: CGFloat = 720
    /// Leaves the rest of the server's connections to the page images being read.
    fileprivate static let previewDownloadLimit = 3
    fileprivate static let previewGenerationLimit = 2

    fileprivate static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private static func sliderPreviewRootDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LANreader", isDirectory: true)
            .appendingPathComponent("slider-previews", isDirectory: true)
    }

    private static func sliderPreviewDirectory(archiveId: String) -> URL {
        sliderPreviewRootDirectory().appendingPathComponent(archiveId, isDirectory: true)
    }

    fileprivate static func sliderPreviewFileURL(archiveId: String, pageNumber: Int) -> URL {
        sliderPreviewDirectory(archiveId: archiveId)
            .appendingPathComponent("\(pageNumber).jpg", isDirectory: false)
    }

    fileprivate static func sliderPreviewCacheBust(pageNumber: Int) -> Int {
        Int(Date().timeIntervalSince1970 * 1000) + pageNumber
    }
}

extension ArchiveReaderFeature {
    func reduceSliderPreview(
        _ action: ReaderSliderPreviewFeature.Action,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case .prepareThumbnails:
            return prepareSliderThumbnails(state: &state)
        case let .thumbnailsQueued(results):
            return handleSliderThumbnailsQueued(results, state: &state)
        case let .pollThumbnailJob(jobId, archiveId):
            return pollSliderThumbnailJob(jobId: jobId, archiveId: archiveId)
        case let .thumbnailJobStatus(jobId, archiveId, status):
            handleSliderThumbnailJobStatus(jobId: jobId, archiveId: archiveId, status: status, state: &state)
            return advanceSliderPreviews(state: &state)
        case let .thumbnailPollingFailed(jobId, _):
            state.sliderPreview.thumbnailJobsById[jobId] = nil
            return advanceSliderPreviews(state: &state)
        case .dragStarted:
            return handleSliderDragStarted(state: &state)
        case let .dragChanged(newValue):
            return handleSliderDragChanged(newValue, state: &state)
        case .dragEnded:
            return handleSliderDragEnded(state: &state)
        case let .previewFetched(pageNumber, result):
            handleSliderPreviewFetched(pageNumber: pageNumber, result: result, state: &state)
            return .none
        case .prefetchFinished:
            state.sliderPreview.prefetchInFlight = false
            return startSliderPrefetchIfNeeded(state: &state)
        case .startPrefetchIfNeeded:
            return startSliderPrefetchIfNeeded(state: &state)
        }
    }
}

private extension ArchiveReaderFeature {
    func prepareSliderThumbnails(state: inout State) -> Effect<Action> {
        guard !state.cached, !state.pages.isEmpty else { return .none }
        guard state.sliderPreview.thumbnailJobsById.isEmpty,
              state.sliderPreview.readyThumbnailPages.count < state.archivePageCount else {
            return .none
        }

        let archiveId = state.currentArchiveId
        let sourceArchiveIds = sliderPreviewSourceArchiveIds(in: state.pages)
        return .run { send in
            var results: [SliderPreviewThumbnailQueueResult] = []
            for sourceId in sourceArchiveIds {
                let response = try await service.queuePageThumbnails(id: sourceId).value
                results.append(
                    SliderPreviewThumbnailQueueResult(archiveId: sourceId, response: response)
                )
            }
            await send(.sliderPreview(.thumbnailsQueued(results)))
        } catch: { error, _ in
            ReaderSliderPreviewFeature.logger.warning(
                "failed to queue slider preview thumbnails. id=\(archiveId) \(error)"
            )
        }
        .cancellable(id: ReaderSliderPreviewFeature.CancelId.thumbnailQueue, cancelInFlight: true)
    }

    func handleSliderThumbnailsQueued(
        _ results: [SliderPreviewThumbnailQueueResult],
        state: inout State
    ) -> Effect<Action> {
        state.sliderPreview.thumbnailJobsById = [:]
        var effect: Effect<Action> = .none

        for result in results {
            if let jobId = result.response.job {
                state.sliderPreview.thumbnailJobsById[jobId] = result.archiveId
                effect = .merge(
                    effect,
                    .send(.sliderPreview(.pollThumbnailJob(jobId, archiveId: result.archiveId)))
                )
            } else {
                state.sliderPreview.readyThumbnailPages.formUnion(
                    sliderPreviewReaderPageNumbers(in: state.pages, sourceArchiveId: result.archiveId)
                )
            }
        }
        return .merge(effect, advanceSliderPreviews(state: &state))
    }

    func pollSliderThumbnailJob(jobId: Int, archiveId: String) -> Effect<Action> {
        .run { send in
            while true {
                let status = try await service.checkBasicJobStatus(id: jobId).value
                await send(.sliderPreview(.thumbnailJobStatus(jobId, archiveId, status)))
                if status.state == "finished" || status.state == "failed" {
                    return
                }
                try await clock.sleep(for: .seconds(1))
            }
        } catch: { error, send in
            ReaderSliderPreviewFeature.logger.warning(
                "failed to poll slider preview thumbnail job. id=\(archiveId) \(error)"
            )
            await send(.sliderPreview(.thumbnailPollingFailed(jobId, archiveId)))
        }
        .cancellable(id: ReaderSliderPreviewFeature.CancelId.thumbnailPolling)
    }

    func handleSliderThumbnailJobStatus(
        jobId: Int,
        archiveId: String,
        status: BasicJobStatus,
        state: inout State
    ) {
        state.sliderPreview.readyThumbnailPages.formUnion(
            sliderPreviewReaderPageNumbers(
                in: state.pages,
                sourceArchiveId: archiveId,
                sourcePageNumbers: status.processedPages
            )
        )
        if status.state == "finished" {
            state.sliderPreview.readyThumbnailPages.formUnion(
                sliderPreviewReaderPageNumbers(in: state.pages, sourceArchiveId: archiveId)
            )
            state.sliderPreview.thumbnailJobsById[jobId] = nil
        } else if status.state == "failed" {
            state.sliderPreview.thumbnailJobsById[jobId] = nil
        }
    }

    func handleSliderDragStarted(state: inout State) -> Effect<Action> {
        state.sliderPreview.dragging = true
        let previewIndex = ReaderPositioning.clampedPageIndex(
            state.sliderPreview.draftIndex ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        state.sliderPreview.previewVisible = !state.pages.isEmpty
        guard !state.pages.isEmpty else { return .none }
        return updateSliderPreview(state: &state, pageIndex: previewIndex)
    }

    func handleSliderDragChanged(_ newValue: Int, state: inout State) -> Effect<Action> {
        guard state.sliderPreview.dragging, !state.pages.isEmpty else { return .none }
        let targetIndex = ReaderPositioning.clampedPageIndex(newValue, pageCount: state.pages.count)
        return updateSliderPreview(state: &state, pageIndex: targetIndex)
    }

    func handleSliderDragEnded(state: inout State) -> Effect<Action> {
        state.sliderPreview.dragging = false
        guard !state.pages.isEmpty else {
            state.sliderPreview.resetDisplayState()
            return .none
        }
        let targetIndex = ReaderPositioning.clampedPageIndex(
            state.sliderPreview.draftIndex ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        state.sliderPreview.resetDisplayState()
        return .send(.requestJump(targetIndex, source: .slider))
    }

    func handleSliderPreviewFetched(
        pageNumber: Int,
        result: SliderPreviewFetchResult,
        state: inout State
    ) {
        guard state.pages.contains(where: { $0.pageNumber == pageNumber }) else {
            return
        }
        switch result {
        case .stored:
            state.sliderPreview.previewStatus[pageNumber] = .stored
        case .failed:
            if state.sliderPreview.previewStatus[pageNumber] != .stored {
                state.sliderPreview.previewStatus[pageNumber] = .failed
            }
        case .networkConstrained:
            if state.sliderPreview.previewStatus[pageNumber] == .fetching {
                state.sliderPreview.previewStatus[pageNumber] = nil
            }
            state.sliderPreview.prefetchStopped = true
        }
        if result != .networkConstrained,
           state.sliderPreview.previewVisible,
           let previewIndex = state.sliderPreview.previewPageIndex,
           state.pages.indices.contains(previewIndex),
           state.pages[previewIndex].pageNumber == pageNumber {
            let stored = state.sliderPreview.previewStatus[pageNumber] == .stored
            state.sliderPreview.previewImageURL = stored
                ? ReaderSliderPreviewFeature.sliderPreviewFileURL(
                    archiveId: state.currentArchiveId,
                    pageNumber: pageNumber
                )
                : nil
            state.sliderPreview.previewLoading = false
        }
    }

    func updateSliderPreview(state: inout State, pageIndex: Int) -> Effect<Action> {
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: state.pages.count)
        guard clampedIndex < state.pages.count else {
            return .none
        }

        // The drag gesture reports every finger movement, so most calls land on the page already shown.
        let pageChanged = state.sliderPreview.previewPageIndex != clampedIndex
        state.sliderPreview.draftIndex = clampedIndex
        state.sliderPreview.previewVisible = true
        state.sliderPreview.previewPageIndex = clampedIndex
        guard pageChanged else { return .none }
        return showSliderPreview(pageIndex: clampedIndex, state: &state)
    }

    /// Shows the page's preview if it is on disk. Otherwise the bubble shows a spinner and the page is
    /// fetched ahead of the background queue.
    func showSliderPreview(pageIndex: Int, state: inout State) -> Effect<Action> {
        let target = SliderPreviewTarget(page: state.pages[pageIndex])
        let fileURL = ReaderSliderPreviewFeature.sliderPreviewFileURL(
            archiveId: state.currentArchiveId,
            pageNumber: target.pageNumber
        )
        if state.sliderPreview.previewStatus[target.pageNumber] == nil,
           ReaderSliderPreviewFeature.fileExists(fileURL) {
            state.sliderPreview.previewStatus[target.pageNumber] = .stored
        }

        let status = state.sliderPreview.previewStatus[target.pageNumber]
        state.sliderPreview.previewImageURL = status == .stored ? fileURL : nil
        switch status {
        case .stored:
            state.sliderPreview.previewLoading = false
            return .none
        case .fetching:
            state.sliderPreview.previewLoading = true
            return .none
        case .failed, nil:
            guard state.cached || state.sliderPreview.readyThumbnailPages.contains(target.pageNumber) else {
                // The server has not generated this page's thumbnail yet.
                state.sliderPreview.previewLoading = !state.sliderPreview.thumbnailJobsById.isEmpty
                return .none
            }
            state.sliderPreview.previewLoading = true
            return fetchForegroundSliderPreview(target, state: &state)
        }
    }

    /// Runs after more thumbnails become available: fetches the page under the slider if it was waiting,
    /// and starts the background prefetch wave if none is active.
    func advanceSliderPreviews(state: inout State) -> Effect<Action> {
        var waitingPreview: Effect<Action> = .none
        if state.sliderPreview.previewVisible,
           let previewIndex = state.sliderPreview.previewPageIndex,
           state.pages.indices.contains(previewIndex),
           state.sliderPreview.previewStatus[state.pages[previewIndex].pageNumber] == nil {
            waitingPreview = showSliderPreview(pageIndex: previewIndex, state: &state)
        }
        return .merge(waitingPreview, startSliderPrefetchIfNeeded(state: &state))
    }

    /// Starts one background prefetch wave for all ready, untried preview pages, nearest first.
    func startSliderPrefetchIfNeeded(state: inout State) -> Effect<Action> {
        guard !state.sliderPreview.prefetchStopped,
              !state.sliderPreview.prefetchInFlight,
              !state.pages.isEmpty else {
            return .none
        }

        let targets = sliderPreviewPrefetchTargets(state: state)
        guard !targets.isEmpty else { return .none }

        state.sliderPreview.prefetchInFlight = true
        let archiveId = state.currentArchiveId
        let cached = state.cached
        return .run(priority: .utility) { [targets] send in
            await runSliderPreviewPrefetch(
                targets: targets,
                archiveId: archiveId,
                cached: cached,
                send: send
            )
        }
        .cancellable(id: ReaderSliderPreviewFeature.CancelId.prefetch, cancelInFlight: true)
    }

    func sliderPreviewPrefetchTargets(state: State) -> [SliderPreviewTarget] {
        let anchor = ReaderPositioning.clampedPageIndex(
            (state.sliderPreview.previewVisible ? state.sliderPreview.previewPageIndex : nil)
                ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        var seenPages: Set<Int> = []
        var targets: [SliderPreviewTarget] = []
        let indices = ReaderSliderPreviewFeature.pageIndicesNearestFirst(
            from: anchor,
            count: state.pages.count
        )
        for index in indices {
            let page = state.pages[index]
            guard seenPages.insert(page.pageNumber).inserted else { continue }
            guard state.sliderPreview.previewStatus[page.pageNumber] == nil,
                  state.cached || state.sliderPreview.readyThumbnailPages.contains(page.pageNumber) else {
                continue
            }
            targets.append(SliderPreviewTarget(page: page))
        }
        return targets
    }

    func runSliderPreviewPrefetch(
        targets: [SliderPreviewTarget],
        archiveId: String,
        cached: Bool,
        send: Send<Action>
    ) async {
        guard !Task.isCancelled else { return }
        let limit = cached
            ? ReaderSliderPreviewFeature.previewGenerationLimit
            : ReaderSliderPreviewFeature.previewDownloadLimit
        await withTaskGroup(of: (Int, SliderPreviewFetchResult?).self) { group in
            var nextIndex = min(limit, targets.count)
            for target in targets.prefix(nextIndex) {
                addSliderPreviewPrefetchTask(to: &group, target: target, archiveId: archiveId, cached: cached)
            }

            var constrained = false
            while let (pageNumber, result) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let result {
                    await send(.sliderPreview(.previewFetched(pageNumber: pageNumber, result)))
                    if result == .networkConstrained {
                        constrained = true
                    }
                }
                if !constrained, nextIndex < targets.count, !Task.isCancelled {
                    addSliderPreviewPrefetchTask(
                        to: &group,
                        target: targets[nextIndex],
                        archiveId: archiveId,
                        cached: cached
                    )
                    nextIndex += 1
                }
            }
        }
        guard !Task.isCancelled else { return }
        await send(.sliderPreview(.prefetchFinished))
    }

    func addSliderPreviewPrefetchTask(
        to group: inout TaskGroup<(Int, SliderPreviewFetchResult?)>,
        target: SliderPreviewTarget,
        archiveId: String,
        cached: Bool
    ) {
        group.addTask {
            let result = await fetchSliderPreviewResult(
                target: target,
                archiveId: archiveId,
                cached: cached,
                background: true
            )
            return (target.pageNumber, result)
        }
    }

    func fetchForegroundSliderPreview(
        _ target: SliderPreviewTarget,
        state: inout State
    ) -> Effect<Action> {
        state.sliderPreview.previewStatus[target.pageNumber] = .fetching
        let archiveId = state.currentArchiveId
        let cached = state.cached
        return .run(priority: .userInitiated) { send in
            guard let result = await fetchSliderPreviewResult(
                target: target,
                archiveId: archiveId,
                cached: cached,
                background: false
            ), !Task.isCancelled else {
                return
            }
            await send(.sliderPreview(.previewFetched(pageNumber: target.pageNumber, result)))
        }
        .cancellable(id: ReaderSliderPreviewFeature.CancelId.fetch)
    }

    func fetchSliderPreviewResult(
        target: SliderPreviewTarget,
        archiveId: String,
        cached: Bool,
        background: Bool
    ) async -> SliderPreviewFetchResult? {
        guard !Task.isCancelled else { return nil }
        let fileURL = ReaderSliderPreviewFeature.sliderPreviewFileURL(
            archiveId: archiveId,
            pageNumber: target.pageNumber
        )
        if ReaderSliderPreviewFeature.fileExists(fileURL) {
            return .stored
        }
        return cached
            ? generateCachedSliderPreview(archiveId: archiveId, pageNumber: target.pageNumber, fileURL: fileURL)
            : await downloadSliderPreview(target: target, fileURL: fileURL, background: background)
    }

    func generateCachedSliderPreview(
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
                maxPixelSize: ReaderSliderPreviewFeature.cachedPreviewMaxPixelSize
            )
        }
        guard !Task.isCancelled else { return nil }
        if !stored {
            ReaderSliderPreviewFeature.logger.warning(
                "failed to generate cached slider preview. id=\(archiveId) page=\(pageNumber)"
            )
        }
        return stored ? .stored : .failed
    }

    func downloadSliderPreview(
        target: SliderPreviewTarget,
        fileURL: URL,
        background: Bool
    ) async -> SliderPreviewFetchResult? {
        do {
            let thumbnailData = try await service.retrieveGeneratedArchiveThumbnail(
                id: target.sourceArchiveId,
                page: target.sourcePageNumber,
                cacheBust: ReaderSliderPreviewFeature.sliderPreviewCacheBust(pageNumber: target.sourcePageNumber),
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
            ReaderSliderPreviewFeature.logger.warning("\(message)")
            return .failed
        }
    }

    func sliderPreviewSourceArchiveIds(in pages: IdentifiedArrayOf<PageFeature.State>) -> [String] {
        var ids = OrderedSet<String>()
        for page in pages {
            ids.append(page.sourceArchiveId)
        }
        return Array(ids)
    }

    func sliderPreviewReaderPageNumbers(
        in pages: IdentifiedArrayOf<PageFeature.State>,
        sourceArchiveId: String,
        sourcePageNumbers: Set<Int>? = nil
    ) -> Set<Int> {
        var result: Set<Int> = []
        for page in pages where page.sourceArchiveId == sourceArchiveId {
            if let sourcePageNumbers, !sourcePageNumbers.contains(page.sourcePageNumber) {
                continue
            }
            result.insert(page.pageNumber)
        }
        return result
    }
}
