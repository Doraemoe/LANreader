// Created 18/11/20

import Foundation
import GRDB

struct Archive: Identifiable {
    var id: String
    var isNew: Bool
    var pageCount: Int
    var progress: Int
    var tags: [String]
    var title: String
    var `extension`: String
    var lastUpdate: Date
}

struct TagItem {
    var tag: String
    var count: Int
}

struct ArchiveThumbnail: Identifiable, Equatable {
    var id: String
    var thumbnail: Data
    var lastUpdate: Date
}

struct ArchiveCache: Identifiable, Equatable {
    var id: String
    var title: String
    var tags: String
    var thumbnail: Data?
    var cached: Bool
    var totalPages: Int
    var lastUpdate: Date
}

struct ArchiveImage: Identifiable, Equatable {
    var id: String
    var image: String
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

public struct DownloadJob: Identifiable, Equatable, Sendable {
    public var id: Int
    var url: String
    var title: String
    var isActive: Bool
    var isSuccess: Bool
    var isError: Bool
    var message: String
    var lastUpdate: Date
}

struct History: Identifiable, Equatable {
    var id: String
    var lastUpdate: Date
}

extension Archive: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
        static let id = Column(CodingKeys.id)
        static let isNew = Column(CodingKeys.isNew)
        static let pageCount = Column(CodingKeys.pageCount)
        static let progress = Column(CodingKeys.progress)
        static let tags = Column(CodingKeys.tags)
        static let title = Column(CodingKeys.title)
        static let `extension` = Column(CodingKeys.extension)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension Archive {
    func toArchiveItem() -> ArchiveItem {
        let tagString = tags.joined(separator: ",")
        return ArchiveItem(id: id,
                name: title,
                extension: `extension`,
                tags: tagString,
                isNew: isNew,
                progress: progress,
                pagecount: pageCount,
                dateAdded: extractDateAdded(tags: tagString))
    }
}

extension TagItem: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tag"
    internal enum Columns {
        static let tar = Column(CodingKeys.tag)
        static let count = Column(CodingKeys.count)
    }
}

extension ArchiveThumbnail: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
        static let id = Column(CodingKeys.id)
        static let thumbnail = Column(CodingKeys.thumbnail)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension ArchiveCache: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let tags = Column(CodingKeys.tags)
        static let thumbnail = Column(CodingKeys.thumbnail)
        static let cached = Column(CodingKeys.cached)
        static let totalPages = Column(CodingKeys.totalPages)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension ArchiveImage: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
        static let id = Column(CodingKeys.id)
        static let image = Column(CodingKeys.image)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension Category: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
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

extension DownloadJob: Codable, FetchableRecord, MutablePersistableRecord {
    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let url = Column(CodingKeys.url)
        static let title = Column(CodingKeys.title)
        static let isActive = Column(CodingKeys.isActive)
        static let isSuccess = Column(CodingKeys.isSuccess)
        static let isError = Column(CodingKeys.isError)
        static let message = Column(CodingKeys.message)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}

extension History: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
        static let id = Column(CodingKeys.id)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
    }
}
