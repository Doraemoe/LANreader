//
// Created on 10/9/20.
//

import Foundation

class SettingsService {
    private static var _shared: SettingsService?

    // server
    func saveLanrargiServer(url: String, apiKey: String) {
        UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)
    }

    public static var shared: SettingsService {
        if _shared == nil {
            _shared = SettingsService()
        }
        return _shared!
    }
}
