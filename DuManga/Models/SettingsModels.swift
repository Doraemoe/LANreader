//Created 29/8/20

import Foundation

enum PageControl: String, CaseIterable, Identifiable {
    case next
    case previous
    case navigation
    
    var id: String { self.rawValue }
}

struct SettingsKey {
    static let lanraragiUrl = "settings.lanraragi.url"
    static let lanraragiApiKey = "settings.lanraragi.apiKey"
    static let tapLeftKey = "settings.read.tap.left"
    static let tapMiddleKey = "settings.read.tap.middle"
    static let tapRightKey = "settings.read.tap.right"
    static let swipeLeftKey = "settings.read.swipe.left"
    static let swipeRightKey = "settings.read.swipe.right"
    static let splitPage = "settings.read.split.page"
    static let splitPagePriorityLeft = "settings.read.split.page.priority.left"
    static let archiveListRandom = "settings.archive.list.random"
    static let useListView = "settings.view.use.list"
}
