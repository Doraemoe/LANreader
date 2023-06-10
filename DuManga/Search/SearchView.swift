import SwiftUI
import NotificationBannerSwift

struct SearchView: View {
    @StateObject private var searchViewModel = SearchViewModel()

    private let initKeyword: String?

    init(keyword: String? = nil) {
        initKeyword = keyword
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ArchiveList(archives: searchViewModel.searchResult())
                    .searchable(
                        text: $searchViewModel.keyword,
                        placement: .navigationBarDrawer(displayMode: .always)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .searchSuggestions {
                        ForEach(searchViewModel.suggestedTag, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                    .foregroundColor(.accentColor)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                searchViewModel.keyword = searchViewModel.completeString(tag: tag)
                            }
                        }
                    }
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
                    .onChange(of: searchViewModel.errorMessage) { errorMessage in
                        if !errorMessage.isEmpty {
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
            .onAppear {
                searchViewModel.connectStore()
            }
            .onDisappear {
                searchViewModel.disconnectStore()
            }
            .navigationTitle("search")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
