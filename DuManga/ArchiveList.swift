//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false

    @State private var nameFilter = ""

    private let archives: [ArchiveItem]
    private let listOrder: String

    init(archives: [ArchiveItem], listOrder: String = ArchiveListOrder.name.rawValue) {
        self.archives = archives
        self.listOrder = listOrder
    }

    var body: some View {
        let filteredItems = filterArchives()
            if useListView {
                return AnyView(List {
                    TextField("filter.name", text: $nameFilter)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding()
                    ForEach(filteredItems) { (item: ArchiveItem) in
                            NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                                ArchiveRow(archiveItem: item)
                            }

                    }
                })
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 160))
                ]
                return AnyView(ScrollView {
                    Spacer(minLength: 20)
                    TextField("filter.name", text: $nameFilter)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding([.leading, .bottom, .trailing])
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredItems) { (item: ArchiveItem) in
                            ZStack {
                                ArchiveGrid(archiveItem: item)
                                    NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                                        Rectangle()
                                                .opacity(0.0001)
                                                .contentShape(Rectangle())
                                    }
                            }
                        }
                    }
                            .padding(.horizontal)
                })
            }

    }

    func filterArchives() -> [ArchiveItem] {
        var archives: [ArchiveItem]
        if listOrder == ArchiveListOrder.random.rawValue {
            archives = self.archives
        } else if listOrder == ArchiveListOrder.name.rawValue {
            archives = self.archives.sorted(by: { $0.name < $1.name })
        } else {
            archives = self.archives.sorted { item, item2 in
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
        if !nameFilter.isEmpty {
            return archives.filter { item in
                item.name.localizedCaseInsensitiveContains(nameFilter)
            }
        } else {
            return archives
        }
    }
}

// struct ArchiveList_Previews: PreviewProvider {
//    static var previews: some View {
//        ArchiveList(archiveItems: [ArchiveItem](), loading: false,
//                errorCode: nil, loadThumbnail: { _ in }, reset: {})
//    }
// }
