import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer struct SearchFeature {
    private let logger = Logger(label: "SearchFeature")

    struct State: Equatable {
        @BindingState var keyword = ""
        var suggestedTag = [String]()
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
    }

    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case generateSuggestion
        case suggestionTapped(String)
        case searchSubmit(String)
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
                state.archiveList.filter = SearchFilter(category: nil, filter: keyword)
                return .none
            case .binding:
                return .none
            case .archiveList:
                return .none
            }
        }
    }
}

struct SearchViewV2: View {
    let store: StoreOf<SearchFeature>

    struct ViewState: Equatable {
        @BindingViewState var keyword: String
        let suggestedTag: [String]

        init(bindingViewStore: BindingViewStore<SearchFeature.State>) {
            self._keyword = bindingViewStore.$keyword
            self.suggestedTag = bindingViewStore.suggestedTag
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: \.archiveList))
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
            .onChange(of: viewStore.keyword) {
                viewStore.send(.generateSuggestion)
            }
        }
    }
}
