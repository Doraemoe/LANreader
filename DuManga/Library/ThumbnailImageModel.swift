// Created 17/10/20

import SwiftUI
import Combine
import Foundation
import Logging

class ThumbnailImageModel: ObservableObject {
    private static let logger = Logger(label: "ThumbnailImageModel")

    @Published var imageData: Data?
    @Published var progress: Double = 0

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    private var isLoading = false

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
        } catch {
            ThumbnailImageModel.logger.error("failed to fetch thumbnail. \(error)")
        }
        isLoading = false
    }
}
