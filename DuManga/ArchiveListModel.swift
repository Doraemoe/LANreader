import Foundation
import Combine

class ArchiveListModel: ObservableObject {

    @Published private(set) var randomSeed: UInt64 = 0

    @Published var sortedArchives = [ArchiveItem]()

    private var cancellables: Set<AnyCancellable> = []

    func load(state: AppState) {
        state.archive.$randomOrderSeed.receive(on: DispatchQueue.main)
                .assign(to: \.randomSeed, on: self)
                .store(in: &cancellables)
    }

    func unload() {
        cancellables.forEach({ $0.cancel() })
    }

    func processArchives(archives: [ArchiveItem], sortOrder: String, hideRead: Bool) {
        var archivesToProcess = archives
        if sortOrder == ArchiveListOrder.name.rawValue {
            archivesToProcess = archivesToProcess.sorted(by: { $0.name < $1.name })
        } else if sortOrder == ArchiveListOrder.dateAdded.rawValue {
            archivesToProcess = archivesToProcess.sorted { item, item2 in
                let dateAdded1 = item.dateAdded
                let dateAdded2 = item2.dateAdded
                if dateAdded1 != nil && dateAdded2 != nil {
                    return dateAdded1! > dateAdded2!
                } else if dateAdded1 != nil {
                    return true
                } else if dateAdded2 != nil {
                    return false
                } else {
                    return item.name < item2.name
                }
            }
        } else if sortOrder == ArchiveListOrder.random.rawValue {
            var generator = FixedRandomGenerator(seed: randomSeed)
            archivesToProcess = archivesToProcess.shuffled(using: &generator)
        }
        if hideRead {
            archivesToProcess = archivesToProcess.filter { item in
                item.pagecount != item.progress
            }
        }
        var seenId = Set<String>()
        var distinctArchives = [ArchiveItem]()
        archivesToProcess.forEach { item in
            if !seenId.contains(item.id) {
                seenId.insert(item.id)
                distinctArchives.append(item)
            }
        }
        sortedArchives = distinctArchives
    }
}
