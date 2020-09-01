//  Created 23/8/20.

import SwiftUI
// TODO: Replace with LazyVGrid in iOS 14
import ASCollectionView

struct ArchiveList: View {
    @State var archiveItems = [String: ArchiveItem]()
    @State var isLoading = false
    @Binding var navBarTitle: String
    
    private let config: [String: String]
    private let client: LANRaragiClient
    
    private let searchKeyword: String?
    private let categoryArchives: [String]?
    private let navBarTitleOverride: String?
    
    init(navBarTitle: Binding<String>, searchKeyword: String? = nil, categoryArchives: [String]? = nil, navBarTitleOverride: String? = nil) {
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
        self.searchKeyword = searchKeyword
        self.categoryArchives = categoryArchives
        self.navBarTitleOverride = navBarTitleOverride
        self._navBarTitle = navBarTitle
    }
    
    var body: some View {
        let archives: [ArchiveItem]
        if !UserDefaults.standard.bool(forKey: SettingsKey.archiveListRandom) {
            archives = Array(self.archiveItems.values).sorted(by: { $0.name < $1.name })
        } else {
            archives = Array(self.archiveItems.values)
        }
        return GeometryReader { geometry in
            ZStack {
                if UserDefaults.standard.bool(forKey: SettingsKey.useListView) {
                    List(archives) { (item: ArchiveItem) in
                        NavigationLink(destination: ArchivePage(id: item.id)) {
                            ArchiveRow(archiveItem: item)
                                .onAppear(perform: { self.loadArchiveThumbnail(id: item.id)
                                })
                        }
                    }
                } else {
                    ASCollectionView(data: archives) {  (item: ArchiveItem, _) in
                        ZStack {
                            ArchiveGrid(archiveItem: item)
                            .onAppear(perform: { self.loadArchiveThumbnail(id: item.id) })
                            NavigationLink(destination: ArchivePage(id: item.id)) {
                                Rectangle()
                                .opacity(0.0001)
                                .contentShape(Rectangle())
                            }
                        }
                    }.layout {
                        .grid(layoutMode: .adaptive(withMinItemSize: 200),
                              itemSpacing: 5,
                              lineSpacing: 10,
                              itemSize: .absolute(220))
                    }
                }
                
                
                VStack {
                    Text("loading")
                    ActivityIndicator(isAnimating: self.$isLoading, style: .large)
                }
                .frame(width: geometry.size.width / 3,
                       height: geometry.size.height / 5)
                    .background(Color.secondary.colorInvert())
                    .foregroundColor(Color.primary)
                    .cornerRadius(20)
                    .opacity(self.isLoading ? 1 : 0)
            }
            .onAppear(perform: {
                self.navBarTitle = self.navBarTitleOverride ?? "library"
            })
                .onAppear(perform: self.loadData)
        }
    }
    
    func loadData() {
        if (self.archiveItems.count > 0) {
            return
        }
        self.isLoading = true
        if searchKeyword != nil && !searchKeyword!.isEmpty {
            client.searchArchiveIndex(filter: searchKeyword) {(result: ArchiveSearchResponse?) in
                result?.data.forEach { item in
                    if self.archiveItems[item.arcid] == nil {
                        self.archiveItems[item.arcid] = (ArchiveItem(id: item.arcid, name: item.title, thumbnail: Image("placeholder")))
                    }
                }
                self.isLoading = false
            }
        } else if categoryArchives != nil && !categoryArchives!.isEmpty {
            categoryArchives?.forEach { archiveId in
                client.getArchiveMetadata(id: archiveId) { (item: ArchiveIndexResponse?) in
                    if let it = item {
                        if self.archiveItems[it.arcid] == nil {
                            self.archiveItems[it.arcid] = (ArchiveItem(id: it.arcid, name: it.title, thumbnail: Image("placeholder")))
                        }
                    }
                }
            }
            self.isLoading = false
        } else {
            client.getArchiveIndex {(items: [ArchiveIndexResponse]?) in
                items?.forEach { item in
                    if self.archiveItems[item.arcid] == nil {
                        self.archiveItems[item.arcid] = (ArchiveItem(id: item.arcid, name: item.title, thumbnail: Image("placeholder")))
                    }
                }
                self.isLoading = false
            }
        }
    }
    
    func loadArchiveThumbnail(id: String) {
        if self.archiveItems[id]?.thumbnail == Image("placeholder") {
            client.getArchiveThumbnail(id: id) { (image: UIImage?) in
                if let img = image {
                    self.archiveItems[id]?.thumbnail = Image(uiImage: img)
                }
            }
        }
    }
    
}

struct ArchiveList_Previews: PreviewProvider {
    static var previews: some View {
        let config = ["url": "http://localhost", "apiKey": "apiKey"]
        UserDefaults.standard.set(config, forKey: "LANraragi")
        return ArchiveList(navBarTitle: Binding.constant("library"))
    }
}
