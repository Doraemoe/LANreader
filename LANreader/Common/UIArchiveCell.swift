import UIKit
import ComposableArchitecture
import SwiftUI

class UIArchiveCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with store: StoreOf<GridFeature>) {
        contentConfiguration = UIHostingConfiguration {
            ArchiveGridV2(store: store)
        }
        .margins(.all, 0)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.92 : 1.0
            }
        }
    }
}
