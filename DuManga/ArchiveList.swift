//
//  ArchiveList.swift
//  DuManga
//
//  Created by Jin Yifan on 23/8/20.
//  Copyright © 2020 Jin Yifan. All rights reserved.
//

import SwiftUI

struct ArchiveList: View {
    @State var archiveItems = [String: ArchiveItem]()
    
    private let config: [String: String]
    private let client: LANRaragiClient
    
    init() {
        self.config = UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String] ?? [String: String]()
        self.client = LANRaragiClient(url: config["url"]!, apiKey: config["apiKey"]!)
    }
    
    var body: some View {
        List(Array(archiveItems.values)) { item in
            ArchiveRow(archiveItem: item)
        }
        .onAppear(perform: loadData)
    }
    
    func loadData() {
        client.getArchiveIndex {(items: [ArchiveIndexResponse]?) in
            items?.forEach { item in
                self.archiveItems[item.arcid] = (ArchiveItem(id: item.arcid, name: item.title, thumbnail: Image("placeholder")))
                self.loadArchiveThumbnail(id: item.arcid)
            }
        }
    }
    
    func loadArchiveThumbnail(id: String) {
        client.getArchiveThumbnail(id: id) { (image: UIImage?) in
            if let img = image {
                self.archiveItems[id]?.thumbnail = Image(uiImage: img)
            }
        }
    }
    
}

struct ArchiveList_Previews: PreviewProvider {
    static var previews: some View {
        let config = ["url": "http://localhost", "apiKey": "apiKey"]
        UserDefaults.standard.set(config, forKey: "LANraragi")
        return ArchiveList()
    }
}
