//  Created 23/8/20.

import Foundation
import SwiftUI

struct ArchiveChapter: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: Int { page }
    let name: String
    let page: Int
}

public struct ArchiveItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    var name: String
    let `extension`: String
    var tags: String
    var isNew: Bool
    var progress: Int
    let pagecount: Int
    let dateAdded: Int?
    var toc: [ArchiveChapter]?
    var refresh: Bool = false
}

public struct CategoryItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    let name: String
    var archives: [String]
    let search: String
    let pinned: String
}

public struct TankoubonDetailsMetadata: Equatable, Hashable, Sendable {
    public let id: String
    public var name: String?
    public var tags: String
    public let includedArchiveTags: String

    public init(id: String, name: String? = nil, tags: String = "", includedArchiveTags: String = "") {
        self.id = id
        self.name = name
        self.tags = tags
        self.includedArchiveTags = includedArchiveTags
    }

    init(response: TankoubonFullResponse) {
        self.init(
            id: response.result.id,
            name: response.result.name,
            tags: response.result.tags ?? "",
            includedArchiveTags: Self.mergedTags(from: response.result.fullData?.map { $0.tags ?? "" } ?? [])
        )
    }

    var combinedTags: String {
        Self.mergedTags(from: [tags, includedArchiveTags])
    }

    private static func mergedTags(from tagStrings: [String]) -> String {
        var seen = Set<String>()
        return tagStrings
            .flatMap { tagString in
                tagString.split(separator: ",").map { tag in
                    tag.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .filter { tag in
                guard !tag.isEmpty else { return false }
                return seen.insert(tag).inserted
            }
            .joined(separator: ",")
    }
}

extension String {
    var isTankoubonArchiveId: Bool {
        hasPrefix("TANK_")
    }
}

extension ArchiveItem {
    func toArchive() -> Archive {
        Archive(id: id,
                isNew: isNew,
                pageCount: pagecount,
                progress: progress,
                tags: tags.split(separator: ",").map(String.init),
                title: name,
                extension: `extension`,
                lastUpdate: Date())
    }
}

extension CategoryItem {
    func toCategory() -> Category {
        Category(id: id,
                 name: name,
                 archives: archives,
                 search: search,
                 pinned: pinned == "1" ? true : false,
                 lastUpdate: Date())
    }
}
