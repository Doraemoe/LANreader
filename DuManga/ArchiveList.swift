//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false

    @State private var nameFilter = ""

    private let archives: [ArchiveItem]
    private let randomList: Bool

    init(archives: [ArchiveItem], randomList: Bool = false) {
        self.archives = archives
        self.randomList = randomList
    }

    var body: some View {
        let filteredItems = filterArchives()
           return ZStack {
                if self.useListView {
                    List {
                        TextField("filter.name", text: $nameFilter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding()
                        ForEach(filteredItems) { (item: ArchiveItem) in
                            NavigationLink(destination: ArchivePage(archiveItem: item)) {
                                ArchiveRow(archiveItem: item)
                            }
                        }
                    }
                } else {
                    let columns = [
                        GridItem(.adaptive(minimum: 160))
                    ]
                    ScrollView {
                        Spacer(minLength: 20)
                        TextField("filter.name", text: $nameFilter)
                                .disableAutocorrection(true)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding([.leading, .bottom, .trailing])
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredItems) { (item: ArchiveItem) in
                                ZStack {
                                    ArchiveGrid(archiveItem: item)
                                    NavigationLink(destination: ArchivePage(archiveItem: item)) {
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
            }
    }

    func filterArchives() -> [ArchiveItem] {
        let archives: [ArchiveItem]
        if randomList {
            archives = self.archives
        } else {
            archives = self.archives.sorted(by: { $0.name < $1.name })
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
