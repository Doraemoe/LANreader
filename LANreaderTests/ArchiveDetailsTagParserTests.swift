import XCTest
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
}
