//
// Created on 3/10/20.
//

import Foundation

func pageReducer(state: inout PageState, action: PageAction) {
    switch action {
    case .extractArchive:
        state.loading = true
    case let .extractArchiveSuccess(id, pages):
        state.loading = false
        state.archivePages[id] = pages
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
    }
}
