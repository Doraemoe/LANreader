import Foundation

class HistoryListModel: ObservableObject {

    @Published var archives = [ArchiveItem]()
    @Published var errorMessage = ""

    private let database = AppDatabase.shared

    func reset() {
        errorMessage = ""
    }

    func loadHistory() {
        do {
            let history = try database.readAllArchiveHistory()
            let archives = history.map { item in
                item.archive.toArchiveItem()
            }
            self.archives = archives
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
