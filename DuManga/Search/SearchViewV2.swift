import ComposableArchitecture
import SwiftUI
import NotificationBannerSwift
import Logging

struct SearchFeature: Reducer {
    private let logger = Logger(label: "SearchFeature")

    struct State: Equatable {
        @BindingState var keyword = ""
        var errorMessage = ""
        var archiveList = ArchiveListFeature.State()
        //        var path = StackState<Path.State>()
    }
    enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case searchSubmit
        case search(String, String, String, String, Bool)
        case populateArchives([ArchiveItem], Int, Bool)
        case setError(String)
        case archiveList(ArchiveListFeature.Action)
        //        case path(StackAction<Path.State, Path.Action>)
    }

    @Dependency(\.lanraragiService) var service

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .searchSubmit:
                let keyword = state.keyword
                let sortby = UserDefaults.standard.string(forKey: SettingsKey.searchSort) ?? "date_added"
                let order = sortby == "name" ? "asc" : "desc"
                return .run { send in
                    await send(.search(keyword, sortby, "0", order, false))
                }
            case let .search(keyword, sortby, start, order, append):
                guard state.archiveList.loading == false else {
                    return .none
                }
                state.archiveList.loading = true
                if append == false {
                    state.archiveList.archives = .init()
                }
                return .run { send in
                    do {
                        let response = try await service.searchArchive(filter: keyword, start: start, sortby: sortby, order: order).value
                        let archives = response.data.map {
                            $0.toArchiveItem()
                        }
                        await send(.populateArchives(archives, response.recordsFiltered, append))
                    } catch {
                        logger.error("failed to search archive. keyword=\(keyword) \(error)")
                        await send(.setError(error.localizedDescription))
                    }

                }
            case let .populateArchives(archives, total, append):
                if append {
                    state.archiveList.archives.append(contentsOf: archives)
                } else {
                    state.archiveList.archives = archives
                }
                state.archiveList.total = total
                state.archiveList.loading = false
                return .none
            case let .setError(message):
                state.errorMessage = message
                return .none
            case .binding:
                return .none
            case let .archiveList(.appendArchives(start)):
                let keyword = state.keyword
                let sortby = UserDefaults.standard.string(forKey: SettingsKey.searchSort) ?? "date_added"
                let order = sortby == SearchSort.name.rawValue ? "asc" : "desc"
                return .run { send in
                    await send(.search(keyword, sortby, start, order, true))
                }
            }
            //            case .path:
            //                return .none
        }
        //        .forEach(\.path, action: /Action.path) {
        //            Path()
        //        }
    }

    //    struct Path: Reducer {
    //        enum State: Equatable {
    //            case lanraragiSettings(LANraragiConfigFeature.State = .init())
    //            case upload(UploadFeature.State = .init())
    //            case log(LogFeature.State = .init())
    //        }
    //        enum Action: Equatable {
    //            case lanraragiSettings(LANraragiConfigFeature.Action)
    //            case upload(UploadFeature.Action)
    //            case log(LogFeature.Action)
    //        }
    //        var body: some ReducerOf<Self> {
    //            Scope(state: /State.lanraragiSettings, action: /Action.lanraragiSettings) {
    //                LANraragiConfigFeature()
    //            }
    //            Scope(state: /State.upload, action: /Action.upload) {
    //                UploadFeature()
    //            }
    //            Scope(state: /State.log, action: /Action.log) {
    //                LogFeature()
    //            }
    //        }
    //    }
}

struct SearchViewV2: View {
    @AppStorage(SettingsKey.searchSort) var searchSort: String = SearchSort.dateAdded.rawValue

    let store: StoreOf<SearchFeature>

    struct ViewState: Equatable {
        @BindingViewState var keyword: String
        let errorMessage: String

        init(bindingViewStore: BindingViewStore<SearchFeature.State>) {
            self._keyword = bindingViewStore.$keyword
            self.errorMessage = bindingViewStore.errorMessage
        }
    }

    var body: some View {
        WithViewStore(self.store, observe: ViewState.init) { viewStore in
            ArchiveListV2(store: store.scope(state: \.archiveList, action: {
                .archiveList($0)
            }))
            .searchable(text: viewStore.$keyword, placement: .navigationBarDrawer(displayMode: .always))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) {
                viewStore.send(.searchSubmit)
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
                viewStore.send(.searchSubmit)
            }

        }
    }
}
