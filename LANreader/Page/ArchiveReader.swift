import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift
import OrderedCollections
import UIKit

// swiftlint:disable type_body_length file_length

public struct ReaderExtractedPage: Equatable, Sendable {
    public let archiveId: String
    public let path: String
    public let archivePageNumber: Int

    public init(archiveId: String, path: String, archivePageNumber: Int) {
        self.archiveId = archiveId
        self.path = path
        self.archivePageNumber = archivePageNumber
    }
}

public struct SliderPreviewThumbnailQueueResult: Equatable, Sendable {
    public let archiveId: String
    public let response: PageThumbnailQueueResponse

    public init(archiveId: String, response: PageThumbnailQueueResponse) {
        self.archiveId = archiveId
        self.response = response
    }
}

@Reducer public struct ArchiveReaderFeature: Sendable {
    private let logger = Logger(label: "ArchiveReaderFeature")

    @ObservableState
    public struct State: Equatable, Sendable {
        @Presents var alert: AlertState<Action.Alert>?

        @SharedReader(.appStorage(SettingsKey.tapLeftKey)) var tapLeft = PageControl.next.rawValue
        @SharedReader(.appStorage(SettingsKey.tapMiddleKey)) var tapMiddle = PageControl.navigation.rawValue
        @SharedReader(.appStorage(SettingsKey.tapRightKey)) var tapRight = PageControl.previous.rawValue
        @SharedReader(.appStorage(SettingsKey.readDirection)) var readDirection = ReadDirection.leftRight.rawValue
        @SharedReader(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.splitPiorityLeft)) var piorityLeft = false
        @SharedReader(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0
        @SharedReader(.appStorage(SettingsKey.doublePageLayout)) var doublePageLayout = false

        var currentArchiveId = ""
        var currentPageIndex = 0
        var scrollRequest: ScrollRequest?
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var collectionScrolling = false
        var pendingSplitResolutions: [String: Bool] = [:]
        var fromStart = false
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""
        var showAutoPageConfig = false
        var autoPage = AutomaticPageFeature.State()
        var lastAutoPageIndex: Int?
        var cached = false
        var inCache = false
        var removeCacheSuccess = false
        var sliderDraftIndex: Int?
        var sliderDragging = false
        var sliderPreviewVisible = false
        var sliderPreviewPageIndex: Int?
        var sliderPreviewImageURL: URL?
        var sliderPreviewLoading = false
        var sliderThumbnailJobId: Int?
        var sliderThumbnailJobsById: [Int: String] = [:]
        var sliderReadyThumbnailPages: Set<Int> = []

        var allArchives: IdentifiedArrayOf<Shared<ArchiveItem>> = []

        init(
            currentArchiveId: String,
            allArchives: [Shared<ArchiveItem>],
            fromStart: Bool = false,
            cached: Bool = false
        ) {
            self.currentArchiveId = currentArchiveId
            self.allArchives = IdentifiedArray(uniqueElements: allArchives)
            self.fromStart = fromStart
            self.cached = cached
        }

        var resolvedReadDirection: ReadDirection {
            ReadDirection(rawValue: readDirection) ?? .leftRight
        }

        var safeCurrentPageIndex: Int {
            ReaderPositioning.clampedPageIndex(currentPageIndex, pageCount: pages.count)
        }

        var currentPage: PageFeature.State? {
            guard !pages.isEmpty else { return nil }
            return pages[safeCurrentPageIndex]
        }

        var archivePageNumbers: Set<Int> {
            Set(pages.map(\.pageNumber))
        }

        var archivePageCount: Int {
            archivePageNumbers.count
        }
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        case autoPage(AutomaticPageFeature.Action)
        case showAutoPageConfig
        case autoPageTick
        case setLastAutoPageIndex(Int?)
        case page(IdentifiedActionOf<PageFeature>)
        case extractArchive
        case finishExtracting([ReaderExtractedPage])
        case toggleControlUi(Bool?)
        case visiblePageChanged(Int)
        case requestJump(Int, source: ReaderNavigationSource)
        case navigate(ReaderNavigationDirection, source: ReaderNavigationSource)
        case scrollRequestHandled(UUID)
        case collectionScrollStarted
        case collectionScrollEnded
        case prepareSliderPreviewThumbnails
        case sliderPreviewThumbnailsQueued(PageThumbnailQueueResponse)
        case tankSliderPreviewThumbnailsQueued([SliderPreviewThumbnailQueueResult])
        case pollSliderPreviewThumbnailJob(Int)
        case sliderPreviewThumbnailJobStatus(BasicJobStatus)
        case sliderPreviewThumbnailPollingFailed
        case pollTankSliderPreviewThumbnailJob(Int, archiveId: String)
        case tankSliderPreviewThumbnailJobStatus(Int, String, BasicJobStatus)
        case tankSliderPreviewThumbnailPollingFailed(Int, String)
        case sliderDragStarted
        case sliderDragChanged(Int)
        case sliderDragEnded
        case loadSliderPreview(Int)
        case sliderPreviewLoaded(Int, URL)
        case sliderPreviewUnavailable(Int)
        case sliderPreviewFailed(Int)
        case cleanupSliderPreviewResources
        case setThumbnail
        case finishThumbnailLoading
        case setError(String)
        case setSuccess(String)
        case downloadPages
        case finishDownloadPages
        case removeCache
        case loadCached
        case removeCacheSuccess
        case loadPreviousArchive
        case loadNextArchive

        public enum Alert: Equatable, Sendable {
            case confirmDelete
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.imageService) var imageService
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid

    public enum CancelId: Sendable {
        case updateProgress
        case autoPage
        case sliderPreviewThumbnailQueue
        case sliderPreviewThumbnailPolling
        case sliderPreviewLoad
    }

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(\.autoPage, action: \.autoPage) {
            AutomaticPageFeature()
        }

        Reduce { state, action in
            switch action {
            case .loadCached:
               state.extracting = true

               let id = state.currentArchiveId
               let cacheFolder = LANraragiService.cachePath!
                   .appendingPathComponent(id, conformingTo: .folder)
               if let content = try? FileManager.default.contentsOfDirectory(
                   at: cacheFolder, includingPropertiesForKeys: []
               ) {
                   let pageState = content.compactMap { url in
                       let page = url.deletingPathExtension().lastPathComponent
                       if let pageNumber = Int(page) {
                           return PageFeature.State(archiveId: id, pageId: page, pageNumber: pageNumber, cached: true)
                       } else {
                           return nil
                       }
                   }
                       .sorted {
                           $0.pageNumber < $1.pageNumber
                       }
                   state.pages.append(contentsOf: pageState)
                   state.currentPageIndex = ReaderPositioning.defaultStartPageIndex(
                       pageCount: state.pages.count,
                       readDirection: state.resolvedReadDirection,
                       doublePageLayout: state.doublePageLayout
                   )
                   state.controlUiHidden = true
                   state.extracting = false
                   return .send(.requestJump(state.currentPageIndex, source: .initialRestore))
               } else {
                   self.resetSliderPreviewArchiveState(state: &state)
                   state.controlUiHidden = true
                   state.extracting = false
                   return .send(.setError(String(localized: "archive.cache.load.failed")))
               }
            case .extractArchive:
                state.extracting = true
                let id = state.currentArchiveId
                let isCached = try? database.existCache(id)
                if isCached == true {
                    state.inCache = true
                }
                return .run { send in
                    let pages: [ReaderExtractedPage]
                    if Self.isTankoubonArchiveId(id) {
                        let tankoubon = try await service.retrieveFullTankoubon(id: id).value
                        let archiveIds = Self.tankoubonArchiveIds(from: tankoubon)
                        var tankPages: [ReaderExtractedPage] = []

                        if archiveIds.isEmpty {
                            logger.error("tankoubon returned no archives. id=\(id)")
                        }

                        for archiveId in archiveIds {
                            let extractResponse = try await service.extractArchive(id: archiveId).value
                            if extractResponse.pages.isEmpty {
                                logger.error("server returned empty pages. id=\(archiveId)")
                            }
                            tankPages.append(
                                contentsOf: Self.extractedPages(from: extractResponse.pages, archiveId: archiveId)
                            )
                        }
                        pages = tankPages
                    } else {
                        let extractResponse = try await service.extractArchive(id: id).value
                        pages = Self.extractedPages(from: extractResponse.pages, archiveId: id)
                    }

                    if pages.isEmpty {
                        logger.error("server returned empty pages. id=\(id)")
                        let errorMessage = String(localized: "error.page.empty")
                        await send(.setError(errorMessage))
                    }
                    await send(.finishExtracting(pages))
                } catch: { error, send in
                    logger.error("failed to extract archive page. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                    await send(.finishExtracting([]))
                }
            case let .finishExtracting(pages):
                if !pages.isEmpty {
                    let pageState = pages.enumerated().map { (index, extractedPage) in
                        let normalizedPagePath = String(extractedPage.path.dropFirst(1))
                        return PageFeature.State(
                            archiveId: state.currentArchiveId,
                            pageId: normalizedPagePath,
                            pageNumber: index + 1,
                            sourceArchiveId: extractedPage.archiveId,
                            sourcePageNumber: extractedPage.archivePageNumber
                        )
                    }
                    state.pages.append(contentsOf: pageState)
                    guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return .none }
                    let pageIndexToShow = ReaderPositioning.initialPageIndex(
                        progress: currentArchive.wrappedValue.progress,
                        pageCount: state.pages.count,
                        fromStart: state.fromStart,
                        readDirection: state.resolvedReadDirection,
                        doublePageLayout: state.doublePageLayout
                    )
                    state.currentPageIndex = pageIndexToShow
                    state.controlUiHidden = true
                }
                state.extracting = false
                guard !state.pages.isEmpty else { return .none }
                let initialRestore = Effect<Action>.send(.requestJump(state.currentPageIndex, source: .initialRestore))
                return .merge(initialRestore, .send(.prepareSliderPreviewThumbnails))
            case let .toggleControlUi(show):
                if let shouldShow = show {
                    state.controlUiHidden = shouldShow
                } else {
                    state.controlUiHidden.toggle()
                }
                state.lastAutoPageIndex = nil
                self.resetSliderPreviewDisplayState(state: &state)
                return .merge(
                    .cancel(id: CancelId.autoPage),
                    .cancel(id: CancelId.sliderPreviewLoad)
                )
            case let .visiblePageChanged(index):
                guard !state.pages.isEmpty else { return .none }
                let clampedIndex = ReaderPositioning.clampedPageIndex(index, pageCount: state.pages.count)
                guard clampedIndex != state.currentPageIndex else { return .none }
                self.preparePendingSplitMode(state: &state, pageIndex: clampedIndex)
                state.currentPageIndex = clampedIndex
                guard let currentArchive = state.allArchives[id: state.currentArchiveId],
                      let page = state.currentPage else { return .none }

                let pageNumber = page.pageNumber
                let shouldClearNewFlag = pageNumber > 1 && currentArchive.wrappedValue.isNew
                currentArchive.withLock {
                    $0.progress = pageNumber
                    if shouldClearNewFlag {
                        $0.isNew = false
                    }
                }
                if state.cached {
                    return .none
                }
                let isTank = Self.isTankoubonArchiveId(state.currentArchiveId)
                return .run(priority: .background) { [state] _ in
                    try await clock.sleep(for: .seconds(0.5))
                    if state.serverProgress {
                        if isTank {
                            _ = try await service.updateTankoubonReadProgress(
                                id: state.currentArchiveId, progress: pageNumber
                            ).value
                        } else {
                            _ = try await service.updateArchiveReadProgress(
                                id: state.currentArchiveId, progress: pageNumber
                            ).value
                        }
                    }
                    if shouldClearNewFlag {
                        _ = try await service.clearNewFlag(id: state.currentArchiveId).value
                    }
                } catch: { [state] error, _ in
                    logger.error("failed to update archive progress. id=\(state.currentArchiveId) \(error)")
                }
                .cancellable(id: CancelId.updateProgress, cancelInFlight: true)
            case let .requestJump(index, source):
                guard !state.pages.isEmpty else { return .none }
                let clampedIndex = ReaderPositioning.clampedPageIndex(index, pageCount: state.pages.count)
                state.scrollRequest = ScrollRequest(
                    id: uuid(),
                    targetPageIndex: clampedIndex,
                    source: source,
                    animated: source != .slider && source != .initialRestore
                )
                return .none
            case .collectionScrollStarted:
                state.collectionScrolling = true
                return .none
            case .collectionScrollEnded:
                state.collectionScrolling = false
                self.applyPendingSplitResolutions(state: &state)
                return .none
            case .prepareSliderPreviewThumbnails:
                guard !state.cached, !state.pages.isEmpty else { return .none }
                guard state.sliderThumbnailJobId == nil,
                      state.sliderThumbnailJobsById.isEmpty,
                      state.sliderReadyThumbnailPages.count < state.archivePageCount else {
                    return .none
                }

                if Self.isTankoubonArchiveId(state.currentArchiveId) {
                    let sourceArchiveIds = Array(OrderedSet(state.pages.map(\.sourceArchiveId)))
                    return .run { send in
                        var results: [SliderPreviewThumbnailQueueResult] = []
                        for archiveId in sourceArchiveIds {
                            let response = try await service.queuePageThumbnails(id: archiveId).value
                            results.append(
                                SliderPreviewThumbnailQueueResult(archiveId: archiveId, response: response)
                            )
                        }
                        await send(.tankSliderPreviewThumbnailsQueued(results))
                    } catch: { [archiveId = state.currentArchiveId] error, _ in
                        logger.warning("failed to queue tank slider preview thumbnails. id=\(archiveId) \(error)")
                    }
                    .cancellable(id: CancelId.sliderPreviewThumbnailQueue, cancelInFlight: true)
                }

                return .run { [archiveId = state.currentArchiveId] send in
                    let response = try await service.queuePageThumbnails(id: archiveId).value
                    await send(.sliderPreviewThumbnailsQueued(response))
                } catch: { [archiveId = state.currentArchiveId] error, _ in
                    logger.warning("failed to queue slider preview thumbnails. id=\(archiveId) \(error)")
                }
                .cancellable(id: CancelId.sliderPreviewThumbnailQueue, cancelInFlight: true)
            case let .sliderPreviewThumbnailsQueued(response):
                if let jobId = response.job {
                    state.sliderThumbnailJobId = jobId
                    return .send(.pollSliderPreviewThumbnailJob(jobId))
                }
                state.sliderThumbnailJobId = nil
                state.sliderReadyThumbnailPages = state.archivePageNumbers
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    return .send(.loadSliderPreview(previewPageIndex))
                }
                return .none
            case let .tankSliderPreviewThumbnailsQueued(results):
                state.sliderThumbnailJobsById = [:]
                var effect: Effect<Action> = .none

                for result in results {
                    if let jobId = result.response.job {
                        state.sliderThumbnailJobsById[jobId] = result.archiveId
                        effect = .merge(
                            effect,
                            .send(.pollTankSliderPreviewThumbnailJob(jobId, archiveId: result.archiveId))
                        )
                    } else {
                        state.sliderReadyThumbnailPages.formUnion(
                            Self.readerPageNumbers(in: state.pages, sourceArchiveId: result.archiveId)
                        )
                    }
                }

                state.sliderThumbnailJobId = state.sliderThumbnailJobsById.keys.sorted().first
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    effect = .merge(effect, .send(.loadSliderPreview(previewPageIndex)))
                }
                return effect
            case let .pollSliderPreviewThumbnailJob(jobId):
                return .run { send in
                    while true {
                        let status = try await service.checkBasicJobStatus(id: jobId).value
                        await send(.sliderPreviewThumbnailJobStatus(status))
                        if status.state == "finished" || status.state == "failed" {
                            return
                        }
                        try await clock.sleep(for: .seconds(1))
                    }
                } catch: { [archiveId = state.currentArchiveId] error, send in
                    logger.warning("failed to poll slider preview thumbnail job. id=\(archiveId) \(error)")
                    await send(.sliderPreviewThumbnailPollingFailed)
                }
                .cancellable(id: CancelId.sliderPreviewThumbnailPolling, cancelInFlight: true)
            case let .sliderPreviewThumbnailJobStatus(status):
                state.sliderReadyThumbnailPages.formUnion(status.processedPages)
                if status.state == "finished" {
                    state.sliderReadyThumbnailPages.formUnion(state.archivePageNumbers)
                    state.sliderThumbnailJobId = nil
                } else if status.state == "failed" {
                    state.sliderThumbnailJobId = nil
                }
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    return .send(.loadSliderPreview(previewPageIndex))
                }
                return .none
            case .sliderPreviewThumbnailPollingFailed:
                state.sliderThumbnailJobId = nil
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    return .send(.loadSliderPreview(previewPageIndex))
                }
                return .none
            case let .pollTankSliderPreviewThumbnailJob(jobId, archiveId):
                return .run { send in
                    while true {
                        let status = try await service.checkBasicJobStatus(id: jobId).value
                        await send(.tankSliderPreviewThumbnailJobStatus(jobId, archiveId, status))
                        if status.state == "finished" || status.state == "failed" {
                            return
                        }
                        try await clock.sleep(for: .seconds(1))
                    }
                } catch: { error, send in
                    logger.warning("failed to poll tank slider preview thumbnail job. id=\(archiveId) \(error)")
                    await send(.tankSliderPreviewThumbnailPollingFailed(jobId, archiveId))
                }
                .cancellable(id: CancelId.sliderPreviewThumbnailPolling)
            case let .tankSliderPreviewThumbnailJobStatus(jobId, archiveId, status):
                state.sliderReadyThumbnailPages.formUnion(
                    Self.readerPageNumbers(
                        in: state.pages,
                        sourceArchiveId: archiveId,
                        sourcePageNumbers: status.processedPages
                    )
                )
                if status.state == "finished" {
                    state.sliderReadyThumbnailPages.formUnion(
                        Self.readerPageNumbers(in: state.pages, sourceArchiveId: archiveId)
                    )
                    state.sliderThumbnailJobsById[jobId] = nil
                } else if status.state == "failed" {
                    state.sliderThumbnailJobsById[jobId] = nil
                }
                state.sliderThumbnailJobId = state.sliderThumbnailJobsById.keys.sorted().first
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    return .send(.loadSliderPreview(previewPageIndex))
                }
                return .none
            case let .tankSliderPreviewThumbnailPollingFailed(jobId, _):
                state.sliderThumbnailJobsById[jobId] = nil
                state.sliderThumbnailJobId = state.sliderThumbnailJobsById.keys.sorted().first
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    return .send(.loadSliderPreview(previewPageIndex))
                }
                return .none
            case .sliderDragStarted:
                state.sliderDragging = true
                let previewIndex = ReaderPositioning.clampedPageIndex(
                    state.sliderDraftIndex ?? state.currentPageIndex,
                    pageCount: state.pages.count
                )
                state.sliderPreviewVisible = !state.pages.isEmpty
                guard !state.pages.isEmpty else { return .none }
                return self.updateSliderPreview(state: &state, pageIndex: previewIndex)
            case let .sliderDragChanged(newValue):
                guard state.sliderDragging else { return .none }
                guard !state.pages.isEmpty else { return .none }
                let targetIndex = ReaderPositioning.clampedPageIndex(
                    newValue,
                    pageCount: state.pages.count
                )
                return self.updateSliderPreview(state: &state, pageIndex: targetIndex)
            case .sliderDragEnded:
                state.sliderDragging = false
                guard !state.pages.isEmpty else {
                    self.resetSliderPreviewDisplayState(state: &state)
                    return .cancel(id: CancelId.sliderPreviewLoad)
                }
                let targetIndex = ReaderPositioning.clampedPageIndex(
                    state.sliderDraftIndex ?? state.currentPageIndex,
                    pageCount: state.pages.count
                )
                self.resetSliderPreviewDisplayState(state: &state)
                return .merge(
                    .cancel(id: CancelId.sliderPreviewLoad),
                    .send(.requestJump(targetIndex, source: .slider))
                )
            case let .loadSliderPreview(pageIndex):
                guard !state.pages.isEmpty else { return .none }
                let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: state.pages.count)
                guard state.sliderPreviewVisible, state.sliderPreviewPageIndex == clampedIndex else { return .none }

                let page = state.pages[clampedIndex]
                if self.restoreExistingSliderPreviewIfAvailable(state: &state, pageIndex: clampedIndex) {
                    return .none
                }

                guard state.cached || state.sliderReadyThumbnailPages.contains(page.pageNumber) else {
                    state.sliderPreviewImageURL = nil
                    state.sliderPreviewLoading = self.hasPendingSliderPreviewThumbnailJobs(state: state)
                    return .none
                }

                state.sliderPreviewImageURL = nil
                state.sliderPreviewLoading = true

                if state.cached {
                    return .run { [archiveId = state.currentArchiveId, pageNumber = page.pageNumber] send in
                        guard let cacheFolder = LANraragiService.cachePath?.appendingPathComponent(archiveId),
                              let sourceURL = imageService.storedImagePath(
                                  folderUrl: cacheFolder,
                                  pageNumber: "\(pageNumber)"
                              ) else {
                            throw ArchiveReaderError.previewSourceUnavailable
                        }

                        let previewFileURL = Self.sliderPreviewFileURL(
                            archiveId: archiveId,
                            pageNumber: pageNumber
                        )
                        guard imageService.generatePreviewImage(
                            sourceUrl: sourceURL,
                            destinationUrl: previewFileURL
                        ) else {
                            throw ArchiveReaderError.previewGenerationFailed
                        }
                        await send(.sliderPreviewLoaded(clampedIndex, previewFileURL))
                    } catch: { [archiveId = state.currentArchiveId] error, send in
                        logger.warning("failed to generate cached slider preview. id=\(archiveId) \(error)")
                        await send(.sliderPreviewFailed(clampedIndex))
                    }
                    .cancellable(id: CancelId.sliderPreviewLoad, cancelInFlight: true)
                }

                let archiveId = state.currentArchiveId
                let pageNumber = page.pageNumber
                let sourceArchiveId = page.sourceArchiveId
                let sourcePageNumber = page.sourcePageNumber

                return .run { send in
                    for attempt in 0..<6 {
                        let thumbnailData = try await service.retrieveGeneratedArchiveThumbnail(
                            id: sourceArchiveId,
                            page: sourcePageNumber,
                            cacheBust: Self.sliderPreviewCacheBust(pageNumber: sourcePageNumber, attempt: attempt)
                        )
                        if let thumbnailData {
                            let previewFileURL = Self.sliderPreviewFileURL(
                                archiveId: archiveId,
                                pageNumber: pageNumber
                            )
                            if imageService.storePreviewImage(
                                imageData: thumbnailData,
                                destinationUrl: previewFileURL
                            ) {
                                await send(.sliderPreviewLoaded(clampedIndex, previewFileURL))
                                return
                            }
                        }
                        try await clock.sleep(for: .milliseconds(300))
                    }
                    await send(.sliderPreviewUnavailable(clampedIndex))
                } catch: { [archiveId = state.currentArchiveId] error, send in
                    logger.warning("failed to fetch slider preview thumbnail. id=\(archiveId) \(error)")
                    await send(.sliderPreviewFailed(clampedIndex))
                }
                .cancellable(id: CancelId.sliderPreviewLoad, cancelInFlight: true)
            case let .sliderPreviewLoaded(pageIndex, url):
                guard state.sliderPreviewPageIndex == pageIndex else { return .none }
                state.sliderPreviewImageURL = url
                state.sliderPreviewLoading = false
                return .none
            case let .sliderPreviewUnavailable(pageIndex):
                guard state.sliderPreviewPageIndex == pageIndex else { return .none }
                if !self.restoreExistingSliderPreviewIfAvailable(state: &state, pageIndex: pageIndex) {
                    state.sliderPreviewLoading = self.hasPendingSliderPreviewThumbnailJobs(state: state)
                    state.sliderPreviewImageURL = nil
                }
                return .none
            case let .sliderPreviewFailed(pageIndex):
                guard state.sliderPreviewPageIndex == pageIndex else { return .none }
                if !self.restoreExistingSliderPreviewIfAvailable(state: &state, pageIndex: pageIndex) {
                    state.sliderPreviewImageURL = nil
                }
                state.sliderPreviewLoading = false
                return .none
            case .cleanupSliderPreviewResources:
                self.resetSliderPreviewArchiveState(state: &state)
                return .merge(
                    .cancel(id: CancelId.sliderPreviewThumbnailQueue),
                    .cancel(id: CancelId.sliderPreviewThumbnailPolling),
                    .cancel(id: CancelId.sliderPreviewLoad)
                )
            case let .navigate(direction, source):
                guard let targetIndex = ReaderPositioning.adjacentPageIndex(
                    from: state.currentPageIndex,
                    direction: direction,
                    pageCount: state.pages.count,
                    readDirection: state.resolvedReadDirection,
                    doublePageLayout: state.doublePageLayout
                ) else {
                    return .none
                }
                self.preparePendingSplitMode(state: &state, pageIndex: targetIndex)
                state.scrollRequest = ScrollRequest(
                    id: uuid(),
                    targetPageIndex: targetIndex,
                    source: source,
                    animated: true
                )
                return .none
            case let .scrollRequestHandled(id):
                guard state.scrollRequest?.id == id else { return .none }
                state.scrollRequest = nil
                return .none
            case .setThumbnail:
                state.settingThumbnail = true
                guard let currentPage = state.currentPage else {
                    state.settingThumbnail = false
                    return .none
                }
                let pageNumber = currentPage.pageNumber
                let isTank = Self.isTankoubonArchiveId(state.currentArchiveId)
                return .run { [id = state.currentArchiveId, pageNumber, isTank] send in
                    let thumbnailData: Data?
                    if isTank {
                        _ = try await service.updateTankoubonThumbnail(id: id, page: pageNumber).value
                        thumbnailData = try await service.retrieveTankoubonThumbnail(id: id)
                    } else {
                        _ = try await service.updateArchiveThumbnail(id: id, page: pageNumber).value
                        thumbnailData = try await service.retrieveArchiveThumbnail(id: id)
                    }
                    guard let thumbnailData else {
                        throw ArchiveReaderError.thumbnailUnavailableAfterUpdate
                    }
                    var archiveThumbnail = ArchiveThumbnail(
                        id: id,
                        thumbnail: thumbnailData,
                        lastUpdate: Date()
                    )
                    try database.saveArchiveThumbnail(&archiveThumbnail)
                    let successMessage = String(localized: "archive.thumbnail.set")
                    await send(.setSuccess(successMessage))
                    await send(.finishThumbnailLoading)
                } catch: { [id = state.currentArchiveId] error, send in
                    logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                    await send(.finishThumbnailLoading)
                }
            case .finishThumbnailLoading:
                state.settingThumbnail = false
                guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return .none }
                currentArchive.withLock {
                    $0.refresh = true
                }
                return .none
            case let .setSuccess(message):
                state.successMessage = message
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            case .binding:
                return .none
            case let .page(.element(id: id, action: .storedImageResolved(shouldDisplayAsSplitPages))):
                self.handleSplitResolution(
                    id: id,
                    shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
                    state: &state
                )
                return .none
            case .page:
                return .none
            case .showAutoPageConfig:
                state.showAutoPageConfig = true
                return .none
            case .autoPage(.startAutoPage):
                state.showAutoPageConfig = false
                state.controlUiHidden = true
                return .send(.autoPageTick)
            case .autoPage(.cancelAutoPage):
                state.showAutoPageConfig = false
                return .none
            case .autoPage:
                return .none
            case .autoPageTick:
                let idx = state.currentPageIndex
                var canAdvance = true
                if state.lastAutoPageIndex == idx {
                    canAdvance = false
                } else if idx == (state.pages.count - 1) {
                    return .cancel(id: CancelId.autoPage)
                } else {
                    if idx >= 0 && idx < state.pages.count {
                        let page = state.pages[idx]
                        if !page.imageLoaded {
                            canAdvance = false
                        }
                    } else {
                        return .cancel(id: CancelId.autoPage)
                    }
                    if canAdvance
                        && state.readDirection != ReadDirection.upDown.rawValue
                        && state.doublePageLayout {
                        let previousIdx = idx - 1
                        if previousIdx >= 0 && previousIdx < state.pages.count {
                            let page = state.pages[previousIdx]
                            if !page.imageLoaded {
                                canAdvance = false
                            }
                        }
                    }
                }

                return .run { [idx, canAdvance, interval = state.autoPageInterval] send in
                    if canAdvance {
                        try? await clock.sleep(for: .seconds(interval))
                        await send(.navigate(.next, source: .autoPage))
                        await send(.setLastAutoPageIndex(idx))
                    } else {
                        try? await clock.sleep(for: .milliseconds(300))
                    }
                    await send(.autoPageTick)
                }.cancellable(id: CancelId.autoPage)
            case let .setLastAutoPageIndex(index):
                state.lastAutoPageIndex = index
                return .none
            case .downloadPages:
                return .run { [state] send in
                    var requested: [String] = []
                    for page in state.pages where !requested.contains(where: { requestedId in
                        requestedId == page.pageId
                    }) {
                        await service.backgroupFetchArchivePage(
                            page: page.pageId,
                            archiveId: state.currentArchiveId,
                            pageNumber: page.pageNumber
                        )
                        requested.append(page.pageId)
                    }
                    guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return }
                    var cache = ArchiveCache(
                        id: state.currentArchiveId,
                        title: currentArchive.wrappedValue.name,
                        tags: currentArchive.wrappedValue.tags,
                        thumbnail: Data(),
                        cached: false,
                        totalPages: requested.count,
                        lastUpdate: Date()
                    )
                    try database.saveCache(&cache)
                    await send(.finishDownloadPages)
                } catch: { error, send in
                    logger.error("failed to cache archive \(error)")
                    await send(.setError(error.localizedDescription))
                }
            case .finishDownloadPages:
                let successMessage = String(localized: "archive.cache.added")
                state.successMessage = successMessage
                return .none
            case .removeCache:
                state.alert = AlertState {
                    TextState("archive.cache.remove.message")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("cancel")
                    }
                }
                return .none
            case .alert(.presented(.confirmDelete)):
                state.removeCacheSuccess = false
                return .run { [id = state.currentArchiveId] send in
                    let deleted = try database.deleteCache(id)
                    if deleted != true {
                        let errorMessage = String(localized: "archive.cache.remove.failed")
                        await send(.setError(errorMessage))
                    } else {
                        let cacheFolder = LANraragiService.cachePath!
                            .appendingPathComponent(id, conformingTo: .folder)
                        try? FileManager.default.removeItem(at: cacheFolder)
                        await send(.removeCacheSuccess)
                    }
                } catch: { [id = state.currentArchiveId] error, send in
                    logger.error("failed to remove archive cache, id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                }
            case .removeCacheSuccess:
                state.removeCacheSuccess = true
                return .none
            case .alert:
                return .none
            case .loadPreviousArchive:
                guard let currentIndex = state.allArchives.firstIndex(where: { $0.id == state.currentArchiveId }) else {
                    return .none
                }
                guard currentIndex > 0 else { return .none }
                let newShared = state.allArchives[currentIndex - 1]
                state.currentArchiveId = newShared.wrappedValue.id
                self.resetState(state: &state)
                return .merge(
                    .cancel(id: CancelId.sliderPreviewThumbnailQueue),
                    .cancel(id: CancelId.sliderPreviewThumbnailPolling),
                    .cancel(id: CancelId.sliderPreviewLoad),
                    state.cached ? .send(.loadCached) : .send(.extractArchive)
                )
            case .loadNextArchive:
                guard let currentIndex = state.allArchives.firstIndex(where: { $0.id == state.currentArchiveId }) else {
                    return .none
                }
                guard currentIndex < state.allArchives.count - 1 else { return .none }
                let newShared = state.allArchives[currentIndex + 1]
                state.currentArchiveId = newShared.wrappedValue.id
                self.resetState(state: &state)
                return .merge(
                    .cancel(id: CancelId.sliderPreviewThumbnailQueue),
                    .cancel(id: CancelId.sliderPreviewThumbnailPolling),
                    .cancel(id: CancelId.sliderPreviewLoad),
                    state.cached ? .send(.loadCached) : .send(.extractArchive)
                )
            }
        }
        .forEach(\.pages, action: \.page) {
            PageFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }

    private static func isTankoubonArchiveId(_ id: String) -> Bool {
        id.hasPrefix("TANK_")
    }

    private static func tankoubonArchiveIds(from response: TankoubonFullResponse) -> [String] {
        if let archives = response.result.archives, !archives.isEmpty {
            return archives
        }
        return response.result.fullData?.map(\.arcid) ?? []
    }

    private static func extractedPages(from pages: [String], archiveId: String) -> [ReaderExtractedPage] {
        pages.enumerated().map { index, path in
            ReaderExtractedPage(archiveId: archiveId, path: path, archivePageNumber: index + 1)
        }
    }

    private static func readerPageNumbers(
        in pages: IdentifiedArrayOf<PageFeature.State>,
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

    private func preparePendingSplitMode(
        state: inout State,
        pageIndex: Int
    ) {
        guard state.splitImage else { return }
        guard state.pages.indices.contains(pageIndex) else { return }
        guard state.pages[pageIndex].pageMode == .loading else { return }

        state.pages[pageIndex].pendingSplitMode = if pageIndex < state.currentPageIndex {
            PageMode.trailingSplitMode(priorityLeft: state.piorityLeft)
        } else {
            PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        }
    }

    private func handleSplitResolution(
        id: PageFeature.State.ID,
        shouldDisplayAsSplitPages: Bool,
        state: inout State
    ) {
        guard state.pages[id: id] != nil else { return }
        if state.collectionScrolling {
            state.pendingSplitResolutions[id] = shouldDisplayAsSplitPages
            return
        }

        applySplitResolution(
            id: id,
            shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
            state: &state
        )
    }

    private func applyPendingSplitResolutions(state: inout State) {
        let pending = state.pendingSplitResolutions
        state.pendingSplitResolutions = [:]

        for pageId in state.pages.map(\.id) where pending[pageId] != nil {
            applySplitResolution(
                id: pageId,
                shouldDisplayAsSplitPages: pending[pageId] ?? false,
                state: &state
            )
        }
    }

    private func applySplitResolution(
        id: PageFeature.State.ID,
        shouldDisplayAsSplitPages: Bool,
        state: inout State
    ) {
        let visiblePageId = state.currentPage?.id

        guard shouldDisplayAsSplitPages,
              state.splitImage else {
            normalizePageDisplay(id: id, state: &state)
            preserveVisiblePage(id: visiblePageId, state: &state)
            return
        }

        applySplitPageDisplay(id: id, state: &state)
        preserveVisiblePage(id: visiblePageId, state: &state)
    }

    private func applySplitPageDisplay(
        id: PageFeature.State.ID,
        state: inout State
    ) {
        guard let current = state.pages[id: id],
              let sourcePageIndex = state.pages.index(id: id) else {
            return
        }

        let splitMode: PageMode
        if current.pageMode.isSplitMode {
            splitMode = current.pageMode
        } else {
            splitMode = current.pendingSplitMode
                ?? PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        }

        state.pages[id: id]?.pageMode = splitMode
        state.pages[id: id]?.pendingSplitMode = nil
        state.pages[id: id]?.imageLoaded = true

        guard let siblingMode = splitMode.splitSiblingMode else { return }
        var insertedPage = PageFeature.State(
            archiveId: state.currentArchiveId,
            pageId: current.pageId,
            pageNumber: current.pageNumber,
            sourceArchiveId: current.sourceArchiveId,
            sourcePageNumber: current.sourcePageNumber,
            pageMode: siblingMode,
            cached: current.cached
        )
        insertedPage.imageLoaded = true
        guard state.pages[id: insertedPage.id] == nil else { return }

        let leadingSplitMode = PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        let insertAfterCurrent = splitMode == leadingSplitMode
        let insertedIndex = insertAfterCurrent ? sourcePageIndex + 1 : sourcePageIndex
        state.pages.insert(insertedPage, at: insertedIndex)
    }

    private func normalizePageDisplay(
        id: PageFeature.State.ID,
        state: inout State
    ) {
        guard let current = state.pages[id: id] else { return }
        let canonicalId = "\(current.pageId)-\(PageMode.normal.identitySuffix)"
        let keepId = state.pages[id: canonicalId] == nil ? id : canonicalId

        state.pages[id: keepId]?.pageMode = .normal
        state.pages[id: keepId]?.pendingSplitMode = nil
        state.pages[id: keepId]?.imageLoaded = true

        state.pages.removeAll {
            $0.pageId == current.pageId && $0.id != keepId && $0.pageMode.isSplitMode
        }
    }

    private func preserveVisiblePage(
        id visiblePageId: PageFeature.State.ID?,
        state: inout State
    ) {
        if let visiblePageId,
           let preservedIndex = state.pages.index(id: visiblePageId) {
            state.currentPageIndex = preservedIndex
        } else {
            state.currentPageIndex = ReaderPositioning.clampedPageIndex(
                state.currentPageIndex,
                pageCount: state.pages.count
            )
        }
    }

    private func updateSliderPreview(
        state: inout State,
        pageIndex: Int
    ) -> Effect<Action> {
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: state.pages.count)
        guard clampedIndex < state.pages.count else {
            return .none
        }

        state.sliderDraftIndex = clampedIndex
        state.sliderPreviewVisible = true
        state.sliderPreviewPageIndex = clampedIndex
        if self.restoreExistingSliderPreviewIfAvailable(state: &state, pageIndex: clampedIndex) {
            return .none
        }
        return .send(.loadSliderPreview(clampedIndex))
    }

    private func resetSliderPreviewDisplayState(state: inout State) {
        state.sliderDraftIndex = nil
        state.sliderDragging = false
        state.sliderPreviewVisible = false
        state.sliderPreviewPageIndex = nil
        state.sliderPreviewImageURL = nil
        state.sliderPreviewLoading = false
    }

    private func resetSliderPreviewArchiveState(state: inout State) {
        resetSliderPreviewDisplayState(state: &state)
        state.sliderThumbnailJobId = nil
        state.sliderThumbnailJobsById = [:]
        state.sliderReadyThumbnailPages = []
    }

    private func hasPendingSliderPreviewThumbnailJobs(state: State) -> Bool {
        state.sliderThumbnailJobId != nil || !state.sliderThumbnailJobsById.isEmpty
    }

    private func previewFileURL(state: State, pageIndex: Int) -> URL? {
        guard pageIndex >= 0, pageIndex < state.pages.count else {
            return nil
        }
        return Self.sliderPreviewFileURL(
            archiveId: state.currentArchiveId,
            pageNumber: state.pages[pageIndex].pageNumber
        )
    }

    private func restoreExistingSliderPreviewIfAvailable(
        state: inout State,
        pageIndex: Int
    ) -> Bool {
        guard let existingPreviewURL = self.previewFileURL(state: state, pageIndex: pageIndex),
              FileManager.default.fileExists(atPath: existingPreviewURL.path(percentEncoded: false)) else {
            return false
        }
        state.sliderPreviewImageURL = existingPreviewURL
        state.sliderPreviewLoading = false
        return true
    }

    private static func sliderPreviewRootDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LANreader", isDirectory: true)
            .appendingPathComponent("reader-preview", isDirectory: true)
    }

    private static func sliderPreviewDirectory(archiveId: String) -> URL {
        sliderPreviewRootDirectory().appendingPathComponent(archiveId, isDirectory: true)
    }

    private static func sliderPreviewFileURL(archiveId: String, pageNumber: Int) -> URL {
        sliderPreviewDirectory(archiveId: archiveId)
            .appendingPathComponent("\(pageNumber).jpg", isDirectory: false)
    }

    private static func sliderPreviewCacheBust(pageNumber: Int, attempt: Int) -> Int {
        Int(Date().timeIntervalSince1970 * 1000) + pageNumber + attempt
    }

    func resetState(state: inout State) {
        state.pages = []
        state.currentPageIndex = 0
        state.scrollRequest = nil
        state.collectionScrolling = false
        state.pendingSplitResolutions = [:]
        state.inCache = false
        state.errorMessage = ""
        state.successMessage = ""
        resetSliderPreviewArchiveState(state: &state)
    }
}

