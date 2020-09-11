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
                // tap
        case let .setting(action: .saveTapLeftControlToUserDefaults(control)):
            return service.saveTapLeftControl(control: control)
                    .map { _ in
                        AppAction.setting(action: .setTapLeftControlToStore(control: control))
                    }
                    .eraseToAnyPublisher()
        case let .setting(action: .saveTapMiddleControlToUserDefaults(control)):
            return service.saveTapMiddleControl(control: control)
                    .map { _ in
                        AppAction.setting(action: .setTapMiddleControlToStore(control: control))
                    }
                    .eraseToAnyPublisher()
        case let .setting(action: .saveTapRightControlToUserDefaults(control)):
            return service.saveTapRightControl(control: control)
                    .map { _ in
                        AppAction.setting(action: .setTapRightControlToStore(control: control))
                    }
                    .eraseToAnyPublisher()
                // swipe
        case let .setting(action: .saveSwipeLeftControlToUserDefaults(control)):
            return service.saveSwipeLeftControl(control: control)
                    .map { _ in
                        AppAction.setting(action: .setSwipeLeftControlToStore(control: control))
                    }
                    .eraseToAnyPublisher()
        case let .setting(action: .saveSwipeRightControlToUserDefaults(control)):
            return service.saveSwipeRightControl(control: control)
                    .map { _ in
                        AppAction.setting(action: .setSwipeRightControlToStore(control: control))
                    }
                    .eraseToAnyPublisher()
                // split
        case let .setting(action: .saveSplitPageToUserDefaults(split)):
            return service.saveSplitPage(split: split)
                    .map { _ in
                        AppAction.setting(action: .setSplitPageToStore(split: split))
                    }
                    .eraseToAnyPublisher()
        case let .setting(action: .saveSplitPagePriorityLeftToUserDefaults(priorityLeft)):
            return service.saveSplitPagePriorityLeft(priorityLeft: priorityLeft)
                    .map { _ in
                        AppAction.setting(action: .setSplitPagePriorityLeftToStore(priorityLeft: priorityLeft))
                    }
                    .eraseToAnyPublisher()
        default:
            break
        }
        return Empty().eraseToAnyPublisher()
    }
}
