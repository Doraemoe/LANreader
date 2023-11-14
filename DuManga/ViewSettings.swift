// Created 1/9/20
import ComposableArchitecture
import SwiftUI

@Reducer struct ViewSettingsFeature {
    struct State: Equatable {
        @PresentationState var destination: Destination.State?
    }

    enum Action: Equatable {
        case destination(PresentationAction<Destination.Action>)

        case showLockScreen(Bool)
    }

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
        .ifLet(\.$destination, action: \.destination) {
          Destination()
        }
    }

    @Reducer public struct Destination {
      public enum State: Equatable {
        case lockScreen(LockScreenFeature.State)
      }

        public enum Action: Equatable {
        case lockScreen(LockScreenFeature.Action)
      }

      public var body: some Reducer<State, Action> {
        Scope(state: \.lockScreen, action: \.lockScreen) {
            LockScreenFeature()
        }
      }
    }
}

struct ViewSettings: View {
    @AppStorage(SettingsKey.searchSort) var searchSort: String = SearchSort.dateAdded.rawValue
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false
    @AppStorage(SettingsKey.enablePasscode) var enablePasscode: Bool = false
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""

    let store: StoreOf<ViewSettingsFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            List {
                Picker("settings.archive.list.order", selection: self.$searchSort) {
                    Text("settings.archive.list.order.dateAdded").tag(SearchSort.dateAdded.rawValue)
                    Text("settings.archive.list.order.name").tag(SearchSort.name.rawValue)
                }
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
                } else if viewStore.destination == nil {
                    viewStore.send(.showLockScreen(newEnable))
                }
            }
            .fullScreenCover(
                store: self.store.scope(state: \.$destination, action: { .destination($0) }),
                state: \.lockScreen,
                action: { .lockScreen($0) }
            ) { store in
                LockScreen(store: store)
            }
        }
    }
}
