// Created 1/9/20
import ComposableArchitecture
import SwiftUI

@Reducer struct ViewSettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
    }

    enum Action {
        case destination(PresentationAction<Destination.Action>)

        case showLockScreen(Bool)
    }

    @Dependency(\.userDefaultService) var userDefault

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
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
    @AppStorage(SettingsKey.searchSortCustom) var searchSortCustom: String = ""
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false
    @AppStorage(SettingsKey.enablePasscode) var enablePasscode: Bool = false
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    @Bindable var store: StoreOf<ViewSettingsFeature>

    var body: some View {
        List {
            LabeledContent {
                TextField("settings.archive.list.order.custom.title", text: $searchSortCustom)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } label: {
                Text("settings.archive.list.order.custom.title")
            }
            .padding()
            Toggle(isOn: self.$hideRead, label: {
                Text("settings.view.hideRead")
            })
            .padding()
            Toggle(isOn: self.$blurInterfaceWhenInactive, label: {
                Text("settings.view.blur.inactive")
            })
            .padding()
            Toggle(isOn: self.$enablePasscode, label: {
                Text("settings.view.passcode")
            })
            .padding()
        }
        .onAppear {
            // Correct invalid passcode status
            if enablePasscode && storedPasscode.isEmpty {
                enablePasscode = false
            } else if !enablePasscode && !storedPasscode.isEmpty {
                enablePasscode = true
            }
        }
        .onChange(of: enablePasscode) { oldPasscode, newEnable in
            if oldPasscode && storedPasscode.isEmpty {
                // heppens when correct invalid passcode status
            } else if !oldPasscode && !storedPasscode.isEmpty {
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
