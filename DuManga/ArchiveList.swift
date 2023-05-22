//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false

    private let archives: [ArchiveItem]

    @EnvironmentObject var store: AppStore

    @StateObject var archiveListModel = ArchiveListModel()

    init(archives: [ArchiveItem]) {
        self.archives = archives
    }

    var body: some View {
        Group {
            if useListView {
                List {
                    sortPicker()
                    ForEach(archiveListModel.sortedArchives) { (item: ArchiveItem) in
                        NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                            ArchiveRow(archiveItem: item)
                        }
                                .contextMenu {
                                    contextMenu(id: item.id)
                                }
                    }
                }
                        .listStyle(.grouped)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 160))
                ]
                ScrollView {
                    sortPicker()
                            .padding([.trailing, .leading], 20)
                    Spacer(minLength: 30)
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(archiveListModel.sortedArchives) { (item: ArchiveItem) in
                            NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                                ArchiveGrid(archiveItem: item)
                            }
                                    .contextMenu {
                                        contextMenu(id: item.id)
                                    }
                        }
                    }
                            .padding(.horizontal)
                }
            }
        }
                .onChange(of: archives) { [archives] newArchives in
                    if archives != newArchives {
                        archiveListModel.processArchives(
                                archives: newArchives, sortOrder: archiveListOrder, hideRead: hideRead
                        )
                    }
                }
                .onChange(of: archiveListOrder) { [archiveListOrder] newOrder in
                    if archiveListOrder != newOrder {
                        archiveListModel.processArchives(archives: archives, sortOrder: newOrder, hideRead: hideRead)
                    }
                }
                .onChange(of: hideRead) { [hideRead] newHideRead in
                    if hideRead != newHideRead {
                        archiveListModel.processArchives(
                                archives: archives, sortOrder: archiveListOrder, hideRead: newHideRead
                        )
                    }
                }
                .onAppear {
                    archiveListModel.load(state: store.state)
                }
                .onDisappear {
                    archiveListModel.unload()
                }
    }

    private func contextMenu(id: String) -> some View {
        Button(action: {
            store.dispatch(.trigger(action: .thumbnailRefreshAction(id: id)))
        }, label: {
            Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
        })
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
