//Created 3/9/20

import SwiftUI

struct ArchiveDetails: View {
    
    let item: ArchiveItem
    
    init(item: ArchiveItem) {
        self.item = item
    }
    
    
    var body: some View {
        HStack {
            item.thumbnail
                .resizable()
                .scaledToFit()
                .padding()
                .frame(width: 200, height: 250)
            VStack(alignment: .center, spacing: 50) {
                Text(item.name)
                    .font(.title)
                Text(item.tags)
            }
            .padding()
            Spacer()
        }
        
    }
}

struct ArchiveDetails_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveDetails(item: ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder")))
    }
}
