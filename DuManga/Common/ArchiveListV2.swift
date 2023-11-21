import ComposableArchitecture
import OrderedCollections
import SwiftUI
import Combine
import Logging
import NotificationBannerSwift

@Reducer struct ArchiveListFeature {
    private let logger = Logger(label: "ArchiveListFeature")
    struct State: Equatable {
        var filter: SearchFilter
        var loadOnAppear = true
        var archives: IdentifiedArrayOf<GridFeature.State> = []
        var loading: Bool = false
        var showLoading: Bool = false
        var total: Int = 0
        var errorMessage = ""

        var hideReadArchives: IdentifiedArrayOf<GridFeature.State> {
            let result = archives.filter {
                $0.archive.pagecount != $0.archive.progress
            }
            return IdentifiedArray(uniqueElements: result)
        }
    }

    enum Action: Equatable {
        case grid(IdentifiedActionOf<GridFeature>)
        case setFilter(SearchFilter)
        case resetArchives
        case load(Bool)
        case populateArchives([ArchiveItem], Int, Bool)
        case subscribeThumbnailTrigger
        case subscribeProgressTrigger
        case refreshThumbnail(String)
        case updateArchiveProgress(String, Int)
        case appendArchives(String)
        case setErrorMessage(String)
        case cancelSearch
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.refreshTrigger) var refreshTrigger
    @Dependency(\.userDefaultService) var userDefault

