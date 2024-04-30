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

        var index: Int?
        var sliderIndex: Double = 0
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var archive: ArchiveItem
        var fromStart = false
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""

        var fallbackIndex: Int {
            index ?? 0
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
        case setIndex(Int)
        case setSliderIndex(Double)
        case updateProgress
        case setIsNew(Bool)
        case setThumbnail
        case finishThumbnailLoading
        case tapAction(String)
        case setError(String)
        case setSuccess(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.refreshTrigger) var refreshTrigger

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
                    return PageFeature.State(id: index, pageId: normalizedPage)
                }
                state.pages.append(contentsOf: pageState)
                state.extracting = false
                let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                state.index = state.fromStart ? 0 : progress
                state.sliderIndex = Double(progress)
                state.controlUiHidden = true
                return .none
            case .loadProgress:
                let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                state.index = state.fromStart ? 0 : progress
                state.sliderIndex = Double(progress)
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
                return .run(priority: .utility) { [totalPage = state.pages.count] send in
                    if index - 1 > 0 {
                        await send(.page(.element(id: index - 1, action: .load(false))))
                    }
                    if index + 1 < totalPage {
                        await send(.page(.element(id: index + 1, action: .load(false))))
                    }
                }
            case let .setIndex(index):
                state.index = index
                return .none
            case let .setSliderIndex(index):
                state.sliderIndex = index
                return .none
            case .updateProgress:
                let progress = (state.index ?? 0) + 1
                state.archive.progress = progress
                return .run(priority: .background) { [state] send in
                    if state.serverProgress {
                        _ = try await service.updateArchiveReadProgress(id: state.archive.id, progress: progress).value
                    }
                    if progress > 1 && state.archive.isNew {
                        _ = try await service.clearNewFlag(id: state.archive.id).value
                        await send(.setIsNew(false))
                    }
                    refreshTrigger.progress.send((state.archive.id, progress))
                } catch: { [state] error, _ in
                    logger.error("failed to update archive progress. id=\(state.archive.id) \(error)")
                }
                .debounce(id: CancelId.updateProgress, for: .seconds(0.5), scheduler: DispatchQueue.main)
            case let .setIsNew(isNew):
                state.archive.isNew = isNew
                return .none
            case .setThumbnail:
                state.settingThumbnail = true
                let index = (state.index ?? 0) + 1
                return .run { [id = state.archive.id] send in
                    _ = try await service.updateArchiveThumbnail(id: id, page: index).value
                    let successMessage = String(localized: "archive.thumbnail.set")
                    await send(.setSuccess(successMessage))
                    refreshTrigger.thumbnail.send(id)
                    await send(.finishThumbnailLoading)
                } catch: { [id = state.archive.id] error, send in
                    logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
                    await send(.setError(error.localizedDescription))
                }
            case .finishThumbnailLoading:
                state.settingThumbnail = false
                return .none
            case let .tapAction(action):
                switch action {
                case PageControl.next.rawValue:
                    if let pageIndex = state.index {
                        if pageIndex < state.archive.pagecount - 1 {
                            state.index! += 1
                        }
                    }
                case PageControl.previous.rawValue:
                    if let pageIndex = state.index {
                        if pageIndex > 0 {
                            state.index! -= 1
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
                        ArchiveDetailsFeature.State.init(id: store.archive.id)
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
            } else {
                store.send(.loadProgress)
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
        .onChange(of: store.index) { _, newValue in
            if let index = newValue {
                store.send(.preload(index))
                store.send(.setSliderIndex(Double(index)))
                store.send(.updateProgress)
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
        .scrollPosition(id: $store.index)
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
        .scrollPosition(id: $store.index)
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
        TabView(selection: $store.fallbackIndex.sending(\.setIndex)) {
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
                        store.send(.page(.element(id: store.index ?? 0, action: .load(true))))
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
                            store.send(.setIndex(store.sliderIndex.int))
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
