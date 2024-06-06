import SwiftUI
import ComposableArchitecture
import NotificationBannerSwift

@Reducer struct CacheFeature {
    @ObservableState
    struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var downloading: [String: PageProgress] = [:]
        var showLoading: Bool = false
        var errorMessage: String = ""
    }

    enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case load
        case refreshProgress
        case removeItemFromDownloading(String)
        case updateProgressInDownloading(String, Int)
        case removeCache(String)
        case setErrorMessage(String)
    }

    @Dependency(\.appDatabase) var database
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                if let allCaches = try? database.readAllCached() {
                    var gridStates: [GridFeature.State] = []
                    for cache in allCaches {
                        if !cache.cached {
                            state.downloading[cache.id] = PageProgress(current: 0, total: cache.totalPages)
                        }
                        let item = ArchiveItem(
                            id: cache.id,
                            name: cache.title,
                            normalizedName: cache.title,
                            extension: "",
                            tags: cache.tags,
                            isNew: false,
                            progress: 0,
                            pagecount: cache.totalPages,
                            dateAdded: nil
                        )
                        gridStates.append(
                            GridFeature.State(
                                archive: Shared(item),
                                cached: true
                            )
                        )
                    }
                    state.archives = IdentifiedArray(uniqueElements: gridStates)
                }
                return .run { send in
                    await send(.refreshProgress)
                }
            case .refreshProgress:
                return .run { [downloading = state.downloading] send in
                    var inProgress = downloading
                    repeat {
                        for caching in inProgress {
                            let cacheFolder = LANraragiService.cachePath!
                                .appendingPathComponent(caching.key, conformingTo: .folder)
                            if let content = try? FileManager.default.contentsOfDirectory(
                                at: cacheFolder, includingPropertiesForKeys: []
                            ) {
                                let downloadPage = content.compactMap { url in
                                    if let pageNumber = Int(url.lastPathComponent) {
                                        return pageNumber
                                    } else {
                                        return nil
                                    }
                                }.count
                                if downloadPage >= caching.value.total {
                                    await send(.removeItemFromDownloading(caching.key))
                                    inProgress.removeValue(forKey: caching.key)
                                    _ = try? database.updateCached(caching.key)
                                } else {
                                    await send(.updateProgressInDownloading(caching.key, downloadPage))
                                }
                            }
                        }
                        try await clock.sleep(for: .seconds(2))
                    } while !inProgress.isEmpty
                }
            case let .removeItemFromDownloading(id):
                state.downloading.removeValue(forKey: id)
                return .none
            case let .updateProgressInDownloading(id, progress):
                state.downloading[id]?.current = progress
                return .none
            case let .removeCache(id):
                let deleted = try? database.deleteCache(id)
                if deleted != true {
                    let errorMessage = String(localized: "archive.cache.remove.failed")
                    return .send(.setErrorMessage(errorMessage))
                }
                state.archives.remove(id: id)
                state.downloading.removeValue(forKey: id)
                let cacheFolder = LANraragiService.cachePath!
                    .appendingPathComponent(id, conformingTo: .folder)
                try? FileManager.default.removeItem(at: cacheFolder)
                return .none
            case let .setErrorMessage(message):
                state.errorMessage = message
                return .none
            default:
                return .none
            }
        }
        .forEach(\.archives, action: \.grid) {
            GridFeature()
        }
    }
}

struct CacheView: View {
    let store: StoreOf<CacheFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(
                    store.scope(state: \.archives, action: \.grid),
                    id: \.state.id
                ) { gridStore in
                    let inProgress = store.downloading.contains { (key, _) in
                        key == gridStore.id
                    }
                    grid(gridStore: gridStore, inProgress: inProgress)
                }
            }
            .padding(.horizontal)
            if store.showLoading {
                ProgressView("loading")
            }
        }
        .task {
            store.send(.load)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("cached")
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                let banner = NotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                banner.show()
                store.send(.setErrorMessage(""))
            }
        }
    }

    private func contextMenu(gridStore: StoreOf<GridFeature>) -> some View {
        Group {
            Button {
                store.send(.removeCache(gridStore.state.id))
            } label: {
                Label("archive.cache.remove", systemImage: "trash")
            }
        }
    }

    private func grid(
        gridStore: StoreOf<GridFeature>,
        inProgress: Bool
    ) -> some View {
        Group {
            if inProgress {
                let progress = if let progressItem = store.downloading[gridStore.state.id] {
                    Double(progressItem.current) / Double(progressItem.total)
                } else {
                    0.0
                }
                ArchiveGridV2(store: gridStore)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .foregroundStyle(Color.black.opacity(0.5))
                            .overlay {
                                ProgressView(value: progress) {
                                    EmptyView()
                                } currentValueLabel: {
                                    Text(String(format: "%.2f%%", progress * 100))
                                        .fontWeight(.bold)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                }
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .padding(.horizontal, 10)
                            }
                    }
                    .contextMenu {
                        contextMenu(gridStore: gridStore)
                    }
            } else {
                NavigationLink(
                    state: AppFeature.Path.State.reader(
                        ArchiveReaderFeature.State.init(
                            archive: gridStore.$archive,
                            cached: true
                        )
                    )
                ) {
                    ArchiveGridV2(store: gridStore)
                        .contextMenu {
                            contextMenu(gridStore: gridStore)
                        }
                }
            }
        }
    }
}

struct PageProgress: Equatable {
    var current: Int
    let total: Int
}
