//Created 18/11/20

import Foundation
import GRDB

struct Archive: Identifiable {
    var id: String
    var thumbnail: Data
    var lastUpdate: Date
}

extension Archive: Codable, FetchableRecord, MutablePersistableRecord {
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let thumbnail = Column(CodingKeys.thumbnail)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}
