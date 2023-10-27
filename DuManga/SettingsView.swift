// Created 29/8/20
import ComposableArchitecture
import SwiftUI

struct SettingsFeature: Reducer {
    struct State: Equatable {
        var path = StackState<Path.State>()
    }
    enum Action: Equatable {
        case path(StackAction<Path.State, Path.Action>)
        case goToLANraragiSettings
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .goToLANraragiSettings:
                state.path.append(.lanraragiSettings(.init()))
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: /Action.path) {
            Path()
        }
    }
    
    
    struct Path: Reducer {
        enum State: Equatable {
            case lanraragiSettings(LANraragiConfigFeature.State)
        }
        enum Action: Equatable {
            case lanraragiSettings(LANraragiConfigFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: /State.lanraragiSettings, action: /Action.lanraragiSettings) {
                LANraragiConfigFeature()
            }
        }
    }
}

struct SettingsView: View {
    let store: StoreOf<SettingsFeature>
    
    var body: some View {
        NavigationStackStore(
            self.store.scope(state: \.path, action: { .path($0) })
        ) {
            Form {
                Section(header: Text("settings.read")) {
                    ReadSettings()
                }
                Section(header: Text("settings.host")) {
                    ServerSettings(store: store)
                }
                Section(header: Text("settings.view")) {
                    ViewSettings()
                }
                Section(header: Text("settings.database")) {
                    DatabaseSettings()
                }
                Section(header: Text("settings.debug")) {
                    NavigationLink(
                        destination: LogView(),
                        label: {
                            Text("settings.debug.log")
                        }).padding()
                    // swiftlint:disable force_cast
                    let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
                    let build = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
                    // swiftlint:enable force_cast
                    LabeledContent("version", value: "\(version)-\(build)")
                        .padding()
                }
            }
        } destination: { state in
            // A view for each case of the Path.State enum
            switch state {
            case .lanraragiSettings:
                CaseLet(
                    /SettingsFeature.Path.State.lanraragiSettings,
                     action: SettingsFeature.Path.Action.lanraragiSettings,
                     then: LANraragiConfigView.init(store:)
                )
            }
        }
        .navigationBarTitle("settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
