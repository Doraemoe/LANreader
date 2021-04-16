// Created on 14/4/21.

import SwiftUI
import Combine
import Logging

class PageImageModel: ObservableObject {
    private static let imageProcessingQueue = DispatchQueue(label: "image-processing")
    private static let logger = Logger(label: "PageImageModel")

    @Published var image = Image("placeholder")

    private(set) var isLoading = false

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private var cancellable: Set<AnyCancellable> = []

    deinit {
        unload()
    }

    func load(id: String) {
        guard !isLoading else {
            return
        }
        guard image == Image("placeholder") else {
            return
        }
        do {
            if let archiveImage = try database.readArchiveImage(id) {
                image = Image(uiImage: UIImage(data: archiveImage.image)!)
                return
            }
        } catch {
            // NOOP
        }

        service.fetchArchivePageData(page: id)
                .subscribe(on: Self.imageProcessingQueue)
                .handleEvents(receiveSubscription: { [weak self] _ in self?.onStart() },
                        receiveCompletion: { [weak self] _ in self?.onFinish() },
                        receiveCancel: { [weak self] in self?.onFinish() })
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        PageImageModel.logger.error("Error \(error)")
                    case .finished:
                        return
                    }
                }, receiveValue: {
                    self.image = Image(uiImage: UIImage(data: $0)!)
                    var archiveImage = ArchiveImage(id: id, image: $0, lastUpdate: Date())
                    do {
                        try self.database.saveArchiveImage(&archiveImage)
                    } catch {
                        PageImageModel.logger.error("db error. pageId=\(id) \(error)")
                    }
                })
                .store(in: &cancellable)
    }

    func unload() {
        onFinish()
        cancellable.forEach({ $0.cancel() })
    }

    private func onStart() {
        isLoading = true
    }

    private func onFinish() {
        isLoading = false
    }
}
