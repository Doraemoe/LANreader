import Foundation

@Observable
class HistoryListModel {

    var archives = [ArchiveItem]()
    var errorMessage = ""

    private let store = AppStore.shared
    private let database = AppDatabase.shared

    func reset() {
        errorMessage = ""
    }

    func loadHistory() {
        do {
            let archives = try database.readAllArchiveHistory()
                .compactMap { store.state.archive.archiveItems[$0.id] }

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
