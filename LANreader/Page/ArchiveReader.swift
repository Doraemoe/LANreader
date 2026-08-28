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

public struct StampCreationTarget: Equatable, Sendable {
    let sourceArchiveId: String
    let sourcePageNumber: Int
    let position: ArchiveStampPosition
}

public struct StampEditingTarget: Equatable, Sendable {
    let stampId: String
    let sourceArchiveId: String
    let sourcePageNumber: Int
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
        @Shared(.appStorage(SettingsKey.doublePageLayout)) var doublePageLayout = false
        @SharedReader(.appStorage(SettingsKey.fitPageWidth)) var fitPageWidth = false
        @Shared(.appStorage(SettingsKey.showStamps)) var showStamps = false
        @SharedReader(.appStorage(SettingsKey.restartFinished)) var restartFinished = false

        var currentArchiveId = ""
        var currentPageIndex = 0
        var spreadPairingOffset = 0
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
        var currentTankoubonDetails: TankoubonDetailsMetadata?
        var sliderDraftIndex: Int?
        var sliderDragging = false
        var sliderPreviewVisible = false
        var sliderPreviewPageIndex: Int?
        var sliderPreviewImageURL: URL?
        var sliderPreviewLoading = false
        var sliderThumbnailJobsById: [Int: String] = [:]
        var sliderReadyThumbnailPages: Set<Int> = []
        /// Median aspect ratio of the pages measured so far, used to size pages that have not been
        /// measured yet. Pages within an archive are near-uniform, so this converges almost immediately.
        var estimatedPageAspectRatio: Double = ReaderPageLayout.defaultAspectRatio
        var stampCreationTarget: StampCreationTarget?
        var stampComment = ""
        var stampEditingTarget: StampEditingTarget?
        var stampEditText = ""
        var stampRequestInFlight = false
        var stampsSupported: Bool?

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

        var chapters: [ArchiveChapter] {
            guard let currentArchive = allArchives[id: currentArchiveId] else {
                return []
            }
            return currentArchive.wrappedValue.toc ?? []
        }

        var canOpenDetails: Bool {
            guard !extracting else { return false }
            guard currentArchiveId.isTankoubonArchiveId else { return true }
            guard !cached else { return true }
            return currentTankoubonDetails?.id == currentArchiveId
        }

        /// Double page layout only applies to horizontal reading, and split wide images is the mutually
        /// exclusive alternative enforced by the read settings screen.
        var canToggleDoublePageLayout: Bool {
            !pages.isEmpty && resolvedReadDirection != .upDown && !splitImage
        }

        var canUseStamps: Bool {
            !cached && stampsSupported != false
        }

        var shouldShowStamps: Bool {
            canUseStamps && showStamps
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
        case stampsSupportResolved(Bool?)
        case finishExtracting([ReaderExtractedPage], TankoubonDetailsMetadata?)
        case primePageAspectRatios
        case pageAspectRatiosPrimed([Int: Double])
        case toggleControlUi(Bool?)
        case toggleDoublePageLayout
        case toggleStampsVisibility
        case stampCreationRequested(pageId: String, position: ArchiveStampPosition)
        case stampCommentChanged(String)
        case cancelStampCreation
        case confirmStampCreation
        case stampCreated(
            target: StampCreationTarget,
            stamp: ArchiveStamp,
            refreshedStamps: [ArchiveStamp]?
        )
        case stampCreationFailed(target: StampCreationTarget, content: String)
        case stampEditingRequested(pageId: String, stamp: ArchiveStamp)
        case stampEditTextChanged(String)
        case cancelStampEditing
        case confirmStampEditing
        case confirmStampDeletion
        case stampUpdated(target: StampEditingTarget, content: String)
        case stampUpdateFailed(target: StampEditingTarget, content: String)
        case stampDeleted(target: StampEditingTarget)
        case stampDeleteFailed(target: StampEditingTarget, content: String)
        case visiblePageChanged(Int)
        case chapterSelected(Int)
        case requestJump(Int, source: ReaderNavigationSource)
        case navigate(ReaderNavigationDirection, source: ReaderNavigationSource)
        case scrollRequestHandled(UUID)
        case collectionScrollStarted
        case collectionScrollEnded
        case prepareSliderPreviewThumbnails
        case sliderPreviewThumbnailsQueued([SliderPreviewThumbnailQueueResult])
        case pollSliderPreviewThumbnailJob(Int, archiveId: String)
        case sliderPreviewThumbnailJobStatus(Int, String, BasicJobStatus)
        case sliderPreviewThumbnailPollingFailed(Int, String)
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
        case primePageAspectRatios
        case stampCreation
        case stampMutation
    }

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(\.autoPage, action: \.autoPage) {
            AutomaticPageFeature()
        }

