// Created 1/9/20

import SwiftUI

struct ArchiveGrid: View {
    var archiveItem: ArchiveItem

    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 2) {
            Text(buildTitle())
                    .frame(width: 130)
                    .lineLimit(1)
                    .foregroundColor(.primary)
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

    func buildTitle() -> String {
        var title = archiveItem.name
        if archiveItem.pagecount == archiveItem.progress {
            title = "👑 " + title
        } else if archiveItem.progress < 2 {
            title = "🆕 " + title
        }
        return title
    }
}
