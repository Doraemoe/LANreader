//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift
import Logging

struct LibraryList: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    @StateObject private var libraryListModel = LibraryListModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: searchArchives())
                    .task {
                        if libraryListModel.archiveItems.isEmpty {
                            await libraryListModel.load(fromServer: alwaysLoadFromServer)
                        }
                    }
                    .onChange(of: libraryListModel.errorCode, perform: { errorCode in
                        if errorCode != nil {
                            let banner = NotificationBanner(
                                title: NSLocalizedString("error", comment: "error"),
                                subtitle: NSLocalizedString("error.list", comment: "list error"),
                                style: .danger
                            )
                            banner.show()
                            libraryListModel.resetArchiveState()
                        }
                    })
                    .refreshable {
                        if libraryListModel.loading != true {
                            libraryListModel.isPullToRefresh = true
                            await libraryListModel.refresh()
                            libraryListModel.isPullToRefresh = false
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            NavigationLink {
                                HistoryList()
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }

                        }
                    }
                    .searchable(text: $libraryListModel.searchText, prompt: "filter.name")
                    .autocorrectionDisabled()
                if libraryListModel.loading && !libraryListModel.isPullToRefresh {
                    LoadingView(geometry: geometry)
                }
            }
        }
    }

    private func searchArchives() -> [ArchiveItem] {
        var archives: [ArchiveItem] = Array(libraryListModel.archiveItems.values)
        if !libraryListModel.searchText.isEmpty {
            archives = archives.filter { item in
                item.name.localizedCaseInsensitiveContains(libraryListModel.searchText)
            }
        }
        return archives
    }
}
