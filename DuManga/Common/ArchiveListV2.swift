import ComposableArchitecture
import OrderedCollections
import SwiftUI
import Combine

@Reducer struct ArchiveListFeature {
    struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var total: Int = 0
    }

    enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case subscribeThumbnailTrigger
        case subscribeProgressTrigger
        case refreshThumbnail(String)
        case updateArchiveProgress(String, Int)
        case appendArchives(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.refreshTrigger) var refreshTrigger

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .subscribeThumbnailTrigger:
                return .run { send in
                    for await archiveId in refreshTrigger.thumbnail.values {
                        await send(.refreshThumbnail(archiveId))
                    }
                }
            case .subscribeProgressTrigger:
                return .run { send in
                    for await (archiveId, progress) in refreshTrigger.progress.values {
                        await send(.updateArchiveProgress(archiveId, progress))
                    }
                }
            case let .refreshThumbnail(archiveId):
                if state.archives.contains(where: { $0.id == archiveId }) {
                    return .send(.grid(.element(id: archiveId, action: .load(true))))
                } else {
                    return .none
                }
            case let .updateArchiveProgress(archiveId, progress):
                state.archives[id: archiveId]?.archive.progress = progress
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

struct ArchiveListV2: View {
    let store: StoreOf<ArchiveListFeature>

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
                        self.store.scope(state: \.archives, action: { .grid($0)})
                    ) { gridStore in
                        WithViewStore(gridStore, observe: GridViewState.init) { gridViewStore in
                            NavigationLink(
                                state: AppFeature.Path.State.reader(
                                    ArchiveReaderFeature.State.init(
                                        archive: gridViewStore.archive
                                    )
                                )
                            ) {
                                ArchiveGridV2(store: gridStore)
                                    .onAppear {
                                        if gridViewStore.archive.id == viewStore.archives.last?.archive.id &&
                                            viewStore.archives.count < viewStore.total {
                                            viewStore.send(.appendArchives(String(viewStore.archives.count)))
                                        }
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            gridViewStore.send(.load(true))
                                        }, label: {
                                            Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
                                        })
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                if viewStore.loading {
                    ProgressView("loading")
                }
            }
            .onAppear {
                viewStore.send(.subscribeThumbnailTrigger)
                viewStore.send(.subscribeProgressTrigger)
            }
        }
    }
}

struct RefreshTrigger {
    var thumbnail = PassthroughSubject<String, Never>()
    var progress = PassthroughSubject<(String, Int), Never>()
}

private enum RefreshTriggerKey: DependencyKey {
    static let liveValue = RefreshTrigger()
    static let testValue = RefreshTrigger()
}

extension DependencyValues {
    var refreshTrigger: RefreshTrigger {
        get { self[RefreshTriggerKey.self] }
        set { self[RefreshTriggerKey.self] = newValue }
    }
}
