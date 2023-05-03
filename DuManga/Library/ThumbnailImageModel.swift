// Created 17/10/20

import SwiftUI
import Combine
import Foundation
import Logging

class ThumbnailImageModel: ObservableObject {
    private static let logger = Logger(label: "ThumbnailImageModel")

    @Published var imageData: Data?

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

    @MainActor
    func load(id: String, fromServer: Bool) async {
        guard !isLoading else {
            return
        }

        if !fromServer, let archive = try? database.readArchiveThumbnail(id) {
            imageData = archive.thumbnail
            return
        }

        isLoading = true
        do {
            imageData = try await service.retrieveArchiveThumbnail(id: id).serializingData().value
            var thumbnail = ArchiveThumbnail(id: id, thumbnail: imageData!, lastUpdate: Date())
            do {
                try self.database.saveArchiveThumbnail(&thumbnail)
            } catch {
                ThumbnailImageModel.logger.warning("failed to save thumbnail to db. id=\(id) \(error)")
            }
        } catch {
            ThumbnailImageModel.logger.error("failed to fetch thumbnail. \(error)")
        }
        isLoading = false
    }
}
