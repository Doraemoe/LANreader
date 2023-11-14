import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer struct SearchFeature {
    private let logger = Logger(label: "SearchFeature")

    struct State: Equatable {
        var path = StackState<AppFeature.Path.State>()

        @BindingState var keyword = ""
        var confirmedKeyword = ""
        var suggestedTag = [String]()
        var errorMessage = ""
        var archiveList = ArchiveListFeature.State()
    }

    enum Action: Equatable, BindableAction {
        case path(StackAction<AppFeature.Path.State, AppFeature.Path.Action>)

        case binding(BindingAction<State>)
        case generateSuggestion
        case suggestionTapped(String)
        case searchSubmit(String)
        case search(String, String, String, String, Bool)
        case cancelSearch
        case populateArchives([ArchiveItem], Int)
        case setError(String)
        case archiveList(ArchiveListFeature.Action)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database
    @Dependency(\.userDefaultService) var userDefault

    enum CancelId { case search }

    var body: some ReducerOf<Self> {

        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        BindingReducer()
        Reduce { state, action in
            switch action {
            case .generateSuggestion:
                let lastToken = state.keyword.split(
                    separator: " ",
                    omittingEmptySubsequences: false
                ).last.map(String.init) ?? ""
                guard !lastToken.isEmpty else {
                    state.suggestedTag = .init()
                    return .none
                }
                do {
                    let result = try database.searchTag(keyword: lastToken)
                    state.suggestedTag = result.map {
                        $0.tag
                    }
                } catch {
                    state.suggestedTag = .init()
                }
                return .none
            case let .suggestionTapped(tag):
                let validKeyword = state.keyword.split(separator: " ").dropLast(1).joined(separator: " ")
                state.keyword = "\(validKeyword) \(tag)$,"
                return .none
            case let .searchSubmit(keyword):
                guard !state.keyword.isEmpty else {
                    return .none
                }
                state.suggestedTag = []
                state.confirmedKeyword = keyword
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                let loading = state.archiveList.loading
                return .run { send in
                    if loading {
                        await send(.cancelSearch)
                    }
                    await send(.search(keyword, sortby, "0", order, false))
                }
            case let .search(keyword, sortby, start, order, append):
                state.archiveList.loading = true
                if !append {
                    state.archiveList.archives = .init()
                    state.archiveList.total = 0
                }
                return .run { send in
                    do {
                        let response = try await service.searchArchive(
                            filter: keyword,
                            start: start,
                            sortby: sortby,
                            order: order
                        ).value
                        let archives = response.data.map {
                            $0.toArchiveItem()
                        }
                        await send(.populateArchives(archives, response.recordsFiltered))
                    } catch {
                        logger.error("failed to search archive. keyword=\(keyword) \(error)")
                        await send(.setError(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelId.search)
            case .cancelSearch:
                state.archiveList.loading = false
                return .cancel(id: CancelId.search)
            case let .populateArchives(archives, total):
                let gridFeatureState = archives.map { item in
                    GridFeature.State(archive: item)
                }
                state.archiveList.archives.append(contentsOf: gridFeatureState)
                state.archiveList.total = total
                state.archiveList.loading = false
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            case .binding:
                return .none
            case let .archiveList(.appendArchives(start)):
                let keyword = state.confirmedKeyword
                let sortby = userDefault.searchSort
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return .run { send in
                    await send(.search(keyword, sortby, start, order, true))
                }
            default:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            AppFeature.Path()
        }
    }
}

struct SearchViewV2: View {
    @AppStorage(SettingsKey.searchSort) var searchSort: String = SearchSort.dateAdded.rawValue

    let store: StoreOf<SearchFeature>

    struct ViewState: Equatable {
        @BindingViewState var keyword: String
        let suggestedTag: [String]
        let errorMessage: String

        init(bindingViewStore: BindingViewStore<SearchFeature.State>) {
            self._keyword = bindingViewStore.$keyword
            self.suggestedTag = bindingViewStore.suggestedTag
            self.errorMessage = bindingViewStore.errorMessage
        }
    }

    var body: some View {
        NavigationStackStore(
            self.store.scope(state: \.path, action: { .path($0) })
        ) {
            WithViewStore(self.store, observe: ViewState.init) { viewStore in
                ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                    .archiveList($0)
                }))
                .searchable(text: viewStore.$keyword, placement: .navigationBarDrawer(displayMode: .always))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .searchSuggestions {
                    ForEach(viewStore.suggestedTag, id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewStore.send(.suggestionTapped(tag))
                        }
                    }
                }
                .onSubmit(of: .search) {
                    viewStore.send(.searchSubmit(viewStore.keyword))
                }
                .navigationTitle("search")
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: viewStore.errorMessage) {
                    if !viewStore.errorMessage.isEmpty {
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                        subtitle: viewStore.errorMessage,
                                                        style: .danger)
                        banner.show()
                        viewStore.send(.setError(""))
                    }
                }
                .onChange(of: self.searchSort) {
                    viewStore.send(.searchSubmit(viewStore.keyword))
                }
                .onChange(of: viewStore.keyword) {
                    viewStore.send(.generateSuggestion)
                }
            }
        } destination: {state in
            switch state {
            case .reader:
                CaseLet(
                    /AppFeature.Path.State.reader,
                     action: AppFeature.Path.Action.reader,
                     then: ArchiveReader.init(store:)
                )
            case .categoryArchiveList:
                CaseLet(
                    /AppFeature.Path.State.categoryArchiveList,
                     action: AppFeature.Path.Action.categoryArchiveList,
                     then: CategoryArchiveListV2.init(store:)
                )
            }
        }
    }
}
