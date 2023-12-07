import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct RandomFeature {
    private let logger = Logger(label: "RandomFeature")

    struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var showLoading: Bool = false
        var errorMessage = ""

        var archivesToDisplay: IdentifiedArrayOf<GridFeature.State> {
            if UserDefaults.standard.bool(forKey: SettingsKey.hideRead) {
                let result = archives.filter {
                    $0.archive.pagecount != $0.archive.progress
                }
                return IdentifiedArray(uniqueElements: result)
            } else {
                return archives
            }
        }
    }

    enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case load(Bool)
        case populateArchives([ArchiveItem])
        case setErrorMessage(String)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .load(showLoading):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = showLoading
                return .run { send in
                    let response = try await service.randomArchives().value
                    let archives = response.data.map {
                        $0.toArchiveItem()
                    }
                    await send(.populateArchives(archives))
                } catch: { error, send in
                    logger.error("failed to get random archives \(error)")
                    await send(.setErrorMessage(error.localizedDescription))
                }
            case let .populateArchives(archives):
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: item)
                }
                state.archives = IdentifiedArray(uniqueElements: gridFeatureState)
                state.loading = false
                state.showLoading = false
                return .none
            case let .setErrorMessage(message):
                state.loading = false
                state.showLoading = false
                state.errorMessage = message
                return .none
            default:
                return .none
            }
        }
        .forEach(\.archives, action: \.grid) {
            GridFeature()
        }
    }
}

struct RandomView: View {
    let store: StoreOf<RandomFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    struct GridViewState: Equatable {
        let archive: ArchiveItem
        init(state: GridFeature.State) {
            self.archive = state.archive
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEachStore(
                        self.store.scope(state: \.archivesToDisplay, action: \.grid)
                    ) { gridStore in
                        WithViewStore(gridStore, observe: GridViewState.init) { gridViewStore in
                            grid(viewStore: viewStore, gridStore: gridStore, gridViewStore: gridViewStore)
                        }
                    }
                }
                .padding(.horizontal)
                if viewStore.showLoading {
                    ProgressView("loading")
                }
            }
            .onAppear {
                if viewStore.archives.isEmpty {
                    viewStore.send(.load(true))
                }
            }
            .refreshable {
                await viewStore.send(.load(false)).finish()
            }
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: String(localized: "error"),
                        subtitle: viewStore.errorMessage,
                        style: .danger
                    )
                    banner.show()
                    viewStore.send(.setErrorMessage(""))
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("random")
        }
    }

    private func contextMenu(gridViewStore: ViewStore<RandomView.GridViewState, GridFeature.Action>) -> some View {
        Group {
            NavigationLink(
                state: AppFeature.Path.State.reader(
                    ArchiveReaderFeature.State.init(
                        archive: gridViewStore.archive,
                        fromStart: true
                    )
                )
            ) {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            Button(action: {
                gridViewStore.send(.load(true))
            }, label: {
                Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
            })
        }
    }

    private func grid(
        viewStore: ViewStoreOf<RandomFeature>,
        gridStore: StoreOf<GridFeature>,
        gridViewStore: ViewStore<RandomView.GridViewState, GridFeature.Action>
    ) -> some View {
        NavigationLink(
            state: AppFeature.Path.State.reader(
                ArchiveReaderFeature.State.init(
                    archive: gridViewStore.archive
                )
            )
        ) {
            ArchiveGridV2(store: gridStore)
                .contextMenu {
                    contextMenu(gridViewStore: gridViewStore)
                }
        }
    }
}
