import UIKit
import ComposableArchitecture
import SwiftUI

class UIArchiveCell: UICollectionViewCell {
    private var hostingController: UIHostingController<ArchiveGridV2>?

    func configure(with store: StoreOf<GridFeature>) {
        hostingController?.view.isHidden = false
        if hostingController == nil {
            let hostingController = UIHostingController(rootView: ArchiveGridV2(store: store))
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            self.hostingController = hostingController
        } else {
            hostingController?.rootView = ArchiveGridV2(store: store)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.view.isHidden = true
    }
}
