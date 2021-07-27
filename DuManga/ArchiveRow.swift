//  Created 23/8/20.

import SwiftUI

struct ArchiveRow: View {
    var archiveItem: ArchiveItem

    var body: some View {
        HStack {
            ThumbnailImage(id: archiveItem.id)
                .scaledToFit()
                .frame(width: 100, height: 125)
            Text(archiveItem.name)
                .font(.title)
            Spacer()
        }
    }
}

struct ArchiveRow_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveRow(archiveItem: ArchiveItem(id: "id", name: "name", tags: "tags",
                isNew: true, progress: 0, dateAdded: 1234))
        .previewLayout(.fixed(width: 600, height: 125))
    }
}
