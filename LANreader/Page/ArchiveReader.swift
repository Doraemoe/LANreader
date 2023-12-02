import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveReaderFeature {
    private let logger = Logger(label: "ArchiveReaderFeature")

    struct State: Equatable {
        @BindingState var index: Int?
        @BindingState var sliderIndex: Double = 0
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var archive: ArchiveItem
        var fromStart = false
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""

        var reversePages: IdentifiedArrayOf<PageFeature.State> {
            IdentifiedArray(uniqueElements: pages.reversed())
        }

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
    @Dependency(\.userDefaultService) var userDefault
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
                        let errorMessage = NSLocalizedString("error.page.empty", comment: "empty content")
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
                    if userDefault.serverProgres {
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
                    let successMessage = NSLocalizedString(
                        "archive.thumbnail.set", comment: "set thumbnail success"
                    )
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
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
    @AppStorage(SettingsKey.readDirection) var readDirection: String = ReadDirection.leftRight.rawValue
    @AppStorage(SettingsKey.fallbackReader) var fallbackReader: Bool = false

    let store: StoreOf<ArchiveReaderFeature>

    init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
    }

    struct ViewState: Equatable {
        @BindingViewState var index: Int?
        @BindingViewState var sliderIndex: Double
        let archiveId: String
        let archiveName: String
        let errorMessage: String
        let successMessage: String
        let controlUiHidden: Bool
        let fallbackIndex: Int
        let pageCount: Int
        let extracting: Bool
        let archiveExtension: String
        let isPageEmpty: Bool
        let settingThumbnail: Bool

        init(bindingViewStore: BindingViewStore<ArchiveReaderFeature.State>) {
            self._index = bindingViewStore.$index
            self._sliderIndex = bindingViewStore.$sliderIndex
            self.archiveId = bindingViewStore.archive.id
            self.archiveName = bindingViewStore.archive.name
            self.errorMessage = bindingViewStore.errorMessage
            self.successMessage = bindingViewStore.successMessage
            self.controlUiHidden = bindingViewStore.controlUiHidden
            self.fallbackIndex = bindingViewStore.fallbackIndex
            self.pageCount = bindingViewStore.pages.count
            self.extracting = bindingViewStore.extracting
            self.archiveExtension = bindingViewStore.archive.extension
            self.isPageEmpty = bindingViewStore.pages.isEmpty
            self.settingThumbnail = bindingViewStore.settingThumbnail
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            GeometryReader { geometry in
                ZStack {
                    if readDirection == ReadDirection.upDown.rawValue {
                        vReader(viewStore: viewStore, geometry: geometry)
                    } else if fallbackReader {
                        hReaderFallback(viewStore: viewStore, geometry: geometry)
                    } else {
                        hReader(viewStore: viewStore, geometry: geometry)
                    }
                    if !viewStore.controlUiHidden {
                        bottomToolbar(viewStore: viewStore)
                    }
                    if viewStore.extracting {
                        LoadingView(geometry: geometry)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(
                        state: AppFeature.Path.State.details(
                            ArchiveDetailsFeature.State.init(id: viewStore.archiveId)
                        )
                    ) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .toolbar(viewStore.controlUiHidden ? .hidden : .visible, for: .navigationBar)
            .navigationBarTitle(viewStore.archiveName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                if viewStore.isPageEmpty {
                    viewStore.send(.extractArchive)
                } else {
                    viewStore.send(.loadProgress)
                }
                if viewStore.archiveExtension == "rar" || viewStore.archiveExtension == "cbr" {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("warning", comment: "warning"),
                        subtitle: NSLocalizedString("warning.file.type", comment: "rar"),
                        style: .warning
                    )
                    banner.show()
                }
            }
            .onChange(of: viewStore.index) { _, newValue in
                if let index = newValue {
                    viewStore.send(.preload(index))
                    viewStore.send(.setSliderIndex(Double(index)))
                    viewStore.send(.updateProgress)
                }
            }
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error", comment: "error"),
                        subtitle: viewStore.errorMessage,
                        style: .danger
                    )
                    banner.show()
                    viewStore.send(.toggleControlUi(false))
                    viewStore.send(.setError(""))
                }
            }
            .onChange(of: viewStore.successMessage) {
                if !viewStore.successMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("success", comment: "success"),
                        subtitle: viewStore.successMessage,
                        style: .success
                    )
                    banner.show()
                    viewStore.send(.setSuccess(""))
                }
            }
        }
    }

    @MainActor
    private func vReader(
        viewStore: ViewStore<ArchiveReader.ViewState, ArchiveReaderFeature.Action>,
        geometry: GeometryProxy
    ) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEachStore(
                    self.store.scope(
                        state: \.pages,
                        action: \.page
                    )
                ) { pageStore in
                    PageImageV2(store: pageStore, geometrySize: geometry.size)
                        .frame(width: geometry.size.width)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: viewStore.$index)
        .onTapGesture {
            viewStore.send(.tapAction(PageControl.navigation.rawValue))
        }
    }

    @MainActor
    private func hReader(
        viewStore: ViewStore<ArchiveReader.ViewState, ArchiveReaderFeature.Action>,
        geometry: GeometryProxy
    ) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEachStore(
                    self.store.scope(
                        state: readDirection == ReadDirection.rightLeft.rawValue ? \.reversePages : \.pages,
                        action: \.page
                    )
                ) { pageStore in
                    PageImageV2(store: pageStore, geometrySize: geometry.size)
                        .frame(width: geometry.size.width)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: viewStore.$index)
        .onTapGesture { location in
            if location.x < geometry.size.width / 3 {
                viewStore.send(.tapAction(tapLeft))
            } else if location.x > geometry.size.width / 3 * 2 {
                viewStore.send(.tapAction(tapRight))
            } else {
                viewStore.send(.tapAction(tapMiddle))
            }
        }
    }

    @MainActor
    private func hReaderFallback(
        viewStore: ViewStore<ArchiveReader.ViewState, ArchiveReaderFeature.Action>,
        geometry: GeometryProxy
    ) -> some View {
        TabView(selection: viewStore.binding(get: \.fallbackIndex, send: { .setIndex($0) })) {
            ForEachStore(
                self.store.scope(
                    state: readDirection == ReadDirection.rightLeft.rawValue ? \.reversePages : \.pages,
                    action: \.page
                )
            ) { pageStore in
                WithViewStore(pageStore, observe: \.id) { pageViewStore in
                    PageImageV2(store: pageStore, geometrySize: geometry.size)
                        .frame(width: geometry.size.width)
                        .tag(pageViewStore.state)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onTapGesture { location in
            if location.x < geometry.size.width / 3 {
                viewStore.send(.tapAction(tapLeft))
            } else if location.x > geometry.size.width / 3 * 2 {
                viewStore.send(.tapAction(tapRight))
            } else {
                viewStore.send(.tapAction(tapMiddle))
            }
        }
    }

    @MainActor
    private func bottomToolbar(
        viewStore: ViewStore<ArchiveReader.ViewState, ArchiveReaderFeature.Action>
    ) -> some View {
        let flip = readDirection == ReadDirection.rightLeft.rawValue ? -1 : 1
        return VStack {
            Spacer()
            Grid {
                GridRow {
                    Button(action: {
                        viewStore.send(.page(.element(id: viewStore.index ?? 0, action: .load(true))))
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    })
                    Text(String(format: "%d/%d",
                                viewStore.sliderIndex.int + 1,
                                viewStore.pageCount))
                    .bold()
                    Button(action: {
                        Task {
                            viewStore.send(.setThumbnail)
                        }
                    }, label: {
                        Image(systemName: "photo.artframe")
                    })
                    .disabled(viewStore.settingThumbnail)
                }
                GridRow {
                    Slider(
                        value: viewStore.$sliderIndex,
                        in: 0...Double(viewStore.pageCount < 1 ? 1 : viewStore.pageCount - 1),
                        step: 1
                    ) { onSlider in
                        if !onSlider {
                            viewStore.send(.setIndex(viewStore.sliderIndex.int))
                        }
                    }
                    .scaleEffect(CGSize(width: flip, height: 1), anchor: .center)
                    .padding(.horizontal)
                    .gridCellColumns(3)
                }
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
