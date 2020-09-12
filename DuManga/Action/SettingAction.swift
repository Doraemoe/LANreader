//
// Created on 9/9/20.
//

import Foundation

enum SettingAction {
    // server
    case saveLanraragiConfigToStore(url: String, apiKey: String)
    case saveLanraragiConfigToUserDefaults(url: String, apiKey: String)
    case verifyAndSaveLanraragiConfig(url: String, apiKey: String)
    case error(errorCode: ErrorCode)
    case resetState

    // tap
    case saveTapLeftControlToUserDefaults(control: PageControl)
    case saveTapMiddleControlToUserDefaults(control: PageControl)
    case saveTapRightControlToUserDefaults(control: PageControl)
    case setTapLeftControlToStore(control: PageControl)
    case setTapMiddleControlToStore(control: PageControl)
    case setTapRightControlToStore(control: PageControl)

    // swipe
    case saveSwipeLeftControlToUserDefaults(control: PageControl)
    case saveSwipeRightControlToUserDefaults(control: PageControl)
    case setSwipeLeftControlToStore(control: PageControl)
    case setSwipeRightControlToStore(control: PageControl)

    // split
    case saveSplitPageToUserDefaults(split: Bool)
    case saveSplitPagePriorityLeftToUserDefaults(priorityLeft: Bool)
    case setSplitPageToStore(split: Bool)
    case setSplitPagePriorityLeftToStore(priorityLeft: Bool)

    //view
    case saveArchiveListRandomToUserDefaults(archiveListRandom: Bool)
    case saveUseListViewToUserDefaults(useListView: Bool)
    case setArchiveListRandomToStore(archiveListRandom: Bool)
    case setUseListViewToStore(useListView: Bool)

}
