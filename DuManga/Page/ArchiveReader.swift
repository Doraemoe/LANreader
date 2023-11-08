import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

struct ArchiveReaderFeature: Reducer {
    private let logger = Logger(label: "ArchiveReaderFeature")

    struct State: Equatable {
        @BindingState var index: Int?
        @BindingState var sliderIndex: Double = 0
        var pages: IdentifiedArrayOf<PageFeature.State> = []
        var archive: ArchiveItem
        var extracting = false
        var controlUiHidden = false
        var settingThumbnail = false
        var errorMessage = ""
        var successMessage = ""
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case page(id: PageFeature.State.ID, action: PageFeature.Action)
        case extractArchive
        case finishExtracting([String])
        case toggleControlUi(Bool?)
        case preload(Int)
        case setIndex(Int)
        case setSliderIndex(Double)
        case setThumbnail(String)
        case finishThumbnailLoading
        case setError(String)
        case setSuccess(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.refreshTrigger) var refreshTrigger

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .extractArchive:
                state.extracting = true
                let id = state.archive.id
                return .run { send in
                    do {
                        let extractResponse = try await service.extractArchive(id: id).value
                        if extractResponse.pages.isEmpty {
                            logger.error("server returned empty pages. id=\(id)")
                            let errorMessage = NSLocalizedString("error.page.empty", comment: "empty content")
                            await send(.setError(errorMessage))
                        }
                        await send(.finishExtracting(extractResponse.pages))
                    } catch {
                        logger.error("failed to extract archive page. id=\(id) \(error)")
                        await send(.setError(error.localizedDescription))
                        await send(.finishExtracting([]))
                    }
                }
            case let .finishExtracting(pages):
                let pageState = pages.enumerated().map { (index, page) in
                    let normalizedPage = String(page.dropFirst(2))
                    return PageFeature.State(id: index, pageId: normalizedPage)
                }
                state.pages.append(contentsOf: pageState)
                state.extracting = false
                let progress = state.archive.progress > 0 ? state.archive.progress - 1 : 0
                state.index = progress
                state.sliderIndex = Double(progress)
                state.controlUiHidden = true
                return .none
            case let .toggleControlUi(show):
                if let shouldShow = show {
                    state.controlUiHidden = shouldShow
                } else {
                    state.controlUiHidden = !state.controlUiHidden
                }
                return .none
            case let .preload(index):
                let previousPageId = index - 1 > 0 ? state.pages[index - 1].pageId : ""
                let nextPageId = index + 1 < state.pages.count ? state.pages[index + 1].pageId : ""
                return .run(priority: .utility) { send in
                    if !previousPageId.isEmpty {
                        await send(.page(id: index - 1, action: .load(previousPageId, false)))
                    }
                    if !nextPageId.isEmpty {
                        await send(.page(id: index + 1, action: .load(nextPageId, false)))
                    }
                }
            case let .setIndex(index):
                state.index = index
                return .none
            case let .setSliderIndex(index):
                state.sliderIndex = index
                return .none
            case let .setThumbnail(id):
                state.settingThumbnail = true
                let index = (state.index ?? 0) + 1
                return .run { send in
                    do {
                        _ = try await service.updateArchiveThumbnail(id: id, page: index).value
                        let successMessage = NSLocalizedString(
                            "archive.thumbnail.set", comment: "set thumbnail success"
                        )
                        await send(.setSuccess(successMessage))
                        refreshTrigger.send(id)
                    } catch {
                        logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
                        await send(.setError(error.localizedDescription))
                    }
                    await send(.finishThumbnailLoading)
                }
            case .finishThumbnailLoading:
                state.settingThumbnail = false
                return .none
            case let .setSuccess(message):
                state.successMessage = message
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            default:
                return .none
            }
        }
        .forEach(\.pages, action: /Action.page(id:action:)) {
            PageFeature()
        }
    }
}

struct ArchiveReader: View {
    @AppStorage(SettingsKey.readDirection) var readDirection: String = ReadDirection.leftRight.rawValue

    let store: StoreOf<ArchiveReaderFeature>

    init(store: StoreOf<ArchiveReaderFeature>) {
        self.store = store
    }

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEachStore(
                                self.store.scope(state: \.pages, action: { .page(id: $0, action: $1) })
                            ) { pageStore in
                                PageImageV2(store: pageStore)
                                    .frame(width: geometry.size.width)
                                    .draggableAndZoomable(contentSize: geometry.size)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .onTapGesture {
                        viewStore.send(.toggleControlUi(nil))
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: viewStore.$index)
                    if !viewStore.controlUiHidden {
                        bottomToolbar(viewStore: viewStore)
                    }
                    if viewStore.extracting {
                        LoadingView(geometry: geometry)
                    }
                }

            }
            .toolbar(viewStore.controlUiHidden ? .hidden : .visible, for: .navigationBar)
            .navigationBarTitle(viewStore.archive.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                if viewStore.pages.isEmpty {
                    viewStore.send(.extractArchive)
                }
            }
            .onChange(of: viewStore.index) { _, newValue in
                if let index = newValue {
                    viewStore.send(.preload(index))
                    viewStore.send(.setSliderIndex(Double(index)))
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
    private func bottomToolbar(viewStore: ViewStoreOf<ArchiveReaderFeature>) -> some View {
        let flip = readDirection == ReadDirection.rightLeft.rawValue ? -1 : 1
        return VStack {
            Spacer()
            Grid {
                GridRow {
                    Button(action: {
                        viewStore.send(.page(id: viewStore.index ?? 0, action: .load(viewStore.archive.id, true)))
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    })
                    Text(String(format: "%d/%d",
                                viewStore.sliderIndex.int + 1,
                                viewStore.pages.count))
                    .bold()
                    Button(action: {
                        Task {
                            viewStore.send(.setThumbnail(viewStore.archive.id))
                        }
                    }, label: {
                        Image(systemName: "photo.artframe")
                    })
                    .disabled(viewStore.settingThumbnail)
                }
                GridRow {
                    Slider(
                        value: viewStore.$sliderIndex,
                        in: 0...Double(viewStore.pages.count < 1 ? 1 : viewStore.pages.count - 1),
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
