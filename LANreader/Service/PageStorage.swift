import Foundation

enum PageStorage {
    static let legacySessionFolder = try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    .appendingPathComponent("current session", conformingTo: .folder)

    static func excludeFromBackup(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var folder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    static func takeStaleItems(temporaryFolder: URL, sessionFolder: URL?, legacySessionFolder: URL?) -> [URL] {
        let fileManager = FileManager.default
        var staleItems = (try? fileManager.contentsOfDirectory(
            at: temporaryFolder,
            includingPropertiesForKeys: nil
        )) ?? []
        if let sessionFolder, fileManager.fileExists(atPath: sessionFolder.path) {
            let staleSession = temporaryFolder.appendingPathComponent(
                "stale-session-\(UUID().uuidString)",
                conformingTo: .folder
            )
            if (try? fileManager.moveItem(at: sessionFolder, to: staleSession)) != nil {
                staleItems.append(staleSession)
            }
        }
        if let legacySessionFolder, fileManager.fileExists(atPath: legacySessionFolder.path) {
            staleItems.append(legacySessionFolder)
        }
        return staleItems
    }

    static func remove(_ items: [URL]) {
        for item in items {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
