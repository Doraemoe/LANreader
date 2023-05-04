// Created 18/11/20

import Foundation
import GRDB

struct AppDatabase {
    private let dbWriter: DatabaseWriter

    init(_ dbWriter: DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
        try cleanImageCache()
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.eraseDatabaseOnSchemaChange = true

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
                table.column("image", .blob)
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

        return migrator
    }

    func cleanImageCache() throws {
        try dbWriter.write { database in
            _ = try ArchiveImage.deleteAll(database)
        }
        try dbWriter.vacuum()
    }
}

extension AppDatabase {
    func saveArchive(_ archive: inout Archive) throws {
        try dbWriter.write { database in
            try archive.save(database)
        }
    }

    func readArchive(_ id: String) throws -> Archive? {
        try dbWriter.read { database in
            try Archive.fetchOne(database, key: id)
        }
    }

    func readAllArchive() throws -> [Archive] {
        try dbWriter.read { database in
            try Archive.fetchAll(database)
        }
    }

    func deleteAllArchive() throws -> Int {
        try dbWriter.write { database in
            try Archive.deleteAll(database)
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
        try dbWriter.read { database in
            try ArchiveThumbnail.fetchOne(database, key: id)
        }
    }

    func saveArchiveImage(_ image: inout ArchiveImage) throws {
        try dbWriter.write { database in
            try image.save(database)
        }
    }

    func readArchiveImage(_ id: String) throws -> ArchiveImage? {
        try dbWriter.read { database in
            try ArchiveImage.fetchOne(database, key: id)
        }
    }

    func readAllCategories() throws -> [Category] {
        try dbWriter.read { database in
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

    func databaseSize() throws -> Int? {
        try dbWriter.read { database in
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
        }
        try dbWriter.vacuum()
    }
}
