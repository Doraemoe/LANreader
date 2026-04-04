import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift
import OrderedCollections
import UIKit

// swiftlint:disable type_body_length file_length

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
        @SharedReader(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0
        @SharedReader(.appStorage(SettingsKey.doublePageLayout)) var doublePageLayout = false

        var currentArchiveId = ""
        var currentPageIndex = 0
        var scrollRequest: ScrollRequest?
        var pages: IdentifiedArrayOf<PageFeature.State> = []
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
        case finishExtracting([String])
        case toggleControlUi(Bool?)
        case visiblePageChanged(Int)
        case requestJump(Int, source: ReaderNavigationSource)
        case navigate(ReaderNavigationDirection, source: ReaderNavigationSource)
        case scrollRequestHandled(UUID)
        case prepareSliderPreviewThumbnails
        case sliderPreviewThumbnailsQueued(PageThumbnailQueueResponse)
        case pollSliderPreviewThumbnailJob(Int)
        case sliderPreviewThumbnailJobStatus(BasicJobStatus)
        case sliderPreviewThumbnailPollingFailed
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

        Scope(state: \.autoPage, action: \.autoPage) {
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
                    let extractResponse = try await service.extractArchive(id: id).value
                    if extractResponse.pages.isEmpty {
                        logger.error("server returned empty pages. id=\(id)")
                        let errorMessage = String(localized: "error.page.empty")
                        await send(.setError(errorMessage))
                    }
                    await send(.finishExtracting(extractResponse.pages))
                } catch: { error, send in
                    logger.error("failed to extract archive page. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                    await send(.finishExtracting([]))
                }
            case let .finishExtracting(pages):
                if !pages.isEmpty {
                    let pageState = pages.enumerated().map { (index, page) in
                        let normalizedPage = String(page.dropFirst(1))
                        return PageFeature.State(
                            archiveId: state.currentArchiveId, pageId: normalizedPage, pageNumber: index + 1
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
                return .merge(
                    .send(.requestJump(state.currentPageIndex, source: .initialRestore)),
                    .send(.prepareSliderPreviewThumbnails)
                )
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
                return .run(priority: .background) { [state] _ in
                    try await clock.sleep(for: .seconds(0.5))
                    if state.serverProgress {
                        _ = try await service.updateArchiveReadProgress(
                            id: state.currentArchiveId, progress: pageNumber
                        ).value
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
            case .prepareSliderPreviewThumbnails:
                guard !state.cached, !state.pages.isEmpty else { return .none }
                guard state.sliderThumbnailJobId == nil,
                      state.sliderReadyThumbnailPages.count < state.archivePageCount else {
                    return .none
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
                    state.sliderPreviewLoading = state.sliderThumbnailJobId != nil
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

                return .run { [archiveId = state.currentArchiveId, pageNumber = page.pageNumber] send in
                    for attempt in 0..<6 {
                        let thumbnailData = try await service.retrieveGeneratedArchiveThumbnail(
                            id: archiveId,
                            page: pageNumber,
                            cacheBust: Self.sliderPreviewCacheBust(pageNumber: pageNumber, attempt: attempt)
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
                    state.sliderPreviewLoading = state.sliderThumbnailJobId != nil
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
                return .run { [id = state.currentArchiveId] send in
                    _ = try await service.updateArchiveThumbnail(id: id, page: pageNumber).value
                    guard let thumbnailData = try await service.retrieveArchiveThumbnail(id: id) else {
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
            case let .page(.element(id: id, action: .insertPage(mode))):
                guard let current = state.pages[id: id] else { return .none }
                let currentIndex = state.pages.index(id: id)!
                state.pages.insert(
                    PageFeature.State(
                        archiveId: state.currentArchiveId,
                        pageId: current.pageId,
                        pageNumber: current.pageNumber,
                        pageMode: mode,
                        cached: current.cached
                    ),
                    at: currentIndex + 1
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
                    if canAdvance && state.readDirection != ReadDirection.upDown.rawValue && state.doublePageLayout {
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
        state.sliderReadyThumbnailPages = []
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
            $store.scope(state: \.$alert, action: \.alert)
        )
        .overlay(content: {
            store.showAutoPageConfig ? AutomaticPageConfig(
                store: store.scope(state: \.autoPage, action: \.autoPage)
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
        .onDisappear {
            store.send(.cleanupSliderPreviewResources)
        }
    }

    // swiftlint:disable function_body_length
    @MainActor
    @ViewBuilder
    private func bottomToolbar(
        store: StoreOf<ArchiveReaderFeature>,
        readerSize: CGSize
    ) -> some View {
        if !store.pages.isEmpty {
            let isRightToLeft = store.resolvedReadDirection == .rightLeft
            let bubbleLayout = sliderPreviewBubbleLayout(readerSize: readerSize)
            let sliderHorizontalPadding: CGFloat = 16
            let bubbleVerticalSpacing: CGFloat = 14
            let sliderDisplayIndex = store.sliderDraftIndex ?? store.currentPageIndex
            let sliderDisplayValue = Double(sliderDisplayIndex)
            let displayIndex = ReaderPositioning.clampedPageIndex(
                sliderDisplayIndex,
                pageCount: store.pages.count
            )
            let displayPageNumber = store.pages[displayIndex].pageNumber
            let sliderMaxIndex = max(store.pages.count - 1, 1)

            VStack(spacing: 0) {
                if store.sliderPreviewVisible {
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, bubbleVerticalSpacing)
                    .environment(\.layoutDirection, .leftToRight)
                    .transition(.opacity)
                }

                Grid {
                    GridRow {
                        Button(action: {
                            let indexString = store.pages[store.safeCurrentPageIndex].id
                            store.send(.page(.element(id: indexString, action: .load(true))))
                        }, label: {
                            Image(systemName: "arrow.clockwise")
                        })
                        .disabled(store.cached)
                        Button {
                            store.send(.showAutoPageConfig)
                        } label: {
                            Image(systemName: "play")
                        }
                        .disabled(store.readDirection == ReadDirection.upDown.rawValue)
                        Text(String(format: "%d/%d",
                                    displayPageNumber,
                                    store.archivePageCount))
                        .bold()
                        Button {
                            if store.cached || store.inCache {
                                store.send(.removeCache)
                            } else {
                                store.send(.downloadPages)
                            }
                        } label: {
                            store.cached || store.inCache ?
                            Image(systemName: "trash") : Image(systemName: "arrowshape.down")
                        }
                        Button(action: {
                            Task {
                                store.send(.setThumbnail)
                            }
                        }, label: {
                            Image(systemName: "photo.artframe")
                        })
                        .disabled(store.settingThumbnail || store.cached)
                    }
                    GridRow {
                        GeometryReader { geometry in
                            let sliderWidth = max(geometry.size.width - sliderHorizontalPadding * 2, 1)

                            ZStack {
                                Slider(
                                    value: .constant(sliderDisplayValue),
                                    in: 0...Double(sliderMaxIndex),
                                    step: 1
                                )
                                .padding(.horizontal, sliderHorizontalPadding)
                                .scaleEffect(x: isRightToLeft ? -1 : 1, y: 1)
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
                                                store.send(
                                                    .sliderDragChanged(
                                                        SliderPreviewPositioning.pageIndex(
                                                            at: value.location.x,
                                                            sliderWidth: sliderWidth,
                                                            horizontalPadding: sliderHorizontalPadding,
                                                            sliderMaxIndex: sliderMaxIndex,
                                                            isRightToLeft: isRightToLeft
                                                        )
                                                    )
                                                )
                                            }
                                            .onEnded { value in
                                                store.send(
                                                    .sliderDragChanged(
                                                        SliderPreviewPositioning.pageIndex(
                                                            at: value.location.x,
                                                            sliderWidth: sliderWidth,
                                                            horizontalPadding: sliderHorizontalPadding,
                                                            sliderMaxIndex: sliderMaxIndex,
                                                            isRightToLeft: isRightToLeft
                                                        )
                                                    )
                                                )
                                                store.send(.sliderDragEnded)
                                            }
                                    )
                            }
                        }
                        .frame(height: 44)
                        .gridCellColumns(5)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .padding()
                .background(.thinMaterial)
            }
        }
    }
    // swiftlint:enable function_body_length

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
