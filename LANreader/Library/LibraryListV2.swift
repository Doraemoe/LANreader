import ComposableArchitecture
import Logging
import SwiftUI

@Reducer struct LibraryFeature {
    private let logger = Logger(label: "LibraryFeature")

    struct State: Equatable {
        @BindingState var archiveList = ArchiveListFeature.State(filter: SearchFilter(category: nil, filter: nil))
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
    let store: StoreOf<LibraryFeature>

    struct ViewState: Equatable {
        @BindingViewState var selectMode: EditMode

        init(state: BindingViewStore<LibraryFeature.State>) {
            self._selectMode = state.$archiveList.selectMode
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: \.archiveList))
            .navigationTitle("library")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, viewStore.$selectMode)
            .toolbar(viewStore.selectMode == .active ? .hidden : .visible, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewStore.selectMode == .active ? "done" : "select") {
                        viewStore.send(.toggleSelectMode)
                    }
                }
            }
            .toolbar {
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
