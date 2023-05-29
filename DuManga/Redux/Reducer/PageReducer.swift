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
        if state.archivePages[id] == nil {
            state.archivePages[id] = PublishedState(wrappedValue: pages)
        } else {
            state.archivePages[id]!.wrappedValue = pages
        }
    case let .updateLoadingProgress(id, progress):
        if progress == nil {
            state.loadingProgress.removeValue(forKey: id)
        } else if state.loadingProgress[id] == nil {
            state.loadingProgress[id] = PublishedState(wrappedValue: progress!)
        } else {
            state.loadingProgress[id]!.wrappedValue = progress!
        }
    case let .error(error):
        state.loading = false
        state.errorCode = error
    case .resetState:
        state.errorCode = nil
    }
}
