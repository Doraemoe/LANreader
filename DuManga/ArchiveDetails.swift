//Created 3/9/20

import SwiftUI

struct ArchiveDetails: View {
    
    let item: ArchiveItem
    
    init(item: ArchiveItem) {
        self.item = item
    }
    
    
    var body: some View {
        VStack {
            Text(item.name)
                .font(.title)
                .padding()
            item.thumbnail
                .resizable()
                .scaledToFit()
                .padding()
                .frame(width: 200, height: 250)
            ScrollView(.vertical) {
                Text(item.tags)
                    .padding()
            }
        }
    }
}

struct ArchiveDetails_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveDetails(item: ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder")))
    }
}
