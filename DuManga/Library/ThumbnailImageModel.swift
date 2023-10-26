// Created 17/10/20

import SwiftUI
import Combine
import Foundation
import Logging

@Observable
class ThumbnailImageModel {
    private static let logger = Logger(label: "ThumbnailImageModel")

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared
    private var isLoading = false


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
