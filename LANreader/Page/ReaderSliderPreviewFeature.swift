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

public struct ReaderSliderPreviewContext: Sendable {
    public let archiveId: String
    public let cached: Bool
    public let currentPageIndex: Int
    public let pageCount: Int
    private let pageAtIndex: @Sendable (Int) -> ReaderSliderPreviewPage

    public init(
        archiveId: String = "",
        cached: Bool = false,
        pages: [ReaderSliderPreviewPage] = [],
        currentPageIndex: Int = 0
    ) {
        self.archiveId = archiveId
        self.cached = cached
        self.currentPageIndex = currentPageIndex
        self.pageCount = pages.count
        self.pageAtIndex = { pages[$0] }
    }

    init(state: ArchiveReaderFeature.State) {
        let pages = state.pages
        self.archiveId = state.currentArchiveId
        self.cached = state.cached
        self.currentPageIndex = state.currentPageIndex
        self.pageCount = pages.count
        self.pageAtIndex = { ReaderSliderPreviewPage(page: pages[$0]) }
    }

    var isEmpty: Bool { pageCount == 0 }
    var indices: Range<Int> { 0..<pageCount }

    func page(at index: Int) -> ReaderSliderPreviewPage {
        pageAtIndex(index)
    }

    func containsPageNumber(_ pageNumber: Int) -> Bool {
        for index in indices where pageAtIndex(index).pageNumber == pageNumber {
            return true
        }
        return false
    }

    var archivePageCount: Int {
        var pageNumbers: Set<Int> = []
        for index in indices {
            pageNumbers.insert(pageAtIndex(index).pageNumber)
        }
        return pageNumbers.count
    }

    var sourceArchiveIds: [String] {
        var ids = OrderedSet<String>()
        for index in indices {
            ids.append(pageAtIndex(index).sourceArchiveId)
        }
        return Array(ids)
    }

    func readerPageNumbers(
        sourceArchiveId: String,
        sourcePageNumbers: Set<Int>? = nil
    ) -> Set<Int> {
        var result: Set<Int> = []
        for index in indices {
            let page = pageAtIndex(index)
            guard page.sourceArchiveId == sourceArchiveId else { continue }
            if let sourcePageNumbers, !sourcePageNumbers.contains(page.sourcePageNumber) {
                continue
            }
            result.insert(page.pageNumber)
        }
        return result
    }
}

@Reducer public struct ReaderSliderPreviewFeature: Sendable {
    private static let logger = Logger(label: "ReaderSliderPreviewFeature")
    private let staticContext: ReaderSliderPreviewContext?

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

    public init() {
        self.staticContext = nil
    }

