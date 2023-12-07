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

    func setSearchSort(searchSort: String) {
        UserDefaults.standard.set(searchSort, forKey: SettingsKey.searchSort)
    }

    var searchSortOrder: String {
        return UserDefaults.standard.string(forKey: SettingsKey.searchSortOrder) ?? "asc"
    }

    var showOriginal: Bool {
        return UserDefaults.standard.bool(forKey: SettingsKey.showOriginal)
    }

    var passcode: String {
        return UserDefaults.standard.string(forKey: SettingsKey.passcode) ?? ""
    }

    func savePasscode(passcode: String) {
        UserDefaults.standard.set(passcode, forKey: SettingsKey.passcode)
    }

    var serverProgres: Bool {
        return UserDefaults.standard.bool(forKey: SettingsKey.serverProgress)
    }

    func setServerProgress(isServerProgress: Bool) {
        UserDefaults.standard.set(isServerProgress, forKey: SettingsKey.serverProgress)
    }

    var hideRead: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.hideRead)
    }

    var lastTagRefresh: Double {
        UserDefaults.standard.double(forKey: SettingsKey.lastTagRefresh)
    }

    func setLastTagRefresh(timeOverride: TimeInterval? = nil) {
        if let override = timeOverride {
            UserDefaults.standard.set(override, forKey: SettingsKey.lastTagRefresh)
        } else {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SettingsKey.lastTagRefresh)
        }
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
    static let testValue = UserDefaultService.shared
}

extension DependencyValues {
    var userDefaultService: UserDefaultService {
        get { self[UserDefaultService.self] }
        set { self[UserDefaultService.self] = newValue }
    }
}
