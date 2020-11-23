//Created 18/11/20

import Foundation
import GRDB

struct AppDatabase {
    private let dbWriter: DatabaseWriter

    init(_ dbWriter: DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
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
        return migrator
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
            return try Archive.fetchOne(database, key: id)
        }
    }
}
