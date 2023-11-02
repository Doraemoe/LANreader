import ComposableArchitecture
import Logging
import SwiftUI

struct LibraryFeature: Reducer {
    private let logger = Logger(label: "LibraryFeature")

    struct State: Equatable {
        var archiveList = ArchiveListFeature.State()
        var errorMessage = ""
    }

    enum Action: Equatable {
        case loadLibrary
        case search(String, String, String)
        case populateArchives([ArchiveItem], Int)
        case archiveList(ArchiveListFeature.Action)
        case setError(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.userDefaultService) var userDefault

    var body: some ReducerOf<Self> {
        Scope(state: \.archiveList, action: /Action.archiveList) {
            ArchiveListFeature()
        }

        Reduce { state, action in
            switch action {
            case .loadLibrary:
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return .run { send in
                    await send(.search(sortby, "0", order))
                }
            case let .search(sortby, start, order):
                state.archiveList.loading = true
                return .run { send in
                    do {
                        let response = try await service.searchArchive(
                            start: start,
                            sortby: sortby,
                            order: order
                        ).value
                        let archives = response.data.map {
                            $0.toArchiveItem()
                        }
                        await send(.populateArchives(archives, response.recordsFiltered))
                    } catch {
                        logger.error("failed to load library. \(error)")
                        await send(.setError(error.localizedDescription))
                    }
                }
            case let .populateArchives(archives, total):
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: item)
                }
                state.archiveList.archives.append(contentsOf: gridFeatureState)
                state.archiveList.total = total
                state.archiveList.loading = false
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            case let .archiveList(.appendArchives(start)):
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return .run { send in
                    await send(.search(sortby, start, order))
                }
            default:
                return .none
            }
        }
    }

}

struct LibraryListV2: View {
    let store: StoreOf<LibraryFeature>

    struct ViewState: Equatable {
        let archives: IdentifiedArrayOf<GridFeature.State>
        let errorMessage: String

        init(state: LibraryFeature.State) {
            self.archives = state.archiveList.archives
            self.errorMessage = state.errorMessage
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                .archiveList($0)
            }))
            .onAppear {
                if viewStore.archives.isEmpty {
                    viewStore.send(.loadLibrary)
                }
            }
            .navigationTitle("library")
            .navigationBarTitleDisplayMode(.inline)
        }

    }
}
