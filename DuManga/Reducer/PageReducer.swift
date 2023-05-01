//
// Created on 3/10/20.
//

import Foundation

func pageReducer(state: inout PageState, action: PageAction) {
    switch action {
    case .startExtractArchive:
        state.loading = true
    case .finishExtractArchive:
        state.loading = false
    case let .storeExtractedArchive(id, pages):
        state.archivePages[id] = pages
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
    }
}