    public init(context: ReaderSliderPreviewContext) {
        self.staticContext = context
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(
                state: &state,
                action: action,
                context: staticContext ?? ReaderSliderPreviewContext(),
                embed: { $0 }
            )
        }
    }

    func reduce<ParentAction>(
        state: inout State,
        action: Action,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        switch action {
        case .prepareThumbnails:
            return prepareThumbnails(state: &state, context: context, embed: embed)
        case let .thumbnailsQueued(results):
            return handleThumbnailsQueued(results, state: &state, context: context, embed: embed)
        case let .pollThumbnailJob(jobId, archiveId):
            return pollThumbnailJob(jobId: jobId, archiveId: archiveId, embed: embed)
        case let .thumbnailJobStatus(jobId, archiveId, status):
            handleThumbnailJobStatus(
                jobId: jobId, archiveId: archiveId, status: status, state: &state, context: context
            )
            return advancePreviews(state: &state, context: context, embed: embed)
        case let .thumbnailPollingFailed(jobId, _):
            state.thumbnailJobsById[jobId] = nil
            return advancePreviews(state: &state, context: context, embed: embed)
        case .dragStarted:
            return handleDragStarted(state: &state, context: context, embed: embed)
        case let .dragChanged(newValue):
            return handleDragChanged(newValue, state: &state, context: context, embed: embed)
        case .dragEnded:
            return handleDragEnded(state: &state, context: context, embed: embed)
        case let .previewFetched(pageNumber, result):
            handlePreviewFetched(pageNumber: pageNumber, result: result, state: &state, context: context)
            return .none
        case .prefetchFinished:
            state.prefetchInFlight = false
            return startPrefetchIfNeeded(state: &state, context: context, embed: embed)
        case .startPrefetchIfNeeded:
            return startPrefetchIfNeeded(state: &state, context: context, embed: embed)
        case .delegate:
            return .none
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
    func prepareThumbnails<ParentAction>(
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        guard !context.cached, !context.isEmpty else { return .none }
        guard state.thumbnailJobsById.isEmpty,
              state.readyThumbnailPages.count < context.archivePageCount else {
            return .none
        }

        let sourceArchiveIds = context.sourceArchiveIds
        return .run { send in
            var results: [SliderPreviewThumbnailQueueResult] = []
            for archiveId in sourceArchiveIds {
                let response = try await service.queuePageThumbnails(id: archiveId).value
                results.append(
                    SliderPreviewThumbnailQueueResult(archiveId: archiveId, response: response)
                )
            }
            await send(embed(.thumbnailsQueued(results)))
        } catch: { [archiveId = context.archiveId] error, _ in
            Self.logger.warning("failed to queue slider preview thumbnails. id=\(archiveId) \(error)")
        }
        .cancellable(id: CancelId.thumbnailQueue, cancelInFlight: true)
    }

    func handleThumbnailsQueued<ParentAction>(
        _ results: [SliderPreviewThumbnailQueueResult],
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        state.thumbnailJobsById = [:]
        var effect: Effect<ParentAction> = .none

        for result in results {
            if let jobId = result.response.job {
                state.thumbnailJobsById[jobId] = result.archiveId
                effect = .merge(
                    effect,
                    .send(embed(.pollThumbnailJob(jobId, archiveId: result.archiveId)))
                )
            } else {
                state.readyThumbnailPages.formUnion(
                    context.readerPageNumbers(sourceArchiveId: result.archiveId)
                )
            }
        }
        return .merge(effect, advancePreviews(state: &state, context: context, embed: embed))
    }

    func pollThumbnailJob<ParentAction>(
        jobId: Int,
        archiveId: String,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        .run { send in
            while true {
                let status = try await service.checkBasicJobStatus(id: jobId).value
                await send(embed(.thumbnailJobStatus(jobId, archiveId, status)))
                if status.state == "finished" || status.state == "failed" {
                    return
                }
                try await clock.sleep(for: .seconds(1))
            }
        } catch: { error, send in
            Self.logger.warning("failed to poll slider preview thumbnail job. id=\(archiveId) \(error)")
            await send(embed(.thumbnailPollingFailed(jobId, archiveId)))
        }
        .cancellable(id: CancelId.thumbnailPolling)
    }

    func handleThumbnailJobStatus(
        jobId: Int,
        archiveId: String,
        status: BasicJobStatus,
        state: inout State,
        context: ReaderSliderPreviewContext
    ) {
        state.readyThumbnailPages.formUnion(
            context.readerPageNumbers(
                sourceArchiveId: archiveId,
                sourcePageNumbers: status.processedPages
            )
        )
        if status.state == "finished" {
            state.readyThumbnailPages.formUnion(
                context.readerPageNumbers(sourceArchiveId: archiveId)
            )
            state.thumbnailJobsById[jobId] = nil
        } else if status.state == "failed" {
            state.thumbnailJobsById[jobId] = nil
        }
    }

    func handleDragStarted<ParentAction>(
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        state.dragging = true
        let previewIndex = ReaderPositioning.clampedPageIndex(
            state.draftIndex ?? context.currentPageIndex,
            pageCount: context.pageCount
        )
        state.previewVisible = !context.isEmpty
        guard !context.isEmpty else { return .none }
        return updatePreview(state: &state, pageIndex: previewIndex, context: context, embed: embed)
    }

    func handleDragChanged<ParentAction>(
        _ newValue: Int,
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        guard state.dragging, !context.isEmpty else { return .none }
        let targetIndex = ReaderPositioning.clampedPageIndex(newValue, pageCount: context.pageCount)
        return updatePreview(state: &state, pageIndex: targetIndex, context: context, embed: embed)
    }

    func handleDragEnded<ParentAction>(
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        state.dragging = false
        guard !context.isEmpty else {
            state.resetDisplayState()
            return .none
        }
        let targetIndex = ReaderPositioning.clampedPageIndex(
            state.draftIndex ?? context.currentPageIndex,
            pageCount: context.pageCount
        )
        state.resetDisplayState()
        return .send(embed(.delegate(.jumpRequested(targetIndex))))
    }

    func handlePreviewFetched(
        pageNumber: Int,
        result: SliderPreviewFetchResult,
        state: inout State,
        context: ReaderSliderPreviewContext
    ) {
        guard context.containsPageNumber(pageNumber) else {
            return
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
           context.indices.contains(previewIndex),
           context.page(at: previewIndex).pageNumber == pageNumber {
            let stored = state.previewStatus[pageNumber] == .stored
            state.previewImageURL = stored
                ? Self.sliderPreviewFileURL(archiveId: context.archiveId, pageNumber: pageNumber)
                : nil
            state.previewLoading = false
        }
    }

    func updatePreview<ParentAction>(
        state: inout State,
        pageIndex: Int,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: context.pageCount)
        guard clampedIndex < context.pageCount else {
            return .none
        }

        // The drag gesture reports every finger movement, so most calls land on the page already shown.
        let pageChanged = state.previewPageIndex != clampedIndex
        state.draftIndex = clampedIndex
        state.previewVisible = true
        state.previewPageIndex = clampedIndex
        guard pageChanged else { return .none }
        return showPreview(pageIndex: clampedIndex, state: &state, context: context, embed: embed)
    }

    /// Shows the page's preview if it is on disk. Otherwise the bubble shows a spinner and the page is
    /// fetched ahead of the background queue.
    func showPreview<ParentAction>(
        pageIndex: Int,
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        let page = context.page(at: pageIndex)
        let fileURL = Self.sliderPreviewFileURL(archiveId: context.archiveId, pageNumber: page.pageNumber)
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
            guard context.cached || state.readyThumbnailPages.contains(page.pageNumber) else {
                // The server has not generated this page's thumbnail yet.
                state.previewLoading = !state.thumbnailJobsById.isEmpty
                return .none
            }
            state.previewLoading = true
            return fetchForegroundPreview(page, state: &state, context: context, embed: embed)
        }
    }

    /// Runs after more thumbnails become available: fetches the page under the slider if it was waiting,
    /// and starts the background prefetch wave if none is active.
    func advancePreviews<ParentAction>(
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        var waitingPreview: Effect<ParentAction> = .none
        if state.previewVisible,
           let previewIndex = state.previewPageIndex,
           context.indices.contains(previewIndex),
           state.previewStatus[context.page(at: previewIndex).pageNumber] == nil {
            waitingPreview = showPreview(pageIndex: previewIndex, state: &state, context: context, embed: embed)
        }
        return .merge(waitingPreview, startPrefetchIfNeeded(state: &state, context: context, embed: embed))
    }

    /// Starts one background prefetch wave for all ready, untried preview pages, nearest first.
    func startPrefetchIfNeeded<ParentAction>(
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        guard !state.prefetchStopped,
              !state.prefetchInFlight,
              !context.isEmpty else {
            return .none
        }

        let targets = prefetchTargets(state: state, context: context)
        guard !targets.isEmpty else { return .none }

        state.prefetchInFlight = true
        let archiveId = context.archiveId
        let cached = context.cached
        return .run(priority: .utility) { [targets] send in
            await runPrefetch(
                targets: targets,
                archiveId: archiveId,
                cached: cached,
                send: send,
                embed: embed
            )
        }
        .cancellable(id: CancelId.prefetch, cancelInFlight: true)
    }

    func prefetchTargets(
        state: State,
        context: ReaderSliderPreviewContext
    ) -> [ReaderSliderPreviewPage] {
        let anchor = ReaderPositioning.clampedPageIndex(
            (state.previewVisible ? state.previewPageIndex : nil) ?? context.currentPageIndex,
            pageCount: context.pageCount
        )
        var seenPages: Set<Int> = []
        var targets: [ReaderSliderPreviewPage] = []
        for index in Self.pageIndicesNearestFirst(from: anchor, count: context.pageCount) {
            let page = context.page(at: index)
            guard seenPages.insert(page.pageNumber).inserted else { continue }
            guard state.previewStatus[page.pageNumber] == nil,
                  context.cached || state.readyThumbnailPages.contains(page.pageNumber) else {
                continue
            }
            targets.append(page)
        }
        return targets
    }

    func runPrefetch<ParentAction>(
        targets: [ReaderSliderPreviewPage],
        archiveId: String,
        cached: Bool,
        send: Send<ParentAction>,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) async {
        guard !Task.isCancelled else { return }
        let limit = cached ? Self.previewGenerationLimit : Self.previewDownloadLimit
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
                    await send(embed(.previewFetched(pageNumber: pageNumber, result)))
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
        await send(embed(.prefetchFinished))
    }

    func addPrefetchTask(
        to group: inout TaskGroup<(Int, SliderPreviewFetchResult?)>,
        target: ReaderSliderPreviewPage,
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

    func fetchForegroundPreview<ParentAction>(
        _ page: ReaderSliderPreviewPage,
        state: inout State,
        context: ReaderSliderPreviewContext,
        embed: @escaping @Sendable (Action) -> ParentAction
    ) -> Effect<ParentAction> {
        state.previewStatus[page.pageNumber] = .fetching
        let archiveId = context.archiveId
        let cached = context.cached
        return .run(priority: .userInitiated) { send in
            guard let result = await fetchPreviewResult(
                target: page,
                archiveId: archiveId,
                cached: cached,
                background: false
            ), !Task.isCancelled else {
                return
            }
            await send(embed(.previewFetched(pageNumber: page.pageNumber, result)))
        }
        .cancellable(id: CancelId.fetch)
    }

    func fetchPreviewResult(
        target: ReaderSliderPreviewPage,
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
            Self.logger.warning("failed to generate cached slider preview. id=\(archiveId) page=\(pageNumber)")
        }
        return stored ? .stored : .failed
    }

    func downloadPreview(
        target: ReaderSliderPreviewPage,
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
            Self.logger.warning("\(message)")
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
