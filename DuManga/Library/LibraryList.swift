//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift

struct LibraryList: View {
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    @EnvironmentObject var store: AppStore

    @StateObject private var libraryListModel = LibraryListModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: Array(self.libraryListModel.archiveItems.values), listOrder: archiveListOrder)
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

    private func checkLoadingFinished() async {
        repeat {
            try? await Task.sleep(for: Duration.seconds(1))
        }
        while libraryListModel.loading == true
    }
}
