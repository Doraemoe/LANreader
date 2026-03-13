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

    private enum CodingKeys: String, CodingKey {
        case arcid
        case `extension`
        case isnew
        case tags
        case title
        case pagecount
        case progress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.arcid = try container.decode(String.self, forKey: .arcid)
        self.extension = try container.decode(String.self, forKey: .extension)
        self.isnew = try container.decodeBooleanString(forKey: .isnew)
        self.tags = try container.decodeIfPresent(String.self, forKey: .tags)
        self.title = try container.decode(String.self, forKey: .title)
        self.pagecount = try container.decode(Int.self, forKey: .pagecount)
        self.progress = try container.decode(Int.self, forKey: .progress)
    }
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

    private enum CodingKeys: String, CodingKey {
        case archives
        case id
        // swiftlint:disable identifier_name
        case last_used
        // swiftlint:enable identifier_name
        case name
        case pinned
        case search
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.archives = try container.decodeIfPresent([String].self, forKey: .archives) ?? []
        self.id = try container.decode(String.self, forKey: .id)
        self.last_used = try container.decodeIfPresent(String.self, forKey: .last_used)
        self.name = try container.decode(String.self, forKey: .name)
        self.pinned = try container.decodePinnedString(forKey: .pinned)
        self.search = try container.decodeIfPresent(String.self, forKey: .search) ?? ""
    }
}

struct ArchiveSearchResponse: Decodable {
    let data: [ArchiveIndexResponse]
    let draw: Int?
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

    private enum CodingKeys: String, CodingKey {
        case namespace
        case text
        case weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.namespace = try container.decode(String.self, forKey: .namespace)
        self.text = try container.decode(String.self, forKey: .text)
        self.weight = try container.decodeNumericString(forKey: .weight)
    }
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

private extension KeyedDecodingContainer {
    func decodeBooleanString(forKey key: Key) throws -> String {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let boolValue = try? decodeIfPresent(Bool.self, forKey: key) {
            return boolValue ? "true" : "false"
        }

        if try decodeNil(forKey: key) {
            return "false"
        }

        throw DecodingError.typeMismatch(
            String.self,
            .init(
                codingPath: codingPath + [key],
                debugDescription: "Expected String, Bool, or null for boolean-like field"
            )
        )
    }

    func decodePinnedString(forKey key: Key) throws -> String {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: codingPath + [key], debugDescription: "Expected String or Int for pinned field")
        )
    }

    func decodeNumericString(forKey key: Key) throws -> String {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return doubleValue.formatted(.number.precision(.fractionLength(0...16)))
        }

        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: codingPath + [key], debugDescription: "Expected String, Int, or Double for numeric field")
        )
    }
}
