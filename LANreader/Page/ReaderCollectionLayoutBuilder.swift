import UIKit

enum ReaderCollectionItem: Hashable {
    case spreadPlaceholder
    case page(String)
}

enum ReaderCollectionLayoutBuilder {
    @MainActor
    static func makeLayout(
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        onVisibleItemsInvalidated: @escaping @MainActor () -> Void
    ) -> UICollectionViewLayout {
        guard readDirection != .upDown else {
            return makeVerticalLayout()
        }
        return makeHorizontalLayout(
            doublePageLayout: doublePageLayout,
            onVisibleItemsInvalidated: onVisibleItemsInvalidated
        )
    }

    /// Vertical reading uses explicit per-item heights derived from each page's aspect ratio, so a
    /// page never has to resize itself once its image finishes loading.
    @MainActor
    static func makeVerticalLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        return layout
    }

    @MainActor
    static func makeHorizontalLayout(
        doublePageLayout: Bool,
        onVisibleItemsInvalidated: @escaping @MainActor () -> Void
    ) -> UICollectionViewCompositionalLayout {
        let heightDimension = NSCollectionLayoutDimension.fractionalHeight(1)
        let widthDimension = doublePageLayout
            ? NSCollectionLayoutDimension.fractionalWidth(0.5)
            : NSCollectionLayoutDimension.fractionalWidth(1)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: widthDimension,
            heightDimension: heightDimension
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: heightDimension
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: doublePageLayout ? 2 : 1
        )

        let section = NSCollectionLayoutSection(group: group)
        section.visibleItemsInvalidationHandler = { _, _, _ in
            onVisibleItemsInvalidated()
        }

        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }

    static func collectionItems(
        pageIds: [String],
        readDirection: ReadDirection,
        doublePageLayout: Bool,
        spreadPairingOffset: Int
    ) -> [ReaderCollectionItem] {
        var items = pageIds.map { ReaderCollectionItem.page($0) }
        if readDirection != .upDown && doublePageLayout && spreadPairingOffset == 1 {
            items.insert(.spreadPlaceholder, at: 0)
        }
        return items
    }

    /// For double page layout treat a pair of items as one visual page; return left item index path.
    static func startOfGroupIndexPath(
        for indexPath: IndexPath,
        readDirection: ReadDirection,
        doublePageLayout: Bool
    ) -> IndexPath {
        guard readDirection != .upDown, doublePageLayout else { return indexPath }
        let row = indexPath.row % 2 == 0 ? indexPath.row : indexPath.row - 1
        return IndexPath(row: row, section: indexPath.section)
    }

    static func scrollPosition(for source: ReaderNavigationSource) -> UICollectionView.ScrollPosition {
        switch source {
        case .initialRestore, .slider:
            return .centeredHorizontally
        case .chapter, .tap, .keyboard, .autoPage, .layoutChange:
            return .left
        }
    }
}
