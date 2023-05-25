// Created on 14/4/21.

import SwiftUI
import Combine
import Logging

class PageImageModel: ObservableObject {
    private static let logger = Logger(label: "PageImageModel")

    @Published var progress: Double = 0

    @Published private(set) var reloadPageId = ""

    private var isLoading = false

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    private var cancellables: Set<AnyCancellable> = []

    func load(state: AppState) {
        reloadPageId = state.trigger.pageId

        state.trigger.$pageId.receive(on: DispatchQueue.main)
                .assign(to: \.reloadPageId, on: self)
                .store(in: &cancellables)
    }

    func load(id: String) {
        guard !isLoading else {
            return
        }

        isLoading = true
        _ = try? database.deleteArchiveImage(id)
        progress = 0
        service.fetchArchivePage(page: id)
                .downloadProgress { progress in
                    self.progress = progress.fractionCompleted
                }
                .responseData { [self] response in
                    if let data = response.value {
                        var pageImage = ArchiveImage(id: id, image: data, lastUpdate: Date())
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
