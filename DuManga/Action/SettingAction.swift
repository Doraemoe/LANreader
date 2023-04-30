//
// Created on 9/9/20.
//

import Foundation
import Logging

enum SettingAction {
    case saveLanraragiConfigToStore(url: String, apiKey: String)
    case error(errorCode: ErrorCode)
    case resetState
}

// MARK: thunk actions

private let logger = Logger(label: "SettingAction")
private let settingsService = SettingsService.shared
private let lanraragiService = LANraragiService.shared

func verifyAndSaveLanraragiConfig(url: String, apiKey: String) -> ThunkAction<AppAction, AppState> {
    { dispatch, _ in
        do {
            _ = try await lanraragiService.verifyClient(url: url, apiKey: apiKey).value
            settingsService.saveLanrargiServer(url: url, apiKey: apiKey)
            dispatch(.setting(action: .saveLanraragiConfigToStore(url: url, apiKey: apiKey)))
        } catch {
            logger.error("failed to verify lanraragi server. \(error)")
            dispatch(.setting(action: .error(errorCode: .lanraragiServerError)))
        }
    }
}
