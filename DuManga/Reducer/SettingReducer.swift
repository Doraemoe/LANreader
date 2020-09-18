//
// Created on 9/9/20.
//

import Foundation
import Combine

// swiftlint:disable cyclomatic_complexity
func settingReducer(state: inout SettingState, action: SettingAction) {
    switch action {
            // server
    case let .saveLanraragiConfigToStore(url, apiKey):
        state.url = url
        state.apiKey = apiKey
        state.savedSuccess = true
    case let .error(errorCode):
        state.errorCode = errorCode
    case .resetState:
        state.savedSuccess = false
        state.errorCode = nil
            // tap
    case let .setTapLeftControlToStore(control):
        state.tapLeft = control
    case let .setTapMiddleControlToStore(control):
        state.tapMiddle = control
    case let .setTapRightControlToStore(control):
        state.tapRight = control
            // swipe
    case let .setSwipeLeftControlToStore(control):
        state.swipeLeft = control
    case let .setSwipeRightControlToStore(control):
        state.swipeRight = control
            // split
    case let .setSplitPageToStore(split):
        state.splitPage = split
    case let .setSplitPagePriorityLeftToStore(priorityLeft):
        state.splitPagePriorityLeft = priorityLeft
            // view
    case let .setArchiveListRandomToStore(archiveListRandom):
        state.archiveListRandom = archiveListRandom
    case let .setUseListViewToStore(useListView):
        state.useListView = useListView
    default:
        break
    }
}
