import ComposableArchitecture
import Logging

@Reducer struct TriggerFeature {
    struct State: Equatable {
        var thumbnailId = ""
        var pageId = ""
        var deletedArchiveId = ""
    }

    enum Action: Equatable {
        case thumbnailRefreshAction(String)
        case pageRefreshAction(String)
        case archiveDeleteAction(String)
     }

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .thumbnailRefreshAction(id):
            state.thumbnailId = id
            return .none
        case let .pageRefreshAction(id):
            state.pageId = id
            return .none
        case let .archiveDeleteAction(id):
            state.deletedArchiveId = id
            return .none
        }
    }
}
