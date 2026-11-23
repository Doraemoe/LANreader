import XCTest
import ComposableArchitecture
import GRDB
import OHHTTPStubs
import OHHTTPStubsSwift
import SwiftUI
import UIKit
@testable import LANreader

final class SearchFeatureTests: LANreaderTestCase {
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

    func testRecentSearchesAreNewestFirstAndIgnoreCaseDuplicates() throws {
        let database = try AppDatabase(DatabaseQueue())
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        try database.saveSearchHistory(keyword: "female:b$", date: Date(timeIntervalSince1970: 2))
        try database.saveSearchHistory(keyword: "ARTIST:A$", date: Date(timeIntervalSince1970: 3))
        try database.saveSearchHistory(keyword: "artist:Éclair$", date: Date(timeIntervalSince1970: 4))
        try database.saveSearchHistory(keyword: "artist:éclair$", date: Date(timeIntervalSince1970: 5))

        XCTAssertEqual(try database.recentSearches(), ["artist:éclair$", "ARTIST:A$", "female:b$"])
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
        initialState.archiveList.loading = true
        initialState.archiveList.total = 100
        let store = TestStore(initialState: initialState) {
            SearchFeature()
        }
        XCTAssertFalse(store.state.showsRecentSearches)

        await store.send(.searchCleared) {
            $0.archiveList.filter = SearchFilter(category: nil, filter: nil)
        }
        await store.receive(\.archiveList.reloadFromFirstPage) {
            $0.archiveList.loading = false
            $0.archiveList.total = 0
        }
        XCTAssertTrue(store.state.showsRecentSearches)
    }

