// Created 29/8/20
import ComposableArchitecture
import SwiftUI

@Reducer struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()

        var read = ReadSettingsFeature.State()
        var view = ViewSettingsFeature.State()
        var database = DatabaseSettingsFeature.State()
    }
    enum Action {
        case path(StackAction<Path.State, Path.Action>)

        case read(ReadSettingsFeature.Action)
        case view(ViewSettingsFeature.Action)
        case database(DatabaseSettingsFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.read, action: \.read) {
            ReadSettingsFeature()
        }

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
        .forEach(\.path, action: \.path)
    }

    @Reducer(state: .equatable)
    enum Path {
        case lanraragiSettings(LANraragiConfigFeature)
        case upload(UploadFeature)
        case log(LogFeature)
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
                    ReadSettings(store: self.store.scope(state: \.read, action: \.read))
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
            switch store.case {
            case let .lanraragiSettings(store):
                LANraragiConfigView(store: store)
            case let .upload(store):
                UploadView(store: store)
            case let .log(store):
                LogView(store: store)
            }
        }
    }
}
