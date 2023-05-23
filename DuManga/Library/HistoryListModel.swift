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
            if archives.count > 100 {
                self.archives = Array(archives[..<100])
                let extraIds = archives[100...].map { item in
                    item.id
                }
                _ = try? database.deleteHistories(extraIds)
            } else {
                self.archives = archives
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
