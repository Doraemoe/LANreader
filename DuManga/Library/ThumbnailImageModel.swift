// Created 17/10/20

import SwiftUI
import Combine
import Foundation
import Logging

class ThumbnailImageModel: ObservableObject {
    private static let imageProcessingQueue = DispatchQueue(label: "image-processing")
    private static let logger = Logger(label: "ThumbnailImageModel")

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
            if let archive = try database.readArchiveThumbnail(id) {
                image = Image(uiImage: UIImage(data: archive.thumbnail)!)
                return
            }
        } catch {
            // NOOP
        }

        service.retrieveArchiveThumbnailData(id: id)
                .subscribe(on: Self.imageProcessingQueue)
                .handleEvents(receiveSubscription: { [weak self] _ in self?.onStart() },
                        receiveCompletion: { [weak self] _ in self?.onFinish() },
                        receiveCancel: { [weak self] in self?.onFinish() })
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        ThumbnailImageModel.logger.error("Error \(error)")
                    case .finished:
                        return
                    }
                }, receiveValue: {
                    self.image = Image(uiImage: UIImage(data: $0)!)
                    var archive = ArchiveThumbnail(id: id, thumbnail: $0, lastUpdate: Date())
                    do {
                        try self.database.saveArchiveThumbnail(&archive)
                    } catch {
                        ThumbnailImageModel.logger.error("db error. id=\(id) \(error)")
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
