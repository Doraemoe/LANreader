//  Created 22/8/20.

import Foundation

struct ArchiveIndexResponse: Decodable {
    let arcid: String
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
    let last_used: String
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

struct ArchiveDeleteResponse: Decodable {
    let success: Int
}

extension ArchiveIndexResponse {
    func toArchiveItem() -> ArchiveItem {
        ArchiveItem(id: arcid,
                name: title,
                tags: tags ?? "",
                isNew: isnew == "true",
                progress: progress,
                pagecount: pagecount,
                dateAdded: extractDateAdded(tags: tags ?? ""))
    }

    func toArchive() -> Archive {
        Archive(id: arcid,
                isNew: Bool(isnew) ?? false,
                pageCount: pagecount,
                progress: progress,
                tags: tags ?? "",
                title: title,
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
