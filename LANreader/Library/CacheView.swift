import SwiftUI
import ComposableArchitecture

@Reducer public struct CacheFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var downloading: [String: PageProgress] = [:]
        var failedDownloads: Set<String> = []
        var retryingDownloads: Set<String> = []
        var errorMessage: String = ""
        var isSelecting = false
        var selected: Set<String> = []
    }

    public enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case load
        case removeItemFromDownloading(String)
        case updateProgressInDownloading(String, Int)
        case cacheDownloadFailed(String)
        case retryCache(String)
        case retryCacheFinished(String)
        case retryCacheFailed(String, String)
        case removeCache(String)
        case toggleSelectionMode
        case toggleSelection(String)
        case removeSelected
        case setErrorMessage(String)
    }

    private enum CancelID: Hashable, Sendable {
        case progressPolling
        case retry(String)
    }

    @Dependency(\.appDatabase) var database
    @Dependency(\.continuousClock) var clock
    @Dependency(\.lanraragiService) var service
    @Dependency(\.imageService) var imageService

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleSelectionMode:
                state.isSelecting.toggle()
                state.selected.removeAll()
                return .none
            case let .toggleSelection(id):
                guard state.isSelecting, state.archives[id: id] != nil else { return .none }
                if !state.selected.insert(id).inserted {
                    state.selected.remove(id)
                }
                return .none
            case .removeSelected:
                let selected = state.selected.sorted()
                return .run { send in
                    for id in selected {
                        await send(.removeCache(id))
                    }
                }
            case .load:
                guard let allCaches = try? database.readAllCached() else {
                    return .cancel(id: CancelID.progressPolling)
                }
                var downloading: [String: PageProgress] = [:]
                var gridStates: [GridFeature.State] = []
                for cache in allCaches {
                    if !cache.cached {
                        downloading[cache.id] = PageProgress(current: 0, total: cache.totalPages)
                    }
                    gridStates.append(
                        GridFeature.State(
                            archive: Shared(value: cache.toArchiveItem()),
                            cached: true
                        )
                    )
                }
                state.archives = IdentifiedArray(uniqueElements: gridStates)
                state.selected.formIntersection(state.archives.ids)
                state.downloading = downloading
                state.failedDownloads = []
                return progressPollingEffect(downloading.filter { !state.retryingDownloads.contains($0.key) })
            case let .removeItemFromDownloading(id):
                state.downloading.removeValue(forKey: id)
                state.failedDownloads.remove(id)
                state.retryingDownloads.remove(id)
                return .none
            case let .updateProgressInDownloading(id, progress):
                state.downloading[id]?.current = progress
                return .none
            case let .cacheDownloadFailed(id):
                guard state.downloading[id] != nil else { return .none }
                state.failedDownloads.insert(id)
                return .none
            case let .retryCache(id):
                guard state.failedDownloads.contains(id), !state.retryingDownloads.contains(id) else {
                    return .none
                }
                state.failedDownloads.remove(id)
                state.retryingDownloads.insert(id)
                return .run { send in
                    let extraction = try await service.extractArchiveForReading(id: id)
                    guard !extraction.pages.isEmpty else {
                        await send(.retryCacheFailed(id, String(localized: "error.page.empty")))
                        return
                    }
                    try await service.cachePages(archiveId: id, pages: extraction.pages)
                    await send(.retryCacheFinished(id))
                } catch: { error, send in
                    await send(.retryCacheFailed(id, error.localizedDescription))
                }
                .cancellable(id: CancelID.retry(id), cancelInFlight: true)
            case let .retryCacheFinished(id):
                state.retryingDownloads.remove(id)
                state.failedDownloads.remove(id)
                return progressPollingEffect(state.downloading.filter {
                    !state.failedDownloads.contains($0.key) && !state.retryingDownloads.contains($0.key)
                })
            case let .retryCacheFailed(id, message):
                state.retryingDownloads.remove(id)
                state.failedDownloads.insert(id)
                state.errorMessage = message
                return .none
            case let .removeCache(id):
                let deleted = try? database.deleteCache(id)
                if deleted != true {
                    let errorMessage = String(localized: "archive.cache.remove.failed")
                    return .send(.setErrorMessage(errorMessage))
                }
                state.archives.remove(id: id)
                state.selected.remove(id)
                state.downloading.removeValue(forKey: id)
                state.failedDownloads.remove(id)
                state.retryingDownloads.remove(id)
                return .merge(
                    .cancel(id: CancelID.retry(id)),
                    .run { _ in await service.removeCachedPages(archiveId: id) },
                    progressPollingEffect(state.downloading.filter {
                        !state.failedDownloads.contains($0.key) && !state.retryingDownloads.contains($0.key)
                    })
                )
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

    private func progressPollingEffect(_ downloading: [String: PageProgress]) -> Effect<Action> {
        guard !downloading.isEmpty else {
            return .cancel(id: CancelID.progressPolling)
        }
        return .run { send in
            var inProgress = downloading
            while !inProgress.isEmpty {
                let activeIDs = await service.activeCacheDownloadIDs()
                for (id, progress) in inProgress {
                    let cacheFolder = LANraragiService.cachePath!
                        .appendingPathComponent(id, conformingTo: .folder)
                    let downloadedPages = imageService.validStoredPageNumbers(
                        folderUrl: cacheFolder, totalPages: progress.total
                    ).count
                    if downloadedPages == progress.total && progress.total > 0 {
                        do {
                            _ = try database.updateCached(id)
                            await send(.removeItemFromDownloading(id))
                        } catch {
                            await send(.cacheDownloadFailed(id))
                            await send(.setErrorMessage(error.localizedDescription))
                        }
                        inProgress.removeValue(forKey: id)
                        continue
                    }
                    if downloadedPages != progress.current {
                        inProgress[id]?.current = downloadedPages
                        await send(.updateProgressInDownloading(id, downloadedPages))
                    }
                    if !activeIDs.contains(id) {
                        inProgress.removeValue(forKey: id)
                        await send(.cacheDownloadFailed(id))
                    }
                }
                guard !inProgress.isEmpty else {
                    return
                }
                try await clock.sleep(for: .seconds(2))
            }
        }
        .cancellable(id: CancelID.progressPolling, cancelInFlight: true)
    }
}

