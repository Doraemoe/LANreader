import ComposableArchitecture
import Logging
import SwiftUI

@Reducer struct CategoryArchiveListFeature {
    private let logger = Logger(label: "CategoryArchiveListFeature")

    struct State: Equatable {
        var id: String
        var name: String

        var archiveList = ArchiveListFeature.State()
        var errorMessage = ""
    }

    enum Action: Equatable {
        case loadCategory
        case refreshCategory
        case populateArchives([ArchiveItem], Int, Bool)
        case archiveList(ArchiveListFeature.Action)
        case setError(String)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.userDefaultService) var userDefault

    var body: some ReducerOf<Self> {
        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce {state, action in
            switch action {
            case .loadCategory:
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return self.search(
                    state: &state, categoryId: state.id, sortby: sortby, start: "0", order: order, append: false
                )
            case .refreshCategory:
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return self.search(
                    state: &state, categoryId: state.id, sortby: sortby, start: "0", order: order, append: false
                )
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
                return self.search(
                    state: &state, categoryId: state.id, sortby: sortby, start: start, order: order, append: true
                )
            default:
                return .none
            }
        }
    }

    // swiftlint:disable function_parameter_count
    func search(
        state: inout State, categoryId: String, sortby: String, start: String, order: String, append: Bool
    ) -> Effect<Action> {
        guard state.archiveList.loading == false else {
            return .none
        }
        state.archiveList.loading = true
        return .run { send in
            do {
                let response = try await service.searchArchive(
                    category: categoryId,
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
    // swiftlint:enable function_parameter_count

}

struct CategoryArchiveListV2: View {
    let store: StoreOf<CategoryArchiveListFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                .archiveList($0)
            }))
            .onAppear {
                viewStore.send(.loadCategory)
            }
            .refreshable {
                await viewStore.send(.refreshCategory).finish()
            }
                .toolbar(.hidden, for: .tabBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(viewStore.name)
        }
    }
}
