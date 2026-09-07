import SwiftUI
import ComposableArchitecture
import NotificationBannerSwift

@Reducer public struct CacheFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var downloading: [String: PageProgress] = [:]
        var errorMessage: String = ""
        var isSelecting = false
        var selected: Set<String> = []
    }

    public enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case load
        case removeItemFromDownloading(String)
        case updateProgressInDownloading(String, Int)
        case removeCache(String)
        case toggleSelectionMode
        case toggleSelection(String)
        case removeSelected
        case setErrorMessage(String)
    }

    private enum CancelID {
        case progressPolling
    }

    @Dependency(\.appDatabase) var database
    @Dependency(\.continuousClock) var clock

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
                return progressPollingEffect(downloading)
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
                state.selected.remove(id)
                state.downloading.removeValue(forKey: id)
                let cacheFolder = LANraragiService.cachePath!
                    .appendingPathComponent(id, conformingTo: .folder)
                try? FileManager.default.removeItem(at: cacheFolder)
                return progressPollingEffect(state.downloading)
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
                for (id, progress) in inProgress {
                    let cacheFolder = LANraragiService.cachePath!
                        .appendingPathComponent(id, conformingTo: .folder)
                    guard let content = try? FileManager.default.contentsOfDirectory(
                        at: cacheFolder, includingPropertiesForKeys: []
                    ) else {
                        continue
                    }
                    let downloadedPages = Set(content.compactMap { url -> Int? in
                        guard !url.hasDirectoryPath,
                              let pageNumber = Int(url.deletingPathExtension().lastPathComponent),
                              pageNumber > 0,
                              pageNumber <= progress.total else {
                            return nil
                        }
                        return pageNumber
                    }).count
                    if downloadedPages >= progress.total {
                        inProgress.removeValue(forKey: id)
                        _ = try? database.updateCached(id)
                        await send(.removeItemFromDownloading(id))
                    } else if downloadedPages != progress.current {
                        inProgress[id]?.current = downloadedPages
                        await send(.updateProgressInDownloading(id, downloadedPages))
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
    @State private var confirmingRemoval = false

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
        .safeAreaInset(edge: .bottom) {
            if store.isSelecting {
                HStack {
                    Text(String(format: String(localized: "archive.selected"), store.selected.count))
                    Spacer()
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        Label("archive.cache.remove", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.selected.isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
        .confirmationDialog("archive.selected.delete", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("archive.cache.remove", role: .destructive) {
                store.send(.removeSelected)
            }
        }
        .task {
            await store.send(.load).finish()
        }
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
        let allArchives = store.archives.map { $0.$archive }
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
        let progress = if let progressItem = store.downloading[gridStore.state.id] {
            progressItem.total > 0
                ? Double(progressItem.current) / Double(progressItem.total)
                : 0
        } else {
            0.0
        }
        return ArchiveGridV2(store: gridStore)
            .overlay {
                inProgress ?
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
                        .font(.title2)
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
}

struct PageProgress: Equatable {
    var current: Int
    let total: Int
}
