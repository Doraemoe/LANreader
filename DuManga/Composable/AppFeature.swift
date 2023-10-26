import ComposableArchitecture

struct AppFeature: Reducer {
    
    struct State: Equatable {
        var archive = ArchiveFeature.State()
        var trigger = TriggerFeature.State()
    }
    
    enum Action: Equatable {
        case archive(ArchiveFeature.Action)
        case trigger(TriggerFeature.Action)
    }
    
    var body: some Reducer<State, Action> {
        Scope(state: \.archive, action: /Action.archive) {
            ArchiveFeature()
        }
        Scope(state: \.trigger, action: /Action.trigger) {
            TriggerFeature()
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
