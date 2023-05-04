//
// Created on 6/10/20.
//

import Foundation
import Combine
import Logging

class CategoryArchiveListModel: ObservableObject {
    private static let logger = Logger(label: "CategoryArchiveListModel")

    @Published var keyword = ""
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var isLoading = false
    @Published private(set) var result = [ArchiveItem]()
    @Published private(set) var isError = false
    @Published private(set) var errorMessage = ""

    private let service = LANraragiService.shared

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState) {
        archiveItems = state.archive.archiveItems
        state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }

    func reset() {
        isLoading = false
        isError = false
        errorMessage = ""
    }

    func loadStaticCategory(ids: [String]) {
        result = Array(archiveItems.filter { key, _ in
                    ids.contains(key)
                }
                .values)
    }

    @MainActor
    func loadDynamicCategory() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        result = .init()
        do {
            let response = try await service.searchArchive(filter: keyword).value

            result = response.data.map { item in
                item.toArchiveItem()
            }
        } catch {
            CategoryArchiveListModel.logger.error("failed to search archive. keyword=\(keyword) \(error)")
            isError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
