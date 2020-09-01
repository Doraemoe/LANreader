//Created 1/9/20

import SwiftUI

struct ArchiveGrid: View {
    var archiveItem: ArchiveItem
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 5) {
            Text(archiveItem.name)
                .clipped()
            archiveItem.thumbnail
            .resizable()
            .scaledToFit()
            .frame(width: 150, height: 190)
        }
    }
}

struct ArchiveGrid_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveGrid(archiveItem: ArchiveItem(id: "id", name: "name", thumbnail: Image("placeholder")))
        .previewLayout(.fixed(width: 150, height: 220))
    }
}
