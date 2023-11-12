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

        var reversePages: IdentifiedArrayOf<PageFeature.State> {
            IdentifiedArray(uniqueElements: pages.reversed())
        }
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case page(id: PageFeature.State.ID, action: PageFeature.Action)
        case extractArchive
        case loadProgress
        case finishExtracting([String])
        case toggleControlUi(Bool?)
        case preload(Int)
        case setIndex(Int)
        case setSliderIndex(Double)
        case updateProgress
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
            case .loadProgress:
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
                return .run(priority: .utility) { [totalPage = state.pages.count] send in
                    if index - 1 > 0 {
                        await send(.page(id: index - 1, action: .load(false)))
                    }
                    if index + 1 < totalPage {
                        await send(.page(id: index + 1, action: .load(false)))
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
                return .run { [state] _ in
                    do {
                        _ = try await service.updateArchiveReadProgress(id: state.archive.id, progress: progress).value
                        if progress == state.archive.pagecount {
                            _ = try await service.clearNewFlag(id: state.archive.id).value
                        }
                        refreshTrigger.progress.send((state.archive.id, progress))
                    } catch {
                        logger.error("failed to update archive progress. id=\(state.archive.id) \(error)")
                    }
                }
                .debounce(id: CancelId.updateProgress, for: .seconds(0.5), scheduler: DispatchQueue.main)
            case .setThumbnail:
                state.settingThumbnail = true
                let index = (state.index ?? 0) + 1
                return .run { [id = state.archive.id] send in
                    do {
                        _ = try await service.updateArchiveThumbnail(id: id, page: index).value
                        let successMessage = NSLocalizedString(
                            "archive.thumbnail.set", comment: "set thumbnail success"
                        )
                        await send(.setSuccess(successMessage))
                        refreshTrigger.thumbnail.send(id)
                    } catch {
                        logger.error("Failed to set current page as thumbnail. id=\(id) \(error)")
                        await send(.setError(error.localizedDescription))
                    }
                    await send(.finishThumbnailLoading)
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
    @AppStorage(SettingsKey.tapLeftKey) var tapLeft: String = PageControl.next.rawValue
    @AppStorage(SettingsKey.tapMiddleKey) var tapMiddle: String = PageControl.navigation.rawValue
    @AppStorage(SettingsKey.tapRightKey) var tapRight: String = PageControl.previous.rawValue
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
                                self.store.scope(
                                    state: readDirection == ReadDirection.rightLeft.rawValue ? \.reversePages : \.pages,
                                    action: { .page(id: $0, action: $1) }
                                )
                            ) { pageStore in
                                PageImageV2(store: pageStore)
                                    .frame(width: geometry.size.width)
                                    .draggableAndZoomable(contentSize: geometry.size)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .onTapGesture { location in
                        if location.x < geometry.size.width / 3 {
                            viewStore.send(.tapAction(tapLeft))
                        } else if location.x > geometry.size.width / 3 * 2 {
                            viewStore.send(.tapAction(tapRight))
                        } else {
                            viewStore.send(.tapAction(tapMiddle))
                        }
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
                } else {
                    viewStore.send(.loadProgress)
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
    private func bottomToolbar(viewStore: ViewStoreOf<ArchiveReaderFeature>) -> some View {
        let flip = readDirection == ReadDirection.rightLeft.rawValue ? -1 : 1
        return VStack {
            Spacer()
            Grid {
                GridRow {
                    Button(action: {
                        viewStore.send(.page(id: viewStore.index ?? 0, action: .load(true)))
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    })
                    Text(String(format: "%d/%d",
                                viewStore.sliderIndex.int + 1,
                                viewStore.pages.count))
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
