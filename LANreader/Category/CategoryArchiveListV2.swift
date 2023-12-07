import ComposableArchitecture
import Logging
import SwiftUI

@Reducer struct CategoryArchiveListFeature {
    private let logger = Logger(label: "CategoryArchiveListFeature")

    struct State: Equatable {
        var id: String
        var name: String

        @BindingState var archiveList: ArchiveListFeature.State
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case archiveList(ArchiveListFeature.Action)
        case toggleSelectMode
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        Reduce {state, action in
            switch action {
            case .toggleSelectMode:
                if state.archiveList.selectMode == .inactive {
                    state.archiveList.selectMode = .active
                } else {
                    state.archiveList.selectMode = .inactive
                }
                return .none
            case .binding:
                return .none
            case .archiveList:
                return .none
            }
        }
    }
}

struct CategoryArchiveListV2: View {
    let store: StoreOf<CategoryArchiveListFeature>

    struct ViewState: Equatable {
        @BindingViewState var selectMode: EditMode
        let name: String

        init(state: BindingViewStore<CategoryArchiveListFeature.State>) {
            self._selectMode = state.$archiveList.selectMode
            self.name = state.name
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: \.archiveList))
                .toolbar(.hidden, for: .tabBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(viewStore.name)
                .environment(\.editMode, viewStore.$selectMode)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(viewStore.selectMode == .active ? "done" : "select") {
                            viewStore.send(.toggleSelectMode)
                        }
                    }
                }
        }
    }
}
