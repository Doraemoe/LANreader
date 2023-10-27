//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false

    private let archives: [ArchiveItem]
    private let sortArchives: Bool

    @State var archiveListModel = ArchiveListModel()

    init(archives: [ArchiveItem], sortArchives: Bool = true) {
        self.archives = archives
        self.sortArchives = sortArchives
    }

    var body: some View {
        let archivesToDisplay = archiveListModel.processArchives(
            archives: archives,
            sortOrder: archiveListOrder,
            hideRead: hideRead,
            sortArchives: sortArchives
        )
        Group {
            let columns = [
                GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
            ]
            ScrollView {
                if sortArchives {
                    sortPicker()
                        .padding([.trailing, .leading], 20)
                }
                Spacer(minLength: 30)
                LazyVGrid(columns: columns) {
                    ForEach(archivesToDisplay) { (item: ArchiveItem) in
                        NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                            ArchiveGrid(archiveItem: item)
                        }
                        .contextMenu {
                            contextMenu(item: item)
                        }
                    }
                }
                .padding(.horizontal)
            }

        }
        .onAppear {
            archiveListModel.connectStore()
        }
        .onDisappear {
            archiveListModel.disconnectStore()
        }
        .onChange(of: archives) { oldArchives, newArchives in
            if oldArchives != newArchives {
                archiveListModel.resetSortedArchives()
            }
        }
    }

    private func contextMenu(item: ArchiveItem) -> some View {
        Group {
            NavigationLink {
                ArchivePageV2(archiveItem: item, startFromBeginning: true)
            } label: {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            Button(action: {
                archiveListModel.refreshThumbnail(id: item.id)
            }, label: {
                Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
            })
        }
    }

    private func sortPicker() -> some View {
        Group {
            if archives.isEmpty {
                EmptyView()
            } else {
                HStack {
                    Picker("settings.archive.list.order", selection: self.$archiveListOrder) {
                        Group {
                            Text("settings.archive.list.order.name").tag(ArchiveListOrder.name.rawValue)
                            Text("settings.archive.list.order.dateAdded").tag(ArchiveListOrder.dateAdded.rawValue)
                            Text("settings.archive.list.order.random").tag(ArchiveListOrder.random.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("settings.view.hideRead")
                    Toggle("", isOn: self.$hideRead)
                        .labelsHidden()
                }
                .padding()
            }
        }
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
