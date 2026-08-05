import Foundation

// LANraragi separates search predicates with commas, not spaces, so a single predicate can contain
// spaces (for example `artist:e auo`). Suggestion lookup and completion therefore operate on the
// comma delimited predicate the user is currently typing.
enum SearchKeyword {
    static func currentPredicateRange(in keyword: String) -> Range<String.Index> {
        guard let lastSeparator = keyword.lastIndex(of: ",") else {
            return keyword.startIndex..<keyword.endIndex
        }
        return keyword.index(after: lastSeparator)..<keyword.endIndex
    }

    /// The text used to look up tag suggestions for the predicate being typed.
    static func suggestionQuery(in keyword: String) -> String {
        var predicate = String(keyword[currentPredicateRange(in: keyword)])
            .trimmingCharacters(in: .whitespaces)
        if predicate.hasPrefix("-") {
            predicate.removeFirst()
        }
        return predicate
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Replaces the predicate being typed with the picked tag, keeping earlier predicates intact.
    static func completing(_ keyword: String, with tag: String) -> String {
        let range = currentPredicateRange(in: keyword)
        let completedPredicates = String(keyword[keyword.startIndex..<range.lowerBound])
        let predicate = String(keyword[range]).trimmingCharacters(in: .whitespaces)
        let exclusion = predicate.hasPrefix("-") ? "-" : ""
        let separator = completedPredicates.isEmpty ? "" : " "
        return "\(completedPredicates)\(separator)\(exclusion)\(tag)$,"
    }
}
