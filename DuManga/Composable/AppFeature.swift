import ComposableArchitecture

struct AppFeature: Reducer {

    struct State: Equatable {
        @PresentationState var destination: Destination.State?

        @BindingState var tabName = "library"

        var archive = ArchiveFeature.State()
        var trigger = TriggerFeature.State()

        var library = LibraryFeature.State()
        var search = SearchFeature.State()
        var settings = SettingsFeature.State()
    }

    enum Action: Equatable, BindableAction {
        case destination(PresentationAction<Destination.Action>)

        case binding(BindingAction<State>)

        case archive(ArchiveFeature.Action)
        case trigger(TriggerFeature.Action)

        case library(LibraryFeature.Action)
        case search(SearchFeature.Action)
        case settings(SettingsFeature.Action)

        case showLogin

    }

    var body: some Reducer<State, Action> {
        BindingReducer()

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

        Reduce { state, action in
            switch action {
            case .showLogin:
                state.destination = .login(LANraragiConfigFeature.State())
                return .none
            default:
                return .none
            }
        }
        .ifLet(\.$destination, action: /Action.destination) {
          Destination()
        }
    }

    struct Path: Reducer {
        enum State: Equatable {
            case reader(ArchiveReaderFeature.State)
        }
        enum Action: Equatable {
            case reader(ArchiveReaderFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: /State.reader, action: /Action.reader) {
                ArchiveReaderFeature()
            }
        }
    }

    public struct Destination: Reducer {
      public enum State: Equatable {
        case login(LANraragiConfigFeature.State)
      }

        public enum Action: Equatable {
        case login(LANraragiConfigFeature.Action)
      }

      public var body: some Reducer<State, Action> {
        Scope(state: /State.login, action: /Action.login) {
            LANraragiConfigFeature()
        }
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
