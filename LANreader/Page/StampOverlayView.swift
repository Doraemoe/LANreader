import UIKit

private final class StampCommentLabel: UILabel {
    private let contentInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let contentSize = CGSize(
            width: max(0, size.width - contentInsets.left - contentInsets.right),
            height: max(0, size.height - contentInsets.top - contentInsets.bottom)
        )
        let labelSize = super.sizeThatFits(contentSize)
        return CGSize(
            width: labelSize.width + contentInsets.left + contentInsets.right,
            height: labelSize.height + contentInsets.top + contentInsets.bottom
        )
    }
}

private final class StampMarkerButton: UIButton {
    private let minimumHitTargetSize = CGSize(width: 44, height: 44)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalInset = max(0, (minimumHitTargetSize.width - bounds.width) / 2)
        let verticalInset = max(0, (minimumHitTargetSize.height - bounds.height) / 2)
        return bounds.insetBy(dx: -horizontalInset, dy: -verticalInset).contains(point)
    }
}

final class StampOverlayView: UIView {
    private struct DisplayedStamp {
        let sourceIndex: Int
        let stamp: ArchiveStamp
        let position: ArchiveStampPosition
    }

    private let markerSize: CGFloat = 30
    private let calloutSpacing: CGFloat = 6
    private var stamps: [ArchiveStamp] = []
    private var displayedStamps: [DisplayedStamp] = []
    private var markerButtons: [StampMarkerButton] = []
    private var selectedSourceIndex: Int?
    private var imageSize: CGSize?
    private var pageMode: PageMode = .normal
    private var onEditStamp: ((ArchiveStamp) -> Void)?

    private let commentLabel: StampCommentLabel = {
        let label = StampCommentLabel()
        label.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        label.clipsToBounds = true
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(commentLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        stamps: [ArchiveStamp],
        pageMode: PageMode,
        imageSize: CGSize?,
        onEditStamp: @escaping (ArchiveStamp) -> Void
    ) {
        let contentsChanged = self.stamps != stamps || self.pageMode != pageMode
        self.stamps = stamps
        self.pageMode = pageMode
        self.imageSize = imageSize
        self.onEditStamp = onEditStamp
        if contentsChanged {
            rebuildMarkers()
        }
        setNeedsLayout()
    }

    func clear() {
        stamps = []
        displayedStamps = []
        imageSize = nil
        selectedSourceIndex = nil
        onEditStamp = nil
        markerButtons.forEach { $0.removeFromSuperview() }
        markerButtons = []
        commentLabel.isHidden = true
        commentLabel.text = nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        markerButtons.contains { button in
            !button.isHidden && button.point(inside: button.convert(point, from: self), with: event)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let imageSize,
              let imageRect = StampOverlayPositioning.aspectFitRect(imageSize: imageSize, in: bounds) else {
            markerButtons.forEach { $0.isHidden = true }
            commentLabel.isHidden = true
            return
        }

        for (index, displayedStamp) in displayedStamps.enumerated() {
            let button = markerButtons[index]
            let point = CGPoint(
                x: imageRect.minX
                    + imageRect.width * CGFloat(displayedStamp.position.horizontalPercentage / 100),
                y: imageRect.minY
                    + imageRect.height * CGFloat(displayedStamp.position.verticalPercentage / 100)
            )
            let origin = CGPoint(
                x: min(max(point.x - markerSize / 2, imageRect.minX), imageRect.maxX - markerSize),
                y: min(max(point.y - markerSize / 2, imageRect.minY), imageRect.maxY - markerSize)
            )
            button.frame = CGRect(origin: origin, size: CGSize(width: markerSize, height: markerSize))
            button.isHidden = false
        }

        layoutComment(in: imageRect)
    }

    private func rebuildMarkers() {
        markerButtons.forEach { $0.removeFromSuperview() }
        markerButtons = []
        displayedStamps = stamps.enumerated().compactMap { index, stamp in
            guard let position = stamp.normalizedPosition,
                  let displayedPosition = StampOverlayPositioning.displayedPosition(
                    position,
                    pageMode: pageMode
                  ) else {
                return nil
            }
            return DisplayedStamp(sourceIndex: index, stamp: stamp, position: displayedPosition)
        }

        if !displayedStamps.contains(where: { $0.sourceIndex == selectedSourceIndex }) {
            selectedSourceIndex = nil
        }

        for displayedStamp in displayedStamps {
            let button = StampMarkerButton(type: .system)
            button.setImage(UIImage(systemName: "seal.fill"), for: .normal)
            button.tintColor = .white
            button.backgroundColor = .systemOrange
            button.layer.cornerRadius = markerSize / 2
            button.layer.cornerCurve = .continuous
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.3
            button.layer.shadowRadius = 2
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.accessibilityLabel = displayedStamp.stamp.content
            button.addAction(
                UIAction { [weak self] _ in
                    self?.toggleComment(for: displayedStamp.sourceIndex)
                },
                for: .touchUpInside
            )
            button.tag = displayedStamp.sourceIndex
            button.addGestureRecognizer(
                UILongPressGestureRecognizer(target: self, action: #selector(handleStampLongPress(_:)))
            )
            addSubview(button)
            markerButtons.append(button)
        }
        bringSubviewToFront(commentLabel)
    }

    @objc private func handleStampLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? UIButton,
              let displayedStamp = displayedStamps.first(where: { $0.sourceIndex == button.tag }) else {
            return
        }
        onEditStamp?(displayedStamp.stamp)
    }

    private func toggleComment(for sourceIndex: Int) {
        selectedSourceIndex = selectedSourceIndex == sourceIndex ? nil : sourceIndex
        setNeedsLayout()
    }

    private func layoutComment(in imageRect: CGRect) {
        guard let selectedSourceIndex,
              let selectedIndex = displayedStamps.firstIndex(where: { $0.sourceIndex == selectedSourceIndex }),
              displayedStamps.indices.contains(selectedIndex),
              markerButtons.indices.contains(selectedIndex) else {
            commentLabel.isHidden = true
            commentLabel.text = nil
            return
        }

        let content = displayedStamps[selectedIndex].stamp.content
        guard !content.isEmpty else {
            commentLabel.isHidden = true
            commentLabel.text = nil
            return
        }

        commentLabel.text = content
        let maxWidth = min(280, imageRect.width)
        let fittedSize = commentLabel.sizeThatFits(
            CGSize(width: maxWidth, height: max(imageRect.height, 1))
        )
        let calloutSize = CGSize(
            width: min(fittedSize.width, maxWidth),
            height: min(fittedSize.height, imageRect.height)
        )
        let markerFrame = markerButtons[selectedIndex].frame
        let proposedY = markerFrame.maxY + calloutSpacing
        let verticalOrigin = proposedY + calloutSize.height <= imageRect.maxY
            ? proposedY
            : max(imageRect.minY, markerFrame.minY - calloutSpacing - calloutSize.height)
        let horizontalOrigin = min(
            max(markerFrame.midX - calloutSize.width / 2, imageRect.minX),
            imageRect.maxX - calloutSize.width
        )
        commentLabel.frame = CGRect(
            origin: CGPoint(x: horizontalOrigin, y: verticalOrigin),
            size: calloutSize
        )
        commentLabel.isHidden = false
    }
}
