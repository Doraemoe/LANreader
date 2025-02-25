import Combine
import ComposableArchitecture
import SwiftUI
import UIKit
import Logging

class UIPageCell: UICollectionViewCell {
    static let reuseIdentifier = "UIPageCell"

    var store: StoreOf<PageFeature>?

    private let logger = Logger(label: "UIPageCell")

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.minimumZoomScale = 1.0
        view.maximumZoomScale = 3.0
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .default)
        view.progressTintColor = .label
        return view
    }()

    private let progressViewLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .natural
        label.textColor = .label
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupImageView() {
        contentView.addSubview(scrollView)
        scrollView.addSubview(imageView)
        contentView.addSubview(progressView)
        contentView.addSubview(progressViewLabel)

        scrollView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressViewLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            progressView.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(
                equalTo: contentView.widthAnchor, multiplier: 0.9),

            progressViewLabel.leadingAnchor.constraint(
                equalTo: progressView.leadingAnchor),
            progressViewLabel.topAnchor.constraint(
                equalTo: progressView.bottomAnchor, constant: 8)
        ])
    }

    func configure(with store: StoreOf<PageFeature>) {
        self.store = store
        imageView.image = nil
        progressView.progress = 0
        progressView.isHidden = true
        progressViewLabel.isHidden = true
        scrollView.zoomScale = 1.0
        setupObserve(store: store)
    }

    func setupObserve(store: StoreOf<PageFeature>) {
        observe { [weak self] in
            guard let self else { return }

            if store.pageMode == .loading {
                imageView.isHidden = true
                progressView.isHidden = false
                progressViewLabel.isHidden = false
                progressView.progress = Float(store.progress)
                progressViewLabel.text = String(
                    format: "%.2f%%", store.progress * 100)
            } else {
                imageView.isHidden = false
                progressView.isHidden = true
                progressViewLabel.isHidden = true
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
                if let uiImage = UIImage(
                    contentsOfFile: contentPath?.path(percentEncoded: false)
                        ?? "") {
                    imageView.image = uiImage
                } else {
                    imageView.image = UIImage(systemName: "rectangle.slash")
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        progressView.progress = 0
        progressView.isHidden = true
        scrollView.zoomScale = 1.0
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        if let image = imageView.image {
            let width = layoutAttributes.frame.width
            let height = width * (image.size.height / image.size.width)
            attributes.frame.size.height = height
        }
        return attributes
    }
}

extension UIPageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
