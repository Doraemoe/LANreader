//
// Created on 10/9/20.
//

import Foundation
import ComposableArchitecture

public struct SearchFilter: Equatable {
    let category: String?
    let filter: String?
}

enum TabName: String, CaseIterable, Identifiable {
    case library
    case category
    case search
    case settings
    var id: String { self.rawValue }
}

enum PageControl: String, CaseIterable, Identifiable {
    case next
    case previous
    case navigation

    var id: String { self.rawValue }
}

enum ReadDirection: String, CaseIterable, Identifiable {
    case upDown
    case rightLeft
    case leftRight

    var id: String { self.rawValue }
}

enum ArchiveListOrder: String, CaseIterable, Identifiable {
    case name
    case dateAdded
    case random

    var id: String { self.rawValue }
}

enum SearchSort: String, CaseIterable, Identifiable {
    case name = "title"
    case dateAdded = "date_added"
    case artist = "artist"
    case group = "group"
    case event = "event"
    case series = "series"
    case character = "character"
    case parody = "parody"
    case lastRead = "lastread"
    case custom = "custom"

    var id: String { self.rawValue }
}

enum SearchSortOrder: String, CaseIterable, Identifiable {
    case asc
    case desc

    var id: String { self.rawValue }
}

enum CompressThreshold: Int, CaseIterable, Identifiable {
    case never, one, two, three, four

    var id: Int { self.rawValue }
}

enum ArchiveSelectFor: Int, CaseIterable, Identifiable {
    case library, categoryStatic, categoryDynamic, search

    var id: Int { self.rawValue }
}

struct SettingsKey {
    static let lanraragiUrl = "settings.lanraragi.url"
    static let lanraragiApiKey = "settings.lanraragi.apiKey"
    static let serverProgress = "settings.lanraragi.serverProgress"

    static let tapLeftKey = "settings.read.tap.left"
    static let tapMiddleKey = "settings.read.tap.middle"
    static let tapRightKey = "settings.read.tap.right"
    static let readDirection = "settings.read.direction"
    static let showOriginal = "settings.read.image.showOriginal"
    static let fallbackReader = "settings.read.fallback"
    static let splitWideImage = "settings.read.split.Image"
    static let splitPiorityLeft = "settings.read.split.piorityLeft"
    static let autoPageInterval = "settings.read.auto.page.interval"
    static let doublePageLayout = "settings.read.double.page"

    static let searchSort = "settings.search.sort"
    static let searchSortCustom = "settings.search.sort.custom"
    static let searchSortOrder = "settings.search.sort.order"
    static let blurInterfaceWhenInactive = "settings.view.blur.inactive"
    static let enablePasscode = "settings.view.passcode.enable"
    static let passcode = "settings.view.passcode"
    static let hideRead = "settings.view.hideRead"

    static let lastTagRefresh = "lastTagRefresh"
    static let tabBarHidden = "tab.bar.hidden"
}

extension Double {
    var int: Int {
        get { Int(self) }
        set { self = Double(newValue) }
    }
}

extension PersistenceReaderKey where Self == InMemoryKey<IdentifiedArrayOf<CategoryItem>> {
  static var category: Self {
    inMemory("category")
  }
}

extension PersistenceReaderKey where Self == InMemoryKey<IdentifiedArrayOf<ArchiveItem>> {
  static var archive: Self {
    inMemory("archive")
  }
}
