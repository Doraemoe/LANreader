// Created 29/8/20
import ComposableArchitecture
import SwiftUI

struct SettingsFeature: Reducer {
    struct State: Equatable {
        var path = StackState<Path.State>()
    }
    enum Action: Equatable {
        case path(StackAction<Path.State, Path.Action>)
    }

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
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
            case lanraragiSettings(LANraragiConfigFeature.State = .init())
            case upload(UploadFeature.State = .init())
            case log(LogFeature.State = .init())
        }
        enum Action: Equatable {
            case lanraragiSettings(LANraragiConfigFeature.Action)
            case upload(UploadFeature.Action)
            case log(LogFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: /State.lanraragiSettings, action: /Action.lanraragiSettings) {
                LANraragiConfigFeature()
            }
            Scope(state: /State.upload, action: /Action.upload) {
                UploadFeature()
            }
            Scope(state: /State.log, action: /Action.log) {
                LogFeature()
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
                    ServerSettings()
                }
                Section(header: Text("settings.view")) {
                    ViewSettings()
                }
                Section(header: Text("settings.database")) {
                    DatabaseSettings(store: Store(initialState: DatabaseSettingsFeature.State(), reducer: {
                        DatabaseSettingsFeature()
                    }))
                }
                Section(header: Text("settings.debug")) {
                    NavigationLink("settings.debug.log", state: SettingsFeature.Path.State.log())
               .padding()
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
            case .upload:
                CaseLet(
                    /SettingsFeature.Path.State.upload,
                     action: SettingsFeature.Path.Action.upload,
                     then: UploadView.init(store:)
                )
            case .log:
                CaseLet(
                    /SettingsFeature.Path.State.log,
                     action: SettingsFeature.Path.Action.log,
                     then: LogView.init(store:)
                )
            }
        }
        .navigationBarTitle("settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
