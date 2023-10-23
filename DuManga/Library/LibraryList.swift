//
// Created on 6/10/20.
//

import SwiftUI
import NotificationBannerSwift
import Logging

struct LibraryList: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false

    @State private var enableSelect: EditMode = .inactive
    @State private var libraryListModel = LibraryListModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if enableSelect == .active {
                    ArchiveSelection(archives: searchArchives(), archiveSelectFor: .library)
                } else {
                    ArchiveList(archives: searchArchives())
                        .task {
                            if libraryListModel.archiveItems.isEmpty {
                                await libraryListModel.load(fromServer: alwaysLoadFromServer)
                            }
                        }
                        .refreshable {
                            if libraryListModel.loading != true {
                                await libraryListModel.refresh(isPullToRefrsh: true)
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
                        .onChange(of: libraryListModel.errorCode) {
                            if libraryListModel.errorCode != nil {
                                let banner = NotificationBanner(
                                    title: NSLocalizedString("error", comment: "error"),
                                    subtitle: NSLocalizedString("error.list", comment: "list error"),
                                    style: .danger
                                )
                                banner.show()
                                libraryListModel.resetArchiveState()
                            }
                        }
                }
                if libraryListModel.loading {
                    LoadingView(geometry: geometry)
                }
            }
            .onAppear {
                libraryListModel.connectStore()
            }
            .onDisappear {
                libraryListModel.disconnectStore()
            }
            .searchable(text: $libraryListModel.searchText, prompt: "filter.name")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(enableSelect == .active ? "cancel" : "select") {
                        switch enableSelect {
                        case .active:
                            self.enableSelect = .inactive
                        case .inactive:
                            self.enableSelect = .active
                        default:
                            break
                        }
                    }
                }
            }
            .environment(\.editMode, $enableSelect)
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
