// Created 1/9/20
import ComposableArchitecture
import SwiftUI

@Reducer public struct ViewSettingsFeature {
    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?

        @Shared(.appStorage(SettingsKey.searchSortCustom)) var searchSortCustom = ""
        @Shared(.appStorage(SettingsKey.blurInterfaceWhenInactive)) var blurInterfaceWhenInactive = false
        @Shared(.appStorage(SettingsKey.paginateArchiveList)) var paginateArchiveList = false
        @Shared(.appStorage(SettingsKey.passcode)) var storedPasscode = ""
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)

        case destination(PresentationAction<Destination.Action>)

        case showLockScreen(Bool)
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case let .showLockScreen(isEnable):
                guard state.destination == nil else { return .none }
                state.destination = .lockScreen(
                    LockScreenFeature.State(lockState: isEnable ? .new : .remove)
                )
                return .none
            default:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    @Reducer
    public enum Destination {
        case lockScreen(LockScreenFeature)
    }
}

struct ViewSettings: View {
    @Bindable var store: StoreOf<ViewSettingsFeature>

    var body: some View {
        LabeledContent {
            TextField("settings.archive.list.order.custom.title", text: Binding(store.$searchSortCustom))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.archive.list.order.custom.title")
                Text("settings.archive.list.order.custom.explain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        Toggle(isOn: Binding(self.store.$blurInterfaceWhenInactive), label: {
            Text("settings.view.blur.inactive")
        })
        .padding()
        Toggle(isOn: Binding(self.store.$paginateArchiveList), label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.view.paginate")
                Text("settings.view.paginate.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        })
        .padding()
        Toggle(isOn: Binding(
            get: { !store.storedPasscode.isEmpty },
            set: { store.send(.showLockScreen($0)) }
        ), label: {
            Text("settings.view.passcode")
        })
        .padding()
        .fullScreenCover(
            item: $store.scope(\.$destination, action: \.destination).lockScreen
        ) { store in
            LockScreen(store: store)
        }
    }
}

extension ViewSettingsFeature.Destination.State: Equatable {}
