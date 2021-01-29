//
// Created on 7/10/20.
//

import SwiftUI
import Combine

class ContentViewModel: ObservableObject {
    @Published var editMode = EditMode.inactive
    @Published var tabName: String = "library"
    @Published var notLoggedIn: Bool = (UserDefaults.standard.string(forKey: SettingsKey.lanraragiUrl) ?? "").isEmpty ?
        true : false
}
