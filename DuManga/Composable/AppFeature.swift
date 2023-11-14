import ComposableArchitecture

@Reducer struct AppFeature {

    struct State: Equatable {
        @PresentationState var destination: Destination.State?

        @BindingState var tabName = "library"

        var archive = ArchiveFeature.State()
        var trigger = TriggerFeature.State()

        var library = LibraryFeature.State()
        var category = CategoryFeature.State()
        var search = SearchFeature.State()
        var settings = SettingsFeature.State()
    }

    enum Action: Equatable, BindableAction {
        case destination(PresentationAction<Destination.Action>)

        case binding(BindingAction<State>)

        case archive(ArchiveFeature.Action)
        case trigger(TriggerFeature.Action)

        case library(LibraryFeature.Action)
        case category(CategoryFeature.Action)
        case search(SearchFeature.Action)
        case settings(SettingsFeature.Action)

        case showLogin
        case showLockScreen

    }

    var body: some Reducer<State, Action> {
        BindingReducer()

        Scope(state: \.archive, action: \.archive) {
            ArchiveFeature()
        }
        Scope(state: \.trigger, action: \.trigger) {
            TriggerFeature()
        }

        Scope(state: \.library, action: \.library) {
            LibraryFeature()
        }
        Scope(state: \.category, action: \.category) {
            CategoryFeature()
        }
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Reduce { state, action in
            switch action {
            case .showLogin:
                state.destination = .login(LANraragiConfigFeature.State())
                return .none
            case .showLockScreen:
                state.destination = .lockScreen(
                    LockScreenFeature.State(lockState: .normal)
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

    @Reducer struct Path {
        enum State: Equatable {
            case reader(ArchiveReaderFeature.State)
            case categoryArchiveList(CategoryArchiveListFeature.State)
        }
        enum Action: Equatable {
            case reader(ArchiveReaderFeature.Action)
            case categoryArchiveList(CategoryArchiveListFeature.Action)
        }
        var body: some ReducerOf<Self> {
            Scope(state: \.reader, action: \.reader) {
                ArchiveReaderFeature()
            }
            Scope(state: \.categoryArchiveList, action: \.categoryArchiveList) {
                CategoryArchiveListFeature()
            }
        }
    }

    @Reducer public struct Destination {
        public enum State: Equatable {
            case login(LANraragiConfigFeature.State)
            case lockScreen(LockScreenFeature.State)
        }

        public enum Action: Equatable {
            case login(LANraragiConfigFeature.Action)
            case lockScreen(LockScreenFeature.Action)
        }

        public var body: some Reducer<State, Action> {
            Scope(state: \.login, action: \.login) {
                LANraragiConfigFeature()
            }
            Scope(state: \.lockScreen, action: \.lockScreen) {
                LockScreenFeature()
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
