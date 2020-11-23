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
            let dbPool = try DatabasePool(path: url.path)
            let appDatabase = try AppDatabase(dbPool)

            return appDatabase
        } catch {
            fatalError("Unresolved error \(error)")
        }
    }
}
