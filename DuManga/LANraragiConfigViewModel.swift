//
// Created on 2/10/20.
//

import Foundation
import Logging

@Observable
class LANraragiConfigViewModel {
    private static let logger = Logger(label: "LANraragiConfigViewModel")

    var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
    var isVerifying = false
    var errorMessage = ""

    private let settingsService = SettingsService.shared
    private let lanraragiService = LANraragiService.shared

    func reset() {
        errorMessage = ""
    }

    @MainActor
    func verifyAndSave() async -> Bool {
        isVerifying = true
        do {
            _ = try await lanraragiService.verifyClient(url: url, apiKey: apiKey).value
            settingsService.saveLanrargiServer(url: url, apiKey: apiKey)
            isVerifying = false
            return true
        } catch {
            LANraragiConfigViewModel.logger.error("failed to verify lanraragi server. \(error)")
            errorMessage = error.localizedDescription
        }
        isVerifying = false
        return false
    }
}
