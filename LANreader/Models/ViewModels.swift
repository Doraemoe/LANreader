//  Created 23/8/20.

import Foundation
import SwiftUI

struct ArchiveItem: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    let normalizedName: String
    let `extension`: String
    var tags: String
    var isNew: Bool
    var progress: Int
    let pagecount: Int
    var refresh: Bool = false
    let dateAdded: Int?
}

struct CategoryItem: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    var archives: [String]
    let search: String
    let pinned: String
}

extension ArchiveItem {
    func toArchive() -> Archive {
        Archive(id: id,
                isNew: isNew,
                pageCount: pagecount,
                progress: progress,
                tags: tags.split(separator: ",").map(String.init),
                title: name,
                extension: `extension`,
                lastUpdate: Date())
    }
}

extension CategoryItem {
    func toCategory() -> Category {
        Category(id: id,
                 name: name,
                 archives: archives,
                 search: search,
                 pinned: pinned == "1" ? true : false,
                 lastUpdate: Date())
    }
}
