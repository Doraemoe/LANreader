import ComposableArchitecture

struct AppFeature: Reducer {

    struct State: Equatable {
        @BindingState var tabName = "library"

        var archive = ArchiveFeature.State()
        var trigger = TriggerFeature.State()

        var library = LibraryFeature.State()
        var search = SearchFeature.State()
        var settings = SettingsFeature.State()
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)

        case archive(ArchiveFeature.Action)
        case trigger(TriggerFeature.Action)

        case library(LibraryFeature.Action)
        case search(SearchFeature.Action)
        case settings(SettingsFeature.Action)

    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { _, action in
            switch action {
            default:
                return .none
            }
        }

        Scope(state: \.archive, action: /Action.archive) {
            ArchiveFeature()
        }
        Scope(state: \.trigger, action: /Action.trigger) {
            TriggerFeature()
        }

        Scope(state: \.library, action: /Action.library) {
            LibraryFeature()
        }
        Scope(state: \.search, action: /Action.search) {
            SearchFeature()
        }
        Scope(state: \.settings, action: /Action.settings) {
            SettingsFeature()
        }

    }
}

extension AppFeature {
    private static var _shared: StoreOf<AppFeature>?

    public static var shared: StoreOf<AppFeature> {
        if _shared == nil {
            _shared = Store(initialState: AppFeature.State(), reducer: {
                AppFeature()
            })
        }
        return _shared!
    }
}