    enum CancelId { case search }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .subscribeThumbnailTrigger:
                return .run { send in
                    for await archiveId in refreshTrigger.thumbnail.values {
                        await send(.refreshThumbnail(archiveId))
                    }
                }
            case .subscribeProgressTrigger:
                return .run { send in
                    for await (archiveId, progress) in refreshTrigger.progress.values {
                        await send(.updateArchiveProgress(archiveId, progress))
                    }
                }
            case let .setFilter(filter):
                state.filter = filter
                return .none
            case .resetArchives:
                state.archives = .init()
                return .none
            case let .load(showLoading):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = showLoading
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return self.search(
                    state: &state, searchFilter: state.filter, sortby: sortby, start: "0", order: order, append: false
                )
            case let .appendArchives(start):
                guard state.loading == false else {
                    return .none
                }
                state.loading = true
                state.showLoading = true
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return self.search(
                    state: &state, searchFilter: state.filter, sortby: sortby, start: start, order: order, append: true
                )
            case let .populateArchives(archives, total, append):
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: item)
                }
                if !append {
                    state.archives = .init()
                    state.total = 0
                }
                state.archives.append(contentsOf: gridFeatureState)
                state.total = total
                state.loading = false
                state.showLoading = false
                return .none
            case let .refreshThumbnail(archiveId):
                if state.archives.contains(where: { $0.id == archiveId }) {
                    return .send(.grid(.element(id: archiveId, action: .load(true))))
                } else {
                    return .none
                }
            case let .updateArchiveProgress(archiveId, progress):
                state.archives[id: archiveId]?.archive.progress = progress
                if progress > 1 && state.archives[id: archiveId]?.archive.isNew == true {
                    state.archives[id: archiveId]?.archive.isNew = false
                }
                return .none
            case let .setErrorMessage(message):
                state.loading = false
                state.showLoading = false
                state.errorMessage = message
                return .none
            case .grid:
                return .none
            case .cancelSearch:
                if state.loading {
                    state.loading = false
                    state.showLoading = false
                    return .cancel(id: CancelId.search)
                }
                return .none
            }
        }
        .forEach(\.archives, action: \.grid) {
            GridFeature()
        }
    }

    // swiftlint:disable function_parameter_count
    func search(
        state: inout State, searchFilter: SearchFilter, sortby: String, start: String, order: String, append: Bool
    ) -> Effect<Action> {
        return .run { send in
            do {
                let response = try await service.searchArchive(
                    category: searchFilter.category,
                    filter: searchFilter.filter,
                    start: start,
                    sortby: sortby,
                    order: order
                ).value
                let archives = response.data.map {
                    $0.toArchiveItem()
                }
                await send(.populateArchives(archives, response.recordsFiltered, append))
            } catch {
                logger.error("failed to load archives. \(error)")
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
        .cancellable(id: CancelId.search)
    }
    // swiftlint:enable function_parameter_count

}

struct ArchiveListV2: View {
    @AppStorage(SettingsKey.hideRead) var hideRead: Bool = false
    @AppStorage(SettingsKey.lanraragiUrl) var lanraragiUrl: String = ""
    @AppStorage(SettingsKey.searchSort) var searchSort: String = SearchSort.dateAdded.rawValue

    let store: StoreOf<ArchiveListFeature>

    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]

    struct ArchiveListViewState: Equatable {
        let filter: SearchFilter
        let archives: IdentifiedArrayOf<GridFeature.State>
        let total: Int
        let showLoading: Bool
        let loadOnAppear: Bool
        let errorMessage: String
        init(state: ArchiveListFeature.State) {
            self.filter = state.filter
            self.archives = state.archives
            self.total = state.total
            self.showLoading = state.showLoading
            self.loadOnAppear = state.loadOnAppear
            self.errorMessage = state.errorMessage
        }
    }

    struct GridViewState: Equatable {
        let archive: ArchiveItem
        init(state: GridFeature.State) {
            self.archive = state.archive
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ArchiveListViewState.init) { viewStore in
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEachStore(
                        self.store.scope(state: hideRead ? \.hideReadArchives : \.archives, action: { .grid($0) })
                    ) { gridStore in
                        WithViewStore(gridStore, observe: GridViewState.init) { gridViewStore in
                            NavigationLink(
                                state: AppFeature.Path.State.reader(
                                    ArchiveReaderFeature.State.init(
                                        archive: gridViewStore.archive
                                    )
                                )
                            ) {
                                ArchiveGridV2(store: gridStore)
                                    .onAppear {
                                        if gridViewStore.archive.id == viewStore.archives.last?.archive.id &&
                                            viewStore.archives.count < viewStore.total {
                                            viewStore.send(.appendArchives(String(viewStore.archives.count)))
                                        }
                                    }
                                    .contextMenu {
                                        contextMenu(gridViewStore: gridViewStore)
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                if viewStore.showLoading {
                    ProgressView("loading")
                }
            }
            .onAppear {
                viewStore.send(.subscribeThumbnailTrigger)
                viewStore.send(.subscribeProgressTrigger)
                if lanraragiUrl.isEmpty == false &&
                    viewStore.archives.isEmpty && viewStore.loadOnAppear {
                    viewStore.send(.load(true))
                }
            }
            .refreshable {
                await viewStore.send(.load(false)).finish()
            }
            .onChange(of: self.searchSort) {
                viewStore.send(.cancelSearch)
                viewStore.send(.resetArchives)
                viewStore.send(.load(true))
            }
            .onChange(of: viewStore.filter) {
                viewStore.send(.cancelSearch)
                viewStore.send(.resetArchives)
                viewStore.send(.load(true))
            }
            .onChange(of: lanraragiUrl, {
                if lanraragiUrl.isEmpty == false {
                    viewStore.send(.cancelSearch)
                    viewStore.send(.resetArchives)
                    viewStore.send(.load(true))
                }
            })
            .onChange(of: viewStore.errorMessage) {
                if !viewStore.errorMessage.isEmpty {
                    let banner = NotificationBanner(
                        title: NSLocalizedString("error", comment: "error"),
                        subtitle: viewStore.errorMessage,
                        style: .danger
                    )
                    banner.show()
                    viewStore.send(.setErrorMessage(""))
                }
            }
        }
    }

    private func contextMenu(gridViewStore: ViewStore<ArchiveListV2.GridViewState, GridFeature.Action>) -> some View {
        Group {
            NavigationLink(
                state: AppFeature.Path.State.reader(
                    ArchiveReaderFeature.State.init(
                        archive: gridViewStore.archive,
                        fromStart: true
                    )
                )
            ) {
                Label("archive.read.fromStart", systemImage: "arrow.left.to.line.compact")
            }
            Button(action: {
                gridViewStore.send(.load(true))
            }, label: {
                Label("archive.reload.thumbnail", systemImage: "arrow.clockwise")
            })
        }
    }
}

struct RefreshTrigger {
    var thumbnail = PassthroughSubject<String, Never>()
    var progress = PassthroughSubject<(String, Int), Never>()
}

private enum RefreshTriggerKey: DependencyKey {
    static let liveValue = RefreshTrigger()
    static let testValue = RefreshTrigger()
}

extension DependencyValues {
    var refreshTrigger: RefreshTrigger {
        get { self[RefreshTriggerKey.self] }
        set { self[RefreshTriggerKey.self] = newValue }
    }
}
