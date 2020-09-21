//
// Created on 9/9/20.
//

import Foundation

struct SettingState {
    var url: String
    var apiKey: String
    var errorCode: ErrorCode?
    var savedSuccess: Bool

    init() {
        // server
        self.url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
        self.errorCode = nil
        self.savedSuccess = false
    }
}
