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
