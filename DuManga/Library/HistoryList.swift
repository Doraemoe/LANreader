import SwiftUI
import NotificationBannerSwift

struct HistoryList: View {

    @State var historyListModel = HistoryListModel()

    var body: some View {
        ArchiveList(archives: historyListModel.archives, sortArchives: false)
            .onAppear {
                historyListModel.loadHistory()
            }
            .onChange(of: historyListModel.errorMessage) {
                if !historyListModel.errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error.history.title", comment: "error"),
                        subtitle: historyListModel.errorMessage,
                        style: .danger
                    )
                    banner.show()
                    historyListModel.reset()
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle("history")
            .navigationBarTitleDisplayMode(.inline)
    }
}
