import ComposableArchitecture
import Logging
import SwiftUI

@Reducer public struct CategoryArchiveListFeature {
    private let logger = Logger(label: "CategoryArchiveListFeature")

    @ObservableState
    public struct State: Equatable {
        @Shared(.inMemory(SettingsKey.tabBarHidden)) var tabBarHidden = false

        var id: String
        var name: String

        var archiveList: ArchiveListFeature.State
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case archiveList(ArchiveListFeature.Action)
        case toggleSelectMode
//        case setTabBarHidden(Bool)
    }

    public var body: some ReducerOf<Self> {
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
//            case let .setTabBarHidden(hidden):
//                state.$tabBarHidden.withLock {
//                    $0 = hidden
//                }
//                return .none
            }
        }
    }
}

struct CategoryArchiveListV2: View {
    @Bindable var store: StoreOf<CategoryArchiveListFeature>

    var body: some View {
        ArchiveListV2(store: store.scope(state: \.archiveList, action: \.archiveList))
            .toolbar(.hidden, for: .tabBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(store.name)
            .environment(\.editMode, $store.archiveList.selectMode)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.archiveList.selectMode == .active ? "done" : "select") {
                        store.send(.toggleSelectMode)
                    }
                }
            }
    }
}
