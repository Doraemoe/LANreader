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
        @SharedReader(.appStorage(SettingsKey.fallbackReader)) var fallbackReader = false
        @SharedReader(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.splitPiorityLeft)) var piorityLeft = false
        @SharedReader(.appStorage(SettingsKey.autoPageInterval)) var autoPageInterval = 5.0
        @SharedReader(.appStorage(SettingsKey.doublePageLayout)) var doublePageLayout = false
        @Shared var archive: ArchiveItem

        var indexString: String?
        var sliderIndex: Double = 0
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

        var fallbackIndexString: String {
            indexString ?? ""
        }
        var currentIndex: Int? {
            pages.index(id: indexString ?? "")
        }

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
        case preload(Int)
        case setIndexString(String)
        case setSliderIndex(Double)
        case updateProgress(Int)
        case setIsNew(Bool)
        case setThumbnail
        case finishThumbnailLoading
        case tapAction(String)
        case setError(String)
        case setSuccess(String)
        case downloadPages
        case finishDownloadPages
        case removeCache
        case loadCached

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
                    state.indexString = state.pages[0].id
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
                        let normalizedPage = String(page.dropFirst(2))
                        return PageFeature.State(
                            archiveId: state.archive.id, pageId: normalizedPage, pageNumber: index + 1
                        )
                    }
                    state.pages.append(contentsOf: pageState)
                    let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                    let pageIndexToShow = state.fromStart ? 0 : progress
                    state.sliderIndex = Double(pageIndexToShow)
                    state.indexString = state.pages[pageIndexToShow].id
                    state.controlUiHidden = true
                }
                state.extracting = false
                return .none
            case .loadProgress:
                let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                state.sliderIndex = Double(progress)
                state.indexString = state.pages[progress].id
                state.controlUiHidden = true
                return .none
            case let .toggleControlUi(show):
                if let shouldShow = show {
                    state.controlUiHidden = shouldShow
                } else {
                    state.controlUiHidden.toggle()
                }
                return .none
            case let .preload(index):
                return .run(priority: .utility) { [state] send in
                    if state.doublePageLayout &&
                        state.readDirection != ReadDirection.upDown.rawValue &&
                        !state.fallbackReader {
                        if index - 1 > 0 {
                            let previous2PageId = state.pages[index-2].id
                            await send(.page(.element(id: previous2PageId, action: .load(false))))
                        }
                        if index - 2 > 0 {
                            let previous3PageId = state.pages[index-3].id
                            await send(.page(.element(id: previous3PageId, action: .load(false))))
                        }
                        if index + 2 < state.pages.count {
                            let next2PageId = state.pages[index+2].id
                            await send(.page(.element(id: next2PageId, action: .load(false))))
                        }
                        if index + 3 < state.pages.count {
                            let next3PageId = state.pages[index+3].id
                            await send(.page(.element(id: next3PageId, action: .load(false))))
                        }
                    } else {
                        if index > 0 {
                            let previousPageId = state.pages[index-1].id
                            await send(.page(.element(id: previousPageId, action: .load(false))))
                        }
                        if index + 1 < state.pages.count {
                            let nextPageId = state.pages[index+1].id
                            await send(.page(.element(id: nextPageId, action: .load(false))))
                        }
                    }
                }
            case let .setIndexString(indexString):
                state.indexString = indexString
                return .none
            case let .setSliderIndex(index):
                state.sliderIndex = index
                return .none
            case let .updateProgress(pageNumber):
                state.archive.progress = pageNumber
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
                state.archive.isNew = isNew
                return .none
            case .setThumbnail:
                state.settingThumbnail = true
                guard let pageNumber = state.pages[id: state.indexString ?? ""]?.pageNumber else {return .none }
                return .run { [id = state.archive.id] send in
                    _ = try await service.updateArchiveThumbnail(id: id, page: pageNumber).value
                    let thumbnailUrl = try await service.retrieveArchiveThumbnail(id: id)
                        .serializingDownloadedFileURL()
                        .value
                    imageService.processThumbnail(
                        thumbnailUrl: thumbnailUrl,
                        destinationUrl: LANraragiService.thumbnailPath!
                            .appendingPathComponent("\(id).heic", conformingTo: .heic)
                    )
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
                state.archive.refresh = true
                return .none
            case let .tapAction(action):
                switch action {
                case PageControl.next.rawValue:
                    if let pageIndex = state.currentIndex {
                        if state.doublePageLayout &&
                            state.readDirection != ReadDirection.upDown.rawValue &&
                            !state.fallbackReader {
                            if pageIndex < state.pages.count - 2 {
                                state.indexString = state.pages[pageIndex + 2].id
                            } else if pageIndex < state.pages.count - 1 {
                                state.indexString = state.pages[pageIndex + 1].id
                            }
                        } else {
                            if pageIndex < state.pages.count - 1 {
                                state.indexString = state.pages[pageIndex + 1].id
                            }
                        }
                    }
                case PageControl.previous.rawValue:
                    if let pageIndex = state.currentIndex {
                        if state.doublePageLayout &&
                            state.readDirection != ReadDirection.upDown.rawValue &&
                            !state.fallbackReader {
                            if pageIndex > 1 {
                                state.indexString = state.pages[pageIndex - 2].id
                            } else if pageIndex > 0 {
                                state.indexString = state.pages[pageIndex - 1].id
                            }
                        } else {
                            if pageIndex > 0 {
                                state.indexString = state.pages[pageIndex - 1].id
                            }
                        }
                    }
                case PageControl.navigation.rawValue:
                    state.controlUiHidden.toggle()
                    state.startAutoPage = false
                    return .cancel(id: CancelId.autoPage)
                default:
                    // This should not happen
                    break
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
                return .run { [id = state.archive.id] send in
                    let deleted = try database.deleteCache(id)
                    if deleted != true {
                        let errorMessage = String(localized: "archive.cache.remove.failed")
                        await send(.setError(errorMessage))
                    } else {
                        let cacheFolder = LANraragiService.cachePath!
                            .appendingPathComponent(id, conformingTo: .folder)
                        try? FileManager.default.removeItem(at: cacheFolder)
                        await self.dismiss()
                    }
                } catch: { [id = state.archive.id] error, send in
                    logger.error("failed to remove archive cache, id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                }
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
    @FocusState private var isFocused: Bool

    @Bindable var store: StoreOf<ArchiveReaderFeature>

    var body: some View {
        let flip = store.readDirection == ReadDirection.rightLeft.rawValue
        GeometryReader { geometry in
            ZStack {
                if store.readDirection == ReadDirection.upDown.rawValue {
                    vReader(store: store, geometry: geometry)
                } else if store.fallbackReader {
                    hReaderFallback(store: store, geometry: geometry)
                        .environment(\.layoutDirection, flip ? .rightToLeft : .leftToRight)
                } else {
                    hReader(store: store, geometry: geometry)
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
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            if store.readDirection == ReadDirection.leftRight.rawValue {
                if press.key == .leftArrow {
                    store.send(.tapAction(PageControl.previous.rawValue), animation: .linear)
                } else if press.key == .rightArrow {
                    store.send(.tapAction(PageControl.next.rawValue), animation: .linear)
                }
            } else if store.readDirection == ReadDirection.rightLeft.rawValue {
                if press.key == .leftArrow {
                    store.send(.tapAction(PageControl.next.rawValue), animation: .linear)
                } else if press.key == .rightArrow {
                    store.send(.tapAction(PageControl.previous.rawValue), animation: .linear)
                }
            }
            return .handled
        }
        .onAppear {
            isFocused = true
        }
//        .toolbar {
//            ToolbarItem(placement: .primaryAction) {
//                NavigationLink(
//                    state: AppFeature.Path.State.details(
//                        ArchiveDetailsFeature.State.init(archive: store.$archive, cached: store.cached)
//                    )
//                ) {
//                    Image(systemName: "info.circle")
//                }
//            }
//        }
        .alert(
            $store.scope(state: \.alert, action: \.alert)
        )
        .toolbar(store.controlUiHidden ? .hidden : .visible, for: .navigationBar)
        .navigationBarTitle(store.archive.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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
                    print("exracting")
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
        .onChange(of: store.indexString) { _, newValue in
            if let id = newValue {
                let index = store.pages.index(id: id) ?? 0
                let pageNumber = store.pages[id: id]?.pageNumber ?? 1
                store.send(.preload(index))
                store.send(.setSliderIndex(Double(index)))
                store.send(.updateProgress(pageNumber))
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
        .onChange(of: store.autoDate) {
            if store.startAutoPage {
                store.send(.tapAction(PageControl.next.rawValue), animation: .linear)
            }
        }
    }

    @MainActor
    private func vReader(
        store: StoreOf<ArchiveReaderFeature>,
        geometry: GeometryProxy
    ) -> some View {
//        ScrollView(.vertical) {
//            LazyVStack(spacing: 0) {
//                ForEach(
//                    store.scope(
//                        state: \.pages,
//                        action: \.page
//                    ),
//                    id: \.state.id
//                ) { pageStore in
//                    PageImageV2(store: pageStore, geometrySize: geometry.size)
//                        .frame(width: geometry.size.width)
//                }
//            }
//            .scrollTargetLayout()
//        }
//        .scrollPosition(id: $store.indexString)
        UIPageCollection(store: store, size: geometry.size)
            .onTapGesture {
                store.send(.tapAction(PageControl.navigation.rawValue))
            }
    }

    @MainActor
    private func hReader(
        store: StoreOf<ArchiveReaderFeature>,
        geometry: GeometryProxy
    ) -> some View {
//        ScrollView(.horizontal) {
//            LazyHStack(spacing: 0) {
//                ForEach(
//                    store.scope(
//                        state: \.pages,
//                        action: \.page
//                    ),
//                    id: \.state.id
//                ) { pageStore in
//                    PageImageV2(store: pageStore, geometrySize: geometry.size)
//                        .frame(width: store.doublePageLayout ? geometry.size.width / 2 : geometry.size.width)
//                }
//            }
//            .scrollTargetLayout()
//        }
//        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
//        .scrollPosition(id: $store.indexString)
        UIPageCollection(store: store, size: geometry.size)
            .onTapGesture { location in
                if location.x < geometry.size.width / 3 {
                    store.send(.tapAction(store.tapLeft), animation: .linear)
                } else if location.x > geometry.size.width / 3 * 2 {
                    store.send(.tapAction(store.tapRight), animation: .linear)
                } else {
                    store.send(.tapAction(store.tapMiddle), animation: .linear)
                }
            }
    }

    @MainActor
    private func hReaderFallback(
        store: StoreOf<ArchiveReaderFeature>,
        geometry: GeometryProxy
    ) -> some View {
        TabView(selection: $store.fallbackIndexString.sending(\.setIndexString)) {
            ForEach(
                store.scope(
                    state: \.pages,
                    action: \.page
                ),
                id: \.state.id
            ) { pageStore in
                PageImageV2(store: pageStore, geometrySize: geometry.size)
                    .frame(width: geometry.size.width)
                    .tag(pageStore.state.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onTapGesture { location in
            if location.x < geometry.size.width / 3 {
                store.send(.tapAction(store.tapLeft), animation: .linear)
            } else if location.x > geometry.size.width / 3 * 2 {
                store.send(.tapAction(store.tapRight), animation: .linear)
            } else {
                store.send(.tapAction(store.tapMiddle), animation: .linear)
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
                        store.send(.page(.element(id: store.indexString ?? "", action: .load(true))))
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
                            let indexString = store.pages[store.sliderIndex.int].id
                            store.send(.setIndexString(indexString))
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
