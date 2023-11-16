import ComposableArchitecture
import Logging
import SwiftUI

@Reducer struct LibraryFeature {
    private let logger = Logger(label: "LibraryFeature")

    struct State: Equatable {
        var archiveList = ArchiveListFeature.State(filter: SearchFilter(category: nil, filter: nil))
    }

    enum Action: Equatable {
        case archiveList(ArchiveListFeature.Action)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.userDefaultService) var userDefault

    var body: some ReducerOf<Self> {
        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce { _, action in
            switch action {
            case .archiveList:
                return .none
            }
        }
    }
}

struct LibraryListV2: View {
    let store: StoreOf<LibraryFeature>

    struct ViewState: Equatable {
        let archives: IdentifiedArrayOf<GridFeature.State>

        init(state: LibraryFeature.State) {
            self.archives = state.archiveList.archives
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { _ in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                .archiveList($0)
            }))
            .navigationTitle("library")
            .navigationBarTitleDisplayMode(.inline)
        }

    }
}
