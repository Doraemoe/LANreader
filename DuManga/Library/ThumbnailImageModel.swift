//Created 17/10/20

import SwiftUI
import Combine
import Foundation
import Logging

class ThumbnailImageModel: ObservableObject {
    private static let imageProcessingQueue = DispatchQueue(label: "image-processing")
    private static let logger = Logger(label: "ThumbnailImageModel")

    @Published var image = Image("placeholder")

    private(set) var isLoading = false

    private let id: String
    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private var cancellable: Set<AnyCancellable> = []

    init(id: String) {
        self.id = id
    }

    deinit {
        unload()
    }

    func load() {
        guard !isLoading else { return }
        guard image == Image("placeholder") else { return }
        do {
            if let archive = try database.readArchive(id) {
                self.image = Image(uiImage: UIImage(data: archive.thumbnail)!)
                return
            }
        } catch {
            self.image = Image("placeholder")
        }

        service.retrieveArchiveThumbnailData(id: id)
            .subscribe(on: Self.imageProcessingQueue)
            .handleEvents(receiveSubscription: {[weak self] _ in self?.onStart()},
                          receiveCompletion: {[weak self] _ in self?.onFinish() },
                          receiveCancel: {[weak self] in self?.onFinish() })
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
                var archive = Archive(id: self.id, thumbnail: $0, lastUpdate: Date())
                do {
                    try self.database.saveArchive(&archive)
                } catch {
                    ThumbnailImageModel.logger.error("db error. id=\(self.id) \(error)")
                }
            })
            .store(in: &cancellable)
    }

    func unload() {
        self.onFinish()
        cancellable.forEach({ $0.cancel() })
    }

    private func onStart() {
        isLoading = true
    }

    private func onFinish() {
        isLoading = false
    }
}
