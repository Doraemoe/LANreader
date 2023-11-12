import ComposableArchitecture
import Logging
import SwiftUI

struct LibraryFeature: Reducer {
    private let logger = Logger(label: "LibraryFeature")

    struct State: Equatable {
        var path = StackState<AppFeature.Path.State>()

        var archiveList = ArchiveListFeature.State()
        var errorMessage = ""
    }

    enum Action: Equatable {
        case path(StackAction<AppFeature.Path.State, AppFeature.Path.Action>)

        case loadLibrary
        case refreshLibrary
        case populateArchives([ArchiveItem], Int, Bool)
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
                return self.search(state: &state, sortby: sortby, start: "0", order: order, append: false)
            case .refreshLibrary:
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return self.search(state: &state, sortby: sortby, start: "0", order: order, append: false)
            case let .populateArchives(archives, total, append):
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: item)
                }
                if !append {
                    state.archiveList.archives = .init()
                    state.archiveList.total = 0
                }
                state.archiveList.archives.append(contentsOf: gridFeatureState)
                state.archiveList.total = total
                state.archiveList.loading = false
                return .none
            case let .setError(message):
                state.errorMessage = message
                state.archiveList.loading = false
                return .none
            case let .archiveList(.appendArchives(start)):
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return self.search(state: &state, sortby: sortby, start: start, order: order, append: true)
            default:
                return .none
            }
        }
        .forEach(\.path, action: /Action.path) {
            AppFeature.Path()
        }
    }

    func search(state: inout State, sortby: String, start: String, order: String, append: Bool) -> Effect<Action> {
        guard state.archiveList.loading == false else {
            return .none
        }
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
                await send(.populateArchives(archives, response.recordsFiltered, append))
            } catch {
                logger.error("failed to load library. \(error)")
                await send(.setError(error.localizedDescription))
            }
        }
    }
}

struct LibraryListV2: View {
    @AppStorage(SettingsKey.lanraragiUrl) var lanraragiUrl: String = ""
    @AppStorage(SettingsKey.searchSort) var searchSort: String = SearchSort.dateAdded.rawValue

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
        NavigationStackStore(
            self.store.scope(state: \.path, action: { .path($0) })
        ) {
            WithViewStore(self.store, observe: ViewState.init) { viewStore in
                ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                    .archiveList($0)
                }))
                .refreshable {
                    await viewStore.send(.refreshLibrary).finish()
                }
                .onChange(of: self.searchSort) {
                    viewStore.send(.loadLibrary)
                }
                .onChange(of: lanraragiUrl, {
                    if lanraragiUrl.isEmpty == false {
                        viewStore.send(.loadLibrary)
                    }
                })
                .onAppear {
                    if lanraragiUrl.isEmpty == false &&
                        viewStore.archives.isEmpty {
                        viewStore.send(.loadLibrary)
                    }
                }
                .navigationTitle("library")
                .navigationBarTitleDisplayMode(.inline)
            }
        } destination: { state in
            switch state {
            case .reader:
                CaseLet(
                    /AppFeature.Path.State.reader,
                     action: AppFeature.Path.Action.reader,
                     then: ArchiveReader.init(store:)
                )
            }
        }
    }
}
