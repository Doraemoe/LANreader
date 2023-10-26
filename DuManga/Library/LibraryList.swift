//
// Created on 6/10/20.
//
import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

struct LibraryList: View {
    @AppStorage(SettingsKey.alwaysLoadFromServer) var alwaysLoadFromServer: Bool = false
    
    @State private var enableSelect: EditMode = .inactive
    @State private var searchText = ""
    
    let store = AppFeature.shared
    
    struct ViewState: Equatable {
        let showLoading: Bool
        let archiveItems: [String: ArchiveItem]
        let errorCode: ErrorCode?
        init(state: AppFeature.State) {
            self.showLoading = state.archive.showLoading
            self.archiveItems = state.archive.archiveItems
            self.errorCode = state.archive.errorCode
        }
    }
    
    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            GeometryReader { geometry in
                ZStack {
                    if enableSelect == .active {
                        ArchiveSelection(archives: searchArchives(archiveItems: viewStore.archiveItems), archiveSelectFor: .library)
                    } else {
                        ArchiveList(archives: searchArchives(archiveItems: viewStore.archiveItems))
                            .task {
                                if viewStore.archiveItems.isEmpty {
                                    viewStore.send(.archive(.fetchArchives(alwaysLoadFromServer, true)))
                                }
                            }
                            .refreshable {
                                if viewStore.showLoading != true {
                                    await viewStore.send(.archive(.fetchArchives(true, false))).finish()
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
                            .onChange(of: viewStore.errorCode) {
                                if viewStore.errorCode != nil {
                                    let banner = NotificationBanner(
                                        title: NSLocalizedString("error", comment: "error"),
                                        subtitle: NSLocalizedString("error.list", comment: "list error"),
                                        style: .danger
                                    )
                                    banner.show()
                                    viewStore.send(.archive(.resetState))
                                }
                            }
                    }
                    if viewStore.showLoading {
                        LoadingView(geometry: geometry)
                    }
                }
                .searchable(text: $searchText, prompt: "filter.name")
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
    }
    
    private func searchArchives(archiveItems: [String: ArchiveItem]) -> [ArchiveItem] {
        var archives: [ArchiveItem] = Array(archiveItems.values)
        if !searchText.isEmpty {
            archives = archives.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return archives
    }
}
