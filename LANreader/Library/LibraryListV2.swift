import ComposableArchitecture
import Logging
import SwiftUI

@Reducer struct LibraryFeature {
    private let logger = Logger(label: "LibraryFeature")

    @ObservableState
    struct State: Equatable {
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            currentTab: .library
        )
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case archiveList(ArchiveListFeature.Action)
        case toggleSelectMode
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.userDefaultService) var userDefault

    var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce { state, action in
            switch action {
            case .toggleSelectMode:
                if state.archiveList.selectMode == .inactive {
                    state.archiveList.selectMode = .active
                } else {
                    state.archiveList.selectMode = .inactive
                }
                return .none
            case .archiveList:
                return .none
            case .binding:
                return .none
            }
        }
    }
}

struct LibraryListV2: View {
    @Bindable var store: StoreOf<LibraryFeature>

    var body: some View {
        ArchiveListV2(store: store.scope(state: \.archiveList, action: \.archiveList))
            .navigationTitle("library")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $store.archiveList.selectMode)
            .toolbar(store.archiveList.selectMode == .active ? .hidden : .visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.archiveList.selectMode == .active ? "done" : "select") {
                        store.send(.toggleSelectMode)
                    }
                }
            }
            .toolbar {
                if store.archiveList.selectMode != .active {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(
                            state: AppFeature.Path.State.random(
                                RandomFeature.State()
                            )
                        ) {
                            Label("shuffle", systemImage: "shuffle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
    }
}
