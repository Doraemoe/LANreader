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

        // TODO: Remove this after db schema is stable
        migrator.eraseDatabaseOnSchemaChange = true

        migrator.registerMigration("archiveList") { database in
            try database.create(table: "archive") { table in
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

    func databaseSize() throws -> Int? {
        try dbWriter.read { database in
            try Int.fetchOne(database,
                    sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
        }
    }

    func clearDatabase() throws {
        try dbWriter.write { database in
            _ = try Archive.deleteAll(database)
            _ = try ArchiveImage.deleteAll(database)
        }
        try dbWriter.vacuum()
    }
}
