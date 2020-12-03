//Created 18/11/20

import Foundation
import GRDB

extension AppDatabase {
    static let shared = makeShared()

    private static func makeShared() -> AppDatabase {
        do {
            let url: URL = try FileManager.default
                    .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("db.sqlite")
            var config = Configuration()
            config.prepareDatabase { database in
                if database.configuration.readonly == false {
                    try database.execute(sql: "PRAGMA auto_vacuum = FULL")
                }
            }
            let dbPool = try DatabasePool(path: url.path, configuration: config)
            let appDatabase = try AppDatabase(dbPool)

            return appDatabase
        } catch {
            fatalError("Unresolved error \(error)")
        }
    }
}
