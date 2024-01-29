// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer struct SettingsFeature {
    @ObservableState
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
        @ObservableState
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
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            Form {
                Section(
                    header: Text("settings.read"),
                    footer: Text("settings.read.fallback.explain")
                ) {
                    ReadSettings()
                }
                Section(header: Text("settings.host")) {
                    ServerSettings()
                }
                Section(
                    header: Text("settings.view"),
                    footer: Text("settings.archive.list.order.custom.explain")
                ) {
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
        } destination: { store in
            switch store.state {
            case .lanraragiSettings:
                if let store = store.scope(state: \.lanraragiSettings, action: \.lanraragiSettings) {
                    LANraragiConfigView(store: store)
                }
            case .upload:
                if let store = store.scope(state: \.upload, action: \.upload) {
                    UploadView(store: store)
                }
            case .log:
                if let store = store.scope(state: \.log, action: \.log) {
                    LogView(store: store)
                }
            }
        }
    }
}
