//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift

struct LibraryList: View {
    @AppStorage(SettingsKey.archiveListRandom) var archiveListRandom: Bool = false

    @EnvironmentObject var store: AppStore

    @StateObject private var libraryListModel = LibraryListModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: Array(self.libraryListModel.archiveItems.values), randomList: archiveListRandom)
                        .onAppear(perform: {
                            self.libraryListModel.load(state: store.state)
                            if libraryListModel.archiveItems.isEmpty {
                                self.store.dispatch(.archive(action: .fetchArchive))
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
                VStack {
                    Text("loading")
                    ProgressView()
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(self.libraryListModel.loading ? 1 : 0)
            }
        }
    }
}
