//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false

    private let archives: [ArchiveItem]

    @EnvironmentObject var store: AppStore

    init(archives: [ArchiveItem]) {
        self.archives = archives
    }

    var body: some View {
        if useListView {
            List {
                sortPicker()
                ForEach(processArchives()) { (item: ArchiveItem) in
                    NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                        ArchiveRow(archiveItem: item)
                    }
                            .contextMenu {
                                Button(action: {
                                    store.dispatch(.trigger(action: .thumbnailRefreshAction(id: item.id)))
                                }, label: {
                                    Text("archive.reload.thumbnail")
                                })
                            }
                }
            }
        } else {
            let columns = [
                GridItem(.adaptive(minimum: 160))
            ]
            ScrollView {
                sortPicker()
                        .padding([.trailing, .leading], 20)
                Spacer(minLength: 30)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(processArchives()) { (item: ArchiveItem) in
                        NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                            ArchiveGrid(archiveItem: item)
                        }
                                .contextMenu {
                                    Button(action: {
                                        store.dispatch(.trigger(action: .thumbnailRefreshAction(id: item.id)))
                                    }, label: {
                                        Text("archive.reload.thumbnail")
                                    })
                                }
                    }
                }
                        .padding(.horizontal)
            }
        }
    }

    private func sortPicker() -> some View {
        Group {
            if archives.isEmpty {
                EmptyView()
            } else {
                Picker("settings.archive.list.order", selection: self.$archiveListOrder) {
                    Group {
                        Text("settings.archive.list.order.name").tag(ArchiveListOrder.name.rawValue)
                        Text("settings.archive.list.order.dateAdded").tag(ArchiveListOrder.dateAdded.rawValue)
                        Text("settings.archive.list.order.random").tag(ArchiveListOrder.random.rawValue)
                    }
                }
                        .pickerStyle(.segmented)
                        .padding()
            }
        }
    }

    private func processArchives() -> [ArchiveItem] {
        var archivesToProcess = archives
        if archiveListOrder == ArchiveListOrder.name.rawValue {
            archivesToProcess = archivesToProcess.sorted(by: { $0.name < $1.name })
        } else if archiveListOrder == ArchiveListOrder.dateAdded.rawValue {
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
        } else if archiveListOrder == ArchiveListOrder.random.rawValue {
            var generator = FixedRandomGenerator(seed: store.state.archive.randomOrderSeed)
            archivesToProcess = archivesToProcess.shuffled(using: &generator)
        }
        if hideRead {
            archivesToProcess = archivesToProcess.filter { item in
                item.pagecount != item.progress
            }
        }
        return archivesToProcess
    }
}

struct FixedRandomGenerator: RandomNumberGenerator {
    private let seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
    }

    func next() -> UInt64 {
        seed
    }
}
