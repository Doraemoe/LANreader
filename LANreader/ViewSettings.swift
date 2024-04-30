// Created 1/9/20
import ComposableArchitecture
import SwiftUI

@Reducer struct ViewSettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?

        @Shared(.appStorage(SettingsKey.searchSortCustom)) var searchSortCustom = ""
        @Shared(.appStorage(SettingsKey.blurInterfaceWhenInactive)) var blurInterfaceWhenInactive = false
        @Shared(.appStorage(SettingsKey.enablePasscode)) var enablePasscode = false
        @Shared(.appStorage(SettingsKey.passcode)) var storedPasscode = ""
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)

        case destination(PresentationAction<Destination.Action>)

        case setEnablePasscode(Bool)
        case showLockScreen(Bool)
    }

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case let .setEnablePasscode(isEnable):
                state.enablePasscode = isEnable
                return .none
            case let .showLockScreen(isEnable):
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

    @Reducer(state: .equatable)
    enum Destination {
        case lockScreen(LockScreenFeature)
    }
}

struct ViewSettings: View {
    @Bindable var store: StoreOf<ViewSettingsFeature>

    var body: some View {
        VStack {
            LabeledContent {
                TextField("settings.archive.list.order.custom.title", text: $store.searchSortCustom)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } label: {
                Text("settings.archive.list.order.custom.title")
            }
            .padding()
            Toggle(isOn: self.$store.blurInterfaceWhenInactive, label: {
                Text("settings.view.blur.inactive")
            })
            .padding()
            Toggle(isOn: self.$store.enablePasscode, label: {
                Text("settings.view.passcode")
            })
            .padding()
        }
        .onAppear {
            // Correct invalid passcode status
            if store.enablePasscode && store.storedPasscode.isEmpty {
                store.send(.setEnablePasscode(false))
            } else if !store.enablePasscode && !store.storedPasscode.isEmpty {
                store.send(.setEnablePasscode(true))
            }
        }
        .onChange(of: store.enablePasscode) { oldPasscode, newEnable in
            if oldPasscode && store.storedPasscode.isEmpty {
                // heppens when correct invalid passcode status
            } else if !oldPasscode && !store.storedPasscode.isEmpty {
                // heppens when correct invalid passcode status
            } else if store.destination == nil {
                store.send(.showLockScreen(newEnable))
            }
        }
        .fullScreenCover(
            item: $store.scope(state: \.destination?.lockScreen, action: \.destination.lockScreen)
        ) { store in
            LockScreen(store: store)
        }
    }
}
