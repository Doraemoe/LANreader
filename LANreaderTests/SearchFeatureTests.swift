import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
import UIKit
@testable import LANreader

final class SearchFeatureTests: XCTestCase {
    func testSuggestionQueryKeepsSpacesInsideAPredicate() {
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "e auo"), "e auo")
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "artist:e au"), "artist:e au")
    }

    func testSuggestionQueryOnlyUsesThePredicateBeingTyped() {
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "language:english$, e au"), "e au")
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "language:english$,e au"), "e au")
    }

    func testSuggestionQueryIsEmptyWhenPredicateIsComplete() {
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: ""), "")
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "language:english$,"), "")
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "language:english$, "), "")
    }

    func testSuggestionQueryStripsExclusionAndQuotes() {
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "-e au"), "e au")
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "\"e au"), "e au")
        XCTAssertEqual(SearchKeyword.suggestionQuery(in: "language:english$, -\"e au"), "e au")
    }

    func testCompletingReplacesOnlyThePredicateBeingTyped() {
        XCTAssertEqual(SearchKeyword.completing("e au", with: "artist:e auo"), "artist:e auo$,")
        XCTAssertEqual(
            SearchKeyword.completing("language:english$, e au", with: "artist:e auo"),
            "language:english$, artist:e auo$,"
        )
    }

    func testCompletingAppendsWhenPreviousPredicateIsComplete() {
        XCTAssertEqual(SearchKeyword.completing("", with: "artist:e auo"), "artist:e auo$,")
        XCTAssertEqual(
            SearchKeyword.completing("language:english$,", with: "artist:e auo"),
            "language:english$, artist:e auo$,"
        )
    }

    func testCompletingKeepsExclusionPrefix() {
        XCTAssertEqual(SearchKeyword.completing("-e au", with: "artist:e auo"), "-artist:e auo$,")
    }

    func testSearchTagMatchesEveryWordInAnyOrder() throws {
        let database = try makeInMemoryDatabase(tags: [("artist:e auo", 5), ("artist:someone", 10)])

        XCTAssertEqual(try database.searchTag(keyword: "e auo").map(\.tag), ["artist:e auo"])
        XCTAssertEqual(try database.searchTag(keyword: "artist auo").map(\.tag), ["artist:e auo"])
    }

    func testSearchTagRanksPrefixMatchesFirst() throws {
        let database = try makeInMemoryDatabase(tags: [("e auo", 1), ("artist:e auo", 100)])

        XCTAssertEqual(
            try database.searchTag(keyword: "e auo").map(\.tag),
            ["e auo", "artist:e auo"]
        )
    }

    func testSearchTagTreatsPercentAsLiteralText() throws {
        let database = try makeInMemoryDatabase(tags: [("tag:100% cotton", 1), ("artist:e auo", 100)])

        XCTAssertEqual(try database.searchTag(keyword: "100%").map(\.tag), ["tag:100% cotton"])
        XCTAssertEqual(try database.searchTag(keyword: "%").map(\.tag), ["tag:100% cotton"])
    }

    func testSearchTagTreatsUnderscoreAsLiteralText() throws {
        let database = try makeInMemoryDatabase(tags: [("tag:date_added", 1), ("artist:e auo", 100)])

        XCTAssertEqual(try database.searchTag(keyword: "date_added").map(\.tag), ["tag:date_added"])
        XCTAssertEqual(try database.searchTag(keyword: "_").map(\.tag), ["tag:date_added"])
    }

    func testSearchTagTreatsBackslashAsLiteralText() throws {
        let database = try makeInMemoryDatabase(tags: [("artist:a\\b", 1), ("artist:e auo", 100)])

        XCTAssertEqual(try database.searchTag(keyword: "a\\b").map(\.tag), ["artist:a\\b"])
        XCTAssertEqual(try database.searchTag(keyword: "\\").map(\.tag), ["artist:a\\b"])
    }

    func testSearchTagStillRanksEscapedPrefixMatchFirst() throws {
        let database = try makeInMemoryDatabase(tags: [("100% cotton", 1), ("tag:100% cotton", 100)])

        XCTAssertEqual(
            try database.searchTag(keyword: "100%").map(\.tag),
            ["100% cotton", "tag:100% cotton"]
        )
    }

    @MainActor
    func testGenerateSuggestionUsesWholePredicate() async throws {
        let database = try makeInMemoryDatabase(tags: [("artist:e auo", 5), ("artist:auokawa", 10)])
        let clock = TestClock()

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = clock
        }

        await store.send(.generateSuggestion("artist:e au"))
        await clock.advance(by: .milliseconds(150))
        await store.receive(\.suggestionsUpdated) {
            $0.suggestedTag = [TagWithType(tag: "artist:e auo", type: .suggested)]
        }
    }

    @MainActor
    func testGenerateSuggestionDebouncesKeystrokes() async throws {
        let database = try makeInMemoryDatabase(tags: [("artist:e auo", 5)])
        let clock = TestClock()

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = clock
        }

        // Each keystroke cancels the previous lookup, so only the final one reaches the database.
        await store.send(.generateSuggestion("a"))
        await clock.advance(by: .milliseconds(100))
        await store.send(.generateSuggestion("ar"))
        await clock.advance(by: .milliseconds(100))
        await store.send(.generateSuggestion("artist:e au"))
        await clock.advance(by: .milliseconds(150))

        await store.receive(\.suggestionsUpdated) {
            $0.suggestedTag = [TagWithType(tag: "artist:e auo", type: .suggested)]
        }
    }

    @MainActor
    func testGenerateSuggestionFallsBackToPopularTagAfterPredicateSeparator() async throws {
        let database = try makeInMemoryDatabase(tags: [("artist:e auo", 5)])

        var initialState = SearchFeature.State()
        initialState.popularTag = [TagWithType(tag: "artist:e auo", type: .popular)]

        let store = TestStore(initialState: initialState) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = TestClock()
        }

        await store.send(.generateSuggestion("artist:e auo$,")) {
            $0.suggestedTag = [TagWithType(tag: "artist:e auo", type: .popular)]
        }
    }

    @MainActor
    func testSuggestionTappedCancelsPendingLookup() async throws {
        let database = try makeInMemoryDatabase(tags: [("artist:e auo", 5)])
        let clock = TestClock()

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.continuousClock = clock
        }

        await store.send(.generateSuggestion("artist:e au"))
        await store.send(.suggestionTapped(TagWithType(tag: "artist:e auo", type: .suggested))) {
            $0.keyword = "artist:e auo$,"
        }
        // The in-flight lookup was cancelled, so no late result reopens the suggestion panel.
        await clock.advance(by: .milliseconds(150))
    }

    @MainActor
    func testSuggestionTappedKeepsEarlierPredicates() async throws {
        var initialState = SearchFeature.State()
        initialState.keyword = "language:english$, e au"

        let store = TestStore(initialState: initialState) {
            SearchFeature()
        }

        await store.send(.suggestionTapped(TagWithType(tag: "artist:e auo", type: .suggested))) {
            $0.keyword = "language:english$, artist:e auo$,"
        }
    }

    func testRecentSearchesAreNewestFirstAndIgnoreCaseDuplicates() throws {
        let database = try AppDatabase(DatabaseQueue())
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        try database.saveSearchHistory(keyword: "female:b$", date: Date(timeIntervalSince1970: 2))
        try database.saveSearchHistory(keyword: "ARTIST:A$", date: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(try database.recentSearches(), ["ARTIST:A$", "female:b$"])
    }

    func testSearchHistoryKeepsOnlyMostRecentEntries() throws {
        let database = try AppDatabase(DatabaseQueue())
        for index in 0..<(AppDatabase.searchHistoryLimit + 5) {
            try database.saveSearchHistory(
                keyword: "keyword \(index)",
                date: Date(timeIntervalSince1970: Double(index))
            )
        }

        let recent = try database.recentSearches()
        XCTAssertEqual(recent.count, AppDatabase.searchHistoryLimit)
        XCTAssertEqual(recent.first, "keyword \(AppDatabase.searchHistoryLimit + 4)")
        XCTAssertEqual(recent.last, "keyword 5")
    }

    @MainActor
    func testSearchSubmitSavesTrimmedKeywordToRecentSearches() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 10)
        }

        await store.send(.searchSubmit(" artist:a$ ")) {
            $0.archiveList.filter = SearchFilter(category: nil, filter: " artist:a$ ")
        }
        await store.receive(\.loadRecentSearches) {
            $0.recentSearches = ["artist:a$"]
        }
        XCTAssertFalse(store.state.showsRecentSearches)
    }

    @MainActor
    func testRecentSearchTappedRunsThatSearch() async throws {
        let database = try AppDatabase(DatabaseQueue())
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        var initialState = SearchFeature.State()
        initialState.recentSearches = ["artist:a$"]
        let store = TestStore(initialState: initialState) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 10)
        }
        XCTAssertTrue(store.state.showsRecentSearches)

        await store.send(.recentSearchTapped("artist:a$")) {
            $0.keyword = "artist:a$"
        }
        await store.receive(\.searchSubmit) {
            $0.archiveList.filter = SearchFilter(category: nil, filter: "artist:a$")
        }
        await store.receive(\.loadRecentSearches)
        XCTAssertFalse(store.state.showsRecentSearches)
    }

    @MainActor
    func testSearchClearedReturnsToRecentSearches() async throws {
        var initialState = SearchFeature.State()
        initialState.recentSearches = ["artist:a$"]
        initialState.archiveList.filter = SearchFilter(category: nil, filter: "artist:a$")
        let store = TestStore(initialState: initialState) {
            SearchFeature()
        }
        XCTAssertFalse(store.state.showsRecentSearches)

        await store.send(.searchCleared) {
            $0.archiveList.filter = SearchFilter(category: nil, filter: nil)
        }
        await store.receive(\.archiveList.resetArchives)
        XCTAssertTrue(store.state.showsRecentSearches)
    }

    @MainActor
    func testClearRecentSearches() async throws {
        let database = try AppDatabase(DatabaseQueue())
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        try database.saveSearchHistory(keyword: "female:b$", date: Date(timeIntervalSince1970: 2))
        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.appDatabase = database
        }

        await store.send(.loadRecentSearches) {
            $0.recentSearches = ["female:b$", "artist:a$"]
        }

        await store.send(.clearRecentSearches) {
            $0.recentSearches = []
        }
        XCTAssertEqual(try database.recentSearches(), [])
        XCTAssertFalse(store.state.showsRecentSearches)
    }

    @MainActor
    func testSearchTabShowsRecentSearchesAndRunsTappedSearch() async throws {
        UserDefaults.standard.set("https://localhost", forKey: SettingsKey.lanraragiUrl)
        defer {
            UserDefaults.standard.removeObject(forKey: SettingsKey.lanraragiUrl)
            HTTPStubs.removeAllStubs()
        }
        stub(condition: isPath("/api/search")) { @Sendable _ in
            HTTPStubsResponse(
                data: Data(#"{"data":[],"recordsFiltered":0,"recordsTotal":0}"#.utf8),
                statusCode: 200, headers: ["Content-Type": "application/json"]
            )
        }
        let database = try AppDatabase(DatabaseQueue())
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        var popularTag = TagItem(tag: "female:b", count: 10)
        try database.saveTag(tagItem: &popularTag)
        let store = withDependencies {
            $0.appDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 10)
        } operation: {
            Store(initialState: SearchFeature.State()) { SearchFeature() }
        }
        let controller = UISearchViewV2Controller(store: store)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        await Task.yield()

        let recent = try XCTUnwrap(
            controller.children.compactMap { $0 as? UIHostingController<RecentSearchesView> }.first
        )
        XCTAssertFalse(recent.view.isHidden)
        XCTAssertEqual(recent.rootView.store.recentSearches, ["artist:a$"])
        let suggestions = try XCTUnwrap(controller.view.firstSubview(of: UITableView.self))
        XCTAssertTrue(suggestions.isHidden)

        recent.rootView.onSelect("artist:a$")
        await Task.yield()

        XCTAssertEqual(store.keyword, "artist:a$")
        XCTAssertEqual(store.archiveList.filter.filter, "artist:a$")
        XCTAssertTrue(recent.view.isHidden)
    }

    @MainActor
    func testDraggingPopularTagsKeepsThemOpenAfterKeyboardDismisses() async throws {
        let database = try AppDatabase(DatabaseQueue())
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        var popularTag = TagItem(tag: "female:b", count: 10)
        try database.saveTag(tagItem: &popularTag)
        let store = withDependencies {
            $0.appDatabase = database
        } operation: {
            Store(initialState: SearchFeature.State()) { SearchFeature() }
        }
        let controller = UISearchViewV2Controller(store: store)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        await Task.yield()
        let searchBar = try XCTUnwrap(
            controller.navigationItem.searchController?.searchBar
                ?? controller.view.firstSubview(of: UISearchBar.self)
        )
        let suggestions = try XCTUnwrap(controller.view.firstSubview(of: UITableView.self))
        XCTAssertTrue(suggestions.isHidden)

        controller.searchBarTextDidBeginEditing(searchBar)
        XCTAssertFalse(suggestions.isHidden)
        controller.scrollViewWillBeginDragging(suggestions)
        controller.searchBarTextDidEndEditing(searchBar)
        XCTAssertFalse(suggestions.isHidden)

        controller.searchBarTextDidBeginEditing(searchBar)
        controller.searchBarTextDidEndEditing(searchBar)
        XCTAssertTrue(suggestions.isHidden)
    }
}

private extension UIView {
    func firstSubview<View: UIView>(of type: View.Type) -> View? {
        for subview in subviews {
            if let match = subview as? View {
                return match
            }
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}

private func makeInMemoryDatabase(tags: [(String, Int)]) throws -> AppDatabase {
    let database = try AppDatabase(DatabaseQueue())
    for (tag, count) in tags {
        var tagItem = TagItem(tag: tag, count: count)
        try database.saveTag(tagItem: &tagItem)
    }
    return database
}
