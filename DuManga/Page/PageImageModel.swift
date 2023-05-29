// Created on 14/4/21.

import Foundation
import Combine
import Logging

class PageImageModel: ObservableObject {
    private static let logger = Logger(label: "PageImageModel")

    @Published var progress: Double = 0

    @Published private(set) var reloadPageId = ""

    private var isLoading = false

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private let store =  AppStore.shared

    private var cancellables: Set<AnyCancellable> = []

    init() {
        reloadPageId = store.state.trigger.pageId

        store.state.trigger.$pageId.receive(on: DispatchQueue.main)
            .assign(to: \.reloadPageId, on: self)
            .store(in: &cancellables)
    }

    func load(id: String, compressThreshold: CompressThreshold) {
        guard !isLoading else {
            return
        }

        if store.state.page.loadingProgress[id] != nil {
            store.state.page.loadingProgress[id]!.projectedValue.receive(on: DispatchQueue.main)
                .assign(to: \.progress, on: self)
                .store(in: &cancellables)
        } else {
            isLoading = true
            progress = 0
            _ = try? database.deleteArchiveImage(id)
            service.fetchArchivePage(page: id)
                .validate()
                .downloadProgress { progress in
                    self.progress = progress.fractionCompleted
                }
                .responseData { [self] response in
                    if let data = response.value {
                        if compressThreshold != .never {
                            self.progress = 2
                        }
                        let dataToSave = resizeImage(data: data, threshold: compressThreshold)
                        var pageImage = ArchiveImage(id: id, image: dataToSave, lastUpdate: Date())
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
}
