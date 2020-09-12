//
// Created on 9/9/20.
//

import Foundation

struct AppState {
    var setting: SettingState
    var category: CategoryState

    init() {
        self.setting = SettingState()
        self.category = CategoryState()
    }
}