struct CacheView: View {
    @Environment(NavigationHelper.self) private var navigation

    let store: StoreOf<CacheFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(
                    store.scope(\.archives, action: \.grid),
                    id: \.state.id
                ) { gridStore in
                    let inProgress = store.downloading[gridStore.id] != nil
                    grid(gridStore: gridStore, inProgress: inProgress)
                }
            }
            .padding(.horizontal)
        }
        .task {
            await store.send(.load).finish()
        }
        .onChange(of: store.errorMessage) {
            if !store.errorMessage.isEmpty {
                showNotificationBanner(
                    title: String(localized: "error"),
                    subtitle: store.errorMessage,
                    style: .danger
                )
                store.send(.setErrorMessage(""))
            }
        }
    }

    private func contextMenu(
        gridStore: StoreOf<GridFeature>,
        inProgress: Bool
    ) -> some View {
        Group {
            Button {
                openReader(gridStore: gridStore, fromStart: true)
            } label: {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            .disabled(inProgress)
            Button {
                store.send(.removeCache(gridStore.state.id))
            } label: {
                Label("archive.cache.remove", systemImage: "trash")
            }
        }
    }

    private func openReader(gridStore: StoreOf<GridFeature>, fromStart: Bool = false) {
        let allArchives = store.archives.filter { store.downloading[$0.id] == nil }.map { $0.$archive }
        let readerStore = Store(
            initialState: ArchiveReaderFeature.State.init(
                currentArchiveId: gridStore.archive.id,
                allArchives: allArchives,
                fromStart: fromStart,
                cached: true
            )
        ) {
            ArchiveReaderFeature()
        }
        let readerController = UIArchiveReaderController(
            store: readerStore, navigationHelper: navigation
        )
        navigation.push(readerController)
    }

    private func grid(
        gridStore: StoreOf<GridFeature>,
        inProgress: Bool
    ) -> some View {
        return ArchiveGridV2(store: gridStore)
            .overlay {
                inProgress ?
                RoundedRectangle(cornerRadius: 8)
                    .foregroundStyle(Color.black.opacity(0.5))
                    .overlay {
                        downloadProgress(id: gridStore.id)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 10)
                    }
                : nil
            }
            .contextMenu {
                if !store.isSelecting {
                    contextMenu(gridStore: gridStore, inProgress: inProgress)
                }
            }
            .overlay(alignment: .topTrailing) {
                if store.isSelecting {
                    Image(systemName: store.selected.contains(gridStore.id) ? "checkmark.circle.fill" : "circle")
                        .font(.largeTitle)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAddTraits(store.selected.contains(gridStore.id) ? [.isSelected, .isButton] : .isButton)
            .onTapGesture {
                if store.isSelecting {
                    store.send(.toggleSelection(gridStore.id))
                } else if !inProgress {
                    openReader(gridStore: gridStore)
                }
            }
    }
    @ViewBuilder
    private func downloadProgress(id: String) -> some View {
        if let progress = store.downloading[id] {
            VStack(spacing: 8) {
                ProgressView(value: progress.total > 0 ? Double(progress.current) / Double(progress.total) : 0) {
                    EmptyView()
                } currentValueLabel: {
                    Text(String(format: "%d / %d", progress.current, progress.total))
                        .fontWeight(.bold)
                        .font(.caption)
                }
                .tint(.white)
                if store.failedDownloads.contains(id) {
                    Text("archive.cache.download.failed")
                        .font(.caption)
                    Button("settings.host.upload.retry") {
                        store.send(.retryCache(id))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSelecting)
                } else if store.retryingDownloads.contains(id) {
                    Text("archive.cache.retrying")
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
        }
    }

}

struct PageProgress: Equatable {
    var current: Int
    let total: Int
}
