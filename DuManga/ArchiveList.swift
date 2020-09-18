//  Created 23/8/20.

import SwiftUI

// TODO: Replace with LazyVGrid in iOS 14

import ASCollectionView
import NotificationBannerSwift

struct ArchiveListContainer: View {
    private static let dynamicCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())
    private static let staticCategorySelector = Selector(
            initBase: [String: ArchiveItem](),
            initFilter: [String](),
            initResult: [ArchiveItem]())

    @EnvironmentObject var store: AppStore

    @Binding var navBarTitle: String

    private let searchKeyword: String?
    private let categoryArchives: [String]?
    private let navBarTitleOverride: String?

    init(navBarTitle: Binding<String>,
         searchKeyword: String? = nil,
         categoryArchives: [String]? = nil,
         navBarTitleOverride: String? = nil) {
        self.searchKeyword = searchKeyword
        self.categoryArchives = categoryArchives
        self.navBarTitleOverride = navBarTitleOverride
        self._navBarTitle = navBarTitle
    }

    var body: some View {
        ArchiveList(archiveItems: selectArchiveList(),
                useListView: self.store.state.setting.useListView,
                loading: self.store.state.archive.loading,
                errorCode: self.store.state.archive.errorCode,
                loadThumbnail: loadThumbnail,
                reset: resetState)
                .onAppear(perform: self.loadData)
                .onAppear(perform: {
                    self.navBarTitle = self.navBarTitleOverride ?? "library"
                })
    }

    private func resetState() {
        self.store.dispatch(.archive(action: .resetState))
    }

    private func loadData() {
        if searchKeyword != nil && !searchKeyword!.isEmpty {
            self.store.dispatch(.archive(action: .fetchArchiveDynamicCategory(keyword: searchKeyword!)))
        } else {
            if self.store.state.archive.archiveItems.isEmpty {
                self.store.dispatch(.archive(action: .fetchArchive))
            }
        }
    }

    private func loadThumbnail(id: String) {
        if self.store.state.archive.archiveItems[id]?.thumbnail == Image("placeholder") {
            self.store.dispatch(.archive(action: .fetchArchiveThumbnail(id: id)))
        }
    }

    private func selectArchiveList() -> [ArchiveItem] {
        if searchKeyword != nil && !searchKeyword!.isEmpty {
            return ArchiveListContainer.dynamicCategorySelector.select(
                    base: self.store.state.archive.archiveItems,
                    filter: self.store.state.archive.dynamicCategoryKeys) { (base, filter) in
                let filtered = base.filter { item in
                    filter.contains(item.key)
                }
                return Array(filtered.values).sorted(by: { $0.name < $1.name })
            }
        } else if categoryArchives != nil && !categoryArchives!.isEmpty {
            return ArchiveListContainer.staticCategorySelector.select(
                    base: self.store.state.archive.archiveItems,
                    filter: categoryArchives!) { (base, filter) in
                let filtered = base.filter { item in
                    filter.contains(item.key)
                }
                return Array(filtered.values).sorted(by: { $0.name < $1.name })
            }
        } else {
            if self.store.state.setting.archiveListRandom {
                return Array(self.store.state.archive.archiveItems.values)
            } else {
                return Array(self.store.state.archive.archiveItems.values).sorted(by: { $0.name < $1.name })
            }
        }
    }

}

struct ArchiveList: View {

    private let archiveItems: [ArchiveItem]
    private let useListView: Bool
    private let loading: Bool
    private let errorCode: ErrorCode?
    private let loadThumbnail: (String) -> Void
    private let reset: () -> Void

    init(archiveItems: [ArchiveItem],
         useListView: Bool,
         loading: Bool,
         errorCode: ErrorCode?,
         loadThumbnail: @escaping (String) -> Void,
         reset: @escaping () -> Void) {
        self.archiveItems = archiveItems
        self.useListView = useListView
        self.loading = loading
        self.errorCode = errorCode
        self.loadThumbnail = loadThumbnail
        self.reset = reset
    }

    var body: some View {
        handleError()
        return GeometryReader { geometry in
            ZStack {
                if self.useListView {
                    List(self.archiveItems) { (item: ArchiveItem) in
                        NavigationLink(destination: ArchivePageContainer(item: item)) {
                            ArchiveRow(archiveItem: item)
                                    .onAppear(perform: {
                                        self.loadThumbnail(item.id)
                                    })
                        }
                    }
                } else {
                    ASCollectionView(data: self.archiveItems) { (item: ArchiveItem, _) in
                        ZStack {
                            ArchiveGrid(archiveItem: item)
                                    .onAppear(perform: { self.loadThumbnail(item.id) })
                            NavigationLink(destination: ArchivePageContainer(item: item)) {
                                Rectangle()
                                        .opacity(0.0001)
                                        .contentShape(Rectangle())
                            }
                        }
                    }.layout {
                        .grid(layoutMode: .adaptive(withMinItemSize: 190),
                                itemSpacing: 30,
                                lineSpacing: 30,
                                itemSize: .absolute(260))
                    }
                }

                VStack {
                    Text("loading")
                    ActivityIndicator(isAnimating: self.loading, style: .large)
                }
                        .frame(width: geometry.size.width / 3,
                                height: geometry.size.height / 5)
                        .background(Color.secondary)
                        .foregroundColor(Color.primary)
                        .cornerRadius(20)
                        .opacity(self.loading ? 1 : 0)
            }
        }
    }

    func handleError() {
        if let error = errorCode {
            switch error {
            case .archiveFetchError:
                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                        subtitle: NSLocalizedString("error.list", comment: "list error"),
                        style: .danger)
                banner.show()
                reset()
            default:
                break
            }
        }
    }
}

struct ArchiveList_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveList(archiveItems: [ArchiveItem](), useListView: false, loading: false,
                errorCode: nil, loadThumbnail: { _ in }, reset: {})
    }
}
