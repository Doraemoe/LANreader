//
// Created on 10/9/20.
//

import Foundation
import Combine

func lanraragiMiddleware(service: LANraragiService) -> Middleware<AppState, AppAction> {
    { state, action in
        switch action {
        case let .setting(action: .verifyAndSaveLanraragiConfig(url, apiKey)):
            return service.verifyClient(url: url, apiKey: apiKey)
                    .map { _ in
                        AppAction.setting(action: .saveLanraragiConfigToUserDefaults(url: url, apiKey: apiKey))
                    }
                    .replaceError(with: AppAction.setting(action: .error(errorCode: ErrorCode.lanraragiServerError)))
                    .eraseToAnyPublisher()
        default:
            break
        }
        return Empty().eraseToAnyPublisher()
    }
}
