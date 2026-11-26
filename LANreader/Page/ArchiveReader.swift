import ComposableArchitecture
import CoreGraphics
import Foundation
import Logging
import OrderedCollections

// swiftlint:disable type_body_length file_length

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

public struct ChapterMutationTarget: Equatable, Sendable {
    let readerArchiveId: String
    let readerPageNumber: Int
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
        @SharedReader(.appStorage(SettingsKey.disablePageFlipAnimation)) var disablePageFlipAnimation = false
        @SharedReader(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.splitPiorityLeft)) var piorityLeft = false
        @SharedReader(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0
        @Shared(.appStorage(SettingsKey.doublePageLayout)) var manualDoublePageLayout = false
        @Shared(.appStorage(SettingsKey.automaticPageLayout)) var automaticPageLayout = false
        @SharedReader(.appStorage(SettingsKey.fitPageWidth)) var fitPageWidth = false
        @Shared(.appStorage(SettingsKey.showStamps)) var showStamps = false
        @SharedReader(.appStorage(SettingsKey.restartFinished)) var restartFinished = false
        @SharedReader(.cachedArchiveIds) var cachedArchiveIds: Set<String> = []

        var currentArchiveId = ""
        var currentPageIndex = 0
        var spreadPairingOffset = 0
        var spreadAnchorPageIndex: Int?
        var doublePageLayout = false
        var readerSize: CGSize = .zero
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
        var inCache: Bool {
            cachedArchiveIds.contains(currentArchiveId)
        }
        var currentTankoubonDetails: TankoubonDetailsMetadata?
        var sliderDraftIndex: Int?
        var sliderDragging = false
        var sliderPreviewVisible = false
        var sliderPreviewPageIndex: Int?
        var sliderPreviewImageURL: URL?
        var sliderPreviewLoading = false
        var sliderThumbnailJobsById: [Int: String] = [:]
        var sliderReadyThumbnailPages: Set<Int> = []
        /// Keyed by reader page number. A page with no entry has not been tried yet.
        var sliderPreviewStatus: [Int: SliderPreviewStatus] = [:]
        /// Set once Low Data Mode blocks a background preview download. After that, only the page
        /// under the slider is fetched.
        var sliderPreviewPrefetchStopped = false
        var sliderPreviewPrefetchInFlight = false
        /// Median aspect ratio of the pages measured so far, used to size pages that have not been
        /// measured yet. Pages within an archive are near-uniform, so this converges almost immediately.
        var estimatedPageAspectRatio: Double = ReaderPageLayout.defaultAspectRatio
        var stampCreationTarget: StampCreationTarget?
        var stampComment = ""
        var stampEditingTarget: StampEditingTarget?
        var stampEditText = ""
        var stampRequestInFlight = false
        var stampsSupported: Bool?
        var chapterCreationTarget: ChapterMutationTarget?
        var chapterEditingTarget: ChapterMutationTarget?
        var chapterTitle = ""
        var chapterRequestInFlight = false
        var chapterMutationsSupported: Bool?

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
            self.doublePageLayout = !automaticPageLayout && manualDoublePageLayout
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

        var canAddChapter: Bool {
            !cached && chapterMutationsSupported != false && currentPage != nil
        }

        var editableChapterPages: Set<Int> {
            guard !cached, chapterMutationsSupported != false else { return [] }
            let chapterPages = Set(chapters.map(\.page))
            guard currentArchiveId.isTankoubonArchiveId else { return chapterPages }
            guard let currentTankoubonDetails else { return [] }
            return chapterPages.subtracting(currentTankoubonDetails.automaticChapterPages)
        }

        var shouldShowChapterMenu: Bool {
            !chapters.isEmpty || canAddChapter
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

        var pageLayoutMode: ReaderPageLayoutMode {
            ReaderPageLayoutMode(automatic: automaticPageLayout, double: manualDoublePageLayout)
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
        case chapterMutationSupportResolved(Bool?)
        case finishExtracting([ReaderExtractedPage], TankoubonDetailsMetadata?)
        case primePageAspectRatios
        case pageAspectRatiosPrimed([Int: Double])
        case toggleControlUi(Bool?)
        case pageLayoutModeChanged(ReaderPageLayoutMode)
        case readerSizeChanged(CGSize)
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
        case chapterCreationRequested
        case chapterEditingRequested(Int)
        case cancelChapterMutation
        case confirmChapterMutation
        case confirmChapterDeletion
        case chapterSaved(target: ChapterMutationTarget, title: String)
        case chapterSaveFailed(target: ChapterMutationTarget, title: String, isEditing: Bool)
        case chapterDeleted(target: ChapterMutationTarget)
        case chapterDeleteFailed(target: ChapterMutationTarget, title: String)
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
        case sliderPreviewFetched(pageNumber: Int, SliderPreviewFetchResult)
        case sliderPreviewPrefetchFinished
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
        case openDetailsTapped

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
        case sliderPreviewFetch
        case sliderPreviewPrefetch
        case primePageAspectRatios
        case stampCreation
        case stampMutation
        case chapterCreation
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
                   self.restoreInitialPage(
                       progress: cachedProgress, restartFinishedArchive: restartFinishedArchive, state: &state
                   )
                   state.controlUiHidden = true
                   state.extracting = false
                   return .merge(
                       .send(.requestJump(state.currentPageIndex, source: .initialRestore)),
                       .send(.primePageAspectRatios),
                       self.startSliderPreviewPrefetchIfNeeded(state: &state)
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
                return .run { send in
                    await send(.stampsSupportResolved(await service.supportsStamps))
                    await send(.chapterMutationSupportResolved(await service.supportsChapterMutations))
                    let extraction = try await service.extractArchiveForReading(id: id)

                    if extraction.pages.isEmpty {
                        logger.error("server returned empty pages. id=\(id)")
                        let errorMessage = String(localized: "error.page.empty")
                        await send(.setError(errorMessage))
                    }
                    await send(.finishExtracting(extraction.pages, extraction.tankoubonDetails))
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
            case let .chapterMutationSupportResolved(isSupported):
                state.chapterMutationsSupported = isSupported
                guard isSupported == false else { return .none }
                state.chapterCreationTarget = nil
                state.chapterEditingTarget = nil
                state.chapterTitle = ""
                state.chapterRequestInFlight = false
                return .cancel(id: CancelId.chapterCreation)
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
                    self.restoreInitialPage(
                        progress: archive.progress, restartFinishedArchive: restartFinishedArchive, state: &state
                    )
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
                return .cancel(id: CancelId.autoPage)
            case let .pageLayoutModeChanged(mode):
                guard state.canToggleDoublePageLayout else { return .none }
                mode.save(automatic: state.$automaticPageLayout, double: state.$manualDoublePageLayout)
                return updatePageLayout(state: &state)
            case let .readerSizeChanged(size):
                guard size.width > 0, size.height > 0 else { return .none }
                state.readerSize = size
                return updatePageLayout(state: &state)
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
            case .chapterCreationRequested:
                guard state.canAddChapter,
                      !state.chapterRequestInFlight,
                      state.chapterEditingTarget == nil,
                      let page = state.currentPage else {
                    return .none
                }
                state.chapterCreationTarget = ChapterMutationTarget(
                    readerArchiveId: state.currentArchiveId,
                    readerPageNumber: page.pageNumber,
                    sourceArchiveId: page.sourceArchiveId,
                    sourcePageNumber: page.sourcePageNumber
                )
                state.chapterTitle = ""
                return .none
            case let .chapterEditingRequested(pageNumber):
                guard state.editableChapterPages.contains(pageNumber),
                      !state.chapterRequestInFlight,
                      state.chapterCreationTarget == nil,
                      let chapter = state.chapters.first(where: { $0.page == pageNumber }),
                      let page = state.pages.first(where: { $0.pageNumber == pageNumber }) else {
                    return .none
                }
                state.chapterEditingTarget = ChapterMutationTarget(
                    readerArchiveId: state.currentArchiveId,
                    readerPageNumber: pageNumber,
                    sourceArchiveId: page.sourceArchiveId,
                    sourcePageNumber: page.sourcePageNumber
                )
                state.chapterTitle = chapter.name
                return .none
            case .cancelChapterMutation:
                state.chapterCreationTarget = nil
                state.chapterEditingTarget = nil
                state.chapterTitle = ""
                return .none
            case .confirmChapterMutation:
                let isEditing = state.chapterEditingTarget != nil
                guard let target = state.chapterEditingTarget ?? state.chapterCreationTarget else { return .none }
                let draft = state.chapterTitle
                let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return .none }
                state.chapterCreationTarget = nil
                state.chapterEditingTarget = nil
                state.chapterTitle = ""
                state.chapterRequestInFlight = true
                return .run { send in
                    do {
                        let response = try await service.addArchiveChapter(
                            id: target.sourceArchiveId,
                            page: target.sourcePageNumber,
                            title: title
                        ).value
                        guard response.success == 1 else {
                            await send(.chapterSaveFailed(target: target, title: draft, isEditing: isEditing))
                            return
                        }
                        await send(.chapterSaved(target: target, title: title))
                    } catch {
                        let source = "\(target.sourceArchiveId):\(target.sourcePageNumber)"
                        logger.warning("failed to save chapter. source=\(source) \(error.localizedDescription)")
                        await send(.chapterSaveFailed(target: target, title: draft, isEditing: isEditing))
                    }
                }
                .cancellable(id: CancelId.chapterCreation, cancelInFlight: true)
            case .confirmChapterDeletion:
                guard let target = state.chapterEditingTarget else { return .none }
                let title = state.chapterTitle
                state.chapterEditingTarget = nil
                state.chapterTitle = ""
                state.chapterRequestInFlight = true
                return .run { send in
                    do {
                        let response = try await service.deleteArchiveChapter(
                            id: target.sourceArchiveId,
                            page: target.sourcePageNumber
                        ).value
                        guard response.success == 1 else {
                            await send(.chapterDeleteFailed(target: target, title: title))
                            return
                        }
                        await send(.chapterDeleted(target: target))
                    } catch {
                        let source = "\(target.sourceArchiveId):\(target.sourcePageNumber)"
                        logger.warning("failed to delete chapter. source=\(source) \(error.localizedDescription)")
                        await send(.chapterDeleteFailed(target: target, title: title))
                    }
                }
                .cancellable(id: CancelId.chapterCreation, cancelInFlight: true)
            case let .chapterSaved(target, title):
                state.chapterRequestInFlight = false
                guard let archive = state.allArchives[id: target.readerArchiveId] else { return .none }
                var chapters = archive.wrappedValue.toc ?? []
                chapters.removeAll { $0.page == target.readerPageNumber }
                chapters.append(ArchiveChapter(name: title, page: target.readerPageNumber))
                chapters.sort { $0.page < $1.page }
                archive.withLock { $0.toc = chapters }
                if state.currentTankoubonDetails?.id == target.readerArchiveId {
                    state.currentTankoubonDetails?.toc = chapters
                    state.currentTankoubonDetails?.automaticChapterPages.remove(target.readerPageNumber)
                }
                return .none
            case let .chapterSaveFailed(target, title, isEditing):
                state.chapterRequestInFlight = false
                if isEditing {
                    state.chapterEditingTarget = target
                } else {
                    state.chapterCreationTarget = target
                }
                state.chapterTitle = title
                state.errorMessage = String(localized: isEditing
                    ? "archive.reader.chapter.edit.failed"
                    : "archive.reader.chapter.add.failed")
                return .none
            case let .chapterDeleted(target):
                state.chapterRequestInFlight = false
                guard let archive = state.allArchives[id: target.readerArchiveId] else { return .none }
                var chapters = archive.wrappedValue.toc ?? []
                chapters.removeAll { $0.page == target.readerPageNumber }
                if state.currentTankoubonDetails?.id == target.readerArchiveId {
                    if let defaultChapter = state.currentTankoubonDetails?.defaultChapters.first(
                        where: { $0.page == target.readerPageNumber }
                    ) {
                        chapters.append(defaultChapter)
                        chapters.sort { $0.page < $1.page }
                        state.currentTankoubonDetails?.automaticChapterPages.insert(defaultChapter.page)
                    }
                    state.currentTankoubonDetails?.toc = chapters.isEmpty ? nil : chapters
                }
                archive.withLock { $0.toc = chapters.isEmpty ? nil : chapters }
                return .none
            case let .chapterDeleteFailed(target, title):
                state.chapterRequestInFlight = false
                state.chapterEditingTarget = target
                state.chapterTitle = title
                state.errorMessage = String(localized: "archive.reader.chapter.delete.failed")
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
                let progressEffect: Effect<Action> = .run(priority: .background) { [state] _ in
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
                } catch: { [state] error, _ in
                    logger.error("failed to update archive progress. id=\(state.currentArchiveId) \(error)")
                }
                .cancellable(id: CancelId.updateProgress, cancelInFlight: true)
                guard shouldClearNewFlag else { return progressEffect }
                return .merge(
                    progressEffect,
                    .run(priority: .background) { [id = state.currentArchiveId] _ in
                        _ = await service.clearNewFlag(id: id)
                    }
                )
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
                    animated: source.usesAnimatedScroll && !state.disablePageFlipAnimation
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
                return .merge(effect, self.advanceSliderPreviews(state: &state))
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
                return self.advanceSliderPreviews(state: &state)
            case let .sliderPreviewThumbnailPollingFailed(jobId, _):
                state.sliderThumbnailJobsById[jobId] = nil
                return self.advanceSliderPreviews(state: &state)
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
                    return .none
                }
                let targetIndex = ReaderPositioning.clampedPageIndex(
                    state.sliderDraftIndex ?? state.currentPageIndex,
                    pageCount: state.pages.count
                )
                self.resetSliderPreviewDisplayState(state: &state)
                return .send(.requestJump(targetIndex, source: .slider))
            case let .sliderPreviewFetched(pageNumber, result):
                guard state.pages.contains(where: { $0.pageNumber == pageNumber }) else {
                    return .none
                }
                switch result {
                case .stored:
                    state.sliderPreviewStatus[pageNumber] = .stored
                case .failed:
                    if state.sliderPreviewStatus[pageNumber] != .stored {
                        state.sliderPreviewStatus[pageNumber] = .failed
                    }
                case .networkConstrained:
                    if state.sliderPreviewStatus[pageNumber] == .fetching {
                        state.sliderPreviewStatus[pageNumber] = nil
                    }
                    state.sliderPreviewPrefetchStopped = true
                }
                if result != .networkConstrained,
                   state.sliderPreviewVisible,
                   let previewIndex = state.sliderPreviewPageIndex,
                   state.pages.indices.contains(previewIndex),
                   state.pages[previewIndex].pageNumber == pageNumber {
                    let stored = state.sliderPreviewStatus[pageNumber] == .stored
                    state.sliderPreviewImageURL = stored
                        ? Self.sliderPreviewFileURL(archiveId: state.currentArchiveId, pageNumber: pageNumber)
                        : nil
                    state.sliderPreviewLoading = false
                }
                return .none
            case .sliderPreviewPrefetchFinished:
                state.sliderPreviewPrefetchInFlight = false
                return self.startSliderPreviewPrefetchIfNeeded(state: &state)
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
                    animated: source.usesAnimatedScroll && !state.disablePageFlipAnimation
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
            case let .page(.element(id: id, action: .load(true))):
                self.setSplitSiblingsLoaded(false, id: id, state: &state)
                return .none
            case let .page(.element(id: id, action: .setError)):
                self.setSplitSiblingsLoaded(true, id: id, state: &state)
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
                    var pageNumbers = Set<Int>()
                    let pages = state.pages.filter { pageNumbers.insert($0.pageNumber).inserted }
                        .sorted { $0.pageNumber < $1.pageNumber }
                        .map {
                            ReaderExtractedPage(
                                archiveId: $0.sourceArchiveId, path: $0.pageId,
                                archivePageNumber: $0.sourcePageNumber
                            )
                        }
                    guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return }
                    let archive = currentArchive.wrappedValue
                    try await service.saveAndCacheArchive(archive, pages: pages, database: database)
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
                return .run { [id = state.currentArchiveId] send in
                    let deleted = try database.deleteCache(id)
                    if deleted != true {
                        let errorMessage = String(localized: "archive.cache.remove.failed")
                        await send(.setError(errorMessage))
                    } else {
                        await service.removeCachedPages(archiveId: id)
                        await send(.removeCacheSuccess)
                    }
                } catch: { [id = state.currentArchiveId] error, send in
                    logger.error("failed to remove archive cache, id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                }
            case .removeCacheSuccess:
                return .none
            case .alert:
                return .none
            case .loadPreviousArchive:
                return switchArchive(offset: -1, state: &state)
            case .loadNextArchive:
                return switchArchive(offset: 1, state: &state)
            case .openDetailsTapped:
                return .none
            }
        }
        .forEach(\.pages, action: \.page) {
            PageFeature()
        }
        .ifLet(\.$alert, action: \.alert)
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
        insertedPage.storedImageURL = current.storedImageURL
        // Match by half, not id: the original item keeps its normal id while showing a split half.
        if let existingSiblingId = state.pages.first(where: {
            $0.pageId == current.pageId && $0.id != id && $0.pageMode == siblingMode
        })?.id {
            state.pages[id: existingSiblingId]?.storedImageURL = current.storedImageURL
            state.pages[id: existingSiblingId]?.imageLoaded = true
            return
        }
        guard state.pages[id: insertedPage.id] == nil else { return }

        let leadingSplitMode = PageMode.preferredSplitMode(priorityLeft: state.piorityLeft)
        let insertAfterCurrent = splitMode == leadingSplitMode
        let insertedIndex = insertAfterCurrent ? sourcePageIndex + 1 : sourcePageIndex
        state.pages.insert(insertedPage, at: insertedIndex)
    }

    private func setSplitSiblingsLoaded(
        _ loaded: Bool,
        id: PageFeature.State.ID,
        state: inout State
    ) {
        guard let page = state.pages[id: id] else { return }
        let siblingIds = state.pages
            .filter { $0.pageId == page.pageId && $0.id != id && $0.pageMode.isSplitMode }
            .map(\.id)
        for siblingId in siblingIds {
            state.pages[id: siblingId]?.imageLoaded = loaded
        }
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
        if let imageAspectRatio = current.imageAspectRatio {
            state.pages[id: keepId]?.imageAspectRatio = imageAspectRatio
        }
        if let storedImageURL = current.storedImageURL {
            state.pages[id: keepId]?.storedImageURL = storedImageURL
        }

        state.pages.removeAll {
            $0.pageId == current.pageId && $0.id != keepId
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

        // The drag gesture reports every finger movement, so most calls land on the page already shown.
        let pageChanged = state.sliderPreviewPageIndex != clampedIndex
        state.sliderDraftIndex = clampedIndex
        state.sliderPreviewVisible = true
        state.sliderPreviewPageIndex = clampedIndex
        guard pageChanged else { return .none }
        return self.showSliderPreview(pageIndex: clampedIndex, state: &state)
    }

    /// Shows the page's preview if it is on disk. Otherwise the bubble shows a spinner and the page is
    /// fetched ahead of the background queue.
    private func showSliderPreview(pageIndex: Int, state: inout State) -> Effect<Action> {
        let page = state.pages[pageIndex]
        let fileURL = Self.sliderPreviewFileURL(archiveId: state.currentArchiveId, pageNumber: page.pageNumber)
        if state.sliderPreviewStatus[page.pageNumber] == nil, Self.fileExists(fileURL) {
            state.sliderPreviewStatus[page.pageNumber] = .stored
        }

        let status = state.sliderPreviewStatus[page.pageNumber]
        state.sliderPreviewImageURL = status == .stored ? fileURL : nil
        switch status {
        case .stored:
            state.sliderPreviewLoading = false
            return .none
        case .fetching:
            state.sliderPreviewLoading = true
            return .none
        case .failed, nil:
            guard state.cached || state.sliderReadyThumbnailPages.contains(page.pageNumber) else {
                // The server has not generated this page's thumbnail yet.
                state.sliderPreviewLoading = !state.sliderThumbnailJobsById.isEmpty
                return .none
            }
            state.sliderPreviewLoading = true
            return self.fetchForegroundSliderPreview(page, state: &state)
        }
    }

    /// Runs after more thumbnails become available: fetches the page under the slider if it was waiting,
    /// and starts the background prefetch wave if none is active.
    private func advanceSliderPreviews(state: inout State) -> Effect<Action> {
        var waitingPreview: Effect<Action> = .none
        if state.sliderPreviewVisible,
           let previewIndex = state.sliderPreviewPageIndex,
           state.pages.indices.contains(previewIndex),
           state.sliderPreviewStatus[state.pages[previewIndex].pageNumber] == nil {
            waitingPreview = self.showSliderPreview(pageIndex: previewIndex, state: &state)
        }
        return .merge(waitingPreview, self.startSliderPreviewPrefetchIfNeeded(state: &state))
    }

    /// Starts one background prefetch wave for all ready, untried preview pages, nearest first.
    private func startSliderPreviewPrefetchIfNeeded(state: inout State) -> Effect<Action> {
        guard !state.sliderPreviewPrefetchStopped,
              !state.sliderPreviewPrefetchInFlight,
              !state.pages.isEmpty else {
            return .none
        }

        let anchor = ReaderPositioning.clampedPageIndex(
            (state.sliderPreviewVisible ? state.sliderPreviewPageIndex : nil) ?? state.currentPageIndex,
            pageCount: state.pages.count
        )
        var seenPages: Set<Int> = []
        var targets: [SliderPreviewTarget] = []
        for index in Self.pageIndicesNearestFirst(from: anchor, count: state.pages.count) {
            let page = state.pages[index]
            guard seenPages.insert(page.pageNumber).inserted else { continue }
            guard state.sliderPreviewStatus[page.pageNumber] == nil,
                  state.cached || state.sliderReadyThumbnailPages.contains(page.pageNumber) else {
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
        guard !targets.isEmpty else { return .none }

        state.sliderPreviewPrefetchInFlight = true
        let archiveId = state.currentArchiveId
        let cached = state.cached
        let limit = cached ? Self.previewGenerationLimit : Self.previewDownloadLimit
        return .run(priority: .utility) { [targets] send in
            await self.runSliderPreviewPrefetch(
                targets: targets,
                archiveId: archiveId,
                cached: cached,
                limit: limit,
                send: send
            )
        }
        .cancellable(id: CancelId.sliderPreviewPrefetch, cancelInFlight: true)
    }

    private func runSliderPreviewPrefetch(
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
                group.addTask {
                    let result = await self.fetchSliderPreviewResult(
                        target: target,
                        archiveId: archiveId,
                        cached: cached,
                        background: true
                    )
                    return (target.pageNumber, result)
                }
            }

            var constrained = false
            while let (pageNumber, result) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let result {
                    await send(.sliderPreviewFetched(pageNumber: pageNumber, result))
                    if result == .networkConstrained {
                        constrained = true
                    }
                }
                if !constrained, nextIndex < targets.count, !Task.isCancelled {
                    let target = targets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let result = await self.fetchSliderPreviewResult(
                            target: target,
                            archiveId: archiveId,
                            cached: cached,
                            background: true
                        )
                        return (target.pageNumber, result)
                    }
                }
            }
        }
        guard !Task.isCancelled else { return }
        await send(.sliderPreviewPrefetchFinished)
    }

    /// Page indices ordered by distance from `anchor`, with the later page first on a tie.
    static func pageIndicesNearestFirst(from anchor: Int, count: Int) -> [Int] {
        (0..<count).sorted { lhs, rhs in
            let lhsDistance = abs(lhs - anchor)
            let rhsDistance = abs(rhs - anchor)
            return lhsDistance == rhsDistance ? lhs > rhs : lhsDistance < rhsDistance
        }
    }

    private func fetchForegroundSliderPreview(
        _ page: PageFeature.State,
        state: inout State
    ) -> Effect<Action> {
        state.sliderPreviewStatus[page.pageNumber] = .fetching
        let archiveId = state.currentArchiveId
        let cached = state.cached
        let target = SliderPreviewTarget(
            pageNumber: page.pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        return .run(priority: .userInitiated) { send in
            guard let result = await self.fetchSliderPreviewResult(
                target: target,
                archiveId: archiveId,
                cached: cached,
                background: false
            ), !Task.isCancelled else {
                return
            }
            await send(.sliderPreviewFetched(pageNumber: target.pageNumber, result))
        }
        .cancellable(id: CancelId.sliderPreviewFetch)
    }

    private func fetchSliderPreviewResult(
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
            ? self.generateCachedSliderPreview(archiveId: archiveId, pageNumber: target.pageNumber, fileURL: fileURL)
            : await self.downloadSliderPreview(target: target, fileURL: fileURL, background: background)
    }

    private func generateCachedSliderPreview(
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

    private func downloadSliderPreview(
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

    private func resetSliderPreviewDisplayState(state: inout State) {
        state.sliderDraftIndex = nil
        state.sliderDragging = false
        state.sliderPreviewVisible = false
        state.sliderPreviewPageIndex = nil
        state.sliderPreviewImageURL = nil
        state.sliderPreviewLoading = false
    }

    private func switchArchive(offset: Int, state: inout State) -> Effect<Action> {
        guard let currentIndex = state.allArchives.firstIndex(where: { $0.id == state.currentArchiveId }),
              state.allArchives.indices.contains(currentIndex + offset) else {
            return .none
        }
        state.currentArchiveId = state.allArchives[currentIndex + offset].wrappedValue.id
        self.resetState(state: &state)
        return .merge(
            .cancel(id: CancelId.sliderPreviewThumbnailQueue),
            .cancel(id: CancelId.sliderPreviewThumbnailPolling),
            .cancel(id: CancelId.sliderPreviewPrefetch),
            .cancel(id: CancelId.sliderPreviewFetch),
            .cancel(id: CancelId.stampCreation),
            .cancel(id: CancelId.stampMutation),
            .cancel(id: CancelId.chapterCreation),
            state.cached ? .send(.loadCached) : .send(.extractArchive)
        )
    }

    private func resetSliderPreviewArchiveState(state: inout State) {
        resetSliderPreviewDisplayState(state: &state)
        state.sliderThumbnailJobsById = [:]
        state.sliderReadyThumbnailPages = []
        state.sliderPreviewStatus = [:]
        state.sliderPreviewPrefetchStopped = false
        state.sliderPreviewPrefetchInFlight = false
    }

    /// Server thumbnails are at most 500 pixels wide; cached pages get previews of about the same size.
    private static let cachedPreviewMaxPixelSize: CGFloat = 720
    /// Leaves the rest of the server's connections to the page images being read.
    private static let previewDownloadLimit = 3
    private static let previewGenerationLimit = 2

    private static func fileExists(_ url: URL) -> Bool {
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

    private static func sliderPreviewFileURL(archiveId: String, pageNumber: Int) -> URL {
        sliderPreviewDirectory(archiveId: archiveId)
            .appendingPathComponent("\(pageNumber).jpg", isDirectory: false)
    }

    private static func sliderPreviewCacheBust(pageNumber: Int) -> Int {
        Int(Date().timeIntervalSince1970 * 1000) + pageNumber
    }

    private func resolvedDoublePageLayout(state: State) -> Bool {
        guard state.resolvedReadDirection != .upDown, !state.splitImage else { return false }
        guard state.automaticPageLayout else { return state.manualDoublePageLayout }
        return state.pages.count > 1 && ReaderPageLayout.automaticDoublePageLayout(
            readerSize: state.readerSize, currentlyEnabled: state.doublePageLayout
        )
    }

    private func restoreInitialPage(progress: Int, restartFinishedArchive: Bool, state: inout State) {
        let storedIndex = ReaderPositioning.initialPageIndex(
            progress: progress,
            pageCount: state.pages.count,
            fromStart: state.fromStart,
            restartFinishedArchive: restartFinishedArchive
        )
        let enabled = resolvedDoublePageLayout(state: state)
        state.doublePageLayout = false
        state.spreadPairingOffset = 0
        state.spreadAnchorPageIndex = nil
        state.currentPageIndex = enabled
            ? applyPageLayout(true, pageIndex: storedIndex, restoring: true, state: &state)
            : storedIndex
    }

    private func updatePageLayout(state: inout State) -> Effect<Action> {
        guard !state.pages.isEmpty else { return .none }
        let enabled = resolvedDoublePageLayout(state: state)
        guard enabled != state.doublePageLayout else { return .none }
        let restoring = state.scrollRequest?.source == .initialRestore
        // A pending initial restore or slider jump has priority over the last reported visible page.
        let pageIndex = state.scrollRequest?.targetPageIndex ?? state.currentPageIndex
        let targetIndex = applyPageLayout(enabled, pageIndex: pageIndex, restoring: restoring, state: &state)
        return .send(.requestJump(targetIndex, source: restoring ? .initialRestore : .layoutChange))
    }

    /// Saved progress is the trailing page of a spread, so a restored page is paired with the page
    /// before it, while any other page starts its spread. Turning spreads off returns to the page the
    /// spread was built around while it is still on screen, or else to the spread's first page.
    private func applyPageLayout(_ enabled: Bool, pageIndex: Int, restoring: Bool, state: inout State) -> Int {
        let pageCount = state.pages.count
        let readDirection = state.resolvedReadDirection
        let previousOffset = state.spreadPairingOffset
        let anchorIndex = state.spreadAnchorPageIndex
        state.doublePageLayout = enabled
        guard enabled else {
            state.spreadPairingOffset = 0
            state.spreadAnchorPageIndex = nil
            let spreadStart = ReaderPositioning.scrollAnchorIndex(
                forPageIndex: pageIndex, pageCount: pageCount, readDirection: readDirection,
                doublePageLayout: true, spreadOffset: previousOffset
            )
            let spreadEnd = ReaderPositioning.canonicalPageIndex(
                forVisibleIndex: pageIndex, pageCount: pageCount, readDirection: readDirection,
                doublePageLayout: true, spreadOffset: previousOffset
            )
            if let anchorIndex, (spreadStart...max(spreadStart, spreadEnd)).contains(anchorIndex) {
                return anchorIndex
            }
            return spreadStart
        }
        let clampedIndex = ReaderPositioning.clampedPageIndex(pageIndex, pageCount: pageCount)
        state.spreadPairingOffset = restoring && clampedIndex > 0 ? (clampedIndex + 1) % 2 : clampedIndex % 2
        state.spreadAnchorPageIndex = clampedIndex
        return ReaderPositioning.canonicalPageIndex(
            forVisibleIndex: clampedIndex, pageCount: pageCount, readDirection: readDirection,
            doublePageLayout: true, spreadOffset: state.spreadPairingOffset
        )
    }

    func resetState(state: inout State) {
        state.pages = []
        state.currentPageIndex = 0
        state.spreadPairingOffset = 0
        state.spreadAnchorPageIndex = nil
        state.fromStart = false
        state.scrollRequest = nil
        state.collectionScrolling = false
        state.pendingSplitResolutions = [:]
        state.errorMessage = ""
        state.successMessage = ""
        state.currentTankoubonDetails = nil
        state.estimatedPageAspectRatio = ReaderPageLayout.defaultAspectRatio
        state.stampCreationTarget = nil
        state.stampComment = ""
        state.stampEditingTarget = nil
        state.stampEditText = ""
        state.stampRequestInFlight = false
        state.chapterCreationTarget = nil
        state.chapterEditingTarget = nil
        state.chapterTitle = ""
        state.chapterRequestInFlight = false
        resetSliderPreviewArchiveState(state: &state)
    }
}

private enum ArchiveReaderError: LocalizedError {
    case thumbnailUnavailableAfterUpdate

    var errorDescription: String? {
        switch self {
        case .thumbnailUnavailableAfterUpdate:
            return "Thumbnail is not ready yet. Please try again in a moment."
        }
    }
}

// swiftlint:enable type_body_length file_length
