//  Created 23/8/20.

import Foundation
import SwiftUI

struct ArchiveItem: Identifiable {
    let id: String
    let name: String
    var thumbnail: Image
}

struct CategoryItem: Identifiable {
    let id: String
    let name: String
    let archives: [String]
    let search: String
}
