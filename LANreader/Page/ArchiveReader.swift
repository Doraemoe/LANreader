import ComposableArchitecture
import CoreGraphics
import Foundation
import Logging

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
        var currentTankoubonDetails: TankoubonDetailsMetadata?
        var sliderPreview = ReaderSliderPreviewFeature.State()
        /// Median aspect ratio of the pages measured so far, used to size pages that have not been
        /// measured yet. Pages within an archive are near-uniform, so this converges almost immediately.
        var estimatedPageAspectRatio: Double = ReaderPageLayout.defaultAspectRatio
        var stamp = ReaderStampFeature.State()
        var chapter = ReaderChapterFeature.State()

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
    }

    public enum Action: Equatable {
        case alert(PresentationAction<Alert>)

        case autoPage(AutomaticPageFeature.Action)
        case showAutoPageConfig
        case autoPageTick
        case setLastAutoPageIndex(Int?)
        case page(IdentifiedActionOf<PageFeature>)
        case extractArchive
        case finishExtracting([ReaderExtractedPage], TankoubonDetailsMetadata?)
        case primePageAspectRatios
        case pageAspectRatiosPrimed([Int: Double])
        case toggleControlUi(Bool?)
        case pageLayoutModeChanged(ReaderPageLayoutMode)
        case readerSizeChanged(CGSize)
        case toggleStampsVisibility
        case stamp(ReaderStampFeature.Action)
        case visiblePageChanged(Int)
        case chapterSelected(Int)
        case chapter(ReaderChapterFeature.Action)
        case requestJump(Int, source: ReaderNavigationSource)
        case navigate(ReaderNavigationDirection, source: ReaderNavigationSource)
        case scrollRequestHandled(UUID)
        case collectionScrollStarted
        case collectionScrollEnded
        case sliderPreview(ReaderSliderPreviewFeature.Action)
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
        case primePageAspectRatios
    }

    public var body: some ReducerOf<Self> {
        Scope(\.autoPage, action: \.autoPage) { AutomaticPageFeature() }
        Scope(\.stamp, action: \.stamp) { ReaderStampFeature() }
        Scope(\.chapter, action: \.chapter) { ReaderChapterFeature() }

        Reduce<State, Action> { (state: inout State, action: Action) -> Effect<Action> in
            switch action {
            case .loadCached:
                return loadCached(state: &state)
            case .extractArchive:
                return extractArchive(state: &state)
            case let .finishExtracting(pages, tankoubonDetails):
                return finishExtracting(pages: pages, tankoubonDetails: tankoubonDetails, state: &state)
            case .primePageAspectRatios:
                return primePageAspectRatios(state: state)
            case let .pageAspectRatiosPrimed(aspectRatios):
                ReaderLayoutCoordinator.applyPrimedAspectRatios(aspectRatios, state: &state)
                return .none
            case let .toggleControlUi(show):
                if let shouldShow = show {
                    state.controlUiHidden = shouldShow
                } else {
                    state.controlUiHidden.toggle()
                }
                state.lastAutoPageIndex = nil
                state.sliderPreview.resetDisplayState()
                return .cancel(id: CancelId.autoPage)
            case let .pageLayoutModeChanged(mode):
                guard state.canToggleDoublePageLayout else { return .none }
                mode.save(automatic: state.$automaticPageLayout, double: state.$manualDoublePageLayout)
                return applyLayoutUpdate(state: &state)
            case let .readerSizeChanged(size):
                guard size.width > 0, size.height > 0 else { return .none }
                state.readerSize = size
                return applyLayoutUpdate(state: &state)
            case .toggleStampsVisibility:
                guard state.canUseStamps else { return .none }
                let showsStamps = !state.showStamps
                state.$showStamps.withLock { $0 = showsStamps }
                return .none
            case let .stamp(.delegate(delegateAction)):
                return handleStampDelegate(delegateAction, state: &state)
            case .stamp:
                return .none
            case let .chapter(.delegate(delegateAction)):
                return handleChapterDelegate(delegateAction, state: &state)
            case .chapter:
                return .none
            case let .visiblePageChanged(index):
                return handleVisiblePageChanged(index, state: &state)
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
                ReaderSplitPageCoordinator.applyPendingSplitResolutions(state: &state)
                return .none
            case let .sliderPreview(previewAction):
                return reduceSliderPreview(previewAction, state: &state)
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
                ReaderSplitPageCoordinator.preparePendingSplitMode(state: &state, pageIndex: targetIndex)
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
                return setThumbnail(state: &state)
            case .finishThumbnailLoading:
                state.settingThumbnail = false
                guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return .none }
                currentArchive.withLock { $0.refresh = true }
                return .none
            case let .setSuccess(message):
                state.successMessage = message
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            case .page(.element(id: _, action: .stampsLoadFailed(endpointUnavailable: true))):
                return .send(.stamp(.supportResolved(false)))
            case let .page(.element(id: id, action: .storedImageResolved(shouldDisplayAsSplitPages))):
                ReaderSplitPageCoordinator.handleSplitResolution(
                    id: id,
                    shouldDisplayAsSplitPages: shouldDisplayAsSplitPages,
                    state: &state
                )
                ReaderLayoutCoordinator.updateEstimatedPageAspectRatio(state: &state)
                return .none
            case let .page(.element(id: id, action: .load(true))):
                ReaderSplitPageCoordinator.setSplitSiblingsLoaded(false, id: id, state: &state)
                return .none
            case let .page(.element(id: id, action: .setError)):
                ReaderSplitPageCoordinator.setSplitSiblingsLoaded(true, id: id, state: &state)
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
                return handleAutoPageTick(state: state)
            case let .setLastAutoPageIndex(index):
                state.lastAutoPageIndex = index
                return .none
            case .downloadPages:
                return downloadPages(state: state)
            case .finishDownloadPages:
                let successMessage = String(localized: "archive.cache.added")
                state.successMessage = successMessage
                return .none
            case .removeCache:
                state.alert = AlertState {
                    TextState("archive.cache.remove.message")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) { TextState("delete") }
                    ButtonState(role: .cancel) { TextState("cancel") }
                }
                return .none
            case .alert(.presented(.confirmDelete)):
                return confirmCacheDelete(state: state)
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
        .forEach(\.pages, action: \.page) { PageFeature() }
        .ifLet(\.$alert, action: \.alert)
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
        state.lastAutoPageIndex = nil
        state.errorMessage = ""
        state.successMessage = ""
        state.currentTankoubonDetails = nil
        state.estimatedPageAspectRatio = ReaderPageLayout.defaultAspectRatio
        state.stamp.resetTransientState()
        state.chapter.resetTransientState()
        state.sliderPreview.resetArchiveState()
    }
}

