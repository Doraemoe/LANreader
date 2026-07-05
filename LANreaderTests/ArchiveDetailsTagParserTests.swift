import XCTest
import ComposableArchitecture
@testable import LANreader

final class ArchiveDetailsTagParserTests: XCTestCase {
    func testTagGroupsUseRequestedNamespaceOrder() {
        let groups = ArchiveDetailsTagParser.tagGroups(
            from: "series:z,source:example.com,character:alice,date_added:1700000000,misc,artist:bob,group:a"
        )

        XCTAssertEqual(
            groups.map(\.id),
            ["artist", "character", "group", "other", "series", "source", "date_added"]
        )
    }

    func testTagGroupsTrimTagsAndDisplayNamespaceValues() {
        let groups = ArchiveDetailsTagParser.tagGroups(
            from: " artist: Bob , plain tag , artist:Alice , source: example.com "
        )

        let artistTags = groups.first { $0.id == "artist" }?.tags
        XCTAssertEqual(artistTags?.map(\.displayText), ["Alice", "Bob"])
        XCTAssertEqual(artistTags?.map(\.raw), ["artist:Alice", "artist: Bob"])

        let otherTags = groups.first { $0.id == "other" }?.tags
        XCTAssertEqual(otherTags?.map(\.displayText), ["plain tag"])
        XCTAssertEqual(otherTags?.map(\.raw), ["plain tag"])

        let sourceTags = groups.first { $0.id == "source" }?.tags
        XCTAssertEqual(sourceTags?.map(\.displayText), ["example.com"])
        XCTAssertEqual(sourceTags?.map(\.raw), ["source: example.com"])
    }

    @MainActor
    func testArchiveDetailsLoadLocalFieldsUsesTankoubonMetadataTags() async {
        let archive = Shared(value: makeDetailsArchive(
            id: "TANK_1783084742",
            name: "Merged search title",
            tags: "artist:merged"
        ))
        let metadata = TankoubonDetailsMetadata(
            id: "TANK_1783084742",
            name: "Tank title",
            tags: "artist:tank",
            includedArchiveTags: "artist:first,series:one"
        )
        let store = TestStore(
            initialState: ArchiveDetailsFeature.State(
                archive: archive,
                tankoubonMetadata: metadata
            )
        ) {
            ArchiveDetailsFeature()
        }

        await store.send(.loadLocalFields) {
            $0.title = "Tank title"
            $0.editableTags = "artist:tank"
            $0.readOnlyTags = "artist:first,series:one"
        }
    }

    @MainActor
    func testArchiveDetailsUpdatingLocalTankoubonMetadataKeepsIncludedTagsReadOnly() async {
        let archive = Shared(value: makeDetailsArchive(
            id: "TANK_1783084742",
            name: "Tank title",
            tags: "artist:tank,artist:first"
        ))
        let metadata = TankoubonDetailsMetadata(
            id: "TANK_1783084742",
            name: "Tank title",
            tags: "artist:tank",
            includedArchiveTags: "artist:first,series:one"
        )
        let store = TestStore(
            initialState: ArchiveDetailsFeature.State(
                archive: archive,
                tankoubonMetadata: metadata
            )
        ) {
            ArchiveDetailsFeature()
        }

        await store.send(.updateLocalTankoubonMetadata("New title", "artist:new,series:one")) {
            $0.tankoubonMetadata?.name = "New title"
            $0.tankoubonMetadata?.tags = "artist:new,series:one"
            $0.$archive.withLock {
                $0.name = "New title"
                $0.tags = "artist:new,series:one,artist:first"
            }
        }
    }
}

private func makeDetailsArchive(
    id: String = "archive",
    name: String = "Archive",
    tags: String = ""
) -> ArchiveItem {
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
