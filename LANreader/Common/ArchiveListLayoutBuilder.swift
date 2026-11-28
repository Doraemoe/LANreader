import UIKit

enum ArchiveListLayoutBuilder {
    static let sideInset: CGFloat = 12.0
    static let interItemSpacing: CGFloat = 12.0
    static let minimumColumnWidth: CGFloat = 172.0
    static let footerHeight: CGFloat = 80.0

    static func gridColumns(forContainerWidth containerWidth: CGFloat) -> Int {
        let contentWidth = max(containerWidth - sideInset * 2, 1)
        return max(Int(contentWidth / minimumColumnWidth), 1)
    }

    static func cellSize(forContainerWidth containerWidth: CGFloat) -> CGSize {
        let contentWidth = max(containerWidth - sideInset * 2, 1)
        let columns = gridColumns(forContainerWidth: containerWidth)
        let totalSpacing = CGFloat(columns - 1) * interItemSpacing
        let cellWidth = (contentWidth - totalSpacing) / CGFloat(columns)
        let cellHeight = cellWidth / ArchiveGridMetrics.coverAspectRatio + 4.0
        return CGSize(width: cellWidth, height: cellHeight)
    }

    @MainActor
    static func makeCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, layoutEnvironment -> NSCollectionLayoutSection? in
            makeArchiveGridSection(layoutEnvironment: layoutEnvironment)
        }
    }

    @MainActor
    static func makeArchiveGridSection(
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        makeArchiveGridSection(containerWidth: layoutEnvironment.container.effectiveContentSize.width)
    }

    @MainActor
    static func makeArchiveGridSection(containerWidth: CGFloat) -> NSCollectionLayoutSection {
        let columns = gridColumns(forContainerWidth: containerWidth)
        let size = cellSize(forContainerWidth: containerWidth)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = makeArchiveGridGroup(
            item: item,
            columns: columns,
            cellHeight: size.height,
            interItemSpacing: interItemSpacing
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: sideInset,
            bottom: 20,
            trailing: sideInset
        )
        section.interGroupSpacing = interItemSpacing
        section.boundarySupplementaryItems = [makeArchiveGridFooter()]
        return section
    }

    @MainActor
    private static func makeArchiveGridGroup(
        item: NSCollectionLayoutItem,
        columns: Int,
        cellHeight: CGFloat,
        interItemSpacing: CGFloat
    ) -> NSCollectionLayoutGroup {
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(cellHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(interItemSpacing)
        return group
    }

    @MainActor
    private static func makeArchiveGridFooter() -> NSCollectionLayoutBoundarySupplementaryItem {
        let footerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(footerHeight)
        )
        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: footerSize,
            elementKind: UICollectionView.elementKindSectionFooter,
            alignment: .bottom
        )
    }
}
