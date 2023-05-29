// Created 1/9/20

import SwiftUI

struct ArchiveGrid: View {
    var archiveItem: ArchiveItem

    var body: some View {
        VStack(alignment: HorizontalAlignment.center, spacing: 2) {
            Text(buildTitle())
                .lineLimit(2)
                .foregroundColor(.primary)
                .padding(4)
                .font(.caption)
            ThumbnailImage(id: archiveItem.id)
                .scaledToFit()
                .queryObservation(.onRender)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary, lineWidth: 2)
                .opacity(0.9)
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
