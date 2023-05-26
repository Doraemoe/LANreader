//
// Created on 10/9/20.
//

import Foundation

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

enum CompressThreshold: Int, CaseIterable, Identifiable {
    case never, one, two, three, four

    var id: Int { self.rawValue }
}

struct SettingsKey {
    static let lanraragiUrl = "settings.lanraragi.url"
    static let lanraragiApiKey = "settings.lanraragi.apiKey"

    static let tapLeftKey = "settings.read.tap.left"
    static let tapMiddleKey = "settings.read.tap.middle"
    static let tapRightKey = "settings.read.tap.right"
    static let readDirection = "settings.read.direction"
    static let compressImageThreshold = "settings.read.image.compress.threshold"

    static let archiveListOrder = "settings.archive.list.order"
    static let useListView = "settings.view.use.list"
    static let blurInterfaceWhenInactive = "settings.view.blur.inactive"
    static let enablePasscode = "settings.view.passcode.enable"
    static let passcode = "settings.view.passcode"
    static let hideRead = "settings.view.hideRead"

    static let alwaysLoadFromServer = "settings.host.alwaysLoad"
}

struct ErrorCode: Equatable {

    static func == (lhs: ErrorCode, rhs: ErrorCode) -> Bool {
        lhs.name == rhs.name
                && lhs.code == rhs.code
    }

    let name: String
    let code: Int

    private init(name: String, code: Int) {
        self.name = name
        self.code = code
    }

    static let lanraragiServerError = ErrorCode(name: "error.host", code: 1000)
    static let archiveFetchError = ErrorCode(name: "error.list", code: 2000)
    static let archiveExtractError = ErrorCode(name: "error.extract", code: 2002)
    static let categoryFetchError = ErrorCode(name: "error.category", code: 3000)
}

extension Double {
    var int: Int {
        get { Int(self) }
        set { self = Double(newValue) }
    }
}
