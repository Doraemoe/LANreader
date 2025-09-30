// Created 18/11/20

import Foundation
import GRDB
import Dependencies

struct AppDatabase {
    private let dbWriter: DatabaseWriter

    init(_ dbWriter: DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
        try cleanImageCache()
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("archiveList") { database in
            try database.create(table: "archive") { table in
                table.column("id", .text).primaryKey()
                table.column("isNew", .boolean)
                table.column("pageCount", .integer)
                table.column("progress", .integer)
                table.column("tags", .text)
                table.column("title", .text)
                table.column("lastUpdate", .datetime)
            }
        }

        migrator.registerMigration("archiveThumbnail") { database in
            try database.create(table: "archiveThumbnail") { table in
                table.column("id", .text).primaryKey()
                table.column("thumbnail", .blob)
                table.column("lastUpdate", .datetime)
            }
        }

        migrator.registerMigration("archiveImage") { database in
            try database.create(table: "archiveImage") { table in
                table.column("id", .text).primaryKey()
                table.column("image", .text)
                table.column("lastUpdate", .datetime)
            }
        }

        migrator.registerMigration("category") { database in
            try database.create(table: "category") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text)
                table.column("archives", .text)
                table.column("search", .text)
                table.column("pinned", .boolean)
                table.column("lastUpdate", .datetime)
            }
        }

        migrator.registerMigration("downloadJob") { database in
            try database.create(table: "downloadJob") { table in
                table.column("id", .integer).primaryKey()
                table.column("url", .text)
                table.column("title", .text)
                table.column("isActive", .boolean)
                table.column("isSuccess", .boolean)
                table.column("isError", .boolean)
                table.column("message", .text)
                table.column("lastUpdate", .datetime)
            }
        }

        migrator.registerMigration("history") { database in
            try database.create(table: "history", body: { table in
                table.column("id", .text).primaryKey()
                table.column("lastUpdate", .datetime)
            })
        }

        migrator.registerMigration("tag") { database in
            try database.create(table: "tag") { table in
                table.column("tag", .text).unique(onConflict: .ignore)
            }
        }

        migrator.registerMigration("archiveCache") { database in
            try database.create(table: "archiveCache") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text)
                table.column("tags", .text)
                table.column("thumbnail", .blob)
                table.column("cached", .boolean)
                table.column("totalPages", .integer)
                table.column("lastUpdate", .datetime)
            }
        }

        migrator.registerMigration("tagCount") { database in
            try database.alter(table: "tag") { table in
                table.add(column: "count", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }

    func cleanImageCache() throws {
        try dbWriter.write { database in
            _ = try ArchiveImage.deleteAll(database)
        }
    }
}

extension AppDatabase {
    func saveCache(_ cache: inout ArchiveCache) throws {
        try dbWriter.write { database in
            try cache.save(database)
        }
    }

    func readAllCached() throws -> [ArchiveCache] {
        try dbReader.read { database in
            try ArchiveCache.fetchAll(database)
        }
    }

    func readCache(_ id: String) throws -> ArchiveCache? {
        try dbReader.read { database in
            try ArchiveCache.fetchOne(database, key: id)
        }
    }

    func existCache(_ id: String) throws -> Bool {
        try dbReader.read { database in
            try ArchiveCache.exists(database, key: id)
        }
    }

    func updateCached(_ id: String) throws -> Int {
        try dbWriter.write { database in
            try ArchiveCache
                .filter(id: id)
                .updateAll(database, Column("cached").set(to: true))
        }
    }

    func deleteCache(_ id: String) throws -> Bool {
        try dbWriter.write { database in
            try ArchiveCache.deleteOne(database, id: id)
        }
    }

    func saveArchive(_ archive: inout Archive) throws {
        try dbWriter.write { database in
            try archive.save(database)
        }
    }

    func readArchive(_ id: String) throws -> Archive? {
        try dbReader.read { database in
            try Archive.fetchOne(database, key: id)
        }
    }

    func readAllArchive() throws -> [Archive] {
        try dbReader.read { database in
            try Archive.fetchAll(database)
        }
    }

    func deleteAllArchive() throws -> Int {
        try dbWriter.write { database in
            try Archive.deleteAll(database)
        }
    }

    func saveTag(tagItem: inout TagItem) throws {
        try dbWriter.write { database in
            try tagItem.save(database)
        }
    }

    func searchTag(keyword: String) throws -> [TagItem] {
        return try dbReader.read { database in
            try TagItem
                .filter(Column("tag").like("%\(keyword)%"))
                .order(Column("count").desc)
                .limit(20)
                .fetchAll(database)
        }
    }

    func popularTag() throws -> [TagItem] {
        return try dbReader.read { database in
            try TagItem.order(Column("count").desc).limit(50).fetchAll(database)
        }
    }

    func deleteAllTag() throws -> Int {
        try dbWriter.write { database in
            try TagItem.deleteAll(database)
        }
    }

    func updateArchiveProgress(_ archiveId: String, progress: Int) throws -> Int {
        try dbWriter.write { database in
            try Archive
                    .filter(id: archiveId)
                    .updateAll(database, Column("progress").set(to: progress))
        }
    }

    func deleteArchive(_ archiveId: String) throws -> Bool {
        try dbWriter.write { database in
            try Archive.deleteOne(database, id: archiveId)
        }
    }

    func saveArchiveThumbnail(_ archiveThumbnail: inout ArchiveThumbnail) throws {
        try dbWriter.write { database in
            try archiveThumbnail.save(database)
        }
    }

    func readArchiveThumbnail(_ id: String) throws -> ArchiveThumbnail? {
        try dbReader.read { database in
            try ArchiveThumbnail.fetchOne(database, key: id)
        }
    }

    func deleteArchiveThumbnail(_ id: String) throws -> Bool {
        try dbWriter.write { database in
            try ArchiveThumbnail.deleteOne(database, key: id)
        }
    }

    func existsArchiveThumbnail(_ id: String) throws -> Bool {
        try dbReader.read { database in
            try ArchiveThumbnail.exists(database, key: id)
        }
    }

    func saveArchiveImage(_ image: inout ArchiveImage) throws {
        try dbWriter.write { database in
            try image.save(database)
        }
    }

    func readArchiveImage(_ id: String) throws -> ArchiveImage? {
        try dbReader.read { database in
            try ArchiveImage.fetchOne(database, key: id)
        }
    }

    func existsArchiveImage(_ id: String) throws -> Bool {
        try dbReader.read { database in
            try ArchiveImage.exists(database, key: id)
        }
    }

    func deleteArchiveImage(_ id: String) throws -> Bool {
        try dbWriter.write { database in
            try ArchiveImage.deleteOne(database, key: id)
        }
    }

    func readAllCategories() throws -> [Category] {
        try dbReader.read { database in
            try Category.fetchAll(database)
        }
    }

    func saveCategory(_ category: inout Category) throws {
        try dbWriter.write { database in
            try category.save(database)
        }
    }

    func deleteAllCategory() throws -> Int {
        try dbWriter.write { database in
            try Category.deleteAll(database)
        }
    }

    func readAllDownloadJobs() throws -> [DownloadJob] {
        try dbReader.read { database in
            try DownloadJob.fetchAll(database)
        }
    }

    func saveDownloadJob(_ downloadJob: inout DownloadJob) throws {
        try dbWriter.write { database in
            try downloadJob.save(database)
        }
    }

    func deleteDownloadJobs(_ id: Int) throws -> Bool {
        try dbWriter.write({ database in
            try DownloadJob.deleteOne(database, key: id)
        })
    }

    func saveHistory(_ history: inout History) throws {
        try dbWriter.write { database in
            try history.save(database)
        }
    }

    func readAllArchiveHistory() throws -> [History] {
        try dbReader.read { database in
            try History
                .order(Column("lastUpdate").desc)
                .fetchAll(database)
        }
    }

    func deleteHistories(_ ids: [String]) throws -> Int {
        try dbWriter.write { database in
            try History.deleteAll(database, ids: ids)
        }
    }

    func databaseSize() throws -> Int? {
        try dbReader.read { database in
            try Int.fetchOne(database,
                    sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
        }
    }

    func clearDatabase() throws {
        try dbWriter.write { database in
            _ = try Archive.deleteAll(database)
            _ = try ArchiveThumbnail.deleteAll(database)
            _ = try ArchiveImage.deleteAll(database)
            _ = try Category.deleteAll(database)
            _ = try TagItem.deleteAll(database)
        }
    }
}

extension AppDatabase {
    /// Provides a read-only access to the database.
    public var dbReader: any GRDB.DatabaseReader {
        dbWriter
    }
}

extension AppDatabase: DependencyKey {
  static let liveValue = AppDatabase.shared
}

extension DependencyValues {
  var appDatabase: AppDatabase {
    get { self[AppDatabase.self] }
    set { self[AppDatabase.self] = newValue }
  }
}
