//
// Created on 9/9/20.
//

import Foundation

typealias Reducer<State, Action> = (inout State, Action) -> Void

func appReducer(state: inout AppState, action: AppAction) {
    switch action {
    case let .archive(action):
        archiveReducer(state: &state.archive, action: action)
    case let .category(action):
        categoryReducer(state: &state.category, action: action)
    case let .page(action):
        pageReducer(state: &state.page, action: action)
    case let .trigger(action):
        triggerReducer(state: &state.trigger, action: action)
    default:
        break
    }
}
