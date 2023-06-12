//
// Created on 9/9/20.
//

import Foundation
import Combine

final class Store<State, Action> {
    private(set) var state: State

    private let reducer: Reducer<State, Action>
    private let middlewares: [Middleware<State, Action>]
    private var middlewareCancellables: Set<AnyCancellable> = []

    init(initialState: State,
         reducer: @escaping Reducer<State, Action>,
         middlewares: [Middleware<State, Action>] = []) {
        self.state = initialState
        self.reducer = reducer
        self.middlewares = middlewares
    }

    func dispatch(_ action: ThunkAction<Action, State>) async {
        await action(dispatch, { state })
    }

    func dispatch(_ action: Action) {
        reducer(&state, action)
        // Dispatch all middleware functions
        for middleware in middlewares {
            guard let middleware = middleware(state, action) else {
                break
            }
            middleware
                    .receive(on: DispatchQueue.main)
                    .sink(receiveValue: dispatch)
                    .store(in: &middlewareCancellables)
        }
    }
}

typealias Middleware<State, Action> = (State, Action) -> AnyPublisher<Action, Never>?
typealias AppStore = Store<AppState, AppAction>
typealias Dispatch<Action> = (Action) -> Void
typealias ThunkAction<Action, State> = (Dispatch<Action>, () -> State) async -> Void

extension AppStore {
    private static var _shared: AppStore?

    public static var shared: AppStore {
        if _shared == nil {
            _shared = AppStore(
                initialState: .init(),
                reducer: appReducer,
                middlewares: [tagMiddleware(database: AppDatabase.shared)]
            )
        }
        return _shared!
    }
}
