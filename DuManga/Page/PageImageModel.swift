// Created on 14/4/21.

import SwiftUI
import Combine
import Logging

class PageImageModel: ObservableObject {
    private static let logger = Logger(label: "PageImageModel")

    @Published var imageData: Data?
    @Published var progress: Double = 0

    private var isLoading = false

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private var cancellable: Set<AnyCancellable> = []

    func checkImageData(id: String) -> Data? {
        if let data = imageData {
            return data
        } else if let data = try? database.readArchiveImage(id) {
            return data.image
        }
        return nil
    }

    func load(id: String) {
        guard !isLoading else {
            return
        }

        isLoading = true
        service.fetchArchivePage(page: id)
                .downloadProgress { progress in
                    self.progress = progress.fractionCompleted
                }
                .responseData { [self] response in
                    if let data = response.value {
                        imageData = data
                        var pageImage = ArchiveImage(id: id, image: imageData!, lastUpdate: Date())
                        do {
                            try database.saveArchiveImage(&pageImage)
                        } catch {
                            PageImageModel.logger.error("failed to save page to db. pageId=\(id) \(error)")
                        }
                    } else if let error = response.error {
                        PageImageModel.logger.error("failed to load image. \(error)")
                    }
                    isLoading = false
                }
    }
}
