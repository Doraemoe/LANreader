//
// Created on 9/9/20.
//

import Foundation
import Combine

func settingMiddleware(service: SettingsService) -> Middleware<AppState, AppAction> {
    { state, action in
        switch action {
                // server
        case let .setting(action: .saveLanraragiConfigToUserDefaults(url, apiKey)):
            return service.saveLanrargiServer(url: url, apiKey: apiKey)
                    .map { _ in
                        AppAction.setting(action: .saveLanraragiConfigToStore(url: url, apiKey: apiKey))
                    }
                    .eraseToAnyPublisher()
        default:
            break
        }
        return Empty().eraseToAnyPublisher()
    }
}
