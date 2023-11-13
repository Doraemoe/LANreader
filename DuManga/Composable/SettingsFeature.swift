import ComposableArchitecture
import Foundation

struct SettingsFeature: Reducer {
    struct State: Equatable {
        var path = StackState<Path.State>()

        var database = DatabaseSettingsFeature.State()
    }
    enum Action: Equatable {
        case path(StackAction<Path.State, Path.Action>)

        case database(DatabaseSettingsFeature.Action)
    }

    var body: some ReducerOf<Self> {

        Scope(state: \.database, action: /Action.database) {
            DatabaseSettingsFeature()
        }

        Reduce { _, action in
            switch action {
            default:
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
