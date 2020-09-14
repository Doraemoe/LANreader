//  Created 23/8/20.

import Foundation
import SwiftUI

struct ArchiveItem: Identifiable, Equatable {
    let id: String
    let name: String
    let tags: String
    var thumbnail: Image

    static func ==(lhs: ArchiveItem, rhs: ArchiveItem) -> Bool {
        lhs.id == rhs.id
                && lhs.name == rhs.name
                && lhs.tags == rhs.tags
                && lhs.thumbnail == rhs.thumbnail
    }
}

struct CategoryItem: Identifiable {
    let id: String
    let name: String
    let archives: [String]
    let search: String
    let pinned: String
}
