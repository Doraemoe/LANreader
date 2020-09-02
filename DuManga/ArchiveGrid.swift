//Created 1/9/20

import SwiftUI

struct ArchiveGrid: View {
    var archiveItem: ArchiveItem
    
    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 2) {
            Text(archiveItem.name)
                .frame(width: 150)
            archiveItem.thumbnail
            .resizable()
            .scaledToFit()
            .frame(width: 180, height: 225)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary, lineWidth: 2)
                .opacity(0.9)
                .frame(width: 180, height: 260, alignment: .center)
        )
    }
}

struct ArchiveGrid_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveGrid(archiveItem: ArchiveItem(id: "id", name: "name", thumbnail: Image("placeholder")))
        .previewLayout(.fixed(width: 200, height: 280))
    }
}
