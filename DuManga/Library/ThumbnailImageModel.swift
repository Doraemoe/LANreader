// Created 17/10/20

import SwiftUI
import Combine
import Foundation
import Logging

class ThumbnailImageModel: ObservableObject {
    private static let logger = Logger(label: "ThumbnailImageModel")

    @Published private(set) var reloadThumbnailId = ""

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private let store = AppStore.shared

    private var isLoading = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        connectStore()
    }

    func connectStore() {
        reloadThumbnailId = store.state.trigger.thumbnailId

        store.state.trigger.$thumbnailId.receive(on: DispatchQueue.main)
                .assign(to: \.reloadThumbnailId, on: self)
                .store(in: &cancellables)
    }

    func disconnectStore() {
        cancellables.forEach { $0.cancel() }
    }

    func load(id: String) async {
        guard !isLoading else {
            return
        }

        isLoading = true
        _ = try? database.deleteArchiveThumbnail(id)
        do {
            let imageData = try await service.retrieveArchiveThumbnail(id: id).serializingData().value
            var thumbnail = ArchiveThumbnail(id: id, thumbnail: imageData, lastUpdate: Date())
            do {
                try database.saveArchiveThumbnail(&thumbnail)
            } catch {
                ThumbnailImageModel.logger.warning("failed to save thumbnail to db. id=\(id) \(error)")
            }
        } catch {
            ThumbnailImageModel.logger.error("failed to fetch thumbnail. \(error)")
        }
        isLoading = false
    }
}
