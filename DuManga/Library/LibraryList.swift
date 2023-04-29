//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift

struct LibraryList: View {
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false

    @EnvironmentObject var store: AppStore

    @StateObject private var libraryListModel = LibraryListModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: processArchives())
                        .onAppear(perform: {
                            self.libraryListModel.load(state: store.state)
                            if libraryListModel.archiveItems.isEmpty {
                                self.store.dispatch(.archive(action: .fetchArchive(fromServer: alwaysLoadFromServer)))
                            }
                        })
                        .onDisappear(perform: {
                            self.libraryListModel.unload()
                        })
                        .onChange(of: self.libraryListModel.errorCode, perform: { errorCode in
                            if errorCode != nil {
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                        subtitle: NSLocalizedString("error.list", comment: "list error"),
                                        style: .danger)
                                banner.show()
                                store.dispatch(.archive(action: .resetState))
                            }
                        })
                        .refreshable {
                            if libraryListModel.loading != true {
                                self.libraryListModel.isPullToRefresh = true
                                self.store.dispatch(.archive(action: .fetchArchive(fromServer: true)))
                                await checkLoadingFinished()
                                self.libraryListModel.isPullToRefresh = false
                            }
                        }
                        .searchable(text: $libraryListModel.searchText, prompt: "filter.name")
                if self.libraryListModel.loading && !self.libraryListModel.isPullToRefresh {
                    VStack {
                        Text("loading")
                        ProgressView()
                    }
                            .frame(width: geometry.size.width / 3,
                                    height: geometry.size.height / 5)
                            .background(Color.secondary)
                            .foregroundColor(Color.primary)
                            .cornerRadius(20)
                }
            }
        }
    }

    private func processArchives() -> [ArchiveItem] {
        var archives: [ArchiveItem] = Array(self.libraryListModel.archiveItems.values)
        if archiveListOrder == ArchiveListOrder.name.rawValue {
            archives = archives.sorted(by: { $0.name < $1.name })
        } else {
            archives = archives.sorted { item, item2 in
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
        }
        if hideRead {
            archives = archives.filter { item in
                item.pagecount != item.progress
            }
        }
        if !libraryListModel.searchText.isEmpty {
            archives = archives.filter { item in
                item.name.localizedCaseInsensitiveContains(libraryListModel.searchText)
            }
        }
        return archives
    }

    private func checkLoadingFinished() async {
        repeat {
            try? await Task.sleep(for: Duration.seconds(1))
        } while libraryListModel.loading == true
    }
}
