import ComposableArchitecture
import SwiftUI
import Logging
import NotificationBannerSwift

@Reducer struct RandomFeature {
    private let logger = Logger(label: "RandomFeature")

    @ObservableState
    struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []

        @Shared(.archive) var archiveItems: IdentifiedArrayOf<ArchiveItem> = []

        var loading: Bool = false
        var showLoading: Bool = false
        var errorMessage = ""
    }

    enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case load(Bool)
        case populateArchives([ArchiveItem])
        case setErrorMessage(String)
        case refreshDisplayArchives
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
                archives.forEach { item in
                    state.archiveItems.updateOrAppend(item)
                }
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: state.$archiveItems[id: item.id]!)
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
            case .refreshDisplayArchives:
                let filteredGridFeatureState = state.archives.filter { gridState in
                    state.archiveItems[id: gridState.archive.id] != nil
                }
                state.archives = filteredGridFeatureState
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

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(
                    store.scope(state: \.archives, action: \.grid),
                    id: \.state.id
                ) { gridStore in
                    grid(gridStore: gridStore)
                }
            }
            .padding(.horizontal)
            if store.showLoading {
                ProgressView("loading")
            }
        }
        .onAppear {
            if store.archives.isEmpty {
                store.send(.load(true))
            } else {
                store.send(.refreshDisplayArchives)
            }
        }
        .refreshable {
            await store.send(.load(false)).finish()
        }
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                banner.show()
                store.send(.setErrorMessage(""))
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("random")
    }

    private func contextMenu(gridStore: StoreOf<GridFeature>) -> some View {
        Group {
            NavigationLink(
                state: AppFeature.Path.State.reader(
                    ArchiveReaderFeature.State.init(
                        archive: gridStore.$archive,
                        fromStart: true
                    )
                )
            ) {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            Button(action: {
                gridStore.send(.load(true))
            }, label: {
                Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
            })
        }
    }

    private func grid(
        gridStore: StoreOf<GridFeature>
    ) -> some View {
        NavigationLink(
            state: AppFeature.Path.State.reader(
                ArchiveReaderFeature.State.init(
                    archive: gridStore.$archive
                )
            )
        ) {
            ArchiveGridV2(store: gridStore)
                .contextMenu {
                    contextMenu(gridStore: gridStore)
                }
        }
    }
}
