import XCTest
import ComposableArchitecture
@testable import LANreader

final class ArchiveListFeatureTests: XCTestCase {
    @MainActor
    func testSearchTabDoesNotLoadWithoutSearchFilter() async {
        let archive = ArchiveItem(
            id: "existing",
            name: "Existing",
            extension: "zip",
            tags: "",
            isNew: false,
            progress: 0,
            pagecount: 10,
            dateAdded: nil
        )
        var initialState = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            loadOnAppear: false,
            currentTab: .search
        )
        initialState.archives = [GridFeature.State(archive: Shared(value: archive))]
        initialState.archivesToDisplay = initialState.archives
        initialState.total = 1

        let store = TestStore(initialState: initialState) {
            ArchiveListFeature()
        }

        await store.send(.load(true)) {
            $0.archives = []
            $0.archivesToDisplay = []
            $0.total = 0
        }
    }

    func testLibraryTabCanLoadWithoutSearchFilter() {
        let state = ArchiveListFeature.State(
            filter: SearchFilter(category: nil, filter: nil),
            currentTab: .library
        )

        XCTAssertTrue(state.canLoadArchives)
    }
}
