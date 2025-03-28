//  Created 22/8/20.

import Foundation

struct ArchiveIndexResponse: Decodable, Equatable {
    let arcid: String
    let `extension`: String
    let isnew: String
    let tags: String?
    let title: String
    let pagecount: Int
    let progress: Int
}

struct ArchiveExtractResponse: Decodable {
    let pages: [String]
}

struct ArchiveCategoriesResponse: Decodable {
    let archives: [String]
    let id: String
    // swiftlint:disable identifier_name
    let last_used: String?
    // swiftlint:enable identifier_name
    let name: String
    let pinned: String
    let search: String
}

struct ArchiveSearchResponse: Decodable {
    let data: [ArchiveIndexResponse]
    let draw: Int
    let recordsFiltered: Int
    let recordsTotal: Int
}

struct ArchiveRandomResponse: Decodable {
    let data: [ArchiveIndexResponse]
}

struct StatsResponse: Decodable {
    let namespace: String
    let text: String
    let weight: String
}

struct GenericSuccessResponse: Decodable {
    let success: Int
}

struct QueueUrlDownloadResponse: Decodable {
    let job: Int
    let operation: String
    let success: Int
    let url: String
}

struct JobStatus: Decodable {
    let id: String
    let state: String
    let task: String
    let result: JobResult?
}

struct JobResult: Decodable {
    let message: String
    let success: Int
    let title: String?
    let url: String
}

struct ServerInfo: Decodable {
    let archivesPerPage: Int
    let debugMode: Bool
    let hasPassword: Bool
    let motd: String
    let name: String
    let nofunMode: Bool
    let serverTracksProgress: Bool
    let version: String
    let versionName: String
}

struct DatabaseBackup: Decodable {
    let archives: [DatabaseBackupArchive]

    struct DatabaseBackupArchive: Decodable {
        let arcid: String
        let filename: String?
        let tags: String?
        let thumbhash: String?
        let title: String?
    }
}

extension JobStatus {
    func toDownloadJob(url: String) -> DownloadJob {
        DownloadJob(
                id: Int(id)!,
                url: url,
                title: result?.title ?? "",
                isActive: state == "active",
                isSuccess: result?.success == 1,
                isError: result?.success == 0,
                message: result?.message ?? "",
                lastUpdate: Date()
        )
    }
}

extension ArchiveIndexResponse {
    func toArchiveItem() -> ArchiveItem {
        ArchiveItem(id: arcid,
                name: title,
                extension: `extension`,
                tags: tags ?? "",
                isNew: isnew == "true",
                progress: progress,
                pagecount: pagecount,
                dateAdded: extractDateAdded(tags: tags ?? ""))
    }

    func toArchive() -> Archive {
        let tagArray = tags?.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? []
        return Archive(id: arcid,
                isNew: Bool(isnew) ?? false,
                pageCount: pagecount,
                progress: progress,
                tags: tagArray,
                title: title,
                extension: `extension`,
                lastUpdate: Date())
    }
}

extension ArchiveCategoriesResponse {
    func toCategoryItem() -> CategoryItem {
        CategoryItem(id: id, name: name, archives: archives, search: search, pinned: pinned)
    }

    func toCategory() -> Category {
        Category(id: id,
                 name: name,
                 archives: archives,
                 search: search,
                 pinned: pinned == "1" ? true : false,
                 lastUpdate: Date())
    }
}

func extractDateAdded(tags: String) -> Int? {
    let dateString = tags.split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.starts(with: "date_added") })?
            .split(separator: ":")
            .last
    if let date = dateString {
        return Int(date)
    } else {
        return nil
    }
}
