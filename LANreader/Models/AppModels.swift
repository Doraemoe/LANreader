//
// Created on 10/9/20.
//

import Foundation
import Sharing
import IdentifiedCollections

public struct SearchFilter: Equatable, Sendable {
    let category: String?
    let filter: String?
}

public struct TagWithType: Equatable, Sendable {
    let tag: String
    let type: TagType
}

enum TagType: Sendable {
    case suggested
    case popular
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

public enum ReaderPageLayoutMode: String, CaseIterable, Sendable {
    case single
    case double
    case automatic

    init(automatic: Bool, double: Bool) {
        self = automatic ? .automatic : (double ? .double : .single)
    }

    /// Choosing single or double also becomes the manual preference that applies when automatic is off.
    func save(automatic: Shared<Bool>, double: Shared<Bool>) {
        automatic.withLock { $0 = self == .automatic }
        if self != .automatic {
            double.withLock { $0 = self == .double }
        }
    }

    var localizationKey: String { "settings.read.layout.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .single: "rectangle.portrait.fill"
        case .double: "rectangle.split.2x1.fill"
        case .automatic: "rectangle.2.swap"
        }
    }
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
    case random = "random"

    var id: String { self.rawValue }
}

enum SearchSortOrder: String, CaseIterable, Identifiable {
    case asc
    case desc

    var id: String { self.rawValue }
}

struct SettingsKey {
    static let lanraragiUrl = "settings:lanraragi:url"
    static let lanraragiApiKey = "settings:lanraragi:apiKey"
    static let serverProgress = "settings:lanraragi:serverProgress"

    static let tapLeftKey = "settings:read:tap:left"
    static let tapMiddleKey = "settings:read:tap:middle"
    static let tapRightKey = "settings:read:tap:right"
    static let readDirection = "settings:read:direction"
    static let disablePageFlipAnimation = "settings:read:disable:page:flip:animation"
    static let splitWideImage = "settings:read:split:Image"
    static let splitPiorityLeft = "settings:read:split:piorityLeft"
    static let autoPageInterval = "settings:read:auto:page:interval"
    static let doublePageLayout = "settings:read:double:page"
    static let automaticPageLayout = "settings:read:automatic:page:layout"
    static let fitPageWidth = "settings:read:fit:page:width"
    static let showStamps = "settings:read:show:stamps"
    static let restartFinished = "settings:read:restart:finished"

    static let searchSort = "settings:search:sort"
    static let searchSortCustom = "settings:search:sort:custom"
    static let searchSortOrder = "settings:search:sort:order"
    static let blurInterfaceWhenInactive = "settings:view:blur:inactive"
    static let passcode = "settings:view:passcode"
    static let hideRead = "settings:view:hideRead"
    static let paginateArchiveList = "settings:view:paginate"

    static let lastTagRefresh = "lastTagRefresh"

    static let translationUrl = "settings:advanced:translation:url"
    static let translationEnabled = "settings:advanced:translation:enabled"
    static let translationService = "settings:advanced:translation:service"
    static let translationTarget = "settings:advanced:translation:target"
    static let translationUnclipRatio = "settings:advanced:translation:unclipRatio"
    static let translationBoxThreshold = "settings:advanced:translation:boxThreshold"
    static let translationMaskDilationOffset = "settings:advanced:translation:maskDilationOffset"
    static let translationDetectionResolution = "settings:advanced:translation:detectionResolution"
    static let translationTextDetector = "settings:advanced:translation:textDetector"
    static let translationRenderTextDirection = "settings:advanced:translation:renderTextDirection"
    static let translationInpaintingSize = "settings:advanced:translation:inpaintingSize"
    static let translationInpainter = "settings:advanced:translation:inpainter"
}

extension SharedReaderKey where Self == InMemoryKey<IdentifiedArrayOf<CategoryItem>> {
  static var category: Self {
    inMemory("category")
  }
}

extension SharedReaderKey where Self == InMemoryKey<IdentifiedArrayOf<ArchiveItem>> {
  static var archive: Self {
    inMemory("archive")
  }
}
