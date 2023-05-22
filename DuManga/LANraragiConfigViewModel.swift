//
// Created on 2/10/20.
//

import Foundation
import Logging

class LANraragiConfigViewModel: ObservableObject {
    private static let logger = Logger(label: "LANraragiConfigViewModel")

    @Published var url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
    @Published var apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
    @Published var isVerifying = false
    @Published var errorMessage = ""

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
            errorMessage = NSLocalizedString("error.host", comment: "host error")
        }
        isVerifying = false
        return false
    }
}
