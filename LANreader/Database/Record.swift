// Created 18/11/20

import Foundation
import GRDB

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
    var toc: [ArchiveChapter]?
    var lastUpdate: Date
    var progress: Int = 0
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

struct SearchHistory: Equatable {
    var keyword: String
    var lastUsed: Date
}

extension SearchHistory: Codable, FetchableRecord, MutablePersistableRecord {
    internal enum Columns {
        static let keyword = Column(CodingKeys.keyword)
        static let lastUsed = Column(CodingKeys.lastUsed)
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
        static let toc = Column(CodingKeys.toc)
        static let lastUpdate = Column(CodingKeys.lastUpdate)
        static let progress = Column(CodingKeys.progress)
    }
}

extension ArchiveCache {
    func toArchiveItem() -> ArchiveItem {
        ArchiveItem(
            id: id,
            name: title,
            extension: "",
            tags: tags,
            isNew: false,
            progress: progress,
            pagecount: totalPages,
            dateAdded: nil,
            toc: toc
        )
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
