import Foundation

func triggerReducer(state: inout TriggerState, action: TriggerAction) {
    switch action {
    case let .thumbnailRefreshAction(id):
        state.thumbnailId = id
    case let .pageRefreshAction(id):
        state.pageId = id
    }
}