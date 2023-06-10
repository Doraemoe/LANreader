//
// Created on 6/10/20.
//

import Foundation
import Combine
import Logging

class CategoryArchiveListModel: ObservableObject {
    private static let logger = Logger(label: "CategoryArchiveListModel")

    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var isLoading = false
    @Published private(set) var isError = false
    @Published private(set) var errorMessage = ""

    private let service = LANraragiService.shared
    private let store = AppStore.shared

    private var result = [String]()
    private var cancellable: Set<AnyCancellable> = []

    init() {
        connectStore()
    }

    func connectStore() {
        archiveItems = store.state.archive.archiveItems

        store.state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)
    }

    func disconnectStore() {
        cancellable.forEach { $0.cancel() }
    }

    func reset() {
        isLoading = false
        isError = false
        errorMessage = ""
    }

    func loadCategory() -> [ArchiveItem] {
        return archiveItems.values.filter { item in
            result.contains(item.id)
        }
    }

    func loadStaticCategory(ids: [String]) {
        result = ids
    }

    @MainActor
    func loadDynamicCategory(keyword: String) async {
        guard !isLoading else {
            return
        }
        if !result.isEmpty {
            return
        }
        isLoading = true
        do {
            let response = try await service.searchArchive(filter: keyword).value
            result = response.data.map { item in
                item.arcid
            }
        } catch {
            CategoryArchiveListModel.logger.error("failed to search archive. keyword=\(keyword) \(error)")
            isError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
