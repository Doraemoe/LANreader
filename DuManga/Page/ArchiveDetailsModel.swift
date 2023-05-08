//
// Created on 3/10/20.
//

import Foundation
import Logging

class ArchiveDetailsModel: ObservableObject {
    private static let logger = Logger(label: "ArchiveDetailsModel")

    @Published var title = ""
    @Published var tags = ""

    @Published var loading = false
    @Published var isError = false
    @Published var errorMessage = ""

    private let service = LANraragiService.shared
    private let database = AppDatabase.shared

    func load(title: String, tags: String) {
        self.title = title
        self.tags = tags
    }

    func reset() {
        isError = false
        errorMessage = ""
    }

    @MainActor
    func updateArchive(archive: ArchiveItem) async -> Bool {
        loading = true

        do {
            _ = try await service.updateArchive(archive: archive).value
            do {
                var archiveDto = archive.toArchive()
                try database.saveArchive(&archiveDto)
            } catch {
                ArchiveDetailsModel.logger.error("failed to save archive. id=\(archive.id) \(error)")
            }
            loading = false
            return true
        } catch {
            ArchiveDetailsModel.logger.error("failed to update archive. id=\(archive.id) \(error)")
            loading = false
            isError = true
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func deleteArchive(id: String) async -> Bool {
        loading = true

        do {
            let response = try await service.deleteArchive(id: id).value
            if response.success == 1 {
                do {
                    let success = try database.deleteArchive(id)
                    if !success {
                        ArchiveDetailsModel.logger.error("failed to delete archive from db. id=\(id)")
                    }
                } catch {
                    ArchiveDetailsModel.logger.error("failed to delete archive from db. id=\(id) \(error)")
                }
                loading = false
                return true
            } else {
                isError = true
                errorMessage = "failed to delete archives, please retry."
                loading = false
                return false
            }
        } catch {
            ArchiveDetailsModel.logger.error("failed to delete archive. id=\(id) \(error)")
            loading = false
            isError = true
            errorMessage = error.localizedDescription
            return false
        }
    }
}
