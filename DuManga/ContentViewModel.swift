//
// Created on 7/10/20.
//

import SwiftUI
import Combine
import Logging

class ContentViewModel: ObservableObject {
    private static let logger = Logger(label: "ContentViewModel")
    @Published var tabName: String = "library"

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    func queueUrlDownload(url: URL) async -> (Bool, String) {
        if var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comp.scheme = "https"
            if let urlToDownload = try? comp.asURL().absoluteString {
                do {
                    let response = try await service.queueUrlDownload(downloadUrl: urlToDownload).value
                    if response.success != 1 {
                        return (false, NSLocalizedString("error.download.queue", comment: "error"))
                    } else {
                        var downloadJob = DownloadJob(
                                id: response.job,
                                url: response.url,
                                title: "",
                                isActive: true,
                                isSuccess: false,
                                isError: false,
                                message: "",
                                lastUpdate: Date()
                        )
                        try? database.saveDownloadJob(&downloadJob)
                        return (true, NSLocalizedString("download.queue.success", comment: "success"))
                    }
                } catch {
                    ContentViewModel.logger.error("failed to queue url to download. url=\(urlToDownload) \(error)")
                    return (false, NSLocalizedString("error.download.queue", comment: "error"))
                }
            } else {
                return (false, NSLocalizedString("error.download.url", comment: "error"))
            }
        } else {
            return (false, NSLocalizedString("error.download.url", comment: "error"))
        }
    }
}