        Reduce<State, Action> { (state: inout State, action: Action) -> Effect<Action> in
            switch action {
            case .loadCached:
               state.extracting = true

               let id = state.currentArchiveId
               let cacheFolder = LANraragiService.cachePath!
                   .appendingPathComponent(id, conformingTo: .folder)
               if let content = try? FileManager.default.contentsOfDirectory(
                   at: cacheFolder, includingPropertiesForKeys: []
               ) {
                   let pageState: [PageFeature.State] = content.compactMap { url in
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
                   let cachedArchive = state.allArchives[id: id]?.wrappedValue
                   let cachedProgress = cachedArchive?.progress ?? 0
                   let restartFinishedArchive = state.restartFinished && ReaderPositioning.isFinished(
                       progress: cachedProgress,
                       archivePageCount: cachedArchive?.pagecount ?? 0
                   )
                   state.currentPageIndex = ReaderPositioning.initialPageIndex(
                       progress: cachedProgress,
                       pageCount: state.pages.count,
                       fromStart: state.fromStart,
                       restartFinishedArchive: restartFinishedArchive,
                       readDirection: state.resolvedReadDirection,
                       doublePageLayout: state.doublePageLayout,
                       spreadOffset: state.spreadPairingOffset
                   )
                   state.controlUiHidden = true
                   state.extracting = false
                   return .merge(
                       .send(.requestJump(state.currentPageIndex, source: .initialRestore)),
                       .send(.primePageAspectRatios)
                   )
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
                    let stampsSupported = await service.stampSupportForCurrentServer()
                    await send(.stampsSupportResolved(stampsSupported))
                    let pages: [ReaderExtractedPage]
                    var tankoubonDetails: TankoubonDetailsMetadata?
                    if id.isTankoubonArchiveId {
                        let tankoubon = try await service.retrieveFullTankoubon(id: id).value
                        var details = TankoubonDetailsMetadata(response: tankoubon)
                        let archiveIds = Self.tankoubonArchiveIds(from: tankoubon)
                        let archiveMetadata = Dictionary(
                            (tankoubon.result.fullData ?? []).map { ($0.arcid, $0) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        var tankPages: [ReaderExtractedPage] = []
                        var tankChapters: [ArchiveChapter] = []

                        if archiveIds.isEmpty {
                            logger.error("tankoubon returned no archives. id=\(id)")
                        }

                        for archiveId in archiveIds {
                            let extractResponse = try await service.extractArchive(id: archiveId).value
                            if extractResponse.pages.isEmpty {
                                logger.error("server returned empty pages. id=\(archiveId)")
                            }
                            let extractedPages = Self.extractedPages(
                                from: extractResponse.pages,
                                archiveId: archiveId
                            )
                            tankChapters.append(
                                contentsOf: Self.tankoubonChapters(
                                    from: archiveMetadata[archiveId],
                                    pageOffset: tankPages.count,
                                    extractedPageCount: extractedPages.count
                                )
                            )
                            tankPages.append(contentsOf: extractedPages)
                        }
                        details.toc = tankChapters.isEmpty ? nil : tankChapters
                        tankoubonDetails = details
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
                    await send(.finishExtracting(pages, tankoubonDetails))
                } catch: { error, send in
                    logger.error("failed to extract archive page. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                    await send(.finishExtracting([], nil))
                }
            case let .stampsSupportResolved(isSupported):
                state.stampsSupported = isSupported
                guard isSupported == false else { return .none }
                state.stampCreationTarget = nil
                state.stampComment = ""
                state.stampEditingTarget = nil
                state.stampEditText = ""
                state.stampRequestInFlight = false
                for pageId in state.pages.ids {
                    state.pages[id: pageId]?.stampsLoading = false
                    state.pages[id: pageId]?.stampsLoaded = true
                }
                return .none
            case let .finishExtracting(pages, tankoubonDetails):
                state.currentTankoubonDetails = tankoubonDetails
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
                    if state.currentArchiveId.isTankoubonArchiveId {
                        currentArchive.withLock {
                            $0.toc = tankoubonDetails?.toc
                        }
                    }
                    let archive = currentArchive.wrappedValue
                    let restartFinishedArchive = state.restartFinished && ReaderPositioning.isFinished(
                        progress: archive.progress,
                        archivePageCount: archive.pagecount
                    )
                    let pageIndexToShow = ReaderPositioning.initialPageIndex(
                        progress: archive.progress,
                        pageCount: state.pages.count,
                        fromStart: state.fromStart,
                        restartFinishedArchive: restartFinishedArchive,
                        readDirection: state.resolvedReadDirection,
                        doublePageLayout: state.doublePageLayout,
                        spreadOffset: state.spreadPairingOffset
                    )
                    state.currentPageIndex = pageIndexToShow
                    state.controlUiHidden = true
                }
                state.extracting = false
                guard !state.pages.isEmpty else { return .none }
                let initialRestore = Effect<Action>.send(.requestJump(state.currentPageIndex, source: .initialRestore))
                return .merge(
                    initialRestore,
                    .send(.primePageAspectRatios),
                    .send(.prepareSliderPreviewThumbnails)
                )
            case .primePageAspectRatios:
                guard let folder = state.pages.first?.folder else { return .none }
                return .run(priority: .utility) { send in
                    let aspectRatios = imageService.storedImageAspectRatios(folderUrl: folder)
                    guard !aspectRatios.isEmpty else { return }
                    await send(.pageAspectRatiosPrimed(aspectRatios))
                }
                .cancellable(id: CancelId.primePageAspectRatios, cancelInFlight: true)
            case let .pageAspectRatiosPrimed(aspectRatios):
                for pageId in state.pages.ids {
                    guard let page = state.pages[id: pageId], page.imageAspectRatio == nil else { continue }
                    guard let aspectRatio = aspectRatios[page.pageNumber] else { continue }
                    state.pages[id: pageId]?.imageAspectRatio = aspectRatio
                }
                self.updateEstimatedPageAspectRatio(state: &state)
                return .none
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
            case .toggleDoublePageLayout:
                guard state.canToggleDoublePageLayout else { return .none }
                let enabled = !state.doublePageLayout
                state.spreadPairingOffset = enabled ? state.safeCurrentPageIndex % 2 : 0
                state.$doublePageLayout.withLock { $0 = enabled }
                let targetIndex = ReaderPositioning.canonicalPageIndex(
                    forVisibleIndex: state.currentPageIndex,
                    pageCount: state.pages.count,
                    readDirection: state.resolvedReadDirection,
                    doublePageLayout: enabled,
                    spreadOffset: state.spreadPairingOffset
                )
                return .send(.requestJump(targetIndex, source: .layoutChange))
            case .toggleStampsVisibility:
                guard state.canUseStamps else { return .none }
                let showsStamps = !state.showStamps
                state.$showStamps.withLock { $0 = showsStamps }
                return .none
            case let .stampCreationRequested(pageId, position):
                guard state.canUseStamps,
                      !state.stampRequestInFlight,
                      state.stampEditingTarget == nil,
                      let page = state.pages[id: pageId],
                      !page.cached,
                      page.imageLoaded else {
                    return .none
                }
                state.stampCreationTarget = StampCreationTarget(
                    sourceArchiveId: page.sourceArchiveId,
                    sourcePageNumber: page.sourcePageNumber,
                    position: position
                )
                state.stampComment = ""
                return .none
            case let .stampCommentChanged(comment):
                state.stampComment = comment
                return .none
            case .cancelStampCreation:
                state.stampCreationTarget = nil
                state.stampComment = ""
                return .none
            case .confirmStampCreation:
                guard let target = state.stampCreationTarget else { return .none }
                let draft = state.stampComment
                let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return .none }
                state.stampCreationTarget = nil
                state.stampComment = ""
                state.stampRequestInFlight = true
                let logContext = "archive=\(target.sourceArchiveId) page=\(target.sourcePageNumber)"
                return .run { send in
                    do {
                        let response = try await service.addStamp(
                            id: target.sourceArchiveId,
                            page: target.sourcePageNumber,
                            content: content,
                            position: target.position.rawValue
                        ).value
                        guard response.success == 1 else {
                            logger.warning("server rejected stamp creation. \(logContext)")
                            await send(.stampCreationFailed(target: target, content: draft))
                            return
                        }
                        let stamp = ArchiveStamp(
                            id: response.stampId,
                            position: target.position.rawValue,
                            content: content
                        )
                        let refreshedStamps: [ArchiveStamp]?
                        do {
                            refreshedStamps = try await service.retrieveStamps(
                                id: target.sourceArchiveId,
                                page: target.sourcePageNumber
                            ).value.result
                        } catch {
                            logger.warning(
                                "failed to refresh stamps after creation. \(logContext) \(error.localizedDescription)"
                            )
                            refreshedStamps = nil
                        }
                        await send(.stampCreated(
                            target: target,
                            stamp: stamp,
                            refreshedStamps: refreshedStamps
                        ))
                    } catch {
                        logger.warning("failed to create stamp. \(logContext) \(error.localizedDescription)")
                        await send(.stampCreationFailed(target: target, content: draft))
                    }
                }
                .cancellable(id: CancelId.stampCreation, cancelInFlight: true)
            case let .stampCreated(target, stamp, refreshedStamps):
                state.stampRequestInFlight = false
                let matchingPageIds = state.pages.compactMap { page in
                    page.sourceArchiveId == target.sourceArchiveId
                        && page.sourcePageNumber == target.sourcePageNumber
                        ? page.id
                        : nil
                }
                guard !matchingPageIds.isEmpty else {
                    return .none
                }
                for pageId in matchingPageIds {
                    if let refreshedStamps {
                        state.pages[id: pageId]?.stamps = refreshedStamps
                        state.pages[id: pageId]?.stampsLoaded = true
                        state.pages[id: pageId]?.stampsLoading = false
                    } else {
                        if state.pages[id: pageId]?.stamps.contains(stamp) == false {
                            state.pages[id: pageId]?.stamps.append(stamp)
                        }
                        state.pages[id: pageId]?.stampsLoaded = false
                        state.pages[id: pageId]?.stampsLoading = false
                    }
                }
                state.$showStamps.withLock { $0 = true }
                guard refreshedStamps == nil else { return .none }
                return .merge(matchingPageIds.map { pageId in
                    .send(.page(.element(id: pageId, action: .loadStamps)))
                })
            case let .stampCreationFailed(target, content):
                state.stampRequestInFlight = false
                state.stampCreationTarget = target
                state.stampComment = content
                state.errorMessage = String(localized: "archive.reader.stamp.add.failed")
                return .none
            case let .stampEditingRequested(pageId, stamp):
                guard state.canUseStamps,
                      !state.stampRequestInFlight,
                      state.stampCreationTarget == nil,
                      let stampId = stamp.id,
                      !stampId.isEmpty,
                      let page = state.pages[id: pageId],
                      !page.cached,
                      page.stamps.contains(where: { $0.id == stampId }) else {
                    return .none
                }
                state.stampEditingTarget = StampEditingTarget(
                    stampId: stampId,
                    sourceArchiveId: page.sourceArchiveId,
                    sourcePageNumber: page.sourcePageNumber
                )
                state.stampEditText = stamp.content
                return .none
            case let .stampEditTextChanged(content):
                state.stampEditText = content
                return .none
            case .cancelStampEditing:
                state.stampEditingTarget = nil
                state.stampEditText = ""
                return .none
            case .confirmStampEditing:
                guard let target = state.stampEditingTarget else { return .none }
                let draft = state.stampEditText
                let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return .none }
                state.stampEditingTarget = nil
                state.stampEditText = ""
                state.stampRequestInFlight = true
                return .run { send in
                    do {
                        let response = try await service.updateStamp(id: target.stampId, content: content).value
                        guard response.success == 1 else {
                            logger.warning("server rejected stamp update. stamp=\(target.stampId)")
                            await send(.stampUpdateFailed(target: target, content: draft))
                            return
                        }
                        await send(.stampUpdated(target: target, content: content))
                    } catch {
                        logger.warning("failed to update stamp. stamp=\(target.stampId) \(error.localizedDescription)")
                        await send(.stampUpdateFailed(target: target, content: draft))
                    }
                }
                .cancellable(id: CancelId.stampMutation, cancelInFlight: true)
            case .confirmStampDeletion:
                guard let target = state.stampEditingTarget else { return .none }
                let content = state.stampEditText
                state.stampEditingTarget = nil
                state.stampEditText = ""
                state.stampRequestInFlight = true
                return .run { send in
                    do {
                        let response = try await service.deleteStamp(id: target.stampId).value
                        guard response.success == 1 else {
                            logger.warning("server rejected stamp deletion. stamp=\(target.stampId)")
                            await send(.stampDeleteFailed(target: target, content: content))
                            return
                        }
                        await send(.stampDeleted(target: target))
                    } catch {
                        logger.warning("failed to delete stamp. stamp=\(target.stampId) \(error.localizedDescription)")
                        await send(.stampDeleteFailed(target: target, content: content))
                    }
                }
                .cancellable(id: CancelId.stampMutation, cancelInFlight: true)
            case let .stampUpdated(target, content):
                state.stampRequestInFlight = false
                for pageId in state.pages.ids {
                    guard let page = state.pages[id: pageId],
                          page.sourceArchiveId == target.sourceArchiveId,
                          page.sourcePageNumber == target.sourcePageNumber,
                          let index = page.stamps.firstIndex(where: { $0.id == target.stampId }) else {
                        continue
                    }
                    let stamp = page.stamps[index]
                    state.pages[id: pageId]?.stamps[index] = ArchiveStamp(
                        id: stamp.id,
                        position: stamp.position,
                        content: content
                    )
                }
                return .none
            case let .stampUpdateFailed(target, content):
                state.stampRequestInFlight = false
                state.stampEditingTarget = target
                state.stampEditText = content
                state.errorMessage = String(localized: "archive.reader.stamp.update.failed")
                return .none
            case let .stampDeleted(target):
                state.stampRequestInFlight = false
                for pageId in state.pages.ids {
                    guard let page = state.pages[id: pageId],
                          page.sourceArchiveId == target.sourceArchiveId,
                          page.sourcePageNumber == target.sourcePageNumber else {
                        continue
                    }
                    state.pages[id: pageId]?.stamps.removeAll { $0.id == target.stampId }
                }
                return .none
            case let .stampDeleteFailed(target, content):
                state.stampRequestInFlight = false
                state.stampEditingTarget = target
                state.stampEditText = content
                state.errorMessage = String(localized: "archive.reader.stamp.delete.failed")
                return .none
            case let .visiblePageChanged(index):
                guard !state.pages.isEmpty else { return .none }
                let clampedIndex = ReaderPositioning.clampedPageIndex(index, pageCount: state.pages.count)
                guard clampedIndex != state.currentPageIndex else { return .none }
                self.preparePendingSplitMode(state: &state, pageIndex: clampedIndex)
                state.currentPageIndex = clampedIndex
                guard let currentArchive = state.allArchives[id: state.currentArchiveId],
                      let page = state.currentPage else { return .none }

                let pageNumber = page.pageNumber
                let isTank = state.currentArchiveId.isTankoubonArchiveId
                let shouldClearNewFlag = !isTank && pageNumber > 1 && currentArchive.wrappedValue.isNew
                currentArchive.withLock {
                    $0.progress = pageNumber
                    if shouldClearNewFlag {
                        $0.isNew = false
                    }
                }
                if state.cached {
                    return .run(priority: .background) { [id = state.currentArchiveId] _ in
                        _ = try database.updateCacheProgress(id, progress: pageNumber)
                    } catch: { [state] error, _ in
                        logger.error("failed to update cached archive progress. id=\(state.currentArchiveId) \(error)")
                    }
                    .cancellable(id: CancelId.updateProgress, cancelInFlight: true)
                }
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
            case let .chapterSelected(pageNumber):
                guard let pageIndex = state.pages.firstIndex(where: { $0.pageNumber == pageNumber }) else {
                    return .none
                }
                return .send(.requestJump(pageIndex, source: .chapter))
            case let .requestJump(index, source):
                guard !state.pages.isEmpty else { return .none }
                let clampedIndex = ReaderPositioning.clampedPageIndex(index, pageCount: state.pages.count)
                state.scrollRequest = ScrollRequest(
                    id: uuid(),
                    targetPageIndex: clampedIndex,
                    source: source,
                    animated: source.usesAnimatedScroll
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
                guard state.sliderThumbnailJobsById.isEmpty,
                      state.sliderReadyThumbnailPages.count < state.archivePageCount else {
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
                    await send(.sliderPreviewThumbnailsQueued(results))
                } catch: { [archiveId = state.currentArchiveId] error, _ in
                    logger.warning("failed to queue slider preview thumbnails. id=\(archiveId) \(error)")
                }
                .cancellable(id: CancelId.sliderPreviewThumbnailQueue, cancelInFlight: true)
            case let .sliderPreviewThumbnailsQueued(results):
                state.sliderThumbnailJobsById = [:]
                var effect: Effect<Action> = .none

                for result in results {
                    if let jobId = result.response.job {
                        state.sliderThumbnailJobsById[jobId] = result.archiveId
                        effect = .merge(
                            effect,
                            .send(.pollSliderPreviewThumbnailJob(jobId, archiveId: result.archiveId))
                        )
                    } else {
                        state.sliderReadyThumbnailPages.formUnion(
                            Self.readerPageNumbers(in: state.pages, sourceArchiveId: result.archiveId)
                        )
                    }
                }

                if let previewPageIndex = state.sliderPreviewPageIndex {
                    effect = .merge(effect, .send(.loadSliderPreview(previewPageIndex)))
                }
                return effect
            case let .pollSliderPreviewThumbnailJob(jobId, archiveId):
                return .run { send in
                    while true {
                        let status = try await service.checkBasicJobStatus(id: jobId).value
                        await send(.sliderPreviewThumbnailJobStatus(jobId, archiveId, status))
                        if status.state == "finished" || status.state == "failed" {
                            return
                        }
                        try await clock.sleep(for: .seconds(1))
                    }
                } catch: { error, send in
                    logger.warning("failed to poll slider preview thumbnail job. id=\(archiveId) \(error)")
                    await send(.sliderPreviewThumbnailPollingFailed(jobId, archiveId))
                }
                .cancellable(id: CancelId.sliderPreviewThumbnailPolling)
            case let .sliderPreviewThumbnailJobStatus(jobId, archiveId, status):
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
                if let previewPageIndex = state.sliderPreviewPageIndex {
                    return .send(.loadSliderPreview(previewPageIndex))
                }
                return .none
            case let .sliderPreviewThumbnailPollingFailed(jobId, _):
                state.sliderThumbnailJobsById[jobId] = nil
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
                    doublePageLayout: state.doublePageLayout,
                    spreadOffset: state.spreadPairingOffset
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
                let isTank = state.currentArchiveId.isTankoubonArchiveId
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
            case .page(.element(id: _, action: .stampsLoadFailed(endpointUnavailable: true))):
                return .send(.stampsSupportResolved(false))
            case let .page(.element(id: id, action: .storedImageResolved(shouldDisplayAsSplitPages))):
                self.handleSplitResolution(
                    id: id,
                    shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
                    state: &state
                )
                self.updateEstimatedPageAspectRatio(state: &state)
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
                    let archive = currentArchive.wrappedValue
                    var cache = ArchiveCache(
                        id: state.currentArchiveId,
                        title: archive.name,
                        tags: archive.tags,
                        thumbnail: Data(),
                        cached: false,
                        totalPages: requested.count,
                        toc: archive.toc,
                        lastUpdate: Date(),
                        progress: archive.progress
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
                    .cancel(id: CancelId.stampCreation),
                    .cancel(id: CancelId.stampMutation),
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
                    .cancel(id: CancelId.stampCreation),
                    .cancel(id: CancelId.stampMutation),
                    state.cached ? .send(.loadCached) : .send(.extractArchive)
                )
            }
        }
        .forEach(\.pages, action: \.page) {
            PageFeature()
        }
        .ifLet(\.$alert, action: \.alert)
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

    private static func tankoubonChapters(
        from archiveMetadata: ArchiveIndexResponse?,
        pageOffset: Int,
        extractedPageCount: Int
    ) -> [ArchiveChapter] {
        guard extractedPageCount > 0, let archiveMetadata else { return [] }
        var chapters: [ArchiveChapter] = (archiveMetadata.toc ?? []).compactMap { chapter in
            guard (1...extractedPageCount).contains(chapter.page) else { return nil }
            return ArchiveChapter(name: chapter.name, page: pageOffset + chapter.page)
        }
        let firstPage = pageOffset + 1
        if !archiveMetadata.title.isEmpty,
           !chapters.contains(where: { $0.page == firstPage }) {
            chapters.insert(
                ArchiveChapter(name: archiveMetadata.title, page: firstPage),
                at: 0
            )
        }
        return chapters
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

    private func updateEstimatedPageAspectRatio(state: inout State) {
        guard let median = ReaderPageLayout.medianAspectRatio(state.pages.compactMap(\.imageAspectRatio)) else {
            return
        }
        guard state.estimatedPageAspectRatio != median else { return }
        state.estimatedPageAspectRatio = median
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
        insertedPage.imageAspectRatio = current.imageAspectRatio
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
        state.sliderThumbnailJobsById = [:]
        state.sliderReadyThumbnailPages = []
    }

    private func hasPendingSliderPreviewThumbnailJobs(state: State) -> Bool {
        !state.sliderThumbnailJobsById.isEmpty
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
        state.spreadPairingOffset = 0
        state.fromStart = false
        state.scrollRequest = nil
        state.collectionScrolling = false
        state.pendingSplitResolutions = [:]
        state.inCache = false
        state.errorMessage = ""
        state.successMessage = ""
        state.currentTankoubonDetails = nil
        state.estimatedPageAspectRatio = ReaderPageLayout.defaultAspectRatio
        state.stampCreationTarget = nil
        state.stampComment = ""
        state.stampEditingTarget = nil
        state.stampEditText = ""
        state.stampRequestInFlight = false
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
        .alert(
            "archive.reader.stamp.add.title",
            isPresented: Binding(
                get: { store.stampCreationTarget != nil },
                set: { isPresented in
                    if !isPresented, store.stampCreationTarget != nil {
                        store.send(.cancelStampCreation)
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.stamp.text.placeholder",
                text: Binding(
                    get: { store.stampComment },
                    set: { store.send(.stampCommentChanged($0)) }
                )
            )
            Button("cancel", role: .cancel) {
                store.send(.cancelStampCreation)
            }
            Button("save") {
                store.send(.confirmStampCreation)
            }
            .disabled(store.stampComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "archive.reader.stamp.edit.title",
            isPresented: Binding(
                get: { store.stampEditingTarget != nil },
                set: { isPresented in
                    if !isPresented, store.stampEditingTarget != nil {
                        store.send(.cancelStampEditing)
                    }
                }
            )
        ) {
            TextField(
                "archive.reader.stamp.text.placeholder",
                text: Binding(
                    get: { store.stampEditText },
                    set: { store.send(.stampEditTextChanged($0)) }
                )
            )
            Button("delete", role: .destructive) {
                store.send(.confirmStampDeletion)
            }
            Button("cancel", role: .cancel) {
                store.send(.cancelStampEditing)
            }
            Button("save") {
                store.send(.confirmStampEditing)
            }
            .disabled(store.stampEditText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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
                        sliderContext: sliderContext,
                        bubbleLayout: bubbleLayout,
                        showsChapterMenu: !store.chapters.isEmpty
                    )
                }

                readerControlPanel(
                    store: store,
                    displayPageNumber: displayPageNumber,
                    sliderContext: sliderContext
                )
            }
            .frame(maxWidth: ReaderToolbarMetrics.maxPanelWidth)
            .padding(.horizontal, ReaderToolbarMetrics.outerHorizontalPadding)
            .padding(.bottom, ReaderToolbarMetrics.bottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func sliderPreviewRow(
        store: StoreOf<ArchiveReaderFeature>,
        displayIndex: Int,
        sliderContext: ReaderSliderContext,
        bubbleLayout: SliderPreviewBubbleLayout,
        showsChapterMenu: Bool
    ) -> some View {
        GeometryReader { geometry in
            let chapterMenuInset = showsChapterMenu ? ReaderToolbarMetrics.chapterMenuInset : 0
            let bubbleLeadingX = SliderPreviewPositioning.bubbleLeadingX(
                pageIndex: displayIndex,
                pageCount: store.pages.count,
                track: SliderPreviewTrackGeometry(
                    rowWidth: geometry.size.width,
                    sliderHorizontalPadding: sliderContext.horizontalPadding,
                    bubbleWidth: bubbleLayout.width,
                    leadingInset: sliderContext.isRightToLeft ? 0 : chapterMenuInset,
                    trailingInset: sliderContext.isRightToLeft ? chapterMenuInset : 0
                ),
                isRightToLeft: sliderContext.isRightToLeft
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
                systemImage: store.doublePageLayout
                    ? "rectangle.split.2x1.fill"
                    : "rectangle.portrait.fill",
                tint: Color(uiColor: .systemGreen),
                disabled: !store.canToggleDoublePageLayout,
                accessibilityLabel: store.doublePageLayout
                    ? "archive.reader.doublePage.disable"
                    : "archive.reader.doublePage.enable"
            ) {
                store.send(.toggleDoublePageLayout)
            }

            readerMoreMenu(store: store)
        }
    }

    private func readerMoreMenu(
        store: StoreOf<ArchiveReaderFeature>
    ) -> some View {
        let cacheActionRemoves = store.cached || store.inCache

        return Menu {
            if store.canUseStamps {
                Button {
                    store.send(.toggleStampsVisibility)
                } label: {
                    if store.showStamps {
                        Label("archive.reader.stamps.hide", systemImage: "mappin.slash")
                    } else {
                        Label("archive.reader.stamps.show", systemImage: "mappin")
                    }
                }
            }

            Button {
                store.send(.setThumbnail)
            } label: {
                Label("archive.thumbnail.current", systemImage: "photo.artframe")
            }
            .disabled(store.settingThumbnail || store.cached)

            if cacheActionRemoves {
                Button(role: .destructive) {
                    store.send(.removeCache)
                } label: {
                    Label("archive.cache.remove", systemImage: "trash")
                }
            } else {
                Button {
                    store.send(.downloadPages)
                } label: {
                    Label("archive.cache.add", systemImage: "tray.and.arrow.down")
                }
            }
        } label: {
            readerToolbarGlyph(systemImage: "ellipsis", tint: Color.primary)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .clipShape(Circle())
        .accessibilityLabel(Text("archive.reader.more"))
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
            readerToolbarGlyph(systemImage: systemImage, tint: tint, disabled: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func readerToolbarGlyph(
        systemImage: String,
        tint: Color,
        disabled: Bool = false
    ) -> some View {
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

    private func readerPageSlider(
        store: StoreOf<ArchiveReaderFeature>,
        context: ReaderSliderContext
    ) -> some View {
        HStack(spacing: ReaderToolbarMetrics.chapterMenuSpacing) {
            if !store.chapters.isEmpty {
                readerChapterMenu(store: store)
            }

            readerSliderTrack(store: store, context: context)
        }
        .frame(height: store.chapters.isEmpty ? 34 : ReaderToolbarMetrics.buttonSize)
    }

    private func readerSliderTrack(
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

    private func readerChapterMenu(
        store: StoreOf<ArchiveReaderFeature>
    ) -> some View {
        Menu {
            ForEach(store.chapters) { chapter in
                Button(chapter.name) {
                    store.send(.chapterSelected(chapter.page))
                }
            }
        } label: {
            readerToolbarGlyph(systemImage: "list.bullet.rectangle", tint: Color.indigo)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .clipShape(Circle())
        .accessibilityLabel(Text("archive.reader.chapters"))
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
    static let maxPanelWidth: CGFloat = 700
    static let panelCornerRadius: CGFloat = 26
    static let previewBottomSpacing: CGFloat = 12
    static let sliderHorizontalPadding: CGFloat = 16
    static let buttonSize: CGFloat = 44
    static let chapterMenuSpacing: CGFloat = 10
    static let chapterMenuInset = buttonSize + chapterMenuSpacing
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
        let sliderWidth = max(
            track.rowWidth
                - track.leadingInset
                - track.trailingInset
                - track.sliderHorizontalPadding * 2,
            1
        )
        let thumbCenterX = track.leadingInset + track.sliderHorizontalPadding + (
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
    let leadingInset: CGFloat
    let trailingInset: CGFloat

    init(
        rowWidth: CGFloat,
        sliderHorizontalPadding: CGFloat,
        bubbleWidth: CGFloat,
        leadingInset: CGFloat = 0,
        trailingInset: CGFloat = 0
    ) {
        self.rowWidth = rowWidth
        self.sliderHorizontalPadding = sliderHorizontalPadding
        self.bubbleWidth = bubbleWidth
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }
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
