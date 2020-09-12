//
// Created on 9/9/20.
//

import Foundation

struct SettingState {
    var url: String
    var apiKey: String
    var errorCode: ErrorCode?
    var savedSuccess: Bool
    var tapLeft: PageControl
    var tapMiddle: PageControl
    var tapRight: PageControl
    var swipeLeft: PageControl
    var swipeRight: PageControl
    var splitPage: Bool
    var splitPagePriorityLeft: Bool
    var archiveListRandom: Bool
    var useListView: Bool

    init() {
        // server
        self.url = UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: SettingsKey.lanraragiApiKey) ?? ""
        self.errorCode = nil
        self.savedSuccess = false
        // tap
        self.tapLeft = PageControl(rawValue: UserDefaults.standard.string(forKey: SettingsKey.tapLeftKey) ?? PageControl.next.rawValue)!
        self.tapMiddle = PageControl(rawValue: UserDefaults.standard.string(forKey: SettingsKey.tapMiddleKey) ?? PageControl.navigation.rawValue)!
        self.tapRight = PageControl(rawValue: UserDefaults.standard.string(forKey: SettingsKey.tapRightKey) ?? PageControl.previous.rawValue)!
        // swipe
        self.swipeLeft = PageControl(rawValue: UserDefaults.standard.string(forKey: SettingsKey.swipeLeftKey) ?? PageControl.next.rawValue)!
        self.swipeRight = PageControl(rawValue: UserDefaults.standard.string(forKey: SettingsKey.swipeRightKey) ?? PageControl.previous.rawValue)!
        // split
        self.splitPage = UserDefaults.standard.bool(forKey: SettingsKey.splitPage)
        self.splitPagePriorityLeft = UserDefaults.standard.bool(forKey: SettingsKey.splitPagePriorityLeft)
        // view
        self.archiveListRandom = UserDefaults.standard.bool(forKey: SettingsKey.archiveListRandom)
        self.useListView = UserDefaults.standard.bool(forKey: SettingsKey.useListView)
    }
}
