import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveReaderFeature {
    private let logger = Logger(label: "ArchiveReaderFeature")

    @ObservableState
    struct State: Equatable {
        @SharedReader(.appStorage(SettingsKey.tapLeftKey)) var tapLeft = PageControl.next.rawValue
        @SharedReader(.appStorage(SettingsKey.tapMiddleKey)) var tapMiddle = PageControl.navigation.rawValue
        @SharedReader(.appStorage(SettingsKey.tapRightKey)) var tapRight = PageControl.previous.rawValue
        @SharedReader(.appStorage(SettingsKey.readDirection)) var readDirection = ReadDirection.leftRight.rawValue
        @SharedReader(.appStorage(SettingsKey.fallbackReader)) var fallbackReader = false
        @SharedReader(.appStorage(SettingsKey.serverProgress)) var serverProgress = false
        @SharedReader(.appStorage(SettingsKey.splitWideImage)) var splitImage = false
        @SharedReader(.appStorage(SettingsKey.splitPiorityLeft)) var piorityLeft = false
        @Shared var archive: ArchiveItem
        @Shared var archiveThumbnail: Data?

        var indexString: String?
        var sliderIndex: Double = 0
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var fromStart = false
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""

        var fallbackIndexString: String {
            indexString ?? ""
        }
        var currentIndex: Int? {
            pages.index(id: indexString ?? "")
        }

        init(archive: Shared<ArchiveItem>, fromStart: Bool = false) {
            self._archive = archive
            self._archiveThumbnail = Shared(
                wrappedValue: nil,
                    .fileStorage(
                        LANraragiService.thumbnailPath!
                            .appendingPathComponent(archive.id, conformingTo: .image)
                    )
            )
            self.fromStart = fromStart
        }
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
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
        case setThumbnailData(Data)
        case finishThumbnailLoading
        case tapAction(String)
        case setError(String)
        case setSuccess(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    enum CancelId { case updateProgress }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .extractArchive:
                state.extracting = true
                let id = state.archive.id
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
                let pageState = pages.enumerated().map { (index, page) in
                    let normalizedPage = String(page.dropFirst(2))
                    return PageFeature.State(archiveId: state.archive.id, pageId: normalizedPage, pageNumber: index + 1)
                }
                state.pages.append(contentsOf: pageState)
                state.extracting = false
                let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                let pageIndexToShow = state.fromStart ? 0 : progress
                state.sliderIndex = Double(pageIndexToShow)
                state.indexString = state.pages[pageIndexToShow].id
                state.controlUiHidden = true
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
                    if index - 1 > 0 {
                        let previousPageId = state.pages[index-1].id
                        await send(.page(.element(id: previousPageId, action: .load(false))))
                    }
                    if index + 1 < state.pages.count {
                        let nextPageId = state.pages[index+1].id
                        await send(.page(.element(id: nextPageId, action: .load(false))))
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
                    let imageData = try await service.retrieveArchiveThumbnail(id: id).serializingData().value
                    await send(.setThumbnailData(imageData))
                    let successMessage = String(localized: "archive.thumbnail.set")
                    await send(.setSuccess(successMessage))
                    await send(.finishThumbnailLoading)
                } catch: { [id = state.archive.id] error, send in
                    logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                }
            case let .setThumbnailData(thumbnail):
                state.archiveThumbnail = thumbnail
                return .none
            case .finishThumbnailLoading:
                state.settingThumbnail = false
                return .none
            case let .tapAction(action):
                switch action {
                case PageControl.next.rawValue:
                    if let pageIndex = state.currentIndex {
                        if pageIndex < state.pages.count - 1 {
                            state.indexString = state.pages[pageIndex + 1].id
                        }
                    }
                case PageControl.previous.rawValue:
                    if let pageIndex = state.currentIndex {
                        if pageIndex > 0 {
                            state.indexString = state.pages[pageIndex - 1].id
                        }
                    }
                case PageControl.navigation.rawValue:
                    state.controlUiHidden.toggle()
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
                        pageMode: mode
                    ),
                    at: currentIndex + 1
                )
                return .none
            case .page:
                return .none
            }
        }
        .forEach(\.pages, action: \.page) {
            PageFeature()
        }
    }
}

struct ArchiveReader: View {
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(
                    state: AppFeature.Path.State.details(
                        ArchiveDetailsFeature.State.init(archive: store.$archive)
                    )
                ) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .toolbar(store.controlUiHidden ? .hidden : .visible, for: .navigationBar)
        .navigationBarTitle(store.archive.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if store.pages.isEmpty {
                store.send(.extractArchive)
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
    }

    @MainActor
    private func vReader(
        store: StoreOf<ArchiveReaderFeature>,
        geometry: GeometryProxy
    ) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(
                    store.scope(
                        state: \.pages,
                        action: \.page
                    ),
                    id: \.state.id
                ) { pageStore in
                    PageImageV2(store: pageStore, geometrySize: geometry.size)
                        .frame(width: geometry.size.width)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $store.indexString)
        .onTapGesture {
            store.send(.tapAction(PageControl.navigation.rawValue))
        }
    }

    @MainActor
    private func hReader(
        store: StoreOf<ArchiveReaderFeature>,
        geometry: GeometryProxy
    ) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(
                    store.scope(
                        state: \.pages,
                        action: \.page
                    ),
                    id: \.state.id
                ) { pageStore in
                    PageImageV2(store: pageStore, geometrySize: geometry.size)
                        .frame(width: geometry.size.width)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $store.indexString)
        .onTapGesture { location in
            if location.x < geometry.size.width / 3 {
                store.send(.tapAction(store.tapLeft))
            } else if location.x > geometry.size.width / 3 * 2 {
                store.send(.tapAction(store.tapRight))
            } else {
                store.send(.tapAction(store.tapMiddle))
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
                store.send(.tapAction(store.tapLeft))
            } else if location.x > geometry.size.width / 3 * 2 {
                store.send(.tapAction(store.tapRight))
            } else {
                store.send(.tapAction(store.tapMiddle))
            }
        }
    }

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
                    Text(String(format: "%d/%d",
                                store.sliderIndex.int + 1,
                                store.pages.count))
                    .bold()
                    Button(action: {
                        Task {
                            store.send(.setThumbnail)
                        }
                    }, label: {
                        Image(systemName: "photo.artframe")
                    })
                    .disabled(store.settingThumbnail)
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
                    .gridCellColumns(3)
                }
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
