// Created on 14/4/21.

import Foundation
import Combine
import Logging

@Observable
class PageImageModel {
    private static let logger = Logger(label: "PageImageModel")

    private(set) var progress: Double = 0
    private(set) var reloadPageId = ""

    private var isLoading = false

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private let store =  AppStore.shared

    private var cancellables: Set<AnyCancellable> = []

    init() {
        connectStore()
    }

    func connectStore() {
        reloadPageId = store.state.trigger.pageId

        store.state.trigger.$pageId.receive(on: DispatchQueue.main)
            .assign(to: \.reloadPageId, on: self)
            .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
    }

    func load(id: String, compressThreshold: CompressThreshold) {
        guard !isLoading else {
            return
        }

        isLoading = true
        progress = 0
        _ = try? database.deleteArchiveImage(id)
        service.fetchArchivePage(page: id)
            .validate()
            .downloadProgress { progress in
                self.progress = progress.fractionCompleted
            }
            .responseURL { [self] response in
                if let url = response.value {
                    if compressThreshold != .never {
                        self.progress = 2
                    }
                    var pageImage = ArchiveImage(id: id, image: url.path, lastUpdate: Date())
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
