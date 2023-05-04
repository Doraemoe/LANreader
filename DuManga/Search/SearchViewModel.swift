import Foundation
import Combine
import Logging

class SearchViewModel: ObservableObject {
    private static let logger = Logger(label: "SearchViewModel")

    @Published var isLoading = false
    @Published var keyword = ""
    @Published var result = [ArchiveItem]()
    @Published var isError = false
    @Published var errorMessage = ""

    let service = LANraragiService.shared

    func reset() {
        isLoading = false
        isError = false
        errorMessage = ""
    }

    @MainActor
    func search() async {
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
            SearchViewModel.logger.error("failed to search archive. keyword=\(keyword) \(error)")
            isError = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

}
