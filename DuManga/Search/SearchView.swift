import SwiftUI
import NotificationBannerSwift

struct SearchView: View {
    @StateObject private var searchViewModel = SearchViewModel()

    @EnvironmentObject var store: AppStore

    private let initKeyword: String?

    init(keyword: String? = nil) {
        initKeyword = keyword
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: searchViewModel.result)
                        .searchable(
                                text: $searchViewModel.keyword,
                                placement: .navigationBarDrawer(displayMode: .always)
                        )
                        .onSubmit(of: .search) {
                            Task {
                                await searchViewModel.search()
                            }
                        }
                        .onAppear {
                            if initKeyword != searchViewModel.keyword, let key = initKeyword {
                                searchViewModel.keyword = key
                                Task {
                                    await searchViewModel.search()
                                }
                            }
                        }
                        .onDisappear {
                            searchViewModel.reset()
                        }
                        .onChange(of: searchViewModel.isError) { isError in
                            if isError {
                                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                        subtitle: searchViewModel.errorMessage,
                                        style: .danger)
                                banner.show()
                                searchViewModel.reset()
                            }
                        }
                if searchViewModel.isLoading {
                    LoadingView(geometry: geometry)
                }
            }
                    .navigationTitle("search")
                    .navigationBarTitleDisplayMode(.inline)
        }
    }
}
