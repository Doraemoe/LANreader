import UIKit
import XCTest
@testable import LANreader

final class ArchiveListLayoutBuilderTests: LANreaderTestCase {
    func testGridColumnsAdaptToPhoneAndTabletWidths() {
        XCTAssertEqual(ArchiveListLayoutBuilder.gridColumns(forContainerWidth: 0), 1)
        XCTAssertEqual(ArchiveListLayoutBuilder.gridColumns(forContainerWidth: 100), 1)
        XCTAssertEqual(ArchiveListLayoutBuilder.gridColumns(forContainerWidth: 390), 2)
        XCTAssertEqual(ArchiveListLayoutBuilder.gridColumns(forContainerWidth: 834), 4)
        XCTAssertEqual(ArchiveListLayoutBuilder.gridColumns(forContainerWidth: 1_194), 6)
    }

    func testCellSizeUsesCoverAspectRatioAndHorizontalSpacing() {
        let phoneSize = ArchiveListLayoutBuilder.cellSize(forContainerWidth: 390)
        let expectedPhoneWidth: CGFloat = (390.0 - 24.0 - 12.0) / 2.0
        XCTAssertEqual(phoneSize.width, expectedPhoneWidth, accuracy: 0.001)
        XCTAssertEqual(
            phoneSize.height,
            expectedPhoneWidth / ArchiveGridMetrics.coverAspectRatio + 4.0,
            accuracy: 0.001
        )

        let tabletSize = ArchiveListLayoutBuilder.cellSize(forContainerWidth: 834)
        let expectedTabletWidth: CGFloat = (834.0 - 24.0 - 36.0) / 4.0
        XCTAssertEqual(tabletSize.width, expectedTabletWidth, accuracy: 0.001)
        XCTAssertEqual(
            tabletSize.height,
            expectedTabletWidth / ArchiveGridMetrics.coverAspectRatio + 4.0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testMakeCollectionViewLayoutBuildsSectionWithExpectedInsetsAndFooter() {
        for width in [CGFloat(390), CGFloat(834)] {
            let layout = ArchiveListLayoutBuilder.makeCollectionViewLayout()
            let collectionView = UICollectionView(
                frame: CGRect(x: 0, y: 0, width: width, height: 844),
                collectionViewLayout: layout
            )
            collectionView.layoutIfNeeded()
            XCTAssertTrue(collectionView.collectionViewLayout === layout)

            let section = ArchiveListLayoutBuilder.makeArchiveGridSection(containerWidth: width)
            XCTAssertEqual(
                section.contentInsets,
                NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 20, trailing: 12)
            )
            XCTAssertEqual(section.interGroupSpacing, 12)
            XCTAssertEqual(section.boundarySupplementaryItems.count, 1)
            let footer = section.boundarySupplementaryItems.first
            XCTAssertEqual(footer?.elementKind, UICollectionView.elementKindSectionFooter)
            XCTAssertEqual(footer?.alignment, .bottom)
            XCTAssertEqual(footer?.layoutSize.heightDimension.dimension, 80)
        }
    }
}
