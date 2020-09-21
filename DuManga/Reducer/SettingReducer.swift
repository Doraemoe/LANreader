//
// Created on 9/9/20.
//

import Foundation
import Combine

func settingReducer(state: inout SettingState, action: SettingAction) {
    switch action {
            // server
    case let .saveLanraragiConfigToStore(url, apiKey):
        state.url = url
        state.apiKey = apiKey
        state.savedSuccess = true
    case let .error(errorCode):
        state.errorCode = errorCode
    case .resetState:
        state.savedSuccess = false
        state.errorCode = nil
    default:
        break
    }
}
