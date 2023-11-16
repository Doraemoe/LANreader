import ComposableArchitecture
import Logging
import SwiftUI

@Reducer struct CategoryArchiveListFeature {
    private let logger = Logger(label: "CategoryArchiveListFeature")

    struct State: Equatable {
        var id: String
        var name: String

        var archiveList: ArchiveListFeature.State
    }

    enum Action: Equatable {
        case archiveList(ArchiveListFeature.Action)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.userDefaultService) var userDefault

    var body: some ReducerOf<Self> {
        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce {_, action in
            switch action {
            case .archiveList:
                return .none
            }
        }
    }
}

struct CategoryArchiveListV2: View {
    let store: StoreOf<CategoryArchiveListFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                .archiveList($0)
            }))
                .toolbar(.hidden, for: .tabBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(viewStore.name)
        }
    }
}
