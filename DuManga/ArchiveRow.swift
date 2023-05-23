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
                .badge(buildBadge())
            Spacer()
        }
    }

    private func buildBadge() -> String? {
        if archiveItem.pagecount == archiveItem.progress {
            return "👑"
        } else if archiveItem.progress < 2 {
            return "🆕"
        }
        return nil
    }
}
