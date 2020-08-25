//  Created 23/8/20.

import SwiftUI

struct ArchiveRow: View {
    var archiveItem: ArchiveItem
    
    var body: some View {
        HStack {
            archiveItem.thumbnail
                .resizable()
                .frame(width: 100, height: 125)
            Text(archiveItem.name)
            Spacer()
        }
    }
}

struct ArchiveRow_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveRow(archiveItem: ArchiveItem(id: "id", name: "name", thumbnail: Image("placeholder")))
        .previewLayout(.fixed(width: 600, height: 125))
    }
}
