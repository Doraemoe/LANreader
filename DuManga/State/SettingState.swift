//
// Created on 9/9/20.
//

import Foundation

struct SettingState {
    @PublishedState var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    @PublishedState var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
    @PublishedState var savedSuccess = false
    @PublishedState var errorCode: ErrorCode?
}
