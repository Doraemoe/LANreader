//  Created 22/8/20.

struct ArchiveIndexResponse: Decodable {
    let arcid: String
    let isnew: String
    let tags: String
    let title: String
}

struct ArchiveExtractResponse: Decodable {
    let pages: [String]
}

struct ArchiveCategoriesResponse: Decodable {
    let archives: [String]
    let id: String
    let last_used: String
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
