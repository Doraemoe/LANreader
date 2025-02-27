import UIKit
import ComposableArchitecture
import SwiftUI

class UIArchiveCell: UICollectionViewCell {
    private var hostingController: UIHostingController<ArchiveGridV2>?

    func configure(with store: StoreOf<GridFeature>) {
        hostingController = nil
        let hostingController = UIHostingController(rootView: ArchiveGridV2(store: store))
        contentView.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)

        ])
        self.hostingController = hostingController
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }
}
