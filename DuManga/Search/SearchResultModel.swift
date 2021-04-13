//
// Created on 6/10/20.
//

import Foundation
import Combine

class SearchResultModel: ObservableObject {
    private static let searchResultSelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())

    @Published private(set) var loading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var errorCode: ErrorCode?

    @Published private(set) var searchResultKeys = [String]()
    @Published private(set) var filteredArchives: [ArchiveItem] = []

    private let service = LANraragiService.shared

    private var cancellable: Set<AnyCancellable> = []

    func load(state: AppState) {
        loading = state.archive.loading
        archiveItems = state.archive.archiveItems
        errorCode = state.archive.errorCode

        state.archive.$loading.receive(on: DispatchQueue.main)
                .assign(to: \.loading, on: self)
                .store(in: &cancellable)

        state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)

        state.archive.$errorCode.receive(on: DispatchQueue.main)
                .assign(to: \.errorCode, on: self)
                .store(in: &cancellable)
    }

    func unload() {
        cancellable.forEach({ $0.cancel() })
    }

    func loadSearchResultKeys(keyword: String,
                              dispatch: @escaping (AppAction) -> Void) {
        service.searchArchiveIndex(filter: keyword)
                .map { (response: ArchiveSearchResponse) in
                    var keys = [String]()
                    response.data.forEach { item in
                        keys.append(item.arcid)
                    }
                    dispatch(.archive(action: .fetchArchiveDynamicCategorySuccess))
                    return keys
                }
                .catch { _ -> Just<[String]> in
                    dispatch(.archive(action: .error(error: .archiveFetchError)))
                    return Just([])
                }
                .receive(on: DispatchQueue.main)
                .assign(to: \.searchResultKeys, on: self)
                .store(in: &cancellable)
    }

    func filterArchives() {
        filteredArchives = SearchResultModel.searchResultSelector.select(
                base: archiveItems,
                filter: searchResultKeys,
                selector: { (base, filter) in
                    let filtered = base.filter { item in
                        filter.contains(item.key)
                    }
                    return Array(filtered.values)
                })
    }
}
