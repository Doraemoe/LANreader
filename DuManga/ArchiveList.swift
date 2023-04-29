//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false

    let archives: [ArchiveItem]

    var body: some View {
            if useListView {
                return AnyView(List {
                    ForEach(archives) { (item: ArchiveItem) in
                            NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                                ArchiveRow(archiveItem: item)
                            }

                    }
                })
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 160))
                ]
                return AnyView(ScrollView {
                    Spacer(minLength: 20)
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(archives) { (item: ArchiveItem) in
                            ZStack {
                                ArchiveGrid(archiveItem: item)
                                    NavigationLink(destination: ArchivePageV2(archiveItem: item)) {
                                        Rectangle()
                                                .opacity(0.0001)
                                                .contentShape(Rectangle())
                                    }
                            }
                        }
                    }
                            .padding(.horizontal)
                })
            }

    }
}
