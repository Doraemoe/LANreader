//  Created 23/8/20.

import SwiftUI

struct ArchiveList: View {
    @State var archiveItems = [String: ArchiveItem]()
    @Binding var settingView: Bool
    
    private let config: [String: String]
    private let client: LANRaragiClient
    
    init(settingView: Binding<Bool>) {
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
        self._settingView = settingView
    }
    
    var body: some View {
        NavigationView {
            List(Array(archiveItems.values)) { (item: ArchiveItem) in
                NavigationLink(destination: ArchivePage(id: item.id)) {
                    ArchiveRow(archiveItem: item)
                        .onAppear(perform: { self.loadArchiveThumbnail(id: item.id)
                        })
                }
            }
            .onAppear(perform: loadData)
            .navigationBarTitle(Text("archive.list.title"))
            .navigationBarItems(trailing:Button(action: {
                self.settingView.toggle()
            }) {
                Text("archive.list.settings")
            } )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func loadData() {
        client.getArchiveIndex {(items: [ArchiveIndexResponse]?) in
            items?.forEach { item in
                if self.archiveItems[item.arcid] == nil {
                    self.archiveItems[item.arcid] = (ArchiveItem(id: item.arcid, name: item.title, thumbnail: Image("placeholder")))
                }
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
        return ArchiveList(settingView: Binding.constant(false))
    }
}
