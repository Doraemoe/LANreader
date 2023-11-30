// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer struct SettingsFeature {
    struct State: Equatable {
        var path = StackState<Path.State>()

        var view = ViewSettingsFeature.State()
        var database = DatabaseSettingsFeature.State()
    }
    enum Action: Equatable {
        case path(StackAction<Path.State, Path.Action>)

        case view(ViewSettingsFeature.Action)
        case database(DatabaseSettingsFeature.Action)
    }

    var body: some ReducerOf<Self> {

        Scope(state: \.view, action: \.view) {
            ViewSettingsFeature()
        }

        Scope(state: \.database, action: \.database) {
            DatabaseSettingsFeature()
        }

        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            Path()
        }
    }

    @Reducer struct Path {
        enum State: Equatable {
            case lanraragiSettings(LANraragiConfigFeature.State)
            case upload(UploadFeature.State)
            case log(LogFeature.State)
        }
        enum Action: Equatable {
            case lanraragiSettings(LANraragiConfigFeature.Action)
            case upload(UploadFeature.Action)
            case log(LogFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: \.lanraragiSettings, action: \.lanraragiSettings) {
                LANraragiConfigFeature()
            }
            Scope(state: \.upload, action: \.upload) {
                UploadFeature()
            }
            Scope(state: \.log, action: \.log) {
                LogFeature()
            }
        }
    }
}

struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStackStore(
            self.store.scope(state: \.path, action: \.path)
        ) {
            Form {
                Section(header: Text("settings.read")) {
                    ReadSettings()
                }
                Section(header: Text("settings.host")) {
                    ServerSettings()
                }
                Section(header: Text("settings.view")) {
                    ViewSettings(store: self.store.scope(state: \.view, action: \.view))
                }
                Section(header: Text("settings.database")) {
                    DatabaseSettings(store: self.store.scope(state: \.database, action: \.database))
                }
                Section(header: Text("settings.debug")) {
                    NavigationLink("settings.debug.log", state: SettingsFeature.Path.State.log(.init()))
               .padding()
                    // swiftlint:disable force_cast
                    let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
                    let build = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
                    // swiftlint:enable force_cast
                    LabeledContent("version", value: "\(version)-\(build)")
                        .padding()
                }
            }
            .navigationBarTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
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
    }
}
