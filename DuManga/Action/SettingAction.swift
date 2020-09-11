//
// Created on 9/9/20.
//

import Foundation

enum SettingAction {
    case saveLanraragiConfigToStore(url: String, apiKey: String)
    case saveLanraragiConfigToUserDefaults(url: String, apiKey: String)
    case verifyAndSaveLanraragiConfig(url: String, apiKey: String)
    case error(errorCode: ErrorCode)
    case resetState
}
