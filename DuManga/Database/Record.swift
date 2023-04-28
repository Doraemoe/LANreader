// Created 18/11/20

import Foundation
import GRDB

struct Archive: Identifiable {
    var id: String
    var isNew: Bool
    var pageCount: Int
    var progress: Int
    var tags: String
    var title: String
    var lastUpdate: Date
}

struct ArchiveThumbnail: Identifiable {
    var id: String
    var thumbnail: Data
    var lastUpdate: Date
}

struct ArchiveImage: Identifiable {
    var id: String
    var image: Data
    var lastUpdate: Date
}

struct Category: Identifiable {
    var id: String
    var name: String
    var archives: [String]
    var search: String
    var pinned: Bool
    var lastUpdate: Date
}

extension Archive: Codable, FetchableRecord, MutablePersistableRecord {
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let isNew = Column(CodingKeys.isNew)
        static let pageCount = Column(CodingKeys.pageCount)
        static let progress = Column(CodingKeys.progress)
        static let tags = Column(CodingKeys.tags)
        static let title = Column(CodingKeys.title)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension Archive {
    func toArchiveItem() -> ArchiveItem {
        ArchiveItem(id: id,
                name: title,
                tags: tags,
                isNew: isNew,
                progress: progress,
                pagecount: pageCount,
                dateAdded: extractDateAdded(tags: tags))
    }
}

extension ArchiveThumbnail: Codable, FetchableRecord, MutablePersistableRecord {
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let thumbnail = Column(CodingKeys.thumbnail)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension ArchiveImage: Codable, FetchableRecord, MutablePersistableRecord {
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let image = Column(CodingKeys.image)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension Category: Codable, FetchableRecord, MutablePersistableRecord {
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let archives = Column(CodingKeys.archives)
        static let search = Column(CodingKeys.search)
        static let pinned = Column(CodingKeys.pinned)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension Category {
    func toCategoryItem() -> CategoryItem {
        CategoryItem(id: id, name: name, archives: archives, search: search, pinned: pinned ? "1" : "0")
    }
}