extension ArchiveReaderFeature.State {
    var inCache: Bool {
        cachedArchiveIds.contains(currentArchiveId)
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

    var sliderPreviewContext: ReaderSliderPreviewContext {
        ReaderSliderPreviewContext(state: self)
    }

    func chapterCreationTarget() -> ChapterMutationTarget? {
        guard let page = currentPage else { return nil }
        return ChapterMutationTarget(
            readerArchiveId: currentArchiveId,
            readerPageNumber: page.pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
    }

    func chapterEditingTarget(for pageNumber: Int) -> (target: ChapterMutationTarget, title: String)? {
        guard let chapter = chapters.first(where: { $0.page == pageNumber }),
              let page = pages.first(where: { $0.pageNumber == pageNumber }) else {
            return nil
        }
        let target = ChapterMutationTarget(
            readerArchiveId: currentArchiveId,
            readerPageNumber: pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePageNumber: page.sourcePageNumber
        )
        return (target, chapter.name)
    }

    var chapters: [ArchiveChapter] {
        guard let currentArchive = allArchives[id: currentArchiveId] else {
            return []
        }
        return currentArchive.wrappedValue.toc ?? []
    }

    var canAddChapter: Bool {
        !cached && chapter.mutationsSupported != false && currentPage != nil
    }

    var editableChapterPages: Set<Int> {
        ReaderChapterFeature.editableChapterPages(
            archiveId: currentArchiveId,
            cached: cached,
            mutationsSupported: chapter.mutationsSupported,
            chapters: chapters,
            automaticChapterPages: currentTankoubonDetails?.automaticChapterPages
        )
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
        !cached && stamp.supported != false
    }

    var shouldShowStamps: Bool {
        canUseStamps && showStamps
    }
}

private extension ArchiveReaderFeature {
    func loadCached(state: inout State) -> Effect<Action> {
        state.extracting = true

        let id = state.currentArchiveId
        let cacheFolder = LANraragiService.cachePath!
            .appendingPathComponent(id, conformingTo: .folder)
        guard let content = try? FileManager.default.contentsOfDirectory(
            at: cacheFolder, includingPropertiesForKeys: []
        ) else {
            state.sliderPreview.resetArchiveState()
            state.controlUiHidden = true
            state.extracting = false
            return .send(.setError(String(localized: "archive.cache.load.failed")))
        }

        let pageState: [PageFeature.State] = content.compactMap { url in
            let page = url.deletingPathExtension().lastPathComponent
            guard let pageNumber = Int(page) else { return nil }
            return PageFeature.State(archiveId: id, pageId: page, pageNumber: pageNumber, cached: true)
        }
        .sorted { $0.pageNumber < $1.pageNumber }
        state.pages.append(contentsOf: pageState)
        let cachedArchive = state.allArchives[id: id]?.wrappedValue
        let cachedProgress = cachedArchive?.progress ?? 0
        let restartFinishedArchive = state.restartFinished && ReaderPositioning.isFinished(
            progress: cachedProgress,
            archivePageCount: cachedArchive?.pagecount ?? 0
        )
        ReaderLayoutCoordinator.restoreInitialPage(
            progress: cachedProgress,
            restartFinishedArchive: restartFinishedArchive,
            state: &state
        )
        state.controlUiHidden = true
        state.extracting = false
        return .merge(
            .send(.requestJump(state.currentPageIndex, source: .initialRestore)),
            .send(.primePageAspectRatios),
            .send(.sliderPreview(.startPrefetchIfNeeded))
        )
    }

    func extractArchive(state: inout State) -> Effect<Action> {
        state.extracting = true
        let id = state.currentArchiveId
        return .run { send in
            await send(.stamp(.supportResolved(await service.supportsStamps)))
            await send(.chapter(.mutationSupportResolved(await service.supportsChapterMutations)))
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
    }

    func finishExtracting(
        pages: [ReaderExtractedPage],
        tankoubonDetails: TankoubonDetailsMetadata?,
        state: inout State
    ) -> Effect<Action> {
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
            ReaderLayoutCoordinator.restoreInitialPage(
                progress: archive.progress,
                restartFinishedArchive: restartFinishedArchive,
                state: &state
            )
            state.controlUiHidden = true
        }
        state.extracting = false
        guard !state.pages.isEmpty else { return .none }
        return .merge(
            .send(.requestJump(state.currentPageIndex, source: .initialRestore)),
            .send(.primePageAspectRatios),
            .send(.sliderPreview(.prepareThumbnails))
        )
    }

    func primePageAspectRatios(state: State) -> Effect<Action> {
        guard let folder = state.pages.first?.folder else { return .none }
        return .run(priority: .utility) { send in
            let aspectRatios = imageService.storedImageAspectRatios(folderUrl: folder)
            guard !aspectRatios.isEmpty else { return }
            await send(.pageAspectRatiosPrimed(aspectRatios))
        }
        .cancellable(id: CancelId.primePageAspectRatios, cancelInFlight: true)
    }

    func applyLayoutUpdate(state: inout State) -> Effect<Action> {
        guard let jump = ReaderLayoutCoordinator.updatePageLayout(state: &state) else { return .none }
        return .send(.requestJump(jump.targetPageIndex, source: jump.source))
    }

    func handleVisiblePageChanged(_ index: Int, state: inout State) -> Effect<Action> {
        guard !state.pages.isEmpty else { return .none }
        let clampedIndex = ReaderPositioning.clampedPageIndex(index, pageCount: state.pages.count)
        guard clampedIndex != state.currentPageIndex else { return .none }
        ReaderSplitPageCoordinator.preparePendingSplitMode(state: &state, pageIndex: clampedIndex)
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
        return persistReadProgress(
            pageNumber: pageNumber,
            isTank: isTank,
            shouldClearNewFlag: shouldClearNewFlag,
            state: state
        )
    }

    func persistReadProgress(
        pageNumber: Int,
        isTank: Bool,
        shouldClearNewFlag: Bool,
        state: State
    ) -> Effect<Action> {
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
    }

    func setThumbnail(state: inout State) -> Effect<Action> {
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
    }

    func handleAutoPageTick(state: State) -> Effect<Action> {
        let idx = state.currentPageIndex
        var canAdvance = true
        if state.lastAutoPageIndex == idx {
            canAdvance = false
        } else if idx == (state.pages.count - 1) {
            return .cancel(id: CancelId.autoPage)
        } else {
            if idx >= 0 && idx < state.pages.count {
                if !state.pages[idx].imageLoaded {
                    canAdvance = false
                }
            } else {
                return .cancel(id: CancelId.autoPage)
            }
            if canAdvance
                && state.readDirection != ReadDirection.upDown.rawValue
                && state.doublePageLayout {
                let previousIdx = idx - 1
                if previousIdx >= 0 && previousIdx < state.pages.count,
                   !state.pages[previousIdx].imageLoaded {
                    canAdvance = false
                }
            }
        }

        return .run { [idx, canAdvance, interval = state.autoPageInterval] send in
            if canAdvance {
                try await clock.sleep(for: .seconds(interval))
                await send(.navigate(.next, source: .autoPage))
                await send(.setLastAutoPageIndex(idx))
            } else {
                try await clock.sleep(for: .milliseconds(300))
            }
            await send(.autoPageTick)
        }.cancellable(id: CancelId.autoPage)
    }

    func downloadPages(state: State) -> Effect<Action> {
        .run { [state] send in
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
    }

    func confirmCacheDelete(state: State) -> Effect<Action> {
        .run { [id = state.currentArchiveId] send in
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
    }

    func reduceSliderPreview(
        _ action: ReaderSliderPreviewFeature.Action,
        state: inout State
    ) -> Effect<Action> {
        if case let .delegate(.jumpRequested(index)) = action {
            return .send(.requestJump(index, source: .slider))
        }
        return ReaderSliderPreviewFeature().reduce(
            state: &state.sliderPreview,
            action: action,
            context: state.sliderPreviewContext,
            embed: Action.sliderPreview
        )
    }

    func switchArchive(offset: Int, state: inout State) -> Effect<Action> {
        guard let currentIndex = state.allArchives.firstIndex(where: { $0.id == state.currentArchiveId }),
              state.allArchives.indices.contains(currentIndex + offset) else {
            return .none
        }
        state.currentArchiveId = state.allArchives[currentIndex + offset].wrappedValue.id
        resetState(state: &state)
        return .merge(
            .cancel(id: CancelId.autoPage),
            .cancel(id: CancelId.primePageAspectRatios),
            ReaderSliderPreviewFeature.cancelEffects(),
            ReaderStampFeature.cancelEffects(),
            ReaderChapterFeature.cancelEffects(),
            state.cached ? .send(.loadCached) : .send(.extractArchive)
        )
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
