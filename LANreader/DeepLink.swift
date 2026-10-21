import Foundation

enum DeepLink: Equatable {
    case read(archiveId: String)
    case search(query: String)
    case download(URL)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "lanreader",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        let value = { (name: String) in
            components.queryItems?
                .first { $0.name == name }?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch host.lowercased() {
        case "read":
            guard let archiveId = value("id"), !archiveId.isEmpty,
                  archiveId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
                return nil
            }
            self = .read(archiveId: archiveId)
        case "search":
            guard let query = value("query"), !query.isEmpty else { return nil }
            self = .search(query: query)
        case "download":
            guard let downloadURL = value("url").flatMap(URL.init(string:)),
                  ["http", "https"].contains(downloadURL.scheme?.lowercased()),
                  downloadURL.host?.isEmpty == false else {
                return nil
            }
            self = .download(downloadURL)
        default:
            return nil
        }
    }
}

enum DeepLinkRoute: Equatable {
    case reader(ArchiveItem, cached: Bool)
    case search(query: String)
}
