//
// Created on 10/9/20.
//

import Foundation
import Combine

class SettingsService {
    // server
    func saveLanrargiServer(url: String, apiKey: String) -> AnyPublisher<Bool, Never> {
        UserDefaults.standard.set(url, forKey: SettingsKey.lanraragiUrl)
        UserDefaults.standard.set(apiKey, forKey: SettingsKey.lanraragiApiKey)
        return Just(true).eraseToAnyPublisher()
    }
}
