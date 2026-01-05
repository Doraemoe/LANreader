import ComposableArchitecture
import SwiftUI
import Logging
import Combine
import NotificationBannerSwift
import OrderedCollections

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
        var sliderIndex: Double = 0
        var jumpIndex: Int? = 0
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var fromStart = false
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""
        var showAutoPageConfig = false
        var autoPage = AutomaticPageFeature.State()
        var autoDate = Date()
        var lastAutoPageIndex: Int?
        var cached = false
        var inCache = false
        var removeCacheSuccess = false

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
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        case autoPage(AutomaticPageFeature.Action)
        case showAutoPageConfig
        case setAutoDate(Date)
        case autoPageTick
        case setLastAutoPageIndex(Int?)
        case page(IdentifiedActionOf<PageFeature>)
        case extractArchive
        case loadProgress
        case finishExtracting([String])
        case toggleControlUi(Bool?)
        case setJumpIndex(Int?)
        case setSliderIndex(Double)
        case updateProgress(Int)
        case setIsNew(Bool)
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

        public enum Alert: Sendable {
            case confirmDelete
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.appDatabase) var database
    @Dependency(\.dismiss) var dismiss

    public enum CancelId: Sendable {
        case updateProgress
        case autoPage
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
                   state.sliderIndex = 0.0
                   state.controlUiHidden = true
                   state.extracting = false
                   return .none
               } else {
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
                    let progress = currentArchive.wrappedValue.progress > 0 ?
                    currentArchive.wrappedValue.progress - 1 : 0
                    let pageIndexToShow = state.fromStart ? 0 : progress
                    state.sliderIndex = Double(pageIndexToShow)
                    state.jumpIndex = pageIndexToShow
                    state.controlUiHidden = true
                }
                state.extracting = false
                return .none
            case .loadProgress:
                guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return .none }
                let progress = currentArchive.wrappedValue.progress > 0 ?
                currentArchive.wrappedValue.progress - 1 : 0
                state.sliderIndex = Double(progress)
                state.controlUiHidden = true
                return .none
            case let .toggleControlUi(show):
                if let shouldShow = show {
                    state.controlUiHidden = shouldShow
                } else {
                    state.controlUiHidden.toggle()
                }
                state.lastAutoPageIndex = nil
                return .cancel(id: CancelId.autoPage)
            case let .setJumpIndex(jumpIndex):
                state.jumpIndex = jumpIndex
                return .none
            case let .setSliderIndex(index):
                state.sliderIndex = index
                return .none
            case let .updateProgress(pageNumber):
                guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return .none }
                currentArchive.withLock {
                    $0.progress = pageNumber
                }
                if state.cached {
                    return .none
                }
                return .run(priority: .background) { [state] send in
                    if state.serverProgress {
                        _ = try await service.updateArchiveReadProgress(
                            id: state.currentArchiveId, progress: pageNumber
                        ).value
                    }
                    if pageNumber > 1 && currentArchive.wrappedValue.isNew {
                        _ = try await service.clearNewFlag(id: state.currentArchiveId).value
                        await send(.setIsNew(false))
                    }
                } catch: { [state] error, _ in
                    logger.error("failed to update archive progress. id=\(state.currentArchiveId) \(error)")
                }
                .debounce(id: CancelId.updateProgress, for: .seconds(0.5), scheduler: DispatchQueue.main)
            case let .setIsNew(isNew):
                guard let currentArchive = state.allArchives[id: state.currentArchiveId] else { return .none }
                currentArchive.withLock {
                    $0.isNew = isNew
                }
                return .none
            case .setThumbnail:
                state.settingThumbnail = true
                let pageNumber = state.pages[state.sliderIndex.int].pageNumber
                return .run { [id = state.currentArchiveId] send in
                    _ = try await service.updateArchiveThumbnail(id: id, page: pageNumber).value
                    let thumbnailUrl = try await service.retrieveArchiveThumbnail(id: id)
                        .serializingDownloadedFileURL()
                        .value
                    var archiveThumbnail = ArchiveThumbnail(
                        id: id,
                        thumbnail: imageService.heicDataOfImage(url: thumbnailUrl) ?? Data(),
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
            case let .setAutoDate(date):
                state.autoDate = date
                return .none
            case .autoPage(.cancelAutoPage):
                state.showAutoPageConfig = false
                return .none
            case .autoPage:
                return .none
            case .autoPageTick:
                let idx = state.sliderIndex.int
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
                        try? await Task.sleep(for: .seconds(interval))
                        await send(.setAutoDate(Date()))
                        await send(.setLastAutoPageIndex(idx))
                    } else {
                        try? await Task.sleep(for: .milliseconds(300))
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
                if state.cached {
                    return .send(.loadCached)
                } else {
                    return .send(.extractArchive)
                }
            case .loadNextArchive:
                guard let currentIndex = state.allArchives.firstIndex(where: { $0.id == state.currentArchiveId }) else {
                    return .none
                }
                guard currentIndex < state.allArchives.count - 1 else { return .none }
                let newShared = state.allArchives[currentIndex + 1]
                state.currentArchiveId = newShared.wrappedValue.id
                self.resetState(state: &state)
                if state.cached {
                    return .send(.loadCached)
                } else {
                    return .send(.extractArchive)
                }
            }
        }
        .forEach(\.pages, action: \.page) {
            PageFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }

    func resetState(state: inout State) {
        state.pages = []
        state.sliderIndex = 0
        state.jumpIndex = 0
        state.inCache = false
        state.errorMessage = ""
        state.successMessage = ""
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
                    bottomToolbar(store: store)
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
            $store.scope(state: \.alert, action: \.alert)
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
    }

    // swiftlint:disable function_body_length
    @MainActor
    private func bottomToolbar(
        store: StoreOf<ArchiveReaderFeature>
    ) -> some View {
        return VStack {
            Grid {
                GridRow {
                    Button(action: {
                        let indexString = store.pages[store.sliderIndex.int].id
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
                                store.sliderIndex.int + 1,
                                store.pages.count))
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
                    Slider(
                        value: $store.sliderIndex,
                        in: 0...Double(store.pages.count <= 1 ? 1 : store.pages.count - 1),
                        step: 1
                    ) { onSlider in
                        if !onSlider {
                            store.send(.setJumpIndex(store.sliderIndex.int))
                        }
                    }
                    .padding(.horizontal)
                    .gridCellColumns(5)
                }
            }
            .padding()
            .background(.thinMaterial)
        }
    }
    // swiftlint:enable function_body_length
}
