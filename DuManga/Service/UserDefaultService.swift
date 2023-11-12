//
// Created on 10/9/20.
//

import Foundation
import Dependencies

class UserDefaultService {
    private static var _shared: UserDefaultService?

    // server
    func saveLanrargiServer(url: String, apiKey: String) {
        UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)
    }

    var searchSort: String {
        return UserDefaults.standard.string(forKey: SettingsKey.searchSort) ?? "date_added"
    }

    var showOriginal: Bool {
        return UserDefaults.standard.bool(forKey: SettingsKey.showOriginal) ?? false
    }

    public static var shared: UserDefaultService {
        if _shared == nil {
            _shared = UserDefaultService()
        }
        return _shared!
    }
}

extension UserDefaultService: DependencyKey {
    static let liveValue = UserDefaultService.shared
}

extension DependencyValues {
    var userDefaultService: UserDefaultService {
        get { self[UserDefaultService.self] }
        set { self[UserDefaultService.self] = newValue }
    }
}
