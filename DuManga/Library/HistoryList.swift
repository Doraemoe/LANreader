import SwiftUI
import NotificationBannerSwift

struct HistoryList: View {

    @StateObject var historyListModel = HistoryListModel()

    var body: some View {
        ArchiveList(archives: historyListModel.archives, sortArchives: false)
            .onAppear {
                historyListModel.loadHistory()
            }
            .onChange(of: historyListModel.errorMessage) { errorMessage in
                if !errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error.history.title", comment: "error"),
                        subtitle: errorMessage,
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