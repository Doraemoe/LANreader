import UIKit
import ComposableArchitecture
import Combine
import SwiftUI

class UIPageCell: UICollectionViewCell {
    private var hostingController: UIHostingController<PageImageV2>?

    private var cancellables: Set<AnyCancellable> = []

    private var cellSize: CGSize = .zero

    func configure(with store: StoreOf<PageFeature>, size: CGSize) {
        if hostingController == nil {
            let hostingController = UIHostingController(rootView: PageImageV2(store: store, geometrySize: size))
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
            hostingController?.rootView = PageImageV2(store: store, geometrySize: size)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.cellSize = .zero
    }

    func load(callback: () -> Void) async {
        if hostingController?.rootView.store.pageMode == .loading {
            print("load image")
            await hostingController?.rootView.store.send(.load(false)).finish()
            callback()
        }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        guard let hostingController = hostingController else {
            return attributes
        }

        let store = hostingController.rootView.store
        let targetWidth = layoutAttributes.size.width

        if store.readDirection != ReadDirection.upDown.rawValue || store.pageMode == .loading {
            attributes.size = hostingController.rootView.geometrySize
        } else {
            if self.cellSize != .zero {
                print("cheap")
                attributes.size = self.cellSize
            } else {
                print("expensive")
                let contentPath = {
                    switch store.pageMode {
                    case .left:
                        return store.pathLeft
                    case .right:
                        return store.pathRight
                    default:
                        return store.path
                    }
                }()
                if let uiImage = UIImage(contentsOfFile: contentPath?.path(percentEncoded: false) ?? "") {
                    let height = hostingController.rootView.geometrySize.width * uiImage.size.height / uiImage.size.width
                    attributes.size = CGSize(width: targetWidth, height: height)
                } else {
                    attributes.size = CGSize(width: targetWidth, height: hostingController.rootView.geometrySize.height)
                }
                self.cellSize = attributes.size
            }
        }
        return attributes
    }
}
