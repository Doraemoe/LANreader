import ComposableArchitecture
import SwiftUI
import Logging
import Combine
import NotificationBannerSwift
import OrderedCollections

@Reducer public struct ArchiveReaderFeature {
    private let logger = Logger(label: "ArchiveReaderFeature")

    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?

        @SharedReader(.appStorage(SettingsKey.tapLeftKey)) var tapLeft = PageControl.next.rawValue
        @SharedReader(.appStorage(SettingsKey.tapMiddleKey)) var tapMiddle = PageControl.navigation.rawValue
        @SharedReader(.appStorage(SettingsKey.tapRightKey)) var tapRight = PageControl.previous.rawValue
        @SharedReader(.appStorage(SettingsKey.readDirection)) var readDirection = ReadDirection.leftRight.rawValue
        @SharedReader(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0
        @SharedReader(.appStorage(SettingsKey.doublePageLayout)) var doublePageLayout = false
        @Shared var archive: ArchiveItem

        var sliderIndex: Double = 0
        var jumpIndex: Int = 0
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var fromStart = false
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""
        var showAutoPageConfig = false
        var startAutoPage = false
        var autoPage = AutomaticPageFeature.State()
        var autoDate = Date()
        var cached = false
        var inCache = false
        var removeCacheSuccess = false

        init(archive: Shared<ArchiveItem>, fromStart: Bool = false, cached: Bool = false) {
            self._archive = archive
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
        case page(IdentifiedActionOf<PageFeature>)
        case extractArchive
        case loadProgress
        case finishExtracting([String])
        case toggleControlUi(Bool?)
        case setJumpIndex(Int)
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

        public enum Alert {
            case confirmDelete
        }
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService
    @Dependency(\.appDatabase) var database
    @Dependency(\.dismiss) var dismiss

    public enum CancelId {
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

                let id = state.archive.id
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
                let id = state.archive.id
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
                            archiveId: state.archive.id, pageId: normalizedPage, pageNumber: index + 1
                        )
                    }
                    state.pages.append(contentsOf: pageState)
                    let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                    let pageIndexToShow = state.fromStart ? 0 : progress
                    state.sliderIndex = Double(pageIndexToShow)
                    state.jumpIndex = pageIndexToShow
                    state.controlUiHidden = true
                }
                state.extracting = false
                return .none
            case .loadProgress:
                let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                state.sliderIndex = Double(progress)
                state.controlUiHidden = true
                return .none
            case let .toggleControlUi(show):
                if let shouldShow = show {
                    state.controlUiHidden = shouldShow
                } else {
                    state.controlUiHidden.toggle()
                }
                return .cancel(id: CancelId.autoPage)
            case let .setJumpIndex(jumpIndex):
                state.jumpIndex = jumpIndex
                return .none
            case let .setSliderIndex(index):
                state.sliderIndex = index
                return .none
            case let .updateProgress(pageNumber):
                state.$archive.withLock {
                    $0.progress = pageNumber
                }
                if state.cached {
                    return .none
                }
                return .run(priority: .background) { [state] send in
                    if state.serverProgress {
                        _ = try await service.updateArchiveReadProgress(
                            id: state.archive.id, progress: pageNumber
                        ).value
                    }
                    if pageNumber > 1 && state.archive.isNew {
                        _ = try await service.clearNewFlag(id: state.archive.id).value
                        await send(.setIsNew(false))
                    }
                } catch: { [state] error, _ in
                    logger.error("failed to update archive progress. id=\(state.archive.id) \(error)")
                }
                .debounce(id: CancelId.updateProgress, for: .seconds(0.5), scheduler: DispatchQueue.main)
            case let .setIsNew(isNew):
                state.$archive.withLock {
                    $0.isNew = isNew
                }
                return .none
            case .setThumbnail:
                state.settingThumbnail = true
                let pageNumber = state.pages[state.sliderIndex.int].pageNumber
                return .run { [id = state.archive.id] send in
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
                } catch: { [id = state.archive.id] error, send in
                    logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                    await send(.finishThumbnailLoading)
                }
            case .finishThumbnailLoading:
                state.settingThumbnail = false
                state.$archive.withLock {
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
                        archiveId: state.archive.id,
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
                state.startAutoPage = true
                return .run { [interval = state.autoPageInterval] send in
                    for await timerDate in Timer.publish(every: interval, on: .main, in: .common).autoconnect().values {
                        await send(.setAutoDate(timerDate))
                    }
                }
                .cancellable(id: CancelId.autoPage)
            case let .setAutoDate(date):
                state.autoDate = date
                return .none
            case .autoPage(.cancelAutoPage):
                state.showAutoPageConfig = false
                return .none
            case .autoPage:
                return .none
            case .downloadPages:
                return .run { [state] send in
                    var requested: [String] = []
                    for page in state.pages where !requested.contains(where: { requestedId in
                        requestedId == page.pageId
                    }) {
                        service.backgroupFetchArchivePage(
                            page: page.pageId,
                            archiveId: state.archive.id,
                            pageNumber: page.pageNumber
                        )
                        requested.append(page.pageId)
                    }
                    var cache = ArchiveCache(
                        id: state.archive.id,
                        title: state.archive.name,
                        tags: state.archive.tags,
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
                return .run { [id = state.archive.id] send in
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
                } catch: { [id = state.archive.id] error, send in
                    logger.error("failed to remove archive cache, id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                }
            case .removeCacheSuccess:
                state.removeCacheSuccess = true
                return .none
            case .alert:
                return .none
            }
        }
        .forEach(\.pages, action: \.page) {
            PageFeature()
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

struct ArchiveReader: View {
    @Bindable var store: StoreOf<ArchiveReaderFeature>
    let navigationHelper: NavigationHelper?

    var body: some View {
        let flip = store.readDirection == ReadDirection.rightLeft.rawValue
        GeometryReader { geometry in
            ZStack {
                if store.readDirection == ReadDirection.upDown.rawValue {
                    UIPageCollection(store: store)
                } else {
                    UIPageCollection(store: store)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                }
                if !store.controlUiHidden {
                    bottomToolbar(store: store)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                }
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
            if store.archive.extension == "rar" || store.archive.extension == "cbr" {
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
            Spacer()
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