    @MainActor
    func testSearchClearedCancelsPendingResults() async throws {
        defer {
            HTTPStubs.removeAllStubs()
        }
        try await configureTestServer()
        let requested = expectation(description: "Search request started")
        stub(condition: isHost("localhost") && isPath("/api/search")) { @Sendable _ in
            requested.fulfill()
            let response = HTTPStubsResponse(
                data: Data(#"{"data":[],"recordsFiltered":100,"recordsTotal":100}"#.utf8),
                statusCode: 200, headers: ["Content-Type": "application/json"]
            )
            response.responseTime = 1
            return response
        }
        var state = SearchFeature.State()
        state.recentSearches = ["artist:a$"]
        state.archiveList.filter = SearchFilter(category: nil, filter: "artist:a$")
        state.archiveList.$lastTagRefresh = Shared(value: Date().timeIntervalSince1970)
        state.archiveList.$searchSort = Shared(value: SearchSort.name.rawValue)
        let store = TestStore(initialState: state) { SearchFeature() }

        await store.send(.archiveList(.load)) {
            $0.archiveList.loading = true
        }
        await fulfillment(of: [requested], timeout: 2)
        await store.send(.searchCleared) {
            $0.archiveList.filter = SearchFilter(category: nil, filter: nil)
        }
        await store.receive(\.archiveList.reloadFromFirstPage) {
            $0.archiveList.loading = false
        }
        await store.finish()
        XCTAssertTrue(store.state.archiveList.archivesToDisplay.isEmpty)
        XCTAssertEqual(store.state.archiveList.total, 0)
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
    func testClearRecentSearchesKeepsHistoryWhenDeletionFails() async throws {
        let queue = try DatabaseQueue()
        let database = try AppDatabase(queue)
        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        try await queue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER rejectHistoryDeletion BEFORE DELETE ON searchHistory
                BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END
                """)
        }
        var state = SearchFeature.State()
        state.recentSearches = ["artist:a$"]
        let store = TestStore(initialState: state) { SearchFeature() } withDependencies: {
            $0.appDatabase = database
        }

        await store.send(.clearRecentSearches)

        XCTAssertEqual(store.state.recentSearches, ["artist:a$"])
        XCTAssertEqual(try database.recentSearches(), ["artist:a$"])
        XCTAssertTrue(store.state.showsRecentSearches)
    }

    @MainActor
    func testSearchTabShowsRecentSearchesAndRunsTappedSearch() async throws {
        UserDefaults.standard.set("https://localhost", forKey: SettingsKey.lanraragiUrl)
        stub(condition: isPath("/api/search")) { @Sendable _ in
            HTTPStubsResponse(
                data: Data(#"{"data":[],"recordsFiltered":0,"recordsTotal":0}"#.utf8),
                statusCode: 200, headers: ["Content-Type": "application/json"]
            )
        }
        // The first load of the day also refreshes the tag list used for suggestions.
        stub(condition: isPath("/api/database/stats")) { @Sendable _ in
            HTTPStubsResponse(data: Data("[]".utf8), statusCode: 200, headers: ["Content-Type": "application/json"])
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
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
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
        // Let the tapped search finish while its stub is still installed.
        for _ in 0..<500 where store.archiveList.loading {
            try? await Task<Never, Never>.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.archiveList.loading)
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
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
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

    @MainActor
    func testSearchTabReloadsRecentSearchesSavedElsewhereWhenItAppears() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = withDependencies {
            $0.appDatabase = database
        } operation: {
            Store(initialState: SearchFeature.State()) { SearchFeature() }
        }
        let controller = UISearchViewV2Controller(store: store)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.loadViewIfNeeded()
        controller.loadViewIfNeeded()
        XCTAssertEqual(store.recentSearches, [])

        try database.saveSearchHistory(keyword: "artist:a$", date: Date(timeIntervalSince1970: 1))
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        await Task.yield()

        XCTAssertEqual(store.recentSearches, ["artist:a$"])
        let recent = try XCTUnwrap(
            controller.children.compactMap { $0 as? UIHostingController<RecentSearchesView> }.first
        )
        XCTAssertFalse(recent.view.isHidden)
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

final class SearchTabNavigationTests: LANreaderTestCase {
    @MainActor
    func testSearchTabNavigationFlowPushesReaderDetailsAndTagSearch() async throws {
        let firstArchive = makeSearchTestArchive(id: "arc1", name: "First", tags: "artist:e auo")
        let store = try makeSearchTabTestStore(initialArchives: [firstArchive])

        await store.send(.root(.archiveList(.openReader(archiveId: firstArchive.id, fromStart: true))))
        let readerID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .reader(readerState) = store.state.path[id: readerID] else {
            return XCTFail("Expected pushed reader state")
        }
        XCTAssertEqual(readerState.currentArchiveId, firstArchive.id)
        XCTAssertTrue(readerState.fromStart)
        XCTAssertEqual(readerState.allArchives.ids, [firstArchive.id])

        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let detailsID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .details(detailsState) = store.state.path[id: detailsID] else {
            return XCTFail("Expected pushed details state")
        }
        XCTAssertEqual(detailsState.archive.id, firstArchive.id)
        XCTAssertEqual(detailsState.title, "First")
        XCTAssertEqual(detailsState.editableTags, "artist:e auo")

        await store.send(.path(.element(id: detailsID, action: .details(.tagTapped(" artist:e auo ")))))
        let tagSearchID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .search(tagSearchState) = store.state.path[id: tagSearchID] else {
            return XCTFail("Expected pushed tag search state")
        }
        XCTAssertEqual(tagSearchState.keyword, "artist:e auo")
        XCTAssertEqual(tagSearchState.archiveList.filter, SearchFilter(category: nil, filter: "artist:e auo"))
        XCTAssertTrue(tagSearchState.archiveList.loadOnAppear)

        await store.send(.path(.popFrom(id: tagSearchID)))
        XCTAssertEqual(Array(store.state.path.ids), [readerID, detailsID])

        await store.send(.path(.element(id: detailsID, action: .details(.deleteSuccess))))
        XCTAssertTrue(store.state.path.isEmpty)
    }

    @MainActor
    func testSearchTabNestedDeletePopsOnlyInnerReaderAndDetails() async throws {
        let firstArchive = makeSearchTestArchive(id: "arc1", name: "First", tags: "artist:e auo")
        let secondArchive = makeSearchTestArchive(id: "arc2", name: "Second", tags: "artist:e auo")
        let store = try makeSearchTabTestStore(initialArchives: [firstArchive])

        await store.send(.root(.archiveList(.openReader(archiveId: firstArchive.id, fromStart: true))))
        let readerID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let detailsID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: detailsID, action: .details(.tagTapped("artist:e auo")))))
        let tagSearchID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(
            .path(
                .element(
                    id: tagSearchID,
                    action: .search(.archiveList(.populateArchives([secondArchive], 1, false)))
                )
            )
        )
        await store.send(
            .path(
                .element(
                    id: tagSearchID,
                    action: .search(.archiveList(.openReader(archiveId: secondArchive.id, fromStart: false)))
                )
            )
        )
        let nestedReaderID = try XCTUnwrap(store.state.path.ids.last)
        guard case let .reader(nestedReaderState) = store.state.path[id: nestedReaderID] else {
            return XCTFail("Expected nested pushed reader state")
        }
        XCTAssertEqual(nestedReaderState.currentArchiveId, secondArchive.id)
        XCTAssertFalse(nestedReaderState.fromStart)

        await store.send(.path(.element(id: nestedReaderID, action: .reader(.openDetailsTapped))))
        let nestedDetailsID = try XCTUnwrap(store.state.path.ids.last)
        guard case .details = store.state.path[id: nestedDetailsID] else {
            return XCTFail("Expected nested pushed details state")
        }

        // Deleting from the nested details pops both the nested details and nested reader,
        // landing back on the pushed tag search without disturbing earlier stack entries.
        await store.send(.path(.element(id: nestedDetailsID, action: .details(.deleteSuccess))))
        XCTAssertEqual(Array(store.state.path.ids), [readerID, detailsID, tagSearchID])
    }

    @MainActor
    func testSearchTabNestedEditRefreshesOriginalDetailsOnPopBack() async throws {
        try await configureTestServer()
        stub(
            condition: isHost("localhost")
                && isPath("/api/archives/arc1/metadata")
                && isMethodPUT()
                && containsQueryParams(["title": "Updated", "tags": "artist:e auo, character:bob"])
        ) { @Sendable _ in
            HTTPStubsResponse(data: Data("{}".utf8), statusCode: 200, headers: ["Content-Type": "application/json"])
        }

        let archive = makeSearchTestArchive(id: "arc1", name: "First", tags: "artist:e auo")
        let store = try makeSearchTabTestStore(initialArchives: [])
        defer { store.state.root.archiveList.$archiveItems.withLock { $0 = [] } }

        await store.send(.root(.archiveList(.populateArchives([archive], 1, false))))
        await store.send(.root(.archiveList(.openReader(archiveId: archive.id, fromStart: false))))
        let readerID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
        let detailsID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: detailsID, action: .details(.tagTapped("artist:e auo")))))
        let tagSearchID = try XCTUnwrap(store.state.path.ids.last)

        await store.send(.path(.element(
            id: tagSearchID,
            action: .search(.archiveList(.populateArchives([archive], 1, false)))
        )))
        await store.send(.path(.element(
            id: tagSearchID,
            action: .search(.archiveList(.openReader(archiveId: archive.id, fromStart: false)))
        )))
        let nestedReaderID = try XCTUnwrap(store.state.path.ids.last)
        await store.send(.path(.element(id: nestedReaderID, action: .reader(.openDetailsTapped))))
        let nestedDetailsID = try XCTUnwrap(store.state.path.ids.last)

        let updatedTags = "artist:e auo, character:bob"
        await store.send(.path(.element(id: nestedDetailsID, action: .details(.binding(.set(\.title, "Updated"))))))
        await store.send(.path(.element(
            id: nestedDetailsID,
            action: .details(.binding(.set(\.editableTags, updatedTags)))
        )))
        await store.send(.path(.element(id: nestedDetailsID, action: .details(.updateArchiveMetadata))))
        await store.receive(\.path[id: nestedDetailsID].details.setSuccessMessage, timeout: .seconds(5))

        await store.send(.path(.popFrom(id: tagSearchID)))
        guard case let .details(refreshedDetails) = store.state.path[id: detailsID] else {
            return XCTFail("Expected original details state")
        }
        XCTAssertEqual(refreshedDetails.title, "Updated")
        XCTAssertEqual(refreshedDetails.editableTags, "artist:e auo, character:bob")
        XCTAssertFalse(refreshedDetails.needsLocalFieldsRefresh)
    }

    @MainActor
    func testSearchNavigationControllerPushesAndPopsWithStore() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let archive = makeSearchTestArchive(id: "arc1", name: "First", tags: "artist:e auo")
        let sharedArchive = Shared(value: archive)

        var initialState = SearchTabFeature.State()
        initialState.root.archiveList.archivesToDisplay = [GridFeature.State(archive: sharedArchive)]

        try await withDependencies {
            $0.appDatabase = database
        } operation: {
            let store = Store(initialState: initialState) {
                SearchTabFeature()
            }
            let (nav, root) = makeSearchNavigationController(store: store)
            nav.loadViewIfNeeded()
            root.loadViewIfNeeded()

            XCTAssertEqual(nav.viewControllers.count, 1)
            XCTAssertTrue(nav.topViewController === root)

            withUITransaction(\.uiKit.disablesAnimations, true) {
                _ = store.send(.root(.archiveList(.openReader(archiveId: archive.id, fromStart: false))))
            }
            await waitUntil { nav.viewControllers.count == 2 }
            XCTAssertEqual(nav.viewControllers.count, 2)
            XCTAssertTrue(nav.topViewController is UIArchiveReaderController)

            let readerID = try XCTUnwrap(store.path.ids.last)
            withUITransaction(\.uiKit.disablesAnimations, true) {
                _ = store.send(.path(.element(id: readerID, action: .reader(.openDetailsTapped))))
            }
            await waitUntil { nav.viewControllers.count == 3 }
            XCTAssertEqual(nav.viewControllers.count, 3)
            XCTAssertTrue(nav.topViewController is UIHostingController<ArchiveDetailsV2>)

            let detailsID = try XCTUnwrap(store.path.ids.last)
            withUITransaction(\.uiKit.disablesAnimations, true) {
                _ = store.send(.path(.element(id: detailsID, action: .details(.deleteSuccess))))
            }
            await waitUntil { nav.viewControllers.count == 1 }
            XCTAssertEqual(nav.viewControllers.count, 1)
            XCTAssertTrue(nav.topViewController === root)
            XCTAssertTrue(store.path.isEmpty)
        }
    }
}

@MainActor
private func makeSearchTabTestStore(initialArchives: [ArchiveItem]) throws -> TestStoreOf<SearchTabFeature> {
    let database = try AppDatabase(DatabaseQueue())
    var initialState = SearchTabFeature.State()
    initialState.root.archiveList.archivesToDisplay = IdentifiedArray(
        uniqueElements: initialArchives.map { GridFeature.State(archive: Shared(value: $0)) }
    )
    let store = TestStore(initialState: initialState) {
        SearchTabFeature()
    } withDependencies: {
        $0.appDatabase = database
    }
    store.exhaustivity = .off
    return store
}

private func makeSearchTestArchive(id: String, name: String, tags: String) -> ArchiveItem {
    ArchiveItem(
        id: id,
        name: name,
        extension: "zip",
        tags: tags,
        isNew: false,
        progress: 0,
        pagecount: 10,
        dateAdded: nil
    )
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
