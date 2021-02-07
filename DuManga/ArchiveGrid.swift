// Created 1/9/20

import SwiftUI

struct ArchiveGrid: View {
    var archiveItem: ArchiveItem

    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 2) {
            Text(archiveItem.name)
                    .frame(width: 130)
                    .lineLimit(1)
            ThumbnailImage(id: archiveItem.id)
                    .scaledToFit()
                    .frame(width: 160, height: 200)
        }
                .overlay(
                        RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary, lineWidth: 2)
                                .opacity(0.9)
                                .frame(width: 160, height: 230, alignment: .center)
                )
    }
}

struct ArchiveGrid_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveGrid(archiveItem: ArchiveItem(id: "id", name: "name", tags: "tags", isNew: true))
                .previewLayout(.fixed(width: 200, height: 280))
    }
}
