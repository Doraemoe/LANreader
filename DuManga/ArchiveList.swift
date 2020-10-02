//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    private static let dynamicCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())
    private static let staticCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())

    @AppStorage(SettingsKey.useListView) var useListView: Bool = false
    @AppStorage(SettingsKey.archiveListRandom) var archiveListRandom: Bool = false

    @EnvironmentObject var store: AppStore

    @StateObject private var archiveListModel = ArchiveListModel()

    @Binding var navBarTitle: String

    private let searchKeyword: String?
    private let categoryArchives: [String]?
    private let navBarTitleOverride: String?

    init(navBarTitle: Binding<String>,
         searchKeyword: String? = nil,
         categoryArchives: [String]? = nil,
         navBarTitleOverride: String? = nil) {
        self.searchKeyword = searchKeyword
        self.categoryArchives = categoryArchives
        self.navBarTitleOverride = navBarTitleOverride
        self._navBarTitle = navBarTitle
    }

    var body: some View {
        let filteredItems = filterArchives()
        return GeometryReader { geometry in
            ZStack {
                if self.useListView {
                    List {
                        TextField("filter.name", text: $archiveListModel.nameFilter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding()
                        ForEach(filteredItems) { (item: ArchiveItem) in
                            NavigationLink(destination: ArchivePage(itemId: item.id)) {
                                ArchiveRow(archiveItem: item)
                                        .onAppear(perform: {
                                            self.loadThumbnail(id: item.id)
                                        })
                            }
                        }
                    }
                } else {
                    let columns = [
                        GridItem(.adaptive(minimum: 160))
                    ]
                    ScrollView {
                        Spacer(minLength: 20)
                        TextField("filter.name", text: $archiveListModel.nameFilter)
                                .disableAutocorrection(true)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding([.leading, .bottom, .trailing])
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredItems) { (item: ArchiveItem) in
                                ZStack {
                                    ArchiveGrid(archiveItem: item)
                                            .onAppear(perform: { self.loadThumbnail(id: item.id) })
                                    NavigationLink(destination: ArchivePage(itemId: item.id)) {
                                        Rectangle()
                                                .opacity(0.0001)
                                                .contentShape(Rectangle())
                                    }
                                }
                            }
                        }
                                .padding(.horizontal)
                    }
                }

                VStack {
                    Text("loading")
                    ProgressView()
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(archiveListModel.loading ? 1 : 0)
            }
                    .onAppear(perform: {
                        archiveListModel.load(state: store.state)
                        self.navBarTitle = self.navBarTitleOverride ?? "library"
                        self.loadData()
                    })
                    .onDisappear(perform: {
                        archiveListModel.unload()
                    })
                    .onChange(of: archiveListModel.errorCode, perform: { errorCode in
                        if errorCode != nil {
                            let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                    subtitle: NSLocalizedString("error.list", comment: "list error"),
                                    style: .danger)
                            banner.show()
                            store.dispatch(.archive(action: .resetState))
                        }
                    })
        }
    }

    private func loadData() {
        if searchKeyword != nil && !searchKeyword!.isEmpty {
            self.store.dispatch(.archive(action: .fetchArchiveDynamicCategory(keyword: searchKeyword!)))
        } else {
            if archiveListModel.archiveItems.isEmpty {
                self.store.dispatch(.archive(action: .fetchArchive))
            }
        }
    }

    private func loadThumbnail(id: String) {
        if archiveListModel.archiveItems[id]?.thumbnail == Image("placeholder") {
            self.store.dispatch(.archive(action: .fetchArchiveThumbnail(id: id)))
        }
    }

    func filterArchives() -> [ArchiveItem] {
        let archives: [ArchiveItem]
        if searchKeyword != nil && !searchKeyword!.isEmpty {
            archives = ArchiveList.dynamicCategorySelector.select(
                    base: archiveListModel.archiveItems,
                    filter: archiveListModel.dynamicCategoryKeys) { (base, filter) in
                let filtered = base.filter { item in
                    filter.contains(item.key)
                }
                return Array(filtered.values).sorted(by: { $0.name < $1.name })
            }
        } else if categoryArchives != nil && !categoryArchives!.isEmpty {
            archives = ArchiveList.staticCategorySelector.select(
                    base: archiveListModel.archiveItems,
                    filter: categoryArchives!) { (base, filter) in
                let filtered = base.filter { item in
                    filter.contains(item.key)
                }
                return Array(filtered.values).sorted(by: { $0.name < $1.name })
            }
        } else {
            if self.archiveListRandom {
                archives = Array(archiveListModel.archiveItems.values)
            } else {
                archives = Array(archiveListModel.archiveItems.values).sorted(by: { $0.name < $1.name })
            }
        }

        if !archiveListModel.nameFilter.isEmpty {
            return archives.filter { item in
                item.name.localizedCaseInsensitiveContains(archiveListModel.nameFilter)
            }
        } else {
            return archives
        }
    }
}

//struct ArchiveList_Previews: PreviewProvider {
//    static var previews: some View {
//        ArchiveList(archiveItems: [ArchiveItem](), loading: false,
//                errorCode: nil, loadThumbnail: { _ in }, reset: {})
//    }
//}