private enum ArchiveReaderError: LocalizedError {
    case thumbnailUnavailableAfterUpdate
    case previewSourceUnavailable
    case previewGenerationFailed

    var errorDescription: String? {
        switch self {
        case .thumbnailUnavailableAfterUpdate:
            return "Thumbnail is not ready yet. Please try again in a moment."
        case .previewSourceUnavailable:
            return "Preview source image is unavailable."
        case .previewGenerationFailed:
            return "Preview image generation failed."
        }
    }
}

struct ArchiveReader: View {
    @Bindable var store: StoreOf<ArchiveReaderFeature>
    let navigationHelper: NavigationHelper?

    var body: some View {
        let flip = store.readDirection == ReadDirection.rightLeft.rawValue
        GeometryReader { geometry in
            Group {
                if store.readDirection == ReadDirection.upDown.rawValue {
                    UIPageCollection(store: store)
                } else {
                    UIPageCollection(store: store)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                }
            }
            .overlay(alignment: .bottom) {
                if !store.controlUiHidden {
                    bottomToolbar(store: store, readerSize: geometry.size)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                }
            }
            .overlay {
                if store.extracting {
                    LoadingView(geometry: geometry)
                }
            }
        }
        .alert(
            $store.scope(\.$alert, action: \.alert)
        )
        .overlay(content: {
            store.showAutoPageConfig ? AutomaticPageConfig(
                store: store.scope(\.autoPage, action: \.autoPage)
            ) : nil
        })
        .task {
            if store.pages.isEmpty {
                if store.cached {
                    store.send(.loadCached)
                } else {
                    store.send(.extractArchive)
                }
            }
            guard let currentArchive = store.allArchives[id: store.currentArchiveId] else { return }
            if currentArchive.wrappedValue.extension == "rar" || currentArchive.wrappedValue.extension == "cbr" {
                let banner = NotificationBanner(
                    title: String(localized: "warning"),
                    subtitle: String(localized: "warning.file.type"),
                    style: .warning
                )
                banner.show()
            }
        }
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                banner.show()
                store.send(.toggleControlUi(false))
                store.send(.setError(""))
            }
        }
        .onChange(of: store.successMessage) {
            if !store.successMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "success"),
                    subtitle: store.successMessage,
                    style: .success
                )
                banner.show()
                store.send(.setSuccess(""))
            }
        }
        .onChange(of: store.removeCacheSuccess) {
            if store.removeCacheSuccess {
                navigationHelper?.pop()
            }
        }
    }

    @MainActor
    @ViewBuilder
    private func bottomToolbar(
        store: StoreOf<ArchiveReaderFeature>,
        readerSize: CGSize
    ) -> some View {
        if !store.pages.isEmpty {
            let isRightToLeft = store.resolvedReadDirection == .rightLeft
            let bubbleLayout = sliderPreviewBubbleLayout(readerSize: readerSize)
            let sliderHorizontalPadding = ReaderToolbarMetrics.sliderHorizontalPadding
            let sliderDisplayIndex = store.sliderDraftIndex ?? store.currentPageIndex
            let sliderDisplayValue = Double(sliderDisplayIndex)
            let displayIndex = ReaderPositioning.clampedPageIndex(
                sliderDisplayIndex,
                pageCount: store.pages.count
            )
            let displayPageNumber = store.pages[displayIndex].pageNumber
            let sliderMaxIndex = max(store.pages.count - 1, 1)
            let sliderContext = ReaderSliderContext(
                displayValue: sliderDisplayValue,
                maxIndex: sliderMaxIndex,
                horizontalPadding: sliderHorizontalPadding,
                isRightToLeft: isRightToLeft
            )

            VStack(spacing: ReaderToolbarMetrics.previewBottomSpacing) {
                if store.sliderPreviewVisible {
                    sliderPreviewRow(
                        store: store,
                        displayIndex: displayIndex,
                        isRightToLeft: isRightToLeft,
                        bubbleLayout: bubbleLayout,
                        sliderHorizontalPadding: sliderHorizontalPadding
                    )
                }

                readerControlPanel(
                    store: store,
                    displayPageNumber: displayPageNumber,
                    sliderContext: sliderContext
                )
            }
            .padding(.horizontal, ReaderToolbarMetrics.outerHorizontalPadding)
            .padding(.bottom, ReaderToolbarMetrics.bottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func sliderPreviewRow(
        store: StoreOf<ArchiveReaderFeature>,
        displayIndex: Int,
        isRightToLeft: Bool,
        bubbleLayout: SliderPreviewBubbleLayout,
        sliderHorizontalPadding: CGFloat
    ) -> some View {
        GeometryReader { geometry in
            let bubbleLeadingX = SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: displayIndex,
                pageCount: store.pages.count,
                track: SliderPreviewTrackGeometry(
                    rowWidth: geometry.size.width,
                    sliderHorizontalPadding: sliderHorizontalPadding,
                    bubbleWidth: bubbleLayout.width
                ),
                isRightToLeft: isRightToLeft
            )

            SliderPreviewBubble(
                imageURL: store.sliderPreviewImageURL,
                loading: store.sliderPreviewLoading,
                imageHeight: bubbleLayout.imageHeight
            )
            .frame(width: bubbleLayout.width)
            .offset(x: bubbleLeadingX)
            .allowsHitTesting(false)
        }
        .frame(height: bubbleLayout.rowHeight)
        .environment(\.layoutDirection, .leftToRight)
        .transition(.opacity)
    }

    private func readerControlPanel(
        store: StoreOf<ArchiveReaderFeature>,
        displayPageNumber: Int,
        sliderContext: ReaderSliderContext
    ) -> some View {
        VStack(spacing: 10) {
            readerActionRow(
                store: store,
                displayPageNumber: displayPageNumber
            )
            readerPageSlider(
                store: store,
                context: sliderContext
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: ReaderToolbarMetrics.panelCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ReaderToolbarMetrics.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private func readerActionRow(
        store: StoreOf<ArchiveReaderFeature>,
        displayPageNumber: Int
    ) -> some View {
        let cacheActionRemoves = store.cached || store.inCache
        let autoPageDisabled = store.readDirection == ReadDirection.upDown.rawValue

        return HStack(spacing: 10) {
            readerToolbarButton(
                systemImage: "arrow.clockwise",
                tint: Color(uiColor: .systemBlue),
                disabled: store.cached,
                accessibilityLabel: "archive.reader.reload.currentPage"
            ) {
                let indexString = store.pages[store.safeCurrentPageIndex].id
                store.send(.page(.element(id: indexString, action: .load(true))))
            }

            readerToolbarButton(
                systemImage: "play.fill",
                tint: Color(uiColor: .systemPurple),
                disabled: autoPageDisabled,
                accessibilityLabel: "archive.reader.autoPage"
            ) {
                store.send(.showAutoPageConfig)
            }

            Spacer(minLength: 2)

            pageCounter(
                currentPage: displayPageNumber,
                pageCount: store.archivePageCount
            )

            Spacer(minLength: 2)

            readerToolbarButton(
                systemImage: cacheActionRemoves ? "trash.fill" : "tray.and.arrow.down.fill",
                tint: cacheActionRemoves ? Color(uiColor: .systemRed) : Color(uiColor: .systemOrange),
                accessibilityLabel: cacheActionRemoves ? "archive.reader.cache.remove" : "archive.reader.pages.download"
            ) {
                if cacheActionRemoves {
                    store.send(.removeCache)
                } else {
                    store.send(.downloadPages)
                }
            }

            readerToolbarButton(
                systemImage: "photo.artframe",
                tint: Color(uiColor: .systemTeal),
                disabled: store.settingThumbnail || store.cached,
                accessibilityLabel: "archive.thumbnail.current"
            ) {
                store.send(.setThumbnail)
            }
        }
    }

    private func pageCounter(currentPage: Int, pageCount: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(currentPage)")
            Text(verbatim: "/")
                .foregroundStyle(.secondary)
            Text("\(pageCount)")
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(minWidth: 86, minHeight: 36)
        .foregroundStyle(.primary)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(
            Text(verbatim: pageCounterAccessibilityLabel(currentPage: currentPage, pageCount: pageCount))
        )
    }

    private func pageCounterAccessibilityLabel(currentPage: Int, pageCount: Int) -> String {
        let format = String(localized: "archive.reader.page.accessibility %lld %lld")
        return String(format: format, Int64(currentPage), Int64(pageCount))
    }

    private func readerToolbarButton(
        systemImage: String,
        tint: Color,
        disabled: Bool = false,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary : tint)
                .frame(width: ReaderToolbarMetrics.buttonSize, height: ReaderToolbarMetrics.buttonSize)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.82), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func readerPageSlider(
        store: StoreOf<ArchiveReaderFeature>,
        context: ReaderSliderContext
    ) -> some View {
        GeometryReader { geometry in
            let sliderWidth = max(geometry.size.width - context.horizontalPadding * 2, 1)

            ZStack {
                Slider(
                    value: .constant(context.displayValue),
                    in: 0...Double(context.maxIndex),
                    step: 1
                )
                .tint(Color(uiColor: .systemBlue))
                .padding(.horizontal, context.horizontalPadding)
                .scaleEffect(x: context.isRightToLeft ? -1 : 1, y: 1)
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !store.sliderDragging {
                                    store.send(.sliderDragStarted)
                                }
                                sendSliderDragChanged(
                                    store: store,
                                    locationX: value.location.x,
                                    sliderWidth: sliderWidth,
                                    context: context
                                )
                            }
                            .onEnded { value in
                                sendSliderDragChanged(
                                    store: store,
                                    locationX: value.location.x,
                                    sliderWidth: sliderWidth,
                                    context: context
                                )
                                store.send(.sliderDragEnded)
                            }
                    )
            }
        }
        .frame(height: 34)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(Text("archive.reader.page.slider"))
    }

    private func sendSliderDragChanged(
        store: StoreOf<ArchiveReaderFeature>,
        locationX: CGFloat,
        sliderWidth: CGFloat,
        context: ReaderSliderContext
    ) {
        store.send(
            .sliderDragChanged(
                SliderPreviewPositioning.pageIndex(
                    at: locationX,
                    sliderWidth: sliderWidth,
                    horizontalPadding: context.horizontalPadding,
                    sliderMaxIndex: context.maxIndex,
                    isRightToLeft: context.isRightToLeft
                )
            )
        )
    }

    private func sliderPreviewBubbleLayout(readerSize: CGSize) -> SliderPreviewBubbleLayout {
        let aspectRatio: CGFloat = 248 / 176
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let minWidth: CGFloat = isPad ? 260 : 176
        let maxWidth: CGFloat = isPad ? 360 : 220
        let widthScale: CGFloat = isPad ? 0.34 : 0.44
        let availableWidth = max(readerSize.width - 48, minWidth)
        let targetWidth = min(max(availableWidth * widthScale, minWidth), maxWidth)
        let maxImageHeight = max(min(readerSize.height * (isPad ? 0.52 : 0.45), isPad ? 520 : 420), 248)
        let width = min(targetWidth, maxImageHeight / aspectRatio)
        let imageHeight = max((width * aspectRatio).rounded(.toNearestOrAwayFromZero), 248)

        return SliderPreviewBubbleLayout(
            width: width.rounded(.toNearestOrAwayFromZero),
            imageHeight: imageHeight,
            rowHeight: imageHeight + 52
        )
    }
}

private struct ReaderSliderContext {
    let displayValue: Double
    let maxIndex: Int
    let horizontalPadding: CGFloat
    let isRightToLeft: Bool
}

private enum ReaderToolbarMetrics {
    static let outerHorizontalPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 26
    static let previewBottomSpacing: CGFloat = 12
    static let sliderHorizontalPadding: CGFloat = 16
    static let buttonSize: CGFloat = 44
}

enum SliderPreviewPositioning {
    static func visualNormalized(
        pageIndex: Int,
        pageCount: Int,
        isRightToLeft: Bool
    ) -> CGFloat {
        guard pageCount > 1 else { return 0 }
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: pageCount)
        let logicalNormalized = CGFloat(clampedIndex) / CGFloat(pageCount - 1)
        return isRightToLeft ? (1 - logicalNormalized) : logicalNormalized
    }

    static func bubbleLeadingX(
        pageIndex: Int,
        pageCount: Int,
        track: SliderPreviewTrackGeometry,
        isRightToLeft: Bool
    ) -> CGFloat {
        let sliderWidth = max(track.rowWidth - track.sliderHorizontalPadding * 2, 1)
        let thumbCenterX = track.sliderHorizontalPadding + (
            sliderWidth * visualNormalized(
                pageIndex: pageIndex,
                pageCount: pageCount,
                isRightToLeft: isRightToLeft
            )
        )
        let maxLeading = max(track.rowWidth - track.bubbleWidth, 0)
        return max(0, min(thumbCenterX - (track.bubbleWidth / 2), maxLeading))
    }

    static func pageIndex(
        at locationX: CGFloat,
        sliderWidth: CGFloat,
        horizontalPadding: CGFloat,
        sliderMaxIndex: Int,
        isRightToLeft: Bool
    ) -> Int {
        let adjustedX = min(
            max(locationX - horizontalPadding, 0),
            sliderWidth
        )
        let visualNormalized = sliderWidth == 0 ? 0 : adjustedX / sliderWidth
        let logicalNormalized = isRightToLeft ? (1 - visualNormalized) : visualNormalized
        return Int((logicalNormalized * CGFloat(sliderMaxIndex)).rounded())
    }
}

struct SliderPreviewTrackGeometry {
    let rowWidth: CGFloat
    let sliderHorizontalPadding: CGFloat
    let bubbleWidth: CGFloat
}

private struct SliderPreviewBubble: View {
    let imageURL: URL?
    let loading: Bool
    let imageHeight: CGFloat

    private var previewImage: UIImage? {
        guard let imageURL,
              let image = UIImage(contentsOfFile: imageURL.path(percentEncoded: false)) else {
            return nil
        }
        if let preparedImage = image.preparingForDisplay() {
            return preparedImage
        }
        return image
    }

    var body: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            } else if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .frame(height: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

private struct SliderPreviewBubbleLayout {
    let width: CGFloat
    let imageHeight: CGFloat
    let rowHeight: CGFloat
}
// swiftlint:enable type_body_length file_length
