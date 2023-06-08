import Foundation
import Combine
import Logging

class SearchViewModel: ObservableObject {
    private static let logger = Logger(label: "SearchViewModel")

    @Published var keyword = ""
    @Published private(set) var isLoading = false
    @Published private(set) var archiveItems = [String: ArchiveItem]()
    @Published private(set) var isError = false
    @Published private(set) var errorMessage = ""

    let store = AppStore.shared
    let service = LANraragiService.shared
    let database = AppDatabase.shared

    private var result = [String]()
    private var cancellable: Set<AnyCancellable> = []

    init() {
        archiveItems = store.state.archive.archiveItems

        store.state.archive.$archiveItems.receive(on: DispatchQueue.main)
                .assign(to: \.archiveItems, on: self)
                .store(in: &cancellable)
    }

    var suggestedTag: [String] {
        let lastToken = keyword.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        guard !lastToken.isEmpty else { return [] }
        let result = try? database.searchTag(keyword: lastToken)
        return result?.map { item in
            item.tag
        } ?? []
    }

    func completeString(tag: String) -> String {
        let validKeyword = keyword.split(separator: " ").dropLast(1).joined(separator: " ")
        return "\(validKeyword) \(tag)$,"

    }

    func reset() {
        isLoading = false
        isError = false
        errorMessage = ""
    }

    func searchResult() -> [ArchiveItem] {
        return archiveItems.values.filter { item in
            result.contains(item.id)
        }
    }

    @MainActor
    func search() async {
        guard !isLoading else {
            return
        }
        result = .init()
        isLoading = true
        do {
            let response = try await service.searchArchive(filter: keyword).value

            result = response.data.map { item in
                item.arcid
            }
        } catch {
            SearchViewModel.logger.error("failed to search archive. keyword=\(keyword) \(error)")
            isError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
