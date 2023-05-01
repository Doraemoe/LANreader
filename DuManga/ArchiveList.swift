//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct ArchiveList: View {
    @AppStorage(SettingsKey.useListView) var useListView: Bool = false

    let archives: [ArchiveItem]

    var body: some View {
        if useListView {
            return AnyView(List(archives) { (item: ArchiveItem) in
                NavigationLink(value: item) {
                    ArchiveRow(archiveItem: item)
                }
            }
                    .navigationDestination(for: ArchiveItem.self) { item in
                        ArchivePageV2(archiveItem: item)
                    })
        } else {
            let columns = [
                GridItem(.adaptive(minimum: 160))
            ]
            return AnyView(ScrollView {
                Spacer(minLength: 20)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(archives) { (item: ArchiveItem) in
                        NavigationLink(value: item) {
                            ArchiveGrid(archiveItem: item)
                        }
                    }
                }
                        .navigationDestination(for: ArchiveItem.self) { item in
                            ArchivePageV2(archiveItem: item)
                        }
                        .padding(.horizontal)
            })
        }

    }
}
