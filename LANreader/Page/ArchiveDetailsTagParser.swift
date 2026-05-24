import Foundation

enum ArchiveDetailsTagParser {
    static let artistTag = "artist"
    static let sourceTag = "source"
    static let dateTag = "date_added"
    static let otherTag = "other"

    static func tagGroups(from tags: String) -> [ArchiveTagGroup] {
        let parsedTags = tags
            .split(separator: ",")
            .enumerated()
            .compactMap { index, rawTag in
                parseTag(rawTag: String(rawTag), id: index)
            }

        return Dictionary(grouping: parsedTags, by: \.namespaceKey)
            .map { namespaceKey, tags in
                ArchiveTagGroup(
                    id: namespaceKey,
                    title: tagGroupTitle(for: namespaceKey),
                    tags: tags.sorted { first, second in
                        if first.displayText == second.displayText {
                            return first.id < second.id
                        }
                        let order = first.displayText.localizedCaseInsensitiveCompare(second.displayText)
                        return order == .orderedAscending
                    }
                )
            }
            .sorted { first, second in
                let firstRank = tagGroupRank(first.id)
                let secondRank = tagGroupRank(second.id)
                if firstRank != secondRank {
                    return firstRank < secondRank
                }
                return first.id.localizedCaseInsensitiveCompare(second.id) == .orderedAscending
            }
    }

    private static func parseTag(rawTag: String, id: Int) -> ArchiveDetailsTag? {
        let raw = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return nil
        }

        let tagPair = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let rawNamespace = tagPair.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasNamespace = tagPair.count == 2 && !rawNamespace.isEmpty
        let namespaceKey = hasNamespace ? rawNamespace.lowercased() : otherTag
        let value = hasNamespace
            ? tagPair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : raw
        let displayText = tagDisplayText(namespaceKey: namespaceKey, value: value, raw: raw)

        return ArchiveDetailsTag(
            id: id,
            raw: raw,
            namespaceKey: namespaceKey,
            value: value,
            displayText: displayText.isEmpty ? raw : displayText,
            accessibilityLabel: "\(tagGroupTitle(for: namespaceKey)), \(displayText.isEmpty ? raw : displayText)"
        )
    }

    private static func tagDisplayText(namespaceKey: String, value: String, raw: String) -> String {
        if namespaceKey == dateTag, let timestamp = TimeInterval(value), timestamp > 0 {
            let date = Date(timeIntervalSince1970: timestamp)
            return date.formatted(date: .abbreviated, time: .omitted)
        }

        if value.isEmpty {
            return raw
        }

        return value
    }

    private static func tagGroupTitle(for namespaceKey: String) -> String {
        switch namespaceKey {
        case otherTag:
            return String(localized: "archive.tags.group.other")
        case dateTag:
            return String(localized: "archive.tags.group.dateAdded")
        default:
            return namespaceKey
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .localizedCapitalized
        }
    }

    private static func tagGroupRank(_ namespaceKey: String) -> Int {
        switch namespaceKey {
        case artistTag:
            return 0
        case sourceTag:
            return 2
        case dateTag:
            return 3
        default:
            return 1
        }
    }
}

struct ArchiveDetailsTag: Identifiable, Hashable {
    let id: Int
    let raw: String
    let namespaceKey: String
    let value: String
    let displayText: String
    let accessibilityLabel: String
}

struct ArchiveTagGroup: Identifiable {
    let id: String
    let title: String
    let tags: [ArchiveDetailsTag]
}
