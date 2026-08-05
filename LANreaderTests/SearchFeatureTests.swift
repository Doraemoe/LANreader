import XCTest
import ComposableArchitecture
import GRDB
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
}

private func makeInMemoryDatabase(tags: [(String, Int)]) throws -> AppDatabase {
    let database = try AppDatabase(DatabaseQueue())
    for (tag, count) in tags {
        var tagItem = TagItem(tag: tag, count: count)
        try database.saveTag(tagItem: &tagItem)
    }
    return database
}
