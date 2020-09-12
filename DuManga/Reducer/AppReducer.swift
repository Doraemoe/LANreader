//
// Created on 9/9/20.
//

import Foundation
import Combine

typealias Reducer<State, Action> = (inout State, Action) -> Void

func appReducer(state: inout AppState, action: AppAction) {
    switch action {
    case let .setting(action):
        settingReducer(state: &state.setting, action: action)
    case let .category(action):
        categoryReducer(state: &state.category, action: action)
    }
}
