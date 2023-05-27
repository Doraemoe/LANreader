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

    private var isLoading = false

    private var cancellables: Set<AnyCancellable> = []

    func load(state: AppState) {
        reloadThumbnailId = state.trigger.thumbnailId

        state.trigger.$thumbnailId.receive(on: DispatchQueue.main)
                .assign(to: \.reloadThumbnailId, on: self)
                .store(in: &cancellables)
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
