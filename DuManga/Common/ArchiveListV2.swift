import ComposableArchitecture
import OrderedCollections
import SwiftUI
import Combine

struct ArchiveListFeature: Reducer {
    struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var total: Int = 0
    }

    enum Action: Equatable {
        case grid(id: GridFeature.State.ID, action: GridFeature.Action)
        case appendArchives(String)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .appendArchives:
                return .none
            default:
                return .none
            }
        }
        .forEach(\.archives, action: /Action.grid(id:action:)) {
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
                        self.store.scope(state: \.archives, action: { .grid(id: $0, action: $1)})
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
                                            gridViewStore.send(.load(gridViewStore.archive.id, true))
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
        }
    }
}

private enum RefreshTriggerKey: DependencyKey {
    static let liveValue = PassthroughSubject<String, Never>()
}

extension DependencyValues {
  var refreshTrigger: PassthroughSubject<String, Never> {
    get { self[RefreshTriggerKey.self] }
    set { self[RefreshTriggerKey.self] = newValue }
  }
}
