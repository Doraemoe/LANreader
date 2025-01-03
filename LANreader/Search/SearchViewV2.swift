import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

@Reducer public struct SearchFeature {
    private let logger = Logger(label: "SearchFeature")

    @ObservableState
    public struct State: Equatable {
        var keyword = ""
        var suggestedTag = [String]()
        var archiveList = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case generateSuggestion(String)
        case suggestionTapped(String)
        case searchSubmit(String)
        case archiveList(ArchiveListFeature.Action)
    }

    @Dependency(\.lanraragiService) var service
    @Dependency(\.appDatabase) var database

    public enum CancelId { case search }

    public var body: some ReducerOf<Self> {

        Scope(state: \.archiveList, action: \.archiveList) {
            ArchiveListFeature()
        }

        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .generateSuggestion(searchText):
                let lastToken = searchText.split(
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
                guard !keyword.isEmpty else {
                    return .none
                }
//                state.suggestedTag = []
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
    @Bindable var store: StoreOf<SearchFeature>

    var body: some View {
            ArchiveListV2(store: store.scope(state: \.archiveList, action: \.archiveList))
            .searchable(text: $store.keyword, placement: .navigationBarDrawer(displayMode: .always))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .searchSuggestions {
                ForEach(store.suggestedTag, id: \.self) { tag in
                    HStack {
                        Text(tag)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.suggestionTapped(tag))
                    }
                }
            }
            .onSubmit(of: .search) {
                store.send(.searchSubmit(store.keyword))
            }
            .navigationTitle("search")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: store.keyword) {
                store.send(.generateSuggestion(""))
            }
    }
}
